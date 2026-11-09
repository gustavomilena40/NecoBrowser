program CoreTests;

{ Testes do núcleo (src\core). Console, sem framework: imprime cada verificação
  e sai com o número de falhas como código de saída (0 = tudo passou). }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  Neco.Core.Url in '..\src\core\Neco.Core.Url.pas',
  Neco.Core.Files in '..\src\core\Neco.Core.Files.pas',
  Neco.Core.Blocklist in '..\src\core\Neco.Core.Blocklist.pas',
  Neco.Core.Bookmarks in '..\src\core\Neco.Core.Bookmarks.pas',
  Neco.Core.History in '..\src\core\Neco.Core.History.pas',
  Neco.Core.Settings in '..\src\core\Neco.Core.Settings.pas';

var
  Falhas: Integer = 0;
  Total: Integer = 0;

procedure Check(ACond: Boolean; const ANome: string);
begin
  Inc(Total);
  if ACond then
    Writeln('  ok    ', ANome)
  else
  begin
    Inc(Falhas);
    Writeln('  FALHA ', ANome);
  end;
end;

procedure CheckEq(const AObtido, AEsperado, ANome: string);
begin
  Check(AObtido = AEsperado, ANome + ' -> "' + AObtido + '"' +
    IfThen(AObtido <> AEsperado, ' (esperado "' + AEsperado + '")', ''));
end;

procedure TestarUrl;
const
  D = seDuckDuckGo;
begin
  Writeln('URL vs busca');
  CheckEq(NecoInputToUrl('example.com', D), 'https://example.com', 'dominio sem esquema');
  CheckEq(NecoInputToUrl('  g1.globo.com  ', D), 'https://g1.globo.com', 'espacos nas pontas');
  CheckEq(NecoInputToUrl('https://example.com/a?b=1', D), 'https://example.com/a?b=1', 'com esquema');
  CheckEq(NecoInputToUrl('HTTP://Example.com', D), 'HTTP://Example.com', 'esquema maiusculo');
  CheckEq(NecoInputToUrl('localhost:8080/x', D), 'http://localhost:8080/x', 'localhost com porta');
  CheckEq(NecoInputToUrl('192.168.0.10', D), 'http://192.168.0.10', 'IPv4');
  CheckEq(NecoInputToUrl('about:blank', D), 'about:blank', 'about:');
  CheckEq(NecoInputToUrl('clima são paulo', D),
    'https://duckduckgo.com/?q=clima+s%C3%A3o+paulo', 'busca com acento');
  CheckEq(NecoInputToUrl('clima são paulo', seGoogle),
    'https://www.google.com/search?q=clima+s%C3%A3o+paulo', 'busca no Google');
  CheckEq(NecoInputToUrl('delphi', D), 'https://duckduckgo.com/?q=delphi', 'palavra sozinha');
  CheckEq(NecoInputToUrl('1.5', D), 'https://duckduckgo.com/?q=1.5', 'numero decimal');
  CheckEq(NecoInputToUrl('c++ & c#', D), 'https://duckduckgo.com/?q=c%2B%2B+%26+c%23', 'simbolos');
  CheckEq(NecoInputToUrl('versão.final', D), 'https://versão.final', 'dominio com acento (IDN)');
  CheckEq(NecoInputToUrl('', D), '', 'vazio');

  Writeln('Host');
  CheckEq(NecoExtractHost('https://User:Pw@Ads.Example.COM:8443/x?y#z'), 'ads.example.com', 'host completo');
  CheckEq(NecoExtractHost('https://example.com.'), 'example.com', 'ponto final');
  CheckEq(NecoExtractHost('http://[::1]:80/'), '::1', 'IPv6');
  CheckEq(NecoExtractHost('example.com/path'), 'example.com', 'sem esquema');
  CheckEq(NecoExtractHost(''), '', 'vazio');
end;

procedure TestarBlocklist;
var
  B: TNecoBlocklist;
  Arq: string;
begin
  Writeln('Blocklist');
  B := TNecoBlocklist.Create;
  try
    B.AddLine('# comentario');
    B.AddLine('127.0.0.1 localhost');
    B.AddLine('0.0.0.0 0.0.0.0');
    B.AddLine('0.0.0.0 doubleclick.net   # anuncios');
    B.AddLine('0.0.0.0 Ads.Exemplo.com.br tracker.exemplo.com.br');
    B.AddLine('somente-dominio.org');
    B.AddLine('1.2.3.4 redirecionado.com');
    Check(B.Count = 4, 'conta 4 hosts (ignora localhost, 0.0.0.0 e redirecionamento): ' + B.Count.ToString);
    Check(B.IsBlocked('doubleclick.net'), 'host exato');
    Check(B.IsBlocked('ad.g.doubleclick.net'), 'subdominio (dominio-pai na lista)');
    Check(B.IsBlocked('ads.exemplo.com.br'), 'maiusculas na lista');
    Check(not B.IsBlocked('exemplo.com.br'), 'pai nao bloqueia so por ter filho na lista');
    Check(not B.IsBlocked('notdoubleclick.net'), 'sufixo sem ponto nao conta');
    Check(not B.IsBlocked('localhost'), 'localhost nunca');
    Check(not B.IsBlocked('redirecionado.com'), 'IP real e redirecionamento');
    Check(B.IsBlocked('somente-dominio.org'), 'lista de dominios simples');
    Check(not B.IsBlocked(''), 'host vazio');
    Check(B.IsUrlBlocked('https://x.tracker.exemplo.com.br:443/pixel.gif?a=1'), 'URL completa');

    Arq := TPath.Combine(TPath.GetTempPath, 'neco-hosts-' + TGUID.NewGuid.ToString + '.txt');
    TFile.WriteAllText(Arq, '0.0.0.0 a.com'#10'0.0.0.0 b.com'#13#10'# x'#13#10, TEncoding.UTF8);
    try
      Check(B.LoadFromFile(Arq) = 2, 'LoadFromFile substitui a lista');
      Check(not B.IsBlocked('doubleclick.net') and B.IsBlocked('b.com'), 'conteudo apos carga');
    finally
      TFile.Delete(Arq);
    end;
    Check(B.LoadFromFile('Z:\nao\existe.txt') = 0, 'arquivo inexistente');
  finally
    B.Free;
  end;
end;

procedure TestarBookmarks(const APasta: string);
var
  A, B: TNecoBookmarks;
  Arq: string;
begin
  Writeln('Favoritos');
  Arq := TPath.Combine(APasta, 'bookmarks.json');
  A := TNecoBookmarks.Create;
  B := TNecoBookmarks.Create;
  try
    A.Add('Exemplo', 'https://example.com/');
    A.Add('Notícias "g1"', 'https://g1.globo.com/');
    A.Add('Exemplo novo', 'https://example.com/');
    Check(A.Count = 2, 'URL repetida nao duplica');
    CheckEq(A[0].Title, 'Exemplo novo', 'repetida atualiza o titulo');
    Check(A.Toggle('X', 'https://x.com/') and A.Contains('https://x.com/'), 'toggle liga');
    Check(not A.Toggle('X', 'https://x.com/') and not A.Contains('https://x.com/'), 'toggle desliga');

    A.SaveToFile(Arq);
    Check(TFile.Exists(Arq) and not TFile.Exists(Arq + '.tmp'), 'gravacao atomica sem sobra');
    B.LoadFromFile(Arq);
    Check(B.Count = 2, 'ida e volta: quantidade');
    CheckEq(B[1].Title, 'Notícias "g1"', 'ida e volta: acento e aspas');
    CheckEq(B[1].Url, 'https://g1.globo.com/', 'ida e volta: url');
    Check(Abs(B[1].Added - A[1].Added) < 1 / 86400, 'ida e volta: data');

    Check(not B.FromJson('{lixo'), 'JSON invalido devolve False');
    Check(B.Count = 0, 'JSON invalido deixa vazio');
  finally
    A.Free;
    B.Free;
  end;
end;

procedure TestarHistory(const APasta: string);
var
  H, H2: TNecoHistory;
  Arq: string;
  I: Integer;
begin
  Writeln('Historico');
  Arq := TPath.Combine(APasta, 'history.json');
  H := TNecoHistory.Create(3);
  H2 := TNecoHistory.Create(3);
  try
    H.Add('about:blank', '');
    Check(H.Count = 0, 'about:blank nao entra');
    H.Add('https://a.com/', 'A');
    H.Add('https://a.com/', '');
    Check((H.Count = 1) and (H[0].Title = 'A'), 'mesma URL seguida nao duplica');
    for I := 1 to 5 do
      H.Add('https://p' + I.ToString + '.com/', '');
    Check(H.Count = 3, 'limite de entradas');
    CheckEq(H[0].Url, 'https://p3.com/', 'descarta as mais antigas');
    H.UpdateTitle('https://p5.com/', 'Cinco');
    H.SaveToFile(Arq);
    Check(not H.Dirty, 'gravou e limpou o dirty');
    H2.LoadFromFile(Arq);
    Check((H2.Count = 3) and (H2[2].Title = 'Cinco'), 'ida e volta');
  finally
    H.Free;
    H2.Free;
  end;
end;

procedure TestarSettings(const APasta: string);
var
  S, S2: TNecoSettings;
begin
  Writeln('Configuracoes');
  S := TNecoSettings.Create(APasta);
  S2 := TNecoSettings.Create(APasta);
  try
    Check((S.SearchEngine = seGoogle) and (S.Theme = ntDark) and S.BlockerEnabled and
      (S.HomeUrl = 'https://www.google.com/'), 'padroes (Google)');
    Check(NecoSearchEngineFromId('') = seGoogle, 'motor ausente no JSON vira Google');
    Check(NecoSearchEngineFromId('duckduckgo') = seDuckDuckGo, 'duckduckgo continua aceito');
    S.SearchEngine := seDuckDuckGo;
    S.Theme := ntLight;
    S.BlockerEnabled := False;
    S.Save;
    S2.Load;
    Check((S2.SearchEngine = seDuckDuckGo) and (S2.Theme = ntLight) and not S2.BlockerEnabled, 'ida e volta');
  finally
    S.Free;
    S2.Free;
  end;
  S := TNecoSettings.Create;
  try
    Check(S.DataDir.EndsWith('NecoBrowser') and S.WebDataDir.EndsWith('NecoBrowser'),
      'pastas padrao: ' + S.DataDir + ' | ' + S.WebDataDir);
  finally
    S.Free;
  end;
end;

var
  Pasta: string;
begin
  ReportMemoryLeaksOnShutdown := False;
  Pasta := TPath.Combine(TPath.GetTempPath, 'NecoCoreTests-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Pasta);
  try
    try
      TestarUrl;
      TestarBlocklist;
      TestarBookmarks(Pasta);
      TestarHistory(Pasta);
      TestarSettings(Pasta);
    except
      on E: Exception do
      begin
        Inc(Falhas);
        Writeln('EXCECAO ', E.ClassName, ': ', E.Message);
      end;
    end;
  finally
    TDirectory.Delete(Pasta, True);
  end;
  Writeln;
  Writeln(Format('%d verificacoes, %d falhas', [Total, Falhas]));
  ExitCode := Falhas;
end.
