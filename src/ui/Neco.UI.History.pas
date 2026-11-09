unit Neco.UI.History;

{ Painel de histórico: as visitas mais recentes primeiro, separadas por dia, com uma
  caixa de busca (título ou endereço). Mostra o TNecoHistory (núcleo) e não o altera
  sozinho: abrir e limpar viram eventos para o form, que adia a ação para fora do clique
  (regra 5.3) e depois chama Rebuild.

  Limpar pede confirmação: o primeiro clique na lixeira só "arma" o botão (fica
  vermelho por alguns segundos); o segundo apaga. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.DateUtils,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Objects, FMX.Layouts, FMX.StdCtrls, FMX.Edit,
  Neco.Core.History, Neco.UI.Theme, Neco.UI.SidePanel, Neco.UI.Bookmarks;

type
  TNecoHistoryPanel = class(TNecoSidePanel)
  private
    FHistory: TNecoHistory;
    FSearchBox: TRectangle;
    FSearch: TEdit;
    FBtnClear: TNecoIconButton;
    FArmTimer: TTimer;
    FArmed: Boolean;
    FOnOpen: TNecoOpenUrlEvent;
    FOnClear: TNotifyEvent;
    procedure SearchChange(Sender: TObject);
    procedure SearchEnter(Sender: TObject);
    procedure SearchExit(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure ArmTimeout(Sender: TObject);
    procedure SetArmed(AValue: Boolean);
    procedure RowClick(Sender: TObject);
    procedure RowMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure RowHover(Sender: TObject);
    procedure StyleRow(ARow: TRectangle);
    procedure AddDayHeader(ADay: TDateTime);
    procedure AddEntry(const AEntry: TNecoHistoryEntry);
  public
    constructor Create(AOwner: TComponent); override;
    property History: TNecoHistory read FHistory write FHistory;
    /// Refaz as linhas. Não chamar de dentro de um clique numa linha.
    procedure Rebuild;
    procedure Restyle; override;
    /// Põe o cursor na busca (Ctrl+H com o painel aberto).
    procedure FocusSearch;
    property OnOpen: TNecoOpenUrlEvent read FOnOpen write FOnOpen;
    /// Segundo clique na lixeira: o form apaga o histórico.
    property OnClear: TNotifyEvent read FOnClear write FOnClear;
  end;

implementation

uses
  Neco.Core.Url;

const
  // Mais que isso pesa para montar e ninguém rola até lá: a busca acha o resto.
  CMaxRows = 300;

{ TNecoHistoryPanel }

constructor TNecoHistoryPanel.Create(AOwner: TComponent);
var
  Lupa: TPath;
begin
  CreatePanel(AOwner, 'Histórico',
    'Nada por aqui ainda. As páginas que você visitar aparecem nesta lista.', 'taunt');

  FBtnClear := AddHeaderButton(ICO_LIXEIRA, 'Limpar o histórico', ClearClick);
  FArmTimer := TTimer.Create(Self);
  FArmTimer.Enabled := False;
  FArmTimer.Interval := 4000;
  FArmTimer.OnTimer := ArmTimeout;

  // Busca logo abaixo do cabeçalho (o cabeçalho está em Y=0; a lista é Client).
  FSearchBox := TRectangle.Create(Self);
  FSearchBox.Parent := Self;
  FSearchBox.Position.Y := 100;
  FSearchBox.Align := TAlignLayout.Top;
  FSearchBox.Height := 34;
  FSearchBox.Margins.Rect := TRectF.Create(14, 0, 12, 8);
  FSearchBox.XRadius := 17;
  FSearchBox.YRadius := 17;
  FSearchBox.Stroke.Thickness := 1;
  FSearchBox.HitTest := False;
  Lupa := NecoNewIcon(Self, FSearchBox, ICO_LUPA, 14, Palette.TextMuted);
  Lupa.Align := TAlignLayout.Left;
  Lupa.Margins.Rect := TRectF.Create(12, 10, 6, 10);
  Lupa.Width := 14;
  FSearch := TEdit.Create(Self);
  FSearch.Parent := FSearchBox;
  FSearch.Align := TAlignLayout.Client;
  FSearch.Margins.Right := 10;
  FSearch.StyleLookup := 'transparentedit';
  FSearch.StyledSettings := [];
  FSearch.TextSettings.Font.Size := 13;
  FSearch.TextPrompt := 'Buscar no histórico';
  FSearch.OnChangeTracking := SearchChange;
  FSearch.OnEnter := SearchEnter;
  FSearch.OnExit := SearchExit;
  Restyle;
end;

procedure TNecoHistoryPanel.Rebuild;
var
  I, N: Integer;
  E: TNecoHistoryEntry;
  Q: string;
  Day, LastDay: TDateTime;
begin
  SetArmed(False);
  Q := LowerCase(Trim(FSearch.Text));
  List.BeginUpdate;
  try
    ClearRows;
    if FHistory = nil then
      Exit;
    N := 0;
    LastDay := -1;
    // A lista do núcleo é cronológica: a mais nova está no fim.
    for I := FHistory.Count - 1 downto 0 do
    begin
      E := FHistory[I];
      if (Q <> '') and (Pos(Q, LowerCase(E.Title)) = 0) and (Pos(Q, LowerCase(E.Url)) = 0) then
        Continue;
      Day := DateOf(E.Visited);
      if Day <> LastDay then
      begin
        AddDayHeader(Day);
        LastDay := Day;
      end;
      AddEntry(E);
      Inc(N);
      if N >= CMaxRows then
        Break;
    end;
  finally
    List.EndUpdate;
  end;
  if Q <> '' then
    EmptyText := 'Nenhuma página com "' + Trim(FSearch.Text) + '" no histórico.'
  else
    EmptyText := 'Nada por aqui ainda. As páginas que você visitar aparecem nesta lista.';
end;

procedure TNecoHistoryPanel.AddDayHeader(ADay: TDateTime);
var
  L: TLabel;
  T: string;
begin
  if ADay = Date then
    T := 'Hoje'
  else if ADay = Date - 1 then
    T := 'Ontem'
  else
    T := FormatDateTime('dddd, d "de" mmmm', ADay);
  L := NecoNewLabel(Self, nil, T, 12, Palette.TextMuted);
  L.Height := 30;
  L.Margins.Rect := TRectF.Create(10, 4, 0, 0);
  L.TextSettings.Font.Style := [TFontStyle.fsBold];
  L.HitTest := False;
  AppendRow(L);
end;

procedure TNecoHistoryPanel.AddEntry(const AEntry: TNecoHistoryEntry);
var
  R: TRectangle;
  Mid: TLayout;
  T, U, H: TLabel;
begin
  R := TRectangle.Create(Self);
  R.Height := 48;
  R.Margins.Rect := TRectF.Create(0, 0, 4, 1);
  R.XRadius := 8;
  R.YRadius := 8;
  R.Stroke.Kind := TBrushKind.None;
  R.Fill.Kind := TBrushKind.Solid;
  R.HitTest := True;
  R.Cursor := crHandPoint;
  R.TagString := AEntry.Url;
  R.Hint := AEntry.Url + sLineBreak + 'Clique para abrir; botão do meio abre em aba nova.';
  R.ShowHint := True;
  R.OnClick := RowClick;
  R.OnMouseDown := RowMouseDown;
  R.OnMouseEnter := RowHover;
  R.OnMouseLeave := RowHover;

  H := NecoNewLabel(Self, R, FormatDateTime('hh:nn', AEntry.Visited), 11, Palette.TextMuted);
  H.Align := TAlignLayout.Left;
  H.Width := 44;
  H.Margins.Left := 10;

  Mid := TLayout.Create(Self);
  Mid.Parent := R;
  Mid.Align := TAlignLayout.Client;
  Mid.HitTest := False;
  Mid.Margins.Rect := TRectF.Create(0, 6, 8, 6);
  T := NecoNewLabel(Self, Mid, AEntry.Title, 13);
  if T.Text = '' then
    T.Text := AEntry.Url;
  T.Align := TAlignLayout.Top;
  T.Height := 19;
  T.Position.Y := 0;
  U := NecoNewLabel(Self, Mid, NecoExtractHost(AEntry.Url), 11, Palette.TextMuted);
  U.Align := TAlignLayout.Top;
  U.Height := 16;
  U.Position.Y := 100;

  StyleRow(R);
  AppendRow(R);
end;

procedure TNecoHistoryPanel.StyleRow(ARow: TRectangle);
begin
  if ARow.IsMouseOver then
    ARow.Fill.Color := Palette.Hover
  else
    ARow.Fill.Color := TAlphaColors.Null;
end;

procedure TNecoHistoryPanel.RowClick(Sender: TObject);
begin
  if Assigned(FOnOpen) then
    FOnOpen(Self, TFmxObject(Sender).TagString, False);
end;

procedure TNecoHistoryPanel.RowMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if (Button = TMouseButton.mbMiddle) and Assigned(FOnOpen) then
    FOnOpen(Self, TFmxObject(Sender).TagString, True);
end;

procedure TNecoHistoryPanel.RowHover(Sender: TObject);
begin
  StyleRow(TRectangle(Sender));
end;

procedure TNecoHistoryPanel.SearchChange(Sender: TObject);
begin
  // O campo de busca não está nas linhas: refazer a lista aqui não o libera.
  Rebuild;
end;

procedure TNecoHistoryPanel.SearchEnter(Sender: TObject);
begin
  FSearchBox.Stroke.Color := Palette.Focus;
end;

procedure TNecoHistoryPanel.SearchExit(Sender: TObject);
begin
  FSearchBox.Stroke.Color := Palette.FieldBorder;
end;

procedure TNecoHistoryPanel.FocusSearch;
begin
  FSearch.SetFocus;
  FSearch.SelectAll;
end;

procedure TNecoHistoryPanel.SetArmed(AValue: Boolean);
begin
  FArmed := AValue;
  FArmTimer.Enabled := AValue;
  if AValue then
  begin
    FBtnClear.IconColor := Palette.Danger;
    FBtnClear.Hint := 'Clique de novo para apagar tudo';
  end
  else
  begin
    FBtnClear.IconColor := 0;
    FBtnClear.Hint := 'Limpar o histórico';
  end;
end;

procedure TNecoHistoryPanel.ClearClick(Sender: TObject);
begin
  if (FHistory = nil) or (FHistory.Count = 0) then
    Exit;
  if not FArmed then
  begin
    SetArmed(True);
    Exit;
  end;
  SetArmed(False);
  if Assigned(FOnClear) then
    FOnClear(Self);
end;

procedure TNecoHistoryPanel.ArmTimeout(Sender: TObject);
begin
  SetArmed(False);
end;

procedure TNecoHistoryPanel.Restyle;
var
  I: Integer;
begin
  inherited;
  if FSearchBox = nil then
    Exit;
  FSearchBox.Fill.Color := Palette.Field;
  if FSearch.IsFocused then
    FSearchBox.Stroke.Color := Palette.Focus
  else
    FSearchBox.Stroke.Color := Palette.FieldBorder;
  FSearch.TextSettings.FontColor := Palette.Text;
  SetArmed(FArmed);
  for I := 0 to RowCount - 1 do
    if Row(I) is TRectangle then
      StyleRow(TRectangle(Row(I)));
end;

end.
