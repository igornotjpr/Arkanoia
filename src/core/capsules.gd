## Capsulas que caem dos blocos especiais. Codigo puro e testavel.
##
## Uma capsula e um Dictionary simples, como todo dado do projeto:
##   { "id": int, "item": String, "pos": Vector2, "phase": float }
##
## "pos" e o CENTRO, em coordenadas da viewport. "phase" e so brilho: nunca
## decide nada, e serve apenas para as capsulas nao pulsarem em uniao.
class_name Capsules
extends RefCounted

## Velocidade de queda a speed_scale 1.0. Como a bola, escala com a altura do
## campo - e isso que mantem o tempo de reacao igual em paisagem e em retrato.
const FALL_SPEED := 96.0

const WIDTH := 22.0
const HEIGHT_FRACTION := 0.55   # da altura do bloco, para a capsula parecer um pedaco da parede
const MIN_HEIGHT := 8.0
const MAX_HEIGHT := 16.0

## Teto de capsulas simultaneas. Mais que isso e o jogador perde a bola de vista.
const MAX_ACTIVE := 4


static func speed(layout: Dictionary) -> float:
	return FALL_SPEED * float(layout["speed_scale"])


static func size(layout: Dictionary) -> Vector2:
	var brick: Vector2 = layout["brick_size"]
	return Vector2(WIDTH, clampf(brick.y * HEIGHT_FRACTION, MIN_HEIGHT, MAX_HEIGHT))


static func make(id: int, item: String, origin: Vector2) -> Dictionary:
	return {
		"id": id,
		"item": item,
		"pos": origin,
		"phase": float(id) * 0.7,
	}


static func rect(capsule: Dictionary, capsule_size: Vector2) -> Rect2:
	var pos: Vector2 = capsule["pos"]
	return Rect2(pos - capsule_size * 0.5, capsule_size)


## Faz as capsulas cairem um passo e resolve coleta e perda.
##
## Devolve { "capsules": Array, "caught": Array, "missed": Array }, onde caught e
## missed sao arrays de ids de item (String).
##
## A coleta e por CRUZAMENTO da linha da raquete, nao por sobreposicao de
## retangulos. Com dt grande a capsula anda mais que a propria altura num unico
## passo: em retrato, 0,1 s sao 32 px de queda contra uma raquete de 10 px, e um
## teste de intersecao simples deixaria a capsula atravessar sem ser vista.
static func step(capsules: Array, dt: float, play: Rect2, paddle: Rect2,
		fall_speed: float, capsule_size: Vector2) -> Dictionary:
	var remaining: Array = []
	var caught: Array = []
	var missed: Array = []
	var half := capsule_size * 0.5

	for capsule in capsules:
		var pos: Vector2 = capsule["pos"]
		var previous_bottom := pos.y + half.y
		pos.y += fall_speed * dt
		var bottom := pos.y + half.y

		var crossed := previous_bottom <= paddle.end.y and bottom >= paddle.position.y
		var overlaps_x := pos.x + half.x >= paddle.position.x and pos.x - half.x <= paddle.end.x

		if crossed and overlaps_x:
			caught.append(str(capsule["item"]))
			continue

		if pos.y - half.y > play.end.y:
			missed.append(str(capsule["item"]))
			continue

		capsule["pos"] = pos
		remaining.append(capsule)

	return {"capsules": remaining, "caught": caught, "missed": missed}


## Reposiciona as capsulas ao girar a tela, como a Arena ja faz com a bola.
static func remap(capsules: Array, old_play: Rect2, new_play: Rect2) -> Array:
	for capsule in capsules:
		var pos: Vector2 = capsule["pos"]
		capsule["pos"] = Vector2(
			ArenaLayout.remap_axis(pos.x, old_play.position.x, old_play.end.x, new_play.position.x, new_play.end.x),
			ArenaLayout.remap_axis(pos.y, old_play.position.y, old_play.end.y, new_play.position.y, new_play.end.y)
		)
	return capsules
