unit Neco.Core.Files;

{ Leitura e gravação de arquivos de dados (JSON) do NecoBrowser.
  Sem FMX e sem Winapi: compila em Windows e Android. }

interface

uses
  System.JSON;

/// Grava o texto em UTF-8 de forma atômica: escreve num .tmp e troca pelo arquivo.
/// Um app que morre no meio da gravação não deixa o JSON pela metade.
procedure NecoSaveTextAtomic(const AFileName, AText: string);

/// Lê o arquivo inteiro em UTF-8. Arquivo inexistente devolve ''.
function NecoLoadText(const AFileName: string): string;

/// Faz o parse; devolve nil se o texto for vazio, inválido ou não for um objeto.
/// O chamador é dono do resultado.
function NecoParseObject(const AText: string): TJSONObject;

function NecoJsonStr(AObj: TJSONObject; const AName, ADefault: string): string;
function NecoJsonBool(AObj: TJSONObject; const AName: string; ADefault: Boolean): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils;

procedure NecoSaveTextAtomic(const AFileName, AText: string);
var
  Tmp: string;
begin
  ForceDirectories(ExtractFileDir(AFileName));
  Tmp := AFileName + '.tmp';
  TFile.WriteAllText(Tmp, AText, TEncoding.UTF8);
  if TFile.Exists(AFileName) then
    TFile.Delete(AFileName);
  TFile.Move(Tmp, AFileName);
end;

function NecoLoadText(const AFileName: string): string;
var
  Reader: TStreamReader;
begin
  if not TFile.Exists(AFileName) then
    Exit('');
  // TStreamReader lê até o EOF em blocos (regra 4.8: não confiar no tamanho do arquivo).
  Reader := TStreamReader.Create(AFileName, TEncoding.UTF8, True);
  try
    Result := Reader.ReadToEnd;
  finally
    Reader.Free;
  end;
end;

function NecoParseObject(const AText: string): TJSONObject;
var
  V: TJSONValue;
begin
  Result := nil;
  if Trim(AText) = '' then
    Exit;
  V := TJSONObject.ParseJSONValue(AText);
  if V is TJSONObject then
    Result := TJSONObject(V)
  else
    V.Free;
end;

function NecoJsonStr(AObj: TJSONObject; const AName, ADefault: string): string;
var
  V: TJSONValue;
begin
  V := AObj.GetValue(AName);
  if (V <> nil) and not (V is TJSONNull) then
    Result := V.Value
  else
    Result := ADefault;
end;

function NecoJsonBool(AObj: TJSONObject; const AName: string; ADefault: Boolean): Boolean;
var
  V: TJSONValue;
begin
  V := AObj.GetValue(AName);
  if V is TJSONBool then
    Result := TJSONBool(V).AsBoolean
  else
    Result := ADefault;
end;

end.
