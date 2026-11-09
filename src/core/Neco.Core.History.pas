unit Neco.Core.History;

{ Histórico simples em JSON: as últimas páginas visitadas, mais recente no fim.
  Sem FMX e sem Winapi: compila em Windows e Android. }

interface

uses
  System.Generics.Collections;

type
  TNecoHistoryEntry = record
    Title: string;
    Url: string;
    Visited: TDateTime;
  end;

  TNecoHistory = class
  private
    FItems: TList<TNecoHistoryEntry>;
    FMaxEntries: Integer;
    FDirty: Boolean;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TNecoHistoryEntry;
  public
    constructor Create(AMaxEntries: Integer = 5000);
    destructor Destroy; override;
    /// Registra a visita. Visitar de novo a última URL só atualiza título e hora.
    /// URLs internas (about:, data:, edge:) não entram.
    procedure Add(const AUrl, ATitle: string);
    /// Atualiza o título da visita mais recente daquela URL.
    procedure UpdateTitle(const AUrl, ATitle: string);
    procedure Clear;
    function ToJson: string;
    function FromJson(const AJson: string): Boolean;
    procedure LoadFromFile(const AFileName: string);
    /// Grava só se houve mudança desde a última gravação ou carga.
    procedure SaveToFile(const AFileName: string);
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TNecoHistoryEntry read GetItem; default;
    property Dirty: Boolean read FDirty;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.DateUtils, Neco.Core.Files;

{ TNecoHistory }

constructor TNecoHistory.Create(AMaxEntries: Integer);
begin
  inherited Create;
  FMaxEntries := AMaxEntries;
  FItems := TList<TNecoHistoryEntry>.Create;
end;

destructor TNecoHistory.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TNecoHistory.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TNecoHistory.GetItem(AIndex: Integer): TNecoHistoryEntry;
begin
  Result := FItems[AIndex];
end;

procedure TNecoHistory.Add(const AUrl, ATitle: string);
var
  E: TNecoHistoryEntry;
  L: string;
begin
  L := LowerCase(AUrl);
  if (L = '') or L.StartsWith('about:') or L.StartsWith('data:') or L.StartsWith('edge:') then
    Exit;
  if (FItems.Count > 0) and (FItems.Last.Url = AUrl) then
  begin
    E := FItems.Last;
    if ATitle <> '' then
      E.Title := ATitle;
    E.Visited := Now;
    FItems[FItems.Count - 1] := E;
  end
  else
  begin
    E.Url := AUrl;
    E.Title := ATitle;
    E.Visited := Now;
    FItems.Add(E);
    while FItems.Count > FMaxEntries do
      FItems.Delete(0);
  end;
  FDirty := True;
end;

procedure TNecoHistory.UpdateTitle(const AUrl, ATitle: string);
var
  I: Integer;
  E: TNecoHistoryEntry;
begin
  if ATitle = '' then
    Exit;
  for I := FItems.Count - 1 downto 0 do
    if FItems[I].Url = AUrl then
    begin
      E := FItems[I];
      if E.Title <> ATitle then
      begin
        E.Title := ATitle;
        FItems[I] := E;
        FDirty := True;
      end;
      Exit;
    end;
end;

procedure TNecoHistory.Clear;
begin
  FItems.Clear;
  FDirty := True;
end;

function TNecoHistory.ToJson: string;
var
  Root, O: TJSONObject;
  Arr: TJSONArray;
  E: TNecoHistoryEntry;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(1));
    Arr := TJSONArray.Create;
    Root.AddPair('history', Arr);
    for E in FItems do
    begin
      O := TJSONObject.Create;
      Arr.AddElement(O);
      O.AddPair('title', E.Title);
      O.AddPair('url', E.Url);
      O.AddPair('visited', DateToISO8601(E.Visited, False));
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function TNecoHistory.FromJson(const AJson: string): Boolean;
var
  Root, O: TJSONObject;
  Arr: TJSONArray;
  V: TJSONValue;
  E: TNecoHistoryEntry;
begin
  FItems.Clear;
  Result := False;
  Root := NecoParseObject(AJson);
  if Root <> nil then
  try
    V := Root.GetValue('history');
    if V is TJSONArray then
    begin
      Arr := TJSONArray(V);
      for V in Arr do
        if V is TJSONObject then
        begin
          O := TJSONObject(V);
          E.Url := NecoJsonStr(O, 'url', '');
          if E.Url = '' then
            Continue;
          E.Title := NecoJsonStr(O, 'title', '');
          if not TryISO8601ToDate(NecoJsonStr(O, 'visited', ''), E.Visited, False) then
            E.Visited := 0;
          FItems.Add(E);
        end;
      while FItems.Count > FMaxEntries do
        FItems.Delete(0);
      Result := True;
    end;
  finally
    Root.Free;
  end;
  FDirty := False;
end;

procedure TNecoHistory.LoadFromFile(const AFileName: string);
begin
  FromJson(NecoLoadText(AFileName));
end;

procedure TNecoHistory.SaveToFile(const AFileName: string);
begin
  if not FDirty then
    Exit;
  NecoSaveTextAtomic(AFileName, ToJson);
  FDirty := False;
end;

end.
