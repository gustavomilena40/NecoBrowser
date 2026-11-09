unit Neco.UI.ErrorView;

{ Página de erro do NecoBrowser: site não encontrado, sem internet, tempo esgotado,
  conexão recusada, ou falha do próprio motor.

  É FMX, por cima da área da página. Por causa do "espaço aéreo" (a página é uma janela
  nativa por cima do FMX), o form esconde o motor da aba enquanto esta tela aparece.
  Não mexe no histórico do motor: Voltar continua funcionando normalmente.

  A Neco muda com o caso: tombo (endereço não existe) ou maca (rede com problema). }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Objects, FMX.Layouts, FMX.StdCtrls,
  Neco.Engine.Intf, Neco.UI.Theme, Neco.UI.Neco;

type
  TNecoErrorView = class(TRectangle)
  private
    FColumn: TLayout;
    FSprite: TNecoSprite;
    FTitle: TLabel;
    FText: TLabel;
    FButtonRow: TLayout;
    FBtnRetry: TNecoIconButton;
    FOnRetry: TNotifyEvent;
    procedure RetryClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    /// Prepara o texto e a Neco. AEngineMessage <> '' = falha do motor (não da rede).
    procedure Prepare(AError: TNecoNavError; const AUrl, AEngineMessage: string);
    procedure Restyle;
    property OnRetry: TNotifyEvent read FOnRetry write FOnRetry;
  end;

implementation

uses
  Neco.Core.Url;

function Darken(AColor: TAlphaColor; AFactor: Single): TAlphaColor;
var
  C: TAlphaColorRec;
begin
  C.Color := AColor;
  C.R := Round(C.R * AFactor);
  C.G := Round(C.G * AFactor);
  C.B := Round(C.B * AFactor);
  Result := C.Color;
end;

{ TNecoErrorView }

constructor TNecoErrorView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Stroke.Kind := TBrushKind.None;
  Fill.Kind := TBrushKind.Solid;
  HitTest := True; // não deixa o clique passar para trás

  FColumn := TLayout.Create(Self);
  FColumn.Parent := Self;
  FColumn.Align := TAlignLayout.Center;
  FColumn.Width := 520;
  FColumn.Height := 380;

  FSprite := TNecoSprite.Create(Self);
  FSprite.Parent := FColumn;
  // Posições fixas na coluna (Align=Top entre irmãos ordenou errado aqui).
  FSprite.SetBounds(0, 0, 520, 170);

  FTitle := NecoNewLabel(Self, FColumn, '', 22);
  FTitle.SetBounds(0, 188, 520, 34);
  FTitle.TextSettings.HorzAlign := TTextAlign.Center;
  FTitle.TextSettings.Font.Style := [TFontStyle.fsBold];

  FText := NecoNewLabel(Self, FColumn, '', 14);
  FText.SetBounds(0, 230, 520, 64);
  FText.TextSettings.WordWrap := True;
  FText.TextSettings.HorzAlign := TTextAlign.Center;
  FText.TextSettings.VertAlign := TTextAlign.Leading;

  FButtonRow := TLayout.Create(Self);
  FButtonRow.Parent := FColumn;
  FButtonRow.SetBounds(0, 304, 520, 40);
  FBtnRetry := NecoNewButton(Self, FButtonRow, ICO_SINCRONIZAR, 'Tentar abrir o endereço de novo (F5)',
    RetryClick);
  FBtnRetry.CaptionText := 'Tentar de novo';
  FBtnRetry.Align := TAlignLayout.Center;
  FBtnRetry.Width := 170;
  FBtnRetry.Height := 38;
  FBtnRetry.XRadius := 19;
  FBtnRetry.YRadius := 19;
  FBtnRetry.IconSize := 16;
  FBtnRetry.Cursor := crHandPoint;
  Restyle;
end;

procedure TNecoErrorView.Prepare(AError: TNecoNavError; const AUrl, AEngineMessage: string);
var
  Host, T, M, A: string;
begin
  Host := NecoExtractHost(AUrl);
  if Host = '' then
    Host := AUrl;
  if AEngineMessage <> '' then
  begin
    A := 'stretcher';
    T := 'A página não conseguiu abrir';
    M := AEngineMessage;
  end
  else
    case AError of
      neNotFound:
        begin
          A := 'tumble';
          T := 'A Neco tropeçou no endereço';
          M := Format('Não achamos o site %s. Confira se o endereço está escrito certo ' +
            '(ou se a internet está funcionando).', [Host]);
        end;
      neOffline:
        begin
          A := 'stretcher';
          T := 'Sem internet';
          M := 'A Neco foi parar na maca: este computador parece estar sem conexão. ' +
            'Confira o Wi-Fi ou o cabo e tente de novo.';
        end;
      neTimeout:
        begin
          A := 'stretcher';
          T := 'O site demorou demais';
          M := Format('%s não respondeu a tempo. Pode ser o site ou a sua rede; ' +
            'tente de novo daqui a pouco.', [Host]);
        end;
    else
      A := 'stretcher';
      T := 'Não foi possível conectar';
      M := Format('%s recusou ou derrubou a conexão. Tente de novo daqui a pouco.', [Host]);
    end;
  FTitle.Text := T;
  FText.Text := M;
  // A maca é larga: escala 2. O tombo é pequeno: escala 3.
  if A = 'tumble' then
    FSprite.Scale := 3
  else
    FSprite.Scale := 2;
  if FSprite.AnimName <> A then
    FSprite.AnimName := A;
end;

procedure TNecoErrorView.RetryClick(Sender: TObject);
begin
  if Assigned(FOnRetry) then
    FOnRetry(Self);
end;

procedure TNecoErrorView.Restyle;
begin
  Fill.Color := Palette.Window;
  FTitle.TextSettings.FontColor := Palette.Text;
  FText.TextSettings.FontColor := Palette.TextMuted;
  FBtnRetry.BaseColor := Palette.Accent;
  FBtnRetry.HoverColor := Darken(Palette.Accent, 0.88);
  FBtnRetry.PressedColor := Darken(Palette.Accent, 0.76);
  FBtnRetry.IconColor := TAlphaColors.White;
end;

end.
