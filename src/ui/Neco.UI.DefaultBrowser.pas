unit Neco.UI.DefaultBrowser;

{ Navegador padrão do Windows.

  O Windows 10/11 não deixa um programa se pôr como padrão sozinho (a escolha é protegida
  por hash). O que dá para fazer, e o que o Chrome e o Firefox fazem:
  1. registrar o NecoBrowser como navegador no registro do usuário (HKCU, sem administrador):
     Software\Clients\StartMenuInternet\NecoBrowser + Software\RegisteredApplications +
     as classes NecoBrowserURL (http/https) e NecoBrowserHTML (.html, .pdf...);
  2. abrir "Aplicativos padrão" já na página do NecoBrowser, onde a pessoa confirma.

  O exe é portátil: o registro guarda o caminho de onde ele estava ao registrar. }

interface

/// Registra (ou atualiza o caminho) e avisa o Explorer. False se o registro recusou.
function NecoRegisterBrowser: Boolean;
/// O NecoBrowser aparece na lista de navegadores do Windows.
function NecoBrowserRegistered: Boolean;
/// É o navegador padrão para links https.
function NecoIsDefaultBrowser: Boolean;
/// Se já foi registrado de outra pasta e aquele exe não existe mais (moveu a pasta),
/// registra de novo com o caminho atual. Não mexe se o outro exe ainda existe: um build
/// de teste não toma o lugar do navegador que a pessoa usa.
procedure NecoFixBrowserRegistration;
/// Abre "Aplicativos padrão" do Windows na página do NecoBrowser.
procedure NecoOpenDefaultAppsSettings;

implementation

{$IFDEF MSWINDOWS}

uses
  System.SysUtils, System.Win.Registry, Winapi.Windows, Winapi.ShellAPI, Winapi.ShlObj;

const
  CAppKey = 'Software\Clients\StartMenuInternet\NecoBrowser';
  CCapKey = CAppKey + '\Capabilities';
  CUrlClass = 'NecoBrowserURL';
  CHtmlClass = 'NecoBrowserHTML';
  CFileExts: array[0..7] of string = ('.htm', '.html', '.shtml', '.xht', '.xhtml', '.svg',
    '.webp', '.pdf');

function ExePath: string;
begin
  Result := ParamStr(0);
end;

function OpenCommand: string;
begin
  Result := '"' + ExePath + '" "%1"';
end;

procedure WriteKey(R: TRegistry; const AKey, AName, AValue: string);
begin
  if not R.OpenKey(AKey, True) then
    raise Exception.Create('sem acesso a ' + AKey);
  try
    R.WriteString(AName, AValue);
  finally
    R.CloseKey;
  end;
end;

procedure WriteClass(R: TRegistry; const AClass, ADesc: string; AIsUrl: Boolean);
var
  K: string;
begin
  K := 'Software\Classes\' + AClass;
  WriteKey(R, K, '', ADesc);
  if AIsUrl then
    WriteKey(R, K, 'URL Protocol', '');
  WriteKey(R, K, 'FriendlyTypeName', ADesc);
  WriteKey(R, K + '\DefaultIcon', '', ExePath + ',0');
  WriteKey(R, K + '\Application', 'ApplicationName', 'NecoBrowser');
  WriteKey(R, K + '\Application', 'ApplicationIcon', ExePath + ',0');
  WriteKey(R, K + '\shell\open\command', '', OpenCommand);
end;

function NecoRegisterBrowser: Boolean;
var
  R: TRegistry;
  E: string;
begin
  Result := False;
  R := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    R.RootKey := HKEY_CURRENT_USER;
    try
      WriteClass(R, CUrlClass, 'NecoBrowser URL', True);
      WriteClass(R, CHtmlClass, 'Documento do NecoBrowser', False);

      WriteKey(R, CAppKey, '', 'NecoBrowser');
      WriteKey(R, CAppKey + '\DefaultIcon', '', ExePath + ',0');
      WriteKey(R, CAppKey + '\shell\open\command', '', '"' + ExePath + '"');
      WriteKey(R, CCapKey, 'ApplicationName', 'NecoBrowser');
      WriteKey(R, CCapKey, 'ApplicationDescription', 'Navegador leve com a Neco-Arc.');
      WriteKey(R, CCapKey, 'ApplicationIcon', ExePath + ',0');
      WriteKey(R, CCapKey + '\StartMenu', 'StartMenuInternet', 'NecoBrowser');
      WriteKey(R, CCapKey + '\URLAssociations', 'http', CUrlClass);
      WriteKey(R, CCapKey + '\URLAssociations', 'https', CUrlClass);
      for E in CFileExts do
      begin
        WriteKey(R, CCapKey + '\FileAssociations', E, CHtmlClass);
        // "Abrir com" do Explorer lista o NecoBrowser para estes tipos.
        WriteKey(R, 'Software\Classes\' + E + '\OpenWithProgids', CHtmlClass, '');
      end;
      WriteKey(R, 'Software\RegisteredApplications', 'NecoBrowser', CCapKey);
      Result := True;
    except
      // sem permissão no registro: a tela do Windows abre mesmo assim, só sem o NecoBrowser
    end;
  finally
    R.Free;
  end;
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);
end;

function ReadValue(const AKey, AName: string): string;
var
  R: TRegistry;
begin
  Result := '';
  R := TRegistry.Create(KEY_READ);
  try
    R.RootKey := HKEY_CURRENT_USER;
    if R.OpenKeyReadOnly(AKey) then
      try
        if R.ValueExists(AName) then
          Result := R.ReadString(AName);
      finally
        R.CloseKey;
      end;
  finally
    R.Free;
  end;
end;

function NecoBrowserRegistered: Boolean;
begin
  Result := SameText(ReadValue('Software\RegisteredApplications', 'NecoBrowser'), CCapKey);
end;

function NecoIsDefaultBrowser: Boolean;
begin
  Result := SameText(ReadValue(
    'Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice', 'ProgId'),
    CUrlClass);
end;

procedure NecoFixBrowserRegistration;
var
  Cmd, Antigo: string;
begin
  if not NecoBrowserRegistered then
    Exit;
  Cmd := ReadValue('Software\Classes\' + CUrlClass + '\shell\open\command', '');
  if SameText(Cmd, OpenCommand) then
    Exit;
  // "C:\pasta\NecoBrowser.exe" "%1" -> C:\pasta\NecoBrowser.exe
  Antigo := Cmd;
  if Antigo.StartsWith('"') then
    Antigo := Copy(Antigo, 2, Pos('"', Copy(Antigo, 2, MaxInt)) - 1);
  if (Antigo = '') or not FileExists(Antigo) then
    NecoRegisterBrowser;
end;

procedure NecoOpenDefaultAppsSettings;
begin
  // registeredAppUser abre direto a página do app (Windows 11); o Windows 10 ignora o
  // parâmetro e mostra a lista geral de aplicativos padrão.
  ShellExecute(0, 'open', 'ms-settings:defaultapps?registeredAppUser=NecoBrowser', nil, nil,
    SW_SHOWNORMAL);
end;

{$ELSE}

function NecoRegisterBrowser: Boolean;
begin
  Result := False;
end;

function NecoBrowserRegistered: Boolean;
begin
  Result := False;
end;

function NecoIsDefaultBrowser: Boolean;
begin
  Result := False;
end;

procedure NecoFixBrowserRegistration;
begin
end;

procedure NecoOpenDefaultAppsSettings;
begin
end;

{$ENDIF}

end.
