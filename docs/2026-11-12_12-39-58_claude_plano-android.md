# Plano: NecoBrowser no Android (fase 2)

## Contexto

O NecoBrowser foi feito desde o começo para ter Android depois
(`docs/2026-11-09_09-37-20_claude_para_claude_plano-fase1-windows.md`): a tela conversa com o
motor só pela interface `INecoEngine`, e o núcleo (`src/core`) não usa FMX nem Winapi. Este plano
leva o navegador para o celular com o mesmo jeito de ser: leve, com bloqueador de verdade e
com a Neco.

### O que o levantamento de 2026-11-12 confirmou

- **Ferramentas prontas no Delphi 13:** SDK do Android 35 (32 e 64 bits) registrado na IDE,
  compilador `dccaarm64.exe`, NDK, JDK (AdoptOpenJDK) e `adb` no CatalogRepository. Falta
  conferir um celular ligado por USB (decisão 1).
- **Núcleo:** os 10 arquivos de `src/core` já compilaram para Android64 na fase 1 (`df0bed9`).
  Os que entraram depois (`Updater`, `AdExtension`) separam o Windows com `{$IFDEF MSWINDOWS}`.
- **Tela:** só `Neco.UI.Frame`, `Neco.UI.Instance`, `Neco.UI.DefaultBrowser` e `Neco.UI.Neco`
  tocam o Windows, e os três primeiros já têm um ramo `{$ELSE}` vazio. `TNecoTab`, os painéis,
  o tema, os sprites e o `TNecoApp` não dependem do Windows.
- **WebView do Android no Delphi:** `Androidapi.JNI.Webkit` declara `WebView`, `WebViewClient`,
  `WebChromeClient`, `WebResourceResponse` e `DownloadListener`. Mas `WebViewClient` e
  `WebChromeClient` são **classes** Java, e o Delphi só implementa **interfaces** Java
  (`TJavaLocal`). Os eventos que importam (`shouldInterceptRequest` para o bloqueador,
  `onCreateWindow` para pop-up, `onShowCustomView` para tela cheia de vídeo, `onReceivedIcon`
  para favicon) só existem nessas classes. **Precisa de um `.jar` próprio**, como a fase 1
  previu. O `DownloadListener` é interface e fica no Delphi.
- **Não usar o `TWebBrowser` do FMX:** ele não dá acesso a requisição, download nem pop-up (mesma
  decisão da fase 1).

### O que muda de verdade no celular

| No Windows | No Android |
|---|---|
| Várias janelas, faixa de abas como barra de título | Uma tela só. Abas numa grade (como no Chrome do celular) |
| Painéis laterais | Painéis em tela cheia, com o botão "voltar" do Android |
| Menus FMX por cima da página | **O FMX não desenha por cima da página** (a página é uma `View` nativa sobre a superfície OpenGL do FMX). Menus e painéis escondem a página e mostram uma foto dela no lugar |
| Extensão uBOL para o YouTube | O WebView do Android não aceita extensões. Fica só o bloqueio por requisição, e o YouTube vira etapa experimental (Etapa 7) |
| Atualizador troca o exe | APK no GitHub Releases, e o Android pede para instalar (Etapa 8) |
| O app fecha quando o usuário fecha | **O Android mata o app quando quer.** A sessão grava sempre que o app vai para o fundo |
| Medidor de memória (exe + processos do WebView2) | A página roda num processo isolado do sistema, que o app não consegue medir. O medidor mostra só o app, ou some |

## Decisões que preciso de você antes de começar

1. **Celular para testar:** qual modelo e versão do Android? Proponho o mínimo **Android 8
   (API 26)**: cobre quase todos os aparelhos em uso, e é a partir dele que o WebView recebe
   atualização pela Play Store e tem o preenchimento automático do sistema. Sem celular, uso o
   emulador do SDK, que é lento e não mede memória direito.
2. **Distribuição:** (a) **APK no GitHub Releases** (recomendado: é o seu fluxo de hoje e não
   precisa de conta paga), (b) Play Store (conta de US$ 25, AAB, revisão e políticas), ou
   (c) os dois depois.
3. **Barra de endereço:** **em cima com a barra de botões embaixo** (recomendado, como o Chrome
   com uma mão), ou tudo embaixo (como o Samsung Internet e o Firefox).
4. **Projeto:** **um `.dproj` separado (`NecoBrowserMobile.dproj`) na mesma pasta, usando o
   mesmo `src`** (recomendado: o `.dpr` do celular cria a tela do celular e o do Windows não
   muda nada), ou um projeto só com `{$IFDEF ANDROID}` no `.dpr`.
5. **Tablet:** fica de fora agora (usa a tela do celular esticada), ou entra depois com uma tela
   própria.

## Regras da execução

As mesmas do multi-janela:
- Branch `android`, um commit e uma tag `an-etapaN` por etapa. Commits locais autorizados com a
  aprovação do plano; **nada vai para o GitHub sem você pedir**.
- Ao fim de cada etapa:
  - o Windows continua com 0 avisos (`bash tools/build.sh`) e nada muda para quem usa;
  - o Android compila com 0 avisos novos;
  - os testes do núcleo passam e não aparece U+FFFD nos arquivos tocados;
  - o roteiro manual da etapa.
- Eu gero o APK e instalo pelo `adb` se o celular estiver ligado; senão deixo o APK em
  `%TEMP%\NecoBuild\an-N` e você instala. Só passo para a próxima etapa com a anterior aprovada.
- `graphify update` e nota na memória ao fim de cada etapa.
- Quando falhar: duas tentativas de correção dentro da etapa; depois disso paramos e voltamos
  para a tag anterior (só com o seu ok) e replanejamos. Cada pressuposto técnico tem uma
  saída já prevista na Etapa 1.

---

## Etapa 0 — Base e ferramentas

- Branch `android` a partir da `main` (que já tem multi-janela e a tela de atalhos).
- `NecoBrowserMobile.dpr` e `.dproj` (alvo Android64; Android32 só se a decisão 1 pedir
  aparelho antigo) com um motor vazio (`TNecoNullEngine`, que não mostra nada) e uma tela
  mínima: a faixa com a Neco e um texto.
- `tools/build_android.sh`: compila pelo `dccaarm64` e gera o APK assinado com a chave de
  depuração. Deixa o APK em `%TEMP%\NecoBuild`.
- Compilar **todo o `src`** para Android64, para ver o que quebra antes de escrever código novo.
- **Medição de referência:** tamanho do APK, tempo de abertura e memória do app vazio
  (`adb shell dumpsys meminfo`).

**Teste:** o APK instala, abre, mostra a Neco animando, gira a tela sem travar e fecha pelo
botão voltar.

## Etapa 1 — Prova técnica do motor (a etapa que decide o resto)

Uma ponte Java mínima e uma página de verdade na tela, para responder às perguntas abaixo antes
de construir em cima:

- `java/NecoWebView.java` e `java/NecoWebListener.java`: o Java cria o `WebView` com o
  `WebViewClient` e o `WebChromeClient` próprios e repassa cada evento a uma interface
  (`NecoWebListener`), que o Delphi implementa com `TJavaLocal`. **Toda chamada a API nova do
  Android fica no Java**, que confere a versão do aparelho (`Build.VERSION.SDK_INT`). O Delphi
  importa só essas duas classes, nada da `Androidapi.JNI.Webkit` gigante.
- `tools/android_jar.sh`: compila com o `javac` do JDK contra o `android.jar` do SDK e gera
  `lib/necoweb.jar`. O `.dproj` inclui o `.jar` e o Delphi converte para o formato do Android
  ao gerar o APK.

| Pergunta | Como respondo | Saída se der "não" |
|---|---|---|
| O `WebView` fica no lugar certo sobre a tela FMX (escala, barra de status, girar a tela)? | Página com régua nos 4 cantos, girando a tela | Pôr o `WebView` num `FrameLayout` próprio do lado do FMX, em vez de sobre ele |
| Teclado virtual: o campo da página sobe e não fica atrás do teclado? | Campo de busca no pé da página | `adjustResize` no manifesto mais um ajuste manual da altura pelo `WindowInsets` |
| `shouldInterceptRequest` roda numa thread de fundo: o filtro do Delphi aguenta? | 50 páginas com o filtro ligado, sem travar nem fechar | A lista de bloqueio vai para o Java (um `HashSet` passado uma vez) e o Delphi só liga e desliga |
| Pausar e voltar (`onPause`/`onResume`, `pauseTimers`): o vídeo para no fundo e volta? | YouTube, botão Home, voltar ao app | Pausar e voltar a página pelo eventos de ciclo de vida do FMX |
| Memória de um `WebView` por aba | 1, 3 e 6 abas com `dumpsys meminfo` | Limite de páginas vivas mais baixo na Etapa 4 |

Relatório da prova em `docs/`. Código provisório da prova apagado no fim, como no multi-janela.

## Etapa 2 — Motor completo (`Neco.Engine.AndroidWebView.pas`)

O `INecoEngine` inteiro, sem mudar a interface. O que cada parte vira no Android:

- **Navegar, voltar, avançar, recarregar, parar, título, endereço, progresso:** direto no `WebView`.
- **Bloqueador:** `shouldInterceptRequest` devolve uma resposta vazia para o que a lista barra.
  Conta os bloqueados como no Windows (o escudo e a comemoração da Neco funcionam).
- **Pop-up (`window.open`):** `onCreateWindow` cria um `WebView` temporário só para descobrir o
  endereço e repassa a `OnNewWindowRequested` (vira aba, como no Windows).
- **Downloads:** `DownloadListener` no Delphi. O arquivo vai para o `DownloadManager` do sistema
  (pasta Downloads e notificação do Android), com os cookies da página. O progresso vem de
  consultas a cada meio segundo, num `INecoDownload` próprio. O painel de downloads funciona
  sem mudança.
- **Tela cheia de vídeo:** `onShowCustomView` põe o vídeo por cima de tudo e esconde as barras
  do sistema; vira `OnFullScreen`.
- **Favicon:** `onReceivedIcon` passa o bitmap para PNG e vira `OnFavicon`.
- **Erros:** os códigos do `onReceivedError` e do `onReceivedSslError` viram `TNecoNavError`.
  A página de erro com a Neco funciona igual.
- **Modo escuro:** `setAlgorithmicDarkeningAllowed` (Android 13+) ou `setForceDark` (Android 10
  a 12), chamados do Java.
- **Sem equivalente:** `SetParentWindow` (uma tela só) e `OpenTaskManager` não fazem nada.
  `SetAutofill` deixa o preenchimento automático do sistema agir. `OnAcceleratorKey` funciona
  só com teclado físico.
- O `Neco.Engine.Factory` escolhe o motor por `{$IFDEF ANDROID}`.

**Testes:**
- o anúncio de um site conhecido some;
- um download chega na pasta Downloads com notificação e aparece no painel;
- um link que abre pop-up vira aba;
- o vídeo vai para tela cheia e volta;
- o favicon aparece;
- endereço inexistente e sem internet mostram a página de erro da Neco;
- tema escuro e claro;
- fechar a aba solta a memória da página.

## Etapa 3 — A tela do celular (`Neco.UI.MobileMain.pas`)

Uma tela nova, que reaproveita `TNecoTab`, painéis, tema, sprites e o `TNecoApp`. A
`Neco.UI.Main` (Windows) não muda.

- **Em cima:** a barra de endereço com o cadeado, a estrela e as sugestões. As sugestões
  ocupam a tela inteira enquanto se digita, como no Chrome do celular, e assim não ficam por
  cima da página.
- **Embaixo** (ou tudo embaixo, conforme a decisão 3): voltar, avançar, a **Neco**, o botão de
  abas (com a contagem) e o menu.
- **Abas:** grade de cartões com título, favicon e a foto da página (`WebView.draw` num bitmap).
  Fecha deslizando para o lado ou no X. "+" cria aba.
- **Menu:** uma folha que sobe de baixo. A página some e no lugar fica a foto dela (decisão
  técnica da tabela de diferenças).
- **Painéis** (favoritos, histórico, downloads, configurações) em tela cheia, voltando pelo
  botão voltar do Android. Os painéis de hoje são `TNecoSidePanel` montados em código: ganham
  um modo "tela cheia".
- **Botão voltar do Android:** fecha o que estiver aberto; senão volta na página; senão
  minimiza o app (como o Chrome).
- **Toques:** apertar e segurar um link ou imagem abre "abrir em aba nova", "copiar link" e
  "baixar imagem" (`WebView.getHitTestResult`).
- **Tela de atalhos:** some do menu no celular (só aparece com teclado físico ligado).

**Testes:**
- navegar só com o polegar;
- abrir e fechar 10 abas pela grade;
- menu e painéis abrindo por cima da página sem piscar;
- girar a tela em cada um deles;
- tema escuro e claro;
- botão voltar em cada situação.

## Etapa 4 — O app no ciclo de vida do Android

- **Gravar sempre:** sessão, favoritos, histórico e configurações gravam quando o app vai para
  o fundo (`aeEnteredBackground`), e não só ao fechar. O Android pode matar o app no fundo sem
  avisar.
- **Abrir de novo** depois de o sistema matar o app: as abas voltam, e a de fundo carrega só ao
  ser aberta (já é assim no Windows).
- **Leveza:** no máximo **3 páginas vivas** (número a confirmar pela medição da Etapa 1). As
  outras guardam o estado (`WebView.saveState`) e soltam o `WebView`; ao voltar a elas, a
  página volta no mesmo lugar ou recarrega.
- **O `TNecoApp` no Android:**
  - sem a trava de instância (o Android já garante uma);
  - sem o atualizador de exe (a Etapa 8 trata o APK);
  - sem a extensão uBOL;
  - o medidor de memória mede só o app, ou some (decisão na Etapa 1).
- **Dados:** a pasta do app (`TPath.GetHomePath`, que o `TNecoSettings` já usa). O WebView guarda
  cookies e cache na pasta dele.

**Testes:**
- abrir 10 abas, mandar o app para o fundo e forçar a parada pelo `adb`; ao abrir de novo,
  as 10 abas voltam;
- memória com 10 abas abertas contra 3;
- ligar e desligar a internet no meio de uma página.

## Etapa 5 — Android por fora: navegador padrão, links e compartilhar

- **Manifesto:** `intent-filter` de `http`, `https` e `VIEW`, para o NecoBrowser aparecer em
  "Navegador padrão" nas configurações do Android. A chave "navegador padrão" do painel abre essa
  tela do sistema.
- **Link vindo de outro app:** abre numa aba nova (`singleTask` e o evento de intent novo do FMX).
  É o equivalente da instância única do Windows.
- **Compartilhar:** "Compartilhar página" no menu (`ACTION_SEND`). O NecoBrowser também recebe
  texto compartilhado de outros apps: se for um endereço abre, senão busca.
- **Arquivos:** `content://` e `file://` vindos do gerenciador de arquivos (PDF, HTML).
- **Permissões:** internet; notificações no Android 13+ (para o download aparecer). Nenhuma
  permissão de armazenamento: o `DownloadManager` não precisa.

**Testes:**
- tornar o NecoBrowser o padrão e tocar num link no WhatsApp;
- compartilhar um link de outro app para o NecoBrowser;
- abrir um PDF pelo gerenciador de arquivos.

## Etapa 6 — Desempenho e bateria

- Página no fundo e app no fundo: o `WebView` pausa os timers (`pauseTimers`/`onPause`).
- A Neco anima só com o app na frente e para no modo de economia de bateria.
- O APK fica abaixo do tamanho medido na Etapa 0 mais o `.jar`: os sprites e a lista de bloqueio
  vão comprimidos, como no Windows.
- **Medição:** abertura a frio, memória com 1, 3 e 10 abas, e bateria em 30 min de YouTube
  contra o Chrome (`dumpsys batterystats`).

## Etapa 7 — YouTube sem anúncio no Android (experimental)

O WebView não aceita a uBOL. A saída é injetar no começo de cada página do YouTube um script
pequeno com as regras de esconder anúncio, os "scriptlets" do mesmo tipo que a uBOL usa:
- **Android com WebView recente:** `addDocumentStartJavaScript` da biblioteca `androidx.webkit`.
- **Aparelho antigo:** `evaluateJavascript` no início da página, que roda um pouco depois do
  ideal.

O YouTube muda o tempo todo, então esta etapa tem critério de parada: se em duas tentativas o
anúncio do vídeo não sumir, a etapa sai do plano, sem afetar as outras. O bloqueio por
requisição (Etapa 2) continua valendo para o resto da web.

## Etapa 8 — Publicação e atualização

- **Chave de assinatura de release:** você cria e guarda (fora do Git). Sem ela, não dá para
  atualizar o app instalado. Perder a chave obriga a desinstalar e instalar de novo.
- O `tools/publicar.sh` passa a gerar também `NecoBrowser.apk` e o `.sha256`, na mesma release do
  GitHub. A versão do APK (`versionCode`) sai do mesmo número de versão do exe.
- **Atualizador no celular:** consulta a release, baixa o APK e chama o instalador do Android,
  que pede a permissão "instalar apps desconhecidos" uma vez. Se a decisão 2 for Play Store,
  esta parte sai e a loja atualiza.

## Etapa 9 — Medição e fechamento

- Relatório em `docs/` com as medições das Etapas 0, 1 e 6, comparando com o Chrome no mesmo
  celular.
- Notas de memória e grafo atualizados. Merge da branch `android` na `main` depois do seu ok.

## Limites conhecidos (fora do escopo)

- Sem extensões (o WebView não aceita).
- Sem várias janelas (uma tela só; o modo tela dividida do Android funciona como qualquer app).
- Sem gerenciador de senhas próprio: o preenchimento automático do sistema (Google ou Samsung)
  faz esse papel.
- Sem sincronização de favoritos entre o PC e o celular. É um projeto separado, que pode vir
  depois (arquivo no Google Drive ou no GitHub).
- O WebView é o do sistema: versão e falhas dele dependem da atualização do "Android System
  WebView" pela Play Store.

## Arquivos principais

- **Novos:**
  - `NecoBrowserMobile.dpr` e `.dproj`;
  - `java/NecoWebView.java` e `java/NecoWebListener.java`, gerando `lib/necoweb.jar`;
  - `src/engine/Neco.Engine.AndroidWebView.pas` e `src/engine/Neco.Engine.AndroidBridge.pas`
    (a importação JNI das duas classes);
  - `src/ui/Neco.UI.MobileMain.pas`, a tela do celular;
  - `tools/build_android.sh` e `tools/android_jar.sh`;
  - `AndroidManifest.template.xml`.
- **Mudam pouco:**
  - `src/engine/Neco.Engine.Factory.pas`: escolhe o motor pela plataforma;
  - `src/ui/Neco.UI.App.pas`: partes do Windows separadas por `{$IFDEF}`;
  - `src/ui/Neco.UI.SidePanel.pas`: modo tela cheia;
  - `src/ui/Neco.UI.Neco.pas`: pausa com o app no fundo;
  - `tools/publicar.sh`: gera o APK.
- **Não mudam:**
  - `src/core` (exceto, talvez, um `{$IFDEF}` a mais);
  - `INecoEngine`;
  - `Neco.UI.Main.pas` e tudo o que é só do Windows.
