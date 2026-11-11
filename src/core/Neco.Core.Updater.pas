unit Neco.Core.Updater;

{ Atualização automática pelo GitHub Releases.

  Ciclo: Check consulta /releases/latest numa tarefa de fundo. Se a versão lá for maior,
  baixa o exe para a pasta de atualização, confere o SHA-256 (arquivo .sha256 da mesma
  release) e só então grava pending.json. Apply troca o exe: o Windows deixa renomear um
  exe em execução, então o atual vira NecoBrowser.old.exe e o novo toma o lugar dele.

  Release esperada: tag vX.Y.Z com os arquivos NecoBrowser-win64.exe, NecoBrowser-win32.exe
  e um .sha256 de cada (tools\publicar.sh gera tudo).

  Sem FMX. Winapi só no que é do Windows (versão do exe). }

interface

uses
  System.SysUtils, System.Threading;

type
  TNecoRelease = record
    Version: string; // sem o "v": 0.2.0
    ExeUrl: string;
    ShaUrl: string;
  end;

  /// Chamado na thread principal quando há versão nova baixada e conferida.
  TNecoUpdateReady = reference to procedure(const AVersion: string);

  TNecoUpdater = class
  private
    FDir: string;
    FTask: ITask;
    function PendingFile: string;
    function GetBusy: Boolean;
  public
    /// AUpdateDir: onde ficam o download e o pending.json (criada se faltar).
    constructor Create(const AUpdateDir: string);
    /// Consulta e baixa em segundo plano. Erros só vão para o rastro (NECO_TRACE).
    /// AOnReady roda na thread principal ao fim de toda consulta ('' = nada novo ou falhou).
    procedure Check(const ACurrentVersion: string; const AOnReady: TNecoUpdateReady);
    /// Versão já baixada e conferida, esperando a troca. '' = nenhuma.
    function PendingVersion: string;
    /// Troca AExePath pelo exe baixado. False = nada pendente ou não deu (o exe atual fica).
    function Apply(const AExePath: string): Boolean;
    /// Ao fechar o app: interrompe o download e espera a tarefa (até 5 s).
    /// Depois disso nenhum AOnReady é chamado.
    procedure Shutdown;
    property Busy: Boolean read GetBusy;
  end;

/// Compara versões "1.2.3" (aceita "v" na frente e partes faltando = 0).
/// <0: A menor; 0: iguais; >0: A maior.
function NecoCompareVersions(const A, B: string): Integer;

/// Lê o JSON de /releases/latest. False se faltar a tag, o exe ou o .sha256.
function NecoParseRelease(const AJson, AAssetName: string; out ARelease: TNecoRelease): Boolean;

/// O hash do arquivo .sha256 ("<hex>  nome" ou só "<hex>"), em minúsculas. '' se inválido.
function NecoParseSha256(const AText: string): string;

/// Versão do próprio exe (recurso de versão), "0.1.0.0". '0' fora do Windows.
function NecoAppVersion: string;

/// Nome do exe na release para esta compilação: NecoBrowser-win64.exe ou -win32.exe.
function NecoUpdateAssetName: string;

/// Apaga os NecoBrowser.old*.exe que sobraram de trocas anteriores (os em uso ficam).
procedure NecoCleanupOldExe(const AExePath: string);

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.Hash, System.Math,
  System.Net.HttpClient, System.Net.URLClient,
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}
  Neco.Core.Files, Neco.Core.Trace;

var
  // Ligado no Shutdown. Só há um atualizador por processo.
  GCancel: Boolean;

const
  CLatestUrl = 'https://api.github.com/repos/gustavomilena40/NecoBrowser/releases/latest';

function VersionParts(const S: string): TArray<Integer>;
var
  T, P: string;
  I, N: Integer;
begin
  Result := nil;
  T := Trim(S);
  if (T <> '') and CharInSet(T[1], ['v', 'V']) then
    Delete(T, 1, 1);
  for P in T.Split(['.']) do
  begin
    // Só os dígitos do começo: "3-beta" vale 3.
    N := 0;
    I := 1;
    while (I <= Length(P)) and CharInSet(P[I], ['0'..'9']) and (N < 100000000) do
    begin
      N := N * 10 + Ord(P[I]) - Ord('0');
      Inc(I);
    end;
    Result := Result + [N];
  end;
end;

function NecoCompareVersions(const A, B: string): Integer;
var
  PA, PB: TArray<Integer>;
  I, X, Y: Integer;
begin
  PA := VersionParts(A);
  PB := VersionParts(B);
  for I := 0 to Max(Length(PA), Length(PB)) - 1 do
  begin
    X := 0;
    Y := 0;
    if I < Length(PA) then
      X := PA[I];
    if I < Length(PB) then
      Y := PB[I];
    if X <> Y then
      Exit(Ord(X > Y) * 2 - 1);
  end;
  Result := 0;
end;

function NecoParseRelease(const AJson, AAssetName: string; out ARelease: TNecoRelease): Boolean;
var
  O, Asset: TJSONObject;
  Assets: TJSONArray;
  V: TJSONValue;
  Name: string;
begin
  ARelease := Default(TNecoRelease);
  O := NecoParseObject(AJson);
  if O = nil then
    Exit(False);
  try
    if NecoJsonBool(O, 'draft', False) or NecoJsonBool(O, 'prerelease', False) then
      Exit(False);
    ARelease.Version := NecoJsonStr(O, 'tag_name', '');
    if (ARelease.Version <> '') and CharInSet(ARelease.Version[1], ['v', 'V']) then
      Delete(ARelease.Version, 1, 1);
    if O.TryGetValue<TJSONArray>('assets', Assets) then
      for V in Assets do
        if V is TJSONObject then
        begin
          Asset := TJSONObject(V);
          Name := NecoJsonStr(Asset, 'name', '');
          if SameText(Name, AAssetName) then
            ARelease.ExeUrl := NecoJsonStr(Asset, 'browser_download_url', '')
          else if SameText(Name, AAssetName + '.sha256') then
            ARelease.ShaUrl := NecoJsonStr(Asset, 'browser_download_url', '');
        end;
  finally
    O.Free;
  end;
  // Sem o .sha256 não baixa: é o que garante que o arquivo chegou inteiro.
  Result := (ARelease.Version <> '') and (ARelease.ExeUrl <> '') and (ARelease.ShaUrl <> '');
end;

function NecoParseSha256(const AText: string): string;
var
  I: Integer;
begin
  Result := LowerCase(Trim(AText));
  I := 1;
  while (I <= Length(Result)) and CharInSet(Result[I], ['0'..'9', 'a'..'f']) do
    Inc(I);
  Result := Copy(Result, 1, I - 1);
  if Length(Result) <> 64 then
    Result := '';
end;

function NecoAppVersion: string;
{$IFDEF MSWINDOWS}
var
  Arq: string;
  Size, Dummy, Len: DWORD;
  Buf: TBytes;
  Info: PVSFixedFileInfo;
begin
  Result := '0';
  Arq := ParamStr(0);
  Size := GetFileVersionInfoSize(PChar(Arq), Dummy);
  if Size = 0 then
    Exit;
  SetLength(Buf, Size);
  if not GetFileVersionInfo(PChar(Arq), 0, Size, @Buf[0]) then
    Exit;
  if not VerQueryValue(@Buf[0], '\', Pointer(Info), Len) or (Len < SizeOf(TVSFixedFileInfo)) then
    Exit;
  Result := Format('%d.%d.%d.%d', [HiWord(Info.dwFileVersionMS), LoWord(Info.dwFileVersionMS),
    HiWord(Info.dwFileVersionLS), LoWord(Info.dwFileVersionLS)]);
end;
{$ELSE}
begin
  Result := '0';
end;
{$ENDIF}

function NecoUpdateAssetName: string;
begin
  {$IFDEF CPUX64}
  Result := 'NecoBrowser-win64.exe';
  {$ELSE}
  Result := 'NecoBrowser-win32.exe';
  {$ENDIF}
end;

function OldExeName(const AExePath: string): string;
begin
  Result := ChangeFileExt(AExePath, '') + '.old.exe';
end;

procedure NecoCleanupOldExe(const AExePath: string);
var
  F: string;
begin
  try
    for F in TDirectory.GetFiles(ExtractFileDir(AExePath),
      ChangeFileExt(ExtractFileName(AExePath), '') + '.old*.exe') do
      System.SysUtils.DeleteFile(F); // em uso (outra janela antiga aberta): fica para a próxima
  except
    // pasta sem acesso: nada a limpar
  end;
end;

{ TNecoUpdater }

constructor TNecoUpdater.Create(const AUpdateDir: string);
begin
  inherited Create;
  FDir := AUpdateDir;
end;

function TNecoUpdater.PendingFile: string;
begin
  Result := TPath.Combine(FDir, 'pending.json');
end;

function TNecoUpdater.GetBusy: Boolean;
begin
  Result := (FTask <> nil) and not (FTask.Status in [TTaskStatus.Completed,
    TTaskStatus.Canceled, TTaskStatus.Exception]);
end;

procedure TNecoUpdater.Shutdown;
begin
  GCancel := True;
  if Busy then
    try
      FTask.Wait(5000);
    except
      // a tarefa trata os próprios erros; aqui só não pode travar o fechamento
    end;
end;

function TNecoUpdater.PendingVersion: string;
var
  O: TJSONObject;
begin
  Result := '';
  O := NecoParseObject(NecoLoadText(PendingFile));
  if O = nil then
    Exit;
  try
    if FileExists(TPath.Combine(FDir, NecoJsonStr(O, 'file', ''))) then
      Result := NecoJsonStr(O, 'version', '');
  finally
    O.Free;
  end;
end;

procedure TNecoUpdater.Check(const ACurrentVersion: string; const AOnReady: TNecoUpdateReady);
var
  Dir, Url, Asset, Pending: string;
begin
  if Busy or GCancel then
    Exit;
  // A tarefa só usa cópias: nada dela aponta para este objeto.
  Dir := FDir;
  Asset := NecoUpdateAssetName;
  Pending := PendingVersion;
  Url := GetEnvironmentVariable('NECO_UPDATE_URL'); // teste sem publicar release
  if Url = '' then
    Url := CLatestUrl;
  FTask := TTask.Run(
    procedure
    var
      Http: THTTPClient;
      Resp: IHTTPResponse;
      Rel: TNecoRelease;
      Sha, Part, Final, Ready: string;
      FS: TFileStream;
      O: TJSONObject;
    begin
      Ready := '';
      try
        Http := THTTPClient.Create;
        try
          Http.UserAgent := 'NecoBrowser/' + ACurrentVersion;
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
          if not NecoParseRelease(Resp.ContentAsString(TEncoding.UTF8), Asset, Rel) then
            raise Exception.Create('release sem ' + Asset + ' e .sha256');
          if NecoCompareVersions(Rel.Version, ACurrentVersion) <= 0 then
          begin
            NecoTrace('atualizacao: ja na mais nova (' + ACurrentVersion + ')');
            Exit;
          end;
          if (Pending <> '') and (NecoCompareVersions(Rel.Version, Pending) <= 0) then
          begin
            Ready := Pending; // já baixada numa vez anterior
            Exit;
          end;

          Resp := Http.Get(Rel.ShaUrl);
          if Resp.StatusCode <> 200 then
            raise Exception.CreateFmt('.sha256 devolveu %d', [Resp.StatusCode]);
          Sha := NecoParseSha256(Resp.ContentAsString(TEncoding.UTF8));
          if Sha = '' then
            raise Exception.Create('.sha256 invalido');

          ForceDirectories(Dir);
          Final := 'NecoBrowser-' + Rel.Version + '.exe';
          Part := TPath.Combine(Dir, Final + '.part');
          FS := TFileStream.Create(Part, fmCreate);
          try
            Resp := Http.Get(Rel.ExeUrl, FS);
          finally
            FS.Free;
          end;
          if Resp.StatusCode <> 200 then
            raise Exception.CreateFmt('download devolveu %d', [Resp.StatusCode]);
          if not SameText(THashSHA2.GetHashStringFromFile(Part, THashSHA2.TSHA2Version.SHA256), Sha) then
          begin
            System.SysUtils.DeleteFile(Part);
            raise Exception.Create('hash nao confere: download descartado');
          end;
          if FileExists(TPath.Combine(Dir, Final)) then
            System.SysUtils.DeleteFile(TPath.Combine(Dir, Final));
          if not RenameFile(Part, TPath.Combine(Dir, Final)) then
            raise Exception.Create('nao renomeou o download');

          O := TJSONObject.Create;
          try
            O.AddPair('version', Rel.Version);
            O.AddPair('file', Final);
            NecoSaveTextAtomic(TPath.Combine(Dir, 'pending.json'), O.Format(2));
          finally
            O.Free;
          end;
          NecoTrace('atualizacao: ' + Rel.Version + ' baixada e conferida');
          Ready := Rel.Version;
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
          NecoTrace('atualizacao falhou: ' + E.Message);
      end;
    end);
end;

function TNecoUpdater.Apply(const AExePath: string): Boolean;
var
  O: TJSONObject;
  NewExe, Old: string;
  I: Integer;
begin
  Result := False;
  O := NecoParseObject(NecoLoadText(PendingFile));
  if O = nil then
    Exit;
  try
    NewExe := TPath.Combine(FDir, NecoJsonStr(O, 'file', ''));
  finally
    O.Free;
  end;
  if not FileExists(NewExe) then
  begin
    System.SysUtils.DeleteFile(PendingFile);
    Exit;
  end;
  // O .old.exe de uma troca anterior pode estar em uso (janela antiga ainda aberta).
  Old := OldExeName(AExePath);
  I := 1;
  while FileExists(Old) and not System.SysUtils.DeleteFile(Old) do
  begin
    Old := ChangeFileExt(AExePath, '') + Format('.old%d.exe', [I]);
    Inc(I);
    if I > 20 then
      Exit;
  end;
  if not RenameFile(AExePath, Old) then
  begin
    NecoTrace('atualizacao: sem permissao para trocar ' + AExePath);
    Exit;
  end;
  try
    // Copiar (não mover): a pasta de atualização pode estar em outro disco.
    TFile.Copy(NewExe, AExePath, False);
  except
    on E: Exception do
    begin
      NecoTrace('atualizacao: copia falhou, exe antigo de volta: ' + E.Message);
      RenameFile(Old, AExePath);
      Exit;
    end;
  end;
  System.SysUtils.DeleteFile(NewExe);
  System.SysUtils.DeleteFile(PendingFile);
  NecoTrace('atualizacao aplicada em ' + AExePath);
  Result := True;
end;

end.
