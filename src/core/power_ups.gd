## Catalogo de power-ups e aritmetica do conjunto ativo. Codigo puro e testavel.
##
## Todo item do jogo e um ESTADO MENTAL, bom ou ruim. O cardapio inteiro se le
## como uma lista de sintomas, e a piada do nome do jogo se sustenta sozinha, sem
## uma linha de tutorial.
##
## O conjunto ativo e um Dictionary simples { id: String -> segundos restantes }.
## Nao ha classe, nao ha no: e exatamente essa escolha que permite ao soak test
## exercitar os power-ups sem instanciar a Arena.
##
## REGRA DO CANAL VISUAL
## ---------------------
## Um efeito CHANNEL_VISUAL so pode ser lido dentro de Arena._draw* e do Fx.
## Nunca em _update_paddle, _simulate_ball, _hit_brick, nem em nada que escreva
## em _bricks. E isso que da as alucinacoes superficie de trapaca zero: elas
## custam pontos porque a MAO do jogador piora, nao porque a fisica mudou.
## A regra e garantida pelo teste, nao pela disciplina - ver _test_power_ups.
class_name PowerUps
extends RefCounted

const CHANNEL_PLAY := 0     # altera a simulacao
const CHANNEL_VISUAL := 1   # so desenho

const TIER_COMMON := 0      # cai do bloco especial fixo do mapa
const TIER_RARE := 1        # cai do bloco especial que surge durante a partida

const WIDE := "wide"
const SLOW := "slow"
const LIFE := "life"
const BONUS := "bonus"
const NARROW := "narrow"
const FAST := "fast"
const MULTI := "multi"

## As alucinacoes. Sete das oito nao tocam a simulacao: elas custam pontos porque
## a MAO do jogador piora, nao porque a fisica mudou. A excecao e VERTIGEM, que
## inverte o controle de verdade - por isso e a unica no canal de jogo.
const SHUFFLE := "shuffle"
const MIRROR := "mirror"
const CURVE := "curve"
const DECOY := "decoy"
const GHOST := "ghost"
const HAZE := "haze"
const DARK := "dark"

## Pontos de EUFORIA, antes do multiplicador de risco.
const BONUS_POINTS := 750

## Travas dos escalares. Ficam aqui, e nao no ArenaLayout, porque limitam a
## COMPOSICAO de varios efeitos - o layout so conhece um fator de cada vez.
const SPEED_MIN_SCALE := 0.72
const SPEED_MAX_SCALE := 1.35

## MULTIBOLA. Cada bola vira SPLIT_COUNT, ate o teto simultaneo. Acima de 6 a
## tela vira sopa e o jogador perde de vista qual bola importa.
const MAX_BALLS := 6
const SPLIT_COUNT := 3
const SPLIT_SPREAD := 0.42   # radianos entre as bolas irmas

## DERIVA. A rotacao e OSCILANTE, nunca constante: por alternar de sinal ela nao
## acumula, se autocorrige e nunca encosta na trava de angulo minimo vertical do
## BallPhysics. Desenha um S, e nao uma espiral que orbitaria a raquete para
## sempre - a mesma classe de defeito que MIN_PADDLE_ANGLE existe para evitar.
const CURVE_FREQUENCY := 3.0    # radianos por segundo de fase
const CURVE_AMPLITUDE := 1.2    # radianos por segundo no pico

## PARANOIA: quantas bolas falsas acompanham as verdadeiras.
const DECOY_COUNT := 2

## Catalogo. Cada entrada:
##   label          texto do popup ao apanhar (maiusculas, sem acento)
##   channel        CHANNEL_PLAY ou CHANNEL_VISUAL
##   duration       segundos; 0.0 marca efeito instantaneo, que nunca entra no
##                  conjunto ativo (a Arena resolve na hora e pronto)
##   risk           peso somado em risk_level(); NEGATIVO nos itens benignos
##   tier           de qual bloco especial este item cai
##   weight         chance relativa dentro do tier; ausente vale 1.0
##   paddle_factor  multiplicador da largura da raquete
##   speed_factor   multiplicador da velocidade da bola
##   sigil          3 linhas de 5 caracteres, '#' aceso e '.' apagado
##   shade          variacao de tom da capsula, -0.06..0.06
##
## Sobre o sigilo e o tom: as capsulas sao QUASE IDENTICAS de proposito. Mesma
## cor base, mesmo formato, mesmo chanfro. O sigilo e abstrato em vez de usar a
## PixelFont porque uma letra de 5x7 seria legivel de imediato e mataria a
## mecanica. E o tom NAO tem correlacao com o risco: uma capsula mais clara tem a
## mesma chance de ser bencao ou maldicao. Quem decora os sigilos passa a acertar;
## quem nao decora aposta.
const EFFECTS := {
	WIDE: {
		"label": "LUCIDEZ",
		"channel": CHANNEL_PLAY,
		"duration": 12.0,
		"risk": -1,
		"tier": TIER_COMMON,
		"paddle_factor": 1.45,
		"speed_factor": 1.0,
		"sigil": ["..#..", "#####", "..#.."],
		"shade": 0.04,
	},
	SLOW: {
		"label": "CALMA",
		"channel": CHANNEL_PLAY,
		"duration": 12.0,
		"risk": -1,
		"tier": TIER_COMMON,
		"paddle_factor": 1.0,
		"speed_factor": 0.78,
		"sigil": [".....", "#####", "....."],
		"shade": -0.05,
	},
	NARROW: {
		"label": "PANICO",
		"channel": CHANNEL_PLAY,
		"duration": 10.0,
		"risk": 2,
		"tier": TIER_COMMON,
		"paddle_factor": 0.70,
		"speed_factor": 1.0,
		"sigil": ["#...#", ".#.#.", "..#.."],
		"shade": 0.05,
	},
	FAST: {
		"label": "SURTO",
		"channel": CHANNEL_PLAY,
		"duration": 10.0,
		"risk": 2,
		"tier": TIER_COMMON,
		"weight": 3.0,
		"paddle_factor": 1.0,
		"speed_factor": 1.28,
		"sigil": ["..#..", ".###.", "#####"],
		"shade": -0.06,
	},
	LIFE: {
		"label": "FOLEGO",
		"channel": CHANNEL_PLAY,
		"duration": 0.0,
		"risk": 0,
		"tier": TIER_RARE,
		"paddle_factor": 1.0,
		"speed_factor": 1.0,
		"sigil": [".#.#.", "#####", ".#.#."],
		"shade": -0.02,
	},
	BONUS: {
		"label": "EUFORIA",
		"channel": CHANNEL_PLAY,
		"duration": 0.0,
		"risk": 0,
		"tier": TIER_RARE,
		"paddle_factor": 1.0,
		"speed_factor": 1.0,
		"sigil": ["#.#.#", ".#.#.", "#.#.#"],
		"shade": 0.06,
	},
	MULTI: {
		"label": "CISAO",
		"channel": CHANNEL_PLAY,
		"duration": 0.0,
		"risk": -1,
		"tier": TIER_RARE,
		"weight": 4.0,
		"paddle_factor": 1.0,
		"speed_factor": 1.0,
		"sigil": ["#...#", ".....", "#...#"],
		"shade": -0.04,
	},

	# --- Alucinacoes ---------------------------------------------------------
	SHUFFLE: {
		"label": "MIRAGEM",
		"channel": CHANNEL_VISUAL,
		"duration": 9.0,
		"risk": 2,
		"tier": TIER_RARE,
		"paddle_factor": 1.0,
		"speed_factor": 1.0,
		"sigil": [".#.#.", "..#..", ".#.#."],
		"shade": 0.03,
	},
	MIRROR: {
		"label": "VERTIGEM",
		"channel": CHANNEL_PLAY,
		"duration": 8.0,
		"risk": 3,
		"tier": TIER_RARE,
		"paddle_factor": 1.0,
		"speed_factor": 1.0,
		"invert_axis": true,
		"sigil": ["##.##", "..#..", "##.##"],
		"shade": -0.01,
	},
	CURVE: {
		"label": "DERIVA",
		"channel": CHANNEL_PLAY,
		"duration": 10.0,
		"risk": 2,
		"tier": TIER_RARE,
		"paddle_factor": 1.0,
		"speed_factor": 1.0,
		"sigil": ["#....", ".###.", "....#"],
		"shade": 0.02,
	},
	DECOY: {
		"label": "PARANOIA",
		"channel": CHANNEL_VISUAL,
		"duration": 9.0,
		"risk": 1,
		"tier": TIER_RARE,
		"paddle_factor": 1.0,
		"speed_factor": 1.0,
		"sigil": ["#.#..", ".....", "..#.#"],
		"shade": -0.03,
	},
	GHOST: {
		"label": "FANTASMA",
		"channel": CHANNEL_VISUAL,
		"duration": 8.0,
		"risk": 2,
		"tier": TIER_RARE,
		"paddle_factor": 1.0,
		"speed_factor": 1.0,
		"sigil": [".###.", ".#.#.", ".###."],
		"shade": 0.01,
	},
	HAZE: {
		"label": "DIPLOPIA",
		"channel": CHANNEL_VISUAL,
		"duration": 9.0,
		"risk": 1,
		"tier": TIER_RARE,
		"paddle_factor": 1.0,
		"speed_factor": 1.0,
		"sigil": ["##...", ".....", "...##"],
		"shade": 0.0,
	},
	DARK: {
		"label": "BREU",
		"channel": CHANNEL_VISUAL,
		"duration": 7.0,
		"risk": 2,
		"tier": TIER_RARE,
		"paddle_factor": 1.0,
		"speed_factor": 1.0,
		"sigil": ["#####", "#...#", "#####"],
		"shade": 0.055,
	},
}

## Pares que se cancelam. Apanhar SURTO enquanto CALMA corre nao empilha: remove.
## Sem isso os escalares se multiplicariam de volta para perto de 1.0 e o jogador
## veria dois efeitos ativos sem sentir nenhum dos dois.
const OPPOSITES := {
	WIDE: NARROW,
	NARROW: WIDE,
	SLOW: FAST,
	FAST: SLOW,
}


## --- Consulta ao catalogo --------------------------------------------------

static func exists(id: String) -> bool:
	return EFFECTS.has(id)


static func label(id: String) -> String:
	return str(_entry(id).get("label", ""))


static func channel(id: String) -> int:
	return int(_entry(id).get("channel", CHANNEL_PLAY))


static func is_visual(id: String) -> bool:
	return channel(id) == CHANNEL_VISUAL


static func duration(id: String) -> float:
	return float(_entry(id).get("duration", 0.0))


## Efeito que resolve na hora e nunca entra no conjunto ativo.
static func is_instant(id: String) -> bool:
	return exists(id) and duration(id) <= 0.0


static func risk(id: String) -> int:
	return int(_entry(id).get("risk", 0))


static func tier(id: String) -> int:
	return int(_entry(id).get("tier", TIER_COMMON))


## Chance relativa dentro do tier. 1.0 e a linha de base; 3.0 sai tres vezes mais.
static func weight(id: String) -> float:
	return maxf(float(_entry(id).get("weight", 1.0)), 0.0)


static func sigil(id: String) -> Array:
	var value: Variant = _entry(id).get("sigil", [])
	return value if value is Array else []


static func shade(id: String) -> float:
	return float(_entry(id).get("shade", 0.0))


## Efeito que este cancela ao ser apanhado, ou "" quando nao ha par.
static func opposite(id: String) -> String:
	return str(OPPOSITES.get(id, ""))


static func all_ids() -> Array:
	return EFFECTS.keys()


static func _entry(id: String) -> Dictionary:
	var value: Variant = EFFECTS.get(id, {})
	return value if value is Dictionary else {}


## --- Conjunto ativo --------------------------------------------------------

## Ativa um efeito, devolvendo um conjunto NOVO (nunca muta o recebido).
##
## Reapanhar renova o tempo em vez de empilhar: o mesmo id jamais aparece duas
## vezes, o que mantem todo escalar limitado e a faixa de efeitos legivel.
static func apply(active: Dictionary, id: String) -> Dictionary:
	var result := active.duplicate()
	if not exists(id) or is_instant(id):
		return result

	var pair := opposite(id)
	if not pair.is_empty():
		result.erase(pair)

	var remaining := float(result.get(id, 0.0))
	result[id] = maxf(remaining, duration(id))
	return result


## Desconta o tempo. Devolve { "active": Dictionary, "expired": Array }.
static func tick(active: Dictionary, delta: float) -> Dictionary:
	var result := {}
	var expired: Array = []

	for id in active:
		var remaining := float(active[id]) - delta
		if remaining > 0.0:
			result[id] = remaining
		else:
			expired.append(id)

	return {"active": result, "expired": expired}


## Ordem estavel para a faixa de efeitos: a ordem do catalogo, nao a de insercao.
## Sem isso os sigilos dancariam na tela a cada expiracao.
static func ordered_ids(active: Dictionary) -> Array:
	var result: Array = []
	for id in EFFECTS:
		if active.has(id):
			result.append(id)
	return result


## --- Escalares -------------------------------------------------------------

## Largura da raquete. Composicao por produto, com trava do ArenaLayout.
static func paddle_width_scale(active: Dictionary) -> float:
	var scale := 1.0
	for id in active:
		scale *= float(_entry(id).get("paddle_factor", 1.0))
	return clampf(scale, ArenaLayout.PADDLE_MIN_WIDTH_SCALE, ArenaLayout.PADDLE_MAX_WIDTH_SCALE)


## Velocidade da bola. A Arena renormaliza a magnitude todo quadro, entao este
## multiplicador e a implementacao inteira de CALMA e SURTO.
static func ball_speed_scale(active: Dictionary) -> float:
	var scale := 1.0
	for id in active:
		scale *= float(_entry(id).get("speed_factor", 1.0))
	return clampf(scale, SPEED_MIN_SCALE, SPEED_MAX_SCALE)


## Sinal do eixo de controle. -1.0 inverte os comandos (VERTIGEM, na v2.0.0).
static func paddle_axis_sign(active: Dictionary) -> float:
	var sign_value := 1.0
	for id in active:
		if bool(_entry(id).get("invert_axis", false)):
			sign_value = -sign_value
	return sign_value


## Soma dos riscos ativos. Pode ser negativa quando so ha itens benignos.
static func risk_level(active: Dictionary) -> int:
	var total := 0
	for id in active:
		total += risk(id)
	return total


## --- Alucinacoes e multibola (funcoes puras) -------------------------------

## Velocidades das bolas irmas ao dividir. A original nao entra na lista.
##
## O leque e simetrico em torno da direcao original, entao a divisao nao empurra
## o conjunto para um lado - com leque assimetrico, CISAO viraria um empurrao.
static func split_velocities(vel: Vector2, count: int, spread: float) -> Array:
	var result: Array = []
	if count <= 0 or vel == Vector2.ZERO:
		return result

	for i in range(1, count + 1):
		var step := ceili(float(i) * 0.5)
		var side := 1.0 if i % 2 == 1 else -1.0
		result.append(BallPhysics.enforce_min_vertical(vel.rotated(side * step * spread)))
	return result


## Rotacao a aplicar na velocidade neste quadro, sob DERIVA.
##
## Oscilante de proposito: a integral sobre um periodo completo e zero, entao a
## direcao MEDIA da bola nao muda e a curva nunca vira deriva permanente.
static func curve_rotation(phase: float, delta: float) -> float:
	return sin(phase * CURVE_FREQUENCY) * CURVE_AMPLITUDE * delta


## Permutacao dos blocos vivos, sob MIRAGEM. Devolve { id -> id }.
##
## E uma BIJECAO sobre o conjunto recebido: cada bloco e desenhado exatamente uma
## vez, em exatamente um lugar. A silhueta da parede fica pixel a pixel identica
## - so as cores e os valores trocam de posicao. Se fosse um sorteio livre, dois
## blocos cairiam na mesma celula e a mentira seria obvia no primeiro quadro.
static func shuffle_map(ids: Array, rng: RandomNumberGenerator) -> Dictionary:
	var shuffled := ids.duplicate()

	# Fisher-Yates com o rng recebido, para a permutacao ser reproduzivel.
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = swap

	var result := {}
	for index in ids.size():
		result[ids[index]] = shuffled[index]
	return result


## --- Sorteio ---------------------------------------------------------------

## Itens que um bloco do tipo informado pode soltar. Bloco comum nao solta nada.
static func drop_table(brick_type: int) -> Array:
	var wanted := -1
	match brick_type:
		LevelBuilder.TYPE_SPECIAL:
			wanted = TIER_COMMON
		LevelBuilder.TYPE_SPECIAL_SPAWNED:
			wanted = TIER_RARE
		_:
			return []

	var result: Array = []
	for id in EFFECTS:
		if tier(id) == wanted:
			result.append(id)
	return result


## Soma dos pesos de um tier. Serve para conferir a chance de um item nos testes.
static func total_weight(brick_type: int) -> float:
	var total := 0.0
	for id in drop_table(brick_type):
		total += weight(str(id))
	return total


## Chance de um item especifico sair do bloco informado, de 0.0 a 1.0.
static func drop_chance(id: String, brick_type: int) -> float:
	var total := total_weight(brick_type)
	if total <= 0.0 or not drop_table(brick_type).has(id):
		return 0.0
	return weight(id) / total


## Sorteia o item solto por um bloco. Devolve "" quando o bloco nao solta nada.
##
## O sorteio e PONDERADO: cada item concorre com o seu weight. CISAO e SURTO
## saem mais que os demais porque sao os dois que mais mudam a partida - um
## enchendo a tela de bolas, o outro apertando o ritmo.
##
## O rng vem de fora, sempre: e o que torna uma corrida reproduzivel nos testes.
static func roll_drop(rng: RandomNumberGenerator, brick_type: int) -> String:
	var table := drop_table(brick_type)
	if table.is_empty():
		return ""

	var total := total_weight(brick_type)
	if total <= 0.0:
		return str(table[rng.randi_range(0, table.size() - 1)])

	var pick := rng.randf() * total
	for id_variant in table:
		var id := str(id_variant)
		pick -= weight(id)
		if pick <= 0.0:
			return id

	# Guarda contra erro de arredondamento no ultimo item.
	return str(table[table.size() - 1])
