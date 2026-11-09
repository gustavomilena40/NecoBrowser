program NecoBrowser;

uses
  System.StartUpCopy,
  FMX.Forms,
  Neco.UI.Main in 'src\ui\Neco.UI.Main.pas' {FormMain};

{$R *.res}

begin
  ReportMemoryLeaksOnShutdown := True;
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
