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

## Pontos de EUFORIA, antes do multiplicador de risco.
const BONUS_POINTS := 750

## Travas dos escalares. Ficam aqui, e nao no ArenaLayout, porque limitam a
## COMPOSICAO de varios efeitos - o layout so conhece um fator de cada vez.
const SPEED_MIN_SCALE := 0.72
const SPEED_MAX_SCALE := 1.35

## Catalogo. Cada entrada:
##   label          texto do popup ao apanhar (maiusculas, sem acento)
##   channel        CHANNEL_PLAY ou CHANNEL_VISUAL
##   duration       segundos; 0.0 marca efeito instantaneo, que nunca entra no
##                  conjunto ativo (a Arena resolve na hora e pronto)
##   risk           peso somado em risk_level(); NEGATIVO nos itens benignos
##   tier           de qual bloco especial este item cai
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


## Sorteia o item solto por um bloco. Devolve "" quando o bloco nao solta nada.
##
## O rng vem de fora, sempre: e o que torna uma corrida reproduzivel nos testes.
static func roll_drop(rng: RandomNumberGenerator, brick_type: int) -> String:
	var table := drop_table(brick_type)
	if table.is_empty():
		return ""
	return str(table[rng.randi_range(0, table.size() - 1)])
