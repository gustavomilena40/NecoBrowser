unit Neco.Core.Settings;

{ Caminhos e preferências do NecoBrowser (settings.json).
  Windows: dados em %APPDATA%\NecoBrowser e dados do motor em %LOCALAPPDATA%\NecoBrowser.
  Sem FMX e sem Winapi: compila em Windows e Android (TPath resolve por plataforma). }

interface

uses
  Neco.Core.Url;

type
  TNecoTheme = (ntDark, ntLight);

  TNecoSettings = class
  private
    FDataDir: string;
    FWebDataDir: string;
    FSearchEngine: TNecoSearchEngine;
    FTheme: TNecoTheme;
    FBlockerEnabled: Boolean;
    FNecoShown: Boolean;
    FFormAutofill: Boolean;
    FSavePasswords: Boolean;
    FShowBookmarkBar: Boolean;
    FRestoreSession: Boolean;
    FAutoUpdate: Boolean;
    FHomeUrl: string;
    FCustomDir: Boolean;
    function GetSettingsFile: string;
    function GetBookmarksFile: string;
    function GetHistoryFile: string;
    function GetDownloadsDir: string;
    function GetSessionFile: string;
  public
    /// ADataDir vazio usa o padrão da plataforma. Os testes passam uma pasta temporária
    /// (e aí os downloads também vão para dentro dela).
    constructor Create(const ADataDir: string = '');
    procedure Load;
    procedure Save;
    function ToJson: string;
    procedure FromJson(const AJson: string);
    property DataDir: string read FDataDir;
    /// Dados do motor (cache, cookies). Fica fora da pasta que roaming sincroniza.
    property WebDataDir: string read FWebDataDir;
    property SettingsFile: string read GetSettingsFile;
    property BookmarksFile: string read GetBookmarksFile;
    property HistoryFile: string read GetHistoryFile;
    property DownloadsDir: string read GetDownloadsDir;
    property SearchEngine: TNecoSearchEngine read FSearchEngine write FSearchEngine;
    property Theme: TNecoTheme read FTheme write FTheme;
    property BlockerEnabled: Boolean read FBlockerEnabled write FBlockerEnabled;
    /// Mostrar a Neco-Arc (faixa de abas, painéis, página de erro).
    property NecoShown: Boolean read FNecoShown write FNecoShown;
    /// O motor lembra o que foi digitado em formulários (nome, endereço...) e sugere de novo.
    property FormAutofill: Boolean read FFormAutofill write FFormAutofill;
    /// O motor oferece salvar senhas (guardadas cifradas no perfil do motor).
    property SavePasswords: Boolean read FSavePasswords write FSavePasswords;
    /// Barra de favoritos abaixo da barra de endereço (Ctrl+Shift+B).
    property ShowBookmarkBar: Boolean read FShowBookmarkBar write FShowBookmarkBar;
    /// Ao abrir, reabre as abas que estavam abertas ao fechar.
    property RestoreSession: Boolean read FRestoreSession write FRestoreSession;
    property SessionFile: string read GetSessionFile;
    /// Procura versão nova no GitHub, baixa e troca o exe ao reiniciar.
    property AutoUpdate: Boolean read FAutoUpdate write FAutoUpdate;
    /// Onde a atualização baixada espera a troca (fora da pasta que roaming sincroniza).
    function UpdateDir: string;
    /// Grava as abas abertas (URLs na ordem da faixa) e qual estava ativa.
    procedure SaveSession(const AUrls: TArray<string>; AActive: Integer);
    /// Lê a sessão gravada. False = não há (ou o arquivo é inválido).
    function LoadSession(out AUrls: TArray<string>; out AActive: Integer): Boolean;
    property HomeUrl: string read FHomeUrl write FHomeUrl;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.IOUtils, Neco.Core.Files;

const
  CAppFolder = 'NecoBrowser';
  CDefaultHome = 'https://www.google.com/';

{ TNecoSettings }

constructor TNecoSettings.Create(const ADataDir: string);
begin
  inherited Create;
  if ADataDir <> '' then
  begin
    FDataDir := ADataDir;
    FWebDataDir := TPath.Combine(ADataDir, 'web');
    FCustomDir := True;
  end
  else
  begin
    FDataDir := TPath.Combine(TPath.GetHomePath, CAppFolder);
    FWebDataDir := TPath.Combine(TPath.GetCachePath, CAppFolder);
  end;
  FSearchEngine := seGoogle;
  FTheme := ntDark;
  FBlockerEnabled := True;
  FNecoShown := True;
  FFormAutofill := True;
  FSavePasswords := True;
  FShowBookmarkBar := True;
  FRestoreSession := True;
  FAutoUpdate := True;
  FHomeUrl := CDefaultHome;
end;

function TNecoSettings.GetSettingsFile: string;
begin
  Result := TPath.Combine(FDataDir, 'settings.json');
end;

function TNecoSettings.GetBookmarksFile: string;
begin
  Result := TPath.Combine(FDataDir, 'bookmarks.json');
end;

function TNecoSettings.GetHistoryFile: string;
begin
  Result := TPath.Combine(FDataDir, 'history.json');
end;

function TNecoSettings.GetDownloadsDir: string;
begin
  if FCustomDir then
    Result := ''
  else
    Result := TPath.GetDownloadsPath;
  if Result = '' then
    Result := TPath.Combine(FDataDir, 'Downloads');
end;

function TNecoSettings.UpdateDir: string;
begin
  Result := TPath.Combine(FWebDataDir, 'update');
end;

function TNecoSettings.GetSessionFile: string;
begin
  Result := TPath.Combine(FDataDir, 'session.json');
end;

procedure TNecoSettings.SaveSession(const AUrls: TArray<string>; AActive: Integer);
var
  O: TJSONObject;
  A: TJSONArray;
  U: string;
begin
  O := TJSONObject.Create;
  try
    O.AddPair('version', TJSONNumber.Create(1));
    A := TJSONArray.Create;
    O.AddPair('tabs', A);
    for U in AUrls do
      A.Add(U);
    O.AddPair('active', TJSONNumber.Create(AActive));
    NecoSaveTextAtomic(SessionFile, O.Format(2));
  finally
    O.Free;
  end;
end;

function TNecoSettings.LoadSession(out AUrls: TArray<string>; out AActive: Integer): Boolean;
var
  O: TJSONObject;
  A: TJSONArray;
  V: TJSONValue;
begin
  AUrls := nil;
  AActive := 0;
  O := NecoParseObject(NecoLoadText(SessionFile));
  if O = nil then
    Exit(False);
  try
    if O.TryGetValue<TJSONArray>('tabs', A) then
      for V in A do
        if (V is TJSONString) and (V.Value <> '') then
          AUrls := AUrls + [V.Value];
    if not O.TryGetValue<Integer>('active', AActive) then
      AActive := 0;
    if (AActive < 0) or (AActive >= Length(AUrls)) then
      AActive := 0;
  finally
    O.Free;
  end;
  Result := Length(AUrls) > 0;
end;

function TNecoSettings.ToJson: string;
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  try
    O.AddPair('version', TJSONNumber.Create(1));
    O.AddPair('searchEngine', NecoSearchEngineId(FSearchEngine));
    if FTheme = ntLight then
      O.AddPair('theme', 'light')
    else
      O.AddPair('theme', 'dark');
    O.AddPair('blocker', TJSONBool.Create(FBlockerEnabled));
    O.AddPair('neco', TJSONBool.Create(FNecoShown));
    O.AddPair('formAutofill', TJSONBool.Create(FFormAutofill));
    O.AddPair('savePasswords', TJSONBool.Create(FSavePasswords));
    O.AddPair('bookmarkBar', TJSONBool.Create(FShowBookmarkBar));
    O.AddPair('restoreSession', TJSONBool.Create(FRestoreSession));
    O.AddPair('autoUpdate', TJSONBool.Create(FAutoUpdate));
    O.AddPair('home', FHomeUrl);
    Result := O.Format(2);
  finally
    O.Free;
  end;
end;

procedure TNecoSettings.FromJson(const AJson: string);
var
  O: TJSONObject;
begin
  O := NecoParseObject(AJson);
  if O = nil then
    Exit;
  try
    FSearchEngine := NecoSearchEngineFromId(NecoJsonStr(O, 'searchEngine', ''));
    if SameText(NecoJsonStr(O, 'theme', 'dark'), 'light') then
      FTheme := ntLight
    else
      FTheme := ntDark;
    FBlockerEnabled := NecoJsonBool(O, 'blocker', True);
    FNecoShown := NecoJsonBool(O, 'neco', True);
    FFormAutofill := NecoJsonBool(O, 'formAutofill', True);
    FSavePasswords := NecoJsonBool(O, 'savePasswords', True);
    FShowBookmarkBar := NecoJsonBool(O, 'bookmarkBar', True);
    FRestoreSession := NecoJsonBool(O, 'restoreSession', True);
    FAutoUpdate := NecoJsonBool(O, 'autoUpdate', True);
    FHomeUrl := NecoJsonStr(O, 'home', CDefaultHome);
    if FHomeUrl = '' then
      FHomeUrl := CDefaultHome;
  finally
    O.Free;
  end;
end;

procedure TNecoSettings.Load;
begin
  FromJson(NecoLoadText(SettingsFile));
end;

procedure TNecoSettings.Save;
begin
  NecoSaveTextAtomic(SettingsFile, ToJson);
end;

end.
