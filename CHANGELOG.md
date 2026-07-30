# Changelog

Versionamento semântico: `MAJOR.MINOR.PATCH`. Neste projeto, **MAJOR** muda
quando o jogo ganha um marco de conteúdo (as alucinações, novas fases), **MINOR**
quando entra comportamento novo dentro do marco atual, e **PATCH** quando é só
correção.

Cada versão é uma tag anotada em `main`. Para ver o que uma tag carrega:

```bash
git show v1.1.0            # a anotação e o commit
git log v1.0.0..v1.1.0     # tudo que entrou entre as duas
```

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
