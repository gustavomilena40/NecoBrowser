unit Neco.Engine.WebView2;

{ Motor do Windows: WebView2 por COM direto (Winapi.WebView2 + Winapi.EdgeUtils da RTL).

  Estrutura:
  - Um ambiente (ICoreWebView2Environment) para o app inteiro, criado na primeira aba.
  - Um controller por aba, filho da janela do form.
  - Cada aba tem um "sink" (TNecoWV2Sink) que implementa todos os handlers COM.
    O sink guarda um ponteiro cru para o motor; Close chama Detach, e qualquer
    evento que chegue depois é ignorado. Nenhuma exceção atravessa a fronteira COM.
  - Fechamento: remover eventos -> Controller.Close -> soltar as interfaces.
  - Downloads (TNecoWV2Download) vivem fora da aba e se desligam sozinhos ao terminar.
  - A janela do form é subclassada para avisar o WebView2 quando ela se move e para
    tirar o foco da página quando o clique cai na parte FMX.

  Todos os callbacks chegam na thread principal (o FMX já fez OleInitialize: STA). }

interface

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows, Neco.Engine.Intf;

type
  TNecoWV2Options = record
    UserDataFolder: string;
    /// Caminho completo da WebView2Loader.dll (normalmente ao lado do exe).
    LoaderPath: string;
    /// Pasta onde a cópia embutida da DLL é extraída quando a de LoaderPath falta ou
    /// é de outra arquitetura (exe de 32 bits com DLL de 64, ou o contrário).
    BinFolder: string;
    DownloadsFolder: string;
    /// Idioma das páginas e do Accept-Language (ex.: 'pt-BR').
    Language: string;
    /// Cor $AARRGGBB que o motor pinta antes da página (evita o clarão branco).
    BackgroundColor: Cardinal;
  end;

procedure NecoWV2Setup(const AOptions: TNecoWV2Options);
function NecoWV2CreateEngine(AParentWnd: HWND): INecoEngine;
/// Fecha todas as abas e downloads e solta o ambiente. Chamar ao fechar o app.
procedure NecoWV2Shutdown;
/// Mede a memória do exe e de todos os processos do WebView2. A resposta chega depois,
/// na thread principal (não chega se o app fechar antes).
procedure NecoWV2QueryMemory(const ACallback: TNecoMemoryCallback);

type
  TNecoWV2ExtInstalled = reference to procedure(const AFolder: string);

/// Extensão de bloqueio (uBlock Origin Lite), no perfil que todas as abas dividem.
/// AFolder: pasta descompactada da versão a usar ('' = ainda não baixada).
/// AManage: este processo instala, troca e remove versões (só a janela dona da sessão).
/// Sem AManage só liga ou desliga a que já está instalada.
/// AOnInstalled: thread principal, com a pasta que ficou instalada (para apagar as antigas).
procedure NecoWV2SetAdExtension(const AFolder: string; AManage, AEnabled: Boolean;
  const AOnInstalled: TNecoWV2ExtInstalled);
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}
uses
  System.SysUtils, System.Classes, System.Types, System.Generics.Collections, System.IOUtils,
  System.JSON, System.StrUtils,
  Winapi.Messages, Winapi.ActiveX, Winapi.CommCtrl, Winapi.WebView2, Winapi.EdgeUtils,
  Neco.Core.Files, Neco.Core.Trace;

// A WebView2Loader.dll da arquitetura deste exe vai embutida (tools\neco_embutidos.py):
// o exe roda sozinho em outra máquina, só com o WebView2 Runtime instalado.
{$IFDEF WIN64}
{$R NecoLoader64.res}
{$ELSE}
{$R NecoLoader32.res}
{$ENDIF}

type
  TNecoWV2Engine = class;

  TNecoWV2Sink = class(TInterfacedObject,
    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler,
    ICoreWebView2NavigationStartingEventHandler,
    ICoreWebView2NavigationCompletedEventHandler,
    ICoreWebView2SourceChangedEventHandler,
    ICoreWebView2HistoryChangedEventHandler,
    ICoreWebView2DocumentTitleChangedEventHandler,
    ICoreWebView2NewWindowRequestedEventHandler,
    ICoreWebView2WebResourceRequestedEventHandler,
    ICoreWebView2DownloadStartingEventHandler,
    ICoreWebView2ProcessFailedEventHandler,
    ICoreWebView2AcceleratorKeyPressedEventHandler,
    ICoreWebView2FocusChangedEventHandler,
    ICoreWebView2ContainsFullScreenElementChangedEventHandler,
    ICoreWebView2FaviconChangedEventHandler)
  private
    FEngine: TNecoWV2Engine;
    function ControllerCompleted(errorCode: HResult; const AController: ICoreWebView2Controller): HResult; stdcall;
    function NavigationStarting(const sender: ICoreWebView2;
      const args: ICoreWebView2NavigationStartingEventArgs): HResult; stdcall;
    function NavigationCompleted(const sender: ICoreWebView2;
      const args: ICoreWebView2NavigationCompletedEventArgs): HResult; stdcall;
    function SourceChanged(const sender: ICoreWebView2;
      const args: ICoreWebView2SourceChangedEventArgs): HResult; stdcall;
    function HistoryChanged(const sender: ICoreWebView2; const args: IUnknown): HResult; stdcall;
    function TitleChanged(const sender: ICoreWebView2; const args: IUnknown): HResult; stdcall;
    function NewWindowRequested(const sender: ICoreWebView2;
      const args: ICoreWebView2NewWindowRequestedEventArgs): HResult; stdcall;
    function WebResourceRequested(const sender: ICoreWebView2;
      const args: ICoreWebView2WebResourceRequestedEventArgs): HResult; stdcall;
    function DownloadStarting(const sender: ICoreWebView2;
      const args: ICoreWebView2DownloadStartingEventArgs): HResult; stdcall;
    function ProcessFailed(const sender: ICoreWebView2;
      const args: ICoreWebView2ProcessFailedEventArgs): HResult; stdcall;
    function AcceleratorKeyPressed(const sender: ICoreWebView2Controller;
      const args: ICoreWebView2AcceleratorKeyPressedEventArgs): HResult; stdcall;
    function GotFocus(const sender: ICoreWebView2Controller; const args: IUnknown): HResult; stdcall;
    function FullScreenChanged(const sender: ICoreWebView2; const args: IUnknown): HResult; stdcall;
    function FaviconChanged(const sender: ICoreWebView2; const args: IUnknown): HResult; stdcall;

    function ICoreWebView2CreateCoreWebView2ControllerCompletedHandler.Invoke = ControllerCompleted;
    function ICoreWebView2NavigationStartingEventHandler.Invoke = NavigationStarting;
    function ICoreWebView2NavigationCompletedEventHandler.Invoke = NavigationCompleted;
    function ICoreWebView2SourceChangedEventHandler.Invoke = SourceChanged;
    function ICoreWebView2HistoryChangedEventHandler.Invoke = HistoryChanged;
    function ICoreWebView2DocumentTitleChangedEventHandler.Invoke = TitleChanged;
    function ICoreWebView2NewWindowRequestedEventHandler.Invoke = NewWindowRequested;
    function ICoreWebView2WebResourceRequestedEventHandler.Invoke = WebResourceRequested;
    function ICoreWebView2DownloadStartingEventHandler.Invoke = DownloadStarting;
    function ICoreWebView2ProcessFailedEventHandler.Invoke = ProcessFailed;
    function ICoreWebView2AcceleratorKeyPressedEventHandler.Invoke = AcceleratorKeyPressed;
    function ICoreWebView2FocusChangedEventHandler.Invoke = GotFocus;
    function ICoreWebView2ContainsFullScreenElementChangedEventHandler.Invoke = FullScreenChanged;
    function ICoreWebView2FaviconChangedEventHandler.Invoke = FaviconChanged;
  public
    constructor Create(AEngine: TNecoWV2Engine);
    procedure Detach;
  end;

  TNecoWV2Engine = class(TNecoEngineBase, INecoEngine)
  private
    FParentWnd: HWND;
    FSink: TNecoWV2Sink;
    FSinkRef: IInterface;
    FController: ICoreWebView2Controller;
    FWebView: ICoreWebView2;
    FTokNavStart, FTokNavDone, FTokSource, FTokHistory, FTokTitle, FTokNewWindow,
    FTokResource, FTokDownload, FTokProcess, FTokAccel, FTokFocus, FTokFull, FTokFav: EventRegistrationToken;
    FHasFavToken: Boolean;
    FHasDownloadToken: Boolean;
    FPendingUrl: string;
    FBounds: TRect;
    FVisible: Boolean;
    FDark: Boolean;
    FAutofillForms: Boolean;
    FSavePasswords: Boolean;
    FReady: Boolean;
    FClosed: Boolean;
    FLoading: Boolean;
    /// A navegação em curso virou download (a falha dela não é erro de página).
    FNavDownload: Boolean;
    /// Id da navegação principal em curso. O aviso de fim de uma navegação já substituída
    /// (clique num link com outra carregando, redirecionamento por script) chega depois do
    /// início da nova: ele é ignorado, senão a página nova viraria página de erro.
    FNavId: UInt64;
    /// URL da navegação principal em curso: o bloqueador nunca barra este documento.
    FMainNavUrl: string;
    // diagnóstico (NECO_TRACE)
    FNavStartMs: Double;
    FResCount: Integer;
    FResBlocked: Integer;
    FResMs: Double;
    procedure StartController;
    procedure ControllerCreated(AError: HResult; const AController: ICoreWebView2Controller);
    procedure ApplyProfile;
    procedure ApplyBounds;
    procedure Fail(const AMessage: string);
    procedure FailLater(const AMessage: string);
  public
    constructor Create(AParentWnd: HWND);
    destructor Destroy; override;
    // INecoEngine
    procedure Navigate(const AUrl: string);
    procedure GoBack;
    procedure GoForward;
    procedure Reload;
    procedure Stop;
    function CanGoBack: Boolean;
    function CanGoForward: Boolean;
    function IsReady: Boolean;
    function IsLoading: Boolean;
    function GetUrl: string;
    function GetTitle: string;
    procedure SetBounds(const ARect: TRect);
    procedure SetVisible(AVisible: Boolean);
    procedure Focus;
    procedure Blur;
    procedure ExecuteScript(const AScript: string);
    procedure SetDarkMode(ADark: Boolean);
    procedure SetAutofill(AForms, APasswords: Boolean);
    procedure OpenTaskManager;
    procedure Close;
    procedure SetParentWindow(AWnd: NativeUInt);
  end;

  TNecoWV2Download = class(TInterfacedObject, INecoDownload,
    ICoreWebView2BytesReceivedChangedEventHandler, ICoreWebView2StateChangedEventHandler)
  private
    FOp: ICoreWebView2DownloadOperation;
    FTokBytes, FTokState: EventRegistrationToken;
    FAttached: Boolean;
    FUrl: string;
    FPath: string;
    FReceived: Int64;
    FTotal: Int64;
    FState: TNecoDownloadState;
    FOnChanged: TNotifyEvent;
    procedure Refresh;
    procedure Changed;
    function BytesChanged(const sender: ICoreWebView2DownloadOperation; const args: IUnknown): HResult; stdcall;
    function StateChanged(const sender: ICoreWebView2DownloadOperation; const args: IUnknown): HResult; stdcall;
    function ICoreWebView2BytesReceivedChangedEventHandler.Invoke = BytesChanged;
    function ICoreWebView2StateChangedEventHandler.Invoke = StateChanged;
  public
    constructor Create(const AOp: ICoreWebView2DownloadOperation; const APath: string);
    /// Remove os handlers do WebView2 (quebra o ciclo operação <-> objeto).
    procedure Detach;
    // INecoDownload
    function GetUrl: string;
    function GetFilePath: string;
    function GetReceived: Int64;
    function GetTotal: Int64;
    function GetState: TNecoDownloadState;
    function GetOnChanged: TNotifyEvent;
    procedure SetOnChanged(const AValue: TNotifyEvent);
    procedure Cancel;
  end;

  /// Uma leitura do ícone (GetFavicon é assíncrono). Segura o motor até responder.
  TNecoWV2FaviconReq = class(TInterfacedObject, ICoreWebView2GetFaviconCompletedHandler)
  private
    FEngine: TNecoWV2Engine;
    FKeep: IInterface;
    function Invoke(errorCode: HResult; const AStream: IStream): HResult; stdcall;
  public
    constructor Create(AEngine: TNecoWV2Engine);
  end;

  /// Uma medição de memória (GetProcessExtendedInfos é assíncrono).
  TNecoWV2MemoryReq = class(TInterfacedObject, ICoreWebView2GetProcessExtendedInfosCompletedHandler)
  private
    FCallback: TNecoMemoryCallback;
    function Invoke(errorCode: HResult; const AInfos: ICoreWebView2ProcessExtendedInfoCollection): HResult; stdcall;
  public
    constructor Create(const ACallback: TNecoMemoryCallback);
  end;

  TNecoWV2EnvHandler = class(TInterfacedObject, ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler)
  private
    function Invoke(errorCode: HResult; const AEnv: ICoreWebView2Environment): HResult; stdcall;
  end;

  /// As opções da RTL não têm a interface 6 (extensões); o loader pergunta por ela com
  /// QueryInterface, então basta a classe também implementá-la.
  TNecoWV2EnvOptions = class(TCoreWebView2EnvironmentOptions, ICoreWebView2EnvironmentOptions6)
  private
    FExtensions: Integer;
  public
    function Get_AreBrowserExtensionsEnabled(out value: Integer): HResult; stdcall;
    function Set_AreBrowserExtensionsEnabled(value: Integer): HResult; stdcall;
  end;

  TNecoWV2ExtList = class(TInterfacedObject, ICoreWebView2ProfileGetBrowserExtensionsCompletedHandler)
  private
    function Invoke(errorCode: HResult; const AList: ICoreWebView2BrowserExtensionList): HResult; stdcall;
  end;

  TNecoWV2ExtAdded = class(TInterfacedObject, ICoreWebView2ProfileAddBrowserExtensionCompletedHandler)
  private
    FFolder: string;
    function Invoke(errorCode: HResult; const AExt: ICoreWebView2BrowserExtension): HResult; stdcall;
  public
    constructor Create(const AFolder: string);
  end;

  /// Fim de Remove e de Enable: só registra no rastro.
  TNecoWV2ExtDone = class(TInterfacedObject, ICoreWebView2BrowserExtensionRemoveCompletedHandler,
    ICoreWebView2BrowserExtensionEnableCompletedHandler)
  private
    FWhat: string;
    function Invoke(errorCode: HResult): HResult; stdcall;
  public
    constructor Create(const AWhat: string);
  end;

  TEnvState = (esNone, esCreating, esReady, esFailed);

const
  CTargetBrowserVersion = '137.0.3296.44';
  CNoRuntime = 'O WebView2 Runtime da Microsoft não está instalado neste computador. ' +
    'Instale pelo site da Microsoft (procure "WebView2 Runtime") e abra o NecoBrowser de novo.';

var
  GOptions: TNecoWV2Options;
  GEnv: ICoreWebView2Environment;
  GEnvState: TEnvState = esNone;
  GEnvError: string;
  GPending: TList<TNecoWV2Engine>;
  GEngines: TList<TNecoWV2Engine>;
  GDownloads: TList<TNecoWV2Download>;
  GHooked: TList<HWND>;
  // Extensão de bloqueio. O perfil é um só para todas as abas: guarda o da primeira pronta.
  GExtEnvOn: Boolean = True;       // False se o ambiente teve de ser criado sem extensões
  GExtProfile: ICoreWebView2Profile7;
  GExtConfigured: Boolean;         // a UI já disse o que quer
  GExtFolder: string;
  GExtManage: Boolean;
  GExtEnabled: Boolean = True;
  GExtOnInstalled: TNecoWV2ExtInstalled;
  GExtBusy, GExtDirty: Boolean;

{ Utilitários }

/// Copia e libera uma string alocada pelo WebView2 (CoTaskMemAlloc).
function TakeStr(P: PWideChar): string;
begin
  Result := P;
  if P <> nil then
    CoTaskMemFree(P);
end;

function HrText(AHr: HResult): string;
begin
  Result := Format('0x%.8x', [Cardinal(AHr)]);
end;

function NavErrorOf(AStatus: COREWEBVIEW2_WEB_ERROR_STATUS): TNecoNavError;
begin
  case AStatus of
    COREWEBVIEW2_WEB_ERROR_STATUS_HOST_NAME_NOT_RESOLVED:
      Result := neNotFound;
    COREWEBVIEW2_WEB_ERROR_STATUS_DISCONNECTED:
      Result := neOffline;
    COREWEBVIEW2_WEB_ERROR_STATUS_TIMEOUT:
      Result := neTimeout;
    COREWEBVIEW2_WEB_ERROR_STATUS_SERVER_UNREACHABLE, COREWEBVIEW2_WEB_ERROR_STATUS_CANNOT_CONNECT,
    COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_RESET:
      Result := neRefused;
    COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_COMMON_NAME_IS_INCORRECT..
    COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_IS_INVALID:
      Result := neCertificate;
    // ERR_ABORTED do Chromium: a navigação foi trocada por outra (clique num link com a
    // página ainda carregando, redirecionamento por script, login). O Chrome não mostra erro.
    COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED, COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_ABORTED:
      Result := neCanceled;
  else
    Result := neOther;
  end;
end;

function NecoParentSubclass(hWnd: HWND; uMsg: UINT; wParam: WPARAM; lParam: LPARAM;
  uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): LRESULT; stdcall;
var
  E: TNecoWV2Engine;
begin
  case uMsg of
    WM_MOVE, WM_MOVING:
      if GEngines <> nil then
        for E in GEngines do
        if (E.FParentWnd = hWnd) and (E.FController <> nil) then
          E.FController.NotifyParentWindowPositionChanged;
    WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN:
      // O clique caiu na parte FMX (a página é outra janela): o teclado volta para o form.
      if GetFocus <> hWnd then
        Winapi.Windows.SetFocus(hWnd);
    WM_NCDESTROY:
      begin
        RemoveWindowSubclass(hWnd, @NecoParentSubclass, uIdSubclass);
        if GHooked <> nil then
          GHooked.Remove(hWnd);
      end;
  end;
  Result := DefSubclassProc(hWnd, uMsg, wParam, lParam);
end;

procedure HookParent(AWnd: HWND);
begin
  if (AWnd = 0) or GHooked.Contains(AWnd) then
    Exit;
  if SetWindowSubclass(AWnd, @NecoParentSubclass, 1, 0) then
    GHooked.Add(AWnd);
end;

/// Extrai a DLL embutida para AFolder (se ainda não estiver lá, do mesmo tamanho).
function ExtractEmbeddedLoader(const AFolder: string; out APath: string): Boolean;
var
  RS: TResourceStream;
  F: TFileStream;
  Tmp: string;
begin
  Result := False;
  APath := '';
  if (AFolder = '') or (FindResource(HInstance, 'NECO_WV2LOADER', RT_RCDATA) = 0) then
    Exit;
  try
    RS := TResourceStream.Create(HInstance, 'NECO_WV2LOADER', RT_RCDATA);
    try
      APath := TPath.Combine(AFolder, 'WebView2Loader.dll');
      if TFile.Exists(APath) and (TFile.GetSize(APath) = RS.Size) then
        Exit(True);
      ForceDirectories(AFolder);
      // Grava ao lado e troca de uma vez: outra instância pode estar lendo a antiga.
      Tmp := APath + '.' + IntToStr(GetCurrentProcessId) + '.tmp';
      F := TFileStream.Create(Tmp, fmCreate);
      try
        F.CopyFrom(RS, 0);
      finally
        F.Free;
      end;
      if MoveFileEx(PChar(Tmp), PChar(APath), MOVEFILE_REPLACE_EXISTING) then
        Result := True
      else
      begin
        System.SysUtils.DeleteFile(Tmp);
        Result := TFile.Exists(APath); // em uso por outra instância: serve
      end;
    finally
      RS.Free;
    end;
  except
    Result := False;
  end;
end;

/// Carrega a WebView2Loader.dll: primeiro a de LoaderPath; se faltar ou for de outra
/// arquitetura, a cópia embutida. Em caso de falha, deixa a causa em GEnvError.
function LoadLoader: Boolean;
var
  Err, Err2: Cardinal;
  P: string;
begin
  Err := ERROR_FILE_NOT_FOUND;
  if (GOptions.LoaderPath <> '') and FileExists(GOptions.LoaderPath) then
  begin
    SetWebView2Path(GOptions.LoaderPath);
    if CheckWebView2Loaded then
    begin
      NecoTrace('loader: ' + GOptions.LoaderPath);
      Exit(True);
    end;
    Err := GetLastError;
  end;
  if ExtractEmbeddedLoader(GOptions.BinFolder, P) then
  begin
    SetWebView2Path(P);
    if CheckWebView2Loaded then
    begin
      NecoTrace(Format('loader: embutido em %s (o do lado do exe deu erro %d)', [P, Err]));
      Exit(True);
    end;
    Err2 := GetLastError;
    GEnvError := Format('Não foi possível carregar a WebView2Loader.dll (erro %d; a cópia embutida ' +
      'deu erro %d).', [Err, Err2]);
    Exit(False);
  end;
  if Err = ERROR_BAD_EXE_FORMAT then
    GEnvError := 'A WebView2Loader.dll ao lado do executável é de outra arquitetura (32 x 64 bits). ' +
      'Use a da pasta redist\' + {$IFDEF WIN64}'Win64'{$ELSE}'Win32'{$ENDIF} + '.'
  else if Err = ERROR_FILE_NOT_FOUND then
    GEnvError := 'WebView2Loader.dll não encontrada ao lado do executável.'
  else
    GEnvError := Format('Não foi possível carregar a WebView2Loader.dll (erro %d).', [Err]);
  Result := False;
end;

procedure EnsureEnvironment;
var
  O: TNecoWV2EnvOptions;
  Opts: ICoreWebView2EnvironmentOptions;
  HR: HResult;
begin
  if GEnvState <> esNone then
    Exit;
  GEnvState := esCreating;
  if not LoadLoader then
  begin
    GEnvState := esFailed;
    Exit;
  end;
  O := TNecoWV2EnvOptions.Create;
  O.FExtensions := Ord(GExtEnvOn);
  Opts := O;
  // Vazia, o loader recusa com E_INVALIDARG. É a versão mínima do import da RTL do Delphi 13
  // (a mesma que o Vcl.Edge usa).
  Opts.Set_TargetCompatibleBrowserVersion(CTargetBrowserVersion);
  if GOptions.Language <> '' then
    Opts.Set_Language(PChar(GOptions.Language));
  if GOptions.UserDataFolder <> '' then
    ForceDirectories(GOptions.UserDataFolder);
  NecoTrace('ambiente pedido');
  HR := CreateCoreWebView2EnvironmentWithOptions(nil, PChar(GOptions.UserDataFolder), Opts,
    TNecoWV2EnvHandler.Create);
  if Failed(HR) then
  begin
    GEnvState := esFailed;
    if HR = HResult($80070002) then
      GEnvError := CNoRuntime
    else
      GEnvError := 'Falha ao iniciar o WebView2 (' + HrText(HR) + ').';
  end;
end;

{ TNecoWV2EnvHandler }

function TNecoWV2EnvHandler.Invoke(errorCode: HResult; const AEnv: ICoreWebView2Environment): HResult;
var
  Lista: TArray<TNecoWV2Engine>;
  E: TNecoWV2Engine;
  Keep: IInterface;
begin
  Result := S_OK;
  try
    // ERROR_INVALID_STATE: o motor já está aberto (outra janela, versão antiga) com opções
    // diferentes. Sem extensões ele abre; perde só o bloqueio do YouTube até reiniciar.
    if Failed(errorCode) and GExtEnvOn and (errorCode = HResult($8007139F)) then
    begin
      NecoTrace('ambiente: motor ja aberto sem extensoes; tentando sem elas');
      GExtEnvOn := False;
      GEnvState := esNone;
      EnsureEnvironment;
      if GEnvState <> esFailed then
        Exit; // a nova resposta chega por outro Invoke
    end;
    if Succeeded(errorCode) and (AEnv <> nil) then
    begin
      GEnv := AEnv;
      GEnvState := esReady;
      NecoTrace(Format('ambiente pronto (extensoes=%d)', [Ord(GExtEnvOn)]));
    end
    else
    begin
      GEnvState := esFailed;
      if errorCode = HResult($80070002) then
        GEnvError := CNoRuntime
      else
        GEnvError := 'Falha ao criar o ambiente WebView2 (' + HrText(errorCode) + ').';
    end;
    Lista := GPending.ToArray;
    GPending.Clear;
    for E in Lista do
    begin
      Keep := E;
      if GEnvState = esReady then
        E.StartController
      else
        E.Fail(GEnvError);
      Keep := nil;
    end;
  except
    // Nunca deixar exceção atravessar a fronteira COM.
  end;
end;

{ TNecoWV2EnvOptions }

function TNecoWV2EnvOptions.Get_AreBrowserExtensionsEnabled(out value: Integer): HResult;
begin
  value := FExtensions;
  Result := S_OK;
end;

function TNecoWV2EnvOptions.Set_AreBrowserExtensionsEnabled(value: Integer): HResult;
begin
  FExtensions := value;
  Result := S_OK;
end;

{ Extensão de bloqueio

  Ciclo (sempre na thread principal, uma rodada por vez): lista as extensões do perfil.
  A instalada por nós é reconhecida pelo id gravado em neco-extensao.json, ao lado dos
  dados do motor (o id de extensão descompactada depende da pasta, então muda a cada
  versão). Mesma pasta: só liga ou desliga. Pasta nova: remove a antiga e instala a nova. }

function ExtStateFile: string;
begin
  Result := TPath.Combine(GOptions.UserDataFolder, 'neco-extensao.json');
end;

procedure ExtLoadState(out AId, AFolder: string);
var
  O: TJSONObject;
begin
  AId := '';
  AFolder := '';
  O := NecoParseObject(NecoLoadText(ExtStateFile));
  if O = nil then
    Exit;
  try
    AId := NecoJsonStr(O, 'id', '');
    AFolder := NecoJsonStr(O, 'folder', '');
  finally
    O.Free;
  end;
end;

procedure ExtSaveState(const AId, AFolder: string);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  try
    O.AddPair('id', AId);
    O.AddPair('folder', AFolder);
    try
      NecoSaveTextAtomic(ExtStateFile, O.Format(2));
    except
      on E: Exception do
        NecoTrace('extensao: nao gravou o estado: ' + E.Message);
    end;
  finally
    O.Free;
  end;
end;

procedure ExtSync; forward;

procedure ExtFinish;
begin
  GExtBusy := False;
  if GExtDirty then
    ExtSync;
end;

procedure ExtSync;
begin
  if (GExtProfile = nil) or not GExtConfigured then
    Exit;
  if GExtBusy then
  begin
    GExtDirty := True; // a rodada em curso termina e faz outra com o pedido novo
    Exit;
  end;
  GExtBusy := True;
  GExtDirty := False;
  if Failed(GExtProfile.GetBrowserExtensions(TNecoWV2ExtList.Create)) then
    ExtFinish;
end;

procedure ExtApplyEnabled(const AExt: ICoreWebView2BrowserExtension);
var
  On: Integer;
begin
  if Failed(AExt.Get_IsEnabled(On)) then
    Exit;
  if (On <> 0) <> GExtEnabled then
    AExt.Enable(Ord(GExtEnabled), TNecoWV2ExtDone.Create(Format('enable=%d', [Ord(GExtEnabled)])));
end;

procedure ExtAttach(const AWebView: ICoreWebView2);
var
  W13: ICoreWebView2_13;
  P: ICoreWebView2Profile;
  P7: ICoreWebView2Profile7;
begin
  if (GExtProfile <> nil) or not GExtEnvOn then
    Exit;
  if Supports(AWebView, ICoreWebView2_13, W13) and Succeeded(W13.Get_Profile(P)) and
    Supports(P, ICoreWebView2Profile7, P7) then
  begin
    GExtProfile := P7;
    ExtSync;
  end
  else
  begin
    NecoTrace('extensao: runtime sem suporte a extensoes');
    GExtEnvOn := False; // não tenta de novo a cada aba
  end;
end;

procedure NecoWV2SetAdExtension(const AFolder: string; AManage, AEnabled: Boolean;
  const AOnInstalled: TNecoWV2ExtInstalled);
begin
  GExtConfigured := True;
  GExtFolder := AFolder;
  GExtManage := AManage;
  GExtEnabled := AEnabled;
  GExtOnInstalled := AOnInstalled;
  ExtSync;
end;

{ TNecoWV2ExtList }

function TNecoWV2ExtList.Invoke(errorCode: HResult; const AList: ICoreWebView2BrowserExtensionList): HResult;
var
  SavedId, SavedFolder, Id, Name: string;
  N, I: Cardinal;
  E, Found: ICoreWebView2BrowserExtension;
  P: PWideChar;
begin
  Result := S_OK;
  try
    if GExtProfile = nil then
    begin
      GExtBusy := False; // fechando
      Exit;
    end;
    if Failed(errorCode) or (AList = nil) or Failed(AList.Get_Count(N)) then
    begin
      NecoTrace('extensao: lista falhou ' + HrText(errorCode));
      ExtFinish;
      Exit;
    end;
    ExtLoadState(SavedId, SavedFolder);
    Found := nil;
    if N > 0 then
      for I := 0 to N - 1 do
      begin
        E := nil;
        if Failed(AList.GetValueAtIndex(I, E)) or (E = nil) then
          Continue;
        P := nil;
        E.Get_id(P);
        Id := TakeStr(P);
        if (SavedId <> '') and SameText(Id, SavedId) then
          Found := E
        else if GExtManage then
        begin
          // Sobra de uma instalação que não chegou a gravar o estado: não fica duplicada.
          P := nil;
          E.Get_name(P);
          Name := TakeStr(P);
          if ContainsText(Name, 'uBlock') then
            E.Remove(TNecoWV2ExtDone.Create('sobra removida ' + Id));
        end;
      end;

    if (Found <> nil) and (not GExtManage or (GExtFolder = '') or SameText(SavedFolder, GExtFolder)) then
    begin
      ExtApplyEnabled(Found);
      if GExtManage and Assigned(GExtOnInstalled) then
        GExtOnInstalled(SavedFolder);
      ExtFinish;
      Exit;
    end;
    if not GExtManage or (GExtFolder = '') or
      not FileExists(TPath.Combine(GExtFolder, 'manifest.json')) then
    begin
      ExtFinish;
      Exit;
    end;
    if Found <> nil then
      Found.Remove(TNecoWV2ExtDone.Create('versao antiga removida ' + SavedFolder));
    NecoTrace('extensao: instalando ' + GExtFolder);
    if Failed(GExtProfile.AddBrowserExtension(PChar(GExtFolder), TNecoWV2ExtAdded.Create(GExtFolder))) then
      ExtFinish; // senão a rodada termina no TNecoWV2ExtAdded
  except
    on Ex: Exception do
    begin
      NecoTrace('extensao: erro na lista: ' + Ex.Message);
      GExtBusy := False;
    end;
  end;
end;

{ TNecoWV2ExtAdded }

constructor TNecoWV2ExtAdded.Create(const AFolder: string);
begin
  inherited Create;
  FFolder := AFolder;
end;

function TNecoWV2ExtAdded.Invoke(errorCode: HResult; const AExt: ICoreWebView2BrowserExtension): HResult;
var
  P: PWideChar;
  Id: string;
begin
  Result := S_OK;
  try
    if GExtProfile = nil then
    begin
      GExtBusy := False;
      Exit;
    end;
    if Succeeded(errorCode) and (AExt <> nil) then
    begin
      P := nil;
      AExt.Get_id(P);
      Id := TakeStr(P);
      ExtSaveState(Id, FFolder);
      NecoTrace('extensao: instalada ' + Id);
      ExtApplyEnabled(AExt);
      if Assigned(GExtOnInstalled) then
        GExtOnInstalled(FFolder);
    end
    else
      NecoTrace('extensao: instalacao falhou ' + HrText(errorCode));
    ExtFinish;
  except
    on Ex: Exception do
    begin
      NecoTrace('extensao: erro ao instalar: ' + Ex.Message);
      GExtBusy := False;
    end;
  end;
end;

{ TNecoWV2ExtDone }

constructor TNecoWV2ExtDone.Create(const AWhat: string);
begin
  inherited Create;
  FWhat := AWhat;
end;

function TNecoWV2ExtDone.Invoke(errorCode: HResult): HResult;
begin
  Result := S_OK;
  try
    NecoTrace(Format('extensao: %s (%s)', [FWhat, HrText(errorCode)]));
  except
    // fronteira COM
  end;
end;

{ TNecoWV2Sink }

constructor TNecoWV2Sink.Create(AEngine: TNecoWV2Engine);
begin
  inherited Create;
  FEngine := AEngine;
end;

procedure TNecoWV2Sink.Detach;
begin
  FEngine := nil;
end;

function TNecoWV2Sink.ControllerCompleted(errorCode: HResult; const AController: ICoreWebView2Controller): HResult;
var
  E: TNecoWV2Engine;
  Keep: IInterface;
begin
  Result := S_OK;
  E := FEngine;
  if E = nil then
  begin
    // A aba fechou antes de o motor ficar pronto.
    if AController <> nil then
      AController.Close;
    Exit;
  end;
  Keep := E;
  try
    E.ControllerCreated(errorCode, AController);
  except
    on X: Exception do
      E.Fail(X.Message);
  end;
end;

function TNecoWV2Sink.NavigationStarting(const sender: ICoreWebView2;
  const args: ICoreWebView2NavigationStartingEventArgs): HResult;
var
  E: TNecoWV2Engine;
  Keep: IInterface;
  P: PWideChar;
  Url: string;
  Cancel: Boolean;
  Id: UInt64;
begin
  Result := S_OK;
  E := FEngine;
  if E = nil then
    Exit;
  Keep := E;
  try
    if Succeeded(args.Get_uri(P)) then
      Url := TakeStr(P);
    E.FMainNavUrl := Url;
    E.FNavDownload := False;
    if Failed(args.Get_NavigationId(Id)) then
      Id := 0;
    E.FNavId := Id;
    E.FNavStartMs := NecoTraceMs;
    E.FResCount := 0;
    E.FResBlocked := 0;
    E.FResMs := 0;
    NecoTrace('nav inicio ' + Url);
    E.FLoading := True;
    Cancel := False;
    if Assigned(E.FOnNavigationStarting) then
      E.FOnNavigationStarting(E, Url, Cancel);
    if Cancel then
    begin
      args.Set_Cancel(1);
      E.FLoading := False;
    end;
  except
  end;
end;

function TNecoWV2Sink.NavigationCompleted(const sender: ICoreWebView2;
  const args: ICoreWebView2NavigationCompletedEventArgs): HResult;
var
  E: TNecoWV2Engine;
  Keep: IInterface;
  Ok: Integer;
  St: COREWEBVIEW2_WEB_ERROR_STATUS;
  Err: TNecoNavError;
  Id: UInt64;
begin
  Result := S_OK;
  E := FEngine;
  if E = nil then
    Exit;
  Keep := E;
  try
    if Succeeded(args.Get_NavigationId(Id)) and (Id <> E.FNavId) then
    begin
      NecoTrace(Format('nav fim ignorado (navegacao %d substituida pela %d)', [Id, E.FNavId]));
      Exit;
    end;
    E.FLoading := False;
    if Failed(args.Get_IsSuccess(Ok)) then
      Ok := 0;
    Err := neNone;
    if Ok = 0 then
    begin
      if Failed(args.Get_WebErrorStatus(St)) then
        St := COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
      if E.FNavDownload then
        Err := neCanceled
      else
        Err := NavErrorOf(St);
    end;
    if NecoTraceOn then
      NecoTrace(Format('nav fim ok=%d erro=%d duracao=%.0fms requisicoes_filtradas=%d bloqueadas=%d tempo_no_filtro=%.1fms',
        [Ok, Ord(Err), NecoTraceMs - E.FNavStartMs, E.FResCount, E.FResBlocked, E.FResMs]));
    if Assigned(E.FOnNavigationCompleted) then
      E.FOnNavigationCompleted(E, Ok <> 0, Err);
  except
  end;
end;

function TNecoWV2Sink.SourceChanged(const sender: ICoreWebView2;
  const args: ICoreWebView2SourceChangedEventArgs): HResult;
var
  E: TNecoWV2Engine;
  Keep: IInterface;
begin
  Result := S_OK;
  E := FEngine;
  if E = nil then
    Exit;
  Keep := E;
  try
    if Assigned(E.FOnUrlChanged) then
      E.FOnUrlChanged(E, E.GetUrl);
  except
  end;
end;

function TNecoWV2Sink.HistoryChanged(const sender: ICoreWebView2; const args: IUnknown): HResult;
var
  E: TNecoWV2Engine;
  Keep: IInterface;
begin
  Result := S_OK;
  E := FEngine;
  if E = nil then
    Exit;
  Keep := E;
  try
    if Assigned(E.FOnHistoryChanged) then
      E.FOnHistoryChanged(E);
  except
  end;
end;

function TNecoWV2Sink.TitleChanged(const sender: ICoreWebView2; const args: IUnknown): HResult;
var
  E: TNecoWV2Engine;
  Keep: IInterface;
begin
  Result := S_OK;
  E := FEngine;
  if E = nil then
    Exit;
  Keep := E;
  try
    if Assigned(E.FOnTitleChanged) then
      E.FOnTitleChanged(E);
  except
  end;
end;

function TNecoWV2Sink.NewWindowRequested(const sender: ICoreWebView2;
  const args: ICoreWebView2NewWindowRequestedEventArgs): HResult;
var
  E: TNecoWV2Engine;
  Keep: IInterface;
  P: PWideChar;
  Url: string;
begin
  Result := S_OK;
  E := FEngine;
  if E = nil then
    Exit;
  Keep := E;
  try
    if Succeeded(args.Get_uri(P)) then
      Url := TakeStr(P);
    // Pop-up e target=_blank nunca abrem janela própria: viram aba (ou a mesma aba).
    args.Set_Handled(1);
    if Url = '' then
      Exit;
    if Assigned(E.FOnNewWindowRequested) then
      E.FOnNewWindowRequested(E, Url)
    else
      E.Navigate(Url);
  except
  end;
end;

function TNecoWV2Sink.WebResourceRequested(const sender: ICoreWebView2;
  const args: ICoreWebView2WebResourceRequestedEventArgs): HResult;
var
  E: TNecoWV2Engine;
  Keep: IInterface;
  Req: ICoreWebView2WebResourceRequest;
  Resp: ICoreWebView2WebResourceResponse;
  Ctx: COREWEBVIEW2_WEB_RESOURCE_CONTEXT;
  P: PWideChar;
  Url: string;
  T0: Double;
begin
  Result := S_OK;
  E := FEngine;
  if (E = nil) or not Assigned(E.FRequestFilter) or (GEnv = nil) then
    Exit;
  Keep := E;
  T0 := NecoTraceMs;
  try
    try
      if Failed(args.Get_Request(Req)) or (Req = nil) or Failed(Req.Get_uri(P)) then
        Exit;
      Url := TakeStr(P);
      if Succeeded(args.Get_ResourceContext(Ctx)) and (Ctx = COREWEBVIEW2_WEB_RESOURCE_CONTEXT_DOCUMENT) and
        (Url = E.FMainNavUrl) then
        Exit; // a página principal que o usuário abriu nunca é bloqueada
      if E.FRequestFilter(Url) then
      begin
        Inc(E.FResBlocked);
        if Succeeded(GEnv.CreateWebResourceResponse(nil, 403, 'Blocked', '', Resp)) then
          args.Set_Response(Resp);
      end;
    finally
      Inc(E.FResCount);
      E.FResMs := E.FResMs + (NecoTraceMs - T0);
    end;
  except
  end;
end;

function TNecoWV2Sink.DownloadStarting(const sender: ICoreWebView2;
  const args: ICoreWebView2DownloadStartingEventArgs): HResult;
var
  E: TNecoWV2Engine;
  Keep: IInterface;
  Op: ICoreWebView2DownloadOperation;
  P: PWideChar;
  Path: string;
  D: INecoDownload;
begin
  Result := S_OK;
  E := FEngine;
  if E = nil then
    Exit;
  Keep := E;
  try
    if not Assigned(E.FOnDownloadStarting) then
      Exit; // sem painel: o WebView2 mostra a própria interface de download
    if Failed(args.Get_DownloadOperation(Op)) or (Op = nil) then
      Exit;
    if Succeeded(args.Get_ResultFilePath(P)) then
      Path := TakeStr(P);
    args.Set_Handled(1); // esconde o painel nativo do WebView2; o nosso assume
    if E.FLoading then
      E.FNavDownload := True;
    D := TNecoWV2Download.Create(Op, Path);
    E.FOnDownloadStarting(E, D);
  except
  end;
end;

function TNecoWV2Sink.ProcessFailed(const sender: ICoreWebView2;
  const args: ICoreWebView2ProcessFailedEventArgs): HResult;
var
  E: TNecoWV2Engine;
  Keep: IInterface;
  Kind: COREWEBVIEW2_PROCESS_FAILED_KIND;
begin
  Result := S_OK;
  E := FEngine;
  if E = nil then
    Exit;
  Keep := E;
  try
    if Failed(args.Get_ProcessFailedKind(Kind)) then
      Kind := 0;
    E.FLoading := False;
    E.Fail(Format('O processo da página parou (tipo %d). Recarregue a página.', [Integer(Kind)]));
  except
  end;
end;

function TNecoWV2Sink.AcceleratorKeyPressed(const sender: ICoreWebView2Controller;
  const args: ICoreWebView2AcceleratorKeyPressedEventArgs): HResult;
var
  E: TNecoWV2Engine;
  Keep: IInterface;
  Kind: COREWEBVIEW2_KEY_EVENT_KIND;
  VK: SYSUINT;
  Shift: TShiftState;
  Handled: Boolean;
begin
  Result := S_OK;
  E := FEngine;
  if (E = nil) or not Assigned(E.FOnAcceleratorKey) then
    Exit;
  Keep := E;
  try
    if Failed(args.Get_KeyEventKind(Kind)) then
      Exit;
    if (Kind <> COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN) and
      (Kind <> COREWEBVIEW2_KEY_EVENT_KIND_SYSTEM_KEY_DOWN) then
      Exit;
    if Failed(args.Get_VirtualKey(VK)) then
      Exit;
    Shift := [];
    if GetKeyState(VK_CONTROL) < 0 then
      Include(Shift, ssCtrl);
    if GetKeyState(VK_SHIFT) < 0 then
      Include(Shift, ssShift);
    if GetKeyState(VK_MENU) < 0 then
      Include(Shift, ssAlt);
    Handled := False;
    E.FOnAcceleratorKey(E, Word(VK), Shift, Handled);
    if Handled then
      args.Set_Handled(1);
  except
  end;
end;

function TNecoWV2Sink.GotFocus(const sender: ICoreWebView2Controller; const args: IUnknown): HResult;
var
  E: TNecoWV2Engine;
  Keep: IInterface;
begin
  Result := S_OK;
  E := FEngine;
  if E = nil then
    Exit;
  Keep := E;
  try
    if Assigned(E.FOnGotFocus) then
      E.FOnGotFocus(E);
  except
  end;
end;

function TNecoWV2Sink.FullScreenChanged(const sender: ICoreWebView2; const args: IUnknown): HResult;
var
  E: TNecoWV2Engine;
  Keep: IInterface;
  V: Integer;
begin
  Result := S_OK;
  E := FEngine;
  if (E = nil) or (E.FWebView = nil) then
    Exit;
  Keep := E;
  try
    if Failed(E.FWebView.Get_ContainsFullScreenElement(V)) then
      V := 0;
    if Assigned(E.FOnFullScreen) then
      E.FOnFullScreen(E, V <> 0);
  except
  end;
end;

function TNecoWV2Sink.FaviconChanged(const sender: ICoreWebView2; const args: IUnknown): HResult;
var
  E: TNecoWV2Engine;
  W15: ICoreWebView2_15;
begin
  Result := S_OK;
  E := FEngine;
  if (E = nil) or (E.FWebView = nil) or not Assigned(E.FOnFavicon) then
    Exit;
  try
    if Supports(E.FWebView, ICoreWebView2_15, W15) then
      W15.GetFavicon(COREWEBVIEW2_FAVICON_IMAGE_FORMAT_PNG, TNecoWV2FaviconReq.Create(E));
  except
  end;
end;

{ TNecoWV2FaviconReq }

constructor TNecoWV2FaviconReq.Create(AEngine: TNecoWV2Engine);
begin
  inherited Create;
  FEngine := AEngine;
  FKeep := AEngine;
end;

function TNecoWV2FaviconReq.Invoke(errorCode: HResult; const AStream: IStream): HResult;
var
  Data: TBytes;
  Buf: array[0..8191] of Byte;
  N: FixedUInt;
  Len: Integer;
begin
  Result := S_OK;
  try
    if not FEngine.FClosed and Succeeded(errorCode) and Assigned(FEngine.FOnFavicon) then
    begin
      Data := nil;
      Len := 0;
      // Ícone é pequeno; o teto evita ler sem fim um stream estranho.
      while (AStream <> nil) and (Len < 1024 * 1024) do
      begin
        N := 0;
        if Failed(AStream.Read(@Buf[0], SizeOf(Buf), @N)) or (N = 0) then
          Break;
        SetLength(Data, Len + Integer(N));
        System.Move(Buf[0], Data[Len], N);
        Inc(Len, N);
      end;
      // Vazio também é avisado: a página nova não tem ícone e a aba tira o da anterior.
      FEngine.FOnFavicon(FEngine, Data);
    end;
  except
  end;
  FKeep := nil;
end;

{ TNecoWV2Engine }

constructor TNecoWV2Engine.Create(AParentWnd: HWND);
begin
  inherited Create;
  FParentWnd := AParentWnd;
  FVisible := True;
  FDark := True;
  FAutofillForms := True;
  FSavePasswords := True;
  FSink := TNecoWV2Sink.Create(Self);
  FSinkRef := FSink;
  GEngines.Add(Self);
  HookParent(AParentWnd);
  EnsureEnvironment;
  case GEnvState of
    esReady:
      StartController;
    esCreating:
      GPending.Add(Self);
    esFailed:
      FailLater(GEnvError); // os eventos ainda não foram ligados: avisa depois
  end;
end;

destructor TNecoWV2Engine.Destroy;
begin
  Close;
  inherited;
end;

procedure TNecoWV2Engine.StartController;
var
  HR: HResult;
begin
  if FClosed or (GEnv = nil) then
    Exit;
  NecoTrace('controller pedido');
  HR := GEnv.CreateCoreWebView2Controller(FParentWnd, FSink);
  if Failed(HR) then
    FailLater('Falha ao criar a página (' + HrText(HR) + ').');
end;

procedure TNecoWV2Engine.ControllerCreated(AError: HResult; const AController: ICoreWebView2Controller);
var
  C2: ICoreWebView2Controller2;
  W4: ICoreWebView2_4;
  W15: ICoreWebView2_15;
  S: ICoreWebView2Settings;
  Cor: COREWEBVIEW2_COLOR;
  U: string;
begin
  if FClosed then
  begin
    if AController <> nil then
      AController.Close;
    Exit;
  end;
  if Failed(AError) or (AController = nil) then
  begin
    Fail('Falha ao criar a página (' + HrText(AError) + ').');
    Exit;
  end;
  NecoTrace('controller pronto');
  FController := AController;
  if Failed(FController.Get_CoreWebView2(FWebView)) or (FWebView = nil) then
  begin
    Fail('O WebView2 não devolveu a página.');
    Exit;
  end;

  if Supports(FController, ICoreWebView2Controller2, C2) then
  begin
    Cor.A := (GOptions.BackgroundColor shr 24) and $FF;
    Cor.R := (GOptions.BackgroundColor shr 16) and $FF;
    Cor.G := (GOptions.BackgroundColor shr 8) and $FF;
    Cor.B := GOptions.BackgroundColor and $FF;
    if Cor.A <> 0 then
      C2.Set_DefaultBackgroundColor(Cor);
  end;

  if Succeeded(FWebView.Get_Settings(S)) and (S <> nil) then
  begin
    S.Set_AreDevToolsEnabled(1);
    S.Set_IsZoomControlEnabled(1);
    S.Set_IsStatusBarEnabled(1);
  end;

  FWebView.add_NavigationStarting(FSink, FTokNavStart);
  FWebView.add_NavigationCompleted(FSink, FTokNavDone);
  FWebView.add_SourceChanged(FSink, FTokSource);
  FWebView.add_HistoryChanged(FSink, FTokHistory);
  FWebView.add_DocumentTitleChanged(FSink, FTokTitle);
  FWebView.add_NewWindowRequested(FSink, FTokNewWindow);
  FWebView.add_ProcessFailed(FSink, FTokProcess);
  FWebView.add_ContainsFullScreenElementChanged(FSink, FTokFull);
  if Supports(FWebView, ICoreWebView2_15, W15) then
    FHasFavToken := Succeeded(W15.add_FaviconChanged(FSink, FTokFav));
  FWebView.AddWebResourceRequestedFilter('*', COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
  FWebView.add_WebResourceRequested(FSink, FTokResource);
  if Supports(FWebView, ICoreWebView2_4, W4) then
    FHasDownloadToken := Succeeded(W4.add_DownloadStarting(FSink, FTokDownload));
  FController.add_AcceleratorKeyPressed(FSink, FTokAccel);
  FController.add_GotFocus(FSink, FTokFocus);

  ApplyProfile;
  ExtAttach(FWebView);
  ApplyBounds;
  FController.Set_IsVisible(Ord(FVisible));
  FReady := True;
  if Assigned(FOnReady) then
    FOnReady(Self);
  if FPendingUrl <> '' then
  begin
    U := FPendingUrl;
    FPendingUrl := '';
    Navigate(U);
  end;
end;

procedure TNecoWV2Engine.ApplyProfile;
var
  W13: ICoreWebView2_13;
  P: ICoreWebView2Profile;
  P6: ICoreWebView2Profile6;
  S: ICoreWebView2Settings;
  S4: ICoreWebView2Settings4;
begin
  if FWebView = nil then
    Exit;
  // Formulários e senhas: no perfil (vale para todas as abas) ou, em runtime antigo, por aba.
  if Supports(FWebView, ICoreWebView2_13, W13) and Succeeded(W13.Get_Profile(P)) and
    Supports(P, ICoreWebView2Profile6, P6) then
  begin
    P6.Set_IsGeneralAutofillEnabled(Ord(FAutofillForms));
    P6.Set_IsPasswordAutosaveEnabled(Ord(FSavePasswords));
    NecoTrace(Format('preenchimento (perfil): formularios=%d senhas=%d', [Ord(FAutofillForms), Ord(FSavePasswords)]));
  end
  else if Succeeded(FWebView.Get_Settings(S)) and Supports(S, ICoreWebView2Settings4, S4) then
  begin
    S4.Set_IsGeneralAutofillEnabled(Ord(FAutofillForms));
    S4.Set_IsPasswordAutosaveEnabled(Ord(FSavePasswords));
    NecoTrace(Format('preenchimento (aba): formularios=%d senhas=%d', [Ord(FAutofillForms), Ord(FSavePasswords)]));
  end;
  P := nil;
  if not Supports(FWebView, ICoreWebView2_13, W13) then
    Exit;
  if Failed(W13.Get_Profile(P)) or (P = nil) then
    Exit;
  if FDark then
    P.Set_PreferredColorScheme(COREWEBVIEW2_PREFERRED_COLOR_SCHEME_DARK)
  else
    P.Set_PreferredColorScheme(COREWEBVIEW2_PREFERRED_COLOR_SCHEME_LIGHT);
  if GOptions.DownloadsFolder <> '' then
    P.Set_DefaultDownloadFolderPath(PChar(GOptions.DownloadsFolder));
end;

procedure TNecoWV2Engine.ApplyBounds;
var
  R: tagRECT;
begin
  if FController = nil then
    Exit;
  R.Left := FBounds.Left;
  R.Top := FBounds.Top;
  R.right := FBounds.Right;
  R.bottom := FBounds.Bottom;
  FController.Set_Bounds(R);
end;

procedure TNecoWV2Engine.Fail(const AMessage: string);
begin
  if FClosed then
    Exit;
  if Assigned(FOnError) then
    FOnError(Self, AMessage);
end;

procedure TNecoWV2Engine.FailLater(const AMessage: string);
var
  Keep: INecoEngine;
begin
  Keep := Self;
  TThread.ForceQueue(nil,
    procedure
    begin
      TNecoWV2Engine(Keep as TObject).Fail(AMessage);
    end);
end;

procedure TNecoWV2Engine.Navigate(const AUrl: string);
var
  HR: HResult;
begin
  if FClosed or (AUrl = '') then
    Exit;
  if FWebView = nil then
  begin
    FPendingUrl := AUrl;
    Exit;
  end;
  HR := FWebView.Navigate(PChar(AUrl));
  if Failed(HR) then
    Fail('Endereço inválido: ' + AUrl);
end;

procedure TNecoWV2Engine.GoBack;
begin
  if FWebView <> nil then
    FWebView.GoBack;
end;

procedure TNecoWV2Engine.GoForward;
begin
  if FWebView <> nil then
    FWebView.GoForward;
end;

procedure TNecoWV2Engine.Reload;
begin
  if FWebView <> nil then
    FWebView.Reload;
end;

procedure TNecoWV2Engine.Stop;
begin
  if FWebView <> nil then
    FWebView.Stop;
end;

function TNecoWV2Engine.CanGoBack: Boolean;
var
  V: Integer;
begin
  Result := (FWebView <> nil) and Succeeded(FWebView.Get_CanGoBack(V)) and (V <> 0);
end;

function TNecoWV2Engine.CanGoForward: Boolean;
var
  V: Integer;
begin
  Result := (FWebView <> nil) and Succeeded(FWebView.Get_CanGoForward(V)) and (V <> 0);
end;

function TNecoWV2Engine.IsReady: Boolean;
begin
  Result := FReady and not FClosed;
end;

function TNecoWV2Engine.IsLoading: Boolean;
begin
  Result := FLoading;
end;

function TNecoWV2Engine.GetUrl: string;
var
  P: PWideChar;
begin
  if (FWebView <> nil) and Succeeded(FWebView.Get_Source(P)) then
    Result := TakeStr(P)
  else
    Result := FPendingUrl;
end;

function TNecoWV2Engine.GetTitle: string;
var
  P: PWideChar;
begin
  if (FWebView <> nil) and Succeeded(FWebView.Get_DocumentTitle(P)) then
    Result := TakeStr(P)
  else
    Result := '';
end;

procedure TNecoWV2Engine.SetBounds(const ARect: TRect);
begin
  FBounds := ARect;
  ApplyBounds;
end;

procedure TNecoWV2Engine.SetVisible(AVisible: Boolean);
begin
  FVisible := AVisible;
  if FController <> nil then
    FController.Set_IsVisible(Ord(AVisible));
end;

procedure TNecoWV2Engine.Focus;
begin
  if FController <> nil then
    FController.MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
end;

procedure TNecoWV2Engine.Blur;
begin
  if FParentWnd <> 0 then
    Winapi.Windows.SetFocus(FParentWnd);
end;

procedure TNecoWV2Engine.ExecuteScript(const AScript: string);
begin
  if FWebView <> nil then
    FWebView.ExecuteScript(PChar(AScript), nil);
end;

procedure TNecoWV2Engine.SetDarkMode(ADark: Boolean);
begin
  FDark := ADark;
  ApplyProfile;
end;

procedure TNecoWV2Engine.SetAutofill(AForms, APasswords: Boolean);
begin
  FAutofillForms := AForms;
  FSavePasswords := APasswords;
  ApplyProfile;
end;

procedure TNecoWV2Engine.OpenTaskManager;
var
  W6: ICoreWebView2_6;
begin
  if FClosed or (FWebView = nil) then
    Exit;
  if Supports(FWebView, ICoreWebView2_6, W6) then
    W6.OpenTaskManagerWindow;
end;

procedure TNecoWV2Engine.SetParentWindow(AWnd: NativeUInt);
var
  W: HWND;
begin
  W := HWND(AWnd);
  if FClosed or (W = 0) or (W = FParentWnd) then
    Exit;
  NecoTrace(Format('motor muda de janela: %x -> %x', [NativeUInt(FParentWnd), NativeUInt(W)]));
  FParentWnd := W;
  // A subclasse avisa o motor quando a janela nova se mexe (WM_MOVE).
  HookParent(W);
  // Controller ainda não criado: ele nasce direto na janela nova (StartController usa FParentWnd).
  if FController = nil then
    Exit;
  // O import da RTL declara wireHWND (ponteiro), mas a função nativa recebe o HWND por
  // valor: mesmo tamanho, então o valor vai direto.
  FController.Set_ParentWindow(wireHWND(W));
  FController.NotifyParentWindowPositionChanged;
  ApplyBounds;
end;

procedure TNecoWV2Engine.Close;
var
  W4: ICoreWebView2_4;
  W15: ICoreWebView2_15;
begin
  if FClosed then
    Exit;
  FClosed := True;
  FReady := False;
  if GPending <> nil then
    GPending.Remove(Self);
  if GEngines <> nil then
    GEngines.Remove(Self);
  ClearEvents;
  if FSink <> nil then
    FSink.Detach;

  // 1. remover eventos
  if FWebView <> nil then
  begin
    FWebView.remove_NavigationStarting(FTokNavStart);
    FWebView.remove_NavigationCompleted(FTokNavDone);
    FWebView.remove_SourceChanged(FTokSource);
    FWebView.remove_HistoryChanged(FTokHistory);
    FWebView.remove_DocumentTitleChanged(FTokTitle);
    FWebView.remove_NewWindowRequested(FTokNewWindow);
    FWebView.remove_ProcessFailed(FTokProcess);
    FWebView.remove_ContainsFullScreenElementChanged(FTokFull);
    if FHasFavToken and Supports(FWebView, ICoreWebView2_15, W15) then
      W15.remove_FaviconChanged(FTokFav);
    FWebView.remove_WebResourceRequested(FTokResource);
    if FHasDownloadToken and Supports(FWebView, ICoreWebView2_4, W4) then
      W4.remove_DownloadStarting(FTokDownload);
  end;
  if FController <> nil then
  begin
    FController.remove_AcceleratorKeyPressed(FTokAccel);
    FController.remove_GotFocus(FTokFocus);
    // 2. fechar o controller
    FController.Close;
  end;
  // 3. soltar as interfaces (todas vivas: o controller só morre quando a última referência sai)
  FWebView := nil;
  FController := nil;
  FSink := nil;
  FSinkRef := nil;
end;

{ TNecoWV2Download }

constructor TNecoWV2Download.Create(const AOp: ICoreWebView2DownloadOperation; const APath: string);
begin
  inherited Create;
  FOp := AOp;
  FPath := APath;
  FState := ndsInProgress;
  Refresh;
  FAttached := Succeeded(FOp.add_BytesReceivedChanged(Self, FTokBytes)) and
    Succeeded(FOp.add_StateChanged(Self, FTokState));
  GDownloads.Add(Self);
end;

procedure TNecoWV2Download.Refresh;
var
  P: PWideChar;
  St: COREWEBVIEW2_DOWNLOAD_STATE;
  N: Int64;
begin
  if FOp = nil then
    Exit;
  if (FUrl = '') and Succeeded(FOp.Get_uri(P)) then
    FUrl := TakeStr(P);
  if Succeeded(FOp.Get_ResultFilePath(P)) then
  begin
    if P <> nil then
      FPath := TakeStr(P);
  end;
  if Succeeded(FOp.Get_BytesReceived(N)) then
    FReceived := N;
  if Succeeded(FOp.Get_TotalBytesToReceive(N)) then
    FTotal := N;
  if Succeeded(FOp.Get_State(St)) then
    case St of
      COREWEBVIEW2_DOWNLOAD_STATE_COMPLETED:
        FState := ndsCompleted;
      COREWEBVIEW2_DOWNLOAD_STATE_INTERRUPTED:
        FState := ndsInterrupted;
    else
      FState := ndsInProgress;
    end;
end;

procedure TNecoWV2Download.Changed;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

function TNecoWV2Download.BytesChanged(const sender: ICoreWebView2DownloadOperation;
  const args: IUnknown): HResult;
var
  Keep: IInterface;
begin
  Result := S_OK;
  Keep := Self;
  try
    Refresh;
    Changed;
  except
  end;
end;

function TNecoWV2Download.StateChanged(const sender: ICoreWebView2DownloadOperation;
  const args: IUnknown): HResult;
var
  Keep: IInterface;
begin
  Result := S_OK;
  Keep := Self;
  try
    Refresh;
    Changed;
    if FState <> ndsInProgress then
      Detach;
  except
  end;
end;

procedure TNecoWV2Download.Detach;
var
  Keep: IInterface;
begin
  Keep := Self; // remover os handlers solta as referências do WebView2 a este objeto
  if FAttached and (FOp <> nil) then
  begin
    FOp.remove_BytesReceivedChanged(FTokBytes);
    FOp.remove_StateChanged(FTokState);
  end;
  FAttached := False;
  FOp := nil;
  if GDownloads <> nil then
    GDownloads.Remove(Self);
end;

function TNecoWV2Download.GetUrl: string;
begin
  Result := FUrl;
end;

function TNecoWV2Download.GetFilePath: string;
begin
  Result := FPath;
end;

function TNecoWV2Download.GetReceived: Int64;
begin
  Result := FReceived;
end;

function TNecoWV2Download.GetTotal: Int64;
begin
  Result := FTotal;
end;

function TNecoWV2Download.GetState: TNecoDownloadState;
begin
  Result := FState;
end;

function TNecoWV2Download.GetOnChanged: TNotifyEvent;
begin
  Result := FOnChanged;
end;

procedure TNecoWV2Download.SetOnChanged(const AValue: TNotifyEvent);
begin
  FOnChanged := AValue;
end;

procedure TNecoWV2Download.Cancel;
begin
  if FOp <> nil then
    FOp.Cancel;
end;

{ Memória }

type
  // PROCESS_MEMORY_COUNTERS_EX2 (Windows 10 1809+). O Winapi.PsAPI da RTL não tem.
  TNecoMemCounters = record
    cb: DWORD;
    PageFaultCount: DWORD;
    PeakWorkingSetSize: SIZE_T;
    WorkingSetSize: SIZE_T;
    QuotaPeakPagedPoolUsage: SIZE_T;
    QuotaPagedPoolUsage: SIZE_T;
    QuotaPeakNonPagedPoolUsage: SIZE_T;
    QuotaNonPagedPoolUsage: SIZE_T;
    PagefileUsage: SIZE_T;
    PeakPagefileUsage: SIZE_T;
    PrivateUsage: SIZE_T;
    PrivateWorkingSetSize: SIZE_T;
    SharedCommitUsage: UInt64;
  end;

const
  // Basta para ler a memória de processo de outro usuário/integridade (o Winapi.Windows não tem).
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

function K32GetProcessMemoryInfo(Process: THandle; ppsmemCounters: Pointer; cb: DWORD): BOOL;
  stdcall; external kernel32;

/// Memória privada em uso (o que a coluna "Memória" do Gerenciador de Tarefas mostra).
/// 0 se o processo já terminou.
function ProcessMemory(APid: Cardinal): UInt64;
var
  H: THandle;
  C: TNecoMemCounters;
  Own: Boolean;
begin
  Result := 0;
  Own := APid = GetCurrentProcessId;
  if Own then
    H := GetCurrentProcess
  else
    H := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, APid);
  if H = 0 then
    Exit;
  try
    FillChar(C, SizeOf(C), 0);
    C.cb := SizeOf(C);
    if K32GetProcessMemoryInfo(H, @C, C.cb) then
      Result := C.PrivateWorkingSetSize
    else
    begin
      // Windows antigo: só a versão EX (sem o conjunto de trabalho privado).
      C.cb := DWORD(PByte(@C.PrivateWorkingSetSize) - PByte(@C));
      if K32GetProcessMemoryInfo(H, @C, C.cb) then
        Result := C.PrivateUsage;
    end;
  finally
    if not Own then
      CloseHandle(H);
  end;
end;

procedure AddProcess(var AReport: TNecoMemoryReport; AKind: COREWEBVIEW2_PROCESS_KIND;
  ABytes: UInt64);
begin
  Inc(AReport.Processes);
  case AKind of
    COREWEBVIEW2_PROCESS_KIND_BROWSER:
      Inc(AReport.Browser, ABytes);
    COREWEBVIEW2_PROCESS_KIND_RENDERER:
      Inc(AReport.Pages, ABytes);
    COREWEBVIEW2_PROCESS_KIND_GPU:
      Inc(AReport.Gpu, ABytes);
  else
    Inc(AReport.Other, ABytes);
  end;
end;

function NewReport: TNecoMemoryReport;
begin
  Result := Default(TNecoMemoryReport);
  Result.App := ProcessMemory(GetCurrentProcessId);
  Result.Processes := 1;
end;

/// Id do quadro principal da página a que este quadro pertence (sobe pelos pais).
/// 0 se o motor não informa.
function TopFrameId(const AFrame: ICoreWebView2FrameInfo): Cardinal;
var
  F, P: ICoreWebView2FrameInfo;
  F2: ICoreWebView2FrameInfo2;
  Id: SYSUINT;
  N: Integer;
begin
  Result := 0;
  F := AFrame;
  for N := 1 to 64 do // iframe dentro de iframe: o teto só evita laço com dado estranho
  begin
    if not Supports(F, ICoreWebView2FrameInfo2, F2) then
      Exit;
    P := nil;
    if Failed(F2.Get_ParentFrameInfo(P)) or (P = nil) then
    begin
      if Succeeded(F2.Get_FrameId(Id)) then
        Result := Id;
      Exit;
    end;
    F := P;
  end;
end;

{ TNecoWV2MemoryReq }

constructor TNecoWV2MemoryReq.Create(const ACallback: TNecoMemoryCallback);
begin
  inherited Create;
  FCallback := ACallback;
end;

function TNecoWV2MemoryReq.Invoke(errorCode: HResult;
  const AInfos: ICoreWebView2ProcessExtendedInfoCollection): HResult;
var
  R: TNecoMemoryReport;
  ByFrame: TDictionary<Cardinal, TNecoWV2Engine>;
  ByEngine: TDictionary<TNecoWV2Engine, Integer>; // índice em R.Tabs
  Owners: TList<TNecoWV2Engine>;
  E: TNecoWV2Engine;
  W20: ICoreWebView2_20;
  Ext: ICoreWebView2ProcessExtendedInfo;
  Info: ICoreWebView2ProcessInfo;
  Frames: ICoreWebView2FrameInfoCollection;
  It: ICoreWebView2FrameInfoCollectionIterator;
  Frame: ICoreWebView2FrameInfo;
  Kind: COREWEBVIEW2_PROCESS_KIND;
  Count: SYSUINT;
  I: Integer;
  FrameId: SYSUINT;
  Pid: SYSINT;
  Has: Integer;
  Bytes: UInt64;
  K: Integer;
begin
  Result := S_OK;
  // App fechando: GEnv já foi solto e quem pediu pode não existir mais.
  if (GEnv = nil) or (GEngines = nil) or not Assigned(FCallback) then
    Exit;
  try
    R := NewReport;
    ByFrame := TDictionary<Cardinal, TNecoWV2Engine>.Create;
    ByEngine := TDictionary<TNecoWV2Engine, Integer>.Create;
    Owners := TList<TNecoWV2Engine>.Create;
    try
      // Quadro principal de cada aba -> aba.
      for E in GEngines do
        if not E.FClosed and Supports(E.FWebView, ICoreWebView2_20, W20) and
          Succeeded(W20.Get_FrameId(FrameId)) then
          ByFrame.AddOrSetValue(FrameId, E);

      if Succeeded(errorCode) and (AInfos <> nil) and Succeeded(AInfos.Get_Count(Count)) then
        for I := 0 to Integer(Count) - 1 do
        begin
          Ext := nil;
          Info := nil;
          if Failed(AInfos.GetValueAtIndex(I, Ext)) or (Ext = nil) or
            Failed(Ext.Get_ProcessInfo(Info)) or (Info = nil) or
            Failed(Info.Get_ProcessId(Pid)) or Failed(Info.Get_Kind(Kind)) then
            Continue;
          Bytes := ProcessMemory(Cardinal(Pid));
          AddProcess(R, Kind, Bytes);
          if Kind <> COREWEBVIEW2_PROCESS_KIND_RENDERER then
            Continue;

          // Quais abas este processo desenha (um site aberto em duas abas divide o processo).
          Owners.Clear;
          Frames := nil;
          It := nil;
          if Succeeded(Ext.Get_AssociatedFrameInfos(Frames)) and (Frames <> nil) and
            Succeeded(Frames.GetIterator(It)) and (It <> nil) then
            while Succeeded(It.Get_hasCurrent(Has)) and (Has <> 0) do
            begin
              Frame := nil;
              if Succeeded(It.GetCurrent(Frame)) and (Frame <> nil) and
                ByFrame.TryGetValue(TopFrameId(Frame), E) and not Owners.Contains(E) then
                Owners.Add(E);
              if Failed(It.MoveNext(Has)) or (Has = 0) then
                Break;
            end;
          for E in Owners do
          begin
            if not ByEngine.TryGetValue(E, K) then
            begin
              K := Length(R.Tabs);
              SetLength(R.Tabs, K + 1);
              R.Tabs[K].Engine := E;
              R.Tabs[K].Bytes := 0;
              R.Tabs[K].SharedWith := 1;
              ByEngine.Add(E, K);
            end;
            Inc(R.Tabs[K].Bytes, Bytes div UInt64(Owners.Count));
            if Owners.Count > R.Tabs[K].SharedWith then
              R.Tabs[K].SharedWith := Owners.Count;
          end;
        end;
    finally
      Owners.Free;
      ByEngine.Free;
      ByFrame.Free;
    end;
    FCallback(R);
  except
    // Nenhuma exceção atravessa a fronteira COM.
  end;
  FCallback := nil;
end;

{ API }

procedure NecoWV2QueryMemory(const ACallback: TNecoMemoryCallback);
var
  E8: ICoreWebView2Environment8;
  E13: ICoreWebView2Environment13;
  Col: ICoreWebView2ProcessInfoCollection;
  Info: ICoreWebView2ProcessInfo;
  Count: SYSUINT;
  I: Integer;
  Pid: SYSINT;
  Kind: COREWEBVIEW2_PROCESS_KIND;
  R: TNecoMemoryReport;
begin
  if not Assigned(ACallback) then
    Exit;
  // Com a lista estendida dá para saber qual processo é de qual aba.
  if Supports(GEnv, ICoreWebView2Environment13, E13) and
    Succeeded(E13.GetProcessExtendedInfos(TNecoWV2MemoryReq.Create(ACallback))) then
    Exit;
  // Runtime mais antigo: só o total, sem o detalhe por aba.
  R := NewReport;
  if Supports(GEnv, ICoreWebView2Environment8, E8) and Succeeded(E8.GetProcessInfos(Col)) and
    (Col <> nil) and Succeeded(Col.Get_Count(Count)) then
    for I := 0 to Integer(Count) - 1 do
    begin
      Info := nil;
      if Succeeded(Col.GetValueAtIndex(I, Info)) and (Info <> nil) and
        Succeeded(Info.Get_ProcessId(Pid)) and Succeeded(Info.Get_Kind(Kind)) then
        AddProcess(R, Kind, ProcessMemory(Cardinal(Pid)));
    end;
  ACallback(R);
end;

procedure NecoWV2Setup(const AOptions: TNecoWV2Options);
begin
  GOptions := AOptions;
end;

function NecoWV2CreateEngine(AParentWnd: HWND): INecoEngine;
begin
  Result := TNecoWV2Engine.Create(AParentWnd);
end;

procedure NecoWV2Shutdown;
var
  E: TNecoWV2Engine;
  D: TNecoWV2Download;
  W: HWND;
begin
  for E in GEngines.ToArray do
    E.Close;
  for D in GDownloads.ToArray do
  begin
    D.FOnChanged := nil;
    D.Detach;
  end;
  GPending.Clear;
  for W in GHooked.ToArray do
    RemoveWindowSubclass(W, @NecoParentSubclass, 1);
  GHooked.Clear;
  // Respostas de extensão que ainda chegarem veem o perfil nil e não fazem nada.
  GExtProfile := nil;
  GExtOnInstalled := nil;
  GExtConfigured := False;
  GExtBusy := False;
  GEnv := nil;
  GEnvState := esNone;
end;

initialization
  GPending := TList<TNecoWV2Engine>.Create;
  GEngines := TList<TNecoWV2Engine>.Create;
  GDownloads := TList<TNecoWV2Download>.Create;
  GHooked := TList<HWND>.Create;

finalization
  FreeAndNil(GPending);
  FreeAndNil(GEngines);
  FreeAndNil(GDownloads);
  FreeAndNil(GHooked);
{$ENDIF}
end.
