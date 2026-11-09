unit Neco.Core.Favicons;

{ Ícones dos sites (favicons) guardados em disco, um PNG por site (host), para a barra
  e o painel de favoritos. Quem captura o ícone é o motor; aqui só se grava e se acha
  o arquivo. Sem FMX: os testes do núcleo cobrem. }

interface

uses
  System.SysUtils;

/// Arquivo do ícone daquele endereço: <pasta>\<host>.png. Vazio se o endereço não tem
/// host (file:, about:, data:...).
function NecoFaviconFile(const ADir, AUrl: string): string;

/// Grava o PNG do site. True se o arquivo mudou (novo ou diferente do que estava);
/// False se já era igual, se veio vazio ou se o endereço não tem host.
function NecoSaveFavicon(const ADir, AUrl: string; const APng: TBytes): Boolean;

implementation

uses
  System.IOUtils, Neco.Core.Url;

function NecoFaviconFile(const ADir, AUrl: string): string;
var
  H: string;
  I: Integer;
begin
  Result := '';
  if not (AUrl.StartsWith('http://', True) or AUrl.StartsWith('https://', True)) then
    Exit;
  H := NecoExtractHost(AUrl);
  if H = '' then
    Exit;
  // Host já vem em minúsculas; troca o que o Windows não aceita em nome de arquivo
  // (IPv6 tem ':' e colchetes).
  for I := 1 to Length(H) do
    if not CharInSet(H[I], ['a'..'z', '0'..'9', '.', '-', '_']) then
      H[I] := '_';
  Result := TPath.Combine(ADir, H + '.png');
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and
    ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function NecoSaveFavicon(const ADir, AUrl: string; const APng: TBytes): Boolean;
var
  F, Tmp: string;
begin
  Result := False;
  F := NecoFaviconFile(ADir, AUrl);
  if (F = '') or (Length(APng) = 0) then
    Exit;
  if TFile.Exists(F) and SameBytes(TFile.ReadAllBytes(F), APng) then
    Exit;
  ForceDirectories(ADir);
  // Grava ao lado e troca: quem lê nunca pega um PNG pela metade.
  Tmp := F + '.tmp';
  TFile.WriteAllBytes(Tmp, APng);
  if TFile.Exists(F) then
    TFile.Delete(F);
  TFile.Move(Tmp, F);
  Result := True;
end;

end.
