unit Neco.Core.Url;

{ Texto digitado na barra de endereço -> URL ou busca.
  Sem FMX e sem Winapi: compila em Windows e Android. }

interface

type
  TNecoSearchEngine = (seDuckDuckGo, seGoogle);

/// Converte o que o usuário digitou numa URL navegável.
/// Endereço (com ou sem esquema) vira URL; o resto vira busca. Texto vazio devolve ''.
function NecoInputToUrl(const AText: string; AEngine: TNecoSearchEngine): string;

/// True se o texto, sem espaços, parece um endereço (domínio, IP, localhost ou esquema).
function NecoLooksLikeUrl(const AText: string): Boolean;

/// URL de busca do motor escolhido.
function NecoSearchUrl(const AQuery: string; AEngine: TNecoSearchEngine): string;

/// Host em minúsculas, sem porta, usuário ou ponto final. Não levanta exceção.
/// Roda centenas de vezes por página no bloqueador: sem TURI, sem regex.
function NecoExtractHost(const AUrl: string): string;

/// Codificação de componente de URL (UTF-8, espaço vira '+').
function NecoUrlEncode(const AText: string): string;

function NecoSearchEngineId(AEngine: TNecoSearchEngine): string;
function NecoSearchEngineFromId(const AId: string): TNecoSearchEngine;

implementation

uses
  System.SysUtils;

const
  // Esquemas aceitos como estão, sem passar por busca.
  CSchemes: array[0..8] of string = ('http://', 'https://', 'file:', 'about:', 'edge://',
    'data:', 'view-source:', 'blob:', 'javascript:');

function HasKnownScheme(const AText: string): Boolean;
var
  S: string;
begin
  for S in CSchemes do
    if SameText(Copy(AText, 1, Length(S)), S) then
      Exit(True);
  Result := False;
end;

function HasWhitespace(const AText: string): Boolean;
var
  C: Char;
begin
  for C in AText do
    if (C = ' ') or (C = #9) or (C = #10) or (C = #13) then
      Exit(True);
  Result := False;
end;

function IsIPv4(const AHost: string): Boolean;
var
  Parts: TArray<string>;
  S: string;
  N: Integer;
begin
  Parts := AHost.Split(['.']);
  if Length(Parts) <> 4 then
    Exit(False);
  for S in Parts do
  begin
    if (S = '') or (Length(S) > 3) or not TryStrToInt(S, N) or (N < 0) or (N > 255) then
      Exit(False);
    if S.IndexOfAny(['+', '-']) >= 0 then
      Exit(False);
  end;
  Result := True;
end;

function IsDomainLabel(const ALabel: string): Boolean;
var
  C: Char;
begin
  if (ALabel = '') or (ALabel[1] = '-') or (ALabel[Length(ALabel)] = '-') then
    Exit(False);
  for C in ALabel do
    if not (CharInSet(C, ['a'..'z', '0'..'9', '-', '_']) or (Ord(C) > 127)) then
      Exit(False);
  Result := True;
end;

function IsAllDigits(const S: string): Boolean;
var
  C: Char;
begin
  for C in S do
    if not CharInSet(C, ['0'..'9']) then
      Exit(False);
  Result := S <> '';
end;

function NecoExtractHost(const AUrl: string): string;
var
  P, S, E, I: Integer;
begin
  P := Pos('://', AUrl);
  if P > 0 then
    S := P + 3
  else
    S := 1;
  E := Length(AUrl) + 1;
  for I := S to Length(AUrl) do
    if CharInSet(AUrl[I], ['/', '?', '#', '\']) then
    begin
      E := I;
      Break;
    end;
  Result := Copy(AUrl, S, E - S);

  I := LastDelimiter('@', Result);
  if I > 0 then
    Delete(Result, 1, I);

  if (Result <> '') and (Result[1] = '[') then
  begin
    // IPv6 literal: [::1]:8080
    I := Pos(']', Result);
    if I > 0 then
      Result := Copy(Result, 2, I - 2);
    Exit(LowerCase(Result));
  end;

  I := Pos(':', Result);
  if I > 0 then
    SetLength(Result, I - 1);
  Result := LowerCase(Result);
  if (Result <> '') and (Result[Length(Result)] = '.') then
    SetLength(Result, Length(Result) - 1);
end;

function NecoLooksLikeUrl(const AText: string): Boolean;
var
  T, Host: string;
  Labels: TArray<string>;
  L: string;
begin
  T := Trim(AText);
  if (T = '') or HasWhitespace(T) then
    Exit(False);
  if HasKnownScheme(T) then
    Exit(True);

  Host := NecoExtractHost('http://' + T);
  if Host = 'localhost' then
    Exit(True);
  if IsIPv4(Host) then
    Exit(True);

  Labels := Host.Split(['.']);
  if Length(Labels) < 2 then
    Exit(False);
  for L in Labels do
    if not IsDomainLabel(L) then
      Exit(False);
  // Último rótulo (TLD): ao menos 2 caracteres e não só dígitos.
  L := Labels[High(Labels)];
  Result := (Length(L) >= 2) and not IsAllDigits(L);
end;

function NecoUrlEncode(const AText: string): string;
const
  Hex: array[0..15] of Char = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'A', 'B', 'C', 'D', 'E', 'F');
var
  Bytes: TBytes;
  B: Byte;
  SB: TStringBuilder;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText);
  SB := TStringBuilder.Create(Length(Bytes) * 3);
  try
    for B in Bytes do
      if B = Ord(' ') then
        SB.Append('+')
      else if (B in [Ord('A')..Ord('Z'), Ord('a')..Ord('z'), Ord('0')..Ord('9')]) or
        (B = Ord('-')) or (B = Ord('_')) or (B = Ord('.')) or (B = Ord('~')) then
        SB.Append(Char(B))
      else
        SB.Append('%').Append(Hex[B shr 4]).Append(Hex[B and $F]);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function NecoSearchUrl(const AQuery: string; AEngine: TNecoSearchEngine): string;
begin
  case AEngine of
    seGoogle:
      Result := 'https://www.google.com/search?q=' + NecoUrlEncode(AQuery);
  else
    Result := 'https://duckduckgo.com/?q=' + NecoUrlEncode(AQuery);
  end;
end;

function NecoInputToUrl(const AText: string; AEngine: TNecoSearchEngine): string;
var
  T, Host: string;
begin
  T := Trim(AText);
  if T = '' then
    Exit('');
  if HasKnownScheme(T) then
    Exit(T);
  if NecoLooksLikeUrl(T) then
  begin
    Host := NecoExtractHost('http://' + T);
    // Rede local quase nunca tem certificado: http direto.
    if (Host = 'localhost') or IsIPv4(Host) then
      Exit('http://' + T);
    Exit('https://' + T);
  end;
  Result := NecoSearchUrl(T, AEngine);
end;

function NecoSearchEngineId(AEngine: TNecoSearchEngine): string;
begin
  case AEngine of
    seGoogle:
      Result := 'google';
  else
    Result := 'duckduckgo';
  end;
end;

function NecoSearchEngineFromId(const AId: string): TNecoSearchEngine;
begin
  if SameText(AId, 'google') then
    Result := seGoogle
  else
    Result := seDuckDuckGo;
end;

end.
