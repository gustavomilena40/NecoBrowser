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
  Neco.Engine.Intf, Neco.UI.Theme, Neco.UI.Tab;

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

    // tela
    FToolbar: TRectangle;
    FBtnBack, FBtnForward, FBtnReload: TNecoIconButton;
    FAddressBox: TRectangle;
    FAddressIcon: TPath;
    FAddress: TEdit;
    FProgressTrack: TLayout;
    FProgress: TRectangle;
    FProgressTimer: TTimer;
    FBody: TLayout;
    FPageArea: TLayout;
    FPageMessage: TLabel;

    procedure BuildUI;
    procedure BuildToolbar;
    procedure ApplyTheme;
    procedure LoadData;
    procedure SaveData;
    function BlockerOn: Boolean;

    // abas
    function NewTab(const AUrl: string; AActivate: Boolean = True): TNecoTab;
    procedure ActivateTab(ATab: TNecoTab);
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
  System.IOUtils, System.Math,
  Neco.Core.Url, Neco.Engine.Factory;

{$R *.fmx}

{ TFormMain }

procedure TFormMain.FormCreate(Sender: TObject);
var
  Cfg: TNecoEngineConfig;
begin
  FTabs := TObjectList<TNecoTab>.Create(False);
  LoadData;
  NecoSetTheme(FSettings.Theme);

  Cfg.WebDataDir := FSettings.WebDataDir;
  Cfg.DownloadsDir := FSettings.DownloadsDir;
  Cfg.Language := 'pt-BR';
  Cfg.BackgroundColor := Palette.Window;
  NecoEngineSetup(Cfg);

  BuildUI;
  ApplyTheme;
end;

procedure TFormMain.FormShow(Sender: TObject);
begin
  // A primeira aba precisa do HWND do form, que só existe com a janela criada.
  if FStarted then
    Exit;
  FStarted := True;
  NewTab(FSettings.HomeUrl);
end;

procedure TFormMain.FormClose(Sender: TObject; var Action: TCloseAction);
var
  T: TNecoTab;
begin
  if FShuttingDown then
    Exit;
  FShuttingDown := True;
  FProgressTimer.Enabled := False;
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
  FreeAndNil(FHistory);
  FreeAndNil(FBookmarks);
  FreeAndNil(FBlocklist);
  FreeAndNil(FSettings);
end;

procedure TFormMain.LoadData;
begin
  FSettings := TNecoSettings.Create;
  FSettings.Load;
  FBlocklist := TNecoBlocklist.Create;
  FBlocklist.LoadFromFile(System.IOUtils.TPath.Combine(ExtractFilePath(ParamStr(0)), 'blocklist-hosts.txt'));
  FBookmarks := TNecoBookmarks.Create;
  FBookmarks.LoadFromFile(FSettings.BookmarksFile);
  FHistory := TNecoHistory.Create;
  FHistory.LoadFromFile(FSettings.HistoryFile);
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

  FToolbar := TRectangle.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Align := TAlignLayout.Top;
  FToolbar.Height := CToolbarHeight;
  FToolbar.Stroke.Kind := TBrushKind.None;
  FToolbar.Position.Y := 0;
  BuildToolbar;

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

  FPageMessage := NecoNewLabel(Self, FPageArea, '', 15);
  FPageMessage.Align := TAlignLayout.Center;
  FPageMessage.Width := 640;
  FPageMessage.Height := 120;
  FPageMessage.TextSettings.WordWrap := True;
  FPageMessage.TextSettings.HorzAlign := TTextAlign.Center;
  FPageMessage.Visible := False;
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

  FAddressBox := TRectangle.Create(Self);
  FAddressBox.Parent := FToolbar;
  FAddressBox.Align := TAlignLayout.Client;
  FAddressBox.Margins.Rect := TRectF.Create(8, 7, 12, 7);
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
end;

procedure TFormMain.ApplyTheme;
begin
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := Palette.Window;
  FToolbar.Fill.Color := Palette.Toolbar;
  FAddressBox.Fill.Color := Palette.Field;
  if FAddress.IsFocused then
    FAddressBox.Stroke.Color := Palette.Focus
  else
    FAddressBox.Stroke.Color := Palette.FieldBorder;
  FAddressIcon.Stroke.Color := Palette.TextMuted;
  FAddress.TextSettings.FontColor := Palette.Text;
  FProgress.Fill.Color := Palette.Accent;
  FPageMessage.TextSettings.FontColor := Palette.TextMuted;
  FBtnBack.Restyle;
  FBtnForward.Restyle;
  FBtnReload.Restyle;
end;

{ Abas }

function TFormMain.NewTab(const AUrl: string; AActivate: Boolean): TNecoTab;
begin
  Result := TNecoTab.Create(Self, FBlocklist, BlockerOn);
  Result.OnChanged := TabChanged;
  Result.OnNewWindow := TabNewWindow;
  Result.OnDownload := TabDownload;
  Result.OnKey := TabKey;
  Result.OnPageFocus := TabPageFocus;
  Result.OnNavigated := TabNavigated;
  Result.Engine.SetDarkMode(CurrentTheme = ntDark);
  Result.Engine.SetVisible(False);
  FTabs.Add(Result);
  if AActivate or (FActive = nil) then
    ActivateTab(Result);
  Result.Navigate(AUrl);
end;

procedure TFormMain.ActivateTab(ATab: TNecoTab);
var
  T: TNecoTab;
begin
  FActive := ATab;
  for T in FTabs do
    if T <> ATab then
      T.Engine.SetVisible(False);
  if ATab <> nil then
  begin
    LayoutEngine;
    ATab.Engine.SetVisible(True);
  end;
  UpdateNavButtons;
  UpdateAddress;
  UpdateProgress;
  UpdateCaption;
  UpdatePageMessage;
end;

procedure TFormMain.CloseTab(ATab: TNecoTab);
var
  I: Integer;
begin
  I := FTabs.IndexOf(ATab);
  if I < 0 then
    Exit;
  ATab.Close;
  FTabs.Delete(I);
  if FActive = ATab then
  begin
    FActive := nil;
    if FTabs.Count > 0 then
      ActivateTab(FTabs[Min(I, FTabs.Count - 1)]);
  end;
  ATab.Free;
  if FTabs.Count = 0 then
    NewTab(FSettings.HomeUrl);
end;

procedure TFormMain.TabChanged(Sender: TObject; AChange: TNecoTabChange);
begin
  if Sender <> FActive then
    Exit;
  case AChange of
    tcTitle:
      UpdateCaption;
    tcUrl:
      UpdateAddress;
    tcLoading:
      begin
        UpdateProgress;
        UpdateNavButtons;
      end;
    tcHistory:
      UpdateNavButtons;
    tcError:
      begin
        UpdateProgress;
        UpdatePageMessage;
      end;
  end;
end;

procedure TFormMain.TabNewWindow(Sender: TObject; const AUrl: string);
begin
  TNecoTab(Sender).Navigate(AUrl);
end;

procedure TFormMain.TabDownload(Sender: TObject; const ADownload: INecoDownload);
begin
  // Painel de downloads: etapa 6.
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
begin
  FPageMessage.Visible := (FActive <> nil) and (FActive.Error <> '');
  if FPageMessage.Visible then
    FPageMessage.Text := FActive.Error;
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

function TFormMain.HandleShortcut(AKey: Word; AShift: TShiftState): Boolean;
var
  Acao: TProc;
begin
  Acao := nil;
  if (AShift * [ssCtrl, ssAlt, ssShift] = [ssCtrl]) and (AKey = vkL) then
    Acao := FocusAddress
  else if (AShift * [ssCtrl, ssAlt, ssShift] = [ssCtrl]) and (AKey = vkW) then
    Acao := procedure begin CloseTab(FActive); end
  else if (AShift * [ssCtrl, ssAlt] = []) and (AKey = vkF5) then
    Acao := procedure begin ReloadClick(nil); end
  else if (AShift * [ssCtrl, ssAlt, ssShift] = [ssAlt]) and (AKey = vkLeft) then
    Acao := procedure begin BackClick(nil); end
  else if (AShift * [ssCtrl, ssAlt, ssShift] = [ssAlt]) and (AKey = vkRight) then
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
