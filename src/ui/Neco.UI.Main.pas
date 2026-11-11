unit Neco.UI.Main;

{ Form principal do NecoBrowser. A tela é montada em código (Neco.UI.Theme tem as cores).

  Espaço aéreo: a página é uma janela nativa por cima do FMX. Nada do FMX pode ficar
  sobre FPageArea; painéis laterais encolhem essa área, nunca a cobrem. }

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Objects, FMX.Layouts, FMX.StdCtrls,
  FMX.Edit, FMX.Dialogs,
  Neco.Core.Settings, Neco.Core.Blocklist, Neco.Core.Bookmarks, Neco.Core.History,
  Neco.Engine.Intf, Neco.UI.Theme, Neco.UI.Tab, Neco.UI.Frame, Neco.UI.Neco,
  Neco.UI.SidePanel, Neco.UI.Downloads, Neco.UI.Bookmarks, Neco.UI.Settings, Neco.UI.ErrorView,
  Neco.UI.BookmarkBar, Neco.UI.History, Neco.UI.App;

type
  TFormMain = class(TForm, INecoWindow)
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    // Emprestados do app (Neco.UI.App): a janela usa, quem cria, grava e libera é o NecoApp.
    FSettings: TNecoSettings;
    FBlocklist: TNecoBlocklist;
    FBookmarks: TNecoBookmarks;
    FHistory: TNecoHistory;
    FTabs: TObjectList<TNecoTab>;
    FActive: TNecoTab;
    FStarted: Boolean;
    FShuttingDown: Boolean;
    // Aberta com Ctrl+N: começa na página inicial e não mexe na sessão gravada.
    FExtraWindow: Boolean;
    // teste de memória (NECO_TESTE_ABAS): abre e fecha abas sozinho, em ciclos
    FSelfTest: TTimer;
    FSelfTestTabs, FSelfTestCycles, FSelfTestCycle, FSelfTestStep: Integer;

    // faixa de abas = barra de título (Neco.UI.Frame)
    FTabStrip: TRectangle;
    FBtnNewTab: TNecoIconButton;
    FBtnMin, FBtnMax, FBtnClose: TNecoIconButton;
    FStage: TNecoStage;
    // arrastar aba para mudar a posição
    FDragTab: TNecoTab;
    FDragging: Boolean;
    FDragStartX, FDragGrabX, FTabW: Single;

    // tela
    FToolbar: TRectangle;
    FBtnBack, FBtnForward, FBtnReload: TNecoIconButton;
    FAddressBox: TRectangle;
    FAddressIcon: TPath;
    FAddress: TEdit;
    FToolRight: TLayout;
    // À direita da barra só ficam memória, a seta do menu e configurações.
    FBtnMenu: TNecoIconButton;
    FShieldBadge: TRectangle;
    FShieldBadgeText: TLabel;
    FBtnSettings: TNecoIconButton;
    // menu da seta (janela própria, como as sugestões: fica por cima da página)
    FMenu: TPopup;
    FMenuBox: TRectangle;
    FMenuY: Single; // onde entra a próxima linha do menu
    // atualização automática: quem baixa é o app; aqui só o aviso
    FUpdateDot: TCircle;      // bolinha na seta quando há versão pronta
    // medidor de memória: o exe mais todos os processos do motor (que o Windows mostra
    // num grupo separado, "Gerenciador WebView2"). Quem mede é o app.
    FBtnMemory: TNecoIconButton;
    // sugestões da barra (buscas digitadas e páginas do histórico). O TPopup é uma janela
    // própria: fica por cima da página nativa e não tira o foco da barra.
    FSuggest: TPopup;
    FSuggestBox: TRectangle;
    FSuggestRows: TList<TRectangle>;
    FSuggestItems: TArray<TNecoSuggestion>;
    FSuggestIndex: Integer;   // -1 = nenhuma escolhida (vale o que foi digitado)
    FSuggestTyped: string;    // o que a pessoa digitou (volta ao sair da lista com as setas)
    FSuggestFilling: Boolean; // a barra está sendo preenchida pela lista, não pela pessoa
    FBtnStar: TNecoIconButton;
    FBookmarkBar: TNecoBookmarkBar;
    FProgressTrack: TLayout;
    FProgress: TRectangle;
    FProgressTimer: TTimer;
    FBody: TLayout;
    FPageArea: TLayout;
    FErrorView: TNecoErrorView;
    // painéis laterais (um aberto por vez)
    FPanelDownloads: TNecoDownloadsPanel;
    FPanelBookmarks: TNecoBookmarksPanel;
    FPanelSettings: TNecoSettingsPanel;
    FPanelHistory: TNecoHistoryPanel;
    // tela cheia: pedida pela página (vídeo) ou pelo F11
    FFullVideo, FFullKey, FFull: Boolean;

    procedure BuildUI;
    procedure BuildTabStrip;
    procedure BuildToolbar;
    procedure ApplyTheme;

    // faixa de abas
    procedure AttachFrame;
    function TitleHitTest(const APoint: TPointF): TNecoFrameHit;
    procedure LayoutTabStrip;
    procedure TabStripResized(Sender: TObject);
    procedure TabStripMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);
    procedure BuildTabButton(ATab: TNecoTab);
    procedure StyleTab(ATab: TNecoTab);
    procedure StyleTabs;
    procedure UpdateTabTitle(ATab: TNecoTab);
    /// Ícone do site na aba: o que o motor mandou ou, na aba ainda não carregada, o guardado.
    procedure UpdateTabIcon(ATab: TNecoTab);
    procedure MemoryClick(Sender: TObject);
    procedure ShowMemory(const AReport: TNecoMemoryReport);
    procedure TabButtonMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);
    procedure TabButtonHover(Sender: TObject);
    procedure TabButtonMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure TabButtonMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);
    function StripX(ASender: TObject; X, Y: Single): Single;
    procedure TabCloseClick(Sender: TObject);
    procedure NewTabClick(Sender: TObject);
    procedure MinClick(Sender: TObject);
    procedure MaxClick(Sender: TObject);
    procedure CloseWindowClick(Sender: TObject);
    procedure UpdateMaxButton;
    procedure FormResized(Sender: TObject);
    function StartUrl: string;
    function CmdLineUrl: string;
    /// Reabre as abas da última vez (as de fundo só carregam quando ativadas).
    function RestoreSession: Boolean;
    procedure SaveSession;
    procedure ReopenClosedTab;
    /// Abre outra janela do navegador, neste mesmo processo, na página inicial.
    procedure NewWindow;
    procedure TabFullScreen(Sender: TObject; AValue: Boolean);
    procedure ApplyFullScreen;
    procedure HistoryClick(Sender: TObject);
    procedure OpenFileClick(Sender: TObject);
    function FaviconDir: string;
    procedure StoreFavicon(ATab: TNecoTab);
    procedure BookmarkMove(Sender: TObject; AFrom, ATo: Integer);
    procedure HistoryClear(Sender: TObject);

    // abas
    /// AIndex < 0: no fim da faixa.
    /// ALazy: a aba só carrega a página quando for ativada.
    function NewTab(const AUrl: string; AActivate: Boolean = True; AIndex: Integer = -1;
      ALazy: Boolean = False): TNecoTab;
    procedure ActivateTab(ATab: TNecoTab);
    /// Troca de aba pelo teclado: ativa e põe o foco na página.
    procedure SwitchTab(ADelta: Integer);
    procedure SelectTab(AIndex: Integer);
    procedure CloseTab(ATab: TNecoTab);
    procedure TabChanged(Sender: TObject; AChange: TNecoTabChange);
    procedure TabNewWindow(Sender: TObject; const AUrl: string);
    procedure TabDownload(Sender: TObject; const ADownload: INecoDownload);
    procedure TabKey(Sender: TObject; AKey: Word; AShift: TShiftState; var AHandled: Boolean);
    procedure TabPageFocus(Sender: TObject);
    procedure TabNavigated(Sender: TObject; const AUrl: string);

    // estado da tela
    procedure UpdateNavButtons;
    procedure UpdateAddress;
    procedure UpdateProgress;
    procedure UpdateCaption;
    procedure UpdatePageMessage;
    procedure LayoutEngine;
    procedure PageAreaResized(Sender: TObject);
    procedure ProgressTick(Sender: TObject);

    // ações
    procedure BackClick(Sender: TObject);
    procedure ForwardClick(Sender: TObject);
    procedure ReloadClick(Sender: TObject);
    procedure AddressKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    procedure AddressEnter(Sender: TObject);
    procedure AddressExit(Sender: TObject);
    procedure AddressTyping(Sender: TObject);
    procedure FocusAddress;
    /// Abre o que está na barra (endereço ou busca) e guarda a busca para sugerir depois.
    procedure GoAddress;
    // sugestões da barra
    procedure BuildSuggest;
    procedure ShowSuggestions;
    procedure HideSuggestions;
    procedure MoveSuggestion(ADelta: Integer);
    procedure StyleSuggestRows;
    procedure SuggestRowClick(Sender: TObject);
    procedure SuggestRowEnter(Sender: TObject);
    // bloqueador
    function AddToolButton(const AIcon, AHint: string; AOnClick: TNotifyEvent): TNecoIconButton;
    procedure UpdateShield;
    procedure ShieldClick(Sender: TObject);
    // menu da seta
    procedure BuildMenu;
    procedure MenuClick(Sender: TObject);
    procedure ClearMenu;
    procedure AddMenuRow(ATag: Integer; const AIcon, AText, ARight: string; AIconColor: TAlphaColor;
      AMarked: Boolean);
    procedure OpenMenu;
    procedure HideMenu;
    // atualização automática (o app baixa; a janela avisa)
    procedure ShowUpdateNotice;
    procedure RefreshUpdateInfo;
    // navegador padrão do Windows
    procedure FormActivated(Sender: TObject);
    procedure RefreshDefaultBrowser;
    procedure MenuRowClick(Sender: TObject);
    procedure MenuRowHover(Sender: TObject);
    // painéis, downloads e favoritos
    procedure BuildPanels;
    procedure TogglePanel(APanel: TNecoSidePanel);
    procedure ShowPanel(APanel: TNecoSidePanel);
    procedure PanelCloseRequest(Sender: TObject);
    procedure UpdatePanelButtons;
    procedure BookmarksClick(Sender: TObject);
    procedure DownloadsClick(Sender: TObject);
    procedure DownloadFinished(Sender: TObject; ASuccess: Boolean);
    procedure UpdateStar;
    procedure StarClick(Sender: TObject);
    procedure ToggleBookmark;
    procedure BookmarkOpen(Sender: TObject; const AUrl: string; ANewTab: Boolean);
    procedure BookmarkDelete(Sender: TObject; const AUrl: string);
    procedure BookmarkRename(Sender: TObject; const AUrl, ATitle: string);
    procedure BookmarkEditRequest(Sender: TObject; const AUrl: string);
    /// Mostra ou esconde a barra de favoritos conforme Settings (a escolha já está gravada).
    procedure LayoutBookmarkBar;
    // tema, configurações e página de erro
    procedure ThemeClick(Sender: TObject);
    procedure SettingsClick(Sender: TObject);
    procedure SettingsChanged(Sender: TObject; AChange: TNecoSettingsChange);
    procedure ErrorRetry(Sender: TObject);
    // INecoWindow: avisos do app
    procedure AppSettingsChanged(AChange: TNecoSettingsChange);
    procedure AppBookmarksChanged;
    procedure AppFaviconsChanged;
    procedure AppHistoryChanged;
    procedure AppUpdateChanged(ANew: Boolean);
    procedure AppMemoryReport(const AReport: TNecoMemoryReport);
    function AppIsMinimized: Boolean;
    procedure SelfTestTick(Sender: TObject);
    /// Atalhos do teclado. Usado pelo form e pela página (via AcceleratorKey).
    function HandleShortcut(AKey: Word; AShift: TShiftState): Boolean;
    /// A ação do atalho (nil = não é atalho). Executar adiado: ver HandleShortcut.
    function ShortcutAction(AKey: Word; AShift: TShiftState): TProc;
  protected
    procedure DoScaleChanged; override;
  public
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
  end;

var
  FormMain: TFormMain;

implementation

uses
  System.IOUtils, System.Math,
  Neco.Core.Url, Neco.Core.Trace, Neco.Core.Favicons, Neco.Engine.Factory,
  Neco.UI.DefaultBrowser;

{$R *.fmx}

{ TFormMain }

procedure TFormMain.FormCreate(Sender: TObject);
begin
  NecoTrace('form criando');
  FTabs := TObjectList<TNecoTab>.Create(False);
  // Dados, tema, motor e trava de instância já foram preparados pelo app.
  FSettings := NecoApp.Settings;
  FBlocklist := NecoApp.Blocklist;
  FBookmarks := NecoApp.Bookmarks;
  FHistory := NecoApp.History;

  BuildUI;
  ApplyTheme;
  // A janela já existe aqui (o FMX cria o handle antes do OnCreate): a barra branca
  // some antes da primeira exibição.
  AttachFrame;
  NecoApp.RegisterWindow(Self);
  RefreshUpdateInfo;
  // Volta da tela "Aplicativos padrão" do Windows: a chave mostra o estado novo.
  OnActivate := FormActivated;
  RefreshDefaultBrowser;
end;

procedure TFormMain.FormShow(Sender: TObject);
var
  P: string;
begin
  // A primeira aba precisa do HWND do form, que só existe com a janela criada.
  if FStarted then
    Exit;
  FStarted := True;
  NecoTrace('form visivel');
  // O FMX pode recriar a janela ao exibir o form: religa a barra própria na janela final.
  AttachFrame;
  if not RestoreSession then
    NewTab(StartUrl);
  // Teste visual sem mexer no mouse: NECO_PAINEL=downloads|favoritos|config abre o painel.
  P := System.SysUtils.GetEnvironmentVariable('NECO_PAINEL');
  if SameText(P, 'downloads') then
    ShowPanel(FPanelDownloads)
  else if SameText(P, 'favoritos') then
    ShowPanel(FPanelBookmarks)
  else if SameText(P, 'config') then
    ShowPanel(FPanelSettings);
  if SameText(P, 'historico') then
    ShowPanel(FPanelHistory);
  // Teste de várias janelas sem teclado: NECO_TESTE_JANELA=1 abre a segunda (como o Ctrl+N).
  if not FExtraWindow and (System.SysUtils.GetEnvironmentVariable('NECO_TESTE_JANELA') = '1') then
    TThread.ForceQueue(nil, NewWindow);
  // Teste de memória: NECO_TESTE_ABAS=<n> [NECO_TESTE_CICLOS=<c>] (ver SelfTestTick).
  FSelfTestTabs := StrToIntDef(System.SysUtils.GetEnvironmentVariable('NECO_TESTE_ABAS'), 0);
  if FSelfTestTabs > 0 then
  begin
    FSelfTestCycles := StrToIntDef(System.SysUtils.GetEnvironmentVariable('NECO_TESTE_CICLOS'), 3);
    FSelfTest := TTimer.Create(Self);
    FSelfTest.Interval := 15000; // abertura assentada antes da primeira medida
    FSelfTest.OnTimer := SelfTestTick;
  end;
end;

function TFormMain.CmdLineUrl: string;
var
  I: Integer;
begin
  // NecoBrowser.exe <endereço ou busca>: abre isso no lugar da página inicial.
  Result := '';
  for I := 1 to ParamCount do
    if not ParamStr(I).StartsWith('-') then
    begin
      // "Abrir com" do Explorer passa o caminho do arquivo (às vezes relativo).
      if FileExists(ParamStr(I)) then
        Exit(NecoPathToFileUrl(ExpandFileName(ParamStr(I))));
      Result := NecoInputToUrl(ParamStr(I), FSettings.SearchEngine);
      if Result <> '' then
        Exit;
    end;
end;

function TFormMain.StartUrl: string;
begin
  Result := CmdLineUrl;
  if Result = '' then
    Result := FSettings.HomeUrl;
end;

function TFormMain.RestoreSession: Boolean;
var
  Urls: TArray<string>;
  Active, I: Integer;
begin
  Result := False;
  // Endereço na linha de comando e o teste de memória abrem só o que pediram.
  if FExtraWindow or not NecoApp.SessionOwner or not FSettings.RestoreSession or (CmdLineUrl <> '') or
    (System.SysUtils.GetEnvironmentVariable('NECO_TESTE_ABAS') <> '') then
    Exit;
  if not FSettings.LoadSession(Urls, Active) or (Length(Urls) = 0) then
    Exit;
  for I := 0 to High(Urls) do
    NewTab(Urls[I], False, -1, True);
  ActivateTab(FTabs[Min(Active, FTabs.Count - 1)]);
  NecoTrace(Format('sessao restaurada: %d abas', [Length(Urls)]));
  Result := True;
end;

procedure TFormMain.SaveSession;
var
  Urls: TArray<string>;
  T: TNecoTab;
begin
  // Segunda janela (ex.: "Abrir com" um PDF com o navegador já aberto) não apaga a
  // sessão da primeira. A janela do Ctrl+N também não (a sessão de várias janelas é da etapa 4).
  if FExtraWindow or not NecoApp.SessionOwner then
    Exit;
  Urls := nil;
  for T in FTabs do
    if (T.Url <> '') and not SameText(T.Url, 'about:blank') then
      Urls := Urls + [T.Url];
  try
    FSettings.SaveSession(Urls, Max(0, FTabs.IndexOf(FActive)));
  except
    // Falha de disco ao fechar não pode impedir o app de fechar.
  end;
end;

procedure TFormMain.ReopenClosedTab;
var
  U: string;
begin
  U := NecoApp.TakeClosedTab;
  if U <> '' then
    NewTab(U);
end;

procedure TFormMain.NewWindow;
var
  F: TFormMain;
begin
  if FShuttingDown or NecoApp.ShuttingDown then
    Exit;
  F := TFormMain.Create(Application);
  F.FExtraWindow := True;
  // Um pouco para o lado, para não cobrir esta inteira.
  F.SetBounds(Left + 40, Top + 40, Width, Height);
  F.Show;
end;

procedure TFormMain.FormClose(Sender: TObject; var Action: TCloseAction);
var
  T: TNecoTab;
  I: Integer;
begin
  if FShuttingDown then
    Exit;
  FShuttingDown := True;
  // Última janela: o app para os timers e downloads dele antes de os motores fecharem.
  if NecoApp.IsLastWindow(Self) then
    NecoApp.BeginShutdown
  else
  begin
    // Sobram outras: esta é destruída ao fechar. Se era a principal, passa o posto a
    // outra (o FMX encerra o app quando a principal fecha).
    Action := TCloseAction.caFree;
    if Application.MainForm = Self then
      for I := 0 to Screen.FormCount - 1 do
        if (Screen.Forms[I] <> Self) and (Screen.Forms[I] is TFormMain) and
          not TFormMain(Screen.Forms[I]).FShuttingDown then
        begin
          Application.MainForm := Screen.Forms[I];
          Break;
        end;
  end;
  // A janela ainda recebe mensagens até ser destruída: solta os callbacks da barra
  // antes de liberar o que eles consultam.
  NecoFrameDetach(Self);
  FStage.Stop;
  if FSelfTest <> nil then
    FSelfTest.Enabled := False;
  FProgressTimer.Enabled := False;
  HideSuggestions;
  FPanelDownloads.Shutdown;
  if FFull then
    NecoFrameSetFullScreen(Self, False);
  SaveSession;
  // Os motores desta janela fecham com ela ainda viva.
  for T in FTabs do
    T.Close;
  FActive := nil;
  for T in FTabs do
    T.Free;
  FTabs.Clear;
  // Última janela: o app grava os dados, fecha o ambiente do motor e aplica a atualização.
  NecoApp.UnregisterWindow(Self);
  FSettings := nil;
  FBlocklist := nil;
  FBookmarks := nil;
  FHistory := nil;
  FreeAndNil(FTabs);
  FreeAndNil(FSuggestRows); // só a lista: as linhas são do form
end;

{ Montagem da tela }

procedure TFormMain.BuildUI;
begin
  Caption := 'NecoBrowser';
  Width := 1280;
  Height := 820;
  OnResize := FormResized;

  FTabStrip := TRectangle.Create(Self);
  FTabStrip.Parent := Self;
  FTabStrip.Align := TAlignLayout.Top;
  FTabStrip.Height := CTabStripHeight;
  FTabStrip.Stroke.Kind := TBrushKind.None;
  FTabStrip.Position.Y := 0;
  BuildTabStrip;

  FToolbar := TRectangle.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Align := TAlignLayout.Top;
  FToolbar.Height := CToolbarHeight;
  FToolbar.Stroke.Kind := TBrushKind.None;
  FToolbar.Position.Y := 100;
  BuildToolbar;
  BuildSuggest;

  FBookmarkBar := TNecoBookmarkBar.Create(Self);
  FBookmarkBar.Parent := Self;
  FBookmarkBar.Position.Y := 500;
  FBookmarkBar.Align := TAlignLayout.Top;
  FBookmarkBar.Bookmarks := FBookmarks;
  FBookmarkBar.OnOpen := BookmarkOpen;
  FBookmarkBar.OnEdit := BookmarkEditRequest;
  FBookmarkBar.OnMore := BookmarksClick;
  FBookmarkBar.OnMove := BookmarkMove;
  FBookmarkBar.FaviconDir := FaviconDir;
  FBookmarkBar.Visible := FSettings.ShowBookmarkBar;
  FBookmarkBar.Rebuild;

  FProgressTrack := TLayout.Create(Self);
  FProgressTrack.Parent := Self;
  FProgressTrack.Align := TAlignLayout.Top;
  FProgressTrack.Height := 2;
  FProgressTrack.Position.Y := 1000;
  FProgress := TRectangle.Create(Self);
  FProgress.Parent := FProgressTrack;
  FProgress.Align := TAlignLayout.Left;
  FProgress.Stroke.Kind := TBrushKind.None;
  FProgress.HitTest := False;
  FProgress.Width := 0;
  FProgress.Visible := False;
  FProgressTimer := TTimer.Create(Self);
  FProgressTimer.Enabled := False;
  FProgressTimer.Interval := 120;
  FProgressTimer.OnTimer := ProgressTick;

  FBody := TLayout.Create(Self);
  FBody.Parent := Self;
  FBody.Align := TAlignLayout.Client;

  FPageArea := TLayout.Create(Self);
  FPageArea.Parent := FBody;
  FPageArea.Align := TAlignLayout.Client;
  FPageArea.OnResized := PageAreaResized;

  // Página de erro: cobre a área da página (o motor fica escondido enquanto ela aparece).
  FErrorView := TNecoErrorView.Create(Self);
  FErrorView.Parent := FPageArea;
  FErrorView.Align := TAlignLayout.Contents;
  FErrorView.Visible := False;
  FErrorView.OnRetry := ErrorRetry;

  BuildPanels;
end;

procedure TFormMain.BuildTabStrip;

  function CaptionButton(const AIcon, AHint: string; AOnClick: TNotifyEvent): TNecoIconButton;
  begin
    Result := NecoNewButton(Self, FTabStrip, AIcon, AHint, AOnClick);
    Result.XRadius := 0;
    Result.YRadius := 0;
    Result.Width := CCaptionButtonWidth;
    Result.Height := CCaptionButtonHeight;
    Result.IconSize := 10;
    Result.Icon.Stroke.Thickness := 1;
    Result.Icon.Stroke.Cap := TStrokeCap.Flat;
    Result.Icon.Stroke.Join := TStrokeJoin.Miter;
  end;

begin
  // Posições calculadas em LayoutTabStrip (abas, "+", assento da Neco, botões da janela).
  FTabStrip.ClipChildren := True;
  FTabStrip.OnResized := TabStripResized;
  FTabStrip.OnMouseDown := TabStripMouseDown;

  FBtnNewTab := NecoNewButton(Self, FTabStrip, ICO_MAIS, 'Nova aba (Ctrl+T)', NewTabClick);
  FBtnNewTab.Width := 28;
  FBtnNewTab.Height := 28;
  FBtnNewTab.XRadius := 14;
  FBtnNewTab.YRadius := 14;
  FBtnNewTab.IconSize := 16;

  FBtnMin := CaptionButton(ICO_JANELA_MINIMIZAR, 'Minimizar', MinClick);
  FBtnMax := CaptionButton(ICO_JANELA_MAXIMIZAR, 'Maximizar', MaxClick);
  FBtnClose := CaptionButton(ICO_JANELA_FECHAR, 'Fechar', CloseWindowClick);
  FBtnClose.HoverColor := CCloseHover;
  FBtnClose.PressedColor := CCloseHoverPressed;
  FBtnClose.HoverIconColor := TAlphaColors.White;

  // A Neco por cima de tudo na faixa; não recebe clique (as abas continuam clicáveis).
  FStage := TNecoStage.Create(Self);
  FStage.Parent := FTabStrip;
  FStage.Align := TAlignLayout.Contents;
  FStage.CanAnimate :=
    function: Boolean
    begin
      Result := not FShuttingDown and not NecoFrameIsMinimized(Self);
    end;
  FStage.CanSchedule :=
    function: Boolean
    begin
      Result := NecoFrameIsForeground(Self);
    end;
end;

procedure TFormMain.AttachFrame;
begin
  NecoFrameAttach(Self, CTabStripHeight, TitleHitTest,
    procedure(AHot: Boolean)
    begin
      if FBtnMax <> nil then
        FBtnMax.Hot := AHot;
    end,
    procedure
    begin
      // Vem de dentro do WndProc: a troca de estado roda depois.
      TThread.ForceQueue(nil,
        procedure
        begin
          if not FShuttingDown then
            NecoFrameToggleMaximize(Self);
        end);
    end);
  UpdateMaxButton;
end;

function TFormMain.TitleHitTest(const APoint: TPointF): TNecoFrameHit;

  function Over(AControl: TControl): Boolean;
  begin
    Result := (AControl <> nil) and AControl.Visible and AControl.AbsoluteRect.Contains(APoint);
  end;

var
  T: TNecoTab;
begin
  Result := fhCaption;
  if FShuttingDown or (FTabs = nil) then
    Exit;
  if Over(FBtnMax) then
    Exit(fhMaxButton);
  if Over(FBtnMin) or Over(FBtnClose) or Over(FBtnNewTab) then
    Exit(fhClient);
  for T in FTabs do
    if Over(T.Button) then
      Exit(fhClient);
  // Em cima da Neco: o clique é dela (ela ri). No resto, arrasta a janela.
  if FStage.HitActor(FStage.AbsoluteToLocal(APoint)) then
    Exit(fhClient);
end;

procedure TFormMain.LayoutTabStrip;
var
  W, Right, Avail, TabW, X: Single;
  T: TNecoTab;
begin
  if FTabStrip = nil then
    Exit;
  W := FTabStrip.Width;
  Right := W - 3 * CCaptionButtonWidth;
  FBtnMin.SetBounds(Right, 0, CCaptionButtonWidth, CCaptionButtonHeight);
  FBtnMax.SetBounds(Right + CCaptionButtonWidth, 0, CCaptionButtonWidth, CCaptionButtonHeight);
  FBtnClose.SetBounds(Right + 2 * CCaptionButtonWidth, 0, CCaptionButtonWidth, CCaptionButtonHeight);

  // As abas dividem o espaço até o "+", que fica colado na última; o assento da Neco
  // é reservado sempre (também é área de arrastar a janela).
  Avail := Right - CNecoSeatWidth - 8 - (FBtnNewTab.Width + 12);
  TabW := CTabMaxWidth;
  if FTabs.Count > 0 then
    TabW := Max(CTabMinWidth, Min(CTabMaxWidth, Avail / FTabs.Count));
  FTabW := TabW;
  X := 8;
  for T in FTabs do
    if T.Button <> nil then
    begin
      // A aba arrastada segue o mouse; as outras vão para as vagas.
      if FDragging and (T = FDragTab) then
        T.Button.SetBounds(T.Button.Position.X, CTabTop, TabW, CTabHeight)
      else
        T.Button.SetBounds(X, CTabTop, TabW, CTabHeight);
      X := X + TabW;
    end;
  FBtnNewTab.SetBounds(X + 6, CTabTop + (CTabHeight - FBtnNewTab.Height) / 2,
    FBtnNewTab.Width, FBtnNewTab.Height);
  FStage.SeatX := Right - CNecoSeatWidth / 2;
  FStage.BringToFront;
end;

procedure TFormMain.TabStripResized(Sender: TObject);
begin
  LayoutTabStrip;
end;

procedure TFormMain.TabStripMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
begin
  // Só chega aqui o clique que o TitleHitTest deixou como "cliente": o da Neco.
  if (Button = TMouseButton.mbLeft) and
    FStage.HitActor(FStage.AbsoluteToLocal(FTabStrip.LocalToAbsolute(TPointF.Create(X, Y)))) then
    FStage.Poke;
end;

procedure TFormMain.BuildTabButton(ATab: TNecoTab);
var
  B: TRectangle;
  X: TNecoIconButton;
begin
  B := TRectangle.Create(Self);
  B.Parent := FTabStrip;
  B.Corners := [TCorner.TopLeft, TCorner.TopRight];
  B.XRadius := 8;
  B.YRadius := 8;
  B.Stroke.Kind := TBrushKind.None;
  B.Fill.Kind := TBrushKind.Solid;
  B.HitTest := True;
  // Com o botão apertado, o mouse continua sendo da aba fora dela: o arrasto para fora da
  // faixa e o soltar em qualquer lugar chegam aqui.
  B.AutoCapture := True;
  B.TagObject := ATab;
  B.OnMouseDown := TabButtonMouseDown;
  B.OnMouseMove := TabButtonMouseMove;
  B.OnMouseUp := TabButtonMouseUp;
  B.OnMouseEnter := TabButtonHover;
  B.OnMouseLeave := TabButtonHover;
  B.Height := CTabHeight;
  B.Width := CTabMaxWidth;

  X := NecoNewButton(Self, B, ICO_FECHAR, 'Fechar aba (Ctrl+W)', TabCloseClick);
  X.Align := TAlignLayout.Right;
  X.Width := 20;
  X.Margins.Rect := TRectF.Create(0, (CTabHeight - 20) / 2, 8, (CTabHeight - 20) / 2);
  X.XRadius := 10;
  X.YRadius := 10;
  X.IconSize := 12;
  X.TagObject := ATab;

  // Ícone do site, como nas pílulas dos favoritos (16x16, à esquerda do título).
  ATab.Icon := TImage.Create(Self);
  ATab.Icon.Parent := B;
  ATab.Icon.Align := TAlignLayout.Left;
  ATab.Icon.Width := 16;
  ATab.Icon.Margins.Rect := TRectF.Create(12, (CTabHeight - 16) / 2, 0, (CTabHeight - 16) / 2);
  ATab.Icon.WrapMode := TImageWrapMode.Fit;
  ATab.Icon.HitTest := False;
  ATab.Icon.Visible := False;

  ATab.TitleLabel := NecoNewLabel(Self, B, '', 12.5);
  ATab.TitleLabel.Align := TAlignLayout.Client;
  ATab.TitleLabel.Margins.Rect := TRectF.Create(12, 0, 4, 0);
  ATab.Button := B;
  ATab.CloseButton := X;
  UpdateTabTitle(ATab);
  UpdateTabIcon(ATab);
end;

procedure TFormMain.StyleTab(ATab: TNecoTab);
begin
  if (ATab = nil) or (ATab.Button = nil) then
    Exit;
  if ATab = FActive then
    ATab.Button.Fill.Color := Palette.Toolbar
  else if ATab.Button.IsMouseOver then
    ATab.Button.Fill.Color := Palette.TabHover
  else
    ATab.Button.Fill.Color := TAlphaColors.Null;
  if ATab = FActive then
    ATab.TitleLabel.TextSettings.FontColor := Palette.Text
  else
    ATab.TitleLabel.TextSettings.FontColor := Palette.TextMuted;
  TNecoIconButton(ATab.CloseButton).Restyle;
end;

procedure TFormMain.StyleTabs;
var
  T: TNecoTab;
begin
  for T in FTabs do
    StyleTab(T);
end;

function NecoFormatBytes(ABytes: UInt64): string;
var
  MB: Double;
begin
  MB := ABytes / (1024 * 1024);
  if MB >= 1000 then
    Result := FormatFloat('0.0', MB / 1024) + ' GB'
  else
    Result := FormatFloat('0', MB) + ' MB';
end;

procedure TFormMain.UpdateTabTitle(ATab: TNecoTab);
var
  H: string;
begin
  if (ATab = nil) or (ATab.TitleLabel = nil) then
    Exit;
  ATab.TitleLabel.Text := ATab.DisplayTitle;
  H := ATab.DisplayTitle;
  if ATab.MemoryBytes > 0 then
  begin
    H := H + sLineBreak + 'Memória: ' + NecoFormatBytes(ATab.MemoryBytes);
    if ATab.MemoryShared > 1 then
      H := H + Format(' (processo dividido com %d abas do mesmo site)', [ATab.MemoryShared]);
  end;
  ATab.Button.Hint := H;
  ATab.Button.ShowHint := True;
end;

procedure TFormMain.UpdateTabIcon(ATab: TNecoTab);
var
  S: TBytesStream;
  F: string;
  Ok: Boolean;
begin
  if (ATab = nil) or (ATab.Icon = nil) then
    Exit;
  Ok := False;
  try
    if Length(ATab.Favicon) > 0 then
    begin
      S := TBytesStream.Create(ATab.Favicon);
      try
        ATab.Icon.Bitmap.LoadFromStream(S);
        Ok := True;
      finally
        S.Free;
      end;
    end
    else if ATab.IsLazy then
    begin
      // Aba restaurada que ainda não carregou: usa o ícone guardado (sites dos favoritos).
      F := NecoFaviconFile(FaviconDir, ATab.Url);
      if (F <> '') and FileExists(F) then
      begin
        ATab.Icon.Bitmap.LoadFromFile(F);
        Ok := True;
      end;
    end;
  except
    Ok := False; // PNG estragado: fica sem ícone
  end;
  ATab.Icon.Visible := Ok;
  if Ok then
    ATab.TitleLabel.Margins.Left := 8
  else
    ATab.TitleLabel.Margins.Left := 12;
end;

procedure TFormMain.ShowMemory(const AReport: TNecoMemoryReport);
var
  T: TNecoTab;
  I: Integer;
  H: string;
begin
  FBtnMemory.CaptionText := NecoFormatBytes(AReport.Total);
  H := 'Memória do NecoBrowser: ' + NecoFormatBytes(AReport.Total) + ' no total' + sLineBreak +
    '  Páginas: ' + NecoFormatBytes(AReport.Pages) + sLineBreak +
    '  Motor (Gerenciador WebView2): ' + NecoFormatBytes(AReport.Browser) + sLineBreak +
    '  Vídeo (GPU): ' + NecoFormatBytes(AReport.Gpu) + sLineBreak +
    '  Rede, áudio e outros: ' + NecoFormatBytes(AReport.Other) + sLineBreak +
    '  Janela do navegador: ' + NecoFormatBytes(AReport.App) + sLineBreak +
    Format('%d processos. Passe o mouse numa aba para ver a dela; ' +
      'clique aqui para ver página por página.', [AReport.Processes]);
  FBtnMemory.Hint := H;

  // Memória por aba, no balão de cada uma.
  for T in FTabs do
  begin
    T.MemoryBytes := 0;
    T.MemoryShared := 1;
    for I := 0 to High(AReport.Tabs) do
      if AReport.Tabs[I].Engine = T.Engine then
      begin
        T.MemoryBytes := AReport.Tabs[I].Bytes;
        T.MemoryShared := AReport.Tabs[I].SharedWith;
        Break;
      end;
    UpdateTabTitle(T);
  end;
end;

procedure TFormMain.MemoryClick(Sender: TObject);
begin
  if (FActive <> nil) and (FActive.Engine <> nil) then
    FActive.Engine.OpenTaskManager;
end;

procedure TFormMain.TabButtonMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
var
  T: TNecoTab;
begin
  T := TNecoTab(TFmxObject(Sender).TagObject);
  if FTabs.IndexOf(T) < 0 then
    Exit;
  if Button = TMouseButton.mbLeft then
  begin
    if T <> FActive then
      ActivateTab(T);
    // Pode virar arrasto (TabButtonMouseMove) se o mouse andar mais que uns pixels.
    FDragTab := T;
    FDragging := False;
    FDragStartX := StripX(Sender, X, Y);
    FDragGrabX := FDragStartX - T.Button.Position.X;
  end
  else if Button = TMouseButton.mbMiddle then
    // Fechar libera esta aba (e este retângulo): depois do clique (regra 5.3).
    TThread.ForceQueue(nil,
      procedure
      begin
        if not FShuttingDown then
          CloseTab(T);
      end);
end;

function TFormMain.StripX(ASender: TObject; X, Y: Single): Single;
begin
  Result := FTabStrip.AbsoluteToLocal(TControl(ASender).LocalToAbsolute(TPointF.Create(X, Y))).X;
end;

procedure TFormMain.TabButtonMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
var
  B: TRectangle;
  P, NewX, MaxX: Single;
  Cur, Idx: Integer;
begin
  if (FDragTab = nil) or (Sender <> FDragTab.Button) or not (ssLeft in Shift) then
    Exit;
  B := FDragTab.Button;
  P := StripX(Sender, X, Y);
  if not FDragging then
  begin
    if Abs(P - FDragStartX) < 6 then
      Exit; // clique comum, não arrasto
    FDragging := True;
    B.BringToFront;
    FStage.BringToFront;
  end;
  // Segue o mouse, presa entre a primeira e a última vaga.
  MaxX := 8 + (FTabs.Count - 1) * FTabW;
  NewX := Max(8, Min(MaxX, P - FDragGrabX));
  B.Position.X := NewX;
  // Passou do meio da vaga vizinha: troca de lugar na lista.
  Cur := FTabs.IndexOf(FDragTab);
  Idx := EnsureRange(Round((NewX - 8) / FTabW), 0, FTabs.Count - 1);
  if Idx <> Cur then
  begin
    FTabs.Move(Cur, Idx);
    LayoutTabStrip;
  end;
end;

procedure TFormMain.TabButtonMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  FDragTab := nil;
  if FDragging then
  begin
    FDragging := False;
    LayoutTabStrip; // encaixa na vaga
  end;
end;

procedure TFormMain.TabButtonHover(Sender: TObject);
begin
  StyleTab(TNecoTab(TFmxObject(Sender).TagObject));
end;

procedure TFormMain.TabCloseClick(Sender: TObject);
var
  T: TNecoTab;
begin
  T := TNecoTab(TFmxObject(Sender).TagObject);
  // O X é filho da aba: liberar aqui dentro derrubaria o botão no meio do próprio clique.
  TThread.ForceQueue(nil,
    procedure
    begin
      if not FShuttingDown then
        CloseTab(T);
    end);
end;

procedure TFormMain.NewTabClick(Sender: TObject);
begin
  NewTab(FSettings.HomeUrl);
end;

procedure TFormMain.MinClick(Sender: TObject);
begin
  NecoFrameMinimize(Self);
end;

procedure TFormMain.MaxClick(Sender: TObject);
begin
  // Normalmente o clique no maximizar chega pelo Windows (HTMAXBUTTON). Este caminho
  // cobre o caso de o FMX receber o clique (ex.: teclado ou acessibilidade).
  NecoFrameToggleMaximize(Self);
end;

procedure TFormMain.CloseWindowClick(Sender: TObject);
begin
  TThread.ForceQueue(nil,
    procedure
    begin
      if not FShuttingDown then
        Close;
    end);
end;

procedure TFormMain.UpdateMaxButton;
begin
  if FBtnMax = nil then
    Exit;
  if NecoFrameIsMaximized(Self) then
  begin
    FBtnMax.IconData := ICO_JANELA_RESTAURAR;
    FBtnMax.Hint := 'Restaurar';
  end
  else
  begin
    FBtnMax.IconData := ICO_JANELA_MAXIMIZAR;
    FBtnMax.Hint := 'Maximizar';
  end;
end;

procedure TFormMain.FormResized(Sender: TObject);
begin
  UpdateMaxButton;
end;

procedure TFormMain.BuildToolbar;
var
  Left: TLayout;
begin
  Left := TLayout.Create(Self);
  Left.Parent := FToolbar;
  Left.Align := TAlignLayout.Left;
  Left.Width := 3 * (CButtonSize + 4) + 8;
  Left.Padding.Rect := TRectF.Create(8, 6, 0, 6);

  FBtnBack := NecoNewButton(Self, Left, ICO_VOLTAR, 'Voltar (Alt+←)', BackClick);
  FBtnBack.Align := TAlignLayout.Left;
  FBtnBack.Margins.Right := 4;
  FBtnBack.Position.X := 0;
  FBtnForward := NecoNewButton(Self, Left, ICO_SETA, 'Avançar (Alt+→)', ForwardClick);
  FBtnForward.Align := TAlignLayout.Left;
  FBtnForward.Margins.Right := 4;
  FBtnForward.Position.X := 100;
  FBtnReload := NecoNewButton(Self, Left, ICO_RECARREGAR, 'Recarregar (F5)', ReloadClick);
  FBtnReload.Align := TAlignLayout.Left;
  FBtnReload.Position.X := 200;

  // Botões da direita: um contêiner só (Align=Right entre irmãos ordena mal; ver skill),
  // com os botões em Align=Left na ordem de criação. AddToolButton recalcula a largura.
  FToolRight := TLayout.Create(Self);
  FToolRight.Parent := FToolbar;
  FToolRight.Align := TAlignLayout.Right;
  FToolRight.Padding.Rect := TRectF.Create(0, 6, 8, 6);
  FToolRight.Width := 8;

  // Medidor de memória: botão largo com texto, antes dos de ícone.
  FBtnMemory := NecoNewButton(Self, FToolRight, ICO_MEMORIA, '', MemoryClick);
  FBtnMemory.Align := TAlignLayout.Left;
  FBtnMemory.Margins.Left := 2;
  FBtnMemory.Position.X := FToolRight.Width;
  FBtnMemory.Width := 96;
  FBtnMemory.IconSize := 16;
  FBtnMemory.CaptionText := '… MB';
  FBtnMemory.Hint := 'Memória do NecoBrowser (medindo...)';
  FBtnMemory.ShowHint := True;
  FToolRight.Width := FToolRight.Width + FBtnMemory.Width + 2;
  // A medição é do app (AppMemoryReport): uma só para todas as janelas.

  // Bloqueador, favoritos, histórico, downloads, abrir arquivo e tema ficam no menu da seta.
  FBtnMenu := AddToolButton(ICO_SETA_BAIXO, 'Mais opções', MenuClick);
  // Selo com o número de bloqueados, no canto da seta (como os selos de extensão do Chrome).
  FShieldBadge := TRectangle.Create(Self);
  FShieldBadge.Parent := FBtnMenu;
  FShieldBadge.HitTest := False;
  FShieldBadge.Stroke.Kind := TBrushKind.None;
  FShieldBadge.XRadius := 6;
  FShieldBadge.YRadius := 6;
  FShieldBadge.Visible := False;
  FShieldBadgeText := NecoNewLabel(Self, FShieldBadge, '', 9);
  FShieldBadgeText.Align := TAlignLayout.Client;
  FShieldBadgeText.TextSettings.HorzAlign := TTextAlign.Center;
  FShieldBadgeText.TextSettings.Font.Style := [TFontStyle.fsBold];
  FShieldBadgeText.TextSettings.Trimming := TTextTrimming.None;
  // Bolinha no canto de cima da seta: versão nova pronta (o item fica no menu).
  FUpdateDot := TCircle.Create(Self);
  FUpdateDot.Parent := FBtnMenu;
  FUpdateDot.HitTest := False;
  FUpdateDot.Stroke.Kind := TBrushKind.None;
  FUpdateDot.SetBounds(CButtonSize - 11, 3, 8, 8);
  FUpdateDot.Visible := False;
  FBtnSettings := AddToolButton(ICO_AJUSTES, 'Configurações', SettingsClick);
  BuildMenu;

  FAddressBox := TRectangle.Create(Self);
  FAddressBox.Parent := FToolbar;
  FAddressBox.Align := TAlignLayout.Client;
  FAddressBox.Margins.Rect := TRectF.Create(8, 7, 6, 7);
  FAddressBox.XRadius := 16;
  FAddressBox.YRadius := 16;
  FAddressBox.Stroke.Thickness := 1;
  FAddressBox.HitTest := False;

  FAddressIcon := FMX.Objects.TPath.Create(Self);
  FAddressIcon.Parent := FAddressBox;
  FAddressIcon.Align := TAlignLayout.Left;
  FAddressIcon.Width := 14;
  FAddressIcon.Margins.Rect := TRectF.Create(12, 9, 6, 9);
  FAddressIcon.WrapMode := TPathWrapMode.Fit;
  FAddressIcon.Stroke.Thickness := 1.8;
  FAddressIcon.Stroke.Cap := TStrokeCap.Round;
  FAddressIcon.Stroke.Join := TStrokeJoin.Round;
  FAddressIcon.Fill.Kind := TBrushKind.None;
  FAddressIcon.HitTest := False;
  FAddressIcon.Data.Data := ICO_GLOBO;

  FAddress := TEdit.Create(Self);
  FAddress.Parent := FAddressBox;
  FAddress.Align := TAlignLayout.Client;
  FAddress.Margins.Right := 10;
  FAddress.StyleLookup := 'transparentedit';
  FAddress.StyledSettings := [];
  FAddress.TextSettings.Font.Size := 14;
  FAddress.TextPrompt := 'Pesquise ou digite um endereço';
  FAddress.KillFocusByReturn := False;
  FAddress.OnKeyDown := AddressKeyDown;
  FAddress.OnEnter := AddressEnter;
  FAddress.OnExit := AddressExit;
  FAddress.OnChangeTracking := AddressTyping;

  FBtnStar := NecoNewButton(Self, FAddressBox, ICO_ESTRELA, 'Favoritar esta página (Ctrl+D)', StarClick);
  FBtnStar.Align := TAlignLayout.Right;
  FBtnStar.Width := 28;
  FBtnStar.Height := 28;
  FBtnStar.XRadius := 14;
  FBtnStar.YRadius := 14;
  FBtnStar.IconSize := 16;
  FBtnStar.Margins.Rect := TRectF.Create(0, 2, 3, 2);
end;

procedure TFormMain.ApplyTheme;
begin
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := Palette.Window;
  FTabStrip.Fill.Color := Palette.Window;
  FBtnNewTab.Restyle;
  FBtnMin.Restyle;
  FBtnMax.Restyle;
  FBtnClose.Restyle;
  StyleTabs;
  FToolbar.Fill.Color := Palette.Toolbar;
  FAddressBox.Fill.Color := Palette.Field;
  if FAddress.IsFocused then
    FAddressBox.Stroke.Color := Palette.Focus
  else
    FAddressBox.Stroke.Color := Palette.FieldBorder;
  FAddressIcon.Stroke.Color := Palette.TextMuted;
  FAddress.TextSettings.FontColor := Palette.Text;
  FProgress.Fill.Color := Palette.Accent;
  FErrorView.Restyle;
  FBtnBack.Restyle;
  FBtnForward.Restyle;
  FBtnReload.Restyle;
  FBtnMemory.Restyle;
  UpdateShield;
  FBtnMenu.Restyle;
  FBtnSettings.Restyle;
  HideMenu; // as linhas pegam a cor na montagem; reabre já com o tema novo
  UpdatePanelButtons;
  UpdateStar;
  FPanelDownloads.Restyle;
  FPanelBookmarks.Restyle;
  FPanelSettings.Restyle;
  FPanelHistory.Restyle;
  if FPanelHistory.Visible then
    FPanelHistory.Rebuild; // as linhas pegam a cor na montagem
  FBookmarkBar.Restyle;
  FBookmarkBar.Rebuild; // as estrelas pegam a cor na montagem
end;

{ Abas }

function TFormMain.NewTab(const AUrl: string; AActivate: Boolean; AIndex: Integer;
  ALazy: Boolean): TNecoTab;
begin
  // A chave do bloqueador é do app: a aba pode mudar de janela.
  Result := TNecoTab.Create(Self, FBlocklist, NecoApp.BlockerOn);
  Result.OnChanged := TabChanged;
  Result.OnNewWindow := TabNewWindow;
  Result.OnDownload := TabDownload;
  Result.OnKey := TabKey;
  Result.OnPageFocus := TabPageFocus;
  Result.OnNavigated := TabNavigated;
  Result.OnFullScreen := TabFullScreen;
  if ALazy then
    Result.SetLazy(AUrl); // antes do botão: o título já sai com o site
  Result.Engine.SetDarkMode(CurrentTheme = ntDark);
  Result.Engine.SetAutofill(FSettings.FormAutofill, FSettings.SavePasswords);
  Result.Engine.SetVisible(False);
  if (AIndex >= 0) and (AIndex < FTabs.Count) then
    FTabs.Insert(AIndex, Result)
  else
    FTabs.Add(Result);
  BuildTabButton(Result);
  LayoutTabStrip;
  if AActivate or ((FActive = nil) and not ALazy) then
    ActivateTab(Result)
  else
    StyleTab(Result);
  if not ALazy then
    Result.Navigate(AUrl);
end;

procedure TFormMain.ActivateTab(ATab: TNecoTab);
var
  T: TNecoTab;
begin
  // Vídeo em tela cheia é da aba que o pediu: trocar de aba sai dela.
  if FFullVideo and (ATab <> FActive) then
  begin
    FFullVideo := False;
    ApplyFullScreen;
  end;
  FActive := ATab;
  if (ATab <> nil) and ATab.IsLazy then
    ATab.LoadLazy;
  for T in FTabs do
    if T <> ATab then
      T.Engine.SetVisible(False);
  if ATab <> nil then
  begin
    LayoutEngine;
    ATab.Engine.SetVisible(not ATab.HasErrorPage);
  end;
  StyleTabs;
  FStage.Loading := (ATab <> nil) and ATab.Loading;
  UpdateNavButtons;
  UpdateAddress;
  UpdateProgress;
  UpdateCaption;
  UpdatePageMessage;
  UpdateShield;
  UpdateStar;
end;

procedure TFormMain.SwitchTab(ADelta: Integer);
var
  I: Integer;
begin
  if FTabs.Count < 2 then
    Exit;
  I := FTabs.IndexOf(FActive);
  I := (I + ADelta + FTabs.Count) mod FTabs.Count;
  SelectTab(I);
end;

procedure TFormMain.SelectTab(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= FTabs.Count) then
    Exit;
  if FTabs[AIndex] <> FActive then
    ActivateTab(FTabs[AIndex]);
  // A página que tinha o foco ficou escondida: o teclado vai para a nova.
  if FAddress.IsFocused then
    FAddress.ResetFocus;
  FActive.Engine.Focus;
end;

procedure TFormMain.CloseTab(ATab: TNecoTab);
var
  I: Integer;
  B: TRectangle;
  WasActive: Boolean;
begin
  I := FTabs.IndexOf(ATab);
  if I < 0 then
    Exit;
  WasActive := ATab = FActive;
  if not FShuttingDown then
    NecoApp.AddClosedTab(ATab.Url);
  if FDragTab = ATab then
  begin
    FDragTab := nil;
    FDragging := False;
  end;
  ATab.Close;
  FTabs.Delete(I);
  // A aba na faixa (o X e o título são filhos dela e vão junto). Quem chama já está
  // fora de qualquer evento desses controles (ForceQueue).
  B := ATab.Button;
  ATab.Button := nil;
  ATab.Icon := nil;
  ATab.TitleLabel := nil;
  ATab.CloseButton := nil;
  B.Free;
  LayoutTabStrip;
  if FActive = ATab then
  begin
    FActive := nil;
    if FTabs.Count > 0 then
      ActivateTab(FTabs[Min(I, FTabs.Count - 1)]);
  end;
  ATab.Free;
  if FTabs.Count = 0 then
    NewTab(FSettings.HomeUrl)
  else if WasActive and not FAddress.IsFocused then
    // A página fechada tinha o teclado: ele passa para a aba que assumiu.
    FActive.Engine.Focus;
end;

procedure TFormMain.TabChanged(Sender: TObject; AChange: TNecoTabChange);
begin
  // O título aparece na faixa para todas as abas, não só a ativa.
  if AChange = tcFavicon then
  begin
    UpdateTabIcon(TNecoTab(Sender));
    StoreFavicon(TNecoTab(Sender));
  end;
  if AChange = tcTitle then
  begin
    UpdateTabTitle(TNecoTab(Sender));
    // A visita entra no histórico antes do título chegar: completa aqui.
    if TNecoTab(Sender).Title <> '' then
      FHistory.UpdateTitle(TNecoTab(Sender).Url, TNecoTab(Sender).Title);
  end;
  if Sender <> FActive then
    Exit;
  case AChange of
    tcTitle:
      UpdateCaption;
    tcUrl:
      begin
        UpdateAddress;
        UpdateStar;
      end;
    tcLoading:
      begin
        UpdateProgress;
        UpdateNavButtons;
        FStage.Loading := FActive.Loading;
        // Página carregou com anúncios barrados: a Neco comemora (no máximo 1x por minuto).
        if not FActive.Loading and (FActive.BlockedCount > 0) then
          FStage.Celebrate;
      end;
    tcHistory:
      UpdateNavButtons;
    tcBlocked:
      UpdateShield;
    tcError:
      begin
        UpdateProgress;
        UpdatePageMessage;
      end;
  end;
end;

procedure TFormMain.TabNewWindow(Sender: TObject; const AUrl: string);
var
  Opener: TNecoTab;
begin
  // Pop-up e target=_blank: aba nova logo depois da que pediu, como no Chrome.
  // Vem de dentro do callback do motor da aba de origem: a troca de aba roda depois.
  Opener := TNecoTab(Sender);
  TThread.ForceQueue(nil,
    procedure
    var
      I: Integer;
    begin
      if FShuttingDown then
        Exit;
      I := FTabs.IndexOf(Opener);
      if I >= 0 then
        NewTab(AUrl, True, I + 1)
      else
        NewTab(AUrl);
    end);
end;

procedure TFormMain.TabDownload(Sender: TObject; const ADownload: INecoDownload);
begin
  // Vem de dentro do callback do motor: só acrescenta a linha (nada é liberado aqui).
  FPanelDownloads.Add(ADownload);
  if not FPanelDownloads.Visible then
    ShowPanel(FPanelDownloads);
end;

procedure TFormMain.TabKey(Sender: TObject; AKey: Word; AShift: TShiftState; var AHandled: Boolean);
begin
  // Vem de dentro de um callback do motor: a ação roda depois (regra 5.3).
  if not HandleShortcut(AKey, AShift) then
    Exit;
  AHandled := True;
end;

procedure TFormMain.TabPageFocus(Sender: TObject);
begin
  // Clique na página (outra janela nativa): o FMX não fecha o menu sozinho.
  HideMenu;
  if FAddress.IsFocused then
    FAddress.ResetFocus;
end;

procedure TFormMain.TabNavigated(Sender: TObject; const AUrl: string);
begin
  FHistory.Add(AUrl, TNecoTab(Sender).Title);
  // Painéis abertos (em qualquer janela): a visita nova aparece. As linhas não têm nada
  // do motor, então refazer aqui dentro do callback é seguro.
  NecoApp.HistoryChanged;
end;

procedure TFormMain.TabFullScreen(Sender: TObject; AValue: Boolean);
begin
  // Vem de dentro do callback do motor: a troca de janela roda depois.
  TThread.ForceQueue(nil,
    procedure
    begin
      if FShuttingDown or (Sender <> FActive) then
        Exit;
      FFullVideo := AValue;
      ApplyFullScreen;
    end);
end;

procedure TFormMain.ApplyFullScreen;
var
  Full: Boolean;
begin
  Full := FFullVideo or FFullKey;
  if Full = FFull then
    Exit;
  FFull := Full;
  NecoTrace('tela cheia ' + BoolToStr(Full, True));
  if Full then
    ShowPanel(nil);
  // Só a página: sem abas, endereço, favoritos e progresso. Align=Top: repõe a ordem.
  BeginUpdate;
  try
    FTabStrip.Visible := not Full;
    FToolbar.Visible := not Full;
    FBookmarkBar.Visible := not Full and FSettings.ShowBookmarkBar;
    FProgressTrack.Visible := not Full;
    FTabStrip.Position.Y := 0;
    FToolbar.Position.Y := FTabStrip.Height;
    FBookmarkBar.Position.Y := FToolbar.Position.Y + FToolbar.Height;
    FProgressTrack.Position.Y := FBookmarkBar.Position.Y + FBookmarkBar.Height + 1;
  finally
    EndUpdate;
  end;
  NecoFrameSetFullScreen(Self, Full);
  Realign;
  LayoutEngine;
  if FActive <> nil then
    FActive.Engine.Focus;
end;

{ Estado da tela }

procedure TFormMain.UpdateNavButtons;
var
  E: INecoEngine;
begin
  if FActive <> nil then
    E := FActive.Engine;
  FBtnBack.Enabled := (E <> nil) and E.CanGoBack;
  FBtnForward.Enabled := (E <> nil) and E.CanGoForward;
  if (FActive <> nil) and FActive.Loading then
  begin
    FBtnReload.IconData := ICO_FECHAR;
    FBtnReload.Hint := 'Parar (Esc)';
  end
  else
  begin
    FBtnReload.IconData := ICO_RECARREGAR;
    FBtnReload.Hint := 'Recarregar (F5)';
  end;
end;

procedure TFormMain.UpdateAddress;
var
  U: string;
begin
  if FActive <> nil then
    U := FActive.Url;
  if U.StartsWith('https://', True) then
    FAddressIcon.Data.Data := ICO_CADEADO
  else
    FAddressIcon.Data.Data := ICO_GLOBO;
  // Não atropela o que o usuário está digitando.
  if not FAddress.IsFocused then
  begin
    if SameText(U, 'about:blank') then
      U := '';
    FAddress.Text := U;
  end;
end;

procedure TFormMain.UpdateCaption;
begin
  if FActive <> nil then
    Caption := FActive.DisplayTitle + ' — NecoBrowser'
  else
    Caption := 'NecoBrowser';
end;

procedure TFormMain.UpdatePageMessage;
var
  Show: Boolean;
begin
  Show := (FActive <> nil) and FActive.HasErrorPage;
  if Show then
  begin
    FErrorView.Prepare(FActive.NavError, FActive.AttemptUrl, FActive.Error);
    FErrorView.Visible := True;
    FErrorView.BringToFront;
  end
  else
    FErrorView.Visible := False;
  // Espaço aéreo: com a página de erro na frente, a janela da página sai de cena.
  if FActive <> nil then
    FActive.Engine.SetVisible(not Show);
end;

procedure TFormMain.UpdateProgress;
begin
  if (FActive <> nil) and FActive.Loading then
  begin
    if not FProgress.Visible then
    begin
      FProgress.Width := FProgressTrack.Width * 0.15;
      FProgress.Opacity := 1;
      FProgress.Visible := True;
    end;
    FProgressTimer.Enabled := True;
  end
  else if FProgress.Visible then
  begin
    // Completa a barra e some no próximo tique.
    FProgress.Width := FProgressTrack.Width;
    FProgress.Tag := 1;
    FProgressTimer.Enabled := True;
  end;
end;

procedure TFormMain.ProgressTick(Sender: TObject);
begin
  if (FActive <> nil) and FActive.Loading then
  begin
    FProgress.Tag := 0;
    // Sem progresso real do motor: avança devagar até 85%.
    FProgress.Width := Min(FProgressTrack.Width * 0.85,
      FProgress.Width + (FProgressTrack.Width * 0.85 - FProgress.Width) * 0.08);
  end
  else
  begin
    FProgress.Visible := False;
    FProgress.Tag := 0;
    FProgressTimer.Enabled := False;
  end;
end;

procedure TFormMain.LayoutEngine;
var
  R: TRectF;
  S: Single;
begin
  if (FActive = nil) or (FActive.Engine = nil) or (Handle = nil) then
    Exit;
  // Coordenada lógica do FMX -> pixel físico da área cliente.
  R := FPageArea.AbsoluteRect;
  S := Handle.Scale;
  FActive.Engine.SetBounds(TRect.Create(Round(R.Left * S), Round(R.Top * S),
    Round(R.Right * S), Round(R.Bottom * S)));
end;

procedure TFormMain.PageAreaResized(Sender: TObject);
begin
  LayoutEngine;
end;

procedure TFormMain.DoScaleChanged;
begin
  inherited;
  // Troca de monitor ou de escala do Windows: o tamanho lógico pode não mudar, o físico muda.
  LayoutEngine;
end;

{ Ações }

procedure TFormMain.BackClick(Sender: TObject);
begin
  if FActive <> nil then
    FActive.Engine.GoBack;
end;

procedure TFormMain.ForwardClick(Sender: TObject);
begin
  if FActive <> nil then
    FActive.Engine.GoForward;
end;

procedure TFormMain.ReloadClick(Sender: TObject);
begin
  if FActive = nil then
    Exit;
  if FActive.Loading then
    FActive.Engine.Stop
  else if FActive.HasErrorPage then
    FActive.Retry
  else
    FActive.Engine.Reload;
end;

procedure TFormMain.AddressKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    Key := 0;
    GoAddress;
  end
  else if (Key = vkDown) and FSuggest.IsOpen then
  begin
    Key := 0;
    MoveSuggestion(1);
  end
  else if (Key = vkUp) and FSuggest.IsOpen then
  begin
    Key := 0;
    MoveSuggestion(-1);
  end
  else if (Key = vkEscape) and FSuggest.IsOpen then
  begin
    // Primeiro Esc fecha a lista e devolve o que foi digitado; o segundo sai da barra.
    Key := 0;
    if FSuggestIndex >= 0 then
    begin
      FSuggestFilling := True;
      try
        FAddress.Text := FSuggestTyped;
        FAddress.GoToTextEnd;
      finally
        FSuggestFilling := False;
      end;
    end;
    HideSuggestions;
  end
  else if Key = vkEscape then
  begin
    Key := 0;
    FAddress.ResetFocus;
    UpdateAddress;
    if FActive <> nil then
      FActive.Engine.Focus;
  end;
end;

procedure TFormMain.AddressEnter(Sender: TObject);
begin
  FAddressBox.Stroke.Color := Palette.Focus;
  // O clique posiciona o cursor depois do OnEnter: seleciona na próxima volta da fila.
  TThread.ForceQueue(nil,
    procedure
    begin
      if (FAddress <> nil) and FAddress.IsFocused then
        FAddress.SelectAll;
    end);
end;

procedure TFormMain.AddressExit(Sender: TObject);
begin
  HideSuggestions;
  FAddressBox.Stroke.Color := Palette.FieldBorder;
  UpdateAddress;
end;

procedure TFormMain.AddressTyping(Sender: TObject);
begin
  if FSuggestFilling or FShuttingDown or not FAddress.IsFocused then
    Exit;
  FSuggestTyped := FAddress.Text;
  ShowSuggestions;
end;

procedure TFormMain.GoAddress;
var
  T, U: string;
begin
  T := Trim(FAddress.Text);
  HideSuggestions;
  U := NecoInputToUrl(T, FSettings.SearchEngine);
  if (U = '') or (FActive = nil) then
    Exit;
  // Só busca entra na lista de digitados; endereço já fica no histórico de páginas.
  if U = NecoSearchUrl(T, FSettings.SearchEngine) then
    FHistory.AddTyped(T);
  FActive.Navigate(U);
  FAddress.ResetFocus;
  FActive.Engine.Focus;
end;

{ Sugestões da barra }

const
  CSuggestRowHeight = 34;
  CSuggestMax = 8;

procedure TFormMain.BuildSuggest;
begin
  FSuggestRows := TList<TRectangle>.Create;
  FSuggestIndex := -1;
  FSuggest := TPopup.Create(Self);
  FSuggest.Parent := Self;
  FSuggest.PlacementTarget := FAddressBox;
  FSuggest.Placement := TPlacement.Bottom;
  FSuggest.VerticalOffset := 4;
  FSuggest.BorderWidth := 0;
  FSuggest.AniDuration := 0;
  FSuggestBox := TRectangle.Create(Self);
  FSuggestBox.Parent := FSuggest;
  FSuggestBox.Align := TAlignLayout.Contents;
  FSuggestBox.XRadius := 10;
  FSuggestBox.YRadius := 10;
  FSuggestBox.Stroke.Thickness := 1;
  FSuggestBox.Padding.Rect := TRectF.Create(4, 4, 4, 4);
end;

procedure TFormMain.ShowSuggestions;
var
  R: TRectangle;
  Ico: FMX.Objects.TPath; // TPath sozinho é o do System.IOUtils aqui
  L, D: TLabel;
  S: TNecoSuggestion;
  I: Integer;
begin
  if (FSuggest = nil) or (FSuggestRows = nil) then
    Exit;
  FSuggestItems := FHistory.Suggest(FSuggestTyped, CSuggestMax);
  FSuggestIndex := -1;
  if Length(FSuggestItems) = 0 then
  begin
    HideSuggestions;
    Exit;
  end;
  // Refaz as linhas (fora de qualquer evento delas: vem da digitação na barra).
  FSuggestBox.BeginUpdate;
  try
    for R in FSuggestRows do
      R.Free;
    FSuggestRows.Clear;
    for I := 0 to High(FSuggestItems) do
    begin
      S := FSuggestItems[I];
      R := TRectangle.Create(Self);
      R.Parent := FSuggestBox;
      R.SetBounds(4, 4 + I * CSuggestRowHeight, FAddressBox.Width - 8, CSuggestRowHeight);
      R.Anchors := [TAnchorKind.akLeft, TAnchorKind.akTop, TAnchorKind.akRight];
      R.XRadius := 6;
      R.YRadius := 6;
      R.Stroke.Kind := TBrushKind.None;
      R.Fill.Kind := TBrushKind.Solid;
      R.HitTest := True;
      R.Tag := I;
      R.OnClick := SuggestRowClick;
      R.OnMouseEnter := SuggestRowEnter;

      Ico := FMX.Objects.TPath.Create(Self);
      Ico.Parent := R;
      Ico.HitTest := False;
      Ico.SetBounds(12, (CSuggestRowHeight - 16) / 2, 16, 16);
      Ico.WrapMode := TPathWrapMode.Fit;
      Ico.Fill.Kind := TBrushKind.None;
      Ico.Stroke.Thickness := 1.8;
      Ico.Stroke.Cap := TStrokeCap.Round;
      Ico.Stroke.Join := TStrokeJoin.Round;
      Ico.Stroke.Color := Palette.TextMuted;
      if S.Kind = nskSearch then
        Ico.Data.Data := ICO_LUPA
      else
        Ico.Data.Data := ICO_HISTORICO;

      L := NecoNewLabel(Self, R, '', 13.5);
      if (S.Kind = nskPage) and (S.Detail <> '') then
      begin
        // Página: título forte, endereço apagado à direita.
        L.Text := S.Detail;
        D := NecoNewLabel(Self, R, S.Text, 12, Palette.TextMuted);
        D.Align := TAlignLayout.Right;
        D.Width := Min(320, (FAddressBox.Width - 8) * 0.45);
        D.Margins.Right := 12;
        D.TextSettings.HorzAlign := TTextAlign.Trailing;
      end
      else
        L.Text := S.Text;
      L.Align := TAlignLayout.Client;
      L.Margins.Rect := TRectF.Create(40, 0, 12, 0);
      FSuggestRows.Add(R);
    end;
  finally
    FSuggestBox.EndUpdate;
  end;
  FSuggestBox.Fill.Color := Palette.Toolbar;
  FSuggestBox.Stroke.Color := Palette.FieldBorder;
  StyleSuggestRows;
  FSuggest.Width := FAddressBox.Width;
  FSuggest.Height := 8 + Length(FSuggestItems) * CSuggestRowHeight;
  // Width/Height não redimensionam a janela já aberta; PopupFormSize sim.
  FSuggest.PopupFormSize := TSizeF.Create(FSuggest.Width, FSuggest.Height);
  if not FSuggest.IsOpen then
    FSuggest.Popup(False);
end;

procedure TFormMain.HideSuggestions;
begin
  FSuggestIndex := -1;
  if (FSuggest <> nil) and FSuggest.IsOpen then
    FSuggest.IsOpen := False;
end;

procedure TFormMain.StyleSuggestRows;
var
  I: Integer;
  R: TRectangle;
begin
  if FSuggestRows = nil then
    Exit;
  for I := 0 to FSuggestRows.Count - 1 do
  begin
    R := FSuggestRows[I];
    if I = FSuggestIndex then
      R.Fill.Color := Palette.Hover
    else
      R.Fill.Color := TAlphaColors.Null;
  end;
end;

procedure TFormMain.MoveSuggestion(ADelta: Integer);
var
  N: Integer;
begin
  N := Length(FSuggestItems);
  if N = 0 then
    Exit;
  // Anda pela lista; passando do fim ou do começo, volta para o que foi digitado (-1).
  FSuggestIndex := FSuggestIndex + ADelta;
  if FSuggestIndex >= N then
    FSuggestIndex := -1
  else if FSuggestIndex < -1 then
    FSuggestIndex := N - 1;
  FSuggestFilling := True;
  try
    if FSuggestIndex >= 0 then
      FAddress.Text := FSuggestItems[FSuggestIndex].Text
    else
      FAddress.Text := FSuggestTyped;
    FAddress.GoToTextEnd;
  finally
    FSuggestFilling := False;
  end;
  StyleSuggestRows;
end;

procedure TFormMain.SuggestRowEnter(Sender: TObject);
begin
  FSuggestIndex := TControl(Sender).Tag;
  StyleSuggestRows;
end;

procedure TFormMain.SuggestRowClick(Sender: TObject);
var
  T: string;
  I: Integer;
begin
  I := TControl(Sender).Tag;
  if (I < 0) or (I > High(FSuggestItems)) then
    Exit;
  T := FSuggestItems[I].Text;
  // Fechar a lista dentro do clique de uma linha dela desmonta a janela com a pilha
  // ainda nela (regra 5.3): abre depois.
  TThread.ForceQueue(nil,
    procedure
    begin
      if FShuttingDown then
        Exit;
      FSuggestFilling := True;
      try
        FAddress.Text := T;
      finally
        FSuggestFilling := False;
      end;
      GoAddress;
    end);
end;

procedure TFormMain.FocusAddress;
begin
  if FActive <> nil then
    FActive.Engine.Blur;
  FAddress.SetFocus;
  FAddress.SelectAll;
end;

{ Painéis laterais }

procedure TFormMain.BuildPanels;
begin
  FPanelDownloads := TNecoDownloadsPanel.Create(Self);
  FPanelDownloads.Parent := FBody;
  FPanelDownloads.Visible := False;
  FPanelDownloads.OnCloseRequest := PanelCloseRequest;
  FPanelDownloads.OnFinished := DownloadFinished;

  FPanelBookmarks := TNecoBookmarksPanel.Create(Self);
  FPanelBookmarks.Parent := FBody;
  FPanelBookmarks.Visible := False;
  FPanelBookmarks.OnCloseRequest := PanelCloseRequest;
  FPanelBookmarks.Bookmarks := FBookmarks;
  FPanelBookmarks.FaviconDir := FaviconDir;
  FPanelBookmarks.OnOpen := BookmarkOpen;
  FPanelBookmarks.OnDelete := BookmarkDelete;
  FPanelBookmarks.OnRename := BookmarkRename;
  FPanelBookmarks.Rebuild;
  // Mudanças na lista chegam pelo app (AppBookmarksChanged), para todas as janelas.

  FPanelSettings := TNecoSettingsPanel.CreateFor(Self, FSettings, FBlocklist.Count);
  FPanelSettings.Parent := FBody;
  FPanelSettings.Visible := False;
  FPanelSettings.OnCloseRequest := PanelCloseRequest;
  FPanelSettings.OnChanged := SettingsChanged;

  FPanelHistory := TNecoHistoryPanel.Create(Self);
  FPanelHistory.Parent := FBody;
  FPanelHistory.Visible := False;
  FPanelHistory.OnCloseRequest := PanelCloseRequest;
  FPanelHistory.History := FHistory;
  FPanelHistory.OnOpen := BookmarkOpen;
  FPanelHistory.OnClear := HistoryClear;
end;

procedure TFormMain.ShowPanel(APanel: TNecoSidePanel);
begin
  // Um painel por vez. Ele encolhe a área da página (OnResized reposiciona o motor).
  FPanelDownloads.Visible := APanel = FPanelDownloads;
  FPanelBookmarks.Visible := APanel = FPanelBookmarks;
  FPanelSettings.Visible := APanel = FPanelSettings;
  if (APanel = FPanelHistory) and not FPanelHistory.Visible then
    FPanelHistory.Rebuild;
  FPanelHistory.Visible := APanel = FPanelHistory;
  UpdatePanelButtons;
end;

procedure TFormMain.TogglePanel(APanel: TNecoSidePanel);
begin
  if APanel.Visible then
    ShowPanel(nil)
  else
    ShowPanel(APanel);
end;

procedure TFormMain.PanelCloseRequest(Sender: TObject);
begin
  ShowPanel(nil);
end;

procedure TFormMain.UpdatePanelButtons;

  procedure Mark(AButton: TNecoIconButton; AOn: Boolean);
  begin
    if AOn then
      AButton.BaseColor := Palette.Pressed
    else
      AButton.BaseColor := 0;
  end;

begin
  // A seta fica marcada quando o painel aberto é um dos do menu.
  Mark(FBtnMenu, FPanelBookmarks.Visible or FPanelDownloads.Visible or FPanelHistory.Visible);
  Mark(FBtnSettings, FPanelSettings.Visible);
end;

procedure TFormMain.BookmarksClick(Sender: TObject);
begin
  TogglePanel(FPanelBookmarks);
end;

function TFormMain.FaviconDir: string;
begin
  Result := NecoApp.FaviconDir;
end;

procedure TFormMain.StoreFavicon(ATab: TNecoTab);
var
  H: string;
  I: Integer;
  Found: Boolean;
begin
  // Guarda só o ícone de sites que estão nos favoritos (não enche o disco).
  if (Length(ATab.Favicon) = 0) or (ATab.Url = '') then
    Exit;
  H := NecoExtractHost(ATab.Url);
  Found := False;
  for I := 0 to FBookmarks.Count - 1 do
    if NecoExtractHost(FBookmarks[I].Url) = H then
    begin
      Found := True;
      Break;
    end;
  if not Found then
    Exit;
  try
    if not NecoSaveFavicon(FaviconDir, ATab.Url, ATab.Favicon) then
      Exit;
  except
    Exit;
  end;
  // Ícone novo: as pílulas e o painel de todas as janelas se refazem (fora do callback
  // do motor).
  TThread.ForceQueue(nil,
    procedure
    begin
      if not FShuttingDown then
        NecoApp.FaviconsChanged;
    end);
end;

procedure TFormMain.BookmarkMove(Sender: TObject; AFrom, ATo: Integer);
begin
  // Vem do soltar do mouse numa pílula; mudar a lista refaz a barra: depois do evento.
  TThread.ForceQueue(nil,
    procedure
    begin
      if not FShuttingDown then
        FBookmarks.Move(AFrom, ATo);
    end);
end;

procedure TFormMain.OpenFileClick(Sender: TObject);
var
  D: TOpenDialog;
  F: string;
begin
  D := TOpenDialog.Create(nil);
  try
    D.Title := 'Abrir no NecoBrowser';
    D.Filter := 'Arquivos que o navegador lê|*.pdf;*.txt;*.md;*.log;*.csv;*.json;*.xml;*.htm;*.html;' +
      '*.svg;*.png;*.jpg;*.jpeg;*.gif;*.webp;*.bmp;*.ico;*.mp4;*.webm;*.mp3;*.wav;*.ogg|' +
      'PDF|*.pdf|Texto|*.txt;*.md;*.log;*.csv;*.json;*.xml|Todos os arquivos|*.*';
    D.Options := [TOpenOption.ofFileMustExist, TOpenOption.ofAllowMultiSelect];
    if not D.Execute then
      Exit;
    // Cada arquivo numa aba nova; a última fica na frente.
    for F in D.Files do
      NewTab(NecoPathToFileUrl(F));
  finally
    D.Free;
  end;
end;

procedure TFormMain.HistoryClick(Sender: TObject);
begin
  TogglePanel(FPanelHistory);
end;

procedure TFormMain.HistoryClear(Sender: TObject);
begin
  // Vem do clique na lixeira do painel; o Rebuild não libera o cabeçalho, mas o
  // padrão é o mesmo dos outros painéis: depois do evento.
  TThread.ForceQueue(nil,
    procedure
    begin
      if FShuttingDown then
        Exit;
      NecoApp.ClearHistory; // grava e refaz os painéis abertos
      FPanelHistory.Rebuild;
      FStage.Perform('flip');
    end);
end;

procedure TFormMain.DownloadsClick(Sender: TObject);
begin
  TogglePanel(FPanelDownloads);
end;

procedure TFormMain.DownloadFinished(Sender: TObject; ASuccess: Boolean);
begin
  // Download concluído: a Neco comemora (sem o limite de 1x por minuto).
  if ASuccess then
    FStage.Celebrate(True);
end;

procedure TFormMain.UpdateStar;
var
  IsOn: Boolean;
begin
  if FBtnStar = nil then
    Exit;
  IsOn := (FActive <> nil) and (FActive.Url <> '') and FBookmarks.Contains(FActive.Url);
  FBtnStar.Filled := IsOn;
  if IsOn then
  begin
    FBtnStar.IconColor := Palette.Star;
    FBtnStar.Hint := 'Remover dos favoritos (Ctrl+D)';
  end
  else
  begin
    FBtnStar.IconColor := Palette.TextMuted;
    FBtnStar.Hint := 'Favoritar esta página (Ctrl+D)';
  end;
end;

procedure TFormMain.StarClick(Sender: TObject);
begin
  ToggleBookmark;
end;

procedure TFormMain.ToggleBookmark;
var
  U: string;
begin
  if FActive = nil then
    Exit;
  U := FActive.Url;
  if (U = '') or SameText(U, 'about:blank') then
    Exit;
  // O ícone vai antes: o Toggle refaz a barra, que já o encontra.
  if Length(FActive.Favicon) > 0 then
    try
      NecoSaveFavicon(FaviconDir, U, FActive.Favicon);
    except
    end;
  // Favoritou: a Neco faz pose.
  if FBookmarks.Toggle(FActive.DisplayTitle, U) then
    FStage.Perform('turn');
end;

{ Avisos do app (INecoWindow) }

procedure TFormMain.AppBookmarksChanged;
begin
  // Quem muda a lista nunca é um clique numa linha do painel (BookmarkDelete adia).
  // O app grava o arquivo.
  if FShuttingDown then
    Exit;
  FPanelBookmarks.Rebuild;
  FBookmarkBar.Rebuild;
  UpdateStar;
end;

procedure TFormMain.AppFaviconsChanged;
begin
  if FShuttingDown then
    Exit;
  FBookmarkBar.Rebuild;
  FPanelBookmarks.Rebuild;
end;

procedure TFormMain.AppHistoryChanged;
begin
  if not FShuttingDown and FPanelHistory.Visible then
    FPanelHistory.Rebuild;
end;

procedure TFormMain.AppUpdateChanged(ANew: Boolean);
begin
  if FShuttingDown then
    Exit;
  RefreshUpdateInfo;
  if ANew then
  begin
    UpdateShield; // bolinha na seta
    ShowUpdateNotice;
  end;
end;

procedure TFormMain.AppMemoryReport(const AReport: TNecoMemoryReport);
begin
  if not FShuttingDown then
    ShowMemory(AReport);
end;

function TFormMain.AppIsMinimized: Boolean;
begin
  Result := FShuttingDown or NecoFrameIsMinimized(Self);
end;

procedure TFormMain.AppSettingsChanged(AChange: TNecoSettingsChange);
var
  T: TNecoTab;
begin
  // O app já aplicou a parte dele (tema global, extensão, atualizador) e gravou.
  if FShuttingDown then
    Exit;
  case AChange of
    scTheme:
      begin
        ApplyTheme;
        // Os sites que respeitam prefers-color-scheme trocam junto.
        for T in FTabs do
          T.Engine.SetDarkMode(FSettings.Theme = ntDark);
      end;
    scBlocker:
      UpdateShield;
    scBookmarkBar:
      LayoutBookmarkBar;
    scAutofill:
      for T in FTabs do
        T.Engine.SetAutofill(FSettings.FormAutofill, FSettings.SavePasswords);
    scNeco:
      begin
        FStage.SetShown(FSettings.NecoShown);
        // As Necos dos painéis e da página de erro param de desenhar no próximo quadro.
        Invalidate;
      end;
    scAutoUpdate:
      RefreshUpdateInfo;
  end;
  FPanelSettings.Refresh;
end;

procedure TFormMain.BookmarkOpen(Sender: TObject; const AUrl: string; ANewTab: Boolean);
begin
  if ANewTab or (FActive = nil) then
    NewTab(AUrl, False)
  else
  begin
    FActive.Navigate(AUrl);
    FActive.Engine.Focus;
  end;
end;

procedure TFormMain.BookmarkRename(Sender: TObject; const AUrl, ATitle: string);
var
  U, T: string;
begin
  // Vem do campo de edição, que o Rebuild vai liberar: depois do evento.
  U := AUrl;
  T := ATitle;
  TThread.ForceQueue(nil,
    procedure
    begin
      if not FShuttingDown then
        FBookmarks.Rename(U, T);
    end);
end;

procedure TFormMain.BookmarkEditRequest(Sender: TObject; const AUrl: string);
begin
  // Botão direito numa pílula da barra: edita o nome no painel.
  ShowPanel(FPanelBookmarks);
  FPanelBookmarks.BeginEdit(AUrl);
end;

procedure TFormMain.LayoutBookmarkBar;
begin
  // Align=Top: quem volta a ficar visível vai para o fim da pilha. Repõe a ordem.
  BeginUpdate;
  try
    FBookmarkBar.Visible := FSettings.ShowBookmarkBar;
    FBookmarkBar.Position.Y := FToolbar.Position.Y + FToolbar.Height;
    FProgressTrack.Position.Y := FBookmarkBar.Position.Y + FBookmarkBar.Height + 1;
  finally
    EndUpdate;
  end;
  Realign;
end;

procedure TFormMain.BookmarkDelete(Sender: TObject; const AUrl: string);
var
  U: string;
begin
  // O clique veio da lixeira de uma linha que o Rebuild vai liberar: depois do clique.
  U := AUrl;
  TThread.ForceQueue(nil,
    procedure
    begin
      if not FShuttingDown then
        FBookmarks.Remove(U);
    end);
end;

{ Tema, configurações e página de erro }

procedure TFormMain.ThemeClick(Sender: TObject);
begin
  // O app troca o tema de todas as janelas (AppSettingsChanged).
  if CurrentTheme = ntDark then
    NecoApp.SetTheme(ntLight)
  else
    NecoApp.SetTheme(ntDark);
end;

procedure TFormMain.SettingsClick(Sender: TObject);
begin
  TogglePanel(FPanelSettings);
end;

procedure TFormMain.SettingsChanged(Sender: TObject; AChange: TNecoSettingsChange);
begin
  // O painel já gravou a escolha em FSettings (que é do app).
  if AChange = scDefaultBrowser then
  begin
    // O Windows não deixa se pôr como padrão sozinho: registra e abre a tela onde
    // a pessoa confirma. Nada a gravar no settings.json.
    if not NecoRegisterBrowser then
      NecoTrace('navegador padrao: registro recusado');
    NecoOpenDefaultAppsSettings;
    Exit;
  end;
  // O app aplica, grava e avisa todas as janelas (inclusive esta).
  NecoApp.SettingsChanged(AChange);
  // Como as extensões de bloqueio: a página desta janela recarrega já com a nova regra.
  if (AChange = scBlocker) and (FActive <> nil) and (FActive.Url <> '') then
    FActive.Engine.Reload;
end;

procedure TFormMain.ErrorRetry(Sender: TObject);
begin
  if FActive <> nil then
    FActive.Retry;
end;

{ Teste de memória }

procedure TFormMain.SelfTestTick(Sender: TObject);
var
  I: Integer;
begin
  // Cada marca 'teste fase=...' sai no rastro com o sistema em repouso; quem mede
  // (fora do processo) lê a memória nesse instante. Depois da marca, 5 s antes de mexer.
  // Ciclo: abre N abas -> 30 s -> marca 'abertas' -> fecha -> 45 s -> marca 'fechadas'.
  if FShuttingDown then
    Exit;
  case FSelfTestStep of
    0:
      begin
        NecoTrace('teste fase=base ciclo=0 abas=' + IntToStr(FTabs.Count));
        FSelfTest.Interval := 5000;
        FSelfTestStep := 1;
      end;
    1:
      begin
        Inc(FSelfTestCycle);
        for I := 1 to FSelfTestTabs do
          NewTab('https://example.com/?neco=' + IntToStr(I), False);
        FSelfTest.Interval := 30000;
        FSelfTestStep := 2;
      end;
    2:
      begin
        NecoTrace(Format('teste fase=abertas ciclo=%d abas=%d', [FSelfTestCycle, FTabs.Count]));
        FSelfTest.Interval := 5000;
        FSelfTestStep := 3;
      end;
    3:
      begin
        while FTabs.Count > 1 do
          CloseTab(FTabs[FTabs.Count - 1]);
        FSelfTest.Interval := 45000;
        FSelfTestStep := 4;
      end;
    4:
      begin
        NecoTrace(Format('teste fase=fechadas ciclo=%d abas=%d', [FSelfTestCycle, FTabs.Count]));
        FSelfTest.Interval := 5000;
        if FSelfTestCycle < FSelfTestCycles then
          FSelfTestStep := 1
        else
        begin
          NecoTrace('teste fim');
          FSelfTest.Enabled := False;
        end;
      end;
  end;
end;

{ Bloqueador }

function TFormMain.AddToolButton(const AIcon, AHint: string; AOnClick: TNotifyEvent): TNecoIconButton;
begin
  Result := NecoNewButton(Self, FToolRight, AIcon, AHint, AOnClick);
  Result.Align := TAlignLayout.Left;
  Result.Margins.Left := 2;
  Result.Position.X := FToolRight.Width; // depois dos que já existem
  FToolRight.Width := FToolRight.Width + CButtonSize + 2;
end;

procedure TFormMain.UpdateShield;
var
  N: Integer;
  S: string;
begin
  if FBtnMenu = nil then
    Exit;
  N := 0;
  if FActive <> nil then
    N := FActive.BlockedCount;
  if NecoApp.BlockerOn then
  begin
    if N = 1 then
      S := '1 anúncio ou rastreador barrado nesta página'
    else
      S := Format('%d anúncios e rastreadores barrados nesta página', [N]);
    FBtnMenu.Hint := 'Mais opções' + sLineBreak + 'Bloqueador ligado: ' + S;
  end
  else
  begin
    FBtnMenu.Hint := 'Mais opções' + sLineBreak + 'Bloqueador desligado';
    N := 0;
  end;
  FUpdateDot.Visible := NecoApp.UpdateVersion <> '';
  if NecoApp.UpdateVersion <> '' then
  begin
    FUpdateDot.Fill.Color := Palette.Accent;
    FBtnMenu.Hint := FBtnMenu.Hint + sLineBreak + 'Versão ' + NecoApp.UpdateVersion +
      ' pronta: reinicie para atualizar';
  end;
  FShieldBadge.Visible := N > 0;
  if N > 0 then
  begin
    if N > 99 then
      S := '99+'
    else
      S := IntToStr(N);
    FShieldBadge.Fill.Color := Palette.Shield;
    FShieldBadgeText.TextSettings.FontColor := Palette.Window;
    FShieldBadgeText.Text := S;
    FShieldBadge.SetBounds(CButtonSize - 4 - (6 + 6 * Length(S)), CButtonSize - 15,
      6 + 6 * Length(S), 13);
  end;
end;

procedure TFormMain.ShieldClick(Sender: TObject);
begin
  // O app grava, liga/desliga a extensão e atualiza o escudo e o painel de todas as janelas.
  NecoApp.SetBlocker(not FSettings.BlockerEnabled);
  // Como as extensões de bloqueio: a página recarrega já com a nova regra.
  if (FActive <> nil) and (FActive.Url <> '') then
    FActive.Engine.Reload;
end;

{ Menu da seta }

const
  CMenuWidth = 280;
  CMenuRowHeight = 36;
  // Tag de cada linha do menu.
  CMenuBlocker = 0;
  CMenuBookmarks = 1;
  CMenuHistory = 2;
  CMenuDownloads = 3;
  CMenuOpenFile = 4;
  CMenuTheme = 5;
  CMenuUpdate = 6;
  CMenuLater = 7;

procedure TFormMain.BuildMenu;
begin
  FMenu := TPopup.Create(Self);
  FMenu.Parent := Self;
  FMenu.PlacementTarget := FBtnMenu;
  FMenu.Placement := TPlacement.Bottom;
  // Alinha a borda direita do menu com a da seta (ela fica perto da borda da janela).
  FMenu.HorizontalOffset := CButtonSize - CMenuWidth;
  FMenu.VerticalOffset := 4;
  FMenu.BorderWidth := 0;
  FMenu.AniDuration := 0;
  FMenuBox := TRectangle.Create(Self);
  FMenuBox.Parent := FMenu;
  FMenuBox.Align := TAlignLayout.Contents;
  FMenuBox.XRadius := 10;
  FMenuBox.YRadius := 10;
  FMenuBox.Stroke.Thickness := 1;
end;

procedure TFormMain.HideMenu;
begin
  if (FMenu <> nil) and FMenu.IsOpen then
    FMenu.IsOpen := False;
end;

procedure TFormMain.ClearMenu;
var
  C: TFmxObject;
begin
  while FMenuBox.ChildrenCount > 0 do
  begin
    C := FMenuBox.Children[FMenuBox.ChildrenCount - 1];
    C.Free;
  end;
  FMenuY := 4;
end;

procedure TFormMain.AddMenuRow(ATag: Integer; const AIcon, AText, ARight: string;
  AIconColor: TAlphaColor; AMarked: Boolean);
var
  R: TRectangle;
  Ico: FMX.Objects.TPath;
  L: TLabel;
begin
  R := TRectangle.Create(Self);
  R.Parent := FMenuBox;
  R.SetBounds(4, FMenuY, CMenuWidth - 8, CMenuRowHeight);
  R.XRadius := 6;
  R.YRadius := 6;
  R.Stroke.Kind := TBrushKind.None;
  R.Fill.Kind := TBrushKind.Solid;
  // Painel aberto fica marcado, como os botões faziam.
  if AMarked then
    R.Fill.Color := Palette.Pressed
  else
    R.Fill.Color := TAlphaColors.Null;
  R.TagFloat := Ord(AMarked); // a cor de volta depois do mouse
  R.HitTest := True;
  R.Tag := ATag;
  R.OnClick := MenuRowClick;
  R.OnMouseEnter := MenuRowHover;
  R.OnMouseLeave := MenuRowHover;

  Ico := FMX.Objects.TPath.Create(Self);
  Ico.Parent := R;
  Ico.HitTest := False;
  Ico.SetBounds(12, (CMenuRowHeight - 18) / 2, 18, 18);
  Ico.WrapMode := TPathWrapMode.Fit;
  Ico.Fill.Kind := TBrushKind.None;
  Ico.Stroke.Thickness := 1.8;
  Ico.Stroke.Cap := TStrokeCap.Round;
  Ico.Stroke.Join := TStrokeJoin.Round;
  Ico.Stroke.Color := AIconColor;
  Ico.Data.Data := AIcon;

  if ARight <> '' then
  begin
    L := NecoNewLabel(Self, R, ARight, 12, Palette.TextMuted);
    L.Align := TAlignLayout.Right;
    L.Width := 110;
    L.Margins.Right := 12;
    L.TextSettings.HorzAlign := TTextAlign.Trailing;
  end;
  L := NecoNewLabel(Self, R, AText, 13.5);
  L.Align := TAlignLayout.Client;
  L.Margins.Rect := TRectF.Create(42, 0, 8, 0);
  FMenuY := FMenuY + CMenuRowHeight;
end;

procedure TFormMain.OpenMenu;
begin
  FMenuBox.Fill.Color := Palette.Toolbar;
  FMenuBox.Stroke.Color := Palette.FieldBorder;
  FMenu.Width := CMenuWidth;
  FMenu.Height := FMenuY + 4;
  FMenu.PopupFormSize := TSizeF.Create(FMenu.Width, FMenu.Height);
  FMenu.Popup(False);
end;

procedure TFormMain.MenuClick(Sender: TObject);
var
  N: Integer;
begin
  if FMenu.IsOpen then
  begin
    HideMenu;
    Exit;
  end;
  HideSuggestions;
  // Monta na hora: estado do bloqueador, painel aberto e tema mudam.
  FMenuBox.BeginUpdate;
  try
    ClearMenu;
    if NecoApp.UpdateVersion <> '' then
      AddMenuRow(CMenuUpdate, ICO_SINCRONIZAR, 'Reiniciar para atualizar',
        'versão ' + NecoApp.UpdateVersion, Palette.Accent, False);
    N := 0;
    if FActive <> nil then
      N := FActive.BlockedCount;
    if NecoApp.BlockerOn then
      AddMenuRow(CMenuBlocker, ICO_ESCUDO, 'Bloqueador ligado', Format('%d barrados', [N]),
        Palette.Shield, False)
    else
      AddMenuRow(CMenuBlocker, ICO_ESCUDO_OFF, 'Bloqueador desligado', 'clique para ligar',
        Palette.TextMuted, False);
    AddMenuRow(CMenuBookmarks, ICO_MARCADOR, 'Favoritos', 'Ctrl+Shift+O', Palette.Text,
      FPanelBookmarks.Visible);
    AddMenuRow(CMenuHistory, ICO_HISTORICO, 'Histórico', 'Ctrl+H', Palette.Text,
      FPanelHistory.Visible);
    AddMenuRow(CMenuDownloads, ICO_BAIXAR, 'Downloads', 'Ctrl+J', Palette.Text,
      FPanelDownloads.Visible);
    AddMenuRow(CMenuOpenFile, ICO_ARQUIVO, 'Abrir arquivo', 'Ctrl+O', Palette.Text, False);
    if CurrentTheme = ntDark then
      AddMenuRow(CMenuTheme, ICO_SOL, 'Tema claro', '', Palette.Text, False)
    else
      AddMenuRow(CMenuTheme, ICO_LUA, 'Tema escuro', '', Palette.Text, False);
  finally
    FMenuBox.EndUpdate;
  end;
  OpenMenu;
end;

procedure TFormMain.MenuRowHover(Sender: TObject);
var
  R: TRectangle;
begin
  R := TRectangle(Sender);
  if R.IsMouseOver then
    R.Fill.Color := Palette.Hover
  else if R.TagFloat <> 0 then
    R.Fill.Color := Palette.Pressed
  else
    R.Fill.Color := TAlphaColors.Null;
end;

procedure TFormMain.MenuRowClick(Sender: TObject);
var
  Acao: Integer;
begin
  Acao := TControl(Sender).Tag;
  // Fechar o menu dentro do clique de uma linha dele desmonta a janela com a pilha
  // ainda nela (regra 5.3); e "Abrir arquivo" abre um diálogo modal: tudo depois.
  TThread.ForceQueue(nil,
    procedure
    begin
      if FShuttingDown then
        Exit;
      HideMenu;
      case Acao of
        CMenuBlocker:
          ShieldClick(nil);
        CMenuBookmarks:
          BookmarksClick(nil);
        CMenuHistory:
          HistoryClick(nil);
        CMenuDownloads:
          DownloadsClick(nil);
        CMenuOpenFile:
          OpenFileClick(nil);
        CMenuTheme:
          ThemeClick(nil);
        CMenuUpdate:
          begin
            // A última janela a fechar grava a sessão, troca o exe e abre o novo.
            NecoApp.RequestRestartForUpdate;
            Close;
          end;
        // CMenuLater: só fecha o aviso; a troca fica para quando fechar o navegador
      end;
    end);
end;

{ Atualização automática

  Quem consulta, baixa e troca o exe é o app (Neco.UI.App). A janela mostra o aviso, a
  bolinha na seta e o texto no painel de configurações. }

procedure TFormMain.ShowUpdateNotice;
begin
  // Não interrompe: só abre o aviso com a janela em uso normal e nada aberto por cima.
  // Senão fica só a bolinha na seta e o item no menu.
  if FFull or FMenu.IsOpen or ((FSuggest <> nil) and FSuggest.IsOpen) or
    not NecoFrameIsForeground(Self) then
    Exit;
  FMenuBox.BeginUpdate;
  try
    ClearMenu;
    AddMenuRow(CMenuUpdate, ICO_SINCRONIZAR, 'Versão ' + NecoApp.UpdateVersion + ' pronta',
      'reiniciar agora', Palette.Accent, False);
    AddMenuRow(CMenuLater, ICO_HISTORICO, 'Depois', 'troca ao fechar', Palette.TextMuted, False);
  finally
    FMenuBox.EndUpdate;
  end;
  OpenMenu;
end;

procedure TFormMain.RefreshUpdateInfo;
begin
  if FPanelSettings <> nil then
    FPanelSettings.SetUpdateInfo(NecoApp.UpdateInfoText);
end;

{ Navegador padrão }

procedure TFormMain.FormActivated(Sender: TObject);
begin
  if not FShuttingDown then
    RefreshDefaultBrowser;
end;

procedure TFormMain.RefreshDefaultBrowser;
begin
  if FPanelSettings <> nil then
    FPanelSettings.SetDefaultBrowser(NecoIsDefaultBrowser);
end;

function TFormMain.HandleShortcut(AKey: Word; AShift: TShiftState): Boolean;
var
  Acao: TProc;
begin
  // A ação nasce em outra função. Se nascesse aqui, o procedimento anônimo e a variável
  // que o adiamento abaixo captura ficariam no mesmo quadro: um aponta para o outro e
  // nenhum é liberado (vazamento visto em 2026-11-11 com o Ctrl+T).
  Acao := ShortcutAction(AKey, AShift);
  Result := Assigned(Acao);
  if Result then
    // Adiado: quem chama pode ser um callback do motor que a ação vai destruir.
    TThread.ForceQueue(nil,
      procedure
      begin
        if not FShuttingDown then
          Acao();
      end);
end;

function TFormMain.ShortcutAction(AKey: Word; AShift: TShiftState): TProc;
var
  Acao: TProc;
  M: TShiftState;
  N: Integer;
begin
  Acao := nil;
  M := AShift * [ssCtrl, ssAlt, ssShift];
  if (M = [ssCtrl]) and (AKey = vkL) then
    Acao := FocusAddress
  else if (M = [ssCtrl, ssShift]) and (AKey = vkT) then
    Acao := ReopenClosedTab
  else if (M = [ssCtrl]) and (AKey = vkN) then
    Acao := NewWindow
  else if (M = [ssCtrl]) and (AKey = vkO) then
    Acao := procedure begin OpenFileClick(nil); end
  else if (M = [ssCtrl]) and (AKey = vkH) then
    Acao := procedure
      begin
        TogglePanel(FPanelHistory);
        if FPanelHistory.Visible then
          FPanelHistory.FocusSearch;
      end
  else if (M = []) and (AKey = vkF11) then
    Acao := procedure
      begin
        // F11 sai de qualquer tela cheia, inclusive a do vídeo.
        FFullKey := not FFull;
        FFullVideo := False;
        ApplyFullScreen;
      end
  else if (M = [ssCtrl]) and (AKey = vkT) then
    Acao := procedure
      begin
        NewTab(FSettings.HomeUrl);
        FocusAddress;
      end
  else if (M = [ssCtrl]) and (AKey = vkD) then
    Acao := ToggleBookmark
  else if (M = [ssCtrl]) and (AKey = vkJ) then
    Acao := procedure begin TogglePanel(FPanelDownloads); end
  else if (M = [ssCtrl, ssShift]) and (AKey = vkB) then
    Acao := procedure begin NecoApp.SetBookmarkBarShown(not FSettings.ShowBookmarkBar); end
  else if (M = [ssCtrl, ssShift]) and (AKey = vkO) then
    Acao := procedure begin TogglePanel(FPanelBookmarks); end
  else if (M = [ssCtrl]) and (AKey = vkW) then
    Acao := procedure begin CloseTab(FActive); end
  else if (M = [ssCtrl]) and (AKey = vkTab) then
    Acao := procedure begin SwitchTab(1); end
  else if (M = [ssCtrl, ssShift]) and (AKey = vkTab) then
    Acao := procedure begin SwitchTab(-1); end
  else if (M = [ssCtrl]) and (AKey >= vk1) and (AKey <= vk9) then
  begin
    // Ctrl+1..8: aba pela posição; Ctrl+9: a última (como no Chrome).
    N := AKey - vk1;
    Acao := procedure
      begin
        if N = 8 then
          SelectTab(FTabs.Count - 1)
        else
          SelectTab(N);
      end;
  end
  else if ((M * [ssCtrl, ssAlt] = []) and (AKey = vkF5)) or ((M = [ssCtrl]) and (AKey = vkR)) then
    Acao := procedure begin ReloadClick(nil); end
  else if (M = []) and (AKey = vkEscape) and (FActive <> nil) and FActive.Loading then
    // Só com a página carregando: no resto do tempo o Esc é da página.
    Acao := procedure begin if (FActive <> nil) and FActive.Loading then FActive.Engine.Stop; end
  else if (M = [ssAlt]) and (AKey = vkLeft) then
    Acao := procedure begin BackClick(nil); end
  else if (M = [ssAlt]) and (AKey = vkRight) then
    Acao := procedure begin ForwardClick(nil); end;
  Result := Acao;
end;

procedure TFormMain.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  // Antes do inherited: o FMX entrega a tecla ao controle com foco primeiro
  // e consome o Tab (inclusive Ctrl+Tab) para trocar o foco.
  // Esc com o menu da seta aberto: fecha o menu (a janela dele não recebe teclas).
  if (Key = vkEscape) and (FMenu <> nil) and FMenu.IsOpen then
  begin
    HideMenu;
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  if (Key <> 0) and HandleShortcut(Key, Shift) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  inherited;
end;

end.
