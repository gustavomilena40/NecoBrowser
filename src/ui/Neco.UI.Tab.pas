unit Neco.UI.Tab;

{ Uma aba: dona de um INecoEngine e do estado que a tela mostra
  (título, URL, carregando, contador de bloqueados).
  A aba não desenha nada; o form principal escuta OnChanged e redesenha. }

interface

uses
  System.SysUtils, System.Classes, System.Types,
  FMX.Controls, FMX.Forms, FMX.Objects, FMX.StdCtrls,
  Neco.Engine.Intf, Neco.Core.Blocklist;

type
  TNecoTabChange = (tcTitle, tcUrl, tcLoading, tcHistory, tcBlocked, tcError);
  TNecoTabChangeEvent = procedure(Sender: TObject; AChange: TNecoTabChange) of object;
  TNecoTabUrlEvent = procedure(Sender: TObject; const AUrl: string) of object;
  TNecoTabBoolEvent = procedure(Sender: TObject; AValue: Boolean) of object;
  TNecoTabDownloadEvent = procedure(Sender: TObject; const ADownload: INecoDownload) of object;
  TNecoTabKeyEvent = procedure(Sender: TObject; AKey: Word; AShift: TShiftState;
    var AHandled: Boolean) of object;

  TNecoTab = class
  private
    FEngine: INecoEngine;
    FTitle: string;
    FUrl: string;
    FLoading: Boolean;
    FBlocked: Integer;
    FError: string;
    FNavError: TNecoNavError;
    FAttemptUrl: string;
    FClosed: Boolean;
    FBlocklist: TNecoBlocklist;
    FBlockerOn: TFunc<Boolean>;
    FOnChanged: TNecoTabChangeEvent;
    FOnNewWindow: TNecoTabUrlEvent;
    FOnDownload: TNecoTabDownloadEvent;
    FOnKey: TNecoTabKeyEvent;
    FOnPageFocus: TNotifyEvent;
    FOnNavigated: TNecoTabUrlEvent;
    FOnFullScreen: TNecoTabBoolEvent;
    FLazyUrl: string;
    procedure EngineFullScreen(Sender: TObject; AValue: Boolean);
    procedure Changed(AChange: TNecoTabChange);
    // Sem const: a assinatura tem que bater com TFunc<string, Boolean>.
    function FilterRequest(AUrl: string): Boolean;
    // eventos do motor
    procedure EngineReady(Sender: TObject);
    procedure EngineError(Sender: TObject; const AMessage: string);
    procedure EngineNavStarting(Sender: TObject; const AUrl: string; var ACancel: Boolean);
    procedure EngineNavCompleted(Sender: TObject; ASuccess: Boolean; AError: TNecoNavError);
    procedure EngineTitle(Sender: TObject);
    procedure EngineUrl(Sender: TObject; const AUrl: string);
    procedure EngineHistory(Sender: TObject);
    procedure EngineNewWindow(Sender: TObject; const AUrl: string);
    procedure EngineDownload(Sender: TObject; const ADownload: INecoDownload);
    procedure EngineKey(Sender: TObject; AKey: Word; AShift: TShiftState; var AHandled: Boolean);
    procedure EngineFocus(Sender: TObject);
  public
    /// Elementos visuais da aba na faixa de abas (criados e liberados pelo form).
    Button: TRectangle;
    TitleLabel: TLabel;
    CloseButton: TControl;
    constructor Create(AForm: TCommonCustomForm; ABlocklist: TNecoBlocklist;
      const ABlockerOn: TFunc<Boolean>);
    destructor Destroy; override;
    procedure Navigate(const AUrl: string);
    /// Aba restaurada que só carrega quando for ativada (como no Chrome).
    procedure SetLazy(const AUrl: string);
    function IsLazy: Boolean;
    procedure LoadLazy;
    /// Fecha o motor. Não chamar de dentro de um evento do próprio motor (regra 5.3):
    /// o form adia com TThread.ForceQueue.
    procedure Close;
    function DisplayTitle: string;
    /// A página da aba é a página de erro do NecoBrowser (o form esconde o motor).
    function HasErrorPage: Boolean;
    /// Tenta de novo o endereço que falhou.
    procedure Retry;
    property Engine: INecoEngine read FEngine;
    property Title: string read FTitle;
    property Url: string read FUrl;
    property Loading: Boolean read FLoading;
    property BlockedCount: Integer read FBlocked;
    /// Falha do próprio motor (ex.: WebView2 ausente). Vazio = sem falha.
    property Error: string read FError;
    /// Falha da última navegação principal que vira página de erro (neNone = nenhuma).
    property NavError: TNecoNavError read FNavError;
    /// Endereço da última navegação principal pedida (o que falhou, se NavError <> neNone).
    property AttemptUrl: string read FAttemptUrl;
    property OnChanged: TNecoTabChangeEvent read FOnChanged write FOnChanged;
    property OnNewWindow: TNecoTabUrlEvent read FOnNewWindow write FOnNewWindow;
    property OnDownload: TNecoTabDownloadEvent read FOnDownload write FOnDownload;
    property OnKey: TNecoTabKeyEvent read FOnKey write FOnKey;
    property OnPageFocus: TNotifyEvent read FOnPageFocus write FOnPageFocus;
    /// Navegação principal concluída com sucesso (para o histórico).
    property OnNavigated: TNecoTabUrlEvent read FOnNavigated write FOnNavigated;
    property OnFullScreen: TNecoTabBoolEvent read FOnFullScreen write FOnFullScreen;
  end;

implementation

uses
  Neco.Core.Url, Neco.Engine.Factory;

{ TNecoTab }

constructor TNecoTab.Create(AForm: TCommonCustomForm; ABlocklist: TNecoBlocklist;
  const ABlockerOn: TFunc<Boolean>);
begin
  inherited Create;
  FBlocklist := ABlocklist;
  FBlockerOn := ABlockerOn;
  FEngine := NecoCreateEngine(AForm);
  FEngine.OnReady := EngineReady;
  FEngine.OnError := EngineError;
  FEngine.OnNavigationStarting := EngineNavStarting;
  FEngine.OnNavigationCompleted := EngineNavCompleted;
  FEngine.OnTitleChanged := EngineTitle;
  FEngine.OnUrlChanged := EngineUrl;
  FEngine.OnHistoryChanged := EngineHistory;
  FEngine.OnNewWindowRequested := EngineNewWindow;
  FEngine.OnDownloadStarting := EngineDownload;
  FEngine.OnAcceleratorKey := EngineKey;
  FEngine.OnGotFocus := EngineFocus;
  FEngine.RequestFilter := FilterRequest;
  FEngine.OnFullScreen := EngineFullScreen;
end;

destructor TNecoTab.Destroy;
begin
  Close;
  inherited;
end;

procedure TNecoTab.Close;
begin
  if FClosed then
    Exit;
  FClosed := True;
  FOnChanged := nil;
  FOnNewWindow := nil;
  FOnDownload := nil;
  FOnKey := nil;
  FOnPageFocus := nil;
  FOnNavigated := nil;
  FOnFullScreen := nil;
  if FEngine <> nil then
  begin
    FEngine.Close;   // desliga os eventos e solta o motor nativo
    FEngine := nil;  // o objeto do motor ainda está vivo aqui: o _Release é seguro (regra 4.2)
  end;
end;

procedure TNecoTab.Navigate(const AUrl: string);
begin
  if (FEngine = nil) or (AUrl = '') then
    Exit;
  FError := '';
  if FUrl = '' then
    FUrl := AUrl;
  FEngine.Navigate(AUrl);
end;

procedure TNecoTab.SetLazy(const AUrl: string);
begin
  FLazyUrl := AUrl;
  FUrl := AUrl;
  FTitle := NecoExtractHost(AUrl);
end;

function TNecoTab.IsLazy: Boolean;
begin
  Result := FLazyUrl <> '';
end;

procedure TNecoTab.LoadLazy;
var
  U: string;
begin
  if FLazyUrl = '' then
    Exit;
  U := FLazyUrl;
  FLazyUrl := '';
  Navigate(U);
end;

procedure TNecoTab.EngineFullScreen(Sender: TObject; AValue: Boolean);
begin
  if Assigned(FOnFullScreen) then
    FOnFullScreen(Self, AValue);
end;

function TNecoTab.DisplayTitle: string;
begin
  // about:blank (aba nova, ou aba cuja navegação virou download) aparece como "Nova aba".
  if (FTitle <> '') and not SameText(FTitle, 'about:blank') then
    Result := FTitle
  else if (FUrl <> '') and not SameText(FUrl, 'about:blank') then
    Result := FUrl
  else
    Result := 'Nova aba';
end;

function TNecoTab.HasErrorPage: Boolean;
begin
  Result := (FNavError <> neNone) or (FError <> '');
end;

procedure TNecoTab.Retry;
begin
  if FAttemptUrl <> '' then
    Navigate(FAttemptUrl)
  else if FEngine <> nil then
    FEngine.Reload;
end;

procedure TNecoTab.Changed(AChange: TNecoTabChange);
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self, AChange);
end;

function TNecoTab.FilterRequest(AUrl: string): Boolean;
begin
  Result := (FBlocklist <> nil) and Assigned(FBlockerOn) and FBlockerOn() and
    FBlocklist.IsUrlBlocked(AUrl);
  if Result then
  begin
    Inc(FBlocked);
    Changed(tcBlocked);
  end;
end;

procedure TNecoTab.EngineReady(Sender: TObject);
begin
  Changed(tcHistory);
end;

procedure TNecoTab.EngineError(Sender: TObject; const AMessage: string);
begin
  FError := AMessage;
  FLoading := False;
  Changed(tcError);
end;

procedure TNecoTab.EngineNavStarting(Sender: TObject; const AUrl: string; var ACancel: Boolean);
var
  HadError: Boolean;
begin
  HadError := (FNavError <> neNone) or (FError <> '');
  FNavError := neNone;
  FAttemptUrl := AUrl;
  FError := '';
  FLoading := True;
  FBlocked := 0; // o contador é da página atual
  Changed(tcLoading);
  Changed(tcBlocked);
  if HadError then
    Changed(tcError); // some a página de erro
end;

procedure TNecoTab.EngineNavCompleted(Sender: TObject; ASuccess: Boolean; AError: TNecoNavError);
begin
  FLoading := False;
  FTitle := FEngine.GetTitle;
  FUrl := FEngine.GetUrl;
  Changed(tcLoading);
  Changed(tcTitle);
  if ASuccess and Assigned(FOnNavigated) then
    FOnNavigated(Self, FUrl);
  // Só estes viram a página de erro com a Neco; certificado e o resto ficam com a
  // página do próprio motor (que oferece o que fazer).
  if not ASuccess and (AError in [neNotFound, neOffline, neTimeout, neRefused]) then
  begin
    FNavError := AError;
    Changed(tcError);
  end;
end;

procedure TNecoTab.EngineTitle(Sender: TObject);
begin
  FTitle := FEngine.GetTitle;
  Changed(tcTitle);
end;

procedure TNecoTab.EngineUrl(Sender: TObject; const AUrl: string);
begin
  FUrl := AUrl;
  Changed(tcUrl);
end;

procedure TNecoTab.EngineHistory(Sender: TObject);
begin
  Changed(tcHistory);
end;

procedure TNecoTab.EngineNewWindow(Sender: TObject; const AUrl: string);
begin
  if Assigned(FOnNewWindow) then
    FOnNewWindow(Self, AUrl)
  else
    Navigate(AUrl);
end;

procedure TNecoTab.EngineDownload(Sender: TObject; const ADownload: INecoDownload);
begin
  if Assigned(FOnDownload) then
    FOnDownload(Self, ADownload);
end;

procedure TNecoTab.EngineKey(Sender: TObject; AKey: Word; AShift: TShiftState; var AHandled: Boolean);
begin
  if Assigned(FOnKey) then
    FOnKey(Self, AKey, AShift, AHandled);
end;

procedure TNecoTab.EngineFocus(Sender: TObject);
begin
  if Assigned(FOnPageFocus) then
    FOnPageFocus(Self);
end;

end.
