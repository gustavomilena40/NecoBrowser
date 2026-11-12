unit Neco.UI.Shortcuts;

{ Painel "Atalhos do teclado": a lista de atalhos e gestos do mouse, por grupo, com as
  teclas em "pílulas". Só leitura. Abre pelo menu da seta ou pelo F1.

  A lista fica aqui (CItems), não é lida do código que trata as teclas
  (TFormMain.ShortcutAction): quem criar um atalho novo acrescenta a linha aqui. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Objects, FMX.Layouts, FMX.StdCtrls,
  Neco.UI.Theme, Neco.UI.SidePanel;

type
  TNecoShortcutsPanel = class(TNecoSidePanel)
  private
    procedure AddGroup(const ATitle: string);
    procedure AddItem(const AKeys, AText: string);
  public
    constructor Create(AOwner: TComponent); override;
    /// Refaz as linhas (as cores vêm do tema na montagem).
    procedure Rebuild;
    procedure Restyle; override;
  end;

implementation

type
  TShortcutItem = record
    Keys: string; // teclas separadas por '+'; alternativas separadas por ' ou '; '' = título de grupo
    Text: string;
  end;

const
  CItems: array[0..32] of TShortcutItem = (
    (Keys: ''; Text: 'Abas'),
    (Keys: 'Ctrl+T'; Text: 'Nova aba'),
    (Keys: 'Ctrl+W'; Text: 'Fechar a aba'),
    (Keys: 'Ctrl+Shift+T'; Text: 'Reabrir a última aba fechada'),
    (Keys: 'Ctrl+Tab'; Text: 'Próxima aba'),
    (Keys: 'Ctrl+Shift+Tab'; Text: 'Aba anterior'),
    (Keys: 'Ctrl+1 … 8'; Text: 'Ir para a aba nessa posição'),
    (Keys: 'Ctrl+9'; Text: 'Ir para a última aba'),

    (Keys: ''; Text: 'Janelas'),
    (Keys: 'Ctrl+N'; Text: 'Nova janela'),
    (Keys: 'Ctrl+Shift+Q'; Text: 'Sair (fecha todas as janelas)'),
    (Keys: 'F11'; Text: 'Tela cheia'),

    (Keys: ''; Text: 'Página'),
    (Keys: 'Ctrl+L'; Text: 'Ir para a barra de endereço'),
    (Keys: 'F5 ou Ctrl+R'; Text: 'Recarregar'),
    (Keys: 'Esc'; Text: 'Parar de carregar'),
    (Keys: 'Alt+←'; Text: 'Voltar'),
    (Keys: 'Alt+→'; Text: 'Avançar'),
    (Keys: 'Ctrl+D'; Text: 'Favoritar a página (de novo: tira)'),
    (Keys: 'Ctrl+O'; Text: 'Abrir um arquivo do computador'),

    (Keys: ''; Text: 'Painéis'),
    (Keys: 'Ctrl+H'; Text: 'Histórico'),
    (Keys: 'Ctrl+J'; Text: 'Downloads'),
    (Keys: 'Ctrl+Shift+O'; Text: 'Favoritos'),
    (Keys: 'Ctrl+Shift+B'; Text: 'Mostrar ou esconder a barra de favoritos'),
    (Keys: 'F1'; Text: 'Esta lista de atalhos'),

    (Keys: ''; Text: 'Mouse'),
    (Keys: 'Meio'; Text: 'Botão do meio numa aba: fecha a aba'),
    (Keys: 'Direito'; Text: 'Botão direito numa aba: mover para outra janela'),
    (Keys: 'Arrastar'; Text: 'Aba para fora da faixa: vira uma janela nova'),
    (Keys: 'Soltar'; Text: 'Aba na faixa de outra janela: junta as janelas'),
    (Keys: 'Esc'; Text: 'Durante o arrasto: devolve a aba'),
    (Keys: 'Duplo clique'; Text: 'Na faixa das abas: maximizar ou restaurar')
  );

{ TNecoShortcutsPanel }

constructor TNecoShortcutsPanel.Create(AOwner: TComponent);
begin
  CreatePanel(AOwner, 'Atalhos do teclado', '', 'idle');
  Restyle; // monta as linhas
end;

procedure TNecoShortcutsPanel.Rebuild;
var
  I: Integer;
begin
  List.BeginUpdate;
  try
    ClearRows;
    for I := Low(CItems) to High(CItems) do
      if CItems[I].Keys = '' then
        AddGroup(CItems[I].Text)
      else
        AddItem(CItems[I].Keys, CItems[I].Text);
  finally
    List.EndUpdate;
  end;
end;

procedure TNecoShortcutsPanel.AddGroup(const ATitle: string);
var
  L: TLabel;
begin
  L := NecoNewLabel(Self, nil, ATitle, 12, Palette.TextMuted);
  L.Height := 32;
  L.Margins.Rect := TRectF.Create(10, 6, 0, 0);
  L.TextSettings.Font.Style := [TFontStyle.fsBold];
  L.HitTest := False;
  AppendRow(L);
end;

procedure TNecoShortcutsPanel.AddItem(const AKeys, AText: string);
var
  R: TLayout;
  Keys: TLayout;
  T: TLabel;
  Alt, Parts: TArray<string>;
  I, J: Integer;
  X: Single;

  procedure AddText(const S: string; ASize: Single; AColor: TAlphaColor; AChip: Boolean);
  var
    Chip: TRectangle;
    L: TLabel;
    W: Single;
  begin
    // Largura aproximada pelo número de letras (a fonte é a do sistema, ~7 px por letra).
    W := Length(S) * 7 + 2;
    if AChip then
    begin
      W := W + 14;
      Chip := TRectangle.Create(Self);
      Chip.Parent := Keys;
      Chip.HitTest := False;
      Chip.SetBounds(X, 9, W, 22);
      Chip.XRadius := 5;
      Chip.YRadius := 5;
      Chip.Fill.Color := Palette.Field;
      Chip.Stroke.Color := Palette.FieldBorder;
      Chip.Stroke.Thickness := 1;
      L := NecoNewLabel(Self, Chip, S, ASize, AColor);
      L.Align := TAlignLayout.Client;
      L.TextSettings.HorzAlign := TTextAlign.Center;
    end
    else
    begin
      L := NecoNewLabel(Self, Keys, S, ASize, AColor);
      L.SetBounds(X, 9, W, 22);
      L.TextSettings.HorzAlign := TTextAlign.Center;
    end;
    L.HitTest := False;
    X := X + W + 4;
  end;

begin
  R := TLayout.Create(Self);
  R.Height := 40;
  R.Margins.Rect := TRectF.Create(10, 0, 8, 0);
  R.HitTest := False;

  // As teclas à direita: Ctrl, +, T ... ; alternativas separadas por "ou".
  Keys := TLayout.Create(Self);
  Keys.Parent := R;
  Keys.Align := TAlignLayout.Right;
  Keys.HitTest := False;
  X := 0;
  Alt := AKeys.Split([' ou ']);
  for I := 0 to High(Alt) do
  begin
    if I > 0 then
      AddText('ou', 11, Palette.TextMuted, False);
    Parts := Alt[I].Split(['+']);
    for J := 0 to High(Parts) do
    begin
      if J > 0 then
        AddText('+', 11, Palette.TextMuted, False);
      AddText(Parts[J], 11.5, Palette.Text, True);
    end;
  end;
  Keys.Width := X;

  T := NecoNewLabel(Self, R, AText, 13, Palette.Text);
  T.Align := TAlignLayout.Client;
  T.Margins.Right := 10;
  T.WordWrap := True;
  T.HitTest := False;
  AppendRow(R);
end;

procedure TNecoShortcutsPanel.Restyle;
begin
  inherited;
  // As cores das linhas vêm do tema na montagem.
  if List <> nil then
    Rebuild;
end;

end.
