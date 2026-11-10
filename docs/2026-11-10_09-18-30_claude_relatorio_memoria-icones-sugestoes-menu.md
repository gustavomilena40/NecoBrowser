# NecoBrowser — medidor de memória, ícone nas abas, sugestões da barra e menu da seta

- **De:** Claude Code, 2026-11-10.
- **Base:** relatório `2026-11-09_15-30-00_claude_relatorio-final-fase1.md`.
- **Estado:** compila em Win64 e Win32 com 0 erros e 0 avisos (baseline 0). Testes do núcleo:
  97 verificações, 0 falhas (13 novas). O usuário compilou e testou as quatro funções no
  aparelho dele: "deu certinho".

## 1. Medidor de memória

**Pedido:** o Gerenciador de Tarefas do Windows mostra o NecoBrowser com ~35 MB, e as páginas
ficam de fora.

**O que se descobriu (medido nesta máquina, Windows 11 23H2):**
- a árvore de processos está certa: `NecoBrowser.exe` → `msedgewebview2.exe` (browser) →
  renderers, GPU, rede, áudio etc.;
- o WebView2 está dentro da janela do form;
- mesmo assim, o Gerenciador põe todos os processos do WebView2 num grupo próprio em
  "Processos em segundo plano", chamado "Gerenciador WebView2 (15)" (~930 MB naquela hora).
  O Teams e o Widgets, da própria Microsoft, também ficam separados;
- conclusão: o app não consegue juntar os dois grupos. A solução foi medir dentro do navegador.

**O que foi feito:**
- `Neco.Engine.Intf`: `TNecoMemoryReport` (App, Browser, Pages, Gpu, Other, Processes, Tabs,
  `Total`) e `INecoEngine.OpenTaskManager`.
- `Neco.Engine.WebView2`: `NecoWV2QueryMemory`.
  - Usa `ICoreWebView2Environment13.GetProcessExtendedInfos` (assíncrono) para listar os
    processos e saber qual renderer desenha qual aba: sobe pelos pais do quadro
    (`ICoreWebView2FrameInfo2`) até o quadro principal e compara com
    `ICoreWebView2_20.FrameId`. Um processo dividido entre abas entra em partes iguais em cada
    uma.
  - Em runtime antigo, usa `ICoreWebView2Environment8.GetProcessInfos`: só dá o total.
  - A memória de cada processo é o conjunto de trabalho privado
    (`PROCESS_MEMORY_COUNTERS_EX2`, via `K32GetProcessMemoryInfo`), o mesmo número da coluna
    "Memória" do Gerenciador de Tarefas.
- `Neco.Engine.Factory`: `NecoEngineQueryMemory`.
- Tela:
  - botão com o total na barra, atualizado a cada 2 s (parado com a janela minimizada);
  - o balão do botão mostra a divisão por tipo de processo;
  - clicar abre o gerenciador de tarefas do WebView2;
  - o balão de cada aba mostra a memória dela.

## 2. Ícone do site nas abas

- `TImage` de 16×16 à esquerda do título, igual às pílulas dos favoritos.
- Usa o favicon que o motor manda. Numa aba restaurada que ainda não carregou, usa o ícone
  guardado em disco, que só existe para sites dos favoritos.
- O motor agora avisa também quando o favicon vem vazio, para a aba tirar o ícone da página
  anterior. `StoreFavicon` já ignorava ícone vazio.

## 3. Sugestões na barra de endereço

**Pedido:** buscar de novo algo já buscado sem digitar tudo outra vez.

- `TNecoHistory` (núcleo, testado):
  - guarda as buscas digitadas (`AddTyped`: texto, contagem, última vez; no máximo 500) no
    mesmo `history.json`, chave `typed`. Um arquivo antigo sem a chave carrega vazio;
  - `Suggest` devolve primeiro as buscas que começam com o texto (mais usadas e recentes
    antes), depois as páginas visitadas que casam pelo endereço (sem esquema e sem `www.`) ou
    pelo título;
  - não diferencia maiúsculas nem acentos;
  - páginas de resultado de busca não entram;
  - `Clear` apaga as buscas também.
- Só entra em `AddTyped` o que vira busca (`NecoInputToUrl(T) = NecoSearchUrl(T)`).
  Endereço digitado já fica no histórico de páginas.
- Tela:
  - a lista é um `TPopup`, que no Windows é uma janela própria (`WS_EX_NOACTIVATE`): fica
    por cima da página nativa e não tira o foco da barra;
  - ↑/↓ andam pela lista e preenchem a barra, Enter abre, o primeiro Esc volta ao que foi
    digitado, clicar numa linha também abre;
  - o tamanho muda com `PopupFormSize`, porque `Width`/`Height` não redimensionam o popup
    já aberto.

## 4. Menu da seta

**Pedido:** oito botões ao lado da barra era demais; ficar só com RAM | seta | configurações.

- Bloqueador, favoritos, histórico, downloads, abrir arquivo e tema foram para um menu
  (`TPopup`, montado na hora de abrir), com o atalho ou o estado à direita de cada linha.
- O selo com o número de bloqueados passou do escudo para a seta.
- A seta fica marcada quando favoritos, histórico ou downloads estão abertos.
- O FMX fecha o menu num clique fora dele dentro do form. Clique na página e Esc foram
  tratados à mão (`TabPageFocus` e `KeyDown`).
- As ações rodam por `TThread.ForceQueue`, porque não se fecha o popup dentro do clique de
  uma linha dele (regra 5.3).

## Arquivos

`Neco.Core.History`, `Neco.Engine.Intf`, `Neco.Engine.WebView2`, `Neco.Engine.Factory`,
`Neco.UI.Main`, `Neco.UI.Tab`, `Neco.UI.Theme`, `tests/CoreTests.dpr`.

Ficaram fora do commit, por já estarem modificados ou soltos antes desta sessão:
`NecoBrowser.dproj`, `NecoBrowser.res`, `NecoBrowser.Artwork/`, `Sprites/`.
