unit Neco.Core.Bookmarks;

{ Favoritos em JSON.
  Sem FMX e sem Winapi: compila em Windows e Android. }

interface

uses
  System.Classes, System.Generics.Collections;

type
  TNecoBookmark = record
    Title: string;
    Url: string;
    Added: TDateTime;
  end;

  TNecoBookmarks = class
  private
    FItems: TList<TNecoBookmark>;
    FOnChange: TNotifyEvent;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TNecoBookmark;
    procedure Changed;
  public
    constructor Create;
    destructor Destroy; override;
    function IndexOfUrl(const AUrl: string): Integer;
    function Contains(const AUrl: string): Boolean;
    /// Acrescenta no fim. Se a URL já existe, só atualiza o título. Devolve o índice.
    function Add(const ATitle, AUrl: string): Integer;
    procedure Remove(const AUrl: string);
    /// Troca o nome do favorito. Nome vazio é ignorado. Devolve False se a URL não existe.
    function Rename(const AUrl, ATitle: string): Boolean;
    procedure Delete(AIndex: Integer);
    /// Liga ou desliga o favorito da URL. Devolve True se ficou favoritado.
    function Toggle(const ATitle, AUrl: string): Boolean;
    procedure Clear;
    function ToJson: string;
    /// Substitui o conteúdo. JSON inválido deixa a lista vazia e devolve False.
    function FromJson(const AJson: string): Boolean;
    procedure LoadFromFile(const AFileName: string);
    procedure SaveToFile(const AFileName: string);
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TNecoBookmark read GetItem; default;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

uses
  System.SysUtils, System.JSON, System.DateUtils, Neco.Core.Files;

{ TNecoBookmarks }

constructor TNecoBookmarks.Create;
begin
  inherited Create;
  FItems := TList<TNecoBookmark>.Create;
end;

destructor TNecoBookmarks.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TNecoBookmarks.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TNecoBookmarks.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TNecoBookmarks.GetItem(AIndex: Integer): TNecoBookmark;
begin
  Result := FItems[AIndex];
end;

function TNecoBookmarks.IndexOfUrl(const AUrl: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    if FItems[I].Url = AUrl then
      Exit(I);
  Result := -1;
end;

function TNecoBookmarks.Contains(const AUrl: string): Boolean;
begin
  Result := IndexOfUrl(AUrl) >= 0;
end;

function TNecoBookmarks.Add(const ATitle, AUrl: string): Integer;
var
  B: TNecoBookmark;
begin
  Result := IndexOfUrl(AUrl);
  if Result >= 0 then
  begin
    B := FItems[Result];
    B.Title := ATitle;
    FItems[Result] := B;
  end
  else
  begin
    B.Title := ATitle;
    B.Url := AUrl;
    B.Added := Now;
    Result := FItems.Add(B);
  end;
  Changed;
end;

procedure TNecoBookmarks.Remove(const AUrl: string);
var
  I: Integer;
begin
  I := IndexOfUrl(AUrl);
  if I >= 0 then
    Delete(I);
end;

function TNecoBookmarks.Rename(const AUrl, ATitle: string): Boolean;
var
  I: Integer;
  B: TNecoBookmark;
  T: string;
begin
  I := IndexOfUrl(AUrl);
  T := Trim(ATitle);
  Result := I >= 0;
  if not Result or (T = '') or (FItems[I].Title = T) then
    Exit;
  B := FItems[I];
  B.Title := T;
  FItems[I] := B;
  Changed;
end;

procedure TNecoBookmarks.Delete(AIndex: Integer);
begin
  FItems.Delete(AIndex);
  Changed;
end;

function TNecoBookmarks.Toggle(const ATitle, AUrl: string): Boolean;
begin
  Result := not Contains(AUrl);
  if Result then
    Add(ATitle, AUrl)
  else
    Remove(AUrl);
end;

procedure TNecoBookmarks.Clear;
begin
  FItems.Clear;
  Changed;
end;

function TNecoBookmarks.ToJson: string;
var
  Root, O: TJSONObject;
  Arr: TJSONArray;
  B: TNecoBookmark;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(1));
    Arr := TJSONArray.Create;
    Root.AddPair('bookmarks', Arr);
    for B in FItems do
    begin
      O := TJSONObject.Create;
      Arr.AddElement(O);
      O.AddPair('title', B.Title);
      O.AddPair('url', B.Url);
      O.AddPair('added', DateToISO8601(B.Added, False));
    end;
    Result := Root.Format(2);
  finally
    Root.Free;
  end;
end;

function TNecoBookmarks.FromJson(const AJson: string): Boolean;
var
  Root, O: TJSONObject;
  Arr: TJSONArray;
  V: TJSONValue;
  B: TNecoBookmark;
begin
  FItems.Clear;
  Result := False;
  Root := NecoParseObject(AJson);
  if Root <> nil then
  try
    V := Root.GetValue('bookmarks');
    if V is TJSONArray then
    begin
      Arr := TJSONArray(V);
      for V in Arr do
        if V is TJSONObject then
        begin
          O := TJSONObject(V);
          B.Url := NecoJsonStr(O, 'url', '');
          if B.Url = '' then
            Continue;
          B.Title := NecoJsonStr(O, 'title', B.Url);
          if not TryISO8601ToDate(NecoJsonStr(O, 'added', ''), B.Added, False) then
            B.Added := 0;
          FItems.Add(B);
        end;
      Result := True;
    end;
  finally
    Root.Free;
  end;
  Changed;
end;

procedure TNecoBookmarks.LoadFromFile(const AFileName: string);
begin
  FromJson(NecoLoadText(AFileName));
end;

procedure TNecoBookmarks.SaveToFile(const AFileName: string);
begin
  NecoSaveTextAtomic(AFileName, ToJson);
end;

end.
