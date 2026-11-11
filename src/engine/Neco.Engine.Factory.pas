unit Neco.Engine.Factory;

{ Escolhe a implementação do motor por plataforma.
  Windows: WebView2. Android: fase 2 (WebView com JNI), ainda não implementado. }

interface

uses
  FMX.Forms, Neco.Engine.Intf;

type
  TNecoEngineConfig = record
    /// Dados do motor (cache, cookies). No Windows: %LOCALAPPDATA%\NecoBrowser.
    WebDataDir: string;
    DownloadsDir: string;
    Language: string;
    /// Cor $AARRGGBB pintada antes da página.
    BackgroundColor: Cardinal;
  end;

/// Configura o motor uma vez, antes da primeira aba.
procedure NecoEngineSetup(const AConfig: TNecoEngineConfig);
/// Cria um motor filho do form. A criação nativa é assíncrona (ver INecoEngine.IsReady).
function NecoCreateEngine(AForm: TCommonCustomForm): INecoEngine;
/// Fecha todos os motores e downloads. Chamar ao fechar o app.
procedure NecoEngineShutdown;
/// Mede a memória do navegador inteiro (o exe e todos os processos do motor).
/// A resposta chega depois, na thread principal.
procedure NecoEngineQueryMemory(const ACallback: TNecoMemoryCallback);

type
  TNecoExtInstalledEvent = reference to procedure(const AFolder: string);

/// Extensão de bloqueio de anúncios (uBlock Origin Lite) para todas as abas.
/// AFolder: pasta descompactada ('' = ainda não baixada). AManage: este processo instala e
/// troca versões (só a janela dona da sessão); sem ele, só liga ou desliga a instalada.
/// AOnInstalled: thread principal, com a pasta que ficou instalada.
procedure NecoEngineSetAdExtension(const AFolder: string; AManage, AEnabled: Boolean;
  const AOnInstalled: TNecoExtInstalledEvent);

implementation

uses
  System.SysUtils, System.IOUtils
{$IFDEF MSWINDOWS}
  , FMX.Platform.Win, Neco.Engine.WebView2
{$ENDIF};

procedure NecoEngineSetup(const AConfig: TNecoEngineConfig);
{$IFDEF MSWINDOWS}
var
  O: TNecoWV2Options;
begin
  O.UserDataFolder := TPath.Combine(AConfig.WebDataDir, 'WebView2');
  O.LoaderPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'WebView2Loader.dll');
  O.BinFolder := TPath.Combine(AConfig.WebDataDir, 'bin' + PathDelim +
    {$IFDEF WIN64}'x64'{$ELSE}'x86'{$ENDIF});
  O.DownloadsFolder := AConfig.DownloadsDir;
  O.Language := AConfig.Language;
  O.BackgroundColor := AConfig.BackgroundColor;
  NecoWV2Setup(O);
end;
{$ELSE}
begin
end;
{$ENDIF}

function NecoCreateEngine(AForm: TCommonCustomForm): INecoEngine;
begin
{$IFDEF MSWINDOWS}
  Result := NecoWV2CreateEngine(FormToHWND(AForm));
{$ELSE}
  raise ENotSupportedException.Create('Motor ainda não implementado nesta plataforma (fase 2).');
{$ENDIF}
end;

procedure NecoEngineShutdown;
begin
{$IFDEF MSWINDOWS}
  NecoWV2Shutdown;
{$ENDIF}
end;

procedure NecoEngineQueryMemory(const ACallback: TNecoMemoryCallback);
begin
{$IFDEF MSWINDOWS}
  NecoWV2QueryMemory(ACallback);
{$ENDIF}
end;

procedure NecoEngineSetAdExtension(const AFolder: string; AManage, AEnabled: Boolean;
  const AOnInstalled: TNecoExtInstalledEvent);
begin
{$IFDEF MSWINDOWS}
  NecoWV2SetAdExtension(AFolder, AManage, AEnabled, TNecoWV2ExtInstalled(AOnInstalled));
{$ENDIF}
end;

end.
