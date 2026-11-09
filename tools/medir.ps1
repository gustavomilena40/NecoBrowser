# medir.ps1 <pasta_build> <url> <rodadas> <etiqueta>
# Abre o exe com a URL (NECO_TRACE ligado), espera o "nav fim" e fecha. Imprime uma linha por rodada.
param([string]$pasta, [string]$url, [int]$n = 3, [string]$tag = '')
$S = Join-Path $env:TEMP 'NecoBuild'
for ($i = 1; $i -le $n; $i++) {
  $tr = "$S\trace-$tag-$i.txt"
  if (Test-Path $tr) { Remove-Item $tr }
  $env:NECO_TRACE = $tr
  $p = Start-Process (Join-Path $pasta 'NecoBrowser.exe') -ArgumentList $url -PassThru
  $fim = $null
  for ($t = 0; $t -lt 300; $t++) {
    Start-Sleep -Milliseconds 100
    if (Test-Path $tr) { $fim = Select-String -Path $tr -Pattern 'nav fim' | Select-Object -First 1; if ($fim) { break } }
  }
  Start-Sleep -Milliseconds 800
  [void]$p.CloseMainWindow(); [void]$p.WaitForExit(8000)
  if (-not $p.HasExited) { $p.Kill() }
  $l = Get-Content $tr
  function T($pat) { $x = $l | Where-Object { $_ -match $pat } | Select-Object -First 1; if ($x) { [double]($x -split "`t")[0] } else { -1 } }
  $nav = ($l | Where-Object { $_ -match 'nav fim' } | Select-Object -First 1) -replace '^[\d.]+\t', ''
  "{0} #{1}: form={2:N0} amb_pedido={3:N0} amb_pronto={4:N0} ctrl_pronto={5:N0} nav_inicio={6:N0} nav_fim={7:N0} | {8}" -f `
    $tag, $i, (T 'form criando'), (T 'ambiente pedido'), (T 'ambiente pronto'), (T 'controller pronto'), (T 'nav inicio'), (T 'nav fim'), $nav
  Start-Sleep -Seconds 2
}
Remove-Item Env:\NECO_TRACE
