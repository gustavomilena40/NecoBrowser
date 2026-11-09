unit Neco.UI.Frame;

{ Barra de título própria (Windows).

  O Windows deixa de desenhar a barra branca: no WM_NCCALCSIZE a área cliente sobe
  até o topo da janela. As bordas laterais e de baixo continuam nativas, então
  redimensionar, a sombra, o snap ao arrastar e os cantos arredondados do Windows 11
  continuam funcionando.

  Quem desenha a faixa do topo é o form (faixa de abas + botões). No WM_NCHITTEST o form
  diz o que há em cada ponto da faixa:
  - fhCaption: arrasta a janela (duplo clique maximiza, botão direito abre o menu da janela);
  - fhMaxButton: o Windows 11 mostra os layouts de snap ao parar o mouse em cima. Como
    esse ponto é "não-cliente", o FMX não recebe o mouse ali: o hover e o clique chegam
    pelos callbacks AMaxHover e AMaxClick;
  - fhClient: o FMX trata normalmente (abas, botões, a Neco).

  A janela também é subclassada pelo motor (Neco.Engine.WebView2) para outras mensagens;
  as duas subclasses convivem. }

interface

uses
  System.SysUtils, System.Types, FMX.Forms;

type
  TNecoFrameHit = (fhClient, fhCaption, fhMaxButton);
  /// APoint em coordenadas lógicas do FMX, relativas à área cliente.
  TNecoFrameHitTest = reference to function(const APoint: TPointF): TNecoFrameHit;

/// Liga a barra própria. ATitleHeight em unidades lógicas do FMX.
procedure NecoFrameAttach(AForm: TCommonCustomForm; ATitleHeight: Single;
  const AHitTest: TNecoFrameHitTest; const AMaxHover: TProc<Boolean>; const AMaxClick: TProc);
/// Solta os callbacks (o form vai ser destruído). A janela mantém a moldura sem barra.
procedure NecoFrameDetach;

procedure NecoFrameMinimize(AForm: TCommonCustomForm);
procedure NecoFrameToggleMaximize(AForm: TCommonCustomForm);
function NecoFrameIsMaximized(AForm: TCommonCustomForm): Boolean;
function NecoFrameIsMinimized(AForm: TCommonCustomForm): Boolean;
/// A janela do form é a janela em primeiro plano.
function NecoFrameIsForeground(AForm: TCommonCustomForm): Boolean;
/// Milissegundos desde a última tecla ou movimento de mouse no sistema todo.
function NecoSystemIdleMs: Cardinal;
/// Abre o arquivo com o programa padrão do sistema.
procedure NecoShellOpen(const APath: string);
/// Abre a pasta do arquivo, com ele selecionado.
procedure NecoShowInFolder(const APath: string);

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows, Winapi.Messages, Winapi.CommCtrl, Winapi.ShellAPI, FMX.Platform.Win,
  Neco.Core.Trace;

var
  GWnd: HWND;
  GForm: TCommonCustomForm;
  GTitleHeight: Single;
  GHitTest: TNecoFrameHitTest;
  GMaxHover: TProc<Boolean>;
  GMaxClick: TProc;
  GMaxHot: Boolean;
  GTracking: Boolean;

/// Espessura da borda de redimensionar, em pixels físicos, na DPI da janela.
function FrameThickness(AWnd: HWND): Integer;
var
  Dpi: UINT;
begin
  Dpi := GetDpiForWindow(AWnd);
  if Dpi = 0 then
    Dpi := 96;
  Result := GetSystemMetricsForDpi(SM_CYFRAME, Dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, Dpi);
end;

procedure SetMaxHot(AValue: Boolean);
begin
  if GMaxHot = AValue then
    Exit;
  GMaxHot := AValue;
  if Assigned(GMaxHover) then
    GMaxHover(AValue);
end;

function TitleHit(AWnd: HWND; ALParam: LPARAM): LRESULT;
var
  Pt: TPoint;
  CR: TRect;
  B: Integer;
  S: Single;
begin
  Result := HTCLIENT;
  Pt := TPoint.Create(SmallInt(LoWord(ALParam)), SmallInt(HiWord(ALParam)));
  Winapi.Windows.ScreenToClient(AWnd, Pt);
  GetClientRect(AWnd, CR);
  // Topo: a borda de redimensionar que a barra do Windows tinha.
  if not IsZoomed(AWnd) then
  begin
    B := FrameThickness(AWnd);
    if Pt.Y < B then
    begin
      if Pt.X < 2 * B then
        Exit(HTTOPLEFT);
      if Pt.X >= CR.Right - 2 * B then
        Exit(HTTOPRIGHT);
      Exit(HTTOP);
    end;
  end;
  if (GForm = nil) or not Assigned(GHitTest) then
    Exit;
  S := GForm.Handle.Scale;
  if S <= 0 then
    S := 1;
  if Pt.Y >= GTitleHeight * S then
    Exit;
  case GHitTest(TPointF.Create(Pt.X / S, Pt.Y / S)) of
    fhCaption:
      Result := HTCAPTION;
    fhMaxButton:
      Result := HTMAXBUTTON;
  end;
end;

function FrameProc(hWnd: HWND; uMsg: UINT; wParam: WPARAM; lParam: LPARAM;
  uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): LRESULT; stdcall;
var
  P: PNCCalcSizeParams;
  Top: Integer;
  Tme: TTrackMouseEvent;
begin
  case uMsg of
    WM_NCCALCSIZE:
      if wParam <> 0 then
      begin
        // O padrão encolhe os quatro lados; devolvemos o topo (sem barra de título).
        // Maximizada, a janela passa da tela pela espessura da borda: desconta no topo.
        P := PNCCalcSizeParams(lParam);
        Top := P.rgrc[0].Top;
        Result := DefSubclassProc(hWnd, uMsg, wParam, lParam);
        P.rgrc[0].Top := Top;
        if IsZoomed(hWnd) then
          Inc(P.rgrc[0].Top, FrameThickness(hWnd));
        Exit;
      end;
    WM_NCHITTEST:
      begin
        Result := DefSubclassProc(hWnd, uMsg, wParam, lParam);
        if Result = HTCLIENT then
          Result := TitleHit(hWnd, lParam);
        if Result <> HTMAXBUTTON then
          SetMaxHot(False);
        Exit;
      end;
    WM_NCMOUSEMOVE:
      if wParam = HTMAXBUTTON then
      begin
        SetMaxHot(True);
        if not GTracking then
        begin
          Tme.cbSize := SizeOf(Tme);
          Tme.dwFlags := TME_LEAVE or TME_NONCLIENT;
          Tme.hwndTrack := hWnd;
          Tme.dwHoverTime := 0;
          GTracking := TrackMouseEvent(Tme);
        end;
        Exit(0);
      end
      else
        SetMaxHot(False);
    WM_NCMOUSELEAVE:
      begin
        GTracking := False;
        SetMaxHot(False);
      end;
    WM_NCLBUTTONDOWN, WM_NCLBUTTONDBLCLK:
      // Engole: o padrão desenharia o botão clássico por cima da nossa faixa.
      if wParam = HTMAXBUTTON then
        Exit(0);
    WM_NCLBUTTONUP:
      if wParam = HTMAXBUTTON then
      begin
        SetMaxHot(False);
        if Assigned(GMaxClick) then
          GMaxClick();
        Exit(0);
      end;
    WM_NCDESTROY:
      begin
        RemoveWindowSubclass(hWnd, @FrameProc, uIdSubclass);
        if GWnd = hWnd then
          GWnd := 0;
      end;
  end;
  Result := DefSubclassProc(hWnd, uMsg, wParam, lParam);
end;

/// O SetWindowSubclass do Winapi.CommCtrl só funciona depois do InitComCtl, que só
/// pega a comctl32 se ela já estiver carregada. Num app FMX ninguém faz isso, e a função
/// devolve False em silêncio (verificado em 2026-11-09). Isto vale também para a
/// subclasse do motor (Neco.Engine.WebView2.HookParent), que roda depois desta.
procedure EnsureComCtl;
var
  Icc: TInitCommonControlsEx;
begin
  InitCommonControls;               // import estático: garante a DLL carregada
  Icc.dwSize := SizeOf(Icc);
  Icc.dwICC := ICC_STANDARD_CLASSES;
  InitCommonControlsEx(Icc);        // chama o InitComCtl do Delphi
end;

procedure NecoFrameAttach(AForm: TCommonCustomForm; ATitleHeight: Single;
  const AHitTest: TNecoFrameHitTest; const AMaxHover: TProc<Boolean>; const AMaxClick: TProc);
var
  W: HWND;
begin
  EnsureComCtl;
  W := FormToHWND(AForm);
  NecoTrace(Format('barra propria: hwnd=%x anterior=%x', [NativeUInt(W), NativeUInt(GWnd)]));
  if W = 0 then
    Exit;
  GForm := AForm;
  GTitleHeight := ATitleHeight;
  GHitTest := AHitTest;
  GMaxHover := AMaxHover;
  GMaxClick := AMaxClick;
  if GWnd <> W then
  begin
    if not SetWindowSubclass(W, @FrameProc, 1, 0) then
    begin
      NecoTrace(Format('barra propria: SetWindowSubclass falhou (erro %d)', [GetLastError]));
      Exit;
    end;
    GWnd := W;
  end;
  // Recalcula a moldura já com a regra nova (a barra branca some aqui).
  SetWindowPos(W, 0, 0, 0, 0, 0, SWP_FRAMECHANGED or SWP_NOMOVE or SWP_NOSIZE or
    SWP_NOZORDER or SWP_NOACTIVATE or SWP_NOOWNERZORDER);
end;

procedure NecoFrameDetach;
begin
  GHitTest := nil;
  GMaxHover := nil;
  GMaxClick := nil;
  GForm := nil;
end;

procedure NecoFrameMinimize(AForm: TCommonCustomForm);
begin
  ShowWindow(FormToHWND(AForm), SW_MINIMIZE);
end;

procedure NecoFrameToggleMaximize(AForm: TCommonCustomForm);
var
  W: HWND;
begin
  W := FormToHWND(AForm);
  if IsZoomed(W) then
    ShowWindow(W, SW_RESTORE)
  else
    ShowWindow(W, SW_MAXIMIZE);
end;

function NecoFrameIsMaximized(AForm: TCommonCustomForm): Boolean;
begin
  Result := IsZoomed(FormToHWND(AForm));
end;

function NecoFrameIsMinimized(AForm: TCommonCustomForm): Boolean;
begin
  Result := IsIconic(FormToHWND(AForm));
end;

function NecoFrameIsForeground(AForm: TCommonCustomForm): Boolean;
begin
  Result := GetForegroundWindow = FormToHWND(AForm);
end;

function NecoSystemIdleMs: Cardinal;
var
  LI: TLastInputInfo;
begin
  LI.cbSize := SizeOf(LI);
  if GetLastInputInfo(LI) then
    Result := GetTickCount - LI.dwTime
  else
    Result := 0;
end;

procedure NecoShellOpen(const APath: string);
begin
  if APath <> '' then
    ShellExecute(0, 'open', PChar(APath), nil, nil, SW_SHOWNORMAL);
end;

procedure NecoShowInFolder(const APath: string);
begin
  if APath <> '' then
    ShellExecute(0, 'open', 'explorer.exe', PChar('/select,"' + APath + '"'), nil, SW_SHOWNORMAL);
end;

{$ELSE}

procedure NecoFrameAttach(AForm: TCommonCustomForm; ATitleHeight: Single;
  const AHitTest: TNecoFrameHitTest; const AMaxHover: TProc<Boolean>; const AMaxClick: TProc);
begin
end;

procedure NecoFrameDetach;
begin
end;

procedure NecoFrameMinimize(AForm: TCommonCustomForm);
begin
end;

procedure NecoFrameToggleMaximize(AForm: TCommonCustomForm);
begin
end;

function NecoFrameIsMaximized(AForm: TCommonCustomForm): Boolean;
begin
  Result := False;
end;

function NecoFrameIsMinimized(AForm: TCommonCustomForm): Boolean;
begin
  Result := False;
end;

function NecoFrameIsForeground(AForm: TCommonCustomForm): Boolean;
begin
  Result := True;
end;

function NecoSystemIdleMs: Cardinal;
begin
  Result := 0;
end;

procedure NecoShellOpen(const APath: string);
begin
end;

procedure NecoShowInFolder(const APath: string);
begin
end;

{$ENDIF}

end.
