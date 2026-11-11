# NecoBrowser — multi-janela, Etapa 1: prova técnica

- **De:** Claude Code (sessão `session_016LXiuQAtQtZv3K2eqVqXnT`), 2026-11-11.
- **Plano:** `docs/2026-11-10_16-07-30_claude_plano-multi-janela.md`.
- **Resultado:** todas as perguntas que puderam ser testadas deram **sim**. O caminho do plano
  segue sem saídas alternativas, com uma exceção sem teste (DPI, abaixo).

## Respostas

| Pergunta | Resposta | Como foi verificado |
|---|---|---|
| Duas `TFormMain` no mesmo processo: barra de tarefas, Alt+Tab, foco e teclado | **Sim**, com ajuste | Usuário (Ctrl+N) e verificação automática dos estilos das janelas |
| Fechar a 1ª janela sem derrubar a 2ª | **Sim** | Usuário e automático: `Application.MainForm` passa para a outra no `FormClose` |
| Página viva troca de janela (`Set_ParentWindow`) | **Sim** | Usuário: vídeo do YouTube continuou tocando, Voltar e Ctrl+T funcionaram. Rastro: nenhuma navegação nova depois da troca |
| Monitores com DPI diferente | **Sem teste** | O usuário tem um monitor só. O código já recalcula a área da página pela escala da janela de destino (`LayoutEngine` usa `Handle.Scale`). Risco aberto |
| Arrasto nativo (`ReleaseCapture` + `WM_NCLBUTTONDOWN/HTCAPTION`) | **Sim** | Usuário: a aba sai para uma janela nova que segue o mouse; com uma aba só, arrasta a janela inteira |

## Achados que mudam o código das próximas etapas

1. **O FMX prende toda janela de form à janela oculta do app** (`FMX.Platform.Win`,
   `DefineParentWnd` usa `ApplicationHWND` como dono). É essa janela oculta que tem o botão na
   barra de tarefas, então duas janelas dividiriam um botão só. `NecoFrameMakeIndependent`
   (`Neco.UI.Frame`) tira o dono, põe `WS_EX_APPWINDOW` e esconde a janela do app.
   A Etapa 4 chama isso em toda `TFormMain`.
2. **A aba não capturava o mouse** (`TControl.AutoCapture` é `False` por padrão). O arrasto só
   funcionava enquanto o cursor ficava sobre a aba. Corrigido em `BuildTabButton`.
3. **Vazamento antigo nos atalhos**, achado pelo usuário: `TFormMain.HandleShortcut$ActRec`. A ação
   anônima e a variável capturada pelo `ForceQueue` ficavam no mesmo quadro (ciclo de
   referências). Reproduzido com um Ctrl+T automático e corrigido separando a escolha da ação em
   `ShortcutAction`.
4. **O import da RTL declara `Set_ParentWindow(wireHWND)`** (ponteiro), mas a função nativa recebe
   o HWND por valor. O valor vai convertido (`Neco.Engine.WebView2`, `SetParentWindow`).

## O que fica no código (o resto da prova foi apagado)

- `INecoEngine.SetParentWindow` e `NecoEngineMoveToForm` (Etapa 6).
- `NecoFrameMakeIndependent` e `NecoFrameStartSystemDrag` (Etapas 4 e 7).
- `AutoCapture` nas abas e a correção do vazamento dos atalhos.

## Verificação

- Build Win64 e Win32 com 0 avisos (`mj-1-final`), CoreTests 123/0, sem U+FFFD.
- Janela única aberta e fechada com código 0, sem relatório de vazamento.
- Referência de memória da Etapa 0 (perfil novo, example.com): 1 janela = 492 MB de WS no total;
  3 janelas (3 exes) = 732 MB, ou seja, cerca de 78 MB de WS (48 MB privados) por exe extra.

## Observação do usuário para depois

Uma tela que liste todos os atalhos (ele não lembrava do Ctrl+L nem do Ctrl+Shift+T). Fica fora do
plano; pode entrar como item pequeno depois da Etapa 8.
