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

end.
