# NecoBrowser — plano da fase 1 (Windows) para o agente executor

## Contexto

O usuário quer um navegador próprio, leve e que ele possa alterar à vontade. O motor
vem pronto do sistema e o código do NecoBrowser é só a "casca" que o controla.

Decisões do usuário:
- **FireMonkey com motor próprio por plataforma.** Não usar o `TWebBrowser` do FMX, que
  não dá acesso às requisições, aos downloads nem aos pop-ups. A tela FMX conversa com uma
  interface `INecoEngine`.
  - Windows: WebView2 via COM direto (`Winapi.WebView2`, que vem na RTL do Delphi 13).
  - Android (fase 2, fora deste plano): `WebView` com JNI e um `.jar` próprio.
- **A fase 1 entrega só o Windows**, já com a arquitetura pronta para o Android, sem
  retrabalho.
- **MVP:** abas, barra de endereço com busca, voltar/avançar/recarregar, bloqueador de
  anúncios de verdade (interceptação de requisição), downloads, favoritos, tema escuro
  e atalhos.
- **Pasta:** `C:\Users\user02\Desktop\Projetos Teste\NecoBrowser`. A pasta existe e está
  vazia. `Projetos Teste` é uma pasta intocável: nunca apague nada nela, nem na raiz.
- **Git autorizado:** `git init` local, com um commit por etapa. Sem remoto e sem push.

Ambiente conferido em 2026-11-09:
- Delphi 13 em `C:\Program Files (x86)\Embarcadero\Studio\37.0`. `Winapi.WebView2.dcu` e
  `Vcl.Edge.dcu` existem.
- WebView2 Runtime 157 instalado.
- **Falta a `WebView2Loader.dll`.** Ela vem do pacote **EdgeView2 SDK** do GetIt (o mesmo
  da captura do usuário). Os outros itens daquela busca não servem: MMX é ferramenta da
  IDE, IPWorks é SNMP e ShellBrowser é navegador de arquivos.

## Pré-requisito manual (do usuário, antes do agente começar)

Na IDE: **Tools → GetIt Package Manager → "EdgeView2 SDK" → Install.** Depois, o agente
localiza a DLL (`Get-ChildItem -Recurse -Filter WebView2Loader.dll` em `Studio\37.0` e em
`Documents\Embarcadero\Studio\37.0\CatalogRepository`). Se não achar, o agente **para e
avisa**. Ele não baixa a DLL de outra fonte por conta própria.

## Regras obrigatórias para o executor

1. Leia integralmente, antes de criar qualquer `.pas`, `.fmx` ou `.dpr`:
   - `C:\Users\user02\.claude\delphi-regras-para-agentes.md`
   - `C:\Users\user02\.agent-bridge\README.md` (locks e documentos em `docs\`)
   - `C:\Users\user02\.agent-bridge\skills\delphi-fmx-visual\SKILL.md`. Use os scripts
     dela: `fmx_tool.py` para `.fmx`, `compilar.py` para baseline de avisos e `ui.ps1`
     para prints do exe.
2. Todos os arquivos novos em UTF-8 com BOM e CRLF. Conferir com as técnicas da Parte 1
   das regras Delphi.
3. Antes da primeira edição, criar um lock em `C:\Users\user02\.agent-bridge\locks\NecoBrowser.lock.md`.
   Removê-lo no fim.
4. Compilar sempre para uma pasta temporária e anotar a contagem de avisos. Nenhum aviso
   novo sem justificativa.
5. Commit a cada etapa concluída e compilando, com o trailer
   `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
6. Copiar este plano para `NecoBrowser\docs\` como primeiro documento do projeto. No fim,
   gravar o relatório final ali também.

## Arquitetura

```
NecoBrowser\
  NecoBrowser.dpr / .dproj          FMX, alvos Win64 (principal) e Win32
  src\core\        sem FMX, sem Winapi: compila em Windows E Android
    Neco.Core.Url.pas               texto digitado -> URL ou busca (DuckDuckGo/Google configurável)
    Neco.Core.Blocklist.pas         carrega hosts, THashSet<string>, testa host e domínios-pai
    Neco.Core.Bookmarks.pas         favoritos em JSON (System.JSON)
    Neco.Core.History.pas           histórico simples em JSON
    Neco.Core.Settings.pas          caminhos (%APPDATA%\NecoBrowser), motor de busca, tema
  src\engine\
    Neco.Engine.Intf.pas            INecoEngine + eventos (sem dependência de plataforma)
    Neco.Engine.WebView2.pas        {$IFDEF MSWINDOWS} implementação COM
    Neco.Engine.Factory.pas         escolhe a implementação por plataforma
  src\ui\
    Neco.UI.Main.pas/.fmx           form principal: barra de abas, barra de endereço, área do motor
    Neco.UI.Tab.pas                 TNecoTab: dono de um INecoEngine + estado (título, url, progresso)
    Neco.UI.Downloads.pas/.fmx      painel de downloads
    Neco.UI.Bookmarks.pas/.fmx      painel de favoritos
  data\blocklist-hosts.txt          lista no formato hosts (ex.: StevenBlack unificada), copiada ao lado do exe
  redist\Win64\WebView2Loader.dll   e Win32 (copiadas do SDK; o post-build leva para a pasta do exe)
  docs\
```

**`INecoEngine`** (contrato mínimo; o Android da fase 2 implementa o mesmo):
`Navigate(url)`, `GoBack`, `GoForward`, `Reload`, `Stop`, `CanGoBack/CanGoForward`,
`SetBounds(RectF físico)`, `SetVisible`, `Focus`, `ExecuteScript`, e os eventos
`OnNavigationStarting`, `OnNavigationCompleted`, `OnTitleChanged`, `OnUrlChanged`,
`OnNewWindowRequested(url)`, `OnDownloadStarting(info)`, `OnAcceleratorKey(key, shift): handled`,
mais uma propriedade `RequestFilter: TFunc<string, Boolean>` (url → bloquear?).

## Implementação WebView2 (pontos que dão errado se ignorados)

- **Criação:** `CreateCoreWebView2EnvironmentWithOptions` com o user data folder em
  `%LOCALAPPDATA%\NecoBrowser\WebView2`. É **um ambiente só** para o app, compartilhado
  por todas as abas, e um controller por aba (`CreateCoreWebView2Controller` sobre o HWND
  do form, via `FMX.Platform.Win.FormToHWND`).
- **Handlers COM:** classes `TInterfacedObject` que implementam os `ICoreWebView2*Handler`.
  Guarde as referências e os tokens (`EventRegistrationToken`) para chamar `remove_*` ao
  fechar a aba. Fechamento na ordem: remover eventos → `Controller.Close` → soltar as
  interfaces. Atenção às regras 4.2 e 4.3 (interface := nil sobre objeto morto).
- **COM/STA:** confirme que a thread principal do FMX já está em STA (OleInitialize). Se
  não estiver, inicialize no `.dpr` com o par de finalização (regra 4.5).
- **DPI:** `Controller.Bounds` é em pixel físico. Converta coordenadas FMX multiplicando
  por `Handle.Scale` do form e recalcule no `OnResize` e na troca de monitor.
- **"Espaço aéreo":** o WebView2 é uma janela nativa por cima do FMX. Nada do FMX (menus,
  pop-ups, painéis) pode ficar sobre a área da página. Os painéis de downloads e favoritos
  são laterais e **encolhem** a área do motor, nunca ficam por cima dela.
- **Bloqueador:** `AddWebResourceRequestedFilter('*', COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL)`.
  No `WebResourceRequested`, extraia o host. Se `Blocklist.IsBlocked(host)`, devolva
  `Environment.CreateWebResourceResponse(nil, 403, 'Blocked', '')`. A consulta precisa ser
  O(1), porque roda centenas de vezes por página. Nunca bloqueie a navegação principal
  (`ResourceContext = DOCUMENT`) de quem o usuário digitou. Contador de bloqueados por aba,
  exibido na barra.
- **Nova janela / `target=_blank`:** `NewWindowRequested` → `Handled := True` → abrir uma
  aba nova com a URI.
- **Downloads:** `ICoreWebView2_4.add_DownloadStarting` (via `QueryInterface`). Use a
  pasta Downloads do usuário, com progresso e conclusão pelo `ICoreWebView2DownloadOperation`
  no painel. Antes, confira no `Winapi.WebView2.hpp` do Delphi 13 quais versões de
  `ICoreWebView2_N` existem. Se faltar alguma, registre e use o fallback (deixar o WebView2
  baixar sozinho).
- **Atalhos:** com o foco na página, o form FMX **não recebe teclas**. Trate pelo
  `Controller.AcceleratorKeyPressed`: Ctrl+T, Ctrl+W, Ctrl+L, Ctrl+Tab, Ctrl+Shift+Tab,
  F5, Alt+←/→, Ctrl+D (favoritar), Ctrl+J (downloads). Os mesmos atalhos também no
  `OnKeyDown` do form, para quando o foco estiver na barra.
- **Tema escuro:** estilo escuro do FMX na interface, e `PreferredColorScheme = DARK` no
  profile (`ICoreWebView2_13`), quando disponível, para os sites respeitarem
  `prefers-color-scheme`.

## Etapas (um commit cada)

1. **Base:** `git init`, `.gitignore` do Delphi (`__history`, `*.dcu`, `Win32\`, `Win64\`,
   `*.local`, `*.identcache`), docs, lock, projeto FMX vazio compilando em Win64 e Win32.
   Baseline de avisos.
2. **Núcleo** (`src\core`) com testes simples num console `tests\CoreTests.dpr` (URL vs
   busca, blocklist com domínio-pai, ida e volta dos favoritos em JSON). O núcleo também
   precisa compilar para Android64 (`dccaarm64`), para provar que não depende de Windows.
   Se o SDK Android não estiver configurado, registre o fato e não trave a etapa.
3. **Motor WebView2 com uma aba:** abrir uma página, voltar/avançar/recarregar, barra de
   endereço e título.
4. **Abas:** criar, fechar e alternar (só a aba ativa visível), nova janela vira aba,
   atalhos.
5. **Bloqueador** com contador por aba e liga/desliga.
6. **Downloads e favoritos** (painéis laterais, JSON em `%APPDATA%\NecoBrowser`).
7. **Tema escuro e acabamento.** Relatório final em `docs\`, remover o lock.

## Verificação

- Cada etapa compila em Win64 e Win32 sem avisos novos sobre a baseline.
- `tests\CoreTests.exe` passa.
- Execução real com prints pelo `ui.ps1`:
  1. abrir `https://example.com`, depois `g1.globo.com`;
  2. digitar "clima são paulo" e confirmar que vai para a busca;
  3. abrir 3 abas, fechar a do meio e conferir se as outras seguem certas;
  4. o contador do bloqueador sobe no g1, e desligar o bloqueio faz voltarem os anúncios;
  5. baixar um arquivo de teste (ex.: um PDF público) e vê-lo concluído no painel;
  6. favoritar, fechar o app, reabrir e o favorito continua lá;
  7. testar os atalhos com o foco dentro da página;
  8. mudar a escala do Windows (125%/150%) e conferir se a página ocupa a área certa.
- Abrir e fechar 20 abas e medir a memória do processo em repouso antes e depois (regra 3.3).
  Ela não deve crescer de forma contínua.

## Fora deste plano (fase 2)

Motor Android: `NecoWebViewClient.jar` (`WebViewClient` com `shouldInterceptRequest`,
`WebChromeClient` com `onCreateWindow` e `onProgressChanged`), importação JNI,
`Neco.Engine.AndroidWebView.pas` e cuidado com o `shouldInterceptRequest` rodando em
thread de fundo. Esse trabalho reusa `src\core` e `INecoEngine` sem alterá-los.
