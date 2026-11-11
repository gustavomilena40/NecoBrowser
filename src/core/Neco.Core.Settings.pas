unit Neco.Core.Settings;

{ Caminhos e preferências do NecoBrowser (settings.json).
  Windows: dados em %APPDATA%\NecoBrowser e dados do motor em %LOCALAPPDATA%\NecoBrowser.
  Sem FMX e sem Winapi: compila em Windows e Android (TPath resolve por plataforma). }

interface

uses
  System.Types, Neco.Core.Url;

type
  TNecoTheme = (ntDark, ntLight);

  /// Uma janela da sessão gravada.
  TNecoSessionWindow = record
    Urls: TArray<string>; // na ordem da faixa
    Active: Integer;
    /// Posição e tamanho da janela restaurada (não maximizada), em pixels da tela.
    /// Vazio = não se sabe (o sistema escolhe).
    Bounds: TRect;
    Maximized: Boolean;
  end;

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
    /// Grava as janelas abertas (formato 2). Janela sem aba fica de fora.
    procedure SaveSessionWindows(const AWindows: TArray<TNecoSessionWindow>);
    /// Lê a sessão gravada, no formato 2 ou no 1 (uma janela só, sem posição).
    /// False = não há (ou o arquivo é inválido).
    function LoadSessionWindows(out AWindows: TArray<TNecoSessionWindow>): Boolean;
    /// Uma janela só: as abas abertas (URLs na ordem da faixa) e qual estava ativa.
    procedure SaveSession(const AUrls: TArray<string>; AActive: Integer);
    /// As abas da primeira janela da sessão gravada.
    function LoadSession(out AUrls: TArray<string>; out AActive: Integer): Boolean;
    property HomeUrl: string read FHomeUrl write FHomeUrl;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Generics.Collections, Neco.Core.Files;

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

/// "tabs" e "active" de um objeto (a raiz no formato 1, cada janela no 2).
procedure AddTabs(AObj: TJSONObject; const AUrls: TArray<string>; AActive: Integer);
var
  A: TJSONArray;
  U: string;
begin
  A := TJSONArray.Create;
  AObj.AddPair('tabs', A);
  for U in AUrls do
    A.Add(U);
  AObj.AddPair('active', TJSONNumber.Create(AActive));
end;

function ReadTabs(AObj: TJSONObject; out AWin: TNecoSessionWindow): Boolean;
var
  A: TJSONArray;
  V: TJSONValue;
begin
  AWin := Default(TNecoSessionWindow);
  if AObj.TryGetValue<TJSONArray>('tabs', A) then
    for V in A do
      if (V is TJSONString) and (V.Value <> '') then
        AWin.Urls := AWin.Urls + [V.Value];
  if not AObj.TryGetValue<Integer>('active', AWin.Active) or (AWin.Active < 0) or
    (AWin.Active >= Length(AWin.Urls)) then
    AWin.Active := 0;
  Result := Length(AWin.Urls) > 0;
end;

procedure TNecoSettings.SaveSessionWindows(const AWindows: TArray<TNecoSessionWindow>);
var
  O, J: TJSONObject;
  A, B: TJSONArray;
  W: TNecoSessionWindow;
  First: Boolean;
begin
  O := TJSONObject.Create;
  try
    O.AddPair('version', TJSONNumber.Create(2));
    A := TJSONArray.Create;
    First := True;
    for W in AWindows do
    begin
      if Length(W.Urls) = 0 then
        Continue;
      // A primeira janela também na raiz, como no formato 1: uma versão antiga do
      // navegador ainda reabre as abas dela.
      if First then
        AddTabs(O, W.Urls, W.Active);
      First := False;
      J := TJSONObject.Create;
      A.AddElement(J);
      AddTabs(J, W.Urls, W.Active);
      if not W.Bounds.IsEmpty then
      begin
        B := TJSONArray.Create;
        J.AddPair('bounds', B);
        B.Add(W.Bounds.Left);
        B.Add(W.Bounds.Top);
        B.Add(W.Bounds.Right);
        B.Add(W.Bounds.Bottom);
      end;
      J.AddPair('maximized', TJSONBool.Create(W.Maximized));
    end;
    O.AddPair('windows', A);
    NecoSaveTextAtomic(SessionFile, O.Format(2));
  finally
    O.Free;
  end;
end;

function TNecoSettings.LoadSessionWindows(out AWindows: TArray<TNecoSessionWindow>): Boolean;
var
  O: TJSONObject;
  A, B: TJSONArray;
  V: TJSONValue;
  W: TNecoSessionWindow;
  N: array[0..3] of Integer;
  I: Integer;
begin
  AWindows := nil;
  O := NecoParseObject(NecoLoadText(SessionFile));
  if O = nil then
    Exit(False);
  try
    if O.TryGetValue<TJSONArray>('windows', A) then
    begin
      for V in A do
        if (V is TJSONObject) and ReadTabs(TJSONObject(V), W) then
        begin
          if TJSONObject(V).TryGetValue<TJSONArray>('bounds', B) and (B.Count = 4) then
          begin
            for I := 0 to 3 do
              if not B.Items[I].TryGetValue<Integer>(N[I]) then
                N[I] := 0;
            W.Bounds := TRect.Create(N[0], N[1], N[2], N[3]);
            if W.Bounds.IsEmpty then
              W.Bounds := TRect.Empty;
          end;
          if not TJSONObject(V).TryGetValue<Boolean>('maximized', W.Maximized) then
            W.Maximized := False;
          AWindows := AWindows + [W];
        end;
    end
    else if ReadTabs(O, W) then
      AWindows := [W]; // formato 1: uma janela, sem posição
  finally
    O.Free;
  end;
  Result := Length(AWindows) > 0;
end;

procedure TNecoSettings.SaveSession(const AUrls: TArray<string>; AActive: Integer);
var
  W: TNecoSessionWindow;
begin
  W := Default(TNecoSessionWindow);
  W.Urls := AUrls;
  W.Active := AActive;
  SaveSessionWindows([W]);
end;

function TNecoSettings.LoadSession(out AUrls: TArray<string>; out AActive: Integer): Boolean;
var
  Ws: TArray<TNecoSessionWindow>;
begin
  AUrls := nil;
  AActive := 0;
  Result := LoadSessionWindows(Ws);
  if Result then
  begin
    AUrls := Ws[0].Urls;
    AActive := Ws[0].Active;
  end;
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
