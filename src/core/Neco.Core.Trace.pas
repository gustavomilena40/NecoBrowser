unit Neco.Core.Trace;

{ Rastro de tempos para diagnóstico. Desligado por padrão: só grava se a variável de
  ambiente NECO_TRACE apontar para um arquivo. Cada linha: milissegundos desde o início
  do processo, TAB, texto.
  Sem FMX e sem Winapi: compila em Windows e Android. }

interface

function NecoTraceOn: Boolean;
procedure NecoTrace(const AText: string);
/// Milissegundos desde o início do processo (relógio monotônico).
function NecoTraceMs: Double;

implementation

uses
  System.SysUtils, System.Classes, System.Diagnostics;

var
  GFile: string;
  GWatch: TStopwatch;

function NecoTraceOn: Boolean;
begin
  Result := GFile <> '';
end;

function NecoTraceMs: Double;
begin
  Result := GWatch.Elapsed.TotalMilliseconds;
end;

procedure NecoTrace(const AText: string);
var
  F: TStreamWriter;
begin
  if GFile = '' then
    Exit;
  try
    F := TStreamWriter.Create(GFile, True, TEncoding.UTF8);
    try
      F.WriteLine(FormatFloat('0.0', NecoTraceMs) + #9 + AText);
    finally
      F.Free;
    end;
  except
    // Diagnóstico nunca derruba o app.
  end;
end;

initialization
  GWatch := TStopwatch.StartNew;
  GFile := GetEnvironmentVariable('NECO_TRACE');

end.
