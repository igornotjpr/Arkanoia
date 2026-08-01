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

## Dimensoes da parede classica, usadas como padrao por quem nao declara as suas.
const DEFAULT_COLS := 11
const DEFAULT_ROWS := 8

## Faixa que uma fase pode declarar. MAX_ROWS e limite de DESIGN, nao estrutural:
## acima de 10 fileiras a parede em paisagem come a faixa livre abaixo do muro e
## sufoca o surgimento de blocos especiais. Quem prova isso e o teste, que calcula
## o teto em vez de confiar neste numero - ver _test_special_bricks.
const MIN_COLS := 5
const MAX_COLS := 16
const MIN_ROWS := 4
const MAX_ROWS := 10

## Limites ESTRUTURAIS, so para compute() nunca dividir por zero nem produzir bloco
## de largura negativa se receber lixo. A validacao de verdade e do LevelBuilder.
const SAFE_MAX_COLS := 24
const SAFE_MAX_ROWS := 24

const BRICK_GAP := 2.0

## Margem lateral MINIMA entre a grade e a borda do campo. A largura do bloco e
## derivada dela; a sobra da divisao volta como margem extra, centrada.
const MIN_SIDE_MARGIN := 9.0

## A ALTURA do bloco acompanha o campo: em retrato, um muro de 15 px de altura
## viraria uma faixa fina perdida no topo de uma tela de 1200 px. Mantendo o muro
## numa fracao constante da altura, a fase tem a mesma proporcao visual em
## qualquer formato.
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

## Limites da largura da raquete sob efeito de power-up.
##
## O piso de 0.40 deixa a raquete com ~30 px, quase quatro vezes o diametro da
## bola: continua sendo mira, nao sorteio. Acima de 1.70 ela cobriria um terco do
## campo e a fase deixaria de exigir pontaria.
const PADDLE_MIN_WIDTH_SCALE := 0.40
const PADDLE_MAX_WIDTH_SCALE := 1.70

## Escala de velocidade proporcional a altura do campo, para que o tempo de
## travessia da bola seja praticamente o mesmo em paisagem e em retrato. O teto
## cobre o campo mais alto possivel (MAX_PLAY_HEIGHT / DESIGN_HEIGHT ~= 3.33).
const MIN_SPEED_SCALE := 0.9
const MAX_SPEED_SCALE := 3.4

## Largura do bloco para um dado numero de colunas, em pixels inteiros.
##
## E DERIVADA, e nao uma constante, porque a fase declara as proprias colunas. O
## piso garante que a grade feche em pixel: a sobra da divisao vira margem lateral
## extra em compute(), em vez de virar fresta entre blocos.
##
## Em 11 colunas isto devolve exatamente 50 - a largura fixa que o jogo usou ate a
## v2.2.0 -, o que mantem a fase 1 identica ao que ja estava no ar.
static func brick_width(cols: int) -> float:
	var n := maxi(cols, 1)
	var usable := PLAY_WIDTH - MIN_SIDE_MARGIN * 2.0
	return maxf(floorf((usable - BRICK_GAP * float(n - 1)) / float(n)), 1.0)


## Calcula todos os retangulos do jogo para uma viewport logica e uma dimensao de
## fase. Sem argumentos de grade, devolve a parede classica de 11x8.
static func compute(viewport: Vector2, cols: int = DEFAULT_COLS, rows: int = DEFAULT_ROWS) -> Dictionary:
	var n_cols := clampi(cols, 1, SAFE_MAX_COLS)
	var n_rows := clampi(rows, 1, SAFE_MAX_ROWS)

	var vw := maxf(viewport.x, DESIGN_WIDTH)
	var vh := maxf(viewport.y, DESIGN_HEIGHT)

	var available := vh - HUD_HEIGHT - BOTTOM_MARGIN
	var play_h := floorf(clampf(available, MIN_PLAY_HEIGHT, MAX_PLAY_HEIGHT))
	var play_x := floorf((vw - PLAY_WIDTH) * 0.5)
	var play_y := floorf(HUD_HEIGHT + maxf(available - play_h, 0.0) * 0.5)

	var play := Rect2(play_x, play_y, PLAY_WIDTH, play_h)

	# Altura do bloco derivada da altura do campo, arredondada para baixo para a
	# grade fechar em pixels inteiros.
	var wall_budget := play_h * WALL_HEIGHT_FRACTION - BRICK_GAP * float(n_rows - 1)
	var brick_h := floorf(clampf(wall_budget / float(n_rows), BRICK_MIN_HEIGHT, BRICK_MAX_HEIGHT))
	var brick_w := brick_width(n_cols)

	var grid_top := floorf(clampf(play_h * GRID_TOP_FRACTION, GRID_TOP_MIN, GRID_TOP_MAX))
	var grid_w := float(n_cols) * brick_w + float(n_cols - 1) * BRICK_GAP
	var grid_h := float(n_rows) * brick_h + float(n_rows - 1) * BRICK_GAP

	# A grade e centralizada no campo: com 11 colunas a sobra e zero e a margem da
	# exatamente MIN_SIDE_MARGIN, mas numa fase de 7 ou 15 colunas o resto da
	# divisao precisa ir para as duas laterais, senao a parede sai torta.
	var grid_x := play.position.x + floorf((PLAY_WIDTH - grid_w) * 0.5)

	return {
		"viewport": Vector2(vw, vh),
		"hud": Rect2(0.0, 0.0, vw, HUD_HEIGHT),
		"play": play,
		"frame": Rect2(play.position - Vector2(FRAME, FRAME), play.size + Vector2(FRAME, FRAME) * 2.0),
		"grid": Rect2(grid_x, play.position.y + grid_top, grid_w, grid_h),
		"brick_size": Vector2(brick_w, brick_h),
		"cols": n_cols,
		"rows": n_rows,
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
##
## width_scale existe para os power-ups de raquete larga e curta. Ele multiplica a
## largura ANTES do clamp, entao uma raquete larga encostada na parede continua
## inteira dentro do campo. Passar a escala em vez de mexer em layout["paddle_size"]
## e deliberado: o layout e recalculado do zero a cada mudanca de viewport, e
## qualquer mutacao ali seria silenciosamente perdida ao girar a tela.
static func paddle_rect(layout: Dictionary, center_x: float, width_scale: float = 1.0) -> Rect2:
	var play: Rect2 = layout["play"]
	var size: Vector2 = layout["paddle_size"]
	var width := size.x * clampf(width_scale, PADDLE_MIN_WIDTH_SCALE, PADDLE_MAX_WIDTH_SCALE)
	var half := width * 0.5
	var cx := clampf(center_x, play.position.x + half, play.end.x - half)
	return Rect2(cx - half, float(layout["paddle_y"]), width, size.y)

## Posicao de repouso da bola quando ela esta "encaixada" na raquete.
static func docked_ball_position(layout: Dictionary, paddle_center_x: float, width_scale: float = 1.0) -> Vector2:
	var rect := paddle_rect(layout, paddle_center_x, width_scale)
	return Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y - float(layout["ball_radius"]) - 1.0)

## Reposiciona um valor proporcionalmente ao mudar o campo de lugar ou de tamanho.
##
## Mora aqui, e nao na Arena, porque o soak test precisa remapear capsulas sem
## instanciar um no. Devolve o valor intacto quando o intervalo de origem e
## degenerado, para nunca produzir NAN ao girar a tela num quadro estranho.
static func remap_axis(value: float, from_min: float, from_max: float, to_min: float, to_max: float) -> float:
	var span := from_max - from_min
	if absf(span) < 0.0001:
		return to_min
	var t := (value - from_min) / span
	return to_min + t * (to_max - to_min)
