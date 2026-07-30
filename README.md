# Arkanoia

Clone de Arkanoid em Godot 4.6, para embutir na seção secreta de jogos do projeto
de ferramentas do TJ-PR. Roda em navegador desktop e mobile, com leaderboard
global no Supabase.

**Versão 1: uma fase, gráficos e efeitos completos, lógica testada.** Tiros,
power-ups e aceleração temporária ficam para etapas seguintes.

---

## Como jogar

| Ação | Desktop | Mobile |
|---|---|---|
| Mover a raquete | mouse, ou `A`/`D`, ou `←`/`→` | arrastar o dedo |
| Lançar a bola | clique, `W`, `↑` ou espaço | toque |
| Pause discreto | `P` ou `Esc` | ícone no canto do HUD |
| Ligar/desligar som | `M` | `M` |

O **pause discreto** é modo emergência de escritório: a tela fica inteiramente
branca com `PAUSE` em cinza claro no centro, e o áudio é silenciado no mesmo
instante. Nada de cores ou logotipo — de longe não parece um jogo.

### Progressão

A fase 1 tem 88 blocos em 11×8. Ao limpar a parede, o jogo avança de fase com o
mesmo mapa e bola mais rápida — o placar é a métrica, não o "final". O combo
multiplica os pontos em até 4× enquanto a bola não voltar à raquete.

Dez blocos reforçados azuis desenham as letras **T** e **J** no meio da parede, e
dois blocos dourados valem 200 pontos. Ao limpar a fase aparece uma mensagem
rotativa (`AUTOS BAIXADOS`, `TRANSITADO EM JULGADO`, ...).

---

## Arquitetura

```
main.gd / main.tscn     raiz: monta a árvore, alterna telas, controla o pause
src/core/               camada pura (sem nós, sem SceneTree) + autoloads
  arena_layout.gd       matemática do layout adaptativo 16:9 <-> 9:16
  ball_physics.gd       integração com sub-passos e resolução AABB
  level_builder.gd      fases a partir de mapas em texto
  score_rules.gd        pontuação, combo, bônus, velocidade
  nick_util.gd          sanitização do nick
  text_util.gd          formatação de data e placar
  pixel_font.gd         fonte bitmap 5x7 gerada em runtime
  palette.gd            paleta fixa
  input_setup.gd        registro das ações de entrada
  supabase_config.gd    URLs, cabeçalhos e corpo do POST
  game_state.gd         autoload: estado da partida e persistência
  sfx.gd                autoload: sintetizador chiptune
  leaderboard.gd        autoload: única camada que conhece o transporte HTTP
src/game/               arena.gd (gameplay + desenho), fx.gd (partículas)
src/ui/                 hud, title_screen, pause_overlay, game_over, leaderboard_view
tests/run_tests.gd      suíte headless
supabase/schema.sql     schema do leaderboard
web/exemplo-embed.html  exemplo de página hospedeira
```

Três decisões que explicam o resto:

**Zero assets binários.** A fonte é um atlas 5×7 gerado de strings embutidas
(`pixel_font.gd`), os sons são ondas quadradas/triangulares/ruído sintetizadas em
`AudioStreamWAV` (`sfx.gd`), e os gráficos são `draw_rect` com chanfro de 1 px.
O repositório não tem PNG nem WAV, o build web fica leve e nada depende de
importação de recursos.

**A árvore é construída em código, não em `.tscn`.** Todos os nós são simples
(`Node2D`/`Control` com `_draw` próprio). Cenas empacotadas só adicionariam
arquivos frágeis por UID sem trazer benefício.

**Física própria, não o motor.** Arkanoid depende de reflexão previsível e de um
ângulo de saída da raquete definido por design. `ball_physics.gd` é código puro,
determinístico e testável headless.

### Layout adaptativo

Com `stretch/mode=canvas_items` e `aspect=expand` sobre a base 640×360, a
viewport lógica nunca fica menor que 640×360: em tela estreita a largura fica em
640 e a altura cresce; em tela larga a altura fica em 360 e a largura cresce.
Por isso a largura do campo é **fixa** em 588 px lógicos e centralizada, e só a
altura se adapta.

Duas consequências tratadas explicitamente:

- `speed_scale` cresce com a altura do campo, para o tempo de travessia da bola
  ser praticamente o mesmo em paisagem e em retrato.
- A **altura** do bloco acompanha o campo (15 a 34 px). Sem isso, em retrato o
  muro viraria uma faixa fina perdida no topo de uma tela de 1200 px.

---

## Testes

```bash
./scripts/test.sh          # suíte da camada pura
./scripts/test.sh --all    # + autoteste de integração
```

Ou diretamente:

```bash
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . -- --arkanoia-selftest
```

> Não passe `--fixed-fps` no autoteste. O timeout do `HTTPRequest` conta tempo de
> processamento, então com o relógio acelerado a chamada ao Supabase expira em
> ~0,1 s reais e o teste do caminho HTTP fica inconclusivo (`TEMPO ESGOTADO`).

**Suíte pura** (2244 asserções): layout nos quatro formatos, física da bola
(reflexão, antitunelamento, ângulo da raquete, componente vertical mínimo),
construção da fase, pontuação, sanitização do nick, cobertura de glifos para
**todo** texto que o jogo escreve na tela, e construção das URLs do Supabase.

Termina com um **soak test** que simula partidas completas em paisagem e retrato
usando exatamente a mesma matemática do jogo, com uma raquete automática
perfeita. Ele exige que a parede inteira caia, que a bola nunca escape do campo,
e que o placar resultante passe no `CHECK` de plausibilidade do schema SQL.

Esse soak test encontrou dois defeitos reais durante o desenvolvimento:

1. Uma rebatida no centro exato da raquete devolvia a bola **perfeitamente
   vertical**. Depois de abrir uma coluna na parede, ela subia pelo canal vazio,
   batia no teto e voltava ao mesmo ponto — loop infinito que nunca mais atingia
   um bloco. Corrigido com `BallPhysics.MIN_PADDLE_ANGLE`.
2. Em retrato, com `MAX_SPEED_SCALE` travado em 2.0, o campo ficava
   desproporcionalmente lento e o muro virava uma faixa fina no topo. Corrigido
   com a altura de bloco dinâmica e o teto de escala em 3.4.

**Autoteste de integração** roda a árvore real (`Arena`, `Hud`, `Fx`, telas,
envio ao leaderboard) com piloto automático: joga, erra de propósito para gastar
as três vidas, verifica o fim de partida, o recorde local e o placar, e sai com
código 0 ou 1.

---

## Supabase

### 1. Rodar o schema

Abra o SQL Editor do projeto e execute `supabase/schema.sql` inteiro, uma vez.
Ele cria a tabela `scores`, a view `leaderboard`, as políticas de RLS, os
privilégios por coluna e o trigger de rate limit.

**Status verificado em 30/07/2026** (por `curl` e pelo autoteste de integração):

| Item | Resultado |
|---|---|
| URL e chave publishable | válidas — a requisição autentica e chega ao PostgREST |
| CORS | `access-control-allow-origin: *`, então GitHub Pages funciona |
| Caminho HTTP do cliente Godot | funciona — mesma resposta que o `curl` |
| View `leaderboard` | **não existe ainda** → `404 PGRST205` |

Ou seja: o único passo pendente é executar o schema. Um `401` indicaria chave
inválida; o `404` prova que a autenticação passou e só o objeto está faltando.

### 2. Credenciais

Já embutidas em `src/core/supabase_config.gd`:

```
URL: https://aqcpaqjvsdsyxlmnbvav.supabase.co
Key: sb_publishable_...  (chave publishable, feita para viver no cliente)
```

A **connection string do Postgres não é usada e não deve ser colocada aqui.**
O jogo fala com a REST API por HTTPS, nunca com o Postgres direto. Uma
`service_role` key ou uma senha de banco num build web público equivale a
publicar acesso total ao banco. A suíte de testes tem asserções que falham se
alguém colar uma delas em `supabase_config.gd`.

Para apontar o jogo para outro projeto sem recompilar, veja o comentário no fim
de `web/exemplo-embed.html`.

### 3. Modelo de segurança da versão 1

A proteção **não** vem do sigilo da chave — ela é pública por design. Vem de:

- RLS com apenas `SELECT` e `INSERT` para `anon`. Nenhuma política de `UPDATE`
  ou `DELETE`, portanto ambos são proibidos.
- Privilégios por coluna: o cliente não escreve `id`, `created_at` nem
  `client_fingerprint`, e não **lê** `client_fingerprint`.
- `CHECK` constraints no formato do nick (espelhando `NickUtil.sanitize`), na
  faixa do placar e na relação placar/duração.
- Trigger de rate limit por origem (5 envios por minuto), devolvendo HTTP 429.
- View `leaderboard` com a melhor pontuação **por nick**, para um único jogador
  não ocupar as dez posições.

Sendo direto sobre o limite disso: **alguém determinado ainda consegue montar um
POST plausível via `curl`.** Isso é inerente a jogo estático com escrita
anônima. As barreiras acima param vandalismo casual e placares absurdos, não um
atacante motivado.

### 4. Endurecer o leaderboard (etapa 2)

`src/core/leaderboard.gd` é a única camada que conhece o transporte. O jogo só
usa `fetch_top()`, `submit()` e os sinais. Trocar o REST direto por uma Edge
Function não exige mexer em mais nada:

1. `POST /functions/v1/arkanoia-start` devolve um token de sessão assinado.
2. O jogo joga e envia `{ token, score, ticks, seed }`.
3. A função valida placar/tempo, confere que o token não foi reusado, e só então
   insere com a `service_role` key (que nunca sai do servidor).
4. Revogar o `INSERT` de `anon` em `public.scores`.

---

## Publicar

### Instalar os export templates (pendente)

O export HTML5 precisa dos templates, que **não estão instalados** nesta máquina:

> Editor do Godot → menu **Editor** → **Manage Export Templates** →
> **Download and Install**

São ~800 MB e precisam bater com a versão do editor (atualmente
`4.6.rc1.official`). Sem eles, `--export-release Web` falha com
`No export template found`.

Se preferir usar o Godot 4.6 estável em vez do RC, troque também a versão dos
templates — o preset em `export_presets.cfg` continua o mesmo.

### Exportar

```bash
godot --headless --path . --export-release Web docs/index.html
```

O preset já está configurado com o que importa:

- `variant/thread_support=false` — threads em WebAssembly exigem
  `SharedArrayBuffer`, que depende dos cabeçalhos COOP/COEP. **O GitHub Pages não
  permite configurar cabeçalhos**, então o build tem que ser sem threads.
  `leaderboard.gd` já usa `use_threads = not OS.has_feature("web")`.
- `html/canvas_resize_policy=2` — o canvas acompanha o container, que é o que faz
  o layout adaptativo funcionar dentro do iframe.
- `exclude_filter="tests/*"` — a suíte não vai para o build.
- Renderer GL Compatibility, já configurado em `project.godot`, para máxima
  compatibilidade com navegador e mobile.

### GitHub Pages

Publique a pasta `docs/` (Settings → Pages → Source: branch, pasta `/docs`).
Depois embuta na página do TJ-PR seguindo `web/exemplo-embed.html`.

---

## Próximas etapas

Ordem sugerida, do mais barato ao mais caro:

1. **Rodar `supabase/schema.sql`** — sem isso o leaderboard não funciona.
2. **Instalar os export templates e gerar o build** — único passo que falta para
   ter o HTML publicável.
3. **Power-ups**: tiros, raquete larga, bola lenta, multibola, vida extra. Os
   blocos já carregam `type`, então soltar power-up ao destruir é natural.
4. **Mais fases**: adicionar mapas em `LevelBuilder.LEVELS`. O formato é texto de
   11×8 e a suíte já valida qualquer fase nova.
5. **Edge Function de validação** (seção 4 acima).
6. **Música de fundo** em loop, sintetizada como os efeitos.
