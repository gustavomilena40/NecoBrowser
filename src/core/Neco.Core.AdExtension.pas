unit Neco.Core.AdExtension;

{ Bloqueador de anúncios em forma de extensão: o uBlock Origin Lite (uBOL).

  Por que além da lista de hosts: o YouTube serve o anúncio pelos mesmos endereços do
  vídeo, e quem bloqueia por endereço (lista de hosts, DNS) não tem como separar um do
  outro. O uBOL roda dentro da página e tira o anúncio de lá.

  Ciclo: Check consulta /releases/latest do uBOL numa tarefa de fundo. Se a versão lá for
  outra, baixa o .chromium.zip, confere o SHA-256 que o GitHub publica do arquivo
  ("digest") e descompacta em <pasta>\uBOLite-<versão>. Só então grava current.json.
  Quem instala a pasta no motor é a UI (NecoEngineSetAdExtension).

  Sem FMX. }

interface

uses
  System.SysUtils, System.Threading;

type
  TNecoAdRelease = record
    Version: string;
    ZipUrl: string;
    /// SHA-256 em hexadecimal minúsculo.
    Sha256: string;
  end;

  /// Thread principal, ao fim de toda consulta. AFolder = pasta nova pronta ('' = nada novo ou falhou).
  TNecoAdExtensionReady = reference to procedure(const AFolder: string);

  TNecoAdExtension = class
  private
    FDir: string;
    FTask: ITask;
    function StateFile: string;
    function GetBusy: Boolean;
  public
    /// ADir: onde ficam as versões descompactadas e o current.json (criada se faltar).
    constructor Create(const ADir: string);
    /// Pasta da versão já baixada e conferida. '' = nenhuma (primeira vez ou apagada).
    function CurrentFolder: string;
    function CurrentVersion: string;
    /// Consulta e baixa em segundo plano. Erros só vão para o rastro (NECO_TRACE).
    procedure Check(const AOnReady: TNecoAdExtensionReady);
    /// Apaga as versões antigas, menos AKeep (a que o motor está usando) e a atual.
    procedure Cleanup(const AKeep: string);
    /// Ao fechar o app: interrompe o download e espera a tarefa (até 5 s).
    /// Depois disso nenhum AOnReady é chamado.
    procedure Shutdown;
    property Busy: Boolean read GetBusy;
  end;

/// Lê o JSON de /releases/latest do uBOL. False se faltar a tag, o .chromium.zip ou o digest.
function NecoParseAdRelease(const AJson: string; out ARelease: TNecoAdRelease): Boolean;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.Hash, System.Zip,
  System.Net.HttpClient, System.Net.URLClient,
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}
  Neco.Core.Files, Neco.Core.Trace;

const
  CLatestUrl = 'https://api.github.com/repos/uBlockOrigin/uBOL-home/releases/latest';
  CPrefix = 'uBOLite-';

var
  // Ligado no Shutdown. Só há um baixador por processo.
  GCancel: Boolean;

function NecoParseAdRelease(const AJson: string; out ARelease: TNecoAdRelease): Boolean;
var
  O, Asset: TJSONObject;
  Assets: TJSONArray;
  V: TJSONValue;
  Name, Digest: string;
  I: Integer;
begin
  ARelease := Default(TNecoAdRelease);
  O := NecoParseObject(AJson);
  if O = nil then
    Exit(False);
  try
    if NecoJsonBool(O, 'draft', False) or NecoJsonBool(O, 'prerelease', False) then
      Exit(False);
    ARelease.Version := NecoJsonStr(O, 'tag_name', '');
    if O.TryGetValue<TJSONArray>('assets', Assets) then
      for V in Assets do
        if V is TJSONObject then
        begin
          Asset := TJSONObject(V);
          Name := NecoJsonStr(Asset, 'name', '');
          if not (Name.StartsWith('uBOLite_', True) and Name.EndsWith('.chromium.zip', True)) then
            Continue;
          ARelease.ZipUrl := NecoJsonStr(Asset, 'browser_download_url', '');
          Digest := LowerCase(NecoJsonStr(Asset, 'digest', ''));
          if Digest.StartsWith('sha256:') then
            ARelease.Sha256 := Copy(Digest, 8, MaxInt);
        end;
  finally
    O.Free;
  end;
  // Sem o hash não baixa: é o que garante que o arquivo chegou inteiro e é o publicado.
  if Length(ARelease.Sha256) <> 64 then
    ARelease.Sha256 := '';
  for I := 1 to Length(ARelease.Sha256) do
    if not CharInSet(ARelease.Sha256[I], ['0'..'9', 'a'..'f']) then
      ARelease.Sha256 := '';
  // A versão vira nome de pasta: só dígitos e pontos.
  for I := 1 to Length(ARelease.Version) do
    if not CharInSet(ARelease.Version[I], ['0'..'9', '.']) then
      ARelease.Version := '';
  Result := (ARelease.Version <> '') and (ARelease.ZipUrl <> '') and (ARelease.Sha256 <> '');
end;

/// Descompacta recusando caminho que saia da pasta (".." ou absoluto).
procedure ExtractSafe(const AZip, ADest: string);
var
  Z: TZipFile;
  N: string;
  I: Integer;
begin
  Z := TZipFile.Create;
  try
    Z.Open(AZip, zmRead);
    for I := 0 to Z.FileCount - 1 do
    begin
      N := StringReplace(Z.FileNames[I], '/', '\', [rfReplaceAll]);
      if N.StartsWith('\') or (Pos(':', N) > 0) or (Pos('..\', N + '\') > 0) then
        raise Exception.Create('zip com caminho suspeito: ' + Z.FileNames[I]);
    end;
    Z.ExtractAll(ADest);
    Z.Close;
  finally
    Z.Free;
  end;
end;

{ TNecoAdExtension }

constructor TNecoAdExtension.Create(const ADir: string);
begin
  inherited Create;
  FDir := ADir;
end;

function TNecoAdExtension.StateFile: string;
begin
  Result := TPath.Combine(FDir, 'current.json');
end;

function TNecoAdExtension.GetBusy: Boolean;
begin
  Result := (FTask <> nil) and not (FTask.Status in [TTaskStatus.Completed,
    TTaskStatus.Canceled, TTaskStatus.Exception]);
end;

function TNecoAdExtension.CurrentVersion: string;
var
  O: TJSONObject;
begin
  Result := '';
  O := NecoParseObject(NecoLoadText(StateFile));
  if O = nil then
    Exit;
  try
    Result := NecoJsonStr(O, 'version', '');
  finally
    O.Free;
  end;
end;

function TNecoAdExtension.CurrentFolder: string;
var
  V: string;
begin
  Result := '';
  V := CurrentVersion;
  if V = '' then
    Exit;
  Result := TPath.Combine(FDir, CPrefix + V);
  if not FileExists(TPath.Combine(Result, 'manifest.json')) then
    Result := '';
end;

procedure TNecoAdExtension.Cleanup(const AKeep: string);
var
  D, Cur: string;
begin
  if not DirectoryExists(FDir) then
    Exit;
  Cur := CurrentFolder;
  try
    for D in TDirectory.GetDirectories(FDir, CPrefix + '*') do
      if not SameText(D, AKeep) and not SameText(D, Cur) then
        try
          TDirectory.Delete(D, True);
          NecoTrace('extensao: versao antiga apagada ' + D);
        except
          // arquivo ainda preso pelo motor: fica para a próxima
        end;
  except
    // pasta sem acesso: nada a limpar
  end;
end;

procedure TNecoAdExtension.Shutdown;
begin
  GCancel := True;
  if Busy then
    try
      FTask.Wait(5000);
    except
      // a tarefa trata os próprios erros; aqui só não pode travar o fechamento
    end;
end;

procedure TNecoAdExtension.Check(const AOnReady: TNecoAdExtensionReady);
var
  Dir, Url, Cur: string;
begin
  if Busy or GCancel then
    Exit;
  // A tarefa só usa cópias: nada dela aponta para este objeto.
  Dir := FDir;
  Cur := CurrentFolder;
  if Cur <> '' then
    Cur := CurrentVersion;
  Url := GetEnvironmentVariable('NECO_UBOL_URL'); // teste sem a rede do GitHub
  if Url = '' then
    Url := CLatestUrl;
  FTask := TTask.Run(
    procedure
    var
      Http: THTTPClient;
      Resp: IHTTPResponse;
      Rel: TNecoAdRelease;
      Part, Tmp, Final, Ready: string;
      FS: TFileStream;
      O: TJSONObject;
    begin
      Ready := '';
      try
        Http := THTTPClient.Create;
        try
          Http.UserAgent := 'NecoBrowser';
          Http.ConnectionTimeout := 15000;
          Http.ResponseTimeout := 60000;
          // Fechar o app interrompe o download no próximo bloco recebido.
          Http.ReceiveDataCallback :=
            procedure(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean)
            begin
              AAbort := GCancel;
            end;
          Resp := Http.Get(Url, nil, [TNetHeader.Create('Accept', 'application/vnd.github+json')]);
          if Resp.StatusCode <> 200 then
            raise Exception.CreateFmt('consulta devolveu %d', [Resp.StatusCode]);
          if not NecoParseAdRelease(Resp.ContentAsString(TEncoding.UTF8), Rel) then
            raise Exception.Create('release sem .chromium.zip com digest');
          if Rel.Version = Cur then
          begin
            NecoTrace('extensao: ja na mais nova (' + Cur + ')');
            Exit;
          end;

          ForceDirectories(Dir);
          Part := TPath.Combine(Dir, CPrefix + Rel.Version + '.zip.part');
          FS := TFileStream.Create(Part, fmCreate);
          try
            Resp := Http.Get(Rel.ZipUrl, FS);
          finally
            FS.Free;
          end;
          try
            if Resp.StatusCode <> 200 then
              raise Exception.CreateFmt('download devolveu %d', [Resp.StatusCode]);
            if not SameText(THashSHA2.GetHashStringFromFile(Part, THashSHA2.TSHA2Version.SHA256),
              Rel.Sha256) then
              raise Exception.Create('hash nao confere: download descartado');
            if GCancel then
              Exit;
            // Descompacta numa pasta de passagem: pasta com o nome final só existe inteira.
            Final := TPath.Combine(Dir, CPrefix + Rel.Version);
            Tmp := Final + '.tmp';
            if DirectoryExists(Tmp) then
              TDirectory.Delete(Tmp, True);
            ExtractSafe(Part, Tmp);
            if not FileExists(TPath.Combine(Tmp, 'manifest.json')) then
              raise Exception.Create('zip sem manifest.json');
            if DirectoryExists(Final) then
              TDirectory.Delete(Final, True);
            if not RenameFile(Tmp, Final) then
              raise Exception.Create('nao renomeou a pasta descompactada');
          finally
            System.SysUtils.DeleteFile(Part);
            if (Tmp <> '') and DirectoryExists(Tmp) then
              try
                TDirectory.Delete(Tmp, True);
              except
                // sobra apagada pelo Cleanup
              end;
          end;

          O := TJSONObject.Create;
          try
            O.AddPair('version', Rel.Version);
            NecoSaveTextAtomic(TPath.Combine(Dir, 'current.json'), O.Format(2));
          finally
            O.Free;
          end;
          NecoTrace('extensao: uBOL ' + Rel.Version + ' baixado e conferido');
          Ready := Final;
        finally
          Http.Free;
          // Volta à thread principal, a não ser que o app esteja fechando.
          if not GCancel then
            TThread.Queue(nil,
              procedure
              begin
                if not GCancel then
                  AOnReady(Ready);
              end);
        end;
      except
        on E: Exception do
          NecoTrace('extensao: download falhou: ' + E.Message);
      end;
    end);
end;

end.
