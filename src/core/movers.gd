## Barreiras moveis: alvos solidos que patrulham um trecho da fase e rebatem a
## bola sem sofrer dano. Codigo puro, sem nos, sem SceneTree.
##
## A barreira nao custou uma linha de fisica nova. BallPhysics.advance rele
## target["rect"] a cada chamada e nunca guarda cache, entao um alvo movel e so um
## alvo cujo retangulo mudou - exatamente o que a Arena ja fazia com a raquete.
##
## O ESTADO CANONICO E "t", NAO O RETANGULO
## ----------------------------------------
## Cada barreira guarda a posicao como uma fracao de 0 a 1 do trecho que percorre,
## e o retangulo e DERIVADO dela a cada quadro. E o mesmo desenho dos blocos, que
## guardam col/row e derivam o rect: ao girar a tela, a barreira reaparece na
## mesma fracao do percurso, sem teleporte e sem uma linha de remapeamento.
class_name Movers
extends RefCounted

## TETO DE VELOCIDADE, DERIVADO DA FISICA E NAO ESCOLHIDO A GOSTO.
##
## BallPhysics resolve colisao por sobreposicao discreta de menor penetracao, e
## nao por varredura. Um alvo que anda mais que o sub-passo da bola
## (MAX_SUBSTEP_DISTANCE = 3 px) pode surgir ja dentro dela e eleta-la pelo eixo
## errado - a bola atravessaria a barreira ou sairia de lado sem motivo visivel.
##
## A 60 quadros por segundo, 3 px por quadro sao 180 px/s. Ficamos na metade, o que
## deixa folga de 2x para um quadro longo (30 fps ainda fica dentro do limite).
const REFERENCE_FPS := 60.0
const SAFETY_FACTOR := 0.5
const MAX_SPEED := BallPhysics.MAX_SUBSTEP_DISTANCE * REFERENCE_FPS * SAFETY_FACTOR

## Altura da barra, como fracao da altura do bloco. Mais fina que um bloco de
## proposito: ela tem que ser lida como obstaculo, nao como parede que sobrou.
const HEIGHT_FRACTION := 0.55

## Largura da barra, em celulas da grade.
const WIDTH_CELLS := 1


## Teto de velocidade para o campo dado.
##
## Escala junto com o campo pelo mesmo motivo que a bola e as capsulas: em retrato
## o campo e ate 3,4x mais alto, e uma barreira em px/s fixo pareceria parada.
static func speed_cap(layout: Dictionary) -> float:
	return MAX_SPEED * float(layout["speed_scale"])


## Constroi as barreiras de uma fase a partir das especificacoes do mapa.
##
## spec: { "row": int, "col_min": int, "col_max": int, "speed": float, "t": float }
static func build(specs: Array, layout: Dictionary) -> Array:
	var movers: Array = []
	for index in specs.size():
		movers.append(make(specs[index], layout, index))
	return movers


static func make(spec: Dictionary, layout: Dictionary, index: int) -> Dictionary:
	var mover := {
		# ID DE TEXTO, NUNCA int: e o que torna estruturalmente impossivel um
		# evento de barreira ser confundido com um bloco. Ver KIND_SOLID.
		"id": "solid:%d" % index,
		"kind": BallPhysics.KIND_SOLID,
		"row": int(spec.get("row", 0)),
		"col_min": int(spec.get("col_min", 0)),
		"col_max": int(spec.get("col_max", 0)),
		"speed": float(spec.get("speed", MAX_SPEED)),
		"t": clampf(float(spec.get("t", 0.0)), 0.0, 1.0),
		"dir": 1.0,
		"rect": Rect2(),
	}
	mover["rect"] = rect_for(mover, layout)
	return mover


## Retangulo da barreira para a fracao de percurso atual.
static func rect_for(mover: Dictionary, layout: Dictionary) -> Rect2:
	var brick_size: Vector2 = layout["brick_size"]
	var first := ArenaLayout.brick_rect(layout, int(mover["col_min"]), int(mover["row"]))
	var last := ArenaLayout.brick_rect(layout, int(mover["col_max"]), int(mover["row"]))

	var width := brick_size.x * float(WIDTH_CELLS)
	var height := floorf(brick_size.y * HEIGHT_FRACTION)
	var travel := maxf(last.end.x - first.position.x - width, 0.0)

	var x := first.position.x + travel * float(mover["t"])
	var y := first.position.y + floorf((brick_size.y - height) * 0.5)
	return Rect2(floorf(x), y, width, height)


## Avanca as barreiras e devolve a lista com os retangulos ja atualizados.
##
## A fracao "t" ricocheteia em 0 e 1 em vez de dar a volta: a barreira patrulha o
## trecho, e nao reaparece do outro lado - o que seria um teleporte na cara do
## jogador e poderia materializar a barra em cima da bola.
static func step(movers: Array, dt: float, layout: Dictionary) -> Array:
	var cap := speed_cap(layout)
	for mover in movers:
		var travel := travel_length(mover, layout)
		if travel <= 0.0:
			mover["rect"] = rect_for(mover, layout)
			continue

		var speed := minf(float(mover["speed"]) * float(layout["speed_scale"]), cap)
		var t := float(mover["t"]) + float(mover["dir"]) * speed * dt / travel

		if t <= 0.0:
			t = 0.0
			mover["dir"] = 1.0
		elif t >= 1.0:
			t = 1.0
			mover["dir"] = -1.0

		mover["t"] = t
		mover["rect"] = rect_for(mover, layout)
	return movers


## Comprimento em px do trecho percorrido pela barreira.
static func travel_length(mover: Dictionary, layout: Dictionary) -> float:
	var brick_size: Vector2 = layout["brick_size"]
	var first := ArenaLayout.brick_rect(layout, int(mover["col_min"]), int(mover["row"]))
	var last := ArenaLayout.brick_rect(layout, int(mover["col_max"]), int(mover["row"]))
	return maxf(last.end.x - first.position.x - brick_size.x * float(WIDTH_CELLS), 0.0)


## Recalcula os retangulos apos o campo mudar de tamanho, preservando o percurso.
static func remap(movers: Array, layout: Dictionary) -> Array:
	for mover in movers:
		mover["rect"] = rect_for(mover, layout)
	return movers
