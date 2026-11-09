# Ajudante de teste do NecoBrowser. Pasta de trabalho: %TEMP%\NecoBuild.
# ATENÇÃO: 'teclas' e 'tela' trazem a janela para a frente; o que o usuário digitar nesse
# momento cai no app. Combine com o usuário antes de usar.
#   neco.ps1 abrir <pasta_build>      -> fecha instâncias, abre o exe, ajusta a 1200x760
#   neco.ps1 fechar                   -> fecha pela janela (encerramento limpo)
#   neco.ps1 tela <arquivo.png>       -> captura a área cliente pela TELA (o WebView2 não sai no PrintWindow)
#   neco.ps1 teclas <sendkeys>        -> manda teclas para a janela em primeiro plano
#   neco.ps1 mem                      -> memória do processo principal e dos filhos msedgewebview2
param([string]$acao, [string]$a1)
$S = Join-Path $env:TEMP 'NecoBuild'
$ui = 'C:\Users\user02\.agent-bridge\skills\delphi-fmx-visual\ui.ps1'
$env:FMX_JANELA = 'FMTFormMain'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class N {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct PT { public int X, Y; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref PT p);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
}
'@
function Janela { [N]::FindWindow('FMTFormMain', [NullString]::Value) }
function Frente { $h = Janela; [N]::keybd_event(0x12,0,0,[UIntPtr]::Zero); [N]::keybd_event(0x12,0,2,[UIntPtr]::Zero); [void][N]::SetForegroundWindow($h); Start-Sleep -Milliseconds 300; $h }

switch ($acao) {
  'abrir' {
    Get-Process NecoBrowser -ErrorAction SilentlyContinue | ForEach-Object { [void]$_.CloseMainWindow() }
    Start-Sleep -Seconds 2
    $p = Start-Process (Join-Path $a1 'NecoBrowser.exe') -PassThru
    Start-Sleep -Seconds 4
    powershell -NoProfile -ExecutionPolicy Bypass -File $ui ajustar 1200 760
    "PID=$($p.Id)"
  }
  'fechar' {
    $p = Get-Process NecoBrowser -ErrorAction SilentlyContinue
    if ($p) { [void]$p.CloseMainWindow(); Start-Sleep -Seconds 4; $p.Refresh(); "encerrou=$($p.HasExited) codigo=$(if ($p.HasExited) { $p.ExitCode })" } else { 'nenhum processo' }
  }
  'tela' {
    $h = Frente; Start-Sleep -Milliseconds 400
    $cr = New-Object N+RECT; [void][N]::GetClientRect($h, [ref]$cr)
    $pt = New-Object N+PT; [void][N]::ClientToScreen($h, [ref]$pt)
    $bmp = New-Object System.Drawing.Bitmap $cr.R, $cr.B
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($pt.X, $pt.Y, 0, 0, $bmp.Size)
    $bmp.Save($a1, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
    "ok $a1 ($($cr.R)x$($cr.B))"
  }
  'teclas' {
    [void](Frente); [System.Windows.Forms.SendKeys]::SendWait($a1); Start-Sleep -Milliseconds 300; 'ok'
  }
  'mem' {
    $p = Get-Process NecoBrowser -ErrorAction SilentlyContinue
    if (-not $p) { 'nenhum processo'; break }
    $p.Refresh()
    $filhos = Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" | Where-Object { $_.CommandLine -like '*NecoBrowser*' }
    $ws = ($filhos | ForEach-Object { (Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue).WorkingSet64 } | Measure-Object -Sum).Sum
    "app: WS={0:N1} MB Private={1:N1} MB Handles={2} | webview2: {3} processos, WS={4:N1} MB" -f ($p.WorkingSet64/1MB), ($p.PrivateMemorySize64/1MB), $p.HandleCount, @($filhos).Count, ($ws/1MB)
  }
}
