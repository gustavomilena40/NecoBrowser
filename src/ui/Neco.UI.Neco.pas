unit Neco.UI.Neco;

{ A Neco-Arc na faixa de abas.

  Os sprites vêm de NecoSprites.res, gerado por tools\neco_sprites.py a partir do zip do
  usuário: um índice em texto (NECO_INDEX) e uma folha PNG por animação. Para trocar uma
  animação, mexa na tabela do script; aqui só os nomes (idle, sink, slide...) importam.

  TNecoStage é um controle transparente por cima da faixa de abas (HitTest = False: os
  cliques passam para as abas). Ela tem um "assento" (SeatX), onde a Neco fica parada,
  e de vez em quando faz uma aparição:
  - no assento: cambalhota, dancinha, pose;
  - atravessando a faixa: afunda no assento, atravessa da esquerda para a direita
    (deslizando, num borrão ou, raramente, como o gato-sombra) e brota de volta.
  Estado de fundo: parada (idle), carregando página (hop), ou deitada quando o
  computador está sem uso há um tempo (lazy).

  Custos: um TTimer de 40 ms; só redesenha quando o quadro ou a posição mudam. Com a
  janela minimizada o timer cai para 1 s e não desenha nada. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  System.Generics.Collections, System.Diagnostics,
  FMX.Types, FMX.Controls, FMX.Graphics;

type
  TNecoAnim = class
  public
    Name: string;
    Sheet: TBitmap;
    Frames, W, H, AnchorX, FloorY, FrameMs: Integer;
    Loop: Boolean;
    destructor Destroy; override;
    function SourceRect(AFrame: Integer): TRectF;
  end;

  TNecoStep = record
    Anim: string;
    Cross: Boolean;   // atravessa a faixa em vez de ficar no assento
    Speed: Single;    // px lógicos por segundo, ao atravessar
  end;

  TNecoStage = class(TControl)
  private
    FTimer: TTimer;
    FClock: TStopwatch;
    FLastMs: Int64;
    FAnim: TNecoAnim;
    FFrame: Integer;
    FFrameMs: Double;
    FX: Single;
    FStep: TNecoStep;
    FInStep: Boolean;
    FQueue: TQueue<TNecoStep>;
    FSeatX: Single;
    FLoading: Boolean;
    FLazy: Boolean;
    FNextEventMs: Int64;
    FLastCheerMs: Int64;
    FLastIdleCheckMs: Int64;
    FActive: Boolean;
    FDemo: Boolean;
    FCanAnimate: TFunc<Boolean>;
    FCanSchedule: TFunc<Boolean>;
    procedure Tick(Sender: TObject);
    procedure Play(const AName: string);
    procedure NextStep;
    function BaseAnim: string;
    procedure Enqueue(const AAnim: string; ACross: Boolean = False; ASpeed: Single = 0);
    procedure PlanEvent;
    function DrawScale(AAnim: TNecoAnim): Single;
    function ActorRect: TRectF;
    procedure SetSeatX(AValue: Single);
    procedure SetLoading(AValue: Boolean);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// Para o timer (o form está fechando).
    procedure Stop;
    /// O ponto está sobre a Neco sentada? (coordenadas do próprio controle)
    function HitActor(const APoint: TPointF): Boolean;
    /// Clique na Neco: ela ri.
    procedure Poke;
    /// Algo bom aconteceu (página com anúncios bloqueados, download concluído).
    /// Sem AForce, no máximo uma comemoração por minuto.
    procedure Celebrate(AForce: Boolean = False);
    /// Uma reação avulsa no assento (ex.: 'turn' ao favoritar), se ela estiver parada.
    procedure Perform(const AName: string);
    /// Liga ou desliga a Neco da faixa (configuração "Mostrar a Neco").
    procedure SetShown(AValue: Boolean);
    /// Centro do assento, em coordenadas do controle.
    property SeatX: Single read FSeatX write SetSeatX;
    property Loading: Boolean read FLoading write SetLoading;
    /// Falso = não desenha (janela minimizada).
    property CanAnimate: TFunc<Boolean> read FCanAnimate write FCanAnimate;
    /// Falso = não começa aparições (janela em segundo plano).
    property CanSchedule: TFunc<Boolean> read FCanSchedule write FCanSchedule;
    /// Os sprites carregaram? Sem eles a Neco simplesmente não aparece.
    property Active: Boolean read FActive;
  end;

  /// Uma Neco avulsa tocando uma animação em loop, num lugar fixo (painéis vazios,
  /// página de erro, configurações). Desenhada em escala inteira, com os pés na base do
  /// controle e centralizada na horizontal. Animação sem loop recomeça depois de uma pausa.
  TNecoSprite = class(TControl)
  private
    FTimer: TTimer;
    FClock: TStopwatch;
    FLastMs: Int64;
    FAnim: TNecoAnim;
    FFrame: Integer;
    FFrameMs: Double;
    FPauseMs: Double;
    FScale: Integer;
    procedure Tick(Sender: TObject);
    procedure SetAnimName(const AValue: string);
    function GetAnimName: string;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// Tamanho do desenho (largura x altura da folha vezes a escala), para o layout.
    function NaturalSize: TSizeF;
    property AnimName: string read GetAnimName write SetAnimName;
    property Scale: Integer read FScale write FScale;
  end;

/// Configuração "Mostrar a Neco": desligada, nenhuma Neco desenha nem anima.
procedure NecoSetShown(AValue: Boolean);
function NecoShown: Boolean;

implementation

{$R NecoSprites.res}

uses
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF} System.Math, Neco.UI.Frame;

const
  CTickMs = 40;
  CIdleTickMs = 1000;
  CFirstEventMinMs = 30000;    // primeira aparição: 30 a 60 s depois de abrir
  CFirstEventRangeMs = 30000;
  CEventMinMs = 60000;         // depois: a cada 1 a 3 min
  CEventRangeMs = 120000;
  CLazyAfterMs = 120000;       // computador sem uso há 2 min: a Neco deita
  CCheerGapMs = 60000;         // no máximo uma comemoração por minuto

var
  GAnims: TObjectDictionary<string, TNecoAnim>;
  GLoaded: Boolean;
  GShown: Boolean = True;

procedure NecoSetShown(AValue: Boolean);
begin
  GShown := AValue;
end;

function NecoShown: Boolean;
begin
  Result := GShown;
end;

{ Carga dos sprites }

function ResourceStream(const AName: string): TResourceStream;
begin
  Result := nil;
  if FindResource(HInstance, PChar(AName), RT_RCDATA) <> 0 then
    Result := TResourceStream.Create(HInstance, AName, RT_RCDATA);
end;

procedure LoadSprites;
var
  RS: TResourceStream;
  Lines: TStringList;
  Line: string;
  F: TArray<string>;
  A: TNecoAnim;
begin
  if GLoaded then
    Exit;
  GLoaded := True;
  GAnims := TObjectDictionary<string, TNecoAnim>.Create([doOwnsValues]);
  Lines := TStringList.Create;
  try
    RS := ResourceStream('NECO_INDEX');
    if RS = nil then
      Exit;
    try
      Lines.LoadFromStream(RS, TEncoding.UTF8);
    finally
      RS.Free;
    end;
    for Line in Lines do
    begin
      if (Line = '') or Line.StartsWith('#') then
        Continue;
      F := Line.Split(['|']);
      if Length(F) < 9 then
        Continue;
      RS := ResourceStream(F[1]);
      if RS = nil then
        Continue;
      A := TNecoAnim.Create;
      try
        A.Name := F[0];
        A.Frames := StrToInt(F[2]);
        A.W := StrToInt(F[3]);
        A.H := StrToInt(F[4]);
        A.AnchorX := StrToInt(F[5]);
        A.FloorY := StrToInt(F[6]);
        A.FrameMs := Max(20, StrToInt(F[7]));
        A.Loop := F[8] = '1';
        A.Sheet := FMX.Graphics.TBitmap.Create; // Winapi.Windows também tem um TBitmap
        A.Sheet.LoadFromStream(RS);
      except
        A.Free;
        A := nil;
      end;
      RS.Free;
      if A <> nil then
        GAnims.AddOrSetValue(A.Name, A);
    end;
  finally
    Lines.Free;
  end;
end;

function Anim(const AName: string): TNecoAnim;
begin
  if (GAnims = nil) or not GAnims.TryGetValue(AName, Result) then
    Result := nil;
end;

{ TNecoAnim }

destructor TNecoAnim.Destroy;
begin
  Sheet.Free;
  inherited;
end;

function TNecoAnim.SourceRect(AFrame: Integer): TRectF;
begin
  // Quadros lado a lado com 2 px de vão (ver tools\neco_sprites.py).
  Result := TRectF.Create(AFrame * (W + 2), 0, AFrame * (W + 2) + W, H);
end;

{ TNecoStage }

constructor TNecoStage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := False;
  FQueue := TQueue<TNecoStep>.Create;
  LoadSprites;
  FActive := (Anim('idle') <> nil);
  FClock := TStopwatch.StartNew;
  // NECO_DEMO=1: uma aparição a cada 4 a 8 s, mesmo com a janela atrás (para testar).
  FDemo := System.SysUtils.GetEnvironmentVariable('NECO_DEMO') = '1';
  if FDemo then
    FNextEventMs := 3000
  else
    FNextEventMs := CFirstEventMinMs + Random(CFirstEventRangeMs);
  FLastCheerMs := -CCheerGapMs;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := CTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := FActive;
  if FActive then
    Play(BaseAnim);
end;

destructor TNecoStage.Destroy;
begin
  Stop;
  FQueue.Free;
  inherited;
end;

procedure TNecoStage.Stop;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
end;

function TNecoStage.BaseAnim: string;
begin
  if FLoading then
    Result := 'hop'
  else if FLazy then
    Result := 'lazy'
  else
    Result := 'idle';
end;

procedure TNecoStage.Play(const AName: string);
var
  A: TNecoAnim;
begin
  A := Anim(AName);
  if A = nil then
    A := Anim('idle');
  FAnim := A;
  FFrame := 0;
  FFrameMs := 0;
  Repaint;
end;

procedure TNecoStage.Enqueue(const AAnim: string; ACross: Boolean; ASpeed: Single);
var
  S: TNecoStep;
begin
  if Anim(AAnim) = nil then
    Exit;
  S.Anim := AAnim;
  S.Cross := ACross;
  S.Speed := ASpeed;
  FQueue.Enqueue(S);
end;

procedure TNecoStage.NextStep;
var
  A: TNecoAnim;
begin
  if FQueue.Count = 0 then
  begin
    FInStep := False;
    FX := FSeatX;
    Play(BaseAnim);
    Exit;
  end;
  FStep := FQueue.Dequeue;
  FInStep := True;
  A := Anim(FStep.Anim);
  if FStep.Cross and (A <> nil) then
    // Entra pela esquerda, com o corpo todo fora da faixa.
    FX := -(A.W - A.AnchorX) * DrawScale(A)
  else
    FX := FSeatX;
  Play(FStep.Anim);
end;

procedure TNecoStage.PlanEvent;
var
  R: Integer;
begin
  R := Random(100);
  if R < 5 then
  begin
    // Raro: o gato-sombra atravessa a faixa.
    Enqueue('sink');
    Enqueue('shadow', True, 260);
    Enqueue('emerge');
  end
  else if R < 20 then
  begin
    Enqueue('sink');
    Enqueue('slide', True, 170);
    Enqueue('emerge');
  end
  else if R < 32 then
  begin
    Enqueue('sink');
    Enqueue('dash', True, 900);
    Enqueue('emerge');
  end
  else if R < 55 then
    Enqueue('flip')
  else if R < 80 then
    Enqueue('dance')
  else
    Enqueue('turn');
end;

procedure TNecoStage.Poke;
begin
  if FActive and GShown and not FInStep and (FQueue.Count = 0) and not FLoading then
  begin
    FLazy := False;
    Enqueue('taunt');
    NextStep;
  end;
end;

procedure TNecoStage.Celebrate(AForce: Boolean);
var
  T: Int64;
begin
  T := FClock.ElapsedMilliseconds;
  if not FActive or not GShown or FInStep or (FQueue.Count > 0) or
    (not AForce and (T - FLastCheerMs < CCheerGapMs)) then
    Exit;
  FLastCheerMs := T;
  FLazy := False;
  Enqueue('cheer');
  NextStep;
end;

procedure TNecoStage.Perform(const AName: string);
begin
  if not FActive or not GShown or FInStep or (FQueue.Count > 0) then
    Exit;
  FLazy := False;
  Enqueue(AName);
  NextStep;
end;

procedure TNecoStage.SetShown(AValue: Boolean);
begin
  NecoSetShown(AValue);
  if not AValue then
  begin
    // Some na hora, mesmo no meio de uma aparição.
    FQueue.Clear;
    FInStep := False;
    FX := FSeatX;
    if FActive then
      Play(BaseAnim);
  end;
  Repaint;
end;

procedure TNecoStage.SetSeatX(AValue: Single);
begin
  if SameValue(FSeatX, AValue, 0.01) then
    Exit;
  FSeatX := AValue;
  if not (FInStep and FStep.Cross) then
  begin
    FX := FSeatX;
    Repaint;
  end;
end;

procedure TNecoStage.SetLoading(AValue: Boolean);
begin
  if FLoading = AValue then
    Exit;
  FLoading := AValue;
  if FLoading then
    FLazy := False;
  if FActive and not FInStep then
    Play(BaseAnim);
end;

function TNecoStage.DrawScale(AAnim: TNecoAnim): Single;
begin
  // Tamanho natural; só encolhe a animação que não caberia de pé na faixa.
  Result := 1;
  if (AAnim <> nil) and (AAnim.FloorY > Height) and (Height > 0) then
    Result := Height / AAnim.FloorY;
end;

function TNecoStage.ActorRect: TRectF;
var
  Sc, SS: Single;
begin
  if FAnim = nil then
    Exit(TRectF.Empty);
  Sc := DrawScale(FAnim);
  Result := TRectF.Create(FX - FAnim.AnchorX * Sc, Height - FAnim.FloorY * Sc,
    FX + (FAnim.W - FAnim.AnchorX) * Sc, Height + (FAnim.H - FAnim.FloorY) * Sc);
  // Alinha ao pixel físico: sem isso o pixel art fica tremido.
  if Scene <> nil then
    SS := Scene.GetSceneScale
  else
    SS := 1;
  if SS <= 0 then
    SS := 1;
  Result.Offset(Round(Result.Left * SS) / SS - Result.Left, Round(Result.Top * SS) / SS - Result.Top);
end;

function TNecoStage.HitActor(const APoint: TPointF): Boolean;
var
  R: TRectF;
begin
  Result := False;
  if not FActive or not GShown or (FAnim = nil) or (FInStep and FStep.Cross) then
    Exit;
  R := ActorRect;
  R.Inflate(-4, -2);
  Result := R.Contains(APoint);
end;

procedure TNecoStage.Tick(Sender: TObject);
var
  T: Int64;
  Dt: Double;
  Changed: Boolean;
  Lazy: Boolean;
begin
  T := FClock.ElapsedMilliseconds;
  Dt := Min(T - FLastMs, 250);
  FLastMs := T;

  if not GShown or (Assigned(FCanAnimate) and not FCanAnimate()) then
  begin
    FTimer.Interval := CIdleTickMs;
    Exit;
  end;
  FTimer.Interval := CTickMs;

  // Computador sem uso: deita. Mexeu: levanta. (confere 1x por segundo)
  if T - FLastIdleCheckMs >= 1000 then
  begin
    FLastIdleCheckMs := T;
    Lazy := (NecoSystemIdleMs >= CLazyAfterMs) and not FLoading;
    if Lazy <> FLazy then
    begin
      FLazy := Lazy;
      if not FInStep then
        Play(BaseAnim);
      // Ao voltar, a próxima aparição não acontece na cara do usuário.
      if not Lazy then
        FNextEventMs := Max(FNextEventMs, T + 10000);
    end;
  end;

  // Hora de uma aparição.
  if not FInStep and not FLoading and not FLazy and (T >= FNextEventMs) then
  begin
    if FDemo then
      FNextEventMs := T + 4000 + Random(4000)
    else
      FNextEventMs := T + CEventMinMs + Random(CEventRangeMs);
    if FDemo or not Assigned(FCanSchedule) or FCanSchedule() then
    begin
      PlanEvent;
      NextStep;
      Exit;
    end;
  end;

  if FAnim = nil then
    Exit;
  Changed := False;

  if FInStep and FStep.Cross then
  begin
    FX := FX + FStep.Speed * Dt / 1000;
    Changed := True;
    if FX - FAnim.AnchorX * DrawScale(FAnim) > Width then
    begin
      NextStep;
      Exit;
    end;
  end;

  FFrameMs := FFrameMs + Dt;
  while FFrameMs >= FAnim.FrameMs do
  begin
    FFrameMs := FFrameMs - FAnim.FrameMs;
    Inc(FFrame);
    Changed := True;
    if FFrame >= FAnim.Frames then
    begin
      if FAnim.Loop then
        FFrame := 0
      else if FInStep then
      begin
        NextStep;
        Exit;
      end
      else
        FFrame := FAnim.Frames - 1;
    end;
  end;

  if Changed then
    Repaint;
end;

procedure TNecoStage.Paint;
var
  R: TRectF;
  SS, Sc: Single;
  Exact: Boolean;
begin
  if not FActive or not GShown or (FAnim = nil) or (FAnim.Sheet = nil) then
    Exit;
  if Assigned(FCanAnimate) and not FCanAnimate() then
    Exit;
  R := ActorRect;
  if Scene <> nil then
    SS := Scene.GetSceneScale
  else
    SS := 1;
  // Escala inteira em pixel físico: vizinho mais próximo (nítido). Senão, bilinear.
  Sc := DrawScale(FAnim) * SS;
  Exact := Abs(Sc - Round(Sc)) < 0.01;
  Canvas.DrawBitmap(FAnim.Sheet, FAnim.SourceRect(Min(FFrame, FAnim.Frames - 1)), R, AbsoluteOpacity, Exact);
end;

{ TNecoSprite }

const
  CSpritePauseMs = 1800; // pausa antes de repetir uma animação sem loop

constructor TNecoSprite.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := False;
  FScale := 2;
  LoadSprites;
  FClock := TStopwatch.StartNew;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := CTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := False;
end;

function TNecoSprite.GetAnimName: string;
begin
  if FAnim <> nil then
    Result := FAnim.Name
  else
    Result := '';
end;

procedure TNecoSprite.SetAnimName(const AValue: string);
begin
  FAnim := Anim(AValue);
  FFrame := 0;
  FFrameMs := 0;
  FPauseMs := 0;
  FLastMs := FClock.ElapsedMilliseconds;
  FTimer.Enabled := FAnim <> nil;
  Repaint;
end;

function TNecoSprite.NaturalSize: TSizeF;
begin
  if FAnim = nil then
    Result := TSizeF.Create(0, 0)
  else
    Result := TSizeF.Create(FAnim.W * FScale, FAnim.H * FScale);
end;

procedure TNecoSprite.Tick(Sender: TObject);
var
  T: Int64;
  Dt: Double;
  Changed: Boolean;
begin
  T := FClock.ElapsedMilliseconds;
  Dt := Min(T - FLastMs, 250);
  FLastMs := T;
  // Escondida (painel fechado, Neco desligada): tique lento e sem desenho.
  if (FAnim = nil) or not GShown or not ParentedVisible then
  begin
    FTimer.Interval := CIdleTickMs;
    Exit;
  end;
  FTimer.Interval := CTickMs;
  if FPauseMs > 0 then
  begin
    FPauseMs := FPauseMs - Dt;
    if FPauseMs > 0 then
      Exit;
    FFrame := 0;
    FFrameMs := 0;
    Repaint;
    Exit;
  end;
  Changed := False;
  FFrameMs := FFrameMs + Dt;
  while FFrameMs >= FAnim.FrameMs do
  begin
    FFrameMs := FFrameMs - FAnim.FrameMs;
    Inc(FFrame);
    Changed := True;
    if FFrame >= FAnim.Frames then
    begin
      if FAnim.Loop then
        FFrame := 0
      else
      begin
        FFrame := FAnim.Frames - 1;
        FPauseMs := CSpritePauseMs;
        Break;
      end;
    end;
  end;
  if Changed then
    Repaint;
end;

procedure TNecoSprite.Paint;
var
  R: TRectF;
  SS, W, H: Single;
begin
  if (FAnim = nil) or (FAnim.Sheet = nil) or not GShown then
    Exit;
  W := FAnim.W * FScale;
  H := FAnim.H * FScale;
  R := TRectF.Create(0, 0, W, H);
  R.Offset((Width - W) / 2, Height - H);
  if Scene <> nil then
    SS := Scene.GetSceneScale
  else
    SS := 1;
  if SS <= 0 then
    SS := 1;
  R.Offset(Round(R.Left * SS) / SS - R.Left, Round(R.Top * SS) / SS - R.Top);
  Canvas.DrawBitmap(FAnim.Sheet, FAnim.SourceRect(Min(FFrame, FAnim.Frames - 1)), R, AbsoluteOpacity,
    Abs(FScale * SS - Round(FScale * SS)) < 0.01);
end;

initialization
  Randomize;

finalization
  FreeAndNil(GAnims);

end.
