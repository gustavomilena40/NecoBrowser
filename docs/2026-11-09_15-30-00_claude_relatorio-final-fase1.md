# NecoBrowser — relatório final da fase 1 (Windows)

- **De:** Claude Code, sessão `4b91b47e-2192-4fde-8383-454d7731e9c3`, 2026-11-09.
- **Base:** plano `2026-11-09_09-37-20_...plano-fase1-windows.md`, handoff
  `2026-11-09_10-39-10_...handoff-fase1-etapas4a7.md` e o relatório da quest visual
  `2026-11-09_11-45-00_claude_relatorio_barra-titulo-e-neco.md`.
- **Pedido do usuário nesta sessão:** seguir para as próximas etapas a partir do último handoff,
  "adicionando necos onde for pertinente". Depois, correções e funções pedidas por ele ao testar
  (seção "Depois das 7 etapas").
- **Estado:**
  - as 7 etapas da fase 1 estão feitas, mais as funções extras pedidas;
  - compila em Win64 e Win32 com 0 erros e 0 avisos (baseline 0);
  - testes do núcleo: 84 verificações, 0 falhas;
  - memória medida com 20 abas em 3 ciclos: sem vazamento no app (seção "Memória").

## Commits desta sessão

| Commit | O quê |
| --- | --- |
| `d590612` | 4. Atalhos de abas; pop-up e `target=_blank` viram aba nova ao lado da de origem. |
| `64bc940` | 5. Bloqueador com a lista real, selo com o contador e liga/desliga. |
| `be0460f` | 6. Painéis de downloads e favoritos. |
| `b2c62f9` | 7. Tema, configurações e página de erro. |
| `9ed0da5` | Corrige página de erro falsa ao trocar de página durante o carregamento. |
| `076fe2c` | Exe portátil (DLL e lista embutidas); preenchimento de formulários e senhas. |
| `ea9e6d9` | Arrastar aba para mudar a posição; tema escuro um pouco mais claro. |
| `de48e41` | Barra de favoritos abaixo do endereço; renomear favorito. |
| `b4c674f` | Histórico com busca, reabrir aba fechada, restaurar sessão, tela cheia. |
| `4649bd8` | Leitor de arquivos, ícone do site nos favoritos, arrastar favoritos. |
| (este) | Este relatório, com a medição de memória. |

O `d093bb5` ("adicionado o exe") é do usuário.

## O que mudou, por etapa

### Etapa 4: abas
- Atalhos (com o foco na barra ou dentro da página):
  - Ctrl+T, Ctrl+W, Ctrl+Tab, Ctrl+Shift+Tab;
  - Ctrl+1..8 (aba pela posição) e Ctrl+9 (a última);
  - Ctrl+R / F5, Esc (só enquanto carrega: no resto do tempo o Esc é da página);
  - Ctrl+L e Alt+←/→, que já existiam.
- Trocar ou fechar aba pelo teclado passa o foco para a página da aba nova.
- `TabNewWindow` abre aba nova logo depois da aba de origem. A criação é adiada para fora do
  callback do motor (`ForceQueue`).

### Etapa 5: bloqueador
- `data\blocklist-hosts.txt` = lista StevenBlack unificada de 2026-11-08: **78.215 domínios**, licença MIT
  (o cabeçalho do arquivo tem a origem).
- Escudo na barra com selo do número de bloqueados na página. Clicar liga ou desliga e recarrega a página.
- **Medido** (rastro, Win64):
  - a carga da lista leva **~100 ms** na abertura (**~150 ms** quando vem do recurso embutido no exe).
    Ficou síncrona, porque o motor leva ~1,7 s para ficar pronto de qualquer jeito;
  - no g1, **9 de 121** requisições foram barradas, com **10,6 ms** no filtro.

### Etapa 6: downloads e favoritos
- `Neco.UI.SidePanel`: painel lateral base. Ele encolhe a página e nunca fica por cima dela (espaço aéreo).
  Um painel por vez.
- **Downloads:** progresso, cancelar, abrir (clique) e mostrar na pasta; "limpar concluídos"; o painel
  abre sozinho quando um download começa.
- **Favoritos:** estrela na barra de endereço e Ctrl+D; painel com abrir (botão do meio = aba nova)
  e remover; grava a cada mudança.
- Atalhos: Ctrl+J (downloads) e Ctrl+Shift+O (favoritos).

### Etapa 7: tema e acabamento
- **Botão de tema** (sol/lua): troca a interface e chama `SetDarkMode` em todas as abas.
- **Configurações** (painel): motor de busca, tema, barra de favoritos, "ao abrir", bloqueador,
  formulários e senhas, "Mostrar a Neco".
- **Página de erro amigável** (FMX sobre a área da página; o motor fica escondido e o histórico
  dele não muda):
  - aparece para site não encontrado, sem internet, tempo esgotado e conexão recusada;
  - erro de certificado e os demais ficam com a página do próprio WebView2;
  - "Tentar de novo" e F5 refazem a navegação.
- **Medido:** domínio inexistente → página de erro em **339 ms**.

## Depois das 7 etapas (pedidos do usuário ao testar)

### Correções
- **Página de erro falsa** (login Google no claude.ai; clicar em outro link enquanto a página
  carregava). A navegação cancelada por outra chegava como erro. Agora `ERR_ABORTED` vira
  `neCanceled`, e o fim de uma navegação já substituída é ignorado pelo `NavigationId`.

### Portabilidade
- O exe roda sozinho em outra máquina: `WebView2Loader.dll` (32 e 64 bits) e a lista de bloqueio
  (comprimida) vão como recursos dentro do exe (`tools\neco_embutidos.py`). A DLL é extraída para a
  pasta de dados só se não houver uma ao lado do exe. Erro 193 (DLL da arquitetura errada ao lado
  do exe, que foi o caso relatado) também cai na DLL embutida.
- Testado nos 3 cenários: sem DLL ao lado, DLL certa ao lado, DLL errada ao lado.
- O pós-build do `.dproj` (que copiava a DLL e a lista) e as entradas de deploy da DLL foram
  removidos: não são mais necessários, e o pós-build quebrava o build Win32.

### Formulários e senhas
- Preenchimento automático de formulários e salvar senhas ligados pelo perfil do WebView2
  (`ICoreWebView2Profile6`, com `Settings4` de reserva). Os dois podem ser desligados nas configurações.

### Abas e favoritos
- Arrastar uma aba muda a posição dela (depois de 6 px de movimento; clique comum continua clique).
- Barra de favoritos logo abaixo do endereço, como no Chrome (Ctrl+Shift+B liga e desliga).
  As pílulas que não cabem vão para o botão », que abre o painel.
- Renomear favorito: lápis no painel, ou botão direito na pílula.
- Arrastar uma pílula da barra muda a posição do favorito.
- Ícone do site em cada favorito (evento `FaviconChanged` do WebView2). O PNG fica em
  `favicons\<host>.png` na pasta de dados, gravado só para sites favoritados. Sem ícone guardado,
  a pílula mostra só o nome; o painel mostra a estrela.
- Tema escuro um pouco mais claro (cada tom subiu ~8 a 10 pontos).

### Funções essenciais de navegador
- **Histórico** (Ctrl+H e botão na barra): mais recente primeiro, separado por dia, busca por título
  ou endereço, limpar com confirmação (dois cliques), até 300 linhas na tela.
- **Reabrir aba fechada** (Ctrl+Shift+T), até as 25 últimas.
- **Restaurar a sessão:** ao abrir, voltam as abas da última vez (desligável). Só a aba ativa
  carrega; as outras carregam quando ativadas. Uma segunda janela com o mesmo perfil não grava nem
  restaura a sessão (trava com nome por pasta de dados).
- **Tela cheia:** a de vídeo (pedida pela página) e o F11. A janela cobre o monitor e a interface some.
- **Leitor de arquivos:** PDF (leitor do WebView2), texto, imagens, vídeo, áudio, HTML. Abre pelo
  caminho na barra de endereço (aspas do "Copiar como caminho" saem), por Ctrl+O / botão na barra
  (vários de uma vez) e pela linha de comando ("Abrir com" do Explorer). A aba mostra o nome do arquivo.
- Zoom (Ctrl+roda, Ctrl+±), busca na página (Ctrl+F) e impressão (Ctrl+P) já vêm do WebView2.

## As Necos novas

| Onde | Animação | Quando |
| --- | --- | --- |
| Página de erro | tombo (`nek24`) | site não encontrado |
| Página de erro | maca (`nek88`) | sem internet, tempo esgotado, conexão recusada, falha do motor |
| Painel de downloads vazio | deitada (`lazy`) | "Nada baixado ainda. A Neco está de folga." |
| Painel de favoritos vazio | pose (`turn`) | convite para usar a estrela |
| Painel de histórico vazio | provocação (`taunt`) | nada visitado (ou busca sem resultado) |
| Configurações | dancinha (`dance`) | prévia ao lado de "Mostrar a Neco" |
| Faixa de abas | comemora (`cheer`) | download concluído (sem o limite de 1x por minuto) |
| Faixa de abas | pose (`turn`) | ao favoritar uma página |
| Faixa de abas | cambalhota (`flip`) | ao limpar o histórico |

- "Mostrar a Neco" desligado: nenhuma Neco desenha nem anima. O timer da faixa cai para 1 s.
- `TNecoSprite` (em `Neco.UI.Neco`) é a Neco avulsa usada nos painéis e no erro.

## Memória com 20 abas (regra 3.3)

Medido com `NECO_TESTE_ABAS=20 NECO_TESTE_CICLOS=3`, build Win64 do commit `4649bd8`, perfil
separado, janela minimizada e sem uso durante o teste. Cada aba abre `https://example.com/`.
A medida é feita em repouso: 30 s depois de abrir e 45 s depois de fechar.

| Fase | App: privada | App: handles | WebView2: processos | WebView2: privada |
| --- | ---: | ---: | ---: | ---: |
| base (1 aba) | 38,0 MB | 304 | 6 | 100,4 MB |
| ciclo 1, 21 abas | 41,1 MB | 347 | 26 | 616,6 MB |
| ciclo 1, fechadas | 40,3 MB | 305 | 6 | 144,5 MB |
| ciclo 2, 21 abas | 41,2 MB | 339 | 26 | 606,7 MB |
| ciclo 2, fechadas | 40,7 MB | 301 | 6 | 150,2 MB |
| ciclo 3, 21 abas | 41,2 MB | 341 | 26 | 624,0 MB |
| ciclo 3, fechadas | 40,4 MB | 301 | 6 | 153,3 MB |

Leitura:
- **App (FMX + Delphi): sem vazamento.** A memória privada fica em ~40 MB e os handles voltam a
  ~301 a cada ciclo.
- **WebView2: cada aba custa ~24 MB privados** (~53 MB de working set) numa página simples.
  Fechar as abas encerra os processos delas (26 → 6).
- Depois de fechar, o WebView2 fica com +44 MB no primeiro ciclo e só +6 e +3 MB nos seguintes:
  é cache do Chromium (rede, GPU, processo reserva) se assentando, não crescimento por ciclo.
- Medição anterior (descartada) foi contaminada por uso da janela durante o teste.

## Como foi testado

- Build Win64 e Win32 a cada mudança (`tools\build.sh`): 0 erros e 0 avisos.
- `tests\rodar-testes.cmd`: 84 verificações, 0 falhas. Entraram, entre outros: renomear e mover
  favorito, sessão, caminhos de arquivo → `file:///`, nome do arquivo na aba e cache de ícones.
- **Execução real sem mexer no mouse nem no teclado do usuário.** O exe abre sem ativar a janela
  (`SW_SHOWNOACTIVATE`) e a captura é por `PrintWindow`. Conferidos por captura: painéis
  (downloads, favoritos, histórico, configurações), página de erro nos dois temas, barra de
  favoritos com ícone, sessão restaurada com abas de fundo sem carregar, TXT com acentos e PDF.
- **Testado à mão pelo usuário:** login Google, troca de página durante o carregamento, exe em outra
  máquina, arrastar abas, barra de favoritos, renomear, histórico, Ctrl+Shift+T, sessão e tela cheia.
- Ganchos de teste por variável de ambiente (desligados por padrão):
  - `NECO_TRACE=<arquivo>` e `NECO_DEMO=1`, que já existiam;
  - `NECO_DADOS=<pasta>`: perfil separado, com os downloads dentro dela;
  - `NECO_PAINEL=downloads|favoritos|config|historico`: abre o painel na partida;
  - `NECO_TESTE_ABAS=<n>` e `NECO_TESTE_CICLOS=<c>`: abre e fecha n abas sozinho e marca as fases no rastro.

### Não testado por mim
- Escala de 125%/150% do Windows.
- Arrastar favoritos na barra (fica para o teste à mão).
- Tela cheia em mais de um monitor.

## Desvios do plano e decisões

- **Página de erro em FMX, não em HTML.** Evita mexer no histórico do motor e reusa a `TNecoSprite`.
- **`INecoEngine` mudou** (a fase 2, Android, precisa acompanhar):
  - `OnNavigationCompleted` ganhou `AError: TNecoNavError`;
  - `SetAutofill(AForms, APasswords)`;
  - eventos `OnFullScreen` e `OnFavicon` (PNG em `TBytes`).
- **Units a mais:** `Neco.UI.SidePanel`, `Settings`, `ErrorView`, `Downloads`, `Bookmarks`,
  `BookmarkBar`, `History` e `Neco.Core.Favicons`, todas montadas em código (sem `.fmx`).
- **`TNecoSearchEngine`** ganhou `seDuckDuckGoHtml` no fim do enum. O valor gravado é o id
  (`duckduckgo-html`), não o número.
- Sugestões na barra de endereço ficaram de fora: a lista teria de ficar por cima da página
  (espaço aéreo), o que pede uma janela nativa à parte.

## Pendências e ideias para depois

- Com muitas abas, elas param na largura mínima e as que não cabem ficam cortadas (sem rolagem).
- `window.open` não devolve a janela para quem abriu: o pop-up vira aba, mas o `opener` fica nulo.
  Login por pop-up (OAuth) pode falhar.
- A cor de fundo do motor antes de a página pintar é fixa na abertura. Com o tema claro, uma aba
  nova ainda pisca escuro por um instante.
- "Abrir com" com o navegador já aberto abre uma segunda janela, em vez de uma aba na primeira.
- Ícone do site na própria aba (hoje só nos favoritos).
- Os sprites são da Type-Moon/French-Bread. O uso é pessoal; rever se o projeto for distribuído.
- `Sprites\` continua fora do Git e sem entrada no `.gitignore`.
- O `.dproj` tem mudanças da IDE do usuário (plataformas Android, ícone) e a limpeza do pós-build.
  Ficou fora dos commits, para o usuário decidir.
