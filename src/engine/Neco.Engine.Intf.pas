unit Neco.Engine.Intf;

{ Contrato entre a tela e o motor de navegação.
  Windows implementa com WebView2 (Neco.Engine.WebView2); Android (fase 2) com WebView.
  Sem dependência de plataforma: só RTL. }

interface

uses
  System.SysUtils, System.Classes, System.Types;

type
  TNecoDownloadState = (ndsInProgress, ndsCompleted, ndsInterrupted);

  /// Um download em andamento ou terminado. Vive independente da aba que o iniciou.
  INecoDownload = interface
    ['{06DACECD-AA05-4413-9F1F-A0CB541D7A3F}']
    function GetUrl: string;
    function GetFilePath: string;
    function GetReceived: Int64;
    /// 0 ou menos: tamanho desconhecido.
    function GetTotal: Int64;
    function GetState: TNecoDownloadState;
    function GetOnChanged: TNotifyEvent;
    procedure SetOnChanged(const AValue: TNotifyEvent);
    procedure Cancel;
    property Url: string read GetUrl;
    property FilePath: string read GetFilePath;
    property Received: Int64 read GetReceived;
    property Total: Int64 read GetTotal;
    property State: TNecoDownloadState read GetState;
    /// Disparado na thread principal a cada progresso e na troca de estado.
    /// Sender é o objeto do download (use Supports para obter a interface).
    property OnChanged: TNotifyEvent read GetOnChanged write SetOnChanged;
  end;

  TNecoNavigationStartingEvent = procedure(Sender: TObject; const AUrl: string;
    var ACancel: Boolean) of object;
  /// Por que a navegação principal falhou (neNone = deu certo).
  /// neCanceled: parada pelo usuário, trocada por outra navegação ou virou download.
  /// neCertificate e neOther: o motor mostra a própria página (ex.: "continuar mesmo assim").
  TNecoNavError = (neNone, neNotFound, neOffline, neTimeout, neRefused, neCertificate,
    neCanceled, neOther);
  TNecoNavigationCompletedEvent = procedure(Sender: TObject; ASuccess: Boolean;
    AError: TNecoNavError) of object;
  TNecoUrlEvent = procedure(Sender: TObject; const AUrl: string) of object;
  TNecoErrorEvent = procedure(Sender: TObject; const AMessage: string) of object;
  TNecoBoolEvent = procedure(Sender: TObject; AValue: Boolean) of object;
  TNecoBytesEvent = procedure(Sender: TObject; const AData: TBytes) of object;
  TNecoDownloadStartingEvent = procedure(Sender: TObject; const ADownload: INecoDownload) of object;
  /// AKey é o código de tecla virtual (vkXxx de System.UITypes). AHandled = True consome a tecla.
  TNecoAcceleratorKeyEvent = procedure(Sender: TObject; AKey: Word; AShift: TShiftState;
    var AHandled: Boolean) of object;
  /// Recebe a URL de cada recurso pedido pela página; True = bloquear.
  /// Roda centenas de vezes por página: precisa ser O(1).
  TNecoRequestFilter = TFunc<string, Boolean>;

  INecoEngine = interface;

  /// Memória de uma aba: os processos de página que desenham aquela aba.
  TNecoMemoryTab = record
    Engine: INecoEngine;
    Bytes: UInt64;
    /// Maior número de abas que dividem um mesmo processo de página com esta (1 = só ela).
    /// Processo dividido entra em partes iguais em cada aba.
    SharedWith: Integer;
  end;

  /// Retrato da memória do navegador inteiro: o próprio exe mais todos os processos do motor.
  /// Valores em bytes de memória privada em uso (a coluna "Memória" do Gerenciador de Tarefas).
  TNecoMemoryReport = record
    /// O próprio NecoBrowser.exe.
    App: UInt64;
    /// Processo principal do motor (no Windows, o "Gerenciador WebView2").
    Browser: UInt64;
    /// Processos que desenham as páginas.
    Pages: UInt64;
    Gpu: UInt64;
    /// Rede, áudio, armazenamento e outros auxiliares.
    Other: UInt64;
    /// Quantos processos entraram na conta (o exe incluído).
    Processes: Integer;
    /// Vazio quando o motor não sabe dizer qual processo é de qual aba.
    Tabs: TArray<TNecoMemoryTab>;
    function Total: UInt64;
  end;
  TNecoMemoryCallback = reference to procedure(const AReport: TNecoMemoryReport);

  INecoEngine = interface
    ['{6524948E-313F-4DFD-B6FD-DA3F12EEDD3B}']
    procedure Navigate(const AUrl: string);
    procedure GoBack;
    procedure GoForward;
    procedure Reload;
    procedure Stop;
    function CanGoBack: Boolean;
    function CanGoForward: Boolean;
    /// A criação do motor nativo é assíncrona. Antes de pronto, Navigate guarda a URL.
    function IsReady: Boolean;
    function IsLoading: Boolean;
    function GetUrl: string;
    function GetTitle: string;
    /// Área da página em pixels físicos, relativa à área cliente da janela.
    procedure SetBounds(const ARect: TRect);
    procedure SetVisible(AVisible: Boolean);
    procedure Focus;
    /// Tira o foco do teclado da página e devolve para a janela (ex.: Ctrl+L).
    procedure Blur;
    procedure ExecuteScript(const AScript: string);
    /// Pede aos sites o esquema de cor escuro (prefers-color-scheme).
    procedure SetDarkMode(ADark: Boolean);
    /// AForms: lembrar e sugerir o que foi digitado em formulários.
    /// APasswords: oferecer salvar senhas (o motor guarda cifradas no perfil dele).
    procedure SetAutofill(AForms, APasswords: Boolean);
    /// Abre o gerenciador de tarefas do próprio motor (memória e CPU de cada página).
    procedure OpenTaskManager;
    /// Solta o motor nativo e desliga todos os eventos. Chamadas posteriores são ignoradas.
    procedure Close;

    function GetRequestFilter: TNecoRequestFilter;
    procedure SetRequestFilter(const AValue: TNecoRequestFilter);
    function GetOnReady: TNotifyEvent;
    procedure SetOnReady(const AValue: TNotifyEvent);
    function GetOnError: TNecoErrorEvent;
    procedure SetOnError(const AValue: TNecoErrorEvent);
    function GetOnNavigationStarting: TNecoNavigationStartingEvent;
    procedure SetOnNavigationStarting(const AValue: TNecoNavigationStartingEvent);
    function GetOnNavigationCompleted: TNecoNavigationCompletedEvent;
    procedure SetOnNavigationCompleted(const AValue: TNecoNavigationCompletedEvent);
    function GetOnTitleChanged: TNotifyEvent;
    procedure SetOnTitleChanged(const AValue: TNotifyEvent);
    function GetOnUrlChanged: TNecoUrlEvent;
    procedure SetOnUrlChanged(const AValue: TNecoUrlEvent);
    function GetOnHistoryChanged: TNotifyEvent;
    procedure SetOnHistoryChanged(const AValue: TNotifyEvent);
    function GetOnNewWindowRequested: TNecoUrlEvent;
    procedure SetOnNewWindowRequested(const AValue: TNecoUrlEvent);
    function GetOnDownloadStarting: TNecoDownloadStartingEvent;
    procedure SetOnDownloadStarting(const AValue: TNecoDownloadStartingEvent);
    function GetOnAcceleratorKey: TNecoAcceleratorKeyEvent;
    procedure SetOnAcceleratorKey(const AValue: TNecoAcceleratorKeyEvent);
    function GetOnGotFocus: TNotifyEvent;
    procedure SetOnGotFocus(const AValue: TNotifyEvent);
    function GetOnFullScreen: TNecoBoolEvent;
    procedure SetOnFullScreen(const AValue: TNecoBoolEvent);
    function GetOnFavicon: TNecoBytesEvent;
    procedure SetOnFavicon(const AValue: TNecoBytesEvent);

    property RequestFilter: TNecoRequestFilter read GetRequestFilter write SetRequestFilter;
    property OnReady: TNotifyEvent read GetOnReady write SetOnReady;
    property OnError: TNecoErrorEvent read GetOnError write SetOnError;
    property OnNavigationStarting: TNecoNavigationStartingEvent read GetOnNavigationStarting
      write SetOnNavigationStarting;
    property OnNavigationCompleted: TNecoNavigationCompletedEvent read GetOnNavigationCompleted
      write SetOnNavigationCompleted;
    property OnTitleChanged: TNotifyEvent read GetOnTitleChanged write SetOnTitleChanged;
    property OnUrlChanged: TNecoUrlEvent read GetOnUrlChanged write SetOnUrlChanged;
    property OnHistoryChanged: TNotifyEvent read GetOnHistoryChanged write SetOnHistoryChanged;
    property OnNewWindowRequested: TNecoUrlEvent read GetOnNewWindowRequested
      write SetOnNewWindowRequested;
    property OnDownloadStarting: TNecoDownloadStartingEvent read GetOnDownloadStarting
      write SetOnDownloadStarting;
    property OnAcceleratorKey: TNecoAcceleratorKeyEvent read GetOnAcceleratorKey
      write SetOnAcceleratorKey;
    /// A página recebeu o foco do teclado (o form FMX deixa de receber teclas).
    property OnGotFocus: TNotifyEvent read GetOnGotFocus write SetOnGotFocus;
    /// A página pediu tela cheia para um elemento (vídeo) ou saiu dela.
    property OnFullScreen: TNecoBoolEvent read GetOnFullScreen write SetOnFullScreen;
    /// Ícone do site (PNG) da página atual; chega depois da navegação.
    property OnFavicon: TNecoBytesEvent read GetOnFavicon write SetOnFavicon;
  end;

  /// Base com os campos de evento, para cada plataforma só implementar o motor.
  TNecoEngineBase = class(TInterfacedObject)
  protected
    FRequestFilter: TNecoRequestFilter;
    FOnReady: TNotifyEvent;
    FOnError: TNecoErrorEvent;
    FOnNavigationStarting: TNecoNavigationStartingEvent;
    FOnNavigationCompleted: TNecoNavigationCompletedEvent;
    FOnTitleChanged: TNotifyEvent;
    FOnUrlChanged: TNecoUrlEvent;
    FOnHistoryChanged: TNotifyEvent;
    FOnNewWindowRequested: TNecoUrlEvent;
    FOnDownloadStarting: TNecoDownloadStartingEvent;
    FOnAcceleratorKey: TNecoAcceleratorKeyEvent;
    FOnGotFocus: TNotifyEvent;
    FOnFullScreen: TNecoBoolEvent;
    FOnFavicon: TNecoBytesEvent;
    /// Zera todos os eventos (chamado no Close, antes de soltar o motor nativo).
    procedure ClearEvents;
  public
    function GetRequestFilter: TNecoRequestFilter;
    procedure SetRequestFilter(const AValue: TNecoRequestFilter);
    function GetOnReady: TNotifyEvent;
    procedure SetOnReady(const AValue: TNotifyEvent);
    function GetOnError: TNecoErrorEvent;
    procedure SetOnError(const AValue: TNecoErrorEvent);
    function GetOnNavigationStarting: TNecoNavigationStartingEvent;
    procedure SetOnNavigationStarting(const AValue: TNecoNavigationStartingEvent);
    function GetOnNavigationCompleted: TNecoNavigationCompletedEvent;
    procedure SetOnNavigationCompleted(const AValue: TNecoNavigationCompletedEvent);
    function GetOnTitleChanged: TNotifyEvent;
    procedure SetOnTitleChanged(const AValue: TNotifyEvent);
    function GetOnUrlChanged: TNecoUrlEvent;
    procedure SetOnUrlChanged(const AValue: TNecoUrlEvent);
    function GetOnHistoryChanged: TNotifyEvent;
    procedure SetOnHistoryChanged(const AValue: TNotifyEvent);
    function GetOnNewWindowRequested: TNecoUrlEvent;
    procedure SetOnNewWindowRequested(const AValue: TNecoUrlEvent);
    function GetOnDownloadStarting: TNecoDownloadStartingEvent;
    procedure SetOnDownloadStarting(const AValue: TNecoDownloadStartingEvent);
    function GetOnAcceleratorKey: TNecoAcceleratorKeyEvent;
    procedure SetOnAcceleratorKey(const AValue: TNecoAcceleratorKeyEvent);
    function GetOnGotFocus: TNotifyEvent;
    procedure SetOnGotFocus(const AValue: TNotifyEvent);
    function GetOnFullScreen: TNecoBoolEvent;
    procedure SetOnFullScreen(const AValue: TNecoBoolEvent);
    function GetOnFavicon: TNecoBytesEvent;
    procedure SetOnFavicon(const AValue: TNecoBytesEvent);
  end;

implementation

{ TNecoMemoryReport }

function TNecoMemoryReport.Total: UInt64;
begin
  Result := App + Browser + Pages + Gpu + Other;
end;

{ TNecoEngineBase }

procedure TNecoEngineBase.ClearEvents;
begin
  FRequestFilter := nil;
  FOnReady := nil;
  FOnError := nil;
  FOnNavigationStarting := nil;
  FOnNavigationCompleted := nil;
  FOnTitleChanged := nil;
  FOnUrlChanged := nil;
  FOnHistoryChanged := nil;
  FOnNewWindowRequested := nil;
  FOnDownloadStarting := nil;
  FOnAcceleratorKey := nil;
  FOnGotFocus := nil;
  FOnFullScreen := nil;
  FOnFavicon := nil;
end;

function TNecoEngineBase.GetRequestFilter: TNecoRequestFilter;
begin
  Result := FRequestFilter;
end;

procedure TNecoEngineBase.SetRequestFilter(const AValue: TNecoRequestFilter);
begin
  FRequestFilter := AValue;
end;

function TNecoEngineBase.GetOnReady: TNotifyEvent;
begin
  Result := FOnReady;
end;

procedure TNecoEngineBase.SetOnReady(const AValue: TNotifyEvent);
begin
  FOnReady := AValue;
end;

function TNecoEngineBase.GetOnError: TNecoErrorEvent;
begin
  Result := FOnError;
end;

procedure TNecoEngineBase.SetOnError(const AValue: TNecoErrorEvent);
begin
  FOnError := AValue;
end;

function TNecoEngineBase.GetOnNavigationStarting: TNecoNavigationStartingEvent;
begin
  Result := FOnNavigationStarting;
end;

procedure TNecoEngineBase.SetOnNavigationStarting(const AValue: TNecoNavigationStartingEvent);
begin
  FOnNavigationStarting := AValue;
end;

function TNecoEngineBase.GetOnNavigationCompleted: TNecoNavigationCompletedEvent;
begin
  Result := FOnNavigationCompleted;
end;

procedure TNecoEngineBase.SetOnNavigationCompleted(const AValue: TNecoNavigationCompletedEvent);
begin
  FOnNavigationCompleted := AValue;
end;

function TNecoEngineBase.GetOnTitleChanged: TNotifyEvent;
begin
  Result := FOnTitleChanged;
end;

procedure TNecoEngineBase.SetOnTitleChanged(const AValue: TNotifyEvent);
begin
  FOnTitleChanged := AValue;
end;

function TNecoEngineBase.GetOnUrlChanged: TNecoUrlEvent;
begin
  Result := FOnUrlChanged;
end;

procedure TNecoEngineBase.SetOnUrlChanged(const AValue: TNecoUrlEvent);
begin
  FOnUrlChanged := AValue;
end;

function TNecoEngineBase.GetOnHistoryChanged: TNotifyEvent;
begin
  Result := FOnHistoryChanged;
end;

procedure TNecoEngineBase.SetOnHistoryChanged(const AValue: TNotifyEvent);
begin
  FOnHistoryChanged := AValue;
end;

function TNecoEngineBase.GetOnNewWindowRequested: TNecoUrlEvent;
begin
  Result := FOnNewWindowRequested;
end;

procedure TNecoEngineBase.SetOnNewWindowRequested(const AValue: TNecoUrlEvent);
begin
  FOnNewWindowRequested := AValue;
end;

function TNecoEngineBase.GetOnDownloadStarting: TNecoDownloadStartingEvent;
begin
  Result := FOnDownloadStarting;
end;

procedure TNecoEngineBase.SetOnDownloadStarting(const AValue: TNecoDownloadStartingEvent);
begin
  FOnDownloadStarting := AValue;
end;

function TNecoEngineBase.GetOnAcceleratorKey: TNecoAcceleratorKeyEvent;
begin
  Result := FOnAcceleratorKey;
end;

procedure TNecoEngineBase.SetOnAcceleratorKey(const AValue: TNecoAcceleratorKeyEvent);
begin
  FOnAcceleratorKey := AValue;
end;

function TNecoEngineBase.GetOnGotFocus: TNotifyEvent;
begin
  Result := FOnGotFocus;
end;

procedure TNecoEngineBase.SetOnGotFocus(const AValue: TNotifyEvent);
begin
  FOnGotFocus := AValue;
end;

function TNecoEngineBase.GetOnFullScreen: TNecoBoolEvent;
begin
  Result := FOnFullScreen;
end;

procedure TNecoEngineBase.SetOnFullScreen(const AValue: TNecoBoolEvent);
begin
  FOnFullScreen := AValue;
end;

function TNecoEngineBase.GetOnFavicon: TNecoBytesEvent;
begin
  Result := FOnFavicon;
end;

procedure TNecoEngineBase.SetOnFavicon(const AValue: TNecoBytesEvent);
begin
  FOnFavicon := AValue;
end;

end.
