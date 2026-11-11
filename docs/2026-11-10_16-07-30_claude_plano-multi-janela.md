# Plano: várias janelas num processo só + arrastar abas entre janelas

## Contexto

Hoje cada janela do NecoBrowser é um `NecoBrowser.exe` separado (~35 MB cada, medido em
`docs/2026-11-10_09-18-30_...memoria...md`). O `.dpr` cria um único `TFormMain`, e tudo que é
do app inteiro mora dentro dele: configurações, favoritos, histórico, lista de bloqueio,
atualizador, extensão uBOL, sessão e a trava de instância (`FSessionOwner`). A barra de
título (`Neco.UI.Frame`) guarda o estado de **uma** janela em variáveis globais.

Objetivo: um processo com N janelas. Isso economiza ~35 MB por janela extra e permite
**arrastar uma aba para fora (vira janela nova) e para dentro de outra janela (junta)**, com a
página viva: vídeo continua, histórico de voltar continua, nada recarrega.

O que o levantamento confirmou que já ajuda:
- O motor já aceita várias janelas-mãe (`GHooked`, `NecoParentSubclass` em
  `src/engine/Neco.Engine.WebView2.pas`), e o WebView2 tem `ICoreWebView2Controller.Set_ParentWindow`.
- `TNecoTab` (`src/ui/Neco.UI.Tab.pas`) quase não depende do form: só o motor nasce com o
  HWND dele, e os eventos são ponteiros religáveis.
- Tema (`Palette`) e sprites da Neco (`GAnims`) são globais de leitura: podem ser divididos.
- O FMX deixa trocar `Application.MainForm` (`FMX.Forms.pas:2273`), e o `DoClose` roda antes
  da checagem que encerra o app (`FMX.Forms.pas:3284`). Dá para fechar a janela principal
  sem derrubar as outras.
- Os painéis recebem os dados por propriedade (`FPanelBookmarks.Bookmarks := ...`), então dá
  para apontá-los para objetos do app.

## Regras da execução

- Branch `multi-janela`. **Etapa 0 commita o estado atual** (uBOL e o resto ainda sem
  commit) como base. Cada etapa termina num commit com tag `mj-etapaN`. Aprovar este plano
  vale como autorização para esses commits locais; nada é enviado ao GitHub.
- Ao fim de cada etapa: `bash tools/build.sh mj-N` (Win64 e Win32, **0 avisos**, como a base
  de hoje), testes do núcleo (`tests/CoreTests.dpr`, compilado com dcc64 numa pasta
  temporária), checagem de acentos (`grep` de U+FFFD = 0) e o roteiro manual da etapa.
- O roteiro manual é seu: eu compilo e preparo o exe em `%TEMP%\NecoBuild\mj-N-win64`, você
  testa e me diz o resultado. Só passo para a próxima etapa com a anterior aprovada.
- Encerramento limpo: o app já roda com `ReportMemoryLeaksOnShutdown := True`. Fechar sem
  relatório de vazamento faz parte de toda etapa.
- `/graphify --update` e uma nota na memória ao fim de cada etapa.

## Plano para quando falhar (vale para todas as etapas)

1. **Não compila ou aparecem avisos novos:** corrijo antes de te entregar. Etapa nenhuma sai
   com aviso acima da base.
2. **Regressão no seu teste:** corrijo dentro da etapa e você testa de novo. Se em duas
   tentativas não ficar bom, ou se a causa não estiver clara, **paramos**: volto para a tag
   da etapa anterior (`git reset --hard mj-etapa<N-1>`, só com o seu ok), escrevo o que deu
   errado e replanejamos aquela etapa.
3. **Um pressuposto técnico falha** (a página não sobrevive à troca de janela, o FMX não deixa
   duas janelas etc.): cada risco tem uma saída já definida na Etapa 1 (tabela abaixo).
   Nenhuma saída força desfazer as etapas anteriores.
4. **Bug achado depois, já em etapa avançada:** `git bisect` entre as tags acha a etapa que
   introduziu o bug.

---

## Etapa 0 — Base

- Commit do estado atual na `main` (uBOL, atualizador, navegador padrão etc.), depois cria a
  branch `multi-janela` e a tag `mj-etapa0`.
- Medição de referência com o exe atual: memória com 1 e 3 janelas (`tools/neco.ps1 mem` e o
  medidor interno). É o número que a Etapa 7 vai comparar.

## Etapa 1 — Prova técnica (decide o caminho)

Código provisório, atrás de uma variável de ambiente `NECO_MJ_PROVA`, para responder antes
de reestruturar:

| Pergunta | Como testo | Se falhar |
|---|---|---|
| Duas `TFormMain` no mesmo processo: duas entradas na barra de tarefas, Alt+Tab, foco e teclado certos? | Ctrl+N cria uma segunda `TFormMain` | Ajustar `WS_EX_APPWINDOW` / dono da janela. Se não houver jeito, o projeto para aqui, sem perda (só código de prova). |
| Fechar a 1ª janela sem derrubar a 2ª | No `FormClose`, trocar `Application.MainForm` | Janela oculta como principal fixa (o app nunca fecha pela janela). |
| Página viva troca de janela com `Set_ParentWindow` (vídeo continua, Voltar funciona, teclado e atalhos funcionam, tamanho certo) | Tecla de prova move a aba ativa para a outra janela | **Saída:** mover por URL (recarrega). Ainda ganha os 35 MB; só perde o "vivo". |
| Janelas em monitores com DPI diferente | Mover a aba entre monitores 100% e 150% | Recalcular `RasterizationScale` e os limites após a troca. |
| Arrasto nativo: iniciar o "mover janela" do Windows no meio do arrasto da aba (`ReleaseCapture` + `WM_NCLBUTTONDOWN/HTCAPTION`) | Prova com uma janela vazia | **Saída:** arrasto por soltura: uma miniatura da aba segue o mouse e a janela nova abre onde soltar. |

Entrega: um relatório curto com sim/não para cada linha e a decisão. O código de prova é
apagado no fim da etapa.

## Etapa 2 — Separar o que é do app do que é da janela (sem mudar comportamento)

Nova unit `src/ui/Neco.UI.App.pas` com `TNecoApp` (objeto único, criado no `.dpr` antes do form):
- Passam do `TFormMain` para ela: `FSettings`, `FBlocklist` (e o `LoadBlocklist`),
  `FBookmarks`, `FHistory`, `FClosed` (abas fechadas), `FUpdater` e o timer,
  `FAdExt` / `FAdFolder` / timer, trava de instância, `NecoEngineSetup`, `SaveData`,
  `FinishUpdate` e `NecoEngineShutdown`.
- Lista de janelas e avisos para todas elas: tema, configurações, favoritos, histórico,
  versão nova baixada, estado do bloqueador. As janelas se registram por uma interface
  `INecoWindow` (implementada pelo `TFormMain`, sem contagem de referência), o que evita
  dependência circular com `Neco.UI.Main`.
- `TNecoBookmarks.OnChange` (evento único) passa a ser tratado pela `TNecoApp`, que repassa
  a todas as janelas.
- O `BlockerOn` dado a cada `TNecoTab` passa a ser do app, não do form. Senão, a aba movida
  ficaria apontando para a janela antiga.
- Medidor de memória: um timer só no app, com o resultado distribuído às janelas. Hoje cada
  janela mediria tudo de novo.

**Testes:** build 0 avisos, CoreTests, e roteiro de regressão completo numa janela só (abrir,
abas, reordenar, favoritos, histórico, configurações, tema, bloqueador e uBOL, atualização
simulada com `NECO_UPDATE_URL`, restaurar sessão, tela cheia, fechar sem vazamento).
Nada pode mudar para quem usa.

## Etapa 3 — Barra de título por janela

`src/ui/Neco.UI.Frame.pas`: as globais (`GWnd`, `GForm`, `GHitTest`, `GMaxHover`,
`GMaxClick`, `GMaxHot`, `GTracking`, `GFull`, `GSaved*`) viram um registro por janela,
apontado pelo `dwRefData` do `SetWindowSubclass` e liberado no `WM_NCDESTROY`.
`NecoFrameDetach` passa a receber o form.

**Testes:** com duas janelas (Ctrl+N já liga aqui, ainda simples), cada uma com arrastar pela
faixa, duplo clique para maximizar, snap do botão maximizar no Windows 11 e tela cheia
(F11 e vídeo), tudo independente da outra.

## Etapa 4 — Várias janelas de verdade

- Ctrl+N e item "Nova janela" no menu da seta.
- Fechar janela fecha só as abas dela. A janela principal passa o posto para outra
  (`Application.MainForm`). A última janela dispara o encerramento da `TNecoApp`: grava a
  sessão, fecha o motor, aplica a atualização baixada.
- **Sessão v2** (`src/core/Neco.Core.Settings.pas`): lista de janelas, cada uma com abas,
  aba ativa, posição/tamanho e se estava maximizada. Continua lendo o formato v1 de hoje.
  Testes novos em `tests/CoreTests.dpr`: v2 ida e volta, v1 antigo lido, arquivo quebrado.
- Leveza: a Neco anima só na janela em primeiro plano. Nas outras, o timer dela para.
- Ctrl+Shift+T reabre na janela atual a última aba fechada em qualquer janela.

**Testes:** 3 janelas: fechar a primeira, a do meio e a última. Tema e configurações mudados
numa janela aparecem nas outras. Favorito criado numa aparece na barra de todas. Fechar e
reabrir restaura as 3 janelas no lugar. Sem vazamento ao fechar.

## Etapa 5 — Uma instância só

Nova unit `src/ui/Neco.UI.Instance.pas`: a primeira instância cria uma janela de mensagens
oculta, com nome derivado da pasta de dados (a mesma chave da trava de hoje). Uma segunda
execução (link clicado no Windows, "Abrir com", atalho) acha essa janela, manda os
argumentos por `WM_COPYDATA` e sai. A primeira abre uma aba na janela ativa e traz a janela
para a frente.
- O reinício pós-atualização (`--apos-atualizar`) continua esperando a trava, como hoje.
- `NECO_DADOS` diferente = perfil diferente = instância separada (os testes continuam
  isolados).

**Testes:** abrir o exe 2 vezes (um processo no Gerenciador de Tarefas e uma aba nova); link
de outro app com o NecoBrowser como padrão; PDF por "Abrir com"; reiniciar para atualizar
(com `NECO_UPDATE_URL`).

## Etapa 6 — Mover aba entre janelas (sem arrastar ainda)

- `INecoEngine.SetParentWindow(AWnd)` (`Neco.Engine.Intf.pas`, `Neco.Engine.WebView2.pas`):
  troca `FParentWnd`, chama `HookParent`, `Set_ParentWindow` e
  `NotifyParentWindowPositionChanged`. Se o controller ainda não existe, só troca o HWND.
- `TFormMain.DetachTab(T)` / `AdoptTab(T, Index)`: tira a aba da lista e solta os botões
  dela na janela de origem; recria os botões na de destino e religa os eventos da aba.
  Origem sem abas fecha.
- Menu de contexto da aba: "Mover para nova janela" e "Mover para a janela…". Também é a
  forma de usar sem mouse, e serve de saída se o arrasto der problema.

**Testes:** vídeo do YouTube tocando continua tocando depois de mover. Voltar e Avançar
funcionam. Aba com download em andamento (o download continua). Aba em tela cheia. Aba
ainda não carregada (da sessão restaurada). Mover a última aba fecha a janela de origem. Sem
vazamento ao fechar.

## Etapa 7 — Arrastar e soltar (como no Chrome)

Em `TabButtonMouseMove` (`src/ui/Neco.UI.Main.pas:1002`), quando o mouse sai da faixa de
abas por mais de ~30 px na vertical:
- **Janela com várias abas:** a aba sai para uma janela nova sob o cursor (Etapa 6) e o
  Windows assume o arrasto da janela nova. Esse é o caminho validado na Etapa 1; se a prova
  falhou, entra a miniatura que segue o mouse.
- **Janela com uma aba só:** arrastar a aba arrasta a janela inteira.
- Durante o arrasto (`WM_MOVING` na janela arrastada), se o cursor passa sobre a faixa de
  abas de outra janela, ela mostra onde a aba vai entrar. Ao soltar (`WM_EXITSIZEMOVE`)
  ali, a aba entra nela naquela posição e a janela arrastada fecha. É assim que se juntam
  janelas.
- Reordenar dentro da mesma faixa continua como hoje.

**Testes:** tirar uma aba de uma janela com 5. Devolver a aba à janela de origem. Juntar 3
janelas em uma. Arrastar com a janela de destino maximizada. Arrastar entre dois monitores.
Clique simples numa aba não pode virar arrasto. Esc durante o arrasto cancela.

## Etapa 8 — Medição e fechamento

- Medir de novo como na Etapa 0 (1 e 3 janelas). A meta é a janela extra não custar mais um
  exe.
- Relatório em `docs/` (padrão dos anteriores), atualização das notas de memória e do grafo,
  merge da branch na `main` depois do seu ok.

## Limites conhecidos (fora do escopo)

- Fechar uma janela com download em andamento cancela o download, como fechar o app faz
  hoje. Download que sobrevive ao fechar fica para depois.
- Pop-up com `window.open` com tamanho continua abrindo como aba, como hoje.
- Reabrir janela fechada inteira (como o Ctrl+Shift+T do Chrome para janelas) não entra.

## Arquivos principais

- Novos: `src/ui/Neco.UI.App.pas`, `src/ui/Neco.UI.Instance.pas`
- Mudam: `src/ui/Neco.UI.Main.pas` (a maior parte), `src/ui/Neco.UI.Frame.pas`,
  `src/ui/Neco.UI.Tab.pas`, `src/engine/Neco.Engine.Intf.pas`,
  `src/engine/Neco.Engine.WebView2.pas`, `src/core/Neco.Core.Settings.pas`,
  `src/ui/Neco.UI.Neco.pas` (pausar a Neco), `NecoBrowser.dpr`/`.dproj`, `tests/CoreTests.dpr`
- Reaproveitados: `NecoAcquireInstanceLock` (`Neco.UI.Frame.pas:342`), `HookParent` e
  `NecoParentSubclass` (motor), `NecoSaveTextAtomic`/`NecoParseObject`
  (`Neco.Core.Files.pas`), `tools/build.sh`, `tools/neco.ps1`, `tools/medir.ps1`.
