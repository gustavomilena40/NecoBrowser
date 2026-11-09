# NecoBrowser — handoff da fase 1: etapas 1 a 3 feitas, 4 a 7 pendentes

- **De:** Claude Code, sessão `ca576c7e-4f0d-4e1f-a2fb-a49ae812d504`, em 2026-11-09 10:39 (-03).
- **Para:** o próximo agente que continuar a fase 1.
- **Precedência:** este documento vence qualquer mensagem anterior sobre o NecoBrowser.
  O plano original continua valendo no que este documento não muda:
  `docs\2026-11-09_09-37-20_claude_para_claude_plano-fase1-windows.md`. Leia os dois inteiros.
- **Motivo da troca:** o contexto da sessão anterior ficou grande. Não houve bloqueio técnico.

## 1. Antes de começar

1. Faça as leituras obrigatórias do plano (regras Delphi, README da ponte, skill `delphi-fmx-visual`).
2. Crie o lock `C:\Users\user02\.agent-bridge\locks\NecoBrowser.lock.md`. O lock da sessão anterior
   foi removido no fim do handoff.
3. Confira o estado: `git log --oneline` e `git status` (precisa vir limpo). O projeto está sob Git
   local, sem remoto. Faça um commit por etapa, com o trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## 2. O que já está feito

| Commit | Conteúdo |
| --- | --- |
| `59a7c0c` | Etapa 1: projeto FMX Win64/Win32, `.gitignore`, `redist\` com as DLLs, baseline de **0 avisos**. |
| `df0bed9` | Etapa 2: `src\core` + `tests\CoreTests.dpr`. O núcleo compila em Android64 (`dccaarm64`). |
| `c2bb28f` | Etapa 3: `INecoEngine`, motor WebView2, `TNecoTab` e o form com barra de ferramentas, endereço e progresso. |
| `372c4dc` | Google como busca e página inicial padrão (decisão do usuário), rastro de tempos, URL pela linha de comando. |
| (handoff) | `tools\` com os scripts de apoio e este documento. |

Testado na execução real (Win32): a página inicial abre em modo escuro, a busca com acento vai para
a URL certa, e voltar/avançar/recarregar/parar funcionam. O usuário usou o app à mão e achou rápido.

### Arquivos

```
NecoBrowser.dpr / .dproj / .res      .res = cabeçalho vazio de 32 bytes, igual ao que a IDE gera para FMX
src\core\   Neco.Core.Url, Files, Blocklist, Bookmarks, History, Settings, Trace (sem FMX e sem Winapi)
src\engine\ Neco.Engine.Intf (INecoEngine, INecoDownload, TNecoEngineBase)
            Neco.Engine.WebView2 ({$IFDEF MSWINDOWS})   Neco.Engine.Factory
src\ui\     Neco.UI.Theme (paleta, ícones Lucide, TNecoIconButton)   Neco.UI.Tab   Neco.UI.Main(.fmx)
tests\      CoreTests.dpr + rodar-testes.cmd (55 verificações, 0 falhas)
tools\      build.sh, bomcrlf.py, neco_icones.py, neco.ps1, medir.ps1 (seção 5)
data\blocklist-hosts.txt   PROVISÓRIO: só um comentário. A etapa 5 troca pela lista real.
redist\Win32|Win64\WebView2Loader.dll   do EdgeView2 SDK 1.0.3065.39 (GetIt)
```

## 3. O que falta (etapas 4 a 7) e o que já está preparado

**Etapa 4 — abas.**
- Já existe:
  - `FTabs`, `NewTab`, `ActivateTab` (só a aba ativa visível) e `CloseTab` (síncrono: quem chama de dentro de um evento precisa adiar);
  - Ctrl+W ligado.
- `TNecoTab` já tem os campos públicos `Button`, `TitleLabel` e `CloseButton`, para a faixa de abas (ainda não criada).
- **Falta:**
  - a faixa de abas (altura `CTabStripHeight`, cor `Palette.Window`, aba ativa em `Palette.Toolbar`);
  - o botão "+";
  - Ctrl+T, Ctrl+Tab e Ctrl+Shift+Tab em `HandleShortcut`;
  - `TabNewWindow` abrir aba nova (hoje navega na mesma aba);
  - título na aba com `DisplayTitle`.
- **Cuidado:** o X da aba não pode liberar a aba dentro do próprio OnClick (regra 5.3; o `MouseUp` do
  `TNecoIconButton` chama `Restyle` depois). Feche com `TThread.ForceQueue`.

**Etapa 5 — bloqueador.**
- Já existe:
  - o filtro: `TNecoTab.FilterRequest`, que consulta `FBlocklist`;
  - o contador `BlockedCount`, que zera a cada navegação principal e dispara `tcBlocked`;
  - `Settings.BlockerEnabled`;
  - `ICO_ESCUDO` e `ICO_ESCUDO_OFF`.
- **Falta:**
  - baixar a lista real (StevenBlack unificada, formato hosts) para `data\blocklist-hosts.txt`;
  - o selo com o contador na barra e o liga/desliga.
- **Melhoria opcional:** registrar `AddWebResourceRequestedFilter` só com o bloqueador ligado e a lista
  não vazia. Hoje ele é registrado sempre. O custo medido foi baixo (seção 4), então isso não é urgente.

**Etapa 6 — downloads e favoritos.**
- Já existe:
  - `INecoDownload` / `TNecoWV2Download`, que vivem fora da aba e se desligam sozinhos ao terminar;
  - o evento `TabDownload`, hoje vazio;
  - o núcleo `TNecoBookmarks`, com Toggle e JSON atômico;
  - `ICO_BAIXAR`, `ICO_MARCADOR`, `ICO_ESTRELA` e `ICO_PASTA`.
- Os painéis são laterais (`CSidePanelWidth`), filhos de `FBody` com `Align = Right`, e **encolhem**
  `FPageArea`. O `OnResized` de `FPageArea` já reposiciona o motor.

**Etapa 7 — tema e acabamento.**
- `NecoSetTheme` e `ApplyTheme` existem; a paleta clara também.
- **Falta:**
  - o botão de tema;
  - reaplicar `SetDarkMode` em todas as abas.
- **Pedidos do usuário nesta sessão:**
  - uma tela simples de configurações para escolher o motor de busca (Google, DuckDuckGo, e talvez
    DuckDuckGo HTML), com Google como padrão;
  - uma **página de erro amigável** quando a navegação falhar: domínio inexistente levou 16,8 s até
    o fim e não mostrou nada claro. Use `OnNavigationCompleted(ASuccess=False)`; dá para pegar o
    `WebErrorStatus` em `ICoreWebView2NavigationCompletedEventArgs` se quiser a causa.
- **Fim da fase:**
  - relatório final em `docs\`;
  - remover o lock;
  - medição de memória com 20 abas (regra 3.3: em repouso, mesma fase do ciclo). **Ainda não foi feita.**

## 4. Fatos verificados que custaram tempo (não refaça)

- **`TargetCompatibleBrowserVersion` vazio = `E_INVALIDARG` (0x80070057)** em
  `CreateCoreWebView2EnvironmentWithOptions`. Usamos `'137.0.3296.44'`, a mesma do `Vcl.Edge` no Delphi 13
  (`CTargetBrowserVersion` em `Neco.Engine.WebView2`).
- `CreateCoreWebView2EnvironmentWithOptions` e o carregamento da DLL vêm do `Winapi.EdgeUtils`, e não do
  `Winapi.WebView2`. Existem `ICoreWebView2_4` a `_27`, `Controller2..4` e `Profile..8`: nenhum fallback foi preciso.
- O import do Delphi usa `HResult`, e não `safecall`. Strings `PWideChar` devolvidas pelo WebView2 precisam de
  `CoTaskMemFree`: use o `TakeStr`.
- Parâmetro chamado `result` num handler COM colide com o `Result` da função (E2004). Renomeie.
- O FMX já chama `OleInitialize` na inicialização de `FMX.Platform.Win`: a thread principal já está em STA.
- A janela do FMX já tem `WS_CLIPCHILDREN`. O `TForm` tem `DoScaleChanged` virtual, usado para recalcular
  os limites do motor ao trocar de monitor ou de escala.
- Teclado no FMX:
  - o controle com foco recebe a tecla **antes** do `OnKeyDown` do form;
  - Tab e Ctrl+Tab são consumidos para trocar o foco.
  Por isso os atalhos ficam num `override` de `KeyDown` (público), antes do `inherited`. Com o foco na
  página, as teclas chegam pelo `AcceleratorKeyPressed` → `TabKey` → `HandleShortcut`, e toda ação é
  adiada com `ForceQueue`.
- A janela do form é subclassada (`NecoParentSubclass`) para:
  - avisar `NotifyParentWindowPositionChanged` quando a janela se move;
  - devolver o foco do teclado ao form quando o clique cai na parte FMX (a página é outra janela).
- **Nome em conflito:** com `System.IOUtils` no `uses` da implementação, `TPath` vira o do IOUtils.
  Qualifique: `FMX.Objects.TPath` / `System.IOUtils.TPath`.
- `TFunc<string, Boolean>` não aceita método com parâmetro `const`. Por isso `FilterRequest(AUrl: string)` não usa `const`.
- Os `.res` FMX gerados pela IDE são só o cabeçalho vazio. `brcc32` não aceita o ícone moderno, e o `cgrc` exige `rc.exe`.
- No `.dproj`, `$(PROJECTDIR)`/`$(OUTPUTDIR)` vêm vazios no msbuild (avaliados antes dos targets). O post-build
  usa `$(MSBuildProjectDirectory)` e `$(DCC_ExeOutput)`.
- O `.gitignore` ancora `/Win32/` e `/Win64/` na raiz; sem isso, `redist\Win32` e `redist\Win64` saem do Git.
- Medição (rastro NECO_TRACE, Win32, uso manual do usuário):
  - abrir o app até o controller pronto: ~600 ms;
  - páginas comuns: 1 a 2,3 s;
  - tempo total no filtro de requisições por página: 0,1 a 9,6 ms (para 26 a 101 requisições).
  A lentidão que o usuário sentiu era o DuckDuckGo montando os resultados por JavaScript, e não o navegador.

## 5. Como compilar, testar e rodar

- **Build:** `bash tools/build.sh <etiqueta>`. Faz três coisas:
  - normaliza BOM/CRLF de todos os fontes;
  - compila Win64 e Win32 em `%TEMP%\NecoBuild\<etiqueta>-win64|-win32`;
  - compara os avisos com `%TEMP%\NecoBuild\base-*.log` (baseline 0).
  O Win64 sempre cai no fallback do MSB6003, que não roda o post-build; por isso o script copia a DLL
  e a lista para a saída Win64.
- **Testes do núcleo:** `tests\rodar-testes.cmd`. O código de saída é o número de falhas.
- **Arquivos novos:** UTF-8 com BOM e CRLF. `tools\bomcrlf.py` faz a conversão e confere (o Write grava sem BOM e com LF).
  Exceções: `.cmd` com CRLF **sem** BOM; `.sh` com LF **sem** BOM (o bash quebra com os dois).
  O `.gitattributes` fixa o fim de linha desses dois.
- `Sprites\Neco Arc Sprites.zip` é do usuário e está fora do Git de propósito: pergunte antes de versionar ou usar.
- **Ícones:** `python -I tools\neco_icones.py` gera as constantes. Ele usa o conversor da skill sem
  alterar o `icones.py` compartilhado; acrescente os SVGs novos no dicionário `NOVOS`.
- **Rastro de tempos:** `$env:NECO_TRACE='arquivo.txt'` antes de abrir o exe. `tools\medir.ps1` abre o exe
  com uma URL, espera o fim da navegação e fecha.
- **Prints:** o `PrintWindow` do `ui.ps1` **não captura o WebView2** (sai só a parte FMX). Use
  `tools\neco.ps1 tela`, que copia da tela com a janela em primeiro plano.
- **Combine com o usuário antes de dirigir a interface.** `neco.ps1 teclas`/`tela` e os cliques trazem a
  janela para a frente. Nesta sessão o usuário estava digitando ao mesmo tempo, e parte do texto caiu no
  lugar errado. Ele também preferiu testar à mão: abra o exe para ele, peça que avise quando terminar e
  leia o rastro depois.

## 6. Desvios do plano (registrar no relatório final)

- Units a mais, não previstas no plano:
  - `Neco.Core.Files`: gravação atômica e leitura de JSON;
  - `Neco.Core.Trace`: diagnóstico;
  - `Neco.UI.Theme`: tokens e botão.
- A tela é montada em código, como a skill recomenda. Os painéis de downloads e favoritos devem seguir
  o mesmo caminho (sem `.fmx` próprio), embora o plano cite `.fmx` para eles.
- O plano dizia que faltava a `WebView2Loader.dll`. Ela já estava instalada (o GetIt já tinha o SDK).
- Página inicial e busca padrão: Google, e não DuckDuckGo (decisão do usuário).
- `INecoEngine` ganhou, além do contrato do plano: `Blur`, `IsReady`, `IsLoading`, `GetUrl`/`GetTitle`,
  `SetDarkMode`, `Close`, `OnReady`, `OnError`, `OnHistoryChanged` e `OnGotFocus`.
