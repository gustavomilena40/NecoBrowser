unit Neco.UI.SidePanel;

{ Painel lateral (downloads, favoritos, configurações).

  Fica à direita da página e a encolhe; nunca fica por cima dela, porque a página é uma
  janela nativa (ver Neco.UI.Main). Montado em código: cabeçalho com título, botões e X;
  lista rolável de linhas; e um estado vazio com uma Neco, mostrado quando a lista não
  tem linhas.

  As linhas são do painel filho; este só as empilha (Align = Top, ordem pelo
  Position.Y) e as libera. Quem remove uma linha a partir de um clique nela adia a
  remoção (regra 5.3). }

interface

uses
  System.Classes, System.Types, System.UITypes, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Objects, FMX.Layouts, FMX.StdCtrls,
  Neco.UI.Theme, Neco.UI.Neco;

type
  TNecoSidePanel = class(TRectangle)
  private
    FDivider: TRectangle;
    FHeader: TLayout;
    FTitle: TLabel;
    FHeaderButtons: TLayout;
    FBtnClose: TNecoIconButton;
    FHeaderExtra: TList<TNecoIconButton>;
    FList: TVertScrollBox;
    FRows: TList<TControl>;
    FTopY, FBottomY: Single;
    FEmpty: TLayout;
    FEmptySprite: TNecoSprite;
    FEmptyText: TLabel;
    FOnCloseRequest: TNotifyEvent;
    procedure CloseClick(Sender: TObject);
    procedure UpdateEmpty;
    procedure LayoutHeaderButtons;
    function GetEmptyText: string;
    procedure SetEmptyText(const AValue: string);
  protected
    /// Botão no cabeçalho, à esquerda do X.
    function AddHeaderButton(const AIcon, AHint: string; AOnClick: TNotifyEvent): TNecoIconButton;
    /// Põe a linha na lista (no topo ou no fim). O painel passa a ser o dono dela.
    procedure AppendRow(ARow: TControl; AOnTop: Boolean = False);
    /// Libera a linha. Não chamar de dentro de um evento da própria linha.
    procedure RemoveRow(ARow: TControl);
    procedure ClearRows;
    function RowCount: Integer;
    function Row(AIndex: Integer): TControl;
    property List: TVertScrollBox read FList;
    /// Texto do estado vazio (ex.: busca sem resultado).
    property EmptyText: string read GetEmptyText write SetEmptyText;
  public
    constructor CreatePanel(AOwner: TComponent; const ATitle, AEmptyText, AEmptyAnim: string);
    destructor Destroy; override;
    procedure Restyle; virtual;
    /// O X do cabeçalho foi clicado: o form esconde o painel.
    property OnCloseRequest: TNotifyEvent read FOnCloseRequest write FOnCloseRequest;
  end;

implementation

{ TNecoSidePanel }

constructor TNecoSidePanel.CreatePanel(AOwner: TComponent; const ATitle, AEmptyText,
  AEmptyAnim: string);
begin
  inherited Create(AOwner);
  FRows := TList<TControl>.Create;
  FHeaderExtra := TList<TNecoIconButton>.Create;
  Align := TAlignLayout.Right;
  Width := CSidePanelWidth;
  Stroke.Kind := TBrushKind.None;
  Fill.Kind := TBrushKind.Solid;

  FDivider := TRectangle.Create(Self);
  FDivider.Parent := Self;
  FDivider.Align := TAlignLayout.Left;
  FDivider.Width := 1;
  FDivider.Stroke.Kind := TBrushKind.None;
  FDivider.HitTest := False;

  FHeader := TLayout.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := TAlignLayout.Top;
  FHeader.Height := 48;
  FHeader.Padding.Rect := TRectF.Create(16, 7, 8, 7);

  FTitle := NecoNewLabel(Self, FHeader, ATitle, 15);
  FTitle.Align := TAlignLayout.Client;
  FTitle.TextSettings.Font.Style := [TFontStyle.fsBold];

  FHeaderButtons := TLayout.Create(Self);
  FHeaderButtons.Parent := FHeader;
  FHeaderButtons.Align := TAlignLayout.Right;
  FHeaderButtons.Width := CButtonSize;
  FBtnClose := NecoNewButton(Self, FHeaderButtons, ICO_FECHAR, 'Fechar painel', CloseClick);
  LayoutHeaderButtons;

  FList := TVertScrollBox.Create(Self);
  FList.Parent := Self;
  FList.Align := TAlignLayout.Client;
  FList.Margins.Rect := TRectF.Create(8, 0, 4, 8);
  FList.ShowScrollBars := True;

  // Estado vazio: a Neco e uma frase, no lugar da lista.
  FEmpty := TLayout.Create(Self);
  FEmpty.Parent := Self;
  FEmpty.Align := TAlignLayout.Client;
  FEmpty.Padding.Rect := TRectF.Create(24, 40, 24, 0);
  FEmpty.HitTest := False;
  FEmptySprite := TNecoSprite.Create(Self);
  FEmptySprite.Parent := FEmpty;
  FEmptySprite.Align := TAlignLayout.Top;
  FEmptySprite.Height := 110;
  FEmptySprite.Scale := 2;
  FEmptySprite.AnimName := AEmptyAnim;
  FEmptyText := NecoNewLabel(Self, FEmpty, AEmptyText, 13);
  FEmptyText.Align := TAlignLayout.Top;
  FEmptyText.Position.Y := 1000;
  FEmptyText.Height := 60;
  FEmptyText.Margins.Top := 12;
  FEmptyText.TextSettings.WordWrap := True;
  FEmptyText.TextSettings.HorzAlign := TTextAlign.Center;
  FEmptyText.TextSettings.VertAlign := TTextAlign.Leading;

  UpdateEmpty;
  Restyle;
end;

destructor TNecoSidePanel.Destroy;
begin
  // As linhas são filhas da lista e morrem com ela (regra 5.1); a lista de ponteiros não.
  FRows.Free;
  FHeaderExtra.Free;
  inherited;
end;

procedure TNecoSidePanel.CloseClick(Sender: TObject);
begin
  if Assigned(FOnCloseRequest) then
    FOnCloseRequest(Self);
end;

function TNecoSidePanel.AddHeaderButton(const AIcon, AHint: string;
  AOnClick: TNotifyEvent): TNecoIconButton;
begin
  Result := NecoNewButton(Self, FHeaderButtons, AIcon, AHint, AOnClick);
  FHeaderExtra.Add(Result);
  LayoutHeaderButtons;
end;

procedure TNecoSidePanel.LayoutHeaderButtons;
var
  B: TNecoIconButton;
  X: Single;
begin
  // Posição calculada (sem Align): os extras na ordem em que entraram, o X por último.
  X := 0;
  for B in FHeaderExtra do
  begin
    B.SetBounds(X, 0, CButtonSize, CButtonSize);
    X := X + CButtonSize + 2;
  end;
  FBtnClose.SetBounds(X, 0, CButtonSize, CButtonSize);
  FHeaderButtons.Width := X + CButtonSize;
end;

procedure TNecoSidePanel.AppendRow(ARow: TControl; AOnTop: Boolean);
begin
  // Align = Top ordena pelo Y: topo com Y cada vez menor, fim com Y cada vez maior.
  if AOnTop then
  begin
    FTopY := FTopY - 1000;
    ARow.Position.Y := FTopY;
    FRows.Insert(0, ARow);
  end
  else
  begin
    FBottomY := FBottomY + 1000;
    ARow.Position.Y := FBottomY;
    FRows.Add(ARow);
  end;
  ARow.Parent := FList;
  ARow.Align := TAlignLayout.Top;
  UpdateEmpty;
end;

procedure TNecoSidePanel.RemoveRow(ARow: TControl);
begin
  if FRows.Remove(ARow) < 0 then
    Exit;
  ARow.Free;
  UpdateEmpty;
end;

procedure TNecoSidePanel.ClearRows;
var
  R: TControl;
begin
  FList.BeginUpdate;
  try
    for R in FRows.ToArray do
      R.Free;
    FRows.Clear;
  finally
    FList.EndUpdate;
  end;
  FTopY := 0;
  FBottomY := 0;
  UpdateEmpty;
end;

function TNecoSidePanel.RowCount: Integer;
begin
  Result := FRows.Count;
end;

function TNecoSidePanel.Row(AIndex: Integer): TControl;
begin
  Result := FRows[AIndex];
end;

function TNecoSidePanel.GetEmptyText: string;
begin
  Result := FEmptyText.Text;
end;

procedure TNecoSidePanel.SetEmptyText(const AValue: string);
begin
  FEmptyText.Text := AValue;
end;

procedure TNecoSidePanel.UpdateEmpty;
begin
  FEmpty.Visible := FRows.Count = 0;
  FList.Visible := FRows.Count > 0;
end;

procedure TNecoSidePanel.Restyle;
begin
  Fill.Color := Palette.Panel;
  FDivider.Fill.Color := Palette.Divider;
  FTitle.TextSettings.FontColor := Palette.Text;
  FEmptyText.TextSettings.FontColor := Palette.TextMuted;
  FBtnClose.Restyle;
end;

end.
