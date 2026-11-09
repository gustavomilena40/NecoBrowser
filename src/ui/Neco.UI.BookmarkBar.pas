unit Neco.UI.BookmarkBar;

{ Barra de favoritos, logo abaixo da barra de endereço (como no Chrome).

  Uma "pílula" por favorito, na ordem da lista. As que não cabem somem e aparece o
  botão », que abre o painel de favoritos. Clique abre na aba atual, botão do meio em
  Aba nova, botão direito pede ao form para editar o nome (no painel).

  Cada pílula mostra o ícone do site, se já foi guardado (Neco.Core.Favicons); sem
  ícone, só o nome. Arrastar uma pílula muda a posição (como as abas).

  A barra só mostra o TNecoBookmarks; quem muda a lista é o form, fora dos cliques. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Objects, FMX.Layouts, FMX.StdCtrls,
  Neco.Core.Bookmarks, Neco.UI.Theme, Neco.UI.Bookmarks;

type
  TNecoMoveEvent = procedure(Sender: TObject; AFrom, ATo: Integer) of object;

  TNecoBookmarkBar = class(TRectangle)
  private
    FBookmarks: TNecoBookmarks;
    FChips: TList<TRectangle>;
    FBtnMore: TNecoIconButton;
    FEmpty: TLabel;
    FOnOpen: TNecoOpenUrlEvent;
    FOnEdit: TNecoUrlNotify;
    FOnMore: TNotifyEvent;
    FOnMove: TNecoMoveEvent;
    FFaviconDir: string;
    // arrasto de uma pílula
    FDragChip: TRectangle;
    FDragging: Boolean;
    FDragStartX, FDragGrabX: Single;
    FDragFrom: Integer;
    FSuppressClick: Boolean;
    function BarX(ASender: TObject; X, Y: Single): Single;
    procedure ChipMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure ChipMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
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
    /// Pasta dos ícones dos sites.
    property FaviconDir: string read FFaviconDir write FFaviconDir;
    /// Refaz as pílulas. Não chamar de dentro de um clique numa pílula.
    procedure Rebuild;
    procedure Restyle;
    property OnOpen: TNecoOpenUrlEvent read FOnOpen write FOnOpen;
    /// Botão direito numa pílula: editar o nome.
    property OnEdit: TNecoUrlNotify read FOnEdit write FOnEdit;
    /// Botão »: abrir o painel com a lista inteira.
    property OnMore: TNotifyEvent read FOnMore write FOnMore;
    /// Pílula arrastada para outra posição (índices da lista). O form adia a mudança.
    property OnMove: TNecoMoveEvent read FOnMove write FOnMove;
  end;

const
  CBookmarkBarHeight = 34;

implementation

uses
  System.Math, FMX.TextLayout, Neco.Core.Favicons;

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
  Img: TImage;
  L: TLabel;
  T, F: string;
  TextX: Single;
begin
  // As pílulas vão embora: um arrasto em andamento acaba aqui.
  FDragChip := nil;
  FDragging := False;
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
        C.OnMouseMove := ChipMouseMove;
        C.OnMouseUp := ChipMouseUp;

        // Ícone do site, se a Neco já guardou; senão só o nome (sem estrela).
        TextX := 10;
        F := NecoFaviconFile(FFaviconDir, B.Url);
        if (F <> '') and FileExists(F) then
        begin
          Img := TImage.Create(Self);
          Img.Parent := C;
          Img.HitTest := False;
          Img.WrapMode := TImageWrapMode.Fit;
          try
            Img.Bitmap.LoadFromFile(F);
            Img.SetBounds(9, (CChipHeight - 16) / 2, 16, 16);
            TextX := 31;
          except
            Img.Free; // PNG estragado: fica sem ícone
          end;
        end;
        C.Width := Min(CChipMaxWidth, TextX + 10 + TextWidth(T, 12));
        L := NecoNewLabel(Self, C, T, 12);
        L.SetBounds(TextX, 0, C.Width - TextX - 6, CChipHeight);

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
    // A arrastada segue o mouse; as outras abrem espaço para ela.
    if not (FDragging and (C = FDragChip)) then
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
  // Fim de um arrasto não é clique.
  if FSuppressClick then
  begin
    FSuppressClick := False;
    Exit;
  end;
  if Assigned(FOnOpen) then
    FOnOpen(Self, TFmxObject(Sender).TagString, False);
end;

procedure TNecoBookmarkBar.ChipMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
begin
  if Button = TMouseButton.mbLeft then
  begin
    // Pode virar arrasto (ChipMouseMove) se o mouse andar mais que uns pixels.
    FDragChip := TRectangle(Sender);
    FDragging := False;
    FSuppressClick := False;
    FDragStartX := BarX(Sender, X, Y);
    FDragGrabX := FDragStartX - FDragChip.Position.X;
    FDragFrom := FChips.IndexOf(FDragChip);
  end
  else if (Button = TMouseButton.mbMiddle) and Assigned(FOnOpen) then
    FOnOpen(Self, TFmxObject(Sender).TagString, True)
  else if (Button = TMouseButton.mbRight) and Assigned(FOnEdit) then
    FOnEdit(Self, TFmxObject(Sender).TagString);
end;

function TNecoBookmarkBar.BarX(ASender: TObject; X, Y: Single): Single;
begin
  Result := AbsoluteToLocal(TControl(ASender).LocalToAbsolute(TPointF.Create(X, Y))).X;
end;

procedure TNecoBookmarkBar.ChipMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
var
  C: TRectangle;
  P, NewX, Center: Single;
  Cur, Idx: Integer;
begin
  if (FDragChip = nil) or (Sender <> FDragChip) or not (ssLeft in Shift) then
    Exit;
  P := BarX(Sender, X, Y);
  if not FDragging then
  begin
    if Abs(P - FDragStartX) < 6 then
      Exit; // clique comum, não arrasto
    FDragging := True;
    FDragChip.BringToFront;
    FDragChip.Opacity := 0.85;
  end;
  NewX := Max(8, Min(Width - 8 - FDragChip.Width, P - FDragGrabX));
  FDragChip.Position.X := NewX;
  // Nova vaga: quantas pílulas visíveis ficam com o centro à esquerda do centro dela.
  Center := NewX + FDragChip.Width / 2;
  Idx := 0;
  for C in FChips do
    if (C <> FDragChip) and C.Visible and (C.Position.X + C.Width / 2 < Center) then
      Inc(Idx);
  Cur := FChips.IndexOf(FDragChip);
  if Idx <> Cur then
  begin
    FChips.Move(Cur, Idx);
    LayoutChips;
  end;
end;

procedure TNecoBookmarkBar.ChipMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
var
  ToIdx: Integer;
begin
  if (Button <> TMouseButton.mbLeft) or (Sender <> FDragChip) then
    Exit;
  if FDragging then
  begin
    FDragging := False;
    FDragChip.Opacity := 1;
    FSuppressClick := True; // o OnClick vem logo depois deste evento
    ToIdx := FChips.IndexOf(FDragChip);
    LayoutChips; // encaixa na vaga
    FDragChip := nil;
    if (ToIdx <> FDragFrom) and Assigned(FOnMove) then
      FOnMove(Self, FDragFrom, ToIdx);
  end
  else
    FDragChip := nil;
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
