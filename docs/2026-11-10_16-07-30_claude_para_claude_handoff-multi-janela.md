# NecoBrowser — handoff: várias janelas num processo + arrastar abas

- **De:** Claude Code (sessão `session_016LXiuQAtQtZv3K2eqVqXnT`), em 2026-11-10 16:07 (-03).
- **Para:** o agente que vai executar o plano.
- **Plano aprovado pelo usuário:** `docs\2026-11-10_16-07-30_claude_plano-multi-janela.md`.
  Leia o plano inteiro antes deste documento. Aqui estão só o estado atual, o que o
  levantamento achou e as armadilhas da máquina. Se algo aqui contradisser o plano, vale o
  plano; avise o usuário.
- **Motivo da troca:** o usuário pediu que esta sessão só planejasse e outro agente executasse.
  Não houve bloqueio técnico.

## 1. Antes de começar

1. Leia por inteiro: `C:\Users\user02\.claude\delphi-regras-para-agentes.md` (regras de Delphi;
   a parte 1, sobre codificação, é obrigatória) e `C:\Users\user02\.agent-bridge\README.md`.
2. Crie o lock `C:\Users\user02\.agent-bridge\locks\NecoBrowser.lock.md` a partir de
   `C:\Users\user02\.agent-bridge\templates\LOCK.md`. Às 16:07 não havia lock de ninguém no
   NecoBrowser.
3. Responda sempre em português do Brasil. O usuário compila e testa o app ele mesmo. Você
   entrega o exe em `%TEMP%\NecoBuild\<etiqueta>-win64` e espera o retorno dele antes de passar
   à próxima etapa (regra do plano).
4. Consulte o grafo antes de explorar código: `graphify query "<pergunta>"` (pedido fixo do
   usuário). Ao fim de cada etapa, rode `/graphify --update` (seção 6).

## 2. Estado do repositório (16:07)

Git local, sem remoto, branch `main`, último commit `4c954fb`. **Há muita coisa sem commit.** A
Etapa 0 do plano commita isso como base:

| Arquivo | O que é |
| --- | --- |
| `src/core/Neco.Core.Updater.pas`, `tools/publicar.sh`, `tools/versao_res.py`, mudanças em `Settings`, `Neco.UI.Settings`, `NecoBrowser.res` | Atualização automática pelo GitHub Releases (sessão anterior, testada pelo usuário). |
| `src/ui/Neco.UI.DefaultBrowser.pas` | Registrar como navegador padrão do Windows. |
| `src/core/Neco.Core.AdExtension.pas`, mudanças em `Neco.Engine.WebView2.pas`, `Neco.Engine.Factory.pas`, `Neco.UI.Main.pas`, `CoreTests.dpr` | Bloqueio do YouTube com o uBlock Origin Lite como extensão do WebView2 (seção 3). Testado pelo usuário. |
| `NecoBrowser.Artwork/`, `Sprites/`, `graphify-out/` | Fora do Git hoje. **Pergunte ao usuário antes de incluir.** Os sprites da Neco têm uma questão de direitos (ver `docs/2026-11-09_11-45-00_...`), e `graphify-out/` é gerado. |

Commits com o trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. O plano
autoriza commits e tags locais por etapa, nada de push.

## 3. A feature do uBOL (feita hoje, testada pelo usuário)

O usuário testou depois deste handoff e confirmou que o YouTube fica sem anúncio. Pode entrar
no commit-base da Etapa 0 sem ressalva. Não existe tela de extensões no app, e isso é de
propósito. Resumo para não quebrar nada ao mover código na Etapa 2:

- `TNecoAdExtension` baixa `uBOLite_*.chromium.zip` de `uBlockOrigin/uBOL-home` (latest),
  confere o `digest` sha256 do GitHub e descompacta em `<WebDataDir>\extensoes\uBOLite-<versão>`.
- No motor, `TNecoWV2EnvOptions` implementa `ICoreWebView2EnvironmentOptions6`, porque a
  classe da RTL (`Winapi.EdgeUtils`) não implementa. `NecoWV2SetAdExtension` instala pelo
  `ICoreWebView2Profile7` do perfil da primeira aba pronta (`ExtAttach`, chamado no
  `ControllerCreated`). O id instalado fica em `<UserDataFolder>\neco-extensao.json`.
- No `TFormMain`: `StartAdExtension`, `ApplyAdExtension`, `AdTick`, `AdDownloaded`,
  `AdInstalled`, campos `FAdExt`, `FAdTimer` e `FAdFolder`. **A Etapa 2 leva tudo isso para
  a `TNecoApp`.** O `ApplyAdExtension` é chamado em `ShieldClick` e no `scBlocker` de
  `SettingsChanged`; isso vira aviso do app para todas as janelas.
- Fallback: se o ambiente falhar com `0x8007139F` (motor já aberto com outras opções), ele
  recria sem extensões (`TNecoWV2EnvHandler.Invoke`). **Depois da Etapa 5 (uma instância
  só), esse caso deixa de acontecer**, a não ser com o exe antigo aberto.

## 4. O que o levantamento achou (base do plano, com local no código)

- **Uma janela por processo hoje:** o `.dpr` faz um só `Application.CreateForm(TFormMain, ...)`.
  A segunda janela é outro exe, e `FSessionOwner` (`NecoAcquireInstanceLock`,
  `Neco.UI.Frame.pas:342`, mutex nomeado pela pasta de dados) decide quem grava a sessão e
  roda atualizador e uBOL.
- **Estado do app dentro do form** (`Neco.UI.Main.pas`, campos nas linhas 24–108):
  `FSettings`, `FBlocklist`, `FBookmarks`, `FHistory`, `FClosed`, `FUpdater`, `FUpdateTimer`,
  `FAdExt`, `FMemTimer`, `FSessionOwner`. Ordem de fechamento em `FormClose` (~linha 428):
  janelas e motores primeiro, depois `NecoEngineShutdown`, `FreeAndNil(FAdExt)`,
  `FinishUpdate` e os dados. **Mantenha essa ordem na `TNecoApp`.**
- **Barra de título com globais de uma janela** (`Neco.UI.Frame.pas:64–76`): `GWnd`, `GForm`,
  `GTitleHeight`, `GHitTest`, `GMaxHover`, `GMaxClick`, `GMaxHot`, `GTracking`, `GFull`,
  `GSavedStyle`, `GSavedRect`, `GSavedMax`. `FrameProc` e `TitleHit` leem essas globais. Use o
  `dwRefData` do `SetWindowSubclass` para apontar o estado de cada janela. Atenção ao
  `EnsureComCtl` (comentário na unit): sem ele o `SetWindowSubclass` falha calado no FMX.
- **Motor já aceita várias janelas-mãe:** `HookParent` / `NecoParentSubclass` / `GHooked`
  (`Neco.Engine.WebView2.pas` ~358–390), e `FParentWnd` por motor. O
  `Set_ParentWindow` existe no import (`Winapi.WebView2.pas:2290`). `Blur` usa `FParentWnd`,
  que precisa ser trocado junto.
- **`TNecoTab` é móvel** (`Neco.UI.Tab.pas`): só o construtor recebe o form (para criar o
  motor). Os eventos `OnChanged`, `OnNewWindow`, `OnDownload`, `OnKey`, `OnPageFocus`,
  `OnNavigated` e `OnFullScreen` são ponteiros de método do form, que precisam ser religados
  ao mover. **Armadilha:** `FBlockerOn` é um `TFunc<Boolean>` criado a partir de
  `TFormMain.BlockerOn` (`Main.pas` ~1258: `TNecoTab.Create(Self, FBlocklist, BlockerOn)`) e
  segura o form antigo. Ele passa a ser do app.
- **Botões da aba** (`Button`, `Icon`, `TitleLabel`, `CloseButton`) são criados e liberados
  pelo form (`BuildTabButton`). Ao mover, libere na origem e recrie no destino.
- **FMX e a janela principal:** `Application.MainForm` tem setter (`FMX.Forms.pas:2273`), e
  `TCommonCustomForm.Close` só chama `Application.Terminate` se `MainForm = Self`, depois de
  `DoClose` (~3284). Trocar o `MainForm` no `FormClose` mantém o app vivo. **Não use
  `Screen.Forms` para contar janelas:** os `TPopup` (menu da seta, sugestões) também são
  forms. Mantenha uma lista própria.
- **Globais que podem ser divididas sem mudança:** `Palette`/`NecoSetTheme`
  (`Neco.UI.Theme.pas:230`) e `GAnims`/`GShown` (`Neco.UI.Neco.pas:153`). `TNecoStage` tem
  `FTimer` próprio (`Neco.UI.Neco.pas:271`); pausar fora da janela em foco é a medida de
  leveza da Etapa 4.
- **Painéis recebem dados por propriedade** (`BuildPanels`, `Main.pas` ~1998):
  `FPanelBookmarks.Bookmarks`, `FPanelHistory.History` e
  `TNecoSettingsPanel.CreateFor(Self, FSettings, FBlocklist.Count)`. `FBookmarks.OnChange :=
  BookmarksChanged` é evento único e vira repasse do app.
- **Sessão v1** (`Neco.Core.Settings.pas:147`): `{"version":1,"tabs":[...],"active":n}`. A v2
  precisa continuar lendo esse formato.
- **Arrastar abas hoje** (`Main.pas` ~969–1045): `TabButtonMouseDown`, `TabButtonMouseMove`
  (limiar de 6 px, depois reordena) e `TabButtonMouseUp`, com os campos `FDragTab`,
  `FDragging`, `FDragStartX`, `FDragGrabX` e `FTabW`. A Etapa 7 entra no `MouseMove`.
- **Linha de comando:** `CmdLineUrl` (`Main.pas` ~360) trata URL, busca e caminho de arquivo
  ("Abrir com"). A Etapa 5 reaproveita isso para os argumentos que chegam por `WM_COPYDATA`.
- WebView2 Runtime instalado: **157.0.4341.42**. `CTargetBrowserVersion` = `137.0.3296.44`.

## 5. Como compilar e testar nesta máquina

- **Build:** `bash tools/build.sh <etiqueta>` normaliza BOM/CRLF (`tools/bomcrlf.py`), compila
  Win64 e Win32 em `%TEMP%\NecoBuild\<etiqueta>-win64|win32` e compara com
  `base-win64.log`/`base-win32.log`. A base hoje é **0 avisos**. O "msbuild falhou com MSB6003;
  compilado direto" é esperado: o script cai no dcc direto. **Uma unit nova precisa entrar no
  `.dpr`, no `.dproj` (`DCCReference`) e, se for do núcleo, no `tests/CoreTests.dpr`.**
- **Testes do núcleo** (123 verificações hoje, 0 falhas):
  ```bash
  cd tests; T="$TEMP/NecoBuild/tests"; mkdir -p "$T"
  "/c/Program Files (x86)/Embarcadero/Studio/37.0/bin/dcc64.exe" -B -Q -NSSystem\;Winapi\;System.Win \
    -E"$(cygpath -w "$T")" -NU"$(cygpath -w "$T")" CoreTests.dpr && "$T/CoreTests.exe" | tail -3
  ```
- **Codificação:** os `.pas`/`.dpr` são UTF-8 com BOM e CRLF. Use Edit/Write, nunca `sed -i`.
  Confira depois: `LC_ALL=C grep -c "$(printf '\357\277\275')" arquivo` tem que dar 0.
  Hoje um script Python em heredoc falhou por causa das `\` nos caminhos do `.dpr`; para esses
  arquivos, prefira a ferramenta Edit.
- **App:** `tools/neco.ps1 abrir|fechar|tela|teclas|mem` (leia o aviso no topo: `teclas` e
  `tela` trazem a janela para a frente, então combine com o usuário antes). `NECO_TRACE=<arquivo>`
  liga o rastro, e `NECO_DADOS=<pasta>` usa um perfil separado (use isso nos seus testes para
  não mexer nos dados do usuário). `tools/medir.ps1` mede os tempos de abertura. Atenção:
  `neco.ps1` acha a janela por `FindWindow('FMTFormMain')`, que só pega a **primeira**; com
  várias janelas, ele precisa de ajuste.
- **Memória:** `tools/neco.ps1 mem` e o medidor interno (botão de memória na barra). A
  referência anterior do exe é ~35 MB (relatório de 2026-11-10 09:18).

## 6. Graphify depois de cada etapa

O usuário pediu atualização ao fim de toda alteração. Hoje o `--update` foi feito assim, e
funcionou:
- Deixe de fora `data/blocklist-hosts.txt` e os PNGs de `NecoBrowser.Artwork/` (memória do
  projeto). Com isso a mudança fica só em código, sem extração por LLM.
- Extração AST dos `.pas`/`.dpr` mudados, `build_merge` sobre `graphify-out/graph.json`,
  recluster e nomes das comunidades novas. As antigas mantêm o nome que já tinham (dá para
  pegar pelo `community_name` dos nós no grafo anterior). Depois `graphify export html`.
- O passo a passo da skill está em `C:\Users\user02\.claude\skills\graphify\references\update.md`.

## 7. Memória do projeto

As notas ficam em
`C:\Users\user02\.claude\projects\C--Users-user02-Desktop-Projetos-Teste-NecoBrowser\memory\`
(índice em `MEMORY.md`). Hoje entrou `necobrowser-ublock-extensao.md`. Ao fim de cada etapa,
atualize ou crie uma nota de projeto sobre a multi-janela, com datas absolutas.

## 8. Ao terminar ou interromper

Siga a regra 6 do README da ponte: registre o que terminou, o que ficou pendente e como
reproduzir o estado. O jeito mais simples é um handoff novo em `docs/` com a tag da última
etapa concluída. Depois remova o lock.
