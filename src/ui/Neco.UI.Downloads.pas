unit Neco.UI.Downloads;

{ Painel de downloads: uma linha por download desta sessão, a mais nova no topo.

  Cada linha guarda o INecoDownload (que vive independente da aba) e escuta o OnChanged
  dele, que chega na thread principal a cada progresso. A linha só atualiza textos e a
  barra; nunca se libera nesse evento. Ao fechar o app, Shutdown desliga os avisos
  antes de o motor soltar os downloads. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Objects, FMX.Layouts, FMX.StdCtrls,
  Neco.Engine.Intf, Neco.UI.Theme, Neco.UI.SidePanel;

type
  TNecoDownloadsPanel = class;
  TNecoDownloadFinishedEvent = procedure(Sender: TObject; ASuccess: Boolean) of object;

  TNecoDownloadRow = class(TRectangle)
  private
    FPanel: TNecoDownloadsPanel;
    FDownload: INecoDownload;
    FIcon: TPath;
    FName: TLabel;
    FStatus: TLabel;
    FTrack: TRectangle;
    FBar: TRectangle;
    FBtnAction: TNecoIconButton;
    FState: TNecoDownloadState;
    FHover: Boolean;
    procedure DownloadChanged(Sender: TObject);
    procedure ActionClick(Sender: TObject);
    procedure RowClick(Sender: TObject);
    procedure RowHover(Sender: TObject);
    procedure Refresh;
  public
    constructor CreateRow(APanel: TNecoDownloadsPanel; const ADownload: INecoDownload);
    destructor Destroy; override;
    /// Para de ouvir o download (antes de liberar a linha ou ao fechar o app).
    procedure Unhook;
    procedure Restyle;
    property State: TNecoDownloadState read FState;
  end;

  TNecoDownloadsPanel = class(TNecoSidePanel)
  private
    FBtnClear: TNecoIconButton;
    FOnFinished: TNecoDownloadFinishedEvent;
    procedure ClearClick(Sender: TObject);
    procedure DoFinished(ASuccess: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Add(const ADownload: INecoDownload);
    /// Quantos downloads ainda estão em andamento.
    function ActiveCount: Integer;
    /// O app está fechando: nenhuma linha escuta mais nada.
    procedure Shutdown;
    /// A janela vai fechar com downloads em andamento (a última aba mudou de janela): eles
    /// saem daqui, prontos para entrar no painel da outra (Add). As linhas daqui param de ouvir.
    function TakeInProgress: TArray<INecoDownload>;
    procedure Restyle; override;
    /// Um download terminou (ASuccess = concluído; False = falhou ou cancelado).
    property OnFinished: TNecoDownloadFinishedEvent read FOnFinished write FOnFinished;
  end;

/// "1,5 MB", "820 KB"...
function NecoFormatBytes(ABytes: Int64): string;

implementation

uses
  Neco.UI.Frame;

function NecoFormatBytes(ABytes: Int64): string;
begin
  if ABytes < 1024 then
    Result := Format('%d B', [ABytes])
  else if ABytes < 1024 * 1024 then
    Result := Format('%.0f KB', [ABytes / 1024])
  else if ABytes < Int64(1024) * 1024 * 1024 then
    Result := Format('%.1f MB', [ABytes / (1024 * 1024)])
  else
    Result := Format('%.2f GB', [ABytes / (1024 * 1024 * 1024)]);
end;

{ TNecoDownloadRow }

constructor TNecoDownloadRow.CreateRow(APanel: TNecoDownloadsPanel; const ADownload: INecoDownload);
var
  Mid: TLayout;
begin
  inherited Create(APanel);
  FPanel := APanel;
  FDownload := ADownload;
  Height := 66;
  Margins.Rect := TRectF.Create(0, 0, 4, 6);
  XRadius := 10;
  YRadius := 10;
  Stroke.Kind := TBrushKind.None;
  Fill.Kind := TBrushKind.Solid;
  HitTest := True;
  OnClick := RowClick;
  OnMouseEnter := RowHover;
  OnMouseLeave := RowHover;

  FIcon := NecoNewIcon(APanel, Self, ICO_ARQUIVO, 20, Palette.TextMuted);
  FIcon.Align := TAlignLayout.Left;
  FIcon.Margins.Rect := TRectF.Create(12, 23, 10, 23);

  FBtnAction := NecoNewButton(APanel, Self, ICO_FECHAR, 'Cancelar', ActionClick);
  FBtnAction.Align := TAlignLayout.Right;
  FBtnAction.Width := 30;
  FBtnAction.Height := 30;
  FBtnAction.IconSize := 16;
  FBtnAction.Margins.Rect := TRectF.Create(0, 18, 8, 18);

  Mid := TLayout.Create(APanel);
  Mid.Parent := Self;
  Mid.Align := TAlignLayout.Client;
  Mid.HitTest := False;
  Mid.Margins.Rect := TRectF.Create(0, 11, 6, 9);

  FName := NecoNewLabel(APanel, Mid, '', 13);
  FName.Align := TAlignLayout.Top;
  FName.Height := 18;
  FName.Position.Y := 0;
  FStatus := NecoNewLabel(APanel, Mid, '', 11.5);
  FStatus.Align := TAlignLayout.Top;
  FStatus.Height := 17;
  FStatus.Position.Y := 100;
  FTrack := TRectangle.Create(APanel);
  FTrack.Parent := Mid;
  FTrack.Align := TAlignLayout.Top;
  FTrack.Height := 3;
  FTrack.Position.Y := 200;
  FTrack.Margins.Top := 5;
  FTrack.XRadius := 1.5;
  FTrack.YRadius := 1.5;
  FTrack.Stroke.Kind := TBrushKind.None;
  FTrack.HitTest := False;
  FBar := TRectangle.Create(APanel);
  FBar.Parent := FTrack;
  FBar.Align := TAlignLayout.Left;
  FBar.Width := 0;
  FBar.XRadius := 1.5;
  FBar.YRadius := 1.5;
  FBar.Stroke.Kind := TBrushKind.None;
  FBar.HitTest := False;

  FState := ndsInProgress;
  FDownload.OnChanged := DownloadChanged;
  Restyle;
  Refresh;
end;

destructor TNecoDownloadRow.Destroy;
begin
  Unhook;
  inherited;
end;

procedure TNecoDownloadRow.Unhook;
begin
  if FDownload <> nil then
  begin
    FDownload.OnChanged := nil;
    FDownload := nil; // o objeto do download continua vivo (o motor ou esta linha o seguram)
  end;
end;

procedure TNecoDownloadRow.DownloadChanged(Sender: TObject);
var
  Old: TNecoDownloadState;
begin
  Old := FState;
  Refresh;
  if (Old = ndsInProgress) and (FState <> ndsInProgress) then
    FPanel.DoFinished(FState = ndsCompleted);
end;

procedure TNecoDownloadRow.Refresh;
var
  Name, S: string;
  Rec, Tot: Int64;
begin
  if FDownload = nil then
    Exit;
  FState := FDownload.State;
  Name := ExtractFileName(FDownload.FilePath);
  if Name = '' then
    Name := FDownload.Url;
  FName.Text := Name;
  Hint := FDownload.FilePath;
  ShowHint := Hint <> '';
  Rec := FDownload.Received;
  Tot := FDownload.Total;
  case FState of
    ndsInProgress:
      begin
        if Tot > 0 then
          S := NecoFormatBytes(Rec) + ' de ' + NecoFormatBytes(Tot)
        else
          S := NecoFormatBytes(Rec) + ' baixados';
        FTrack.Visible := True;
        if Tot > 0 then
          FBar.Width := FTrack.Width * Rec / Tot
        else
          FBar.Width := FTrack.Width * 0.3;
        FBtnAction.IconData := ICO_FECHAR;
        FBtnAction.Hint := 'Cancelar';
        FBtnAction.Visible := True;
      end;
    ndsCompleted:
      begin
        S := 'Concluído · ' + NecoFormatBytes(Rec) + ' · clique para abrir';
        FTrack.Visible := False;
        FBtnAction.IconData := ICO_PASTA;
        FBtnAction.Hint := 'Mostrar na pasta';
        FBtnAction.Visible := True;
      end;
  else
    S := 'Falhou ou foi cancelado';
    FTrack.Visible := False;
    FBtnAction.Visible := False;
  end;
  FStatus.Text := S;
  Restyle;
end;

procedure TNecoDownloadRow.ActionClick(Sender: TObject);
begin
  if FDownload = nil then
    Exit;
  if FState = ndsInProgress then
    FDownload.Cancel
  else if FState = ndsCompleted then
    NecoShowInFolder(FDownload.FilePath);
end;

procedure TNecoDownloadRow.RowClick(Sender: TObject);
begin
  if (FDownload <> nil) and (FState = ndsCompleted) then
    NecoShellOpen(FDownload.FilePath);
end;

procedure TNecoDownloadRow.RowHover(Sender: TObject);
begin
  FHover := IsMouseOver;
  Restyle;
end;

procedure TNecoDownloadRow.Restyle;
begin
  if FHover and (FState = ndsCompleted) then
    Fill.Color := Palette.Hover
  else
    Fill.Color := Palette.Field;
  FName.TextSettings.FontColor := Palette.Text;
  if FState = ndsInterrupted then
    FStatus.TextSettings.FontColor := Palette.Danger
  else
    FStatus.TextSettings.FontColor := Palette.TextMuted;
  if FState = ndsCompleted then
    FIcon.Stroke.Color := Palette.Shield
  else
    FIcon.Stroke.Color := Palette.TextMuted;
  FTrack.Fill.Color := Palette.Divider;
  FBar.Fill.Color := Palette.Accent;
  FBtnAction.Restyle;
  if FState = ndsCompleted then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
end;

{ TNecoDownloadsPanel }

constructor TNecoDownloadsPanel.Create(AOwner: TComponent);
begin
  CreatePanel(AOwner, 'Downloads', 'Nada baixado ainda. A Neco está de folga.', 'lazy');
  FBtnClear := AddHeaderButton(ICO_LIXEIRA, 'Limpar os que já terminaram', ClearClick);
end;

procedure TNecoDownloadsPanel.Add(const ADownload: INecoDownload);
begin
  if ADownload = nil then
    Exit;
  AppendRow(TNecoDownloadRow.CreateRow(Self, ADownload), True);
end;

function TNecoDownloadsPanel.ActiveCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to RowCount - 1 do
    if TNecoDownloadRow(Row(I)).State = ndsInProgress then
      Inc(Result);
end;

procedure TNecoDownloadsPanel.ClearClick(Sender: TObject);
var
  I: Integer;
  R: TNecoDownloadRow;
begin
  // O botão é do cabeçalho, não das linhas: liberar linhas aqui é seguro.
  for I := RowCount - 1 downto 0 do
  begin
    R := TNecoDownloadRow(Row(I));
    if R.State <> ndsInProgress then
    begin
      R.Unhook;
      RemoveRow(R);
    end;
  end;
end;

procedure TNecoDownloadsPanel.DoFinished(ASuccess: Boolean);
begin
  if Assigned(FOnFinished) then
    FOnFinished(Self, ASuccess);
end;

procedure TNecoDownloadsPanel.Shutdown;
var
  I: Integer;
begin
  FOnFinished := nil;
  for I := 0 to RowCount - 1 do
    TNecoDownloadRow(Row(I)).Unhook;
end;

function TNecoDownloadsPanel.TakeInProgress: TArray<INecoDownload>;
var
  I: Integer;
  R: TNecoDownloadRow;
begin
  Result := nil;
  for I := 0 to RowCount - 1 do
  begin
    R := TNecoDownloadRow(Row(I));
    if (R.State = ndsInProgress) and (R.FDownload <> nil) then
    begin
      Result := Result + [R.FDownload];
      // Antes da linha nova: o download tem um ouvinte só (OnChanged).
      R.Unhook;
    end;
  end;
end;

procedure TNecoDownloadsPanel.Restyle;
var
  I: Integer;
begin
  inherited;
  if FBtnClear <> nil then
    FBtnClear.Restyle;
  for I := 0 to RowCount - 1 do
    TNecoDownloadRow(Row(I)).Restyle;
end;

end.
