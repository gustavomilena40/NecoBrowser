unit Neco.UI.Instance;

{ Uma instância só por perfil (pasta de dados).

  A primeira execução pega a trava com nome (NecoAcquireInstanceLock) e cria uma janela de
  mensagens oculta com o mesmo nome (NecoInstanceListen). Uma segunda execução (link clicado
  noutro programa, "Abrir com", atalho) acha essa janela, manda os argumentos por
  WM_COPYDATA e sai (NecoInstanceHandOff). A primeira abre o pedido numa aba.

  Perfil diferente (NECO_DADOS) = nome diferente = instância separada. }

interface

uses
  System.SysUtils;

type
  TNecoInstanceArgs = reference to procedure(const AArgs: TArray<string>);

/// Trava com nome (por processo, até ele fechar). True = esta instância é a primeira.
/// AWaitMs > 0: se outra tem a trava, espera ela fechar até esse tempo (reinício após atualizar).
function NecoAcquireInstanceLock(const AKey: string; AWaitMs: Cardinal = 0): Boolean;
/// Já há uma instância com este perfil? Entrega os argumentos a ela e devolve True (esta
/// execução deve sair). Se a outra ainda está abrindo, espera a janela dela até AWaitMs.
/// False = não há outra (ou ela não respondeu): esta segue normalmente.
function NecoInstanceHandOff(const AKey: string; const AArgs: TArray<string>; AWaitMs: Cardinal): Boolean;
/// Primeira instância: passa a receber os pedidos das próximas. AOnArgs roda na thread
/// principal, fora da mensagem (a outra execução já foi liberada).
procedure NecoInstanceListen(const AKey: string; const AOnArgs: TNecoInstanceArgs);
/// Para de receber (o app está fechando).
procedure NecoInstanceStop;

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows, Winapi.Messages, System.Classes, Neco.Core.Trace;

const
  CClassName = 'NecoBrowser.Instance';
  CMagic = $4E45434F; // 'NECO': identifica a mensagem
  CFormat = '1';      // primeira peça da mensagem: formato

var
  GWnd: HWND;
  GOnArgs: TNecoInstanceArgs;

/// '\' separa espaço de nomes no Windows: o caminho da pasta vira um nome plano.
function InstanceName(const AKey: string): string;
begin
  Result := 'NecoBrowser.' + StringReplace(StringReplace(LowerCase(AKey), '\', '_', [rfReplaceAll]),
    ':', '_', [rfReplaceAll]);
end;

function NecoAcquireInstanceLock(const AKey: string; AWaitMs: Cardinal): Boolean;
var
  N: string;
  H: THandle;
  Fim: UInt64;
begin
  N := InstanceName(AKey);
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

function InstanceWndProc(hWnd: HWND; uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  CDS: PCopyDataStruct;
  S: string;
  Partes, Args: TArray<string>;
begin
  if uMsg = WM_COPYDATA then
  begin
    CDS := PCopyDataStruct(lParam);
    if (CDS <> nil) and (CDS.dwData = CMagic) and Assigned(GOnArgs) then
    begin
      SetString(S, PChar(CDS.lpData), CDS.cbData div SizeOf(Char));
      if (S <> '') and (S[High(S)] = #0) then
        SetLength(S, Length(S) - 1); // o terminador
      Partes := S.Split([#0]);
      if (Length(Partes) = 0) or (Partes[0] <> CFormat) then
        Exit(0);
      Args := Copy(Partes, 1, MaxInt);
      NecoTrace(Format('instancia: pedido de outra execucao (%d argumentos)', [Length(Args)]));
      // Responde já: a outra execução sai, e o trabalho de tela roda depois.
      TThread.ForceQueue(nil,
        procedure
        begin
          if Assigned(GOnArgs) then
            GOnArgs(Args);
        end);
      Exit(1);
    end;
  end;
  Result := DefWindowProc(hWnd, uMsg, wParam, lParam);
end;

function NecoInstanceHandOff(const AKey: string; const AArgs: TArray<string>; AWaitMs: Cardinal): Boolean;
var
  N, Msg: string;
  Partes: TArray<string>;
  M: THandle;
  W: HWND;
  Pid: DWORD;
  CDS: TCopyDataStruct;
  Res: DWORD_PTR;
  Fim: UInt64;
begin
  Result := False;
  N := InstanceName(AKey);
  // Sem a trava, não há outra instância: esta é a primeira.
  M := OpenMutex(SYNCHRONIZE, False, PChar(N));
  if M = 0 then
    Exit;
  CloseHandle(M);
  Partes := [CFormat];
  Partes := Partes + AArgs;
  Msg := string.Join(#0, Partes);
  Fim := GetTickCount64 + AWaitMs;
  repeat
    W := FindWindowEx(HWND_MESSAGE, 0, CClassName, PChar(N));
    if W <> 0 then
    begin
      // Quem está em primeiro plano é esta execução: deixa a outra trazer a janela dela.
      if GetWindowThreadProcessId(W, Pid) <> 0 then
        AllowSetForegroundWindow(Pid);
      CDS.dwData := CMagic;
      CDS.cbData := (Length(Msg) + 1) * SizeOf(Char);
      CDS.lpData := PChar(Msg);
      Res := 0;
      if (SendMessageTimeout(W, WM_COPYDATA, 0, LPARAM(@CDS), SMTO_ABORTIFHUNG, 5000, @Res) <> 0) and
        (Res = 1) then
        Exit(True);
      Exit(False); // achou mas não respondeu: abre separada, como antes
    end;
    if GetTickCount64 >= Fim then
      Exit;
    Sleep(100);
  until False;
end;

procedure NecoInstanceListen(const AKey: string; const AOnArgs: TNecoInstanceArgs);
var
  WC: TWndClass;
begin
  if GWnd <> 0 then
    Exit;
  FillChar(WC, SizeOf(WC), 0);
  WC.lpfnWndProc := @InstanceWndProc;
  WC.hInstance := HInstance;
  WC.lpszClassName := CClassName;
  if (Winapi.Windows.RegisterClass(WC) = 0) and (GetLastError <> ERROR_CLASS_ALREADY_EXISTS) then
  begin
    NecoTrace(Format('instancia: RegisterClass falhou (erro %d)', [GetLastError]));
    Exit;
  end;
  GOnArgs := AOnArgs;
  GWnd := CreateWindowEx(0, CClassName, PChar(InstanceName(AKey)), 0, 0, 0, 0, 0, HWND_MESSAGE, 0,
    HInstance, nil);
  if GWnd = 0 then
  begin
    NecoTrace(Format('instancia: CreateWindowEx falhou (erro %d)', [GetLastError]));
    GOnArgs := nil;
  end;
end;

procedure NecoInstanceStop;
begin
  GOnArgs := nil;
  if GWnd <> 0 then
  begin
    DestroyWindow(GWnd);
    GWnd := 0;
  end;
end;

{$ELSE}

function NecoAcquireInstanceLock(const AKey: string; AWaitMs: Cardinal): Boolean;
begin
  Result := True;
end;

function NecoInstanceHandOff(const AKey: string; const AArgs: TArray<string>; AWaitMs: Cardinal): Boolean;
begin
  Result := False;
end;

procedure NecoInstanceListen(const AKey: string; const AOnArgs: TNecoInstanceArgs);
begin
end;

procedure NecoInstanceStop;
begin
end;

{$ENDIF}

end.
