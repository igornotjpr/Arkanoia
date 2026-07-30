## Blocos especiais que surgem durante a partida. Codigo puro e testavel.
##
## O bloco fixo do mapa (simbolo 'S') e responsabilidade do LevelBuilder. Este
## modulo cuida do outro tipo: o que materializa no meio da fase, aguenta mais
## batidas e solta uma capsula do nivel raro.
##
## A REGRA DA ALTURA MINIMA
## ------------------------
## O pedido era que o bloco nao aparecesse baixo demais, a ponto de a capsula
## chegar antes de o jogador ter tempo de decidir. Se o surgimento ficasse restrito
## a parede 11x8, a regra jamais dispararia: a parede termina a mais de 80 px da
## raquete em qualquer formato, o que ja da mais de 1,5 s de queda.
##
## A regra so vira real porque o bloco PODE surgir abaixo da parede, no campo
## aberto. E isso sai praticamente de graca: ArenaLayout.brick_rect e multiplicacao
## pura, entao row 8, 9, 10... ja desenha fora da grade, e a Arena reconstroi todo
## retangulo a partir de col/row ao girar a tela - um bloco solto sobrevive a
## rotacao sem uma linha de codigo nova.
class_name SpecialBricks
extends RefCounted

## Tempo minimo de queda da capsula, do pe do bloco ate a raquete.
const MIN_REACTION_SECONDS := 0.9

## Quantas fileiras abaixo da parede um bloco pode surgir. Trava independente da
## altura minima: em retrato o campo e tao alto que a regra de tempo sozinha
## deixaria o bloco nascer quase em cima da raquete e ainda assim "com folga".
const EXTRA_ROWS := 4

const TELEGRAPH_SECONDS := 0.7
const ROLL_INTERVAL_MIN := 12.0
const ROLL_INTERVAL_MAX := 22.0
const RETRY_SECONDS := 1.5

const MAX_ALIVE := 2

## Abaixo disso o sorteio para: um bloco novo no fim da fase so faria o jogador
## cacar o ultimo tijolo por mais meio minuto.
const STOP_WHEN_ALIVE_BELOW := 8

const SPAWNED_HP := 3
const SPAWNED_POINTS := 320

## Trecho da trajetoria futura da bola mantido livre, em segundos.
const BALL_LOOKAHEAD := 0.55
const LOOKAHEAD_SAMPLES := 8


## Fileira mais baixa em que um bloco pode surgir, dado o layout e a velocidade
## de queda da capsula.
static func max_spawn_row(layout: Dictionary, capsule_speed: float) -> int:
	var ceiling := ArenaLayout.ROWS - 1 + EXTRA_ROWS
	if capsule_speed <= 0.0:
		return ArenaLayout.ROWS - 1

	var paddle_y := float(layout["paddle_y"])
	for row in range(ceiling, ArenaLayout.ROWS - 2, -1):
		var bottom := ArenaLayout.brick_rect(layout, 0, row).end.y
		if (paddle_y - bottom) / capsule_speed >= MIN_REACTION_SECONDS:
			return row

	# A parede original e sempre elegivel: ela ja existe ali de qualquer forma.
	return ArenaLayout.ROWS - 1


## Intervalo ate o proximo sorteio.
static func next_interval(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(ROLL_INTERVAL_MIN, ROLL_INTERVAL_MAX)


## Celulas sem bloco vivo, de row 0 ate max_row.
static func free_cells(bricks: Array, max_row: int) -> Array:
	var taken := {}
	for brick in bricks:
		if bool(brick["alive"]):
			taken[Vector2i(int(brick["col"]), int(brick["row"]))] = true

	var cells: Array = []
	for row in range(0, max_row + 1):
		for col in range(ArenaLayout.COLS):
			var cell := Vector2i(col, row)
			if not taken.has(cell):
				cells.append(cell)
	return cells


## True quando materializar um bloco nesta celula nao atropela a bola.
##
## Sem esta checagem, BallPhysics._resolve_rect ejetaria a bola sobreposta pelo
## eixo de menor penetracao - um teleporte visivel e inexplicavel para quem joga.
##
## A trajetoria futura e amostrada em vez de resolvida analiticamente: a bola
## ricocheteia, entao a reta so vale para o proximo meio segundo de qualquer
## forma, e amostrar mantem a funcao trivial de ler e de testar.
static func is_cell_safe(cell_rect: Rect2, ball_pos: Vector2, ball_vel: Vector2,
		radius: float, lookahead: float) -> bool:
	var guarded := cell_rect.grow(radius + 2.0)
	if guarded.has_point(ball_pos):
		return false

	for i in range(1, LOOKAHEAD_SAMPLES + 1):
		var t := lookahead * float(i) / float(LOOKAHEAD_SAMPLES)
		if guarded.has_point(ball_pos + ball_vel * t):
			return false

	return true


## Sorteia uma celula livre e segura. Devolve Vector2i(-1, -1) quando nao ha.
static func pick_cell(rng: RandomNumberGenerator, cells: Array, layout: Dictionary,
		ball_pos: Vector2, ball_vel: Vector2, radius: float) -> Vector2i:
	var pool := cells.duplicate()
	while not pool.is_empty():
		var index := rng.randi_range(0, pool.size() - 1)
		var cell: Vector2i = pool[index]
		pool.remove_at(index)

		var cell_rect := ArenaLayout.brick_rect(layout, cell.x, cell.y)
		if is_cell_safe(cell_rect, ball_pos, ball_vel, radius, BALL_LOOKAHEAD):
			return cell

	return Vector2i(-1, -1)


## Bloco pronto para entrar em Arena._bricks, com todas as chaves que ela le.
static func make_brick(id: int, cell: Vector2i, layout: Dictionary) -> Dictionary:
	return {
		"id": id,
		"col": cell.x,
		"row": cell.y,
		"hp": SPAWNED_HP,
		"max_hp": SPAWNED_HP,
		"type": LevelBuilder.TYPE_SPECIAL_SPAWNED,
		"color": Palette.SPECIAL,
		"points": SPAWNED_POINTS,
		"alive": true,
		"flash": 0.0,
		"kind": BallPhysics.KIND_BRICK,
		"rect": ArenaLayout.brick_rect(layout, cell.x, cell.y),
	}
