program NecoBrowser;

uses
  System.StartUpCopy,
  FMX.Forms,
  Neco.Core.Trace in 'src\core\Neco.Core.Trace.pas',
  Neco.Core.Url in 'src\core\Neco.Core.Url.pas',
  Neco.Core.Files in 'src\core\Neco.Core.Files.pas',
  Neco.Core.Blocklist in 'src\core\Neco.Core.Blocklist.pas',
  Neco.Core.Bookmarks in 'src\core\Neco.Core.Bookmarks.pas',
  Neco.Core.History in 'src\core\Neco.Core.History.pas',
  Neco.Core.Settings in 'src\core\Neco.Core.Settings.pas',
  Neco.Engine.Intf in 'src\engine\Neco.Engine.Intf.pas',
  Neco.Engine.WebView2 in 'src\engine\Neco.Engine.WebView2.pas',
  Neco.Engine.Factory in 'src\engine\Neco.Engine.Factory.pas',
  Neco.UI.Theme in 'src\ui\Neco.UI.Theme.pas',
  Neco.UI.Tab in 'src\ui\Neco.UI.Tab.pas',
  Neco.UI.Frame in 'src\ui\Neco.UI.Frame.pas',
  Neco.UI.Neco in 'src\ui\Neco.UI.Neco.pas',
  Neco.UI.SidePanel in 'src\ui\Neco.UI.SidePanel.pas',
  Neco.UI.Downloads in 'src\ui\Neco.UI.Downloads.pas',
  Neco.UI.Bookmarks in 'src\ui\Neco.UI.Bookmarks.pas',
  Neco.UI.Settings in 'src\ui\Neco.UI.Settings.pas',
  Neco.UI.ErrorView in 'src\ui\Neco.UI.ErrorView.pas',
  Neco.UI.BookmarkBar in 'src\ui\Neco.UI.BookmarkBar.pas',
  Neco.UI.History in 'src\ui\Neco.UI.History.pas',
  Neco.UI.Main in 'src\ui\Neco.UI.Main.pas' {FormMain};

{$R *.res}

begin
  ReportMemoryLeaksOnShutdown := True;
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
