# NecoBrowser: relatório final do multi-janela (Etapas 2 a 8)

- **De:** Claude Code (sessão `session_016LXiuQAtQtZv3K2eqVqXnT`), 2026-11-11.
- **Plano:** `docs/2026-11-10_16-07-30_claude_plano-multi-janela.md`. A Etapa 1 tem relatório
  próprio: `docs/2026-11-11_10-37-49_claude_relatorio_etapa1-prova-multi-janela.md`.
- **Branch:** `multi-janela`, tags `mj-etapa0` a `mj-etapa7`. O merge na `main` espera o ok do
  usuário. Nada foi enviado ao GitHub.
- **Resultado:** o navegador abre N janelas num processo só. Uma janela extra custa uns 3,5 MB
  do navegador, contra uns 77 MB quando cada janela era um exe. Abas passam de uma janela para
  outra com a página viva, pelo menu ou arrastando como no Chrome.

## Como foi aprovado

O usuário testou e aprovou as Etapas 2 e 3. Depois pediu para terminar o plano de uma vez, então
as Etapas 4 a 7 têm só os testes automáticos abaixo. O teste manual delas ficou para o fim, junto,
antes do merge.

## O que cada etapa entregou

| Etapa | Commit | O que mudou |
|---|---|---|
| 2 | `40c10fb` | `TNecoApp` (`src/ui/Neco.UI.App.pas`) guarda o que é do navegador inteiro (dados, motor, atualizador, uBOL, medidor de memória). As janelas recebem os avisos pela interface `INecoWindow` |
| 3 | `7a378ab` | Barra de título por janela: o estado da barra fica num registro no `dwRefData` da subclasse e é liberado no `WM_NCDESTROY` |
| 4 | `682d06e` | Ctrl+N e "Nova janela"; "Sair" (Ctrl+Shift+Q) fecha todas e grava todas. Sessão v2 com as janelas, posição e maximizada (lê o formato 1). Botão próprio na barra de tarefas. A Neco anima só na janela atual |
| 5 | `5aa7a31` | Uma instância por perfil (`src/ui/Neco.UI.Instance.pas`): a segunda execução manda a linha de comando por `WM_COPYDATA` e sai em cerca de 70 ms |
| 6 | `f045dd7` | Botão direito na aba: "Mover para nova janela", "Mover para: …", "Fechar aba". Downloads em andamento acompanham a aba quando a janela de origem fecha |
| 7 | `e30cd30` | Arrastar e soltar: a aba sai para uma janela que segue o mouse; com uma aba só, arrasta a janela; a faixa de destino mostra onde a aba entra; Esc devolve a aba |

## Medição (Etapa 8)

Mesmo computador e mesma hora, perfil novo (`NECO_DADOS`), `https://example.com/` em cada janela,
30 s de repouso antes de medir. A medição é app mais os processos do WebView2 desse perfil.
Script: `medir_v2.ps1` (scratchpad da sessão).

| | 1 janela | 3 janelas | custo das 2 extras |
|---|---|---|---|
| Antes: exe `mj-0`, uma janela por exe | 490 MB WS, 270 MB priv | 713 MB WS, 378 MB priv | +223 MB WS, sendo +155 MB do exe |
| Agora: exe `mj-7b`, um processo | 484 MB WS, 263 MB priv | 622 MB WS, 336 MB priv | +138 MB WS, sendo +7 MB do exe |

- **Meta do plano cumprida:** a janela extra não custa mais um exe. A parte do NecoBrowser caiu
  de uns 77 MB para uns 3,5 MB por janela.
- **O que sobra é do WebView2:** +131 MB nas 2 janelas, contra +68 MB antes. A diferença está
  dentro da variação entre execuções (antes eram 8 processos do motor, agora 9). Esta medição não
  decide se a parte do motor mudou; só a parte do app ficou clara.

## Testes automáticos

Todos usam um perfil temporário. O rastro (`NECO_TRACE`) é a prova de cada passo.

- **Etapa 4:**
  - sessão v2 gravada à mão com 3 janelas, uma delas maximizada: as 3 voltaram no lugar;
  - fechei a 1ª, a do meio e a última: o app ficou vivo até a última e saiu com código 0;
  - a última janela, maximizada, gravou a posição de antes de maximizar.
- **Etapa 5:**
  - a segunda execução com endereço, sem argumento e com arquivo de caminho relativo (noutra pasta) virou aba no processo aberto;
  - `NECO_DADOS` diferente continuou separado.
- **Etapa 6 (`NECO_TESTE_MOVER=1`):**
  - a aba ainda não carregada foi para uma janela nova e carregou lá;
  - voltou sem navegação nova, e a janela vazia fechou.
- **Etapa 7:** com o mouse simulado, com o computador parado havia 13 minutos:
  - aba tirada de uma janela com 3 e solta na faixa de outra: juntou e a janela temporária fechou;
  - Esc no meio do arrasto: a aba voltou.
- **CoreTests:** 128 verificações, 0 falhas (5 novas da sessão v2: ida e volta, v1 antigo, arquivo quebrado, campos errados).
- **Compilação:** Win64 e Win32 com 0 avisos em todas as etapas; nenhum U+FFFD nos arquivos tocados.

## Achados no caminho

1. **O placement do Windows devolve posição velha** (`GetWindowPlacement.rcNormalPosition` ficou
   com a posição de quando a janela foi criada). Com a janela restaurada, a posição gravada agora
   vem do `GetWindowRect` (`NecoFrameGetPlacement`).
2. **Janela em 0,0 não voltava lá.** Para o FMX, 0,0 é a posição de projeto do `.fmx`, e ao exibir
   ele põe a janela no lugar padrão. `NecoFrameSetPlacement` agora usa `Position := Designed`.
3. **Controller do WebView2 pedido numa janela e aba movida antes de ele nascer:** ele nasceria
   na janela antiga. O motor guarda a janela do pedido e corrige ao nascer.
4. **O download tem um ouvinte só** (`OnChanged`): a linha antiga é solta antes da nova
   (`TakeInProgress`).
5. **SendKeys não serve para testar:** o Windows não deixa o script pôr a janela em primeiro plano.
   Os testes usam ganchos por variável de ambiente (`NECO_TESTE_JANELA`, `NECO_TESTE_MOVER`).

## Riscos abertos

- **Sem teste com o usuário:** Etapas 4 a 7 (o teste manual está no fim deste relatório).
- **DPI diferente entre monitores e arrasto entre monitores:** sem teste (um monitor só).
- **Janela semitransparente durante o arrasto** (`WS_EX_LAYERED` com a página do WebView2 dentro):
  o teste automático não olha a tela. Se a página sumir ou piscar, tirar `NecoFrameSetTranslucent`
  não muda mais nada.
- **Fechar janelas uma a uma pelo X** (inclusive "Fechar todas as janelas" da barra de tarefas)
  grava só a última, como no Chrome. "Sair" grava todas.
- **Reinício para atualizar** passou a fechar todas as janelas (`CloseAllWindows`). O caminho do
  `--apos-atualizar` não mudou e foi testado na Etapa 2, mas não de novo com várias janelas.
- Limites do plano mantidos: fechar janela com download cancela (salvo quando a aba muda de
  janela), `window.open` com tamanho abre como aba, sem "reabrir janela fechada".

## Teste manual pedido ao usuário (antes do merge)

1. Ctrl+N três vezes, posições diferentes e uma maximizada. **Sair** e reabrir: as janelas voltam no lugar.
2. Tema e configurações mudados numa janela aparecem nas outras; favorito novo aparece na barra de todas.
3. Com o navegador aberto, clicar num link de outro programa e abrir um PDF por "Abrir com":
   vira aba, sem segundo processo no Gerenciador de Tarefas.
4. Botão direito numa aba com vídeo tocando → "Mover para nova janela": o vídeo continua tocando.
5. Arrastar uma aba para fora (janela com 5), devolver à janela de origem, juntar 3 janelas numa,
   arrastar para uma janela maximizada, Esc no meio do arrasto, e clique simples sem virar arrasto.
6. Fechar tudo: sem aviso de vazamento.
