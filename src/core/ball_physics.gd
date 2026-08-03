## Fisica da bola: integracao com sub-passos e resolucao AABB deterministica.
##
## Escolha deliberada de NAO usar o motor de fisica: o Arkanoid depende de
## reflexao previsivel e de um angulo de saida da raquete controlado por design.
## Sendo codigo puro (sem nos, sem SceneTree), toda a logica e testavel headless.
##
## A bola e tratada como um quadrado de lado 2*radius para colisao com blocos e
## raquete - o comportamento classico do genero - e como circulo apenas
## visualmente.
class_name BallPhysics
extends RefCounted

const KIND_PADDLE := 1
const KIND_BRICK := 2

## Alvo solido que rebate a bola sem sofrer dano: a barreira movel.
##
## Emite evento "solid", e NAO "brick", e isso nao e preciosismo. Quem trata
## "brick" indexa a lista de blocos direto pelo id do evento, e int() sobre String
## extrai digitos de qualquer posicao - int("solid:1") vale 1, nao 0. Um id de
## texto num evento "brick" passaria por qualquer checagem de faixa e danificaria
## um bloco real e arbitrario da parede, dando pontos e abrindo buraco, em
## silencio.
const KIND_SOLID := 3

## Distancia maxima percorrida por sub-passo. Impede tunelamento: nenhum alvo do
## jogo tem lado menor que ~10 px, entao 3 px por passo mantem margem folgada.
const MAX_SUBSTEP_DISTANCE := 3.0
const MAX_SUBSTEPS := 64

## Angulo maximo de saida da raquete, medido a partir da vertical.
const MAX_BOUNCE_ANGLE := 1.0821  # deg_to_rad(62)

## Fracao minima da velocidade que deve ser vertical, para evitar que a bola
## entre em loop quase horizontal e o jogo travar.
const MIN_VERTICAL_RATIO := 0.30

## Angulo minimo de saida da raquete (~7 graus). Sem ele, uma rebatida no centro
## exato devolve a bola perfeitamente vertical; depois de abrir uma coluna na
## parede, ela sobe pelo canal vazio, bate no teto e volta ao mesmo ponto - um
## loop infinito que nunca mais atinge um bloco. O soak test em
## tests/run_tests.gd reproduz exatamente esse caso.
const MIN_PADDLE_ANGLE := 0.12

## Influencia da velocidade horizontal da raquete no angulo de saida ("efeito").
const PADDLE_SPIN := 0.0011


## Avanca a bola por "dt" segundos.
##
## targets: Array de Dictionary com as chaves
##   "rect": Rect2         - area do alvo
##   "id":   Variant       - identificador devolvido nos eventos
##   "kind": int           - KIND_PADDLE, KIND_BRICK ou KIND_SOLID
##   "vx":   float (opc.)  - velocidade horizontal, usada apenas pela raquete
##
## O "rect" e relido a cada chamada e nunca guardado em cache, entao um alvo que
## se move e so um alvo cujo retangulo mudou entre um quadro e outro - e por isso
## que a barreira movel nao custou uma linha de fisica nova.
##
## Retorna { pos, vel, events, lost }. Cada evento e
##   { "type": "wall"|"paddle"|"brick"|"solid", "id": Variant, "point": Vector2, "normal": Vector2 }
static func advance(pos: Vector2, vel: Vector2, radius: float, dt: float, bounds: Rect2, targets: Array) -> Dictionary:
	var events: Array = []
	var lost := false
	var speed := vel.length()

	if dt <= 0.0 or speed <= 0.0:
		return {"pos": pos, "vel": vel, "events": events, "lost": false}

	var substeps := clampi(int(ceil(speed * dt / MAX_SUBSTEP_DISTANCE)), 1, MAX_SUBSTEPS)
	var sub_dt := dt / float(substeps)

	# Um alvo so pode ser atingido uma vez por quadro: sem isso, um bloco de 2 hp
	# poderia levar dois danos em sub-passos consecutivos do mesmo frame.
	var consumed := {}

	for _i in substeps:
		pos += vel * sub_dt

		var wall := _resolve_bounds(pos, vel, radius, bounds)
		pos = wall["pos"]
		vel = wall["vel"]
		if wall["hit"]:
			events.append({"type": "wall", "id": null, "point": pos, "normal": wall["normal"]})

		if pos.y - radius > bounds.end.y:
			lost = true
			break

		var resolved := 0
		for target in targets:
			var id: Variant = target.get("id", null)
			if consumed.has(id):
				continue
			var res := _resolve_rect(pos, vel, radius, target["rect"])
			if not res["hit"]:
				continue

			pos = res["pos"]
			consumed[id] = true

			if int(target.get("kind", KIND_BRICK)) == KIND_PADDLE:
				# A raquete so rebate pelo TOPO.
				#
				# Uma bola encostada por BAIXO ja passou: devolve-la para cima
				# prendia o jogo num laco eterno. _resolve_rect via a penetracao
				# vertical como a menor, empurrava a bola para baixo da raquete e
				# invertia vel.y; paddle_bounce entao sobrescrevia a velocidade
				# para cima, incondicionalmente. No quadro seguinte tudo se
				# repetia, com a bola parada no mesmo pixel para sempre.
				# Encontrado pelo soak test em 30/07/2026, com 19934 rebatidas em
				# 400s de simulacao e a parede nunca terminando.
				if res["normal"] == Vector2.DOWN:
					vel = res["vel"]
				else:
					vel = paddle_bounce(pos, vel, target["rect"], float(target.get("vx", 0.0)))
					events.append({"type": "paddle", "id": id, "point": pos, "normal": Vector2.UP})
			else:
				vel = res["vel"]
				var kind := int(target.get("kind", KIND_BRICK))
				var kind_type := "solid" if kind == KIND_SOLID else "brick"
				events.append({"type": kind_type, "id": id, "point": pos, "normal": res["normal"]})

			resolved += 1
			# No maximo dois contatos por sub-passo (ex.: quina entre dois blocos).
			if resolved >= 2:
				break

		if resolved > 0:
			vel = enforce_min_vertical(vel)

	return {"pos": pos, "vel": vel, "events": events, "lost": lost}


## Reflete nas paredes esquerda, direita e superior. O fundo NAO reflete: sair
## por baixo e tratado como bola perdida por quem chama advance().
static func _resolve_bounds(pos: Vector2, vel: Vector2, radius: float, bounds: Rect2) -> Dictionary:
	var hit := false
	var normal := Vector2.ZERO

	if pos.x - radius < bounds.position.x:
		pos.x = bounds.position.x + radius
		vel.x = absf(vel.x)
		hit = true
		normal = Vector2.RIGHT
	elif pos.x + radius > bounds.end.x:
		pos.x = bounds.end.x - radius
		vel.x = -absf(vel.x)
		hit = true
		normal = Vector2.LEFT

	if pos.y - radius < bounds.position.y:
		pos.y = bounds.position.y + radius
		vel.y = absf(vel.y)
		hit = true
		normal = Vector2.DOWN

	return {"pos": pos, "vel": vel, "hit": hit, "normal": normal}


## Resolve a sobreposicao com um retangulo pelo eixo de menor penetracao.
static func _resolve_rect(pos: Vector2, vel: Vector2, radius: float, rect: Rect2) -> Dictionary:
	var ball := Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	if not rect.intersects(ball):
		return {"hit": false, "pos": pos, "vel": vel, "normal": Vector2.ZERO}

	var push_left := (pos.x + radius) - rect.position.x
	var push_right := rect.end.x - (pos.x - radius)
	var push_up := (pos.y + radius) - rect.position.y
	var push_down := rect.end.y - (pos.y - radius)

	var pen_x := minf(push_left, push_right)
	var pen_y := minf(push_up, push_down)
	var normal: Vector2

	if pen_x < pen_y:
		if push_left < push_right:
			pos.x = rect.position.x - radius
			vel.x = -absf(vel.x)
			normal = Vector2.LEFT
		else:
			pos.x = rect.end.x + radius
			vel.x = absf(vel.x)
			normal = Vector2.RIGHT
	else:
		if push_up < push_down:
			pos.y = rect.position.y - radius
			vel.y = -absf(vel.y)
			normal = Vector2.UP
		else:
			pos.y = rect.end.y + radius
			vel.y = absf(vel.y)
			normal = Vector2.DOWN

	return {"hit": true, "pos": pos, "vel": vel, "normal": normal}


## Angulo de saida da raquete determinado pelo ponto de impacto (estilo Arkanoid):
## centro devolve quase vertical, bordas devolvem ate MAX_BOUNCE_ANGLE. A
## velocidade da raquete adiciona um leve efeito, e MIN_PADDLE_ANGLE garante que
## a saida nunca seja exatamente vertical.
static func paddle_bounce(pos: Vector2, vel: Vector2, paddle: Rect2, paddle_vx: float = 0.0) -> Vector2:
	var speed := maxf(vel.length(), 1.0)
	var half := maxf(paddle.size.x * 0.5, 1.0)
	var offset := (pos.x - (paddle.position.x + half)) / half
	offset = clampf(offset + paddle_vx * PADDLE_SPIN, -1.0, 1.0)

	var angle := offset * MAX_BOUNCE_ANGLE
	if absf(angle) < MIN_PADDLE_ANGLE:
		angle = MIN_PADDLE_ANGLE * _drift_sign(angle, vel.x, paddle_vx)

	return Vector2(sin(angle), -cos(angle)) * speed


## Escolhe para que lado inclinar uma rebatida quase vertical. A ordem importa:
## manter o sentido horizontal que a bola ja tinha faz ela varrer o campo de
## forma continua, em vez de oscilar em torno do mesmo ponto.
static func _drift_sign(angle: float, vel_x: float, paddle_vx: float) -> float:
	for candidate in [angle, vel_x, paddle_vx]:
		if not is_zero_approx(candidate):
			return -1.0 if candidate < 0.0 else 1.0
	return 1.0


## Garante um componente vertical minimo preservando o modulo da velocidade.
static func enforce_min_vertical(vel: Vector2) -> Vector2:
	var speed := vel.length()
	if speed <= 0.0:
		return vel
	var min_y := speed * MIN_VERTICAL_RATIO
	if absf(vel.y) >= min_y:
		return vel

	var sign_y := -1.0 if vel.y <= 0.0 else 1.0
	var new_y := sign_y * min_y
	var new_x := sqrt(maxf(speed * speed - new_y * new_y, 0.0))
	if vel.x < 0.0:
		new_x = -new_x
	return Vector2(new_x, new_y)


## Angulo minimo de lancamento: a bola nunca sai perfeitamente vertical, o que
## deixaria a primeira jogada deterministica e sem graca.
const MIN_LAUNCH_ANGLE := 0.30

## Velocidade inicial ao lancar a bola: sempre para cima, com leve inclinacao.
static func launch_velocity(speed: float, bias: float = 0.0) -> Vector2:
	var angle := clampf(bias, -1.0, 1.0) * (MAX_BOUNCE_ANGLE * 0.45)
	if absf(angle) < MIN_LAUNCH_ANGLE:
		var dir := -1.0 if angle < 0.0 else 1.0
		angle = dir * MIN_LAUNCH_ANGLE
	return Vector2(sin(angle), -cos(angle)) * speed
