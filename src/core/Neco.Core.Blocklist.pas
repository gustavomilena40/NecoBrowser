unit Neco.Core.Blocklist;

{ Lista de hosts bloqueados (anúncios e rastreadores).
  Aceita o formato hosts ("0.0.0.0 ads.exemplo.com") e lista simples de domínios.
  A consulta é O(número de rótulos do host): um THashSet e a subida pelos domínios-pai.
  Sem FMX e sem Winapi: compila em Windows e Android. }

interface

uses
  System.Generics.Collections;

type
  TNecoBlocklist = class
  private
    FHosts: THashSet<string>;
    function GetCount: Integer;
    class function IsAddress(const AToken: string): Boolean; static;
    class function IsIgnoredName(const AHost: string): Boolean; static;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure Add(const AHost: string);
    /// Interpreta uma linha no formato hosts ou de lista de domínios.
    procedure AddLine(const ALine: string);
    /// Devolve quantos hosts a lista tem depois da carga. Arquivo inexistente: 0.
    function LoadFromFile(const AFileName: string): Integer;
    /// True se o host ou algum domínio-pai dele (sem chegar ao TLD) está na lista.
    function IsBlocked(const AHost: string): Boolean;
    function IsUrlBlocked(const AUrl: string): Boolean;
    property Count: Integer read GetCount;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Neco.Core.Url;

{ TNecoBlocklist }

constructor TNecoBlocklist.Create;
begin
  inherited Create;
  FHosts := THashSet<string>.Create;
end;

destructor TNecoBlocklist.Destroy;
begin
  FHosts.Free;
  inherited;
end;

procedure TNecoBlocklist.Clear;
begin
  FHosts.Clear;
end;

function TNecoBlocklist.GetCount: Integer;
begin
  Result := FHosts.Count;
end;

class function TNecoBlocklist.IsAddress(const AToken: string): Boolean;
begin
  Result := (AToken = '0.0.0.0') or (AToken = '127.0.0.1') or (AToken = '::') or
    (AToken = '::1') or (AToken = '0') or (AToken = '::0');
end;

class function TNecoBlocklist.IsIgnoredName(const AHost: string): Boolean;
begin
  // Entradas de cabeçalho comuns nas listas hosts: nunca bloquear.
  Result := (AHost = 'localhost') or (AHost = 'localhost.localdomain') or (AHost = 'local') or
    (AHost = 'broadcasthost') or (AHost = '0.0.0.0') or (AHost = 'ip6-localhost') or
    (AHost = 'ip6-loopback') or AHost.StartsWith('ip6-');
end;

procedure TNecoBlocklist.Add(const AHost: string);
var
  H: string;
begin
  H := LowerCase(Trim(AHost));
  if (H <> '') and (H[Length(H)] = '.') then
    SetLength(H, Length(H) - 1);
  if (H = '') or (Pos('.', H) = 0) or IsIgnoredName(H) then
    Exit;
  FHosts.Add(H);
end;

procedure TNecoBlocklist.AddLine(const ALine: string);
var
  L: string;
  P, I: Integer;
  Tokens: TArray<string>;
begin
  L := ALine;
  P := Pos('#', L);
  if P > 0 then
    SetLength(L, P - 1);
  L := Trim(L);
  if L = '' then
    Exit;
  Tokens := L.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  if Length(Tokens) = 0 then
    Exit;
  if IsAddress(Tokens[0]) then
  begin
    for I := 1 to High(Tokens) do
      Add(Tokens[I]);
  end
  else if Length(Tokens) = 1 then
    Add(Tokens[0]);
  // Linha com IP real (ex.: "1.2.3.4 site") é redirecionamento, não bloqueio: ignorada.
end;

function TNecoBlocklist.LoadFromFile(const AFileName: string): Integer;
var
  Reader: TStreamReader;
begin
  FHosts.Clear;
  if TFile.Exists(AFileName) then
  begin
    Reader := TStreamReader.Create(AFileName, TEncoding.UTF8, True);
    try
      while not Reader.EndOfStream do
        AddLine(Reader.ReadLine);
    finally
      Reader.Free;
    end;
  end;
  Result := FHosts.Count;
end;

function TNecoBlocklist.IsBlocked(const AHost: string): Boolean;
var
  H: string;
  P: Integer;
begin
  if (AHost = '') or (FHosts.Count = 0) then
    Exit(False);
  H := AHost;
  while True do
  begin
    if FHosts.Contains(H) then
      Exit(True);
    P := Pos('.', H);
    if P = 0 then
      Exit(False);
    H := Copy(H, P + 1, MaxInt);
    // Não testa o TLD sozinho ("com", "br").
    if Pos('.', H) = 0 then
      Exit(False);
  end;
end;

function TNecoBlocklist.IsUrlBlocked(const AUrl: string): Boolean;
begin
  Result := IsBlocked(NecoExtractHost(AUrl));
end;

end.
