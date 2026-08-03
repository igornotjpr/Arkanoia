# Changelog

Versionamento semântico: `MAJOR.MINOR.PATCH`. Neste projeto, **MAJOR** muda
quando o jogo ganha um marco de mecânica (as alucinações; o chefe, quando vier),
**MINOR** quando entra comportamento novo dentro do marco atual, e **PATCH**
quando é só correção.

> "Novas fases" saiu dos exemplos de MAJOR na v2.3.0. Até ali, acrescentar uma
> fase exigia mexer no motor — a grade era fixa em 11×8 e `map_for_level` travava
> no último mapa. Depois da geometria variável e da rotação, uma fase nova é um
> mapa em texto que a suíte valida sozinha: conteúdo de rotina, não marco.

Cada versão é uma tag anotada em `main`. Para ver o que uma tag carrega:

```bash
git show v1.1.0            # a anotação e o commit
git log v1.0.0..v1.1.0     # tudo que entrou entre as duas
```

---

## v2.4.0 — 01/08/2026

Barreiras móveis, e a opção de apostar vidas em bolas extras.

### Adicionado

- **Barreiras móveis** (`src/core/movers.gd`). Barras de aço que patrulham um
  trecho vazio da fase e rebatem a bola sem sofrer dano. Estão em `ARCO`,
  `FORTALEZA` e `CORREDOR`; a fase 1 continua sem nenhuma, de propósito.
- **`BallPhysics.KIND_SOLID`**, com tipo de evento `"solid"` próprio.
- **Lançamento múltiplo.** Com a bola encaixada, `S` (ou a seta para baixo, ou o
  botão no campo) alterna entre 1 e `min(vidas, 6)` bolas. Cada bola além da
  primeira custa uma vida, **cobrada só no lançamento** — até soltar dá para
  voltar atrás.

### A física não mudou uma linha

`BallPhysics.advance` relê `target["rect"]` a cada chamada e nunca guarda cache,
então um alvo que se move já era só um alvo cujo retângulo mudou — exatamente o
que a Arena fazia com a raquete desde a v1.0.0.

O que **precisou** de cuidado foi o id. O tratamento de `"brick"` indexa a lista
de blocos direto pelo id do evento, e `int()` sobre String extrai dígitos de
qualquer posição: **`int("solid:1")` vale 1, não 0.** Uma barreira emitindo
evento `"brick"` passaria por qualquer checagem de faixa e danificaria um bloco
real e arbitrário da parede, dando pontos e abrindo buraco, em silêncio. Por isso
o tipo de evento é próprio e a trava passou a ser de **tipo**, não de faixa.

Blocos usam id `int`, barreiras usam `String`, e o Dictionary do Godot separa `3`
de `"3"` — os dois namespaces não têm como se encostar.

### Por que a aposta se equilibra sozinha

Não há constante nova de balanceamento, e não precisa haver. Bater na raquete
**zera o combo**, então mais bolas significa combo pior; e `level_clear_bonus`
paga 500 por vida restante. Você troca multiplicador e bônus por cobertura de
campo. `ScoreRules.max_stake` garante que apostar N exige N vidas e gasta N−1, o
que impede o lançamento de encerrar a própria partida.

### Testes

- O teto de velocidade da barreira é **derivado da física**, não escolhido: a
  resolução é por sobreposição discreta, então uma barra que ande mais que o
  sub-passo da bola (3 px) pode ejetá-la. O teste amarra `Movers.MAX_SPEED` a
  `BallPhysics.MAX_SUBSTEP_DISTANCE`.
- Toda barreira patrulha vão **vazio**, conferido célula por célula no mapa real.
- Nenhum id de barreira é `int`, e nenhuma delas encosta na faixa da raquete.
- O soak passou a incluir as barreiras: as fases com barra são limpas com a bola
  batendo nela de 13 a 34 vezes por partida, sem prender e sem escapar do campo.

---

## v2.3.0 — 01/08/2026

O jogo deixou de ser uma fase só.

### Por que

`LevelBuilder.LEVELS` tinha **um** mapa, e `map_for_level` usava `clampi`: a fase
7 era a fase 1 com a bola mais rápida. Somando a isso a velocidade saturando na
fase 9 e o bônus de fase na fase 5, **a partir da fase 9 o jogo era
matematicamente idêntico a si mesmo para sempre.**

### Adicionado

- **Geometria por fase.** A largura do bloco deixou de ser a constante `50` — que
  só fechava em pixel exato com 11 colunas — e passou a ser derivada em
  `ArenaLayout.brick_width(cols)`. Cada fase declara a própria grade, de 5×4 a
  16×10, e a sobra da divisão vira margem lateral centrada. Em 11 colunas o
  resultado é exatamente o de antes: bloco de 50 px, margem de 9 px.
- **Cinco fases novas**, cada uma com uma forma e uma dimensão: `ARCO` (11×8),
  `FUNIL` (13×9), `FORTALEZA` (11×9), `CORREDOR` (7×10) e `CHUVA` (15×8).
- **Rotação de mapas.** Depois da última fase a lista recomeça, no mesmo padrão
  que `clear_message` já usava.

### Alterado

- Velocidade da bola: passo por fase de 18 para 20 px/s, teto de 340 para 380.
- Teto do bônus de fase de 5000 para 8000, para as fases altas continuarem pagando.
- `SpecialBricks` lê a geometria do layout em vez de constantes globais, então a
  regra da altura mínima vale para qualquer parede — inclusive as de 10 fileiras,
  que deixam menos campo aberto abaixo do muro.

### Testes

- O soak ganhou o parâmetro de fase e **roda todas as fases nos dois formatos**.
  É o que impede um mapa bonito de ser inlimpável: com uma raquete perfeita, "não
  limpou em 400 s" só pode ser geometria ruim.
- Varredura de toda combinação de grade permitida (5–16 colunas × 4–10 fileiras ×
  4 viewports): a grade fecha em pixels inteiros, cabe no campo e fica centrada.
- O teto de `MAX_ROWS` é **derivado**: o teste prova que duas fileiras a mais já
  sufocariam a faixa de surgimento dos blocos especiais.
- As asserções da fase 1 (88 blocos, 5220 pontos, células exatas do "TJ")
  continuam intactas — são elas que provam que liberar a grade não mexeu no que
  já estava no ar.

Dois defeitos de balanceamento apareceram no soak e foram corrigidos antes de
sair: a `FORTALEZA` com os anéis fechados levava 300 s (a bola raspava a muralha
sem alcançar o miolo — ganhou portões, caiu para 114 s), e a `CHUVA` esparsa
levava 270 s porque os vãos diagonais se alinhavam em canais (ficou mais densa,
90 blocos em 171 s).

---

## v2.2.0 — 30/07/2026

Os efeitos negativos ficaram mais duros e mais legíveis.

### Adicionado

- **Número da versão no canto inferior direito do menu.** A fonte é
  `application/config/version` no `project.godot`, então o mesmo número vale para
  o jogo, para o export e para qualquer ferramenta que leia o projeto. Um teste
  confere que ele bate com a entrada mais recente deste arquivo e com o README —
  a mesma defesa contra deriva que já existe entre `ScoreRules` e o schema.

### Alterado

- **O nome do efeito apanhado agora é anunciado grande**, em escala 3 com sombra,
  no centro do campo, e fica mais tempo na tela — anúncios maiores sobem mais
  devagar e duram mais, porque um texto grande passando rápido é ilegível
  justamente quando importa. É a única informação que o jogador recebe sobre o
  que acabou de pegar.
- **SURTO**: bola de 28% para **60%** mais rápida.
- **PANICO**: raquete de 30% para **60%** mais curta.
- **DERIVA**: curva 25% mais acentuada.
- **PARANOIA**: de duas para **três** bolas fantasma.
- **DIPLOPIA**: deslocamento e opacidade da segunda imagem bem mais fortes.
- **FANTASMA** ganhou animação de assombração: os blocos mortos passaram a ser
  desenhados num **azul pálido de luar**, igual para todos — a assombração não
  pode ser confundida com o bloco colorido que ainda está lá — e **esmaecem entre
  duas posições**, a que ocupavam e a que a alucinação lhes dava, com a opacidade
  pulsando junto. Sob MIRAGEM o destino é literalmente a posição da mentira.
- **BREU**: a janela virou um **círculo** (desenhado em faixas horizontais, com o
  degrau de pixel do resto do jogo) e ficou bem mais escura.

Duas travas precisaram abrir para acomodar os novos valores:
`PowerUps.SPEED_MAX_SCALE` de 1.35 para 1.60 e
`ArenaLayout.PADDLE_MIN_WIDTH_SCALE` de 0.62 para 0.40 — a raquete no PANICO fica
com ~30 px, quase quatro vezes o diâmetro da bola, então continua sendo mira e
não sorteio.

### Corrigido

- A asserção de multibola do soak deixou de depender de uma semente cravada e
  passou a varrer algumas: qualquer ajuste de peso muda a sequência do rng, e
  aquela semente já tinha quebrado três vezes por rebalanceamento, sem nada de
  errado no código.

---

## v2.1.0 — 30/07/2026

### Corrigido

- **A bola podia ficar presa embaixo da raquete, para sempre.** `_resolve_rect`
  via a penetração vertical como a menor, empurrava a bola para baixo da raquete
  e invertia `vel.y`; em seguida `paddle_bounce` sobrescrevia a velocidade para
  cima, incondicionalmente. No quadro seguinte tudo se repetia, com a bola
  parada no mesmo pixel e a partida sem fim. Agora a raquete só rebate pelo
  **topo**: quem passou por baixo cai e é perdida, como deve ser.

  O defeito existia desde a v1.0.0 e só apareceu quando o aumento de frequência
  do SURTO deixou a bola rápida por mais tempo. O soak acusou com 19934 rebatidas
  em 400 s e a parede nunca terminando. Há teste de regressão dedicado.

### Alterado

- **Sorteio de cápsulas agora é ponderado.** Cada item tem um `weight`, e o
  ajuste pedido: **SURTO** de 25% para 50% das cápsulas comuns, **CISAO** de 10%
  para 31% das raras. São os dois itens que mais mudam a partida — um apertando o
  ritmo, o outro enchendo a tela de bolas.

---

## v2.0.0 — 30/07/2026

O marco de conteúdo: as alucinações, que são a alma do jogo, mais a multibola.

### Adicionado

- **Sete alucinações.** **MIRAGEM** (os blocos trocam de lugar, só visualmente),
  **VERTIGEM** (os comandos invertem), **DERIVA** (a bola encurva), **PARANOIA**
  (bolas fantasma que não colidem), **FANTASMA** (blocos destruídos continuam
  aparecendo), **DIPLOPIA** (o campo desenhado duas vezes, deslocado) e **BREU**
  (escuridão exceto uma janela em volta da bola).
- **CISAO**: divide cada bola em três, até seis simultâneas. Perder uma não custa
  nada — só a última bola tira vida.
- Sete de dez cápsulas raras são alucinações, então o bloco que surge no meio da
  fase vale mais justamente porque provavelmente vai sabotar quem o quebra.

### Alterado

- **A `Arena` passou a trabalhar com uma lista de bolas** em vez de uma só.
  Os alvos são remontados antes de cada bola: o mapa `consumed` do `BallPhysics`
  vale por chamada, e sem remontar duas bolas cobrariam o mesmo bloco no mesmo
  quadro.
- `SpecialBricks.pick_cell` recebe a lista de bolas e checa todas — com multibola,
  olhar só uma deixaria as outras serem atropeladas por um bloco novo.
- **BREU mantém a faixa da raquete iluminada.** Escurecê-la também transformava o
  efeito em sorte em vez de perícia: o jogador precisa ver as próprias mãos. O
  que o BREU tira é o cenário.

### A regra que sustenta tudo

Cinco das sete alucinações não tocam a simulação em nada. Elas vivem num canal
separado, lido apenas dentro do código de desenho. O soak roda uma partida
inteira com cada efeito visual forçado e exige duração, rebatidas, combo e parede
**idênticos** aos da partida sem ele — mais um controle com efeito do canal de
jogo, que precisa mudar a partida, senão o teste passaria com tudo quebrado.

MIRAGEM é uma **bijeção** sobre os blocos vivos: a silhueta da parede fica pixel a
pixel igual. A curva da DERIVA é **oscilante**, com integral zero num período, em
vez de constante — uma rotação constante brigaria com a trava de ângulo mínimo
vertical e faria a bola orbitar a raquete para sempre.

3264 asserts no total (eram 2893).

---

## v1.2.0 — 30/07/2026

Fundação dos power-ups, com os seis itens clássicos. As alucinações vêm na
v2.0.0, sobre esta base.

> **Antes de publicar:** rode `supabase/migrations/001_teto_plausibilidade.sql`
> no SQL Editor do Supabase. O servidor precisa aceitar a faixa nova de pontuação
> antes de existir cliente capaz de produzi-la.

### Adicionado

- **Cápsulas de power-up.** Blocos especiais soltam itens que descem pela tela e
  a raquete apanha: **LUCIDEZ** (raquete larga), **CALMA** (bola lenta),
  **FOLEGO** (+1 vida), **EUFORIA** (pontos), **PANICO** (raquete curta) e
  **SURTO** (bola rápida). Todo item é um estado mental — o cardápio se lê como
  uma lista de sintomas.
- **Cápsulas quase idênticas de propósito.** Mesma cor, formato e chanfro; o que
  distingue é um sigilo de 5×3 pixels e uma variação de tom de no máximo 6%, sem
  correlação com o efeito. A faixa de efeitos no campo desenha os mesmos sigilos,
  então a associação se aprende jogando, sem tutorial. Um único som de coleta,
  para o áudio não entregar o item.
- **Blocos especiais em duas variedades.** Dois fixos no mapa (símbolo `S`), e
  outros que **surgem durante a partida** com 3 hp e itens raros. O surgimento
  tem aviso prévio de 0,7 s, nunca acontece em cima da bola nem na trajetória dos
  próximos 0,55 s, e nunca abaixo da altura que garante 0,9 s de queda — é isso
  que faz de apanhar uma escolha, e não uma emboscada.
- **Multiplicador de risco**, até 2,5× por bloco. Itens benignos têm risco
  negativo: acumular só vantagem reduz o que se ganha.
- Três módulos puros novos — `power_ups.gd`, `capsules.gd`, `special_bricks.gd` —
  e as suítes de teste correspondentes. O soak test passou a rodar três políticas
  (`off`, `catch`, `dodge`) chamando exatamente as mesmas funções que a `Arena`.

### Alterado

- **Teto de plausibilidade do servidor** de 1200 para 2400 pts/s (base 5000 →
  20000), derivado do novo máximo teórico por bloco. Os números viraram
  `ScoreRules.PLAUSIBLE_POINTS_PER_SECOND` e `PLAUSIBLE_BASE`, com um teste que
  lê o `schema.sql` e falha se divergirem — antes estavam escritos à mão em três
  lugares e nada impedia a deriva.
- `ArenaLayout.paddle_rect` e `docked_ball_position` aceitam `width_scale`;
  `Arena._remap` virou `ArenaLayout.remap_axis`, agora testável sem nós.
- A fase 1 trocou dois blocos comuns por especiais: o teto base foi de 5000 para
  5220 pontos. O easter egg "TJ" ficou intacto.
- O autoteste de integração usa semente fixa e falha se nenhum bloco especial
  surgir.

### Corrigido

- A lista de cobertura de glifos da fonte estava desatualizada desde a v1.1.0 —
  os textos do menu de pause nunca tinham sido incluídos. Os rótulos de power-up
  agora são varridos direto do catálogo, então um nome novo sem glifo quebra o
  teste sozinho.

---

## v1.1.0 — 30/07/2026

### Corrigido

- **Ranking global não carregava no navegador**, exibindo `FALHA DE REDE (8)`. O
  código 8 é `RESULT_BODY_DECOMPRESS_FAILED`, e não `RESULT_REQUEST_FAILED`
  (que vale 9), então caía no texto de erro genérico. A Cloudflare do Supabase
  responde com `Content-Encoding: gzip`; na web o `fetch()` do navegador já
  entrega o corpo descomprimido mas mantém o cabeçalho, e o Godot tentava
  descomprimir JSON puro. `accept_gzip` agora fica desligado apenas na web.
- **Build web engordava a cada exportação** (91 KB → 117 KB no `.pck`). O Godot
  importava os PNGs que ele mesmo tinha acabado de exportar em `docs/`, e eles
  voltavam para dentro do pacote seguinte. Resolvido com `docs/.gdignore`.

### Alterado

- **Pause virou menu**, com os botões `CONTINUAR` e `SAIR PARA O INÍCIO` em cinza
  sobre branco, preservando o disfarce de escritório. Clique fora dos botões não
  faz mais nada — antes, clique em qualquer lugar despausava, e com um menu na
  tela sair por engano custaria a corrida inteira. `P` e `Esc` seguem sendo o
  despause de uma tecla. Sair pelo menu abandona a partida sem enviar pontuação.
- **A raquete não volta mais ao centro** a cada vida perdida e a cada fase nova.
  No mouse isso era invisível, porque o cursor reassumia a posição no quadro
  seguinte; no teclado ela teleportava para o meio da tela. A posição central
  agora só vale no começo de uma partida.

---

## v1.0.0 — 30/07/2026

Primeira versão jogável: uma fase, gráficos e efeitos completos, lógica coberta
por testes headless. Leaderboard global no Supabase, controles de mouse, teclado
e toque, pause discreto e publicação no GitHub Pages.

Tiros, power-ups e aceleração temporária ficam para etapas seguintes.
