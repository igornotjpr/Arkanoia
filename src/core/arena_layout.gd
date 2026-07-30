## Matematica de layout adaptativo (16:9 <-> 9:16). Codigo puro, sem SceneTree.
##
## O projeto usa stretch "canvas_items" + aspect "expand" com base 640x360, o que
## garante que a viewport logica NUNCA fique menor que 640x360: em telas estreitas
## a largura permanece 640 e a altura cresce; em telas largas a altura permanece
## 360 e a largura cresce. Portanto a largura do campo de jogo pode ser fixa
## (588 px logicos) e centralizada, enquanto a altura se adapta.
##
## Para que o ritmo do jogo nao mude entre paisagem e retrato, "speed_scale"
## cresce junto com a altura do campo: o tempo que a bola leva para atravessar a
## tela fica aproximadamente constante.
class_name ArenaLayout
extends RefCounted

const DESIGN_WIDTH := 640.0
const DESIGN_HEIGHT := 360.0

const HUD_HEIGHT := 30.0
const BOTTOM_MARGIN := 10.0

const FRAME := 6.0            # espessura da moldura desenhada em volta do campo
const PLAY_WIDTH := 588.0     # largura interna do campo (fixa em todos os formatos)
const MIN_PLAY_HEIGHT := 280.0
const MAX_PLAY_HEIGHT := 1200.0

const COLS := 11
const ROWS := 8
const BRICK_GAP := 2.0
const BRICK_WIDTH := 50.0     # (588 - 2*9 - 10*2) / 11 == 50 exato
const GRID_SIDE_MARGIN := 9.0

## A largura do bloco e fixa, mas a ALTURA acompanha o campo: em retrato, um muro
## de 15 px de altura viraria uma faixa fina perdida no topo de uma tela de 1200
## px. Mantendo o muro numa fracao constante da altura, a fase tem a mesma
## proporcao visual em qualquer formato.
const WALL_HEIGHT_FRACTION := 0.28
const BRICK_MIN_HEIGHT := 15.0
const BRICK_MAX_HEIGHT := 34.0

const GRID_TOP_FRACTION := 0.06
const GRID_TOP_MIN := 20.0
const GRID_TOP_MAX := 60.0

const PADDLE_WIDTH := 74.0
const PADDLE_HEIGHT := 10.0
const PADDLE_BOTTOM_OFFSET := 24.0
const BALL_RADIUS := 4.0

## Escala de velocidade proporcional a altura do campo, para que o tempo de
## travessia da bola seja praticamente o mesmo em paisagem e em retrato. O teto
## cobre o campo mais alto possivel (MAX_PLAY_HEIGHT / DESIGN_HEIGHT ~= 3.33).
const MIN_SPEED_SCALE := 0.9
const MAX_SPEED_SCALE := 3.4

## Calcula todos os retangulos do jogo para uma viewport logica dada.
static func compute(viewport: Vector2) -> Dictionary:
	var vw := maxf(viewport.x, DESIGN_WIDTH)
	var vh := maxf(viewport.y, DESIGN_HEIGHT)

	var available := vh - HUD_HEIGHT - BOTTOM_MARGIN
	var play_h := floorf(clampf(available, MIN_PLAY_HEIGHT, MAX_PLAY_HEIGHT))
	var play_x := floorf((vw - PLAY_WIDTH) * 0.5)
	var play_y := floorf(HUD_HEIGHT + maxf(available - play_h, 0.0) * 0.5)

	var play := Rect2(play_x, play_y, PLAY_WIDTH, play_h)

	# Altura do bloco derivada da altura do campo, arredondada para baixo para a
	# grade fechar em pixels inteiros.
	var wall_budget := play_h * WALL_HEIGHT_FRACTION - BRICK_GAP * (ROWS - 1)
	var brick_h := floorf(clampf(wall_budget / float(ROWS), BRICK_MIN_HEIGHT, BRICK_MAX_HEIGHT))

	var grid_top := floorf(clampf(play_h * GRID_TOP_FRACTION, GRID_TOP_MIN, GRID_TOP_MAX))
	var grid_w := PLAY_WIDTH - GRID_SIDE_MARGIN * 2.0
	var grid_h := ROWS * brick_h + (ROWS - 1) * BRICK_GAP

	return {
		"viewport": Vector2(vw, vh),
		"hud": Rect2(0.0, 0.0, vw, HUD_HEIGHT),
		"play": play,
		"frame": Rect2(play.position - Vector2(FRAME, FRAME), play.size + Vector2(FRAME, FRAME) * 2.0),
		"grid": Rect2(play.position.x + GRID_SIDE_MARGIN, play.position.y + grid_top, grid_w, grid_h),
		"brick_size": Vector2(BRICK_WIDTH, brick_h),
		"paddle_size": Vector2(PADDLE_WIDTH, PADDLE_HEIGHT),
		"paddle_y": play.end.y - PADDLE_BOTTOM_OFFSET,
		"ball_radius": BALL_RADIUS,
		"speed_scale": clampf(play_h / DESIGN_HEIGHT, MIN_SPEED_SCALE, MAX_SPEED_SCALE),
	}

## Retangulo de um bloco na grade, em coordenadas da viewport.
static func brick_rect(layout: Dictionary, col: int, row: int) -> Rect2:
	var grid: Rect2 = layout["grid"]
	var size: Vector2 = layout["brick_size"]
	return Rect2(
		grid.position.x + col * (size.x + BRICK_GAP),
		grid.position.y + row * (size.y + BRICK_GAP),
		size.x,
		size.y
	)

## Retangulo da raquete dado o centro horizontal desejado (ja limitado ao campo).
static func paddle_rect(layout: Dictionary, center_x: float) -> Rect2:
	var play: Rect2 = layout["play"]
	var size: Vector2 = layout["paddle_size"]
	var half := size.x * 0.5
	var cx := clampf(center_x, play.position.x + half, play.end.x - half)
	return Rect2(cx - half, float(layout["paddle_y"]), size.x, size.y)

## Posicao de repouso da bola quando ela esta "encaixada" na raquete.
static func docked_ball_position(layout: Dictionary, paddle_center_x: float) -> Vector2:
	var rect := paddle_rect(layout, paddle_center_x)
	return Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y - float(layout["ball_radius"]) - 1.0)
