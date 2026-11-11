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
/// Cada janela tem a sua barra: soltar uma não mexe nas outras.
procedure NecoFrameDetach(AForm: TCommonCustomForm);

procedure NecoFrameMinimize(AForm: TCommonCustomForm);
procedure NecoFrameToggleMaximize(AForm: TCommonCustomForm);
function NecoFrameIsMaximized(AForm: TCommonCustomForm): Boolean;
function NecoFrameIsMinimized(AForm: TCommonCustomForm): Boolean;
/// A janela do form é a janela em primeiro plano.
function NecoFrameIsForeground(AForm: TCommonCustomForm): Boolean;
/// Milissegundos desde a última tecla ou movimento de mouse no sistema todo.
function NecoSystemIdleMs: Cardinal;
/// Tela cheia: a janela cobre o monitor inteiro, sem bordas. Desligar volta ao que era.
procedure NecoFrameSetFullScreen(AForm: TCommonCustomForm; AOn: Boolean);
/// Posição da janela para gravar na sessão: o retângulo dela restaurada (não maximizada,
/// nem em tela cheia), em pixels do Windows, e se estava maximizada.
function NecoFrameGetPlacement(AForm: TCommonCustomForm; out ABounds: TRect; out AMaximized: Boolean): Boolean;
/// Põe a janela restaurada nesse retângulo (o de NecoFrameGetPlacement). Ignora retângulo
/// vazio ou fora de todos os monitores. Não mostra a janela se ela está oculta.
procedure NecoFrameSetPlacement(AForm: TCommonCustomForm; const ABounds: TRect);
/// Janela com botão próprio na barra de tarefas e no Alt+Tab (várias janelas no processo).
procedure NecoFrameMakeIndependent(AForm: TCommonCustomForm);
/// Com o botão do mouse ainda apertado: põe o ponto (AGrabX, AGrabY) da janela, em pixels
/// físicos a partir do canto dela, embaixo do cursor e passa o arrasto ao Windows ("mover
/// janela"). A janela segue o mouse até soltar; Esc cancela. AGrabX < 0: não move antes.
procedure NecoFrameStartSystemDrag(AForm: TCommonCustomForm; AGrabX, AGrabY: Integer);
/// Trava com nome (por processo, até ele fechar). True = esta instância é a primeira.
/// AWaitMs > 0: se outra tem a trava, espera ela fechar até esse tempo (reinício após atualizar).
function NecoAcquireInstanceLock(const AName: string; AWaitMs: Cardinal = 0): Boolean;
/// Abre o arquivo com o programa padrão do sistema.
procedure NecoShellOpen(const APath: string);
/// Inicia um programa com parâmetros (sem esperar).
procedure NecoLaunch(const AExe, AParams: string);
/// Abre a pasta do arquivo, com ele selecionado.
procedure NecoShowInFolder(const APath: string);

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows, Winapi.Messages, Winapi.CommCtrl, Winapi.ShellAPI, Winapi.MultiMon, FMX.Platform.Win,
  Neco.Core.Trace;

type
  /// Estado da barra de uma janela. Vai no dwRefData da subclasse: nasce no NecoFrameAttach
  /// e é liberado no WM_NCDESTROY da janela.
  PFrameState = ^TFrameState;
  TFrameState = record
    Form: TCommonCustomForm; // nil depois do NecoFrameDetach
    TitleHeight: Single;
    HitTest: TNecoFrameHitTest;
    MaxHover: TProc<Boolean>;
    MaxClick: TProc;
    MaxHot: Boolean;
    Tracking: Boolean;
    Full: Boolean;
    SavedStyle: NativeInt;
    SavedRect: TRect;
    SavedMax: Boolean;
  end;

const
  CFrameSubclassId = 1;

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

function FrameProc(hWnd: HWND; uMsg: UINT; wParam: WPARAM; lParam: LPARAM;
  uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): LRESULT; stdcall; forward;

/// O estado da janela, ou nil se ela não tem a barra própria.
function FindState(AWnd: HWND): PFrameState;
var
  Ref: DWORD_PTR;
begin
  Result := nil;
  if (AWnd <> 0) and GetWindowSubclass(AWnd, @FrameProc, CFrameSubclassId, Ref) then
    Result := PFrameState(Ref);
end;

procedure SetMaxHot(S: PFrameState; AValue: Boolean);
begin
  if S.MaxHot = AValue then
    Exit;
  S.MaxHot := AValue;
  if Assigned(S.MaxHover) then
    S.MaxHover(AValue);
end;

function TitleHit(S: PFrameState; AWnd: HWND; ALParam: LPARAM): LRESULT;
var
  Pt: TPoint;
  CR: TRect;
  B: Integer;
  Sc: Single;
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
  if (S.Form = nil) or not Assigned(S.HitTest) then
    Exit;
  Sc := S.Form.Handle.Scale;
  if Sc <= 0 then
    Sc := 1;
  if Pt.Y >= S.TitleHeight * Sc then
    Exit;
  case S.HitTest(TPointF.Create(Pt.X / Sc, Pt.Y / Sc)) of
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
  S: PFrameState;
begin
  S := PFrameState(dwRefData);
  case uMsg of
    WM_NCCALCSIZE:
      if (wParam <> 0) and S.Full then
        Exit(0) // tela cheia: a janela inteira é área cliente
      else if wParam <> 0 then
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
        if S.Full then
          Exit(HTCLIENT); // sem arrastar nem redimensionar
        Result := DefSubclassProc(hWnd, uMsg, wParam, lParam);
        if Result = HTCLIENT then
          Result := TitleHit(S, hWnd, lParam);
        if Result <> HTMAXBUTTON then
          SetMaxHot(S, False);
        Exit;
      end;
    WM_NCMOUSEMOVE:
      if wParam = HTMAXBUTTON then
      begin
        SetMaxHot(S, True);
        if not S.Tracking then
        begin
          Tme.cbSize := SizeOf(Tme);
          Tme.dwFlags := TME_LEAVE or TME_NONCLIENT;
          Tme.hwndTrack := hWnd;
          Tme.dwHoverTime := 0;
          S.Tracking := TrackMouseEvent(Tme);
        end;
        Exit(0);
      end
      else
        SetMaxHot(S, False);
    WM_NCMOUSELEAVE:
      begin
        S.Tracking := False;
        SetMaxHot(S, False);
      end;
    WM_NCLBUTTONDOWN, WM_NCLBUTTONDBLCLK:
      // Engole: o padrão desenharia o botão clássico por cima da nossa faixa.
      if wParam = HTMAXBUTTON then
        Exit(0);
    WM_NCLBUTTONUP:
      if wParam = HTMAXBUTTON then
      begin
        SetMaxHot(S, False);
        if Assigned(S.MaxClick) then
          S.MaxClick();
        Exit(0);
      end;
    WM_NCDESTROY:
      begin
        RemoveWindowSubclass(hWnd, @FrameProc, uIdSubclass);
        Dispose(S);
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
  S: PFrameState;
  Nova: Boolean;
begin
  EnsureComCtl;
  W := FormToHWND(AForm);
  if W = 0 then
    Exit;
  // O FMX pode recriar a janela: a nova ganha estado próprio, a velha libera o dela.
  S := FindState(W);
  Nova := S = nil;
  NecoTrace(Format('barra propria: hwnd=%x nova=%s', [NativeUInt(W), BoolToStr(Nova, True)]));
  if Nova then
  begin
    New(S); // New zera os campos gerenciados (os callbacks); o resto vai abaixo
    S.MaxHot := False;
    S.Tracking := False;
    S.Full := False;
    S.SavedStyle := 0;
    S.SavedRect := TRect.Empty;
    S.SavedMax := False;
  end;
  S.Form := AForm;
  S.TitleHeight := ATitleHeight;
  S.HitTest := AHitTest;
  S.MaxHover := AMaxHover;
  S.MaxClick := AMaxClick;
  if Nova and not SetWindowSubclass(W, @FrameProc, CFrameSubclassId, DWORD_PTR(S)) then
  begin
    NecoTrace(Format('barra propria: SetWindowSubclass falhou (erro %d)', [GetLastError]));
    Dispose(S);
    Exit;
  end;
  // Recalcula a moldura já com a regra nova (a barra branca some aqui).
  SetWindowPos(W, 0, 0, 0, 0, 0, SWP_FRAMECHANGED or SWP_NOMOVE or SWP_NOSIZE or
    SWP_NOZORDER or SWP_NOACTIVATE or SWP_NOOWNERZORDER);
end;

procedure NecoFrameDetach(AForm: TCommonCustomForm);
var
  S: PFrameState;
begin
  S := FindState(FormToHWND(AForm));
  if S = nil then
    Exit;
  S.HitTest := nil;
  S.MaxHover := nil;
  S.MaxClick := nil;
  S.Form := nil;
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

procedure NecoFrameSetFullScreen(AForm: TCommonCustomForm; AOn: Boolean);
var
  W: HWND;
  S: PFrameState;
  MI: TMonitorInfo;
  R: TRect;
begin
  W := FormToHWND(AForm);
  // O estado da tela cheia é da barra da janela: sem ela, nada a fazer.
  S := FindState(W);
  if (S = nil) or (AOn = S.Full) then
    Exit;
  if AOn then
  begin
    // Como o Chromium: guarda o estado, tira moldura e cobre o monitor.
    S.SavedMax := IsZoomed(W);
    if S.SavedMax then
      SendMessage(W, WM_SYSCOMMAND, SC_RESTORE, 0);
    GetWindowRect(W, S.SavedRect);
    S.SavedStyle := GetWindowLongPtr(W, GWL_STYLE);
    S.Full := True;
    SetWindowLongPtr(W, GWL_STYLE, S.SavedStyle and not NativeInt(WS_CAPTION or WS_THICKFRAME));
    MI.cbSize := SizeOf(MI);
    GetMonitorInfo(MonitorFromWindow(W, MONITOR_DEFAULTTONEAREST), @MI);
    R := MI.rcMonitor;
    SetWindowPos(W, HWND_TOP, R.Left, R.Top, R.Width, R.Height, SWP_NOOWNERZORDER or SWP_FRAMECHANGED);
  end
  else
  begin
    S.Full := False;
    SetWindowLongPtr(W, GWL_STYLE, S.SavedStyle);
    R := S.SavedRect;
    SetWindowPos(W, 0, R.Left, R.Top, R.Width, R.Height, SWP_NOZORDER or SWP_NOOWNERZORDER or SWP_FRAMECHANGED);
    if S.SavedMax then
      ShowWindow(W, SW_MAXIMIZE);
  end;
end;

/// O "normal" do placement é relativo à área de trabalho do monitor (sem a barra de
/// tarefas); o resto da sessão usa coordenadas de tela.
function WorkToScreen(const R: TRect): TRect;
var
  MI: TMonitorInfo;
  Rr: TRect;
begin
  Result := R;
  Rr := R;
  MI.cbSize := SizeOf(MI);
  if GetMonitorInfo(MonitorFromRect(@Rr, MONITOR_DEFAULTTONEAREST), @MI) then
    Result.Offset(MI.rcWork.Left - MI.rcMonitor.Left, MI.rcWork.Top - MI.rcMonitor.Top);
end;

function NecoFrameGetPlacement(AForm: TCommonCustomForm; out ABounds: TRect; out AMaximized: Boolean): Boolean;
var
  W: HWND;
  S: PFrameState;
  WP: TWindowPlacement;
begin
  ABounds := TRect.Empty;
  AMaximized := False;
  W := FormToHWND(AForm);
  if W = 0 then
    Exit(False);
  S := FindState(W);
  if (S <> nil) and S.Full then
  begin
    // Em tela cheia o retângulo é o do monitor: vale o de antes dela (já restaurada).
    ABounds := S.SavedRect;
    AMaximized := S.SavedMax;
    Exit(not ABounds.IsEmpty);
  end;
  WP.length := SizeOf(WP);
  if not GetWindowPlacement(W, WP) then
    Exit(False);
  // Minimizada: vale como ela volta.
  AMaximized := IsZoomed(W) or (IsIconic(W) and (WP.flags and WPF_RESTORETOMAXIMIZED <> 0));
  if not IsZoomed(W) and not IsIconic(W) then
    // Na tela: o retângulo de verdade. O "normal" do placement pode estar velho (fica o
    // de quando a janela foi criada, visto em 2026-11-11).
    GetWindowRect(W, ABounds)
  else
    ABounds := WorkToScreen(WP.rcNormalPosition);
  Result := not ABounds.IsEmpty;
end;

procedure NecoFrameSetPlacement(AForm: TCommonCustomForm; const ABounds: TRect);
var
  W: HWND;
  R: TRect;
begin
  W := FormToHWND(AForm);
  R := ABounds;
  // Monitor que não existe mais: deixa o sistema escolher.
  if (W = 0) or R.IsEmpty or (MonitorFromRect(@R, MONITOR_DEFAULTTONULL) = 0) then
    Exit;
  if IsZoomed(W) or IsIconic(W) then
    ShowWindow(W, SW_RESTORE);
  // Sem SWP_SHOWWINDOW: oculta continua oculta.
  SetWindowPos(W, 0, R.Left, R.Top, R.Width, R.Height, SWP_NOZORDER or SWP_NOACTIVATE or SWP_NOOWNERZORDER);
end;

procedure NecoFrameMakeIndependent(AForm: TCommonCustomForm);
var
  W, App: HWND;
  Ex: NativeInt;
  Changed: Boolean;
begin
  W := FormToHWND(AForm);
  if W = 0 then
    Exit;
  // O FMX cria toda janela de form "possuída" pela janela oculta do app, e é essa que fica
  // na barra de tarefas: com várias janelas seria um botão só. Sem dono e com
  // WS_EX_APPWINDOW, cada janela tem o seu botão e aparece no Alt+Tab.
  Changed := GetWindowLongPtr(W, GWLP_HWNDPARENT) <> 0;
  if Changed then
    SetWindowLongPtr(W, GWLP_HWNDPARENT, 0);
  Ex := GetWindowLongPtr(W, GWL_EXSTYLE);
  if Ex and WS_EX_APPWINDOW = 0 then
  begin
    SetWindowLongPtr(W, GWL_EXSTYLE, Ex or WS_EX_APPWINDOW);
    Changed := True;
  end;
  // A barra de tarefas só relê o estilo quando a janela aparece.
  if Changed and IsWindowVisible(W) then
  begin
    ShowWindow(W, SW_HIDE);
    ShowWindow(W, SW_SHOW);
  end;
  // A janela oculta do app sai da barra de tarefas e do Alt+Tab.
  App := ApplicationHWND;
  if App <> 0 then
  begin
    Ex := GetWindowLongPtr(App, GWL_EXSTYLE);
    if Ex and WS_EX_TOOLWINDOW = 0 then
    begin
      ShowWindow(App, SW_HIDE);
      SetWindowLongPtr(App, GWL_EXSTYLE, (Ex and not NativeInt(WS_EX_APPWINDOW)) or WS_EX_TOOLWINDOW);
    end;
  end;
  NecoTrace(Format('janela independente: hwnd=%x mudou=%s', [NativeUInt(W), BoolToStr(Changed, True)]));
end;

procedure NecoFrameStartSystemDrag(AForm: TCommonCustomForm; AGrabX, AGrabY: Integer);
var
  W: HWND;
  P: TPoint;
begin
  W := FormToHWND(AForm);
  if W = 0 then
    Exit;
  GetCursorPos(P);
  // AGrabX < 0: a janela fica onde está (arrasta a partir do ponto atual do mouse).
  if AGrabX >= 0 then
    SetWindowPos(W, HWND_TOP, P.X - AGrabX, P.Y - AGrabY, 0, 0, SWP_NOSIZE);
  SetForegroundWindow(W);
  // Quem tinha o mouse preso (a aba) solta; o clique "na barra de título" da janela nova
  // faz o Windows entrar no laço de mover, que dura até o botão ser solto.
  Winapi.Windows.ReleaseCapture;
  PostMessage(W, WM_NCLBUTTONDOWN, HTCAPTION, MakeLParam(Word(P.X), Word(P.Y)));
  NecoTrace(Format('arrasto do sistema: hwnd=%x em %d,%d', [NativeUInt(W), P.X, P.Y]));
end;

function NecoAcquireInstanceLock(const AName: string; AWaitMs: Cardinal): Boolean;
var
  N: string;
  H: THandle;
  Fim: UInt64;
begin
  // '\' separa espaço de nomes no Windows: o caminho da pasta vira um nome plano.
  N := 'NecoBrowser.' + StringReplace(StringReplace(LowerCase(AName), '\', '_', [rfReplaceAll]),
    ':', '_', [rfReplaceAll]);
  Fim := GetTickCount64 + AWaitMs;
  repeat
    H := CreateMutex(nil, False, PChar(N));
    // O handle da dona fica aberto de propósito: o Windows solta quando o processo termina.
    Result := (H <> 0) and (GetLastError <> ERROR_ALREADY_EXISTS);
    if Result then
      Exit;
    // Sem a trava, não segura o nome: senão a trava sobreviveria à dona enquanto esta
    // janela estiver aberta.
    if H <> 0 then
      CloseHandle(H);
    if GetTickCount64 >= Fim then
      Exit;
    Sleep(200);
  until False;
end;

procedure NecoShellOpen(const APath: string);
begin
  if APath <> '' then
    ShellExecute(0, 'open', PChar(APath), nil, nil, SW_SHOWNORMAL);
end;

procedure NecoLaunch(const AExe, AParams: string);
begin
  ShellExecute(0, 'open', PChar(AExe), PChar(AParams), PChar(ExtractFileDir(AExe)), SW_SHOWNORMAL);
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

procedure NecoFrameDetach(AForm: TCommonCustomForm);
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

procedure NecoFrameSetFullScreen(AForm: TCommonCustomForm; AOn: Boolean);
begin
end;

function NecoFrameGetPlacement(AForm: TCommonCustomForm; out ABounds: TRect; out AMaximized: Boolean): Boolean;
begin
  ABounds := TRect.Empty;
  AMaximized := False;
  Result := False;
end;

procedure NecoFrameSetPlacement(AForm: TCommonCustomForm; const ABounds: TRect);
begin
end;

procedure NecoFrameMakeIndependent(AForm: TCommonCustomForm);
begin
end;

procedure NecoFrameStartSystemDrag(AForm: TCommonCustomForm; AGrabX, AGrabY: Integer);
begin
end;

function NecoAcquireInstanceLock(const AName: string; AWaitMs: Cardinal): Boolean;
begin
  Result := True;
end;

procedure NecoShellOpen(const APath: string);
begin
end;

procedure NecoLaunch(const AExe, AParams: string);
begin
end;

procedure NecoShowInFolder(const APath: string);
begin
end;

{$ENDIF}

end.
