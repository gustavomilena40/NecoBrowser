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
    FClosed: Boolean;
    FBlocklist: TNecoBlocklist;
    FBlockerOn: TFunc<Boolean>;
    FOnChanged: TNecoTabChangeEvent;
    FOnNewWindow: TNecoTabUrlEvent;
    FOnDownload: TNecoTabDownloadEvent;
    FOnKey: TNecoTabKeyEvent;
    FOnPageFocus: TNotifyEvent;
    FOnNavigated: TNecoTabUrlEvent;
    procedure Changed(AChange: TNecoTabChange);
    // Sem const: a assinatura tem que bater com TFunc<string, Boolean>.
    function FilterRequest(AUrl: string): Boolean;
    // eventos do motor
    procedure EngineReady(Sender: TObject);
    procedure EngineError(Sender: TObject; const AMessage: string);
    procedure EngineNavStarting(Sender: TObject; const AUrl: string; var ACancel: Boolean);
    procedure EngineNavCompleted(Sender: TObject; ASuccess: Boolean);
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
    /// Fecha o motor. Não chamar de dentro de um evento do próprio motor (regra 5.3):
    /// o form adia com TThread.ForceQueue.
    procedure Close;
    function DisplayTitle: string;
    property Engine: INecoEngine read FEngine;
    property Title: string read FTitle;
    property Url: string read FUrl;
    property Loading: Boolean read FLoading;
    property BlockedCount: Integer read FBlocked;
    property Error: string read FError;
    property OnChanged: TNecoTabChangeEvent read FOnChanged write FOnChanged;
    property OnNewWindow: TNecoTabUrlEvent read FOnNewWindow write FOnNewWindow;
    property OnDownload: TNecoTabDownloadEvent read FOnDownload write FOnDownload;
    property OnKey: TNecoTabKeyEvent read FOnKey write FOnKey;
    property OnPageFocus: TNotifyEvent read FOnPageFocus write FOnPageFocus;
    /// Navegação principal concluída com sucesso (para o histórico).
    property OnNavigated: TNecoTabUrlEvent read FOnNavigated write FOnNavigated;
  end;

implementation

uses
  Neco.Engine.Factory;

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

function TNecoTab.DisplayTitle: string;
begin
  if FTitle <> '' then
    Result := FTitle
  else if FUrl <> '' then
    Result := FUrl
  else
    Result := 'Nova aba';
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
begin
  FError := '';
  FLoading := True;
  FBlocked := 0; // o contador é da página atual
  Changed(tcLoading);
  Changed(tcBlocked);
end;

procedure TNecoTab.EngineNavCompleted(Sender: TObject; ASuccess: Boolean);
begin
  FLoading := False;
  FTitle := FEngine.GetTitle;
  FUrl := FEngine.GetUrl;
  Changed(tcLoading);
  Changed(tcTitle);
  if ASuccess and Assigned(FOnNavigated) then
    FOnNavigated(Self, FUrl);
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
