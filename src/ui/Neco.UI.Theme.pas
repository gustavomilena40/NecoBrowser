unit Neco.UI.Theme;

{ Tokens visuais do NecoBrowser (cores, medidas, ícones Lucide) e o botão de ícone.
  A interface é montada em código: as cores ficam só aqui, e trocar o tema é
  trocar a paleta e chamar Restyle em quem desenha. }

interface

uses
  System.Classes, System.UITypes, System.Types,
  FMX.Types, FMX.Controls, FMX.Objects, FMX.Graphics, FMX.StdCtrls,
  Neco.Core.Settings;

type
  TNecoPalette = record
    Window: TAlphaColor;       // fundo da faixa de abas
    Toolbar: TAlphaColor;      // barra de endereço e aba ativa
    TabHover: TAlphaColor;
    Field: TAlphaColor;        // caixa do endereço
    FieldBorder: TAlphaColor;
    Focus: TAlphaColor;        // borda do campo com foco
    Text: TAlphaColor;
    TextMuted: TAlphaColor;
    Hover: TAlphaColor;
    Pressed: TAlphaColor;
    Panel: TAlphaColor;        // painéis laterais
    Divider: TAlphaColor;
    Accent: TAlphaColor;       // progresso, links
    Star: TAlphaColor;
    Shield: TAlphaColor;       // bloqueador ligado
    Danger: TAlphaColor;
  end;

const
  // A faixa de abas é também a barra de título (Neco.UI.Frame). A altura cabe a
  // Neco de pé em tamanho natural (45 px de altura nos sprites).
  CTabStripHeight = 46;
  CTabTop = 8;                 // espaço acima das abas (arrastar e redimensionar pelo topo)
  CTabHeight = CTabStripHeight - CTabTop;
  CCaptionButtonWidth = 46;    // minimizar, maximizar e fechar, como no Windows 11
  CCaptionButtonHeight = 34;
  CNecoSeatWidth = 72;         // o canto da Neco, entre as abas e os botões da janela
  CCloseHover = $FFC42B1C;     // fundo do X da janela com o mouse em cima
  CCloseHoverPressed = $FFB22A1B;
  CToolbarHeight = 46;
  CButtonSize = 34;
  CIconSize = 18;
  CTabMaxWidth = 220;
  CTabMinWidth = 72;
  CSidePanelWidth = 340;
  CFontSize = 13;

  ICO_VOLTAR =
    'M0 0 M24 24 M12 19 L5 12 L12 5 M19 12 L5 12';
  ICO_SETA =
    'M0 0 M24 24 M5 12 L19 12 M12 5 L19 12 L12 19';
  ICO_RECARREGAR =
    'M0 0 M24 24 M21 12 C21 16.971 16.971 21 12 21 C7.029 21 3 16.971 3 12 C3 7.029 7.029 3 12 ' +
    '3 C14.52 3 16.93 4 18.74 5.74 L21 8 M21 3 L21 8 L16 8';
  ICO_FECHAR =
    'M0 0 M24 24 M18 6 L6 18 M6 6 L18 18';
  ICO_MAIS =
    'M0 0 M24 24 M5 12 L19 12 M12 5 L12 19';
  ICO_CADEADO =
    'M0 0 M24 24 M5 11 L19 11 C20.105 11 21 11.895 21 13 L21 20 C21 21.105 20.105 22 19 22 L5 2' +
    '2 C3.895 22 3 21.105 3 20 L3 13 C3 11.895 3.895 11 5 11 Z M7 11 L7 7 C7 4.239 9.239 2 12 2' +
    ' C14.761 2 17 4.239 17 7 L17 11';
  ICO_GLOBO =
    'M0 0 M24 24 M2 12 C2 17.523 6.477 22 12 22 C17.523 22 22 17.523 22 12 C22 6.477 17.523 2 1' +
    '2 2 C6.477 2 2 6.477 2 12 Z M12 2 C6.667 7.6 6.667 16.4 12 22 C17.333 16.4 17.333 7.6 12 2' +
    ' M2 12 L22 12';
  ICO_ESCUDO =
    'M0 0 M24 24 M20 13 C20 18 16.5 20.5 12.34 21.95 C12.122 22.024 11.886 22.02 11.67 21.94 C7' +
    '.5 20.5 4 18 4 13 L4 6 C4 5.448 4.448 5 5 5 C7 5 9.5 3.8 11.24 2.28 C11.678 1.906 12.322 1' +
    '.906 12.76 2.28 C14.51 3.81 17 5 19 5 C19.552 5 20 5.448 20 6 Z';
  ICO_ESCUDO_OFF =
    'M0 0 M24 24 M2 2 L22 22 M5 5 C4.448 5 4 5.448 4 6 L4 13 C4 18 7.5 20.5 11.67 21.94 C11.886' +
    ' 22.02 12.122 22.024 12.34 21.95 C14.69 21.13 16.82 19.98 18.24 18.24 M9.309 3.652 C9.995 ' +
    '3.258 10.642 2.799 11.24 2.28 C11.678 1.906 12.322 1.906 12.76 2.28 C14.51 3.81 17 5 19 5 ' +
    'C19.552 5 20 5.448 20 6 L20 13 C20.001 13.423 19.974 13.845 19.92 14.264';
  ICO_ESTRELA =
    'M0 0 M24 24 M11.525 2.295 C11.614 2.114 11.798 2 12 2 C12.202 2 12.386 2.114 12.475 2.295 ' +
    'L14.785 6.974 C15.094 7.599 15.69 8.033 16.38 8.134 L21.546 8.89 C21.746 8.919 21.912 9.05' +
    '9 21.974 9.251 C22.036 9.442 21.984 9.653 21.84 9.794 L18.104 13.432 C17.604 13.919 17.375' +
    ' 14.622 17.493 15.31 L18.375 20.45 C18.41 20.65 18.329 20.852 18.165 20.971 C18.001 21.09 ' +
    '17.783 21.105 17.604 21.01 L12.986 18.582 C12.368 18.258 11.631 18.258 11.013 18.582 L6.39' +
    '6 21.01 C6.217 21.105 6 21.089 5.836 20.97 C5.673 20.851 5.591 20.649 5.626 20.45 L6.507 1' +
    '5.311 C6.625 14.622 6.397 13.92 5.896 13.432 L2.16 9.795 C2.014 9.654 1.962 9.443 2.024 9.' +
    '25 C2.087 9.058 2.253 8.917 2.454 8.889 L7.619 8.134 C8.31 8.034 8.907 7.6 9.216 6.974 Z';
  ICO_BAIXAR =
    'M0 0 M24 24 M21 15 L21 19 C21 20.105 20.105 21 19 21 L5 21 C3.895 21 3 20.105 3 19 L3 15 M' +
    '7 10 L12 15 L17 10 M12 15 L12 3';
  ICO_MARCADOR =
    'M0 0 M24 24 M19 21 L12 17 L5 21 L5 5 C5 3.895 5.895 3 7 3 L17 3 C18.105 3 19 3.895 19 5 L1' +
    '9 21 Z';
  ICO_SOL =
    'M0 0 M24 24 M8 12 C8 14.209 9.791 16 12 16 C14.209 16 16 14.209 16 12 C16 9.791 14.209 8 1' +
    '2 8 C9.791 8 8 9.791 8 12 Z M12 2 L12 4 M12 20 L12 22 M4.93 4.93 L6.34 6.34 M17.66 17.66 L' +
    '19.07 19.07 M2 12 L4 12 M20 12 L22 12 M6.34 17.66 L4.93 19.07 M19.07 4.93 L17.66 6.34';
  ICO_LUA =
    'M0 0 M24 24 M12 3 C9.515 5.485 9.515 9.515 12 12 C14.485 14.485 18.515 14.485 21 12 C21 16' +
    '.971 16.971 21 12 21 C7.029 21 3 16.971 3 12 C3 7.029 7.029 3 12 3 Z';
  ICO_PASTA =
    'M0 0 M24 24 M20 20 C21.105 20 22 19.105 22 18 L22 8 C22 6.895 21.105 6 20 6 L12.1 6 C11.42' +
    ' 6.007 10.784 5.668 10.41 5.1 L9.6 3.9 C9.23 3.338 8.603 3 7.93 3 L4 3 C2.895 3 2 3.895 2 ' +
    '5 L2 18 C2 19.105 2.895 20 4 20 Z';
  ICO_LIXEIRA =
    'M0 0 M24 24 M3 6 L21 6 M19 6 L19 20 C19 21 18 22 17 22 L7 22 C6 22 5 21 5 20 L5 6 M8 6 L8 ' +
    '4 C8 3 9 2 10 2 L14 2 C15 2 16 3 16 4 L16 6';
  ICO_AJUSTES =
    'M0 0 M24 24 M20 7 L11 7 M14 17 L5 17 M14 17 C14 18.657 15.343 20 17 20 C18.657 20 20 18.65' +
    '7 20 17 C20 15.343 18.657 14 17 14 C15.343 14 14 15.343 14 17 Z M4 7 C4 8.657 5.343 10 7 1' +
    '0 C8.657 10 10 8.657 10 7 C10 5.343 8.657 4 7 4 C5.343 4 4 5.343 4 7 Z';
  ICO_OK =
    'M0 0 M24 24 M20 6 L9 17 L4 12';
  ICO_ARQUIVO =
    'M0 0 M24 24 M15 2 L6 2 C4.895 2 4 2.895 4 4 L4 20 C4 21.105 4.895 22 6 22 L18 22 C19.105 2' +
    '2 20 21.105 20 20 L20 7 Z M14 2 L14 6 C14 7.105 14.895 8 16 8 L20 8';
  ICO_SINCRONIZAR =
    'M0 0 M24 24 M3 12 C3 7.029 7.029 3 12 3 C14.516 3.009 16.931 3.991 18.74 5.74 L21 8 M21 3 ' +
    'L21 8 L16 8 M21 12 C21 16.971 16.971 21 12 21 C9.484 20.991 7.069 20.009 5.26 18.26 L3 16 ' +
    'M8 16 L3 16 L3 21';
  ICO_LAPIS =
    'M0 0 M24 24 M21.174 6.812 C22.275 5.711 22.275 3.926 21.174 2.826 C20.074 1.725 18.289 1.7' +
    '24 17.188 2.825 L3.842 16.174 C3.61 16.406 3.438 16.691 3.342 17.004 L2.021 21.356 C1.968 ' +
    '21.532 2.017 21.723 2.147 21.853 C2.277 21.983 2.468 22.031 2.644 21.978 L6.997 20.658 C7.' +
    '31 20.563 7.595 20.392 7.827 20.161 Z M15 5 L19 9';
  ICO_CHEVRONS =
    'M0 0 M24 24 M6 17 L11 12 L6 7 M13 17 L18 12 L13 7';
  ICO_HISTORICO =
    'M0 0 M24 24 M3 12 C3 16.971 7.029 21 12 21 C16.971 21 21 16.971 21 12 C21 7.029 16.971 3 1' +
    '2 3 C9.484 3.009 7.069 3.991 5.26 5.74 L3 8 M3 3 L3 8 L8 8 M12 7 L12 12 L16 14';
  ICO_LUPA =
    'M0 0 M24 24 M3 11 C3 15.418 6.582 19 11 19 C15.418 19 19 15.418 19 11 C19 6.582 15.418 3 1' +
    '1 3 C6.582 3 3 6.582 3 11 Z M21 21 L16.7 16.7';
  // Botões da janela, no traço fino do Windows 11 (desenhados com traço 1).
  ICO_JANELA_MINIMIZAR =
    'M0 0 M24 24 M2 12 L22 12';
  ICO_JANELA_MAXIMIZAR =
    'M0 0 M24 24 M2 2 L22 2 L22 22 L2 22 Z';
  ICO_JANELA_RESTAURAR =
    'M0 0 M24 24 M2 7 L17 7 L17 22 L2 22 Z M7 7 L7 2 L22 2 L22 17 L17 17';
  ICO_JANELA_FECHAR =
    'M0 0 M24 24 M2 2 L22 22 M22 2 L2 22';

type
  /// Botão quadrado (ou com texto) desenhado com TRectangle + TPath (+ TLabel).
  /// Só o retângulo recebe clique; ícone e texto têm HitTest = False.
  TNecoIconButton = class(TRectangle)
  private
    FIcon: TPath;
    FCaption: TLabel;
    FHover: Boolean;
    FIconColor: TAlphaColor;   // 0 = cor de texto da paleta
    FFilled: Boolean;
    FBaseColor: TAlphaColor;   // 0 = transparente
    FHoverColor: TAlphaColor;  // 0 = Palette.Hover
    FHoverIconColor: TAlphaColor; // 0 = a mesma cor do ícone
    FPressedColor: TAlphaColor;   // 0 = Palette.Pressed
    FHot: Boolean;             // hover vindo de fora (botão maximizar: o mouse está no não-cliente)
    procedure SetIconData(const AValue: string);
    procedure SetIconColor(AValue: TAlphaColor);
    procedure SetFilled(AValue: Boolean);
    procedure SetBaseColor(AValue: TAlphaColor);
    procedure SetHot(AValue: Boolean);
    procedure SetIconSize(AValue: Single);
    function GetCaptionText: string;
    procedure SetCaptionText(const AValue: string);
  protected
    procedure DoMouseEnter; override;
    procedure DoMouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure EnabledChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Restyle;
    property IconData: string write SetIconData;
    property IconColor: TAlphaColor read FIconColor write SetIconColor;
    property Filled: Boolean read FFilled write SetFilled;
    property BaseColor: TAlphaColor read FBaseColor write SetBaseColor;
    property HoverColor: TAlphaColor read FHoverColor write FHoverColor;
    property HoverIconColor: TAlphaColor read FHoverIconColor write FHoverIconColor;
    property PressedColor: TAlphaColor read FPressedColor write FPressedColor;
    property Hot: Boolean read FHot write SetHot;
    property IconSize: Single write SetIconSize;
    property CaptionText: string read GetCaptionText write SetCaptionText;
    property Icon: TPath read FIcon;
  end;

var
  Palette: TNecoPalette;
  CurrentTheme: TNecoTheme = ntDark;

procedure NecoSetTheme(ATheme: TNecoTheme);
function NecoNewLabel(AOwner: TComponent; AParent: TFmxObject; const AText: string;
  ASize: Single = CFontSize; AColor: TAlphaColor = 0): TLabel;
function NecoNewButton(AOwner: TComponent; AParent: TFmxObject; const AIcon, AHint: string;
  AOnClick: TNotifyEvent): TNecoIconButton;
/// Ícone solto (decoração: HitTest = False), traço 2 arredondado.
function NecoNewIcon(AOwner: TComponent; AParent: TFmxObject; const AIcon: string;
  ASize: Single; AColor: TAlphaColor): TPath;

implementation

uses
  System.SysUtils;

const
  // Escuro um pouco mais claro que o original (pedido do usuário em 2026-11-09):
  // cada tom subiu ~8 a 10 pontos, mantendo o contraste entre as camadas.
  CDark: TNecoPalette = (
    Window: $FF27282C; Toolbar: $FF35373B; TabHover: $FF3F4146; Field: $FF27282C;
    FieldBorder: $FF45474D; Focus: $FF5B8DEF; Text: $FFE8E8E8; TextMuted: $FFA0A6AC;
    Hover: $FF45474D; Pressed: $FF55575D; Panel: $FF2D2E32; Divider: $FF45474D;
    Accent: $FF5B8DEF; Star: $FFF5C542; Shield: $FF3DDC84; Danger: $FFF2545B);
  CLight: TNecoPalette = (
    Window: $FFDEE1E6; Toolbar: $FFFFFFFF; TabHover: $FFE8EAED; Field: $FFF1F3F4;
    FieldBorder: $FFDADCE0; Focus: $FF1A73E8; Text: $FF202124; TextMuted: $FF5F6368;
    Hover: $FFE8EAED; Pressed: $FFDADCE0; Panel: $FFF8F9FA; Divider: $FFDADCE0;
    Accent: $FF1A73E8; Star: $FFE3A008; Shield: $FF1E8E3E; Danger: $FFD93025);

procedure NecoSetTheme(ATheme: TNecoTheme);
begin
  CurrentTheme := ATheme;
  if ATheme = ntLight then
    Palette := CLight
  else
    Palette := CDark;
end;

function NecoNewLabel(AOwner: TComponent; AParent: TFmxObject; const AText: string;
  ASize: Single; AColor: TAlphaColor): TLabel;
begin
  Result := TLabel.Create(AOwner);
  Result.Parent := AParent;
  Result.StyledSettings := [];
  Result.HitTest := False;
  Result.Text := AText;
  Result.TextSettings.Font.Size := ASize;
  if AColor = 0 then
    Result.TextSettings.FontColor := Palette.Text
  else
    Result.TextSettings.FontColor := AColor;
  Result.TextSettings.WordWrap := False;
  Result.TextSettings.Trimming := TTextTrimming.Character;
end;

function NecoNewButton(AOwner: TComponent; AParent: TFmxObject; const AIcon, AHint: string;
  AOnClick: TNotifyEvent): TNecoIconButton;
begin
  Result := TNecoIconButton.Create(AOwner);
  Result.Parent := AParent;
  Result.IconData := AIcon;
  Result.Hint := AHint;
  Result.ShowHint := AHint <> '';
  Result.OnClick := AOnClick;
end;

function NecoNewIcon(AOwner: TComponent; AParent: TFmxObject; const AIcon: string;
  ASize: Single; AColor: TAlphaColor): TPath;
begin
  Result := TPath.Create(AOwner);
  Result.Parent := AParent;
  Result.HitTest := False;
  Result.Width := ASize;
  Result.Height := ASize;
  Result.WrapMode := TPathWrapMode.Fit;
  Result.Fill.Kind := TBrushKind.None;
  Result.Stroke.Thickness := 2;
  Result.Stroke.Cap := TStrokeCap.Round;
  Result.Stroke.Join := TStrokeJoin.Round;
  Result.Stroke.Color := AColor;
  Result.Data.Data := AIcon;
end;

{ TNecoIconButton }

constructor TNecoIconButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := CButtonSize;
  Height := CButtonSize;
  XRadius := 8;
  YRadius := 8;
  Stroke.Kind := TBrushKind.None;
  HitTest := True;
  Cursor := crDefault;

  FIcon := TPath.Create(Self);
  FIcon.Parent := Self;
  FIcon.HitTest := False;
  FIcon.Align := TAlignLayout.Center;
  FIcon.Width := CIconSize;
  FIcon.Height := CIconSize;
  FIcon.WrapMode := TPathWrapMode.Fit;
  FIcon.Stroke.Thickness := 2;
  FIcon.Stroke.Cap := TStrokeCap.Round;
  FIcon.Stroke.Join := TStrokeJoin.Round;
  Restyle;
end;

procedure TNecoIconButton.SetIconData(const AValue: string);
begin
  FIcon.Data.Data := AValue;
end;

procedure TNecoIconButton.SetIconColor(AValue: TAlphaColor);
begin
  FIconColor := AValue;
  Restyle;
end;

procedure TNecoIconButton.SetFilled(AValue: Boolean);
begin
  FFilled := AValue;
  Restyle;
end;

procedure TNecoIconButton.SetBaseColor(AValue: TAlphaColor);
begin
  FBaseColor := AValue;
  Restyle;
end;

procedure TNecoIconButton.SetHot(AValue: Boolean);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  Restyle;
end;

procedure TNecoIconButton.SetIconSize(AValue: Single);
begin
  FIcon.Width := AValue;
  FIcon.Height := AValue;
end;

function TNecoIconButton.GetCaptionText: string;
begin
  if FCaption <> nil then
    Result := FCaption.Text
  else
    Result := '';
end;

procedure TNecoIconButton.SetCaptionText(const AValue: string);
begin
  if FCaption = nil then
  begin
    // Com texto: ícone à esquerda e rótulo ocupando o resto.
    FIcon.Align := TAlignLayout.Left;
    FIcon.Margins.Rect := TRectF.Create(10, 8, 6, 8);
    FCaption := NecoNewLabel(Self, Self, '');
    FCaption.Align := TAlignLayout.Client;
    FCaption.Margins.Right := 8;
  end;
  FCaption.Text := AValue;
  Restyle;
end;

procedure TNecoIconButton.Restyle;
var
  C: TAlphaColor;
  Over: Boolean;
begin
  Over := (FHover or FHot) and Enabled;
  if Over and (FHoverColor <> 0) then
    Fill.Color := FHoverColor
  else if Over then
    Fill.Color := Palette.Hover
  else if FBaseColor <> 0 then
    Fill.Color := FBaseColor
  else
    Fill.Color := TAlphaColors.Null;
  Fill.Kind := TBrushKind.Solid;

  if Over and (FHoverIconColor <> 0) then
    C := FHoverIconColor
  else if FIconColor <> 0 then
    C := FIconColor
  else
    C := Palette.Text;
  FIcon.Stroke.Color := C;
  if FFilled then
  begin
    FIcon.Fill.Kind := TBrushKind.Solid;
    FIcon.Fill.Color := C;
  end
  else
    FIcon.Fill.Kind := TBrushKind.None;
  if FCaption <> nil then
    FCaption.TextSettings.FontColor := C; // o texto acompanha o ícone
  if Enabled then
    Opacity := 1
  else
    Opacity := 0.35;
end;

procedure TNecoIconButton.DoMouseEnter;
begin
  inherited;
  FHover := True;
  Restyle;
end;

procedure TNecoIconButton.DoMouseLeave;
begin
  inherited;
  FHover := False;
  Restyle;
end;

procedure TNecoIconButton.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if Enabled and (FPressedColor <> 0) then
    Fill.Color := FPressedColor
  else if Enabled then
    Fill.Color := Palette.Pressed;
  inherited;
end;

procedure TNecoIconButton.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  // O OnClick pode ter destruído coisas ao redor, mas não este botão (ninguém
  // libera um botão dentro do clique dele: regra 5.3).
  Restyle;
end;

procedure TNecoIconButton.EnabledChanged;
begin
  inherited;
  Restyle;
end;

initialization
  NecoSetTheme(ntDark);

end.
