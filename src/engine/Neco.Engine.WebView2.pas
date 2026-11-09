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
    /// Caminho completo da WebView2Loader.dll.
    LoaderPath: string;
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
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}
uses
  System.SysUtils, System.Classes, System.Types, System.Generics.Collections,
  Winapi.Messages, Winapi.ActiveX, Winapi.CommCtrl, Winapi.WebView2, Winapi.EdgeUtils,
  Neco.Core.Trace;

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
    ICoreWebView2FocusChangedEventHandler)
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
    FTokResource, FTokDownload, FTokProcess, FTokAccel, FTokFocus: EventRegistrationToken;
    FHasDownloadToken: Boolean;
    FPendingUrl: string;
    FBounds: TRect;
    FVisible: Boolean;
    FDark: Boolean;
    FReady: Boolean;
    FClosed: Boolean;
    FLoading: Boolean;
    /// URL da navegação principal em curso: o bloqueador nunca barra este documento.
    FMainNavUrl: string;
    // diagnóstico (NECO_TRACE)
    FNavStartMs: Double;
    FResCount: Integer;
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
    procedure Close;
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

  TNecoWV2EnvHandler = class(TInterfacedObject, ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler)
  private
    function Invoke(errorCode: HResult; const AEnv: ICoreWebView2Environment): HResult; stdcall;
  end;

  TEnvState = (esNone, esCreating, esReady, esFailed);

const
  CTargetBrowserVersion = '137.0.3296.44';

var
  GOptions: TNecoWV2Options;
  GEnv: ICoreWebView2Environment;
  GEnvState: TEnvState = esNone;
  GEnvError: string;
  GPending: TList<TNecoWV2Engine>;
  GEngines: TList<TNecoWV2Engine>;
  GDownloads: TList<TNecoWV2Download>;
  GHooked: TList<HWND>;

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

procedure EnsureEnvironment;
var
  Opts: ICoreWebView2EnvironmentOptions;
  HR: HResult;
begin
  if GEnvState <> esNone then
    Exit;
  GEnvState := esCreating;
  if GOptions.LoaderPath <> '' then
    SetWebView2Path(GOptions.LoaderPath);
  if not CheckWebView2Loaded then
  begin
    GEnvState := esFailed;
    GEnvError := 'WebView2Loader.dll não encontrada ao lado do executável.';
    Exit;
  end;
  Opts := TCoreWebView2EnvironmentOptions.Create;
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
      GEnvError := 'WebView2 Runtime não encontrado. Instale o Microsoft Edge WebView2 Runtime.'
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
    if Succeeded(errorCode) and (AEnv <> nil) then
    begin
      GEnv := AEnv;
      GEnvState := esReady;
      NecoTrace('ambiente pronto');
    end
    else
    begin
      GEnvState := esFailed;
      if errorCode = HResult($80070002) then
        GEnvError := 'WebView2 Runtime não encontrado. Instale o Microsoft Edge WebView2 Runtime.'
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
    E.FNavStartMs := NecoTraceMs;
    E.FResCount := 0;
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
begin
  Result := S_OK;
  E := FEngine;
  if E = nil then
    Exit;
  Keep := E;
  try
    E.FLoading := False;
    if Failed(args.Get_IsSuccess(Ok)) then
      Ok := 0;
    if NecoTraceOn then
      NecoTrace(Format('nav fim ok=%d duracao=%.0fms requisicoes_filtradas=%d tempo_no_filtro=%.1fms',
        [Ok, NecoTraceMs - E.FNavStartMs, E.FResCount, E.FResMs]));
    if Assigned(E.FOnNavigationCompleted) then
      E.FOnNavigationCompleted(E, Ok <> 0);
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
        if Succeeded(GEnv.CreateWebResourceResponse(nil, 403, 'Blocked', '', Resp)) then
          args.Set_Response(Resp);
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

{ TNecoWV2Engine }

constructor TNecoWV2Engine.Create(AParentWnd: HWND);
begin
  inherited Create;
  FParentWnd := AParentWnd;
  FVisible := True;
  FDark := True;
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
  FWebView.AddWebResourceRequestedFilter('*', COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
  FWebView.add_WebResourceRequested(FSink, FTokResource);
  if Supports(FWebView, ICoreWebView2_4, W4) then
    FHasDownloadToken := Succeeded(W4.add_DownloadStarting(FSink, FTokDownload));
  FController.add_AcceleratorKeyPressed(FSink, FTokAccel);
  FController.add_GotFocus(FSink, FTokFocus);

  ApplyProfile;
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
begin
  if (FWebView = nil) or not Supports(FWebView, ICoreWebView2_13, W13) then
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

procedure TNecoWV2Engine.Close;
var
  W4: ICoreWebView2_4;
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

{ API }

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
