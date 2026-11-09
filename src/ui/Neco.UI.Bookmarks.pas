unit Neco.UI.Bookmarks;

{ Painel de favoritos. Mostra o TNecoBookmarks (núcleo) e não o altera sozinho: abrir e
  apagar viram eventos para o form, que adia a ação para fora do clique (regra 5.3) e
  depois chama Rebuild. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Objects, FMX.Layouts, FMX.StdCtrls, FMX.Edit,
  Neco.Core.Bookmarks, Neco.UI.Theme, Neco.UI.SidePanel;

type
  /// ANewTab: abrir em aba nova (botão do meio).
  TNecoOpenUrlEvent = procedure(Sender: TObject; const AUrl: string; ANewTab: Boolean) of object;
  TNecoUrlNotify = procedure(Sender: TObject; const AUrl: string) of object;
  TNecoRenameEvent = procedure(Sender: TObject; const AUrl, ATitle: string) of object;

  TNecoBookmarksPanel = class(TNecoSidePanel)
  private
    FBookmarks: TNecoBookmarks;
    FFaviconDir: string;
    FOnOpen: TNecoOpenUrlEvent;
    FOnDelete: TNecoUrlNotify;
    FOnRename: TNecoRenameEvent;
    // edição do nome (um campo por vez)
    FEdit: TEdit;
    FEditLabel: TLabel;
    FEditUrl: string;
    FEditDone: Boolean;
    procedure EditClick(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    procedure EditExit(Sender: TObject);
    procedure FinishEdit(ACommit: Boolean);
    procedure RowClick(Sender: TObject);
    procedure RowMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure RowHover(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure StyleRow(ARow: TRectangle);
  public
    constructor Create(AOwner: TComponent); override;
    /// Lista que o painel mostra (não é dono dela).
    property Bookmarks: TNecoBookmarks read FBookmarks write FBookmarks;
    /// Pasta dos ícones dos sites (sem ícone guardado: estrela).
    property FaviconDir: string read FFaviconDir write FFaviconDir;
    /// Refaz as linhas a partir da lista. Não chamar de dentro de um clique numa linha.
    procedure Rebuild;
    procedure Restyle; override;
    /// Troca o título da linha por um campo de texto (Enter salva, Esc cancela).
    procedure BeginEdit(const AUrl: string);
    property OnOpen: TNecoOpenUrlEvent read FOnOpen write FOnOpen;
    property OnDelete: TNecoUrlNotify read FOnDelete write FOnDelete;
    /// Nome novo confirmado. O form adia a mudança na lista (Rebuild libera o campo).
    property OnRename: TNecoRenameEvent read FOnRename write FOnRename;
  end;

implementation

uses
  Neco.Core.Favicons;

{ TNecoBookmarksPanel }

constructor TNecoBookmarksPanel.Create(AOwner: TComponent);
begin
  CreatePanel(AOwner, 'Favoritos',
    'Nenhum favorito ainda. Clique na estrela da barra de endereço (ou Ctrl+D) e a Neco guarda a página.',
    'turn');
end;

procedure TNecoBookmarksPanel.Rebuild;
var
  I: Integer;
  B: TNecoBookmark;
  R: TRectangle;
  Mid: TLayout;
  T, U: TLabel;
  Ico: TPath;
  Img: TImage;
  F: string;
  Del, Ed: TNecoIconButton;
begin
  // Um campo em edição morre junto com a linha: sem avisos dele daqui para frente.
  FEditDone := True;
  FEdit := nil;
  FEditLabel := nil;
  List.BeginUpdate;
  try
    ClearRows;
    if FBookmarks = nil then
      Exit;
    for I := 0 to FBookmarks.Count - 1 do
    begin
      B := FBookmarks[I];
      R := TRectangle.Create(Self);
      R.Height := 52;
      R.Margins.Rect := TRectF.Create(0, 0, 4, 2);
      R.XRadius := 8;
      R.YRadius := 8;
      R.Stroke.Kind := TBrushKind.None;
      R.Fill.Kind := TBrushKind.Solid;
      R.HitTest := True;
      R.Cursor := crHandPoint;
      R.TagString := B.Url;
      R.Hint := B.Url + sLineBreak + 'Clique para abrir; botão do meio abre em aba nova.';
      R.ShowHint := True;
      R.OnClick := RowClick;
      R.OnMouseDown := RowMouseDown;
      R.OnMouseEnter := RowHover;
      R.OnMouseLeave := RowHover;

      Img := nil;
      F := NecoFaviconFile(FFaviconDir, B.Url);
      if (F <> '') and FileExists(F) then
      begin
        Img := TImage.Create(Self);
        Img.Parent := R;
        Img.HitTest := False;
        Img.WrapMode := TImageWrapMode.Fit;
        Img.Align := TAlignLayout.Left;
        Img.Width := 16;
        Img.Margins.Rect := TRectF.Create(12, 18, 10, 18);
        try
          Img.Bitmap.LoadFromFile(F);
        except
          FreeAndNil(Img);
        end;
      end;
      if Img = nil then
      begin
        Ico := NecoNewIcon(Self, R, ICO_ESTRELA, 16, Palette.Star);
        Ico.Align := TAlignLayout.Left;
        Ico.Margins.Rect := TRectF.Create(12, 18, 10, 18);
        Ico.Fill.Kind := TBrushKind.Solid;
        Ico.Fill.Color := Palette.Star;
      end;

      Del := NecoNewButton(Self, R, ICO_LIXEIRA, 'Remover dos favoritos', DeleteClick);
      Del.Align := TAlignLayout.Right;
      Del.Width := 30;
      Del.Height := 30;
      Del.IconSize := 15;
      Del.IconColor := Palette.TextMuted;
      Del.Margins.Rect := TRectF.Create(0, 11, 6, 11);
      Del.TagString := B.Url;

      Ed := NecoNewButton(Self, R, ICO_LAPIS, 'Editar o nome', EditClick);
      Ed.Align := TAlignLayout.Right;
      Ed.Width := 30;
      Ed.Height := 30;
      Ed.IconSize := 14;
      Ed.IconColor := Palette.TextMuted;
      Ed.Margins.Rect := TRectF.Create(0, 11, 0, 11);
      Ed.TagString := B.Url;

      Mid := TLayout.Create(Self);
      Mid.Parent := R;
      Mid.Align := TAlignLayout.Client;
      Mid.HitTest := False;
      Mid.Margins.Rect := TRectF.Create(0, 8, 4, 8);
      T := NecoNewLabel(Self, Mid, B.Title, 13);
      if T.Text = '' then
        T.Text := B.Url;
      T.Align := TAlignLayout.Top;
      T.Height := 19;
      T.Position.Y := 0;
      R.TagObject := T; // o título, para a edição achar
      U := NecoNewLabel(Self, Mid, B.Url, 11, Palette.TextMuted);
      U.Align := TAlignLayout.Top;
      U.Height := 16;
      U.Position.Y := 100;

      StyleRow(R);
      AppendRow(R);
    end;
  finally
    List.EndUpdate;
  end;
end;

procedure TNecoBookmarksPanel.StyleRow(ARow: TRectangle);
begin
  if ARow.IsMouseOver then
    ARow.Fill.Color := Palette.Hover
  else
    ARow.Fill.Color := TAlphaColors.Null;
end;

procedure TNecoBookmarksPanel.RowClick(Sender: TObject);
begin
  if Assigned(FOnOpen) then
    FOnOpen(Self, TFmxObject(Sender).TagString, False);
end;

procedure TNecoBookmarksPanel.RowMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if (Button = TMouseButton.mbMiddle) and Assigned(FOnOpen) then
    FOnOpen(Self, TFmxObject(Sender).TagString, True);
end;

procedure TNecoBookmarksPanel.RowHover(Sender: TObject);
begin
  StyleRow(TRectangle(Sender));
end;

procedure TNecoBookmarksPanel.DeleteClick(Sender: TObject);
begin
  if Assigned(FOnDelete) then
    FOnDelete(Self, TFmxObject(Sender).TagString);
end;

procedure TNecoBookmarksPanel.EditClick(Sender: TObject);
begin
  BeginEdit(TFmxObject(Sender).TagString);
end;

procedure TNecoBookmarksPanel.BeginEdit(const AUrl: string);
var
  I: Integer;
  R: TControl;
begin
  if FEdit <> nil then
    FinishEdit(True);
  for I := 0 to RowCount - 1 do
  begin
    R := Row(I);
    if (R.TagString <> AUrl) or not (R.TagObject is TLabel) then
      Continue;
    FEditLabel := TLabel(R.TagObject);
    FEditUrl := AUrl;
    FEditDone := False;
    FEdit := TEdit.Create(Self);
    FEdit.Parent := FEditLabel.Parent;
    FEdit.Position.Y := -10; // antes do título na pilha
    FEdit.Align := TAlignLayout.Top;
    FEdit.Height := 22;
    FEdit.StyledSettings := [];
    FEdit.TextSettings.Font.Size := 13;
    FEdit.TextSettings.FontColor := Palette.Text;
    FEdit.Text := FEditLabel.Text;
    FEdit.KillFocusByReturn := False;
    FEdit.OnKeyDown := EditKeyDown;
    FEdit.OnExit := EditExit;
    FEditLabel.Visible := False;
    FEdit.SetFocus;
    FEdit.SelectAll;
    Exit;
  end;
end;

procedure TNecoBookmarksPanel.FinishEdit(ACommit: Boolean);
var
  T: string;
begin
  if FEditDone or (FEdit = nil) then
    Exit;
  FEditDone := True;
  T := Trim(FEdit.Text);
  // Esconde (não libera: pode estar dentro de um evento do próprio campo). O próximo
  // Rebuild leva o campo junto com a linha.
  FEdit.Visible := False;
  FEditLabel.Visible := True;
  if ACommit and (T <> '') and (T <> FEditLabel.Text) then
  begin
    FEditLabel.Text := T;
    if Assigned(FOnRename) then
      FOnRename(Self, FEditUrl, T);
  end;
end;

procedure TNecoBookmarksPanel.EditKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    Key := 0;
    FinishEdit(True);
  end
  else if Key = vkEscape then
  begin
    Key := 0;
    FinishEdit(False);
  end;
end;

procedure TNecoBookmarksPanel.EditExit(Sender: TObject);
begin
  FinishEdit(True);
end;

procedure TNecoBookmarksPanel.Restyle;
begin
  inherited;
  // As linhas pegam as cores na montagem: refazer é o jeito mais simples de trocar o tema.
  if RowCount > 0 then
    Rebuild;
end;

end.
