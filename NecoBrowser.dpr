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
  Neco.Core.Favicons in 'src\core\Neco.Core.Favicons.pas',
  Neco.Core.Updater in 'src\core\Neco.Core.Updater.pas',
  Neco.Core.AdExtension in 'src\core\Neco.Core.AdExtension.pas',
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
  Neco.UI.DefaultBrowser in 'src\ui\Neco.UI.DefaultBrowser.pas',
  Neco.UI.Shortcuts in 'src\ui\Neco.UI.Shortcuts.pas',
  Neco.UI.Instance in 'src\ui\Neco.UI.Instance.pas',
  Neco.UI.App in 'src\ui\Neco.UI.App.pas',
  Neco.UI.Main in 'src\ui\Neco.UI.Main.pas' {FormMain};

{$R *.res}

begin
  ReportMemoryLeaksOnShutdown := True;
  // Já há um navegador aberto com este perfil: ele abre o pedido e esta execução sai.
  if TNecoApp.HandOffToRunning then
    Exit;
  Application.Initialize;
  // O que é do navegador inteiro (dados, motor, atualizador) vem antes da primeira janela.
  NecoApp := TNecoApp.Create;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
  NecoApp.Free;
  NecoApp := nil;
end.
