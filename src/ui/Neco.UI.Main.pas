unit Neco.UI.Main;

{ Form principal do NecoBrowser. A tela é montada em código (Neco.UI.Theme tem as cores).

  Espaço aéreo: a página é uma janela nativa por cima do FMX. Nada do FMX pode ficar
  sobre FPageArea; painéis laterais encolhem essa área, nunca a cobrem. }

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Objects, FMX.Layouts, FMX.StdCtrls,
  FMX.Edit,
  Neco.Core.Settings, Neco.Core.Blocklist, Neco.Core.Bookmarks, Neco.Core.History,
  Neco.Engine.Intf, Neco.UI.Theme, Neco.UI.Tab, Neco.UI.Frame, Neco.UI.Neco,
  Neco.UI.SidePanel, Neco.UI.Downloads, Neco.UI.Bookmarks, Neco.UI.Settings, Neco.UI.ErrorView,
  Neco.UI.BookmarkBar, Neco.UI.History;

type
  TFormMain = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    FSettings: TNecoSettings;
    FBlocklist: TNecoBlocklist;
    FBookmarks: TNecoBookmarks;
    FHistory: TNecoHistory;
    FTabs: TObjectList<TNecoTab>;
    FActive: TNecoTab;
    FStarted: Boolean;
    FShuttingDown: Boolean;
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
    FBtnShield: TNecoIconButton;
    FShieldBadge: TRectangle;
    FShieldBadgeText: TLabel;
    FBtnBookmarks, FBtnHistory, FBtnDownloads, FBtnTheme, FBtnSettings: TNecoIconButton;
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
    // abas fechadas (Ctrl+Shift+T), a mais recente no fim
    FClosed: TList<string>;
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
    procedure LoadData;
    procedure LoadBlocklist;
    procedure SaveData;
    function BlockerOn: Boolean;
    function StartUrl: string;
    function CmdLineUrl: string;
    /// Reabre as abas da última vez (as de fundo só carregam quando ativadas).
    function RestoreSession: Boolean;
    procedure SaveSession;
    procedure ReopenClosedTab;
    procedure TabFullScreen(Sender: TObject; AValue: Boolean);
    procedure ApplyFullScreen;
    procedure HistoryClick(Sender: TObject);
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
    procedure FocusAddress;
    // bloqueador
    function AddToolButton(const AIcon, AHint: string; AOnClick: TNotifyEvent): TNecoIconButton;
    procedure UpdateShield;
    procedure ShieldClick(Sender: TObject);
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
    procedure BookmarksChanged(Sender: TObject);
    procedure BookmarkOpen(Sender: TObject; const AUrl: string; ANewTab: Boolean);
    procedure BookmarkDelete(Sender: TObject; const AUrl: string);
    procedure BookmarkRename(Sender: TObject; const AUrl, ATitle: string);
    procedure BookmarkEditRequest(Sender: TObject; const AUrl: string);
    procedure SetBookmarkBarShown(AShow: Boolean);
    // tema, configurações e página de erro
    procedure ThemeClick(Sender: TObject);
    procedure SettingsClick(Sender: TObject);
    procedure SettingsChanged(Sender: TObject; AChange: TNecoSettingsChange);
    procedure SetTheme(ATheme: TNecoTheme);
    procedure SaveSettings;
    procedure ErrorRetry(Sender: TObject);
    procedure SelfTestTick(Sender: TObject);
    /// Atalhos do teclado. Usado pelo form e pela página (via AcceleratorKey).
    function HandleShortcut(AKey: Word; AShift: TShiftState): Boolean;
  protected
    procedure DoScaleChanged; override;
  public
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
  end;

var
  FormMain: TFormMain;

implementation

uses
  System.IOUtils, System.Math, System.ZLib,
  Neco.Core.Url, Neco.Core.Trace, Neco.Engine.Factory;

{$R *.fmx}
// Lista de bloqueio comprimida (tools\neco_embutidos.py): o exe funciona sem arquivos ao lado.
{$R NecoData.res}

{ TFormMain }

procedure TFormMain.FormCreate(Sender: TObject);
var
  Cfg: TNecoEngineConfig;
begin
  NecoTrace('form criando');
  FTabs := TObjectList<TNecoTab>.Create(False);
  FClosed := TList<string>.Create;
  LoadData;
  NecoSetTheme(FSettings.Theme);
  NecoSetShown(FSettings.NecoShown);

  Cfg.WebDataDir := FSettings.WebDataDir;
  Cfg.DownloadsDir := FSettings.DownloadsDir;
  Cfg.Language := 'pt-BR';
  Cfg.BackgroundColor := Palette.Window;
  NecoEngineSetup(Cfg);

  BuildUI;
  ApplyTheme;
  // A janela já existe aqui (o FMX cria o handle antes do OnCreate): a barra branca
  // some antes da primeira exibição.
  AttachFrame;
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
  if not FSettings.RestoreSession or (CmdLineUrl <> '') or
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
  if FClosed.Count = 0 then
    Exit;
  U := FClosed.Last;
  FClosed.Delete(FClosed.Count - 1);
  NewTab(U);
end;

procedure TFormMain.FormClose(Sender: TObject; var Action: TCloseAction);
var
  T: TNecoTab;
begin
  if FShuttingDown then
    Exit;
  FShuttingDown := True;
  // A janela ainda recebe mensagens até ser destruída: solta os callbacks da barra
  // antes de liberar o que eles consultam.
  NecoFrameDetach;
  FStage.Stop;
  if FSelfTest <> nil then
    FSelfTest.Enabled := False;
  FProgressTimer.Enabled := False;
  FPanelDownloads.Shutdown;
  FBookmarks.OnChange := nil;
  if FFull then
    NecoFrameSetFullScreen(Self, False);
  SaveSession;
  SaveData;
  // Ordem: fechar cada motor (a janela do form ainda existe), depois o ambiente.
  for T in FTabs do
    T.Close;
  FActive := nil;
  for T in FTabs do
    T.Free;
  FTabs.Clear;
  NecoEngineShutdown;
  FreeAndNil(FTabs);
  FreeAndNil(FClosed);
  FreeAndNil(FHistory);
  FreeAndNil(FBookmarks);
  FreeAndNil(FBlocklist);
  FreeAndNil(FSettings);
end;

procedure TFormMain.LoadData;
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

procedure TFormMain.LoadBlocklist;
var
  Arq: string;
  RS: TResourceStream;
  Z: TZDecompressionStream;
begin
  // A do lado do exe ganha (dá para atualizar sem recompilar); senão, a embutida.
  Arq := System.IOUtils.TPath.Combine(ExtractFilePath(ParamStr(0)), 'blocklist-hosts.txt');
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

procedure TFormMain.SaveData;
begin
  try
    FSettings.Save;
    FBookmarks.SaveToFile(FSettings.BookmarksFile);
    FHistory.SaveToFile(FSettings.HistoryFile);
  except
    // Falha de disco ao fechar não pode impedir o app de fechar.
  end;
end;

function TFormMain.BlockerOn: Boolean;
begin
  Result := (FSettings <> nil) and FSettings.BlockerEnabled;
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

  FBookmarkBar := TNecoBookmarkBar.Create(Self);
  FBookmarkBar.Parent := Self;
  FBookmarkBar.Position.Y := 500;
  FBookmarkBar.Align := TAlignLayout.Top;
  FBookmarkBar.Bookmarks := FBookmarks;
  FBookmarkBar.OnOpen := BookmarkOpen;
  FBookmarkBar.OnEdit := BookmarkEditRequest;
  FBookmarkBar.OnMore := BookmarksClick;
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

  ATab.TitleLabel := NecoNewLabel(Self, B, '', 12.5);
  ATab.TitleLabel.Align := TAlignLayout.Client;
  ATab.TitleLabel.Margins.Rect := TRectF.Create(12, 0, 4, 0);
  ATab.Button := B;
  ATab.CloseButton := X;
  UpdateTabTitle(ATab);
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

procedure TFormMain.UpdateTabTitle(ATab: TNecoTab);
begin
  if (ATab = nil) or (ATab.TitleLabel = nil) then
    Exit;
  ATab.TitleLabel.Text := ATab.DisplayTitle;
  ATab.Button.Hint := ATab.DisplayTitle;
  ATab.Button.ShowHint := True;
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

  FBtnShield := AddToolButton(ICO_ESCUDO, '', ShieldClick);
  // Selo com o número de bloqueados, no canto do escudo (como os selos de extensão do Chrome).
  FShieldBadge := TRectangle.Create(Self);
  FShieldBadge.Parent := FBtnShield;
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
  FBtnBookmarks := AddToolButton(ICO_MARCADOR, 'Favoritos (Ctrl+Shift+O)', BookmarksClick);
  FBtnHistory := AddToolButton(ICO_HISTORICO, 'Histórico (Ctrl+H)', HistoryClick);
  FBtnDownloads := AddToolButton(ICO_BAIXAR, 'Downloads (Ctrl+J)', DownloadsClick);
  FBtnTheme := AddToolButton(ICO_SOL, '', ThemeClick);
  FBtnSettings := AddToolButton(ICO_AJUSTES, 'Configurações', SettingsClick);

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
  UpdateShield;
  FBtnBookmarks.Restyle;
  FBtnHistory.Restyle;
  FBtnDownloads.Restyle;
  FBtnSettings.Restyle;
  // O botão mostra o tema para onde ele leva.
  if CurrentTheme = ntDark then
  begin
    FBtnTheme.IconData := ICO_SOL;
    FBtnTheme.Hint := 'Tema claro';
  end
  else
  begin
    FBtnTheme.IconData := ICO_LUA;
    FBtnTheme.Hint := 'Tema escuro';
  end;
  FBtnTheme.Restyle;
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
  Result := TNecoTab.Create(Self, FBlocklist, BlockerOn);
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
  if not FShuttingDown and (ATab.Url <> '') and not SameText(ATab.Url, 'about:blank') then
  begin
    FClosed.Add(ATab.Url);
    if FClosed.Count > 25 then
      FClosed.Delete(0);
  end;
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
  if FAddress.IsFocused then
    FAddress.ResetFocus;
end;

procedure TFormMain.TabNavigated(Sender: TObject; const AUrl: string);
begin
  FHistory.Add(AUrl, TNecoTab(Sender).Title);
  // Painel aberto: a visita nova aparece (as linhas não têm nada do motor).
  if FPanelHistory.Visible then
    FPanelHistory.Rebuild;
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
var
  U: string;
begin
  if Key = vkReturn then
  begin
    Key := 0;
    U := NecoInputToUrl(FAddress.Text, FSettings.SearchEngine);
    if (U = '') or (FActive = nil) then
      Exit;
    FActive.Navigate(U);
    FAddress.ResetFocus;
    FActive.Engine.Focus;
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
  FAddressBox.Stroke.Color := Palette.FieldBorder;
  UpdateAddress;
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
  FPanelBookmarks.OnOpen := BookmarkOpen;
  FPanelBookmarks.OnDelete := BookmarkDelete;
  FPanelBookmarks.OnRename := BookmarkRename;
  FPanelBookmarks.Rebuild;
  FBookmarks.OnChange := BookmarksChanged;

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
  Mark(FBtnBookmarks, FPanelBookmarks.Visible);
  Mark(FBtnDownloads, FPanelDownloads.Visible);
  Mark(FBtnSettings, FPanelSettings.Visible);
  Mark(FBtnHistory, FPanelHistory.Visible);
end;

procedure TFormMain.BookmarksClick(Sender: TObject);
begin
  TogglePanel(FPanelBookmarks);
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
      FHistory.Clear;
      try
        FHistory.SaveToFile(FSettings.HistoryFile);
      except
      end;
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
  // Favoritou: a Neco faz pose.
  if FBookmarks.Toggle(FActive.DisplayTitle, U) then
    FStage.Perform('turn');
end;

procedure TFormMain.BookmarksChanged(Sender: TObject);
begin
  // Quem muda a lista nunca é um clique numa linha do painel (BookmarkDelete adia).
  FPanelBookmarks.Rebuild;
  FBookmarkBar.Rebuild;
  UpdateStar;
  try
    FBookmarks.SaveToFile(FSettings.BookmarksFile);
  except
    // Sem disco agora: o SaveData do fechamento tenta de novo.
  end;
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

procedure TFormMain.SetBookmarkBarShown(AShow: Boolean);
begin
  FSettings.ShowBookmarkBar := AShow;
  // Align=Top: quem volta a ficar visível vai para o fim da pilha. Repõe a ordem.
  BeginUpdate;
  try
    FBookmarkBar.Visible := AShow;
    FBookmarkBar.Position.Y := FToolbar.Position.Y + FToolbar.Height;
    FProgressTrack.Position.Y := FBookmarkBar.Position.Y + FBookmarkBar.Height + 1;
  finally
    EndUpdate;
  end;
  Realign;
  FPanelSettings.Refresh;
  SaveSettings;
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

procedure TFormMain.SaveSettings;
begin
  try
    FSettings.Save;
  except
    // Sem disco agora: o SaveData do fechamento tenta de novo.
  end;
end;

procedure TFormMain.SetTheme(ATheme: TNecoTheme);
var
  T: TNecoTab;
begin
  FSettings.Theme := ATheme;
  NecoSetTheme(ATheme);
  ApplyTheme;
  // Os sites que respeitam prefers-color-scheme trocam junto.
  for T in FTabs do
    T.Engine.SetDarkMode(ATheme = ntDark);
  FPanelSettings.Refresh;
  SaveSettings;
end;

procedure TFormMain.ThemeClick(Sender: TObject);
begin
  if CurrentTheme = ntDark then
    SetTheme(ntLight)
  else
    SetTheme(ntDark);
end;

procedure TFormMain.SettingsClick(Sender: TObject);
begin
  TogglePanel(FPanelSettings);
end;

procedure TFormMain.SettingsChanged(Sender: TObject; AChange: TNecoSettingsChange);
var
  T: TNecoTab;
begin
  // O painel já gravou a escolha em FSettings; aqui ela passa a valer.
  case AChange of
    scTheme:
      begin
        SetTheme(FSettings.Theme);
        Exit; // SetTheme já gravou
      end;
    scBlocker:
      begin
        UpdateShield;
        if (FActive <> nil) and (FActive.Url <> '') then
          FActive.Engine.Reload;
      end;
    scBookmarkBar:
      begin
        SetBookmarkBarShown(FSettings.ShowBookmarkBar);
        Exit; // já gravou
      end;
    scAutofill:
      for T in FTabs do
        T.Engine.SetAutofill(FSettings.FormAutofill, FSettings.SavePasswords);
    scNeco:
      begin
        FStage.SetShown(FSettings.NecoShown);
        // As Necos dos painéis e da página de erro param de desenhar no próximo quadro.
        Invalidate;
      end;
  end;
  SaveSettings;
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
  if FBtnShield = nil then
    Exit;
  N := 0;
  if FActive <> nil then
    N := FActive.BlockedCount;
  if BlockerOn then
  begin
    FBtnShield.IconData := ICO_ESCUDO;
    FBtnShield.IconColor := Palette.Shield;
    if N = 1 then
      S := '1 anúncio ou rastreador barrado nesta página.'
    else
      S := Format('%d anúncios e rastreadores barrados nesta página.', [N]);
    FBtnShield.Hint := 'Bloqueador ligado: ' + S + ' Clique para desligar.';
  end
  else
  begin
    FBtnShield.IconData := ICO_ESCUDO_OFF;
    FBtnShield.IconColor := Palette.TextMuted;
    FBtnShield.Hint := 'Bloqueador desligado. Clique para ligar.';
    N := 0;
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
  FSettings.BlockerEnabled := not FSettings.BlockerEnabled;
  try
    FSettings.Save;
  except
    // Sem disco: a escolha vale até fechar o app.
  end;
  UpdateShield;
  FPanelSettings.Refresh;
  // Como as extensões de bloqueio: a página recarrega já com a nova regra.
  if (FActive <> nil) and (FActive.Url <> '') then
    FActive.Engine.Reload;
end;

function TFormMain.HandleShortcut(AKey: Word; AShift: TShiftState): Boolean;
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
    Acao := procedure begin SetBookmarkBarShown(not FSettings.ShowBookmarkBar); end
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

procedure TFormMain.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  // Antes do inherited: o FMX entrega a tecla ao controle com foco primeiro
  // e consome o Tab (inclusive Ctrl+Tab) para trocar o foco.
  if (Key <> 0) and HandleShortcut(Key, Shift) then
  begin
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  inherited;
end;

end.
