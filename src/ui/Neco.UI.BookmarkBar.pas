unit Neco.UI.BookmarkBar;

{ Barra de favoritos, logo abaixo da barra de endereço (como no Chrome).

  Uma "pílula" por favorito, na ordem da lista. As que não cabem somem e aparece o
  botão », que abre o painel de favoritos. Clique abre na aba atual, botão do meio em
  aba nova, botão direito pede ao form para editar o nome (no painel).

  A barra só mostra o TNecoBookmarks; quem muda a lista é o form, fora dos cliques. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Objects, FMX.Layouts, FMX.StdCtrls,
  Neco.Core.Bookmarks, Neco.UI.Theme, Neco.UI.Bookmarks;

type
  TNecoBookmarkBar = class(TRectangle)
  private
    FBookmarks: TNecoBookmarks;
    FChips: TList<TRectangle>;
    FBtnMore: TNecoIconButton;
    FEmpty: TLabel;
    FOnOpen: TNecoOpenUrlEvent;
    FOnEdit: TNecoUrlNotify;
    FOnMore: TNotifyEvent;
    procedure ChipClick(Sender: TObject);
    procedure ChipMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure ChipHover(Sender: TObject);
    procedure MoreClick(Sender: TObject);
    procedure BarResized(Sender: TObject);
    procedure StyleChip(AChip: TRectangle);
    procedure LayoutChips;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Bookmarks: TNecoBookmarks read FBookmarks write FBookmarks;
    /// Refaz as pílulas. Não chamar de dentro de um clique numa pílula.
    procedure Rebuild;
    procedure Restyle;
    property OnOpen: TNecoOpenUrlEvent read FOnOpen write FOnOpen;
    /// Botão direito numa pílula: editar o nome.
    property OnEdit: TNecoUrlNotify read FOnEdit write FOnEdit;
    /// Botão »: abrir o painel com a lista inteira.
    property OnMore: TNotifyEvent read FOnMore write FOnMore;
  end;

const
  CBookmarkBarHeight = 34;

implementation

uses
  System.Math, FMX.TextLayout;

const
  CChipHeight = 26;
  CChipMaxWidth = 190;
  CChipGap = 4;

function TextWidth(const AText: string; ASize: Single): Single;
var
  L: TTextLayout;
begin
  L := TTextLayoutManager.DefaultTextLayout.Create;
  try
    L.BeginUpdate;
    try
      L.Font.Size := ASize;
      L.WordWrap := False;
      L.MaxSize := TPointF.Create(10000, 100);
      L.Text := AText;
    finally
      L.EndUpdate;
    end;
    Result := L.TextWidth;
  finally
    L.Free;
  end;
end;

{ TNecoBookmarkBar }

constructor TNecoBookmarkBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FChips := TList<TRectangle>.Create;
  Height := CBookmarkBarHeight;
  Stroke.Kind := TBrushKind.None;
  Fill.Kind := TBrushKind.Solid;
  ClipChildren := True;
  OnResized := BarResized;

  FBtnMore := NecoNewButton(Self, Self, ICO_CHEVRONS, 'Mais favoritos', MoreClick);
  FBtnMore.Width := 28;
  FBtnMore.Height := CChipHeight;
  FBtnMore.XRadius := 6;
  FBtnMore.YRadius := 6;
  FBtnMore.IconSize := 14;
  FBtnMore.Visible := False;

  FEmpty := NecoNewLabel(Self, Self,
    'Para os favoritos aparecerem aqui, clique na estrela da barra de endereço (Ctrl+D).', 12);
  FEmpty.SetBounds(14, 0, 700, CBookmarkBarHeight);
  Restyle;
end;

destructor TNecoBookmarkBar.Destroy;
begin
  FChips.Free;
  inherited;
end;

procedure TNecoBookmarkBar.Rebuild;
var
  I: Integer;
  B: TNecoBookmark;
  C: TRectangle;
  Ico: TPath;
  L: TLabel;
  T: string;
begin
  BeginUpdate;
  try
    for C in FChips do
      C.Free;
    FChips.Clear;
    if FBookmarks <> nil then
      for I := 0 to FBookmarks.Count - 1 do
      begin
        B := FBookmarks[I];
        T := B.Title;
        if T = '' then
          T := B.Url;
        C := TRectangle.Create(Self);
        C.Parent := Self;
        C.Height := CChipHeight;
        C.XRadius := 6;
        C.YRadius := 6;
        C.Stroke.Kind := TBrushKind.None;
        C.Fill.Kind := TBrushKind.Solid;
        C.HitTest := True;
        C.TagString := B.Url;
        C.Hint := T + sLineBreak + B.Url;
        C.ShowHint := True;
        C.OnClick := ChipClick;
        C.OnMouseDown := ChipMouseDown;
        C.OnMouseEnter := ChipHover;
        C.OnMouseLeave := ChipHover;
        C.Width := Min(CChipMaxWidth, 34 + TextWidth(T, 12));

        Ico := NecoNewIcon(Self, C, ICO_ESTRELA, 12, Palette.Star);
        Ico.Fill.Kind := TBrushKind.Solid;
        Ico.Fill.Color := Palette.Star;
        Ico.SetBounds(9, (CChipHeight - 12) / 2, 12, 12);
        L := NecoNewLabel(Self, C, T, 12);
        L.SetBounds(26, 0, C.Width - 32, CChipHeight);

        StyleChip(C);
        FChips.Add(C);
      end;
    FEmpty.Visible := FChips.Count = 0;
  finally
    EndUpdate;
  end;
  LayoutChips;
end;

procedure TNecoBookmarkBar.LayoutChips;
var
  C: TRectangle;
  X, Limit: Single;
  Hidden: Boolean;
begin
  // As que cabem, da esquerda para a direita; se sobrar alguma, o » no fim.
  X := 8;
  Limit := Width - 8 - FBtnMore.Width - CChipGap;
  Hidden := False;
  for C in FChips do
  begin
    if Hidden or (X + C.Width > Limit) then
    begin
      Hidden := True;
      C.Visible := False;
      Continue;
    end;
    C.Visible := True;
    C.SetBounds(X, (CBookmarkBarHeight - CChipHeight) / 2 - 1, C.Width, CChipHeight);
    X := X + C.Width + CChipGap;
  end;
  FBtnMore.Visible := Hidden;
  FBtnMore.SetBounds(Width - 8 - FBtnMore.Width, (CBookmarkBarHeight - CChipHeight) / 2 - 1,
    FBtnMore.Width, CChipHeight);
end;

procedure TNecoBookmarkBar.BarResized(Sender: TObject);
begin
  LayoutChips;
end;

procedure TNecoBookmarkBar.StyleChip(AChip: TRectangle);
var
  O: TFmxObject;
begin
  if AChip.IsMouseOver then
    AChip.Fill.Color := Palette.Hover
  else
    AChip.Fill.Color := TAlphaColors.Null;
  for O in AChip.Children do
    if O is TLabel then
      TLabel(O).TextSettings.FontColor := Palette.Text;
end;

procedure TNecoBookmarkBar.ChipClick(Sender: TObject);
begin
  if Assigned(FOnOpen) then
    FOnOpen(Self, TFmxObject(Sender).TagString, False);
end;

procedure TNecoBookmarkBar.ChipMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
begin
  if (Button = TMouseButton.mbMiddle) and Assigned(FOnOpen) then
    FOnOpen(Self, TFmxObject(Sender).TagString, True)
  else if (Button = TMouseButton.mbRight) and Assigned(FOnEdit) then
    FOnEdit(Self, TFmxObject(Sender).TagString);
end;

procedure TNecoBookmarkBar.ChipHover(Sender: TObject);
begin
  StyleChip(TRectangle(Sender));
end;

procedure TNecoBookmarkBar.MoreClick(Sender: TObject);
begin
  if Assigned(FOnMore) then
    FOnMore(Self);
end;

procedure TNecoBookmarkBar.Restyle;
var
  C: TRectangle;
begin
  Fill.Color := Palette.Toolbar;
  FEmpty.TextSettings.FontColor := Palette.TextMuted;
  FBtnMore.Restyle;
  for C in FChips do
    StyleChip(C);
end;

end.
