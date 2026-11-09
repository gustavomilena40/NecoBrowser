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
    FHomeUrl: string;
    FCustomDir: Boolean;
    function GetSettingsFile: string;
    function GetBookmarksFile: string;
    function GetHistoryFile: string;
    function GetDownloadsDir: string;
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
