unit Neco.UI.App;

{ O que é do navegador inteiro, não de uma janela: configurações, favoritos, histórico,
  lista de bloqueio, abas fechadas, atualizador, extensão de bloqueio, medidor de memória,
  trava de instância e o ciclo de vida do motor.

  Um objeto só (NecoApp), criado no .dpr antes da primeira janela. Cada janela se registra
  (INecoWindow) e recebe os avisos do que mudou. A última janela a fechar encerra o app:
  grava os dados, fecha o motor e aplica a atualização baixada. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, FMX.Types,
  Neco.Core.Settings, Neco.Core.Blocklist, Neco.Core.Bookmarks, Neco.Core.History,
  Neco.Core.Updater, Neco.Core.AdExtension, Neco.Engine.Intf, Neco.UI.Settings;

type
  /// O que a janela faz quando algo do app muda. Implementada pela TFormMain. Sem contagem
  /// de referência: o TComponent não conta, então a lista não segura a janela.
  INecoWindow = interface
    ['{6B449A2F-3E39-4151-A1E6-E01AEFF90B49}']
    /// Uma configuração mudou (nesta ou em outra janela). O app já aplicou a parte dele e
    /// já gravou; a janela só atualiza a tela.
    procedure AppSettingsChanged(AChange: TNecoSettingsChange);
    procedure AppBookmarksChanged;
    /// Só os ícones guardados dos favoritos mudaram (a lista é a mesma).
    procedure AppFaviconsChanged;
    procedure AppHistoryChanged;
    /// O estado do atualizador mudou. ANew: acabou de baixar uma versão nova.
    procedure AppUpdateChanged(ANew: Boolean);
    procedure AppMemoryReport(const AReport: TNecoMemoryReport);
    /// Minimizada: com todas assim, o medidor não mede.
    function AppIsMinimized: Boolean;
  end;

  TNecoApp = class
  private
    FSettings: TNecoSettings;
    FBlocklist: TNecoBlocklist;
    FBookmarks: TNecoBookmarks;
    FHistory: TNecoHistory;
    FClosed: TList<string>;
    FWindows: TList<INecoWindow>;
    FSessionOwner: Boolean;
    FShuttingDown: Boolean;
    // atualização automática (só no processo dono da sessão; nos outros FUpdater = nil)
    FUpdater: TNecoUpdater;
    FUpdateTimer: TTimer;
    FUpdateVersion: string;
    FRestartForUpdate: Boolean;
    // extensão de bloqueio (uBlock Origin Lite): baixada só pelo processo dono da sessão
    FAdExt: TNecoAdExtension;
    FAdTimer: TTimer;
    FAdFolder: string;
    // medidor de memória: uma medição para o app todo, repassada às janelas
    FMemTimer: TTimer;
    FMemAskedAt: Cardinal; // 0 = nenhuma medição em curso
    procedure LoadData;
    procedure LoadBlocklist;
    procedure SaveData;
    procedure BookmarksChanged(Sender: TObject);
    procedure StartUpdater;
    procedure UpdateTick(Sender: TObject);
    procedure UpdateReady(const AVersion: string);
    procedure FinishUpdate;
    procedure StartAdExtension;
    procedure ApplyAdExtension;
    procedure AdTick(Sender: TObject);
    procedure AdDownloaded(const AFolder: string);
    procedure AdInstalled(const AFolder: string);
    procedure MemoryTick(Sender: TObject);
    procedure NotifySettings(AChange: TNecoSettingsChange);
    procedure EndShutdown;
  public
    /// Carrega os dados, pega a trava de instância e prepara o motor (antes da 1ª janela).
    constructor Create;
    destructor Destroy; override;

    // janelas
    procedure RegisterWindow(const AWindow: INecoWindow);
    function IsLastWindow(const AWindow: INecoWindow): Boolean;
    /// A última janela começou a fechar: para timers e downloads do app antes de ela fechar
    /// os motores das abas.
    procedure BeginShutdown;
    /// Tira a janela da lista (os motores dela já fechados). Se era a última, encerra o app.
    procedure UnregisterWindow(const AWindow: INecoWindow);

    // configurações (o painel grava direto em Settings e avisa por SettingsChanged)
    procedure SettingsChanged(AChange: TNecoSettingsChange);
    procedure SetTheme(ATheme: TNecoTheme);
    procedure SetBlocker(AOn: Boolean);
    procedure SetBookmarkBarShown(AShow: Boolean);
    procedure SaveSettings;
    function BlockerOn: Boolean;
    function FaviconDir: string;

    // histórico, favoritos e abas fechadas
    procedure HistoryChanged;
    procedure ClearHistory;
    /// Um ícone de favorito foi gravado no disco: as janelas refazem barra e painel.
    procedure FaviconsChanged;
    procedure AddClosedTab(const AUrl: string);
    /// A aba fechada mais recente ('' = nenhuma); sai da lista.
    function TakeClosedTab: string;

    // atualização
    /// "Reiniciar para atualizar": a última janela a fechar troca o exe e abre o novo.
    procedure RequestRestartForUpdate;
    function UpdateInfoText: string;
    property UpdateVersion: string read FUpdateVersion;

    property Settings: TNecoSettings read FSettings;
    property Blocklist: TNecoBlocklist read FBlocklist;
    property Bookmarks: TNecoBookmarks read FBookmarks;
    property History: TNecoHistory read FHistory;
    /// Primeiro processo com este perfil: só ele grava e restaura a sessão.
    property SessionOwner: Boolean read FSessionOwner;
    property ShuttingDown: Boolean read FShuttingDown;
  end;

var
  NecoApp: TNecoApp;

implementation

uses
  System.IOUtils, System.ZLib, System.Types,
  Neco.Core.Trace, Neco.Engine.Factory, Neco.UI.Theme, Neco.UI.Neco, Neco.UI.Frame,
  Neco.UI.DefaultBrowser;

// Lista de bloqueio comprimida (tools\neco_embutidos.py): o exe funciona sem arquivos ao lado.
{$R NecoData.res}

const
  CClosedMax = 25;

{ TNecoApp }

constructor TNecoApp.Create;
var
  Cfg: TNecoEngineConfig;
begin
  inherited Create;
  FWindows := TList<INecoWindow>.Create;
  FClosed := TList<string>.Create;
  LoadData;
  // Reinício depois de atualizar: o processo antigo ainda está saindo; espera ele soltar
  // a trava para este ser o dono e reabrir as abas.
  if FindCmdLineSwitch('apos-atualizar', ['-'], True) then
    FSessionOwner := NecoAcquireInstanceLock(FSettings.DataDir, 15000)
  else
    FSessionOwner := NecoAcquireInstanceLock(FSettings.DataDir);
  NecoSetTheme(FSettings.Theme);
  NecoSetShown(FSettings.NecoShown);

  Cfg.WebDataDir := FSettings.WebDataDir;
  Cfg.DownloadsDir := FSettings.DownloadsDir;
  Cfg.Language := 'pt-BR';
  Cfg.BackgroundColor := Palette.Window;
  NecoEngineSetup(Cfg);

  FBookmarks.OnChange := BookmarksChanged;
  FMemTimer := TTimer.Create(nil);
  FMemTimer.Interval := 2000;
  FMemTimer.OnTimer := MemoryTick;
  StartUpdater;
  StartAdExtension;
  // Pasta do exe mudou desde que virou navegador padrão: os links voltam a achar o exe.
  NecoFixBrowserRegistration;
end;

destructor TNecoApp.Destroy;
begin
  // Normalmente a última janela já encerrou tudo (EndShutdown). Sobra o caso de o app
  // terminar sem janela (falha na criação do form). Os dois passos são idempotentes.
  BeginShutdown;
  EndShutdown;
  FreeAndNil(FWindows);
  inherited;
end;

procedure TNecoApp.LoadData;
begin
  // NECO_DADOS=<pasta>: perfil separado (testes sem tocar nos dados do usuário).
  FSettings := TNecoSettings.Create(System.SysUtils.GetEnvironmentVariable('NECO_DADOS'));
  FSettings.Load;
  FBlocklist := TNecoBlocklist.Create;
  LoadBlocklist;
  FBookmarks := TNecoBookmarks.Create;
  FBookmarks.LoadFromFile(FSettings.BookmarksFile);
  FHistory := TNecoHistory.Create;
  FHistory.LoadFromFile(FSettings.HistoryFile);
end;

procedure TNecoApp.LoadBlocklist;
var
  Arq: string;
  RS: TResourceStream;
  Z: TZDecompressionStream;
begin
  // A do lado do exe ganha (dá para atualizar sem recompilar); senão, a embutida.
  Arq := TPath.Combine(ExtractFilePath(ParamStr(0)), 'blocklist-hosts.txt');
  try
    if FileExists(Arq) then
      FBlocklist.LoadFromFile(Arq)
    else
    begin
      Arq := 'embutida';
      RS := TResourceStream.Create(HInstance, 'NECO_BLOCKLIST', RT_RCDATA);
      try
        Z := TZDecompressionStream.Create(RS);
        try
          FBlocklist.LoadFromStream(Z);
        finally
          Z.Free;
        end;
      finally
        RS.Free;
      end;
    end;
  except
    // Sem lista o navegador funciona, só não bloqueia.
    FBlocklist.Clear;
  end;
  NecoTrace(Format('lista de bloqueio: %d hosts (%s)', [FBlocklist.Count, Arq]));
end;

procedure TNecoApp.SaveData;
begin
  try
    FSettings.Save;
    FBookmarks.SaveToFile(FSettings.BookmarksFile);
    FHistory.SaveToFile(FSettings.HistoryFile);
  except
    // Falha de disco ao fechar não pode impedir o app de fechar.
  end;
end;

{ Janelas }

procedure TNecoApp.RegisterWindow(const AWindow: INecoWindow);
begin
  if not FWindows.Contains(AWindow) then
    FWindows.Add(AWindow);
  FMemTimer.Enabled := True;
end;

function TNecoApp.IsLastWindow(const AWindow: INecoWindow): Boolean;
begin
  Result := (FWindows.Count = 1) and (FWindows[0] = AWindow);
end;

procedure TNecoApp.BeginShutdown;
begin
  if FShuttingDown then
    Exit;
  FShuttingDown := True;
  FMemTimer.Enabled := False;
  if FUpdateTimer <> nil then
    FUpdateTimer.Enabled := False;
  if FAdTimer <> nil then
    FAdTimer.Enabled := False;
  // Para o download da extensão antes de fechar o motor (a resposta não chega mais).
  if FAdExt <> nil then
    FAdExt.Shutdown;
  FBookmarks.OnChange := nil;
end;

procedure TNecoApp.UnregisterWindow(const AWindow: INecoWindow);
begin
  FWindows.Remove(AWindow);
  if (FWindows.Count = 0) and FShuttingDown then
    EndShutdown;
end;

procedure TNecoApp.EndShutdown;
begin
  if FSettings = nil then
    Exit; // já encerrado
  SaveData;
  // Ordem: os motores das abas já fecharam (com as janelas ainda vivas); agora o ambiente.
  NecoEngineShutdown;
  FreeAndNil(FAdExt);
  // Com tudo gravado e os motores fechados: troca o exe (e reabre, se foi o pedido).
  FinishUpdate;
  FreeAndNil(FUpdateTimer);
  FreeAndNil(FAdTimer);
  FreeAndNil(FMemTimer);
  FreeAndNil(FClosed);
  FreeAndNil(FHistory);
  FreeAndNil(FBookmarks);
  FreeAndNil(FBlocklist);
  FreeAndNil(FSettings);
end;

{ Configurações }

function TNecoApp.BlockerOn: Boolean;
begin
  Result := (FSettings <> nil) and FSettings.BlockerEnabled;
end;

function TNecoApp.FaviconDir: string;
begin
  Result := TPath.Combine(FSettings.DataDir, 'favicons');
end;

procedure TNecoApp.SaveSettings;
begin
  try
    FSettings.Save;
  except
    // Sem disco agora: o SaveData do fechamento tenta de novo.
  end;
end;

procedure TNecoApp.NotifySettings(AChange: TNecoSettingsChange);
var
  W: INecoWindow;
begin
  for W in FWindows.ToArray do
    W.AppSettingsChanged(AChange);
end;

procedure TNecoApp.SettingsChanged(AChange: TNecoSettingsChange);
begin
  // O painel já gravou a escolha em Settings; aqui ela passa a valer no app todo.
  case AChange of
    scTheme:
      NecoSetTheme(FSettings.Theme);
    scBlocker:
      ApplyAdExtension;
    scNeco:
      NecoSetShown(FSettings.NecoShown);
    scAutoUpdate:
      if FUpdateTimer <> nil then
      begin
        // Ligou: procura daqui a pouco, sem esperar a próxima abertura.
        FUpdateTimer.Interval := 2000;
        FUpdateTimer.Enabled := FSettings.AutoUpdate;
      end;
  end;
  SaveSettings;
  NotifySettings(AChange);
end;

procedure TNecoApp.SetTheme(ATheme: TNecoTheme);
begin
  FSettings.Theme := ATheme;
  SettingsChanged(scTheme);
end;

procedure TNecoApp.SetBlocker(AOn: Boolean);
begin
  FSettings.BlockerEnabled := AOn;
  SettingsChanged(scBlocker);
end;

procedure TNecoApp.SetBookmarkBarShown(AShow: Boolean);
begin
  FSettings.ShowBookmarkBar := AShow;
  SettingsChanged(scBookmarkBar);
end;

{ Favoritos, histórico e abas fechadas }

procedure TNecoApp.BookmarksChanged(Sender: TObject);
var
  W: INecoWindow;
begin
  // Quem muda a lista nunca é um clique numa linha do painel (as janelas adiam).
  for W in FWindows.ToArray do
    W.AppBookmarksChanged;
  try
    FBookmarks.SaveToFile(FSettings.BookmarksFile);
  except
    // Sem disco agora: o SaveData do fechamento tenta de novo.
  end;
end;

procedure TNecoApp.FaviconsChanged;
var
  W: INecoWindow;
begin
  for W in FWindows.ToArray do
    W.AppFaviconsChanged;
end;

procedure TNecoApp.HistoryChanged;
var
  W: INecoWindow;
begin
  for W in FWindows.ToArray do
    W.AppHistoryChanged;
end;

procedure TNecoApp.ClearHistory;
begin
  FHistory.Clear;
  try
    FHistory.SaveToFile(FSettings.HistoryFile);
  except
  end;
  HistoryChanged;
end;

procedure TNecoApp.AddClosedTab(const AUrl: string);
begin
  if FShuttingDown or (AUrl = '') or SameText(AUrl, 'about:blank') then
    Exit;
  FClosed.Add(AUrl);
  if FClosed.Count > CClosedMax then
    FClosed.Delete(0);
end;

function TNecoApp.TakeClosedTab: string;
begin
  Result := '';
  if FClosed.Count = 0 then
    Exit;
  Result := FClosed.Last;
  FClosed.Delete(FClosed.Count - 1);
end;

{ Medidor de memória }

procedure TNecoApp.MemoryTick(Sender: TObject);
var
  W: INecoWindow;
  Visible: Boolean;
begin
  if FShuttingDown then
    Exit;
  // Com todas as janelas minimizadas ninguém vê o número.
  Visible := False;
  for W in FWindows do
    if not W.AppIsMinimized then
    begin
      Visible := True;
      Break;
    end;
  if not Visible then
    Exit;
  // Uma medição por vez; se a resposta se perdeu, tenta de novo depois de 10 s.
  if (FMemAskedAt <> 0) and (TThread.GetTickCount - FMemAskedAt < 10000) then
    Exit;
  FMemAskedAt := TThread.GetTickCount;
  if FMemAskedAt = 0 then
    FMemAskedAt := 1;
  NecoEngineQueryMemory(
    procedure(const AReport: TNecoMemoryReport)
    var
      Win: INecoWindow;
    begin
      FMemAskedAt := 0;
      if FShuttingDown then
        Exit;
      for Win in FWindows.ToArray do
        Win.AppMemoryReport(AReport);
    end);
end;

{ Atualização automática }

procedure TNecoApp.StartUpdater;
var
  P: string;
begin
  // Só o processo dono da sessão: dois processos não baixam nem trocam o exe juntos.
  if not FSessionOwner then
    Exit;
  FUpdater := TNecoUpdater.Create(FSettings.UpdateDir);
  NecoCleanupOldExe(ParamStr(0));
  // Baixada numa vez anterior e ainda não trocada (o navegador não fechou direito, ou a
  // pasta do exe não deixou): avisa de novo.
  P := FUpdater.PendingVersion;
  if (P <> '') and (NecoCompareVersions(P, NecoAppVersion) > 0) then
    FUpdateVersion := P;
  FUpdateTimer := TTimer.Create(nil);
  FUpdateTimer.Interval := 10000; // primeira consulta com a abertura já assentada
  FUpdateTimer.OnTimer := UpdateTick;
  FUpdateTimer.Enabled := FSettings.AutoUpdate;
end;

procedure TNecoApp.UpdateTick(Sender: TObject);
var
  W: INecoWindow;
begin
  FUpdateTimer.Interval := 6 * 60 * 60 * 1000; // depois, de 6 em 6 horas
  if FShuttingDown or not FSettings.AutoUpdate or FUpdater.Busy then
    Exit;
  FUpdater.Check(NecoAppVersion, UpdateReady);
  for W in FWindows.ToArray do
    W.AppUpdateChanged(False); // "procurando versão nova..."
end;

procedure TNecoApp.UpdateReady(const AVersion: string);
var
  Novo: Boolean;
  W: INecoWindow;
begin
  // Thread principal, ao fim de cada consulta ('' = nada novo ou falhou).
  if FShuttingDown then
    Exit;
  Novo := (AVersion <> '') and (AVersion <> FUpdateVersion);
  if Novo then
    FUpdateVersion := AVersion;
  for W in FWindows.ToArray do
    W.AppUpdateChanged(Novo);
end;

function ShortVersion(const AVersion: string): string;
begin
  // 0.2.0.0 -> 0.2.0
  Result := AVersion;
  if (Length(Result.Split(['.'])) = 4) and Result.EndsWith('.0') then
    SetLength(Result, Length(Result) - 2);
end;

function TNecoApp.UpdateInfoText: string;
begin
  Result := 'Versão ' + ShortVersion(NecoAppVersion);
  if FUpdater = nil then
    Result := Result + ' (outra janela cuida da atualização)'
  else if FUpdateVersion <> '' then
    Result := Result + ' · ' + FUpdateVersion + ' baixada: troca ao reiniciar'
  else if not FSettings.AutoUpdate then
    Result := Result + ' · desligado'
  else if FUpdater.Busy then
    Result := Result + ' · procurando versão nova...'
  else
    Result := Result + ' · procura versão nova ao abrir';
end;

procedure TNecoApp.RequestRestartForUpdate;
begin
  FRestartForUpdate := True;
end;

procedure TNecoApp.FinishUpdate;
var
  Exe: string;
begin
  if FUpdater = nil then
    Exit;
  Exe := ParamStr(0);
  // Para o download em curso antes de mexer nos arquivos.
  FUpdater.Shutdown;
  // Pediu para reiniciar, ou deixou para depois com a atualização ligada.
  if (FRestartForUpdate or FSettings.AutoUpdate) and (FUpdater.PendingVersion <> '') and
    (NecoCompareVersions(FUpdater.PendingVersion, NecoAppVersion) > 0) then
    FUpdater.Apply(Exe);
  FreeAndNil(FUpdater);
  // Reabre mesmo se a troca falhou: quem clicou em reiniciar espera a janela de volta.
  if FRestartForUpdate then
    NecoLaunch(Exe, '--apos-atualizar');
end;

{ Extensão de bloqueio

  A lista de hosts não pega o YouTube (anúncio e vídeo vêm dos mesmos endereços). O
  uBlock Origin Lite roda dentro da página e pega. Ele segue o mesmo botão do bloqueador. }

procedure TNecoApp.StartAdExtension;
begin
  // Só o processo dono da sessão baixa e troca versões: o perfil do motor é um só.
  if FSessionOwner then
  begin
    FAdExt := TNecoAdExtension.Create(TPath.Combine(FSettings.WebDataDir, 'extensoes'));
    FAdFolder := FAdExt.CurrentFolder;
    FAdTimer := TTimer.Create(nil);
    FAdTimer.Interval := 15000; // primeira consulta com a abertura já assentada
    FAdTimer.OnTimer := AdTick;
    FAdTimer.Enabled := True;
  end;
  ApplyAdExtension;
end;

procedure TNecoApp.ApplyAdExtension;
begin
  if FShuttingDown then
    Exit;
  if FAdExt = nil then
  begin
    NecoEngineSetAdExtension('', False, BlockerOn, nil);
    Exit;
  end;
  NecoEngineSetAdExtension(FAdFolder, True, BlockerOn, AdInstalled);
  // Ligou o bloqueador depois da primeira consulta e a extensão ainda não veio: procura já.
  if BlockerOn and (FAdFolder = '') and (FAdTimer.Interval > 15000) and not FAdExt.Busy then
    FAdExt.Check(AdDownloaded);
end;

procedure TNecoApp.AdTick(Sender: TObject);
begin
  FAdTimer.Interval := 24 * 60 * 60 * 1000; // depois, uma vez por dia
  if FShuttingDown or not BlockerOn or FAdExt.Busy then
    Exit;
  FAdExt.Check(AdDownloaded);
end;

procedure TNecoApp.AdDownloaded(const AFolder: string);
begin
  // Thread principal. '' = nada novo ou falhou.
  if FShuttingDown or (AFolder = '') then
    Exit;
  FAdFolder := AFolder;
  ApplyAdExtension;
end;

procedure TNecoApp.AdInstalled(const AFolder: string);
begin
  // O motor está usando AFolder: as outras versões já podem sair do disco.
  if not FShuttingDown and (FAdExt <> nil) then
    FAdExt.Cleanup(AFolder);
end;

end.
