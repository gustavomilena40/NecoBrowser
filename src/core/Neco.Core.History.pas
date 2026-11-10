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

  /// O que foi digitado na barra e mandado buscar (para sugerir de novo).
  TNecoTypedEntry = record
    Text: string;
    Count: Integer;
    Last: TDateTime;
  end;

  TNecoSuggestionKind = (nskSearch, nskPage);
  /// Sugestão para a barra de endereço.
  TNecoSuggestion = record
    Kind: TNecoSuggestionKind;
    /// O que vai para a barra (o texto da busca ou a URL da página).
    Text: string;
    /// Título da página (vazio nas buscas).
    Detail: string;
  end;

  TNecoHistory = class
  private
    FItems: TList<TNecoHistoryEntry>;
    FTyped: TList<TNecoTypedEntry>;
    FMaxEntries: Integer;
    FDirty: Boolean;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TNecoHistoryEntry;
    function GetTypedCount: Integer;
    function GetTyped(AIndex: Integer): TNecoTypedEntry;
  public
    constructor Create(AMaxEntries: Integer = 5000);
    destructor Destroy; override;
    /// Registra a visita. Visitar de novo a última URL só atualiza título e hora.
    /// URLs internas (about:, data:, edge:) não entram.
    procedure Add(const AUrl, ATitle: string);
    /// Atualiza o título da visita mais recente daquela URL.
    procedure UpdateTitle(const AUrl, ATitle: string);
    /// Registra uma busca digitada na barra (repetir a mesma, sem diferenciar maiúsculas,
    /// só conta mais uma vez e atualiza a hora). Guarda as 500 mais recentes.
    procedure AddTyped(const AText: string);
    /// Sugestões para o texto digitado, no máximo AMax: primeiro as buscas que começam
    /// com o texto (as mais repetidas e recentes antes), depois as páginas visitadas cujo
    /// endereço começa com o texto ou cujo título o contém. Sem diferenciar maiúsculas
    /// nem acentos. Páginas de resultado de busca não entram (a busca já aparece).
    function Suggest(const AText: string; AMax: Integer = 8): TArray<TNecoSuggestion>;
    /// Apaga as visitas e as buscas digitadas.
    procedure Clear;
    function ToJson: string;
    function FromJson(const AJson: string): Boolean;
    procedure LoadFromFile(const AFileName: string);
    /// Grava só se houve mudança desde a última gravação ou carga.
    procedure SaveToFile(const AFileName: string);
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TNecoHistoryEntry read GetItem; default;
    property TypedCount: Integer read GetTypedCount;
    property Typed[AIndex: Integer]: TNecoTypedEntry read GetTyped;
    property Dirty: Boolean read FDirty;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.DateUtils, System.Generics.Defaults,
  Neco.Core.Files, Neco.Core.Url;

const
  CMaxTyped = 500;

/// Minúsculas e sem acento, para comparar o que foi digitado.
function Fold(const S: string): string;
const
  De = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  Para = 'aaaaaeeeeiiiiooooouuuucn';
var
  I, P: Integer;
begin
  Result := Trim(S).ToLower; // LowerCase só mexe em A..Z
  for I := 1 to Length(Result) do
  begin
    P := Pos(Result[I], De);
    if P > 0 then
      Result[I] := Para[P];
  end;
end;

/// Endereço sem esquema e sem "www.", para casar com o que se digita ("g1.glo...").
function BareUrl(const AUrl: string): string;
var
  P: Integer;
begin
  Result := LowerCase(AUrl);
  P := Pos('://', Result);
  if P > 0 then
    Delete(Result, 1, P + 2);
  if Result.StartsWith('www.') then
    Delete(Result, 1, 4);
end;

/// Página de resultado de algum dos buscadores (a busca já aparece como sugestão).
function IsSearchPage(const AUrl: string): Boolean;
var
  E: TNecoSearchEngine;
begin
  for E := Low(TNecoSearchEngine) to High(TNecoSearchEngine) do
    if AUrl.StartsWith(NecoSearchUrl('', E), True) then
      Exit(True);
  Result := False;
end;

{ TNecoHistory }

constructor TNecoHistory.Create(AMaxEntries: Integer);
begin
  inherited Create;
  FMaxEntries := AMaxEntries;
  FItems := TList<TNecoHistoryEntry>.Create;
  FTyped := TList<TNecoTypedEntry>.Create;
end;

destructor TNecoHistory.Destroy;
begin
  FTyped.Free;
  FItems.Free;
  inherited;
end;

function TNecoHistory.GetTypedCount: Integer;
begin
  Result := FTyped.Count;
end;

function TNecoHistory.GetTyped(AIndex: Integer): TNecoTypedEntry;
begin
  Result := FTyped[AIndex];
end;

procedure TNecoHistory.AddTyped(const AText: string);
var
  T, K: string;
  I, Old: Integer;
  E: TNecoTypedEntry;
begin
  T := Trim(AText);
  if T = '' then
    Exit;
  K := Fold(T);
  for I := 0 to FTyped.Count - 1 do
    if Fold(FTyped[I].Text) = K then
    begin
      E := FTyped[I];
      E.Text := T; // fica a grafia mais recente
      Inc(E.Count);
      E.Last := Now;
      FTyped[I] := E;
      FDirty := True;
      Exit;
    end;
  E.Text := T;
  E.Count := 1;
  E.Last := Now;
  FTyped.Add(E);
  // Passou do limite: sai a busca usada há mais tempo.
  while FTyped.Count > CMaxTyped do
  begin
    Old := 0;
    for I := 1 to FTyped.Count - 1 do
      if FTyped[I].Last < FTyped[Old].Last then
        Old := I;
    FTyped.Delete(Old);
  end;
  FDirty := True;
end;

function TNecoHistory.Suggest(const AText: string; AMax: Integer): TArray<TNecoSuggestion>;
var
  K, U: string;
  Found: TList<TNecoTypedEntry>;
  Seen: TList<string>;
  E: TNecoTypedEntry;
  I: Integer;
  S: TNecoSuggestion;
  N: Integer;
begin
  Result := nil;
  K := Fold(AText);
  if (K = '') or (AMax <= 0) then
    Exit;
  SetLength(Result, AMax);
  N := 0;

  // Buscas digitadas que começam com o texto; as mais usadas e recentes primeiro.
  Found := TList<TNecoTypedEntry>.Create;
  try
    for E in FTyped do
      if Fold(E.Text).StartsWith(K) then
        Found.Add(E);
    Found.Sort(TComparer<TNecoTypedEntry>.Construct(
      function(const A, B: TNecoTypedEntry): Integer
      begin
        Result := B.Count - A.Count;
        if Result = 0 then
          if A.Last > B.Last then
            Result := -1
          else if A.Last < B.Last then
            Result := 1;
      end));
    for E in Found do
    begin
      if N >= AMax then
        Break;
      S.Kind := nskSearch;
      S.Text := E.Text;
      S.Detail := '';
      Result[N] := S;
      Inc(N);
    end;
  finally
    Found.Free;
  end;

  // Páginas visitadas, da mais recente para trás, sem repetir endereço.
  Seen := TList<string>.Create;
  try
    for I := FItems.Count - 1 downto 0 do
    begin
      if N >= AMax then
        Break;
      U := FItems[I].Url;
      if IsSearchPage(U) or Seen.Contains(U) then
        Continue;
      if not (BareUrl(U).StartsWith(K) or Fold(FItems[I].Title).Contains(K)) then
        Continue;
      Seen.Add(U);
      S.Kind := nskPage;
      S.Text := U;
      S.Detail := FItems[I].Title;
      Result[N] := S;
      Inc(N);
    end;
  finally
    Seen.Free;
  end;
  SetLength(Result, N);
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
  FTyped.Clear;
  FDirty := True;
end;

function TNecoHistory.ToJson: string;
var
  Root, O: TJSONObject;
  Arr: TJSONArray;
  E: TNecoHistoryEntry;
  T: TNecoTypedEntry;
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
    Arr := TJSONArray.Create;
    Root.AddPair('typed', Arr);
    for T in FTyped do
    begin
      O := TJSONObject.Create;
      Arr.AddElement(O);
      O.AddPair('text', T.Text);
      O.AddPair('count', TJSONNumber.Create(T.Count));
      O.AddPair('last', DateToISO8601(T.Last, False));
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
  T: TNecoTypedEntry;
begin
  FItems.Clear;
  FTyped.Clear;
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
    // Buscas digitadas (arquivo de versão anterior não tem: fica vazio).
    Arr := nil;
    V := Root.GetValue('typed');
    if V is TJSONArray then
      Arr := TJSONArray(V);
    if Arr <> nil then
      for V in Arr do
        if V is TJSONObject then
        begin
          O := TJSONObject(V);
          T.Text := Trim(NecoJsonStr(O, 'text', ''));
          if T.Text = '' then
            Continue;
          T.Count := O.GetValue<Integer>('count', 1);
          if T.Count < 1 then
            T.Count := 1;
          if not TryISO8601ToDate(NecoJsonStr(O, 'last', ''), T.Last, False) then
            T.Last := 0;
          if FTyped.Count < CMaxTyped then
            FTyped.Add(T);
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
