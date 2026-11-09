unit Neco.UI.Settings;

{ Painel de configurações: motor de busca, tema, bloqueador e a Neco.

  O painel altera o TNecoSettings direto e avisa o form (OnChanged), que aplica e grava.
  As linhas são criadas uma vez e só mudam de estilo (Refresh): nenhum clique libera
  controle (regra 5.3). }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Objects, FMX.Layouts, FMX.StdCtrls,
  Neco.Core.Url, Neco.Core.Settings, Neco.UI.Theme, Neco.UI.Neco, Neco.UI.SidePanel;

type
  TNecoSettingsChange = (scSearch, scTheme, scBlocker, scAutofill, scNeco);
  TNecoSettingsChangeEvent = procedure(Sender: TObject; AChange: TNecoSettingsChange) of object;

  /// Uma linha clicável: opção de escolha única (bolinha) ou chave liga/desliga.
  TNecoOptionRow = class(TRectangle)
  private
    FSwitch: Boolean;
    FChecked: Boolean;
    FMark: TCircle;      // bolinha (opção) ou trilho (chave)
    FTrack: TRectangle;
    FDot: TCircle;       // miolo da bolinha ou botão da chave
    FTitle: TLabel;
    FSub: TLabel;
    procedure Hover(Sender: TObject);
    procedure SetChecked(AValue: Boolean);
  public
    constructor CreateRow(AOwner: TComponent; ASwitch: Boolean; const ATitle, ASub: string);
    procedure Restyle;
    property Checked: Boolean read FChecked write SetChecked;
  end;

  TNecoSettingsPanel = class(TNecoSidePanel)
  private
    FSettings: TNecoSettings;
    FBlockedHosts: Integer;
    FSearch: array[TNecoSearchEngine] of TNecoOptionRow;
    FTheme: array[TNecoTheme] of TNecoOptionRow;
    FBlocker: TNecoOptionRow;
    FForms: TNecoOptionRow;
    FPasswords: TNecoOptionRow;
    FNeco: TNecoOptionRow;
    FNecoSprite: TNecoSprite;
    FSections: TArray<TLabel>;
    FOnChanged: TNecoSettingsChangeEvent;
    procedure Section(const AText: string);
    function Option(ASwitch: Boolean; const ATitle, ASub: string): TNecoOptionRow;
    procedure RowClick(Sender: TObject);
    procedure DoChanged(AChange: TNecoSettingsChange);
  public
    /// ABlockedHosts: tamanho da lista de bloqueio (só para mostrar).
    constructor CreateFor(AOwner: TComponent; ASettings: TNecoSettings; ABlockedHosts: Integer);
    /// Marca as linhas pelo que está em Settings (mudou por fora: escudo, botão de tema).
    procedure Refresh;
    procedure Restyle; override;
    property OnChanged: TNecoSettingsChangeEvent read FOnChanged write FOnChanged;
  end;

implementation

const
  CEngineTitle: array[TNecoSearchEngine] of string = ('DuckDuckGo', 'Google', 'DuckDuckGo HTML');
  CEngineSub: array[TNecoSearchEngine] of string = ('privado, sem rastrear a busca',
    'o padrão', 'versão leve, sem JavaScript: abre num piscar');
  CThemeTitle: array[TNecoTheme] of string = ('Escuro', 'Claro');

{ TNecoOptionRow }

constructor TNecoOptionRow.CreateRow(AOwner: TComponent; ASwitch: Boolean; const ATitle, ASub: string);
var
  Mid: TLayout;
  Box: TLayout;
begin
  inherited Create(AOwner);
  FSwitch := ASwitch;
  Height := 50;
  Margins.Rect := TRectF.Create(0, 0, 4, 2);
  XRadius := 8;
  YRadius := 8;
  Stroke.Kind := TBrushKind.None;
  Fill.Kind := TBrushKind.Solid;
  HitTest := True;
  Cursor := crHandPoint;
  OnMouseEnter := Hover;
  OnMouseLeave := Hover;

  Box := TLayout.Create(AOwner);
  Box.Parent := Self;
  Box.HitTest := False;
  if ASwitch then
  begin
    // Chave à direita: trilho 36x20 com o botão redondo.
    Box.Align := TAlignLayout.Right;
    Box.Width := 52;
    FTrack := TRectangle.Create(AOwner);
    FTrack.Parent := Box;
    FTrack.HitTest := False;
    FTrack.Stroke.Kind := TBrushKind.None;
    FTrack.SetBounds(4, 15, 36, 20);
    FTrack.XRadius := 10;
    FTrack.YRadius := 10;
    FDot := TCircle.Create(AOwner);
    FDot.Parent := FTrack;
    FDot.HitTest := False;
    FDot.Stroke.Kind := TBrushKind.None;
  end
  else
  begin
    // Bolinha à esquerda.
    Box.Align := TAlignLayout.Left;
    Box.Width := 40;
    FMark := TCircle.Create(AOwner);
    FMark.Parent := Box;
    FMark.HitTest := False;
    FMark.SetBounds(12, 16, 18, 18);
    FMark.Stroke.Thickness := 2;
    FMark.Fill.Kind := TBrushKind.None;
    FDot := TCircle.Create(AOwner);
    FDot.Parent := FMark;
    FDot.HitTest := False;
    FDot.Stroke.Kind := TBrushKind.None;
    FDot.SetBounds(4, 4, 10, 10);
  end;

  Mid := TLayout.Create(AOwner);
  Mid.Parent := Self;
  Mid.Align := TAlignLayout.Client;
  Mid.HitTest := False;
  if ASwitch then
    Mid.Margins.Rect := TRectF.Create(12, 7, 4, 7)
  else
    Mid.Margins.Rect := TRectF.Create(0, 7, 4, 7);
  FTitle := NecoNewLabel(AOwner, Mid, ATitle, 13);
  FTitle.Align := TAlignLayout.Top;
  FTitle.Height := 19;
  FTitle.Position.Y := 0;
  FSub := NecoNewLabel(AOwner, Mid, ASub, 11);
  FSub.Align := TAlignLayout.Top;
  FSub.Height := 16;
  FSub.Position.Y := 100;
  FSub.Visible := ASub <> '';
  if ASub = '' then
    Mid.Margins.Top := 15;
  Restyle;
end;

procedure TNecoOptionRow.SetChecked(AValue: Boolean);
begin
  FChecked := AValue;
  Restyle;
end;

procedure TNecoOptionRow.Hover(Sender: TObject);
begin
  Restyle;
end;

procedure TNecoOptionRow.Restyle;
begin
  if IsMouseOver then
    Fill.Color := Palette.Hover
  else
    Fill.Color := TAlphaColors.Null;
  FTitle.TextSettings.FontColor := Palette.Text;
  FSub.TextSettings.FontColor := Palette.TextMuted;
  if FSwitch then
  begin
    if FChecked then
    begin
      FTrack.Fill.Color := Palette.Accent;
      FDot.SetBounds(18, 2, 16, 16);
      FDot.Fill.Color := TAlphaColors.White;
    end
    else
    begin
      FTrack.Fill.Color := Palette.FieldBorder;
      FDot.SetBounds(2, 2, 16, 16);
      FDot.Fill.Color := Palette.TextMuted;
    end;
  end
  else
  begin
    if FChecked then
      FMark.Stroke.Color := Palette.Accent
    else
      FMark.Stroke.Color := Palette.TextMuted;
    FDot.Fill.Color := Palette.Accent;
    FDot.Visible := FChecked;
  end;
end;

{ TNecoSettingsPanel }

constructor TNecoSettingsPanel.CreateFor(AOwner: TComponent; ASettings: TNecoSettings;
  ABlockedHosts: Integer);
var
  E: TNecoSearchEngine;
  T: TNecoTheme;
  Stage: TLayout;
begin
  CreatePanel(AOwner, 'Configurações', '', '');
  FSettings := ASettings;
  FBlockedHosts := ABlockedHosts;

  Section('Busca na barra de endereço');
  // Google primeiro: é o padrão.
  FSearch[seGoogle] := Option(False, CEngineTitle[seGoogle], CEngineSub[seGoogle]);
  for E := Low(TNecoSearchEngine) to High(TNecoSearchEngine) do
    if E <> seGoogle then
      FSearch[E] := Option(False, CEngineTitle[E], CEngineSub[E]);

  Section('Aparência');
  for T := Low(TNecoTheme) to High(TNecoTheme) do
    FTheme[T] := Option(False, CThemeTitle[T], '');

  Section('Bloqueador');
  FBlocker := Option(True, 'Bloquear anúncios e rastreadores',
    FormatFloat('#,##0', FBlockedHosts) + ' domínios na lista');

  Section('Formulários e senhas');
  FForms := Option(True, 'Lembrar o que eu digito em formulários',
    'nome, e-mail, endereço: sugere de novo na próxima vez');
  FPasswords := Option(True, 'Oferecer para salvar senhas',
    'guardadas cifradas no seu usuário do Windows');

  Section('Neco-Arc');
  FNeco := Option(True, 'Mostrar a Neco', 'na faixa de abas, nos painéis e na página de erro');
  Stage := TLayout.Create(Self);
  Stage.Height := 120;
  Stage.HitTest := False;
  FNecoSprite := TNecoSprite.Create(Self);
  FNecoSprite.Parent := Stage;
  FNecoSprite.Align := TAlignLayout.Client;
  FNecoSprite.Margins.Rect := TRectF.Create(0, 8, 0, 8);
  FNecoSprite.Scale := 2;
  FNecoSprite.AnimName := 'dance';
  AppendRow(Stage);

  Refresh;
  Restyle;
end;

procedure TNecoSettingsPanel.Section(const AText: string);
var
  L: TLabel;
begin
  L := NecoNewLabel(Self, nil, AText, 11.5);
  L.Height := 30;
  L.Margins.Rect := TRectF.Create(10, 6, 4, 0);
  L.TextSettings.VertAlign := TTextAlign.Trailing;
  L.TextSettings.Font.Style := [TFontStyle.fsBold];
  FSections := FSections + [L];
  AppendRow(L);
end;

function TNecoSettingsPanel.Option(ASwitch: Boolean; const ATitle, ASub: string): TNecoOptionRow;
begin
  Result := TNecoOptionRow.CreateRow(Self, ASwitch, ATitle, ASub);
  Result.OnClick := RowClick;
  AppendRow(Result);
end;

procedure TNecoSettingsPanel.RowClick(Sender: TObject);
var
  E: TNecoSearchEngine;
  T: TNecoTheme;
begin
  for E := Low(TNecoSearchEngine) to High(TNecoSearchEngine) do
    if (Sender = FSearch[E]) and (FSettings.SearchEngine <> E) then
    begin
      FSettings.SearchEngine := E;
      DoChanged(scSearch);
    end;
  for T := Low(TNecoTheme) to High(TNecoTheme) do
    if (Sender = FTheme[T]) and (FSettings.Theme <> T) then
    begin
      FSettings.Theme := T;
      DoChanged(scTheme);
    end;
  if Sender = FBlocker then
  begin
    FSettings.BlockerEnabled := not FSettings.BlockerEnabled;
    DoChanged(scBlocker);
  end;
  if Sender = FForms then
  begin
    FSettings.FormAutofill := not FSettings.FormAutofill;
    DoChanged(scAutofill);
  end;
  if Sender = FPasswords then
  begin
    FSettings.SavePasswords := not FSettings.SavePasswords;
    DoChanged(scAutofill);
  end;
  if Sender = FNeco then
  begin
    FSettings.NecoShown := not FSettings.NecoShown;
    DoChanged(scNeco);
  end;
  Refresh;
end;

procedure TNecoSettingsPanel.DoChanged(AChange: TNecoSettingsChange);
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self, AChange);
end;

procedure TNecoSettingsPanel.Refresh;
var
  E: TNecoSearchEngine;
  T: TNecoTheme;
begin
  if FSettings = nil then
    Exit;
  for E := Low(TNecoSearchEngine) to High(TNecoSearchEngine) do
    FSearch[E].Checked := FSettings.SearchEngine = E;
  for T := Low(TNecoTheme) to High(TNecoTheme) do
    FTheme[T].Checked := FSettings.Theme = T;
  FBlocker.Checked := FSettings.BlockerEnabled;
  FForms.Checked := FSettings.FormAutofill;
  FPasswords.Checked := FSettings.SavePasswords;
  FNeco.Checked := FSettings.NecoShown;
  FNecoSprite.Repaint;
end;

procedure TNecoSettingsPanel.Restyle;
var
  I: Integer;
begin
  inherited;
  for I := 0 to RowCount - 1 do
    if Row(I) is TNecoOptionRow then
      TNecoOptionRow(Row(I)).Restyle;
  for I := 0 to High(FSections) do
    FSections[I].TextSettings.FontColor := Palette.TextMuted;
end;

end.
