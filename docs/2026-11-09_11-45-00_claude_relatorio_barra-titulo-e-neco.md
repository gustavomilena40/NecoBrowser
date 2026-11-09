# NecoBrowser — quest paralela: barra de título própria e a Neco-Arc

- **De:** Claude Code, sessão `45fc48d8-27a3-4a76-bf9a-31ef78b55a35`, 2026-11-09.
- **Pedido do usuário:** antes das etapas 4 a 7, tirar a barra branca do Windows (botões
  próprios de minimizar, maximizar e fechar), com as abas na mesma linha, como no Chrome; e
  usar os sprites da Neco-Arc (`Sprites\Neco Arc Sprites.zip`) como identidade visual,
  com aparições aleatórias. Lista de animações proposta e aprovada pelo usuário.
- As etapas 4 a 7 do handoff `2026-11-09_10-39-10_...` continuam valendo. Esta quest
  adiantou só a parte visual da faixa de abas (ver "O que muda para a etapa 4").

## O que foi feito

| Arquivo | Conteúdo |
| --- | --- |
| `src\ui\Neco.UI.Frame.pas` (novo) | Subclasse da janela: `WM_NCCALCSIZE` sobe a área cliente até o topo, `WM_NCHITTEST` pergunta ao form o que há em cada ponto (arrastar, cliente, botão maximizar). Maximizar responde `HTMAXBUTTON`: o Windows 11 mostra os layouts de snap. Hover e clique desse botão chegam por callback (`WM_NCMOUSEMOVE/LEAVE`, `WM_NCLBUTTONUP`). |
| `src\ui\Neco.UI.Neco.pas` (novo) | `TNecoStage`: a Neco por cima da faixa de abas (sem receber clique, exceto em cima dela). |
| `src\ui\NecoSprites.res` (novo, gerado) | Índice + uma folha PNG por animação (85 KB). |
| `tools\neco_sprites.py` (novo) | Gera o `.res`, o `data\neco.ico` e uma prévia em `%TEMP%\NecoBuild\neco-previa.png`. A tabela `ANIMS` é o único lugar a mexer para trocar animações. |
| `data\neco.ico` (novo, gerado) | Rosto da `nek00`. O `.dproj` aponta `Icon_MainIcon` para ele. |
| `src\ui\Neco.UI.Main.pas` | Faixa de abas (abas com título e X, botão "+", assento da Neco, botões da janela), `TitleHitTest`, `LayoutTabStrip`. |
| `src\ui\Neco.UI.Theme.pas` | Medidas da faixa, ícones dos botões da janela, `TNecoIconButton` com `HoverColor`, `HoverIconColor`, `PressedColor`, `Hot` e `IconSize`. |

### Comportamento da Neco

- Parada no assento (`idle`); pulando enquanto a aba ativa carrega (`hop`); deitada quando o
  computador está sem uso há 2 min (`lazy`, via `GetLastInputInfo`).
- Aparições a cada 1 a 3 min (a primeira 30 a 60 s depois de abrir), só com a janela em
  primeiro plano: cambalhota, dancinha, pose, ou atravessar a faixa (afunda, atravessa
  deslizando ou num borrão, brota de volta). Gato-sombra em ~5% das aparições.
- Clique nela: ri (`taunt`). Página carregada com anúncios bloqueados: comemora (`cheer`,
  no máximo 1x por minuto; só acontece de verdade quando a etapa 5 trouxer a lista real).
- Janela minimizada: não desenha, e o timer cai de 40 ms para 1 s. Medido: 0,4% de um núcleo
  no processo principal com a Neco animando.
- `NECO_DEMO=1` no ambiente: uma aparição a cada 4 a 8 s, mesmo com a janela atrás (teste).

## Achado: `SetWindowSubclass` falhava em silêncio (afeta o motor)

O `SetWindowSubclass` do `Winapi.CommCtrl` só funciona depois do `InitComCtl`, que só pega a
`comctl32` se ela já estiver carregada. Num app FMX ninguém faz isso: a função devolve `False`
sem erro (verificado pelo rastro: a barra branca continuava, `anterior=0` na segunda chamada).

`Neco.UI.Frame.EnsureComCtl` agora chama `InitCommonControls` + `InitCommonControlsEx` antes de
subclassar. **Isto muda o motor também:** o `HookParent` de `Neco.Engine.WebView2` usa a mesma
função e, até aqui, provavelmente nunca foi instalado. Ou seja, o `NotifyParentWindowPositionChanged`
ao mover a janela e a devolução do foco ao clicar na parte FMX passam a funcionar agora. O handoff
anterior os dava como prontos. Vale conferir na etapa 4 (atalhos com foco na página e na barra).

## Verificação

- Build Win64 e Win32: 0 erros, 0 avisos (baseline 0).
- Execução real (Win32), sem dirigir mouse nem teclado (o usuário estava usando a máquina):
  - capturas por `PrintWindow`: a barra branca sumiu (área cliente 1264x812 numa janela
    1280x820; antes era 1264x781);
  - `WM_NCHITTEST` enviado direto à janela: borda do topo = TOP, aba/X/"+"/minimizar/fechar/Neco
    = CLIENT, vazio da faixa = CAPTION, maximizar = MAXBUTTON. Maximizada: sem borda no topo,
    ícone vira "restaurar";
  - modo demonstração: travessias (borrão, deslizando) e poses no assento conferidas por série
    de capturas.
- **Não testado por mim:** clicar nos botões e nas abas, arrastar, snap pelo mouse e escala de
  125%/150%. O usuário estava usando o app durante os testes (a série mostra o hover no
  maximizar e a janela sendo maximizada).

## Desvios e pendências

- **Carregando:** a lista aprovada dizia "Neco correndo no lugar da barra de progresso". Ela
  ficaria por cima do campo de endereço, então a Neco pula no assento enquanto carrega e a
  barra de progresso continua.
- **Páginas HTML com a Neco** (erro com `nek88`/`nek24`, página inicial): ficam para a etapa 7,
  junto da página de erro amigável. A página inicial continua o Google (decisão do usuário).
- **Liga/desliga da Neco:** vai na tela de configurações da etapa 7. Ainda não existe a opção.
- **O que muda para a etapa 4:** a faixa, as abas visuais, o "+", fechar pelo X e pelo
  botão do meio, e o clique para ativar já existem. Faltam Ctrl+T, Ctrl+Tab, Ctrl+Shift+Tab e
  `TabNewWindow` abrir aba nova. Com muitas abas, elas param na largura mínima e as que não cabem
  ficam cortadas (sem rolagem).
- **Direitos:** os sprites são da Type-Moon/French-Bread (ver `Credits.txt` no zip). Uso pessoal;
  o `.res` e o `.ico` derivados estão no Git local. Se o projeto for distribuído, rever.
- O zip `Sprites\` continua fora do Git e sem entrada no `.gitignore` (não alterei o
  `.gitignore` sem pedido).
