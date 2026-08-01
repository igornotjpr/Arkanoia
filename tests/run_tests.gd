## Suite de testes headless da camada pura do Arkanoia.
##
## Execucao:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script res://tests/run_tests.gd
##
## Sai com codigo 0 se tudo passar, 1 caso contrario - pronto para CI.
##
## Cobre ArenaLayout, BallPhysics, LevelBuilder, ScoreRules, NickUtil, PixelFont e
## SupabaseConfig, e termina com um soak test que simula partidas completas em
## paisagem e retrato usando exatamente a mesma matematica do jogo.
extends SceneTree

const EPS := 0.001

var _passed := 0
var _failed := 0
var _suite := ""
var _failures: Array[String] = []


func _initialize() -> void:
	print("")
	print("=== ARKANOIA :: TESTES ===")

	_test_arena_layout()
	_test_level_builder()
	_test_ball_physics()
	_test_score_rules()
	_test_nick_util()
	_test_pixel_font()
	_test_supabase_config()
	_test_leaderboard_helpers()
	_test_power_ups()
	_test_capsules()
	_test_special_bricks()
	_test_schema_mirror()
	_test_gameplay_soak()

	print("")
	print("--------------------------------------------")
	print("passou: %d    falhou: %d" % [_passed, _failed])
	if _failed > 0:
		print("")
		for failure in _failures:
			print("  FALHA  " + failure)
	print("--------------------------------------------")
	print("")

	quit(1 if _failed > 0 else 0)


# ============================================================================
#  ArenaLayout
# ============================================================================

func _test_arena_layout() -> void:
	_begin("ArenaLayout")

	# As tres formas que a viewport logica pode assumir com base 640x360 e
	# aspect "expand": paisagem, retrato (altura cresce) e ultrawide (largura cresce).
	var cases := {
		"paisagem 640x360": Vector2(640, 360),
		"retrato 640x1385": Vector2(640, 1385),
		"ultrawide 853x360": Vector2(853, 360),
		"quadrado 700x700": Vector2(700, 700),
	}

	for label in cases:
		var viewport: Vector2 = cases[label]
		var layout := ArenaLayout.compute(viewport)
		var play: Rect2 = layout["play"]
		var frame: Rect2 = layout["frame"]
		var grid: Rect2 = layout["grid"]

		_check(play.size.x == ArenaLayout.PLAY_WIDTH,
			"%s: largura do campo e fixa (%s)" % [label, play.size.x])
		_check(play.position.y >= ArenaLayout.HUD_HEIGHT,
			"%s: campo comeca abaixo do HUD" % label)
		_check(frame.position.x >= 0.0 and frame.end.x <= viewport.x + EPS,
			"%s: moldura cabe na largura" % label)
		_check(play.end.y <= viewport.y + EPS,
			"%s: campo cabe na altura" % label)
		_check(play.size.y >= ArenaLayout.MIN_PLAY_HEIGHT - EPS,
			"%s: altura minima respeitada" % label)

		# A grade de blocos precisa caber com folga dentro do campo.
		_check(grid.position.x >= play.position.x and grid.end.x <= play.end.x + EPS,
			"%s: grade cabe na largura do campo" % label)
		var last_brick := ArenaLayout.brick_rect(layout, int(layout["cols"]) - 1, int(layout["rows"]) - 1)
		_check(last_brick.end.x <= grid.end.x + EPS,
			"%s: ultimo bloco termina dentro da grade (%s vs %s)" % [label, last_brick.end.x, grid.end.x])
		_check(last_brick.end.y < float(layout["paddle_y"]),
			"%s: blocos ficam acima da raquete" % label)

		# Raquete e bola encaixada.
		var paddle := ArenaLayout.paddle_rect(layout, -9999.0)
		_check(is_equal_approx(paddle.position.x, play.position.x),
			"%s: raquete limitada a esquerda" % label)
		paddle = ArenaLayout.paddle_rect(layout, 99999.0)
		_check(is_equal_approx(paddle.end.x, play.end.x),
			"%s: raquete limitada a direita" % label)

		var ball := ArenaLayout.docked_ball_position(layout, play.get_center().x)
		_check(ball.y < float(layout["paddle_y"]),
			"%s: bola encaixada fica acima da raquete" % label)
		_check(play.has_point(ball),
			"%s: bola encaixada esta dentro do campo" % label)

		var scale := float(layout["speed_scale"])
		_check(scale >= ArenaLayout.MIN_SPEED_SCALE - EPS and scale <= ArenaLayout.MAX_SPEED_SCALE + EPS,
			"%s: speed_scale dentro da faixa (%s)" % [label, scale])

		# A altura do bloco acompanha o campo, mas dentro de limites e sempre em
		# pixels inteiros (senao a grade nao fecha e aparecem frestas).
		var brick_size: Vector2 = layout["brick_size"]
		var n_rows := int(layout["rows"])
		_eq(brick_size.x, ArenaLayout.brick_width(ArenaLayout.DEFAULT_COLS),
			"%s: largura do bloco vem de brick_width" % label)
		_check(brick_size.y >= ArenaLayout.BRICK_MIN_HEIGHT and brick_size.y <= ArenaLayout.BRICK_MAX_HEIGHT,
			"%s: altura do bloco dentro dos limites (%s)" % [label, brick_size.y])
		_eq(brick_size.y, floorf(brick_size.y), "%s: altura do bloco e inteira" % label)
		_approx(grid.size.y, n_rows * brick_size.y + (n_rows - 1) * ArenaLayout.BRICK_GAP,
			EPS, "%s: altura da grade bate com as linhas" % label)

		# O muro nunca deve dominar o campo nem sumir dentro dele.
		var wall_share := grid.size.y / play.size.y
		_check(wall_share > 0.15 and wall_share < 0.55,
			"%s: muro ocupa fracao razoavel do campo (%.2f)" % [label, wall_share])

		# Espaco de reacao entre o muro e a raquete.
		_check(float(layout["paddle_y"]) - grid.end.y > 80.0,
			"%s: sobra espaco de reacao abaixo do muro" % label)

	# A PROVA DE QUE LIBERAR A GEOMETRIA NAO MEXEU NO QUE JA EXISTIA.
	# Ate a v2.2.0 a largura do bloco era a constante 50, valida so para 11 colunas.
	# Agora ela e derivada - e em 11 colunas tem que dar exatamente 50, com a grade
	# comecando a MIN_SIDE_MARGIN da borda, como a fase 1 sempre esteve no ar.
	var layout_base := ArenaLayout.compute(Vector2(640, 360))
	var brick_size: Vector2 = layout_base["brick_size"]
	_eq(brick_size.x, 50.0, "11 colunas continuam dando bloco de 50 px")
	var grid_base: Rect2 = layout_base["grid"]
	var play_base: Rect2 = layout_base["play"]
	_approx(grid_base.position.x - play_base.position.x, ArenaLayout.MIN_SIDE_MARGIN, EPS,
		"11 colunas continuam com a margem lateral historica")

	# Grade variavel: para toda combinacao permitida, a grade tem que fechar em
	# pixels inteiros, caber no campo e ficar centralizada. Sem isto, uma fase de
	# 13 colunas sairia torta ou com fresta entre blocos.
	for cols in range(ArenaLayout.MIN_COLS, ArenaLayout.MAX_COLS + 1):
		for rows in range(ArenaLayout.MIN_ROWS, ArenaLayout.MAX_ROWS + 1):
			for viewport in [Vector2(640, 360), Vector2(640, 1385), Vector2(853, 360), Vector2(700, 700)]:
				var tag := "%dx%d @ %s" % [cols, rows, viewport]
				var l := ArenaLayout.compute(viewport, cols, rows)
				var g: Rect2 = l["grid"]
				var p: Rect2 = l["play"]
				var bs: Vector2 = l["brick_size"]

				_eq(int(l["cols"]), cols, "%s: layout devolve as colunas pedidas" % tag)
				_eq(int(l["rows"]), rows, "%s: layout devolve as linhas pedidas" % tag)
				_eq(bs.x, floorf(bs.x), "%s: largura do bloco e inteira" % tag)
				_check(bs.x >= 1.0, "%s: largura do bloco e positiva" % tag)
				_approx(g.size.x, cols * bs.x + (cols - 1) * ArenaLayout.BRICK_GAP, EPS,
					"%s: largura da grade fecha com as colunas" % tag)
				_check(g.position.x >= p.position.x and g.end.x <= p.end.x + EPS,
					"%s: grade cabe no campo" % tag)
				_approx(g.position.x - p.position.x, p.end.x - g.end.x, 1.0,
					"%s: grade fica centralizada no campo" % tag)

				# O ultimo bloco da grade tem que terminar dentro dela, e a parede
				# inteira tem que ficar acima da raquete.
				var last := ArenaLayout.brick_rect(l, cols - 1, rows - 1)
				_approx(last.end.x, g.end.x, EPS, "%s: ultimo bloco fecha na borda da grade" % tag)
				_check(last.end.y < float(l["paddle_y"]), "%s: parede fica acima da raquete" % tag)

	# Viewport menor que a base e elevada a base, nunca deixa layout invalido.
	var tiny := ArenaLayout.compute(Vector2(120, 90))
	_check(Rect2(Vector2.ZERO, Vector2(tiny["viewport"])).encloses(Rect2(tiny["play"])),
		"viewport degenerada e corrigida para a base")


# ============================================================================
#  LevelBuilder
# ============================================================================

func _test_level_builder() -> void:
	_begin("LevelBuilder")

	var bricks := LevelBuilder.build(1)
	_eq(bricks.size(), 88, "fase 1 tem 88 blocos (11x8 cheios)")

	var seen_cells := {}
	var hard_blue := 0
	var hard_gold := 0
	var special := 0
	for index in bricks.size():
		var brick: Dictionary = bricks[index]
		_eq(int(brick["id"]), index, "id do bloco %d bate com o indice (lookup direto na Arena)" % index)

		var cell := Vector2i(int(brick["col"]), int(brick["row"]))
		_check(not seen_cells.has(cell), "celula %s aparece uma unica vez" % cell)
		seen_cells[cell] = true

		_check(int(brick["col"]) >= 0 and int(brick["col"]) < LevelBuilder.cols(1), "coluna valida")
		_check(int(brick["row"]) >= 0 and int(brick["row"]) < LevelBuilder.rows(1), "linha valida")
		_check(int(brick["hp"]) >= 1 and int(brick["hp"]) == int(brick["max_hp"]), "hp inicial == max_hp")
		_check(int(brick["points"]) > 0, "bloco vale pontos")

		match int(brick["type"]):
			LevelBuilder.TYPE_TJ_BLUE:
				hard_blue += 1
				_eq(int(brick["hp"]), 2, "bloco azul TJ tem 2 hp")
			LevelBuilder.TYPE_TJ_GOLD:
				hard_gold += 1
				_eq(int(brick["hp"]), 2, "bloco dourado TJ tem 2 hp")
			LevelBuilder.TYPE_SPECIAL:
				special += 1
				_eq(int(brick["hp"]), LevelBuilder.SPECIAL_HP, "bloco especial tem %d hp" % LevelBuilder.SPECIAL_HP)

	_eq(hard_blue, 10, "easter egg: 10 blocos azuis desenham T e J")
	_eq(hard_gold, 2, "easter egg: 2 blocos dourados")
	_eq(special, 2, "fase 1 tem 2 blocos especiais fixos")

	# O mapa nunca declara o bloco que surge em jogo: quem o cria e SpecialBricks.
	for brick in bricks:
		_check(int(brick["type"]) != LevelBuilder.TYPE_SPECIAL_SPAWNED,
			"bloco de surgimento nao aparece em mapa")

	# As letras precisam estar onde o mapa promete (linha 2, colunas 2-4 = topo do T).
	for col in [2, 3, 4]:
		_check(_brick_type_at(bricks, col, 2) == LevelBuilder.TYPE_TJ_BLUE,
			"barra do T em (%d,2)" % col)
	_check(_brick_type_at(bricks, 3, 4) == LevelBuilder.TYPE_TJ_BLUE, "haste do T em (3,4)")
	_check(_brick_type_at(bricks, 8, 3) == LevelBuilder.TYPE_TJ_BLUE, "haste do J em (8,3)")
	_check(_brick_type_at(bricks, 6, 4) == LevelBuilder.TYPE_TJ_BLUE, "base do J em (6,4)")

	# Fileiras de cima valem mais que as de baixo.
	for row in range(LevelBuilder.ROW_POINTS.size() - 1):
		_check(LevelBuilder.ROW_POINTS[row] > LevelBuilder.ROW_POINTS[row + 1],
			"fileira %d vale mais que a %d" % [row, row + 1])

	# 5000 na v1.1.0; os dois 'S' trocaram um bloco de 50 e um de 30 por 150 cada.
	_eq(LevelBuilder.max_base_score(1), 5220, "teto base da fase 1 == 5220 pontos")
	_eq(LevelBuilder.dimensions(1), Vector2i(11, 8), "a fase 1 continua 11x8")

	# --- Todo mapa da rotacao ---
	#
	# map_is_valid nao e chamada pelo jogo: e AQUI que ela vale. Um mapa torto e
	# erro de quem escreveu a fase, e tem que quebrar a suite em vez de degradar
	# em silencio na tela de alguem.
	_check(LevelBuilder.level_count() >= 2, "existe mais de uma fase (a rotacao tem o que rodar)")
	for index in LevelBuilder.LEVELS.size():
		var map: Array = LevelBuilder.LEVELS[index]
		var dims := LevelBuilder.map_dimensions(map)
		var tag := "mapa %d (%dx%d)" % [index + 1, dims.x, dims.y]

		_check(LevelBuilder.map_is_valid(map), "%s: retangular, dentro dos limites e so com simbolos conhecidos" % tag)

		var built := LevelBuilder.build(index + 1)
		_check(built.size() > 0, "%s: produz blocos" % tag)
		_check(LevelBuilder.max_base_score(index + 1) > 0, "%s: vale pontos" % tag)

		var specials := 0
		for brick in built:
			_check(int(brick["col"]) < dims.x, "%s: coluna dentro do mapa" % tag)
			_check(int(brick["row"]) < dims.y, "%s: linha dentro do mapa" % tag)
			if int(brick["type"]) == LevelBuilder.TYPE_SPECIAL:
				specials += 1
		# Sem 'S' a fase nao solta uma capsula sequer - e o power-up e metade do jogo.
		_check(specials >= 1, "%s: tem pelo menos um bloco especial fixo" % tag)

	# A rotacao nao trava: a fase N e a fase N + level_count() usam o mesmo mapa,
	# e fases consecutivas dentro de um ciclo usam mapas diferentes.
	var count := LevelBuilder.level_count()
	for level in range(1, 41):
		_eq(LevelBuilder.build(level).size(), LevelBuilder.build(level + count).size(),
			"fase %d e fase %d compartilham o mapa" % [level, level + count])
	for level in range(1, count):
		_check(LevelBuilder.map_for_level(level) != LevelBuilder.map_for_level(level + 1),
			"fase %d e fase %d sao mapas diferentes" % [level, level + 1])


func _brick_type_at(bricks: Array, col: int, row: int) -> int:
	for brick in bricks:
		if int(brick["col"]) == col and int(brick["row"]) == row:
			return int(brick["type"])
	return -1


# ============================================================================
#  BallPhysics
# ============================================================================

func _test_ball_physics() -> void:
	_begin("BallPhysics")

	var bounds := Rect2(0.0, 0.0, 200.0, 200.0)
	var radius := 4.0

	# Parede esquerda: inverte X, mantem Y, e a bola volta para dentro.
	var res := BallPhysics.advance(Vector2(6.0, 100.0), Vector2(-120.0, -60.0), radius, 0.1, bounds, [])
	_check(Vector2(res["vel"]).x > 0.0, "parede esquerda inverte X")
	_check(Vector2(res["vel"]).y < 0.0, "parede esquerda preserva Y")
	_check(Vector2(res["pos"]).x >= bounds.position.x + radius - EPS, "bola nao fica presa na parede")
	_check(_has_event(res, "wall"), "colisao com parede gera evento")

	# Parede direita.
	res = BallPhysics.advance(Vector2(194.0, 100.0), Vector2(120.0, 60.0), radius, 0.1, bounds, [])
	_check(Vector2(res["vel"]).x < 0.0, "parede direita inverte X")

	# Teto.
	res = BallPhysics.advance(Vector2(100.0, 6.0), Vector2(0.0, -120.0), radius, 0.1, bounds, [])
	_check(Vector2(res["vel"]).y > 0.0, "teto inverte Y")

	# Fundo nao reflete: e perda de bola.
	res = BallPhysics.advance(Vector2(100.0, 195.0), Vector2(0.0, 300.0), radius, 0.1, bounds, [])
	_check(bool(res["lost"]), "sair pelo fundo marca a bola como perdida")

	# Bloco atingido por baixo: inverte Y para cima.
	var brick := {"rect": Rect2(80.0, 40.0, 50.0, 15.0), "id": 7, "kind": BallPhysics.KIND_BRICK}
	res = BallPhysics.advance(Vector2(105.0, 62.0), Vector2(0.0, -200.0), radius, 0.05, bounds, [brick])
	_check(Vector2(res["vel"]).y > 0.0, "bloco atingido por baixo empurra a bola para baixo")
	_check(_has_event(res, "brick"), "colisao com bloco gera evento")
	_eq(int(_first_event(res, "brick")["id"]), 7, "evento carrega o id do bloco")

	# Bloco atingido pela lateral: inverte X, preserva Y.
	res = BallPhysics.advance(Vector2(74.0, 47.0), Vector2(200.0, 30.0), radius, 0.03, bounds, [brick])
	_check(Vector2(res["vel"]).x < 0.0, "bloco atingido pela lateral inverte X")
	_check(Vector2(res["vel"]).y > 0.0, "bloco atingido pela lateral preserva Y")

	# Antitunelamento: velocidade absurda precisa registrar o impacto.
	res = BallPhysics.advance(Vector2(105.0, 120.0), Vector2(0.0, -6000.0), radius, 1.0 / 60.0, bounds, [brick])
	_check(_has_event(res, "brick"), "bola a 6000 px/s nao atravessa o bloco")

	# Um alvo nao pode ser atingido duas vezes no mesmo quadro.
	res = BallPhysics.advance(Vector2(105.0, 58.0), Vector2(0.0, -400.0), radius, 0.5, bounds, [brick])
	var brick_events := 0
	for event in res["events"]:
		if str(event["type"]) == "brick":
			brick_events += 1
	_eq(brick_events, 1, "bloco leva no maximo um dano por quadro")

	# Raquete: angulo de saida controlado pelo ponto de impacto.
	var paddle := Rect2(100.0, 180.0, 74.0, 10.0)
	var incoming := Vector2(0.0, 250.0)
	var center_out := BallPhysics.paddle_bounce(paddle.get_center(), incoming, paddle)
	_check(center_out.y < 0.0, "raquete devolve a bola para cima")
	_approx(center_out.length(), incoming.length(), 0.01, "raquete preserva o modulo da velocidade")
	_check(absf(center_out.x) < incoming.length() * 0.25, "impacto no centro devolve quase vertical")

	# Regressao: rebatida no centro exato NAO pode sair perfeitamente vertical.
	# Se sair, a bola abre uma coluna na parede e fica presa no canal para sempre
	# (foi exatamente o que o soak test flagrou).
	_check(absf(center_out.x) > 0.0, "impacto no centro nunca devolve vertical exata")
	_approx(absf(center_out.angle_to(Vector2.UP)), BallPhysics.MIN_PADDLE_ANGLE, 0.001,
		"rebatida central usa MIN_PADDLE_ANGLE")

	# O sentido do desvio segue o que a bola ja tinha, para ela varrer o campo.
	var drift_left := BallPhysics.paddle_bounce(paddle.get_center(), Vector2(-3.0, 250.0), paddle)
	var drift_right := BallPhysics.paddle_bounce(paddle.get_center(), Vector2(3.0, 250.0), paddle)
	_check(drift_left.x < 0.0, "bola vindo da direita continua indo para a esquerda")
	_check(drift_right.x > 0.0, "bola vindo da esquerda continua indo para a direita")

	# Sem nenhuma pista de sentido, a raquete em movimento decide.
	var drift_by_paddle := BallPhysics.paddle_bounce(paddle.get_center(), Vector2(0.0, 250.0), paddle, -50.0)
	_check(drift_by_paddle.x < 0.0, "sem sentido previo, a raquete em movimento define o desvio")

	var left_out := BallPhysics.paddle_bounce(Vector2(paddle.position.x, paddle.position.y), incoming, paddle)
	var right_out := BallPhysics.paddle_bounce(Vector2(paddle.end.x, paddle.position.y), incoming, paddle)
	_check(left_out.x < 0.0, "impacto na ponta esquerda joga a bola para a esquerda")
	_check(right_out.x > 0.0, "impacto na ponta direita joga a bola para a direita")
	_approx(left_out.x, -right_out.x, 0.01, "angulos das pontas sao simetricos")
	_check(absf(left_out.angle_to(Vector2.UP)) <= BallPhysics.MAX_BOUNCE_ANGLE + EPS,
		"angulo nao passa de MAX_BOUNCE_ANGLE")

	# Efeito da raquete em movimento inclina a saida, sem alterar o modulo.
	var spun := BallPhysics.paddle_bounce(paddle.get_center(), incoming, paddle, 400.0)
	_check(spun.x > center_out.x, "raquete indo para a direita empurra a bola para a direita")
	_approx(spun.length(), incoming.length(), 0.01, "efeito preserva o modulo")

	# Componente vertical minimo: impede o loop horizontal infinito.
	var flat := BallPhysics.enforce_min_vertical(Vector2(300.0, 1.0))
	_check(absf(flat.y) >= 300.0 * BallPhysics.MIN_VERTICAL_RATIO * 0.99, "Y minimo garantido")
	_approx(flat.length(), Vector2(300.0, 1.0).length(), 0.01, "correcao de Y preserva o modulo")
	_check(flat.x > 0.0, "correcao de Y preserva o sentido de X")
	var steep := Vector2(10.0, -300.0)
	_check(BallPhysics.enforce_min_vertical(steep) == steep, "velocidade ja vertical fica intacta")

	# Lancamento: sempre para cima e nunca perfeitamente vertical.
	for bias in [-1.0, -0.5, 0.0, 0.01, 0.5, 1.0]:
		var launch := BallPhysics.launch_velocity(250.0, bias)
		_check(launch.y < 0.0, "lancamento com bias %s vai para cima" % bias)
		_approx(launch.length(), 250.0, 0.01, "lancamento com bias %s respeita a velocidade" % bias)
		_check(absf(launch.x) > 1.0, "lancamento com bias %s nao e perfeitamente vertical" % bias)

	# dt zero ou velocidade zero nao mudam nada.
	res = BallPhysics.advance(Vector2(50.0, 50.0), Vector2(100.0, 100.0), radius, 0.0, bounds, [])
	_check(Vector2(res["pos"]) == Vector2(50.0, 50.0), "dt zero nao move a bola")

	# ------------------------------------------------------------------
	# REGRESSAO: bola presa POR BAIXO da raquete (encontrada em 30/07/2026)
	# ------------------------------------------------------------------
	# _resolve_rect via a penetracao vertical como a menor, empurrava a bola para
	# baixo da raquete e invertia vel.y; paddle_bounce entao sobrescrevia a
	# velocidade para cima, incondicionalmente. No quadro seguinte tudo se
	# repetia: a bola ficava parada no mesmo pixel para sempre, e a partida
	# nunca terminava. O soak fez 19934 rebatidas em 400 s antes de acusar.
	var trap_bounds := Rect2(0.0, 0.0, 640.0, 360.0)
	var trap_paddle := Rect2(300.0, 326.0, 74.0, 10.0)
	var trap_targets: Array = [{
		"rect": trap_paddle, "id": "paddle", "kind": BallPhysics.KIND_PADDLE, "vx": 0.0,
	}]

	# Bola encostada no lado de BAIXO da raquete, tentando subir.
	var trapped := BallPhysics.advance(
		Vector2(337.0, 340.0), Vector2(25.0, -208.0), radius, 1.0 / 60.0, trap_bounds, trap_targets
	)
	_check(Vector2(trapped["vel"]).y > 0.0,
		"bola encostada por baixo da raquete nao e relancada para cima")
	_check(not _has_event(trapped, "paddle"),
		"encostar por baixo nao conta como rebatida")

	# E ela precisa mesmo CAIR: 120 quadros depois, ja saiu pelo fundo.
	var trap_pos := Vector2(337.0, 340.0)
	var trap_vel := Vector2(25.0, -208.0)
	var escaped := false
	for _frame in 120:
		var stepped := BallPhysics.advance(trap_pos, trap_vel, radius, 1.0 / 60.0, trap_bounds, trap_targets)
		trap_pos = stepped["pos"]
		trap_vel = stepped["vel"]
		if bool(stepped["lost"]):
			escaped = true
			break
	_check(escaped, "a bola que passou por baixo da raquete e perdida, nao fica presa")

	# O caso legitimo continua funcionando: bola vindo de CIMA e rebatida.
	var above := BallPhysics.advance(
		Vector2(337.0, 320.0), Vector2(0.0, 240.0), radius, 1.0 / 60.0, trap_bounds, trap_targets
	)
	_check(_has_event(above, "paddle"), "bola vinda de cima ainda e rebatida")
	_check(Vector2(above["vel"]).y < 0.0, "a rebatida legitima devolve a bola para cima")


func _has_event(result: Dictionary, type_name: String) -> bool:
	for event in result["events"]:
		if str(event["type"]) == type_name:
			return true
	return false


func _first_event(result: Dictionary, type_name: String) -> Dictionary:
	for event in result["events"]:
		if str(event["type"]) == type_name:
			return event
	return {}


# ============================================================================
#  ScoreRules
# ============================================================================

func _test_score_rules() -> void:
	_begin("ScoreRules")

	_eq(ScoreRules.combo_multiplier(0), 1.0, "combo 0 -> x1")
	_eq(ScoreRules.combo_multiplier(1), 1.0, "combo 1 -> x1")
	_eq(ScoreRules.combo_multiplier(2), 1.25, "combo 2 -> x1.25")
	_eq(ScoreRules.combo_multiplier(5), 2.0, "combo 5 -> x2")
	_eq(ScoreRules.combo_multiplier(100), ScoreRules.COMBO_MAX, "combo satura em COMBO_MAX")

	# Multiplicador tem que ser monotonico: nunca vale menos manter o combo.
	var previous := 0.0
	for combo in range(0, 40):
		var current := ScoreRules.combo_multiplier(combo)
		_check(current >= previous, "multiplicador nao regride no combo %d" % combo)
		previous = current

	_eq(ScoreRules.brick_points(80, 1), 80, "bloco sem combo vale o base")
	_eq(ScoreRules.brick_points(80, 5), 160, "bloco com combo 5 vale o dobro")
	_eq(ScoreRules.chip_points(200), 50, "trincar um bloco reforcado vale 25%")

	_check(ScoreRules.level_clear_bonus(1, 3) > 0, "bonus de fase e positivo")
	_check(ScoreRules.level_clear_bonus(1, 3) > ScoreRules.level_clear_bonus(1, 0),
		"mais vidas restantes rendem mais bonus")
	_eq(ScoreRules.level_clear_bonus(999, 0), ScoreRules.LEVEL_CLEAR_BONUS_CAP,
		"bonus de fase satura no teto (protege o CHECK do schema)")

	# Velocidade sobe com a fase e satura. O teto e lido do proprio saturado, e nao
	# cravado: reafirmar o numero aqui so duplicaria a constante em dois lugares.
	var speed_ceiling := ScoreRules.ball_speed_for_level(9999)
	_check(speed_ceiling > ScoreRules.ball_speed_for_level(1),
		"a velocidade sobe da fase 1 ate o teto")
	var previous_speed := 0.0
	for level in range(1, 40):
		var speed := ScoreRules.ball_speed_for_level(level)
		_check(speed >= previous_speed, "velocidade nao regride na fase %d" % level)
		_check(speed <= speed_ceiling + EPS, "velocidade satura em %.0f px/s" % speed_ceiling)
		previous_speed = speed

	_eq(ScoreRules.ball_speed_multiplier(0, 88), 1.0, "parede intacta nao acelera")
	_check(ScoreRules.ball_speed_multiplier(88, 88) > 1.3, "parede limpa acelera a bola")
	_eq(ScoreRules.ball_speed_multiplier(5, 0), 1.0, "divisao por zero protegida")

	_check(ScoreRules.is_valid_score(0), "0 e pontuacao valida")
	_check(ScoreRules.is_valid_score(ScoreRules.MAX_VALID_SCORE), "teto e valido")
	_check(not ScoreRules.is_valid_score(-1), "negativo e invalido")
	_check(not ScoreRules.is_valid_score(ScoreRules.MAX_VALID_SCORE + 1), "acima do teto e invalido")


# ============================================================================
#  NickUtil
# ============================================================================

func _test_nick_util() -> void:
	_begin("NickUtil")

	_eq(NickUtil.sanitize("igor"), "IGOR", "converte para maiusculas")
	_eq(NickUtil.sanitize("  igor  "), "IGOR", "remove espacos das pontas")
	_eq(NickUtil.sanitize("José"), "JOSE", "remove acentos")
	_eq(NickUtil.sanitize("ÁÉÍÓÚÇÃÑ"), "AEIOUCAN", "remove todos os acentos mapeados")
	_eq(NickUtil.sanitize("a<script>"), "ASCRIPT", "descarta caracteres de markup")
	_eq(NickUtil.sanitize("dr.  house"), "DR. HOUSE", "colapsa espacos repetidos")
	_eq(NickUtil.sanitize("   x"), "X", "nao deixa separador no inicio")
	_eq(NickUtil.sanitize("ABCDEFGHIJKLMNOP").length(), NickUtil.MAX_LEN, "trunca em MAX_LEN")
	_eq(NickUtil.sanitize(""), "", "vazio continua vazio")
	_eq(NickUtil.sanitize("!!!"), "", "so simbolos proibidos resulta em vazio")
	_eq(NickUtil.sanitize("tj-pr_01"), "TJ-PR_01", "preserva separadores permitidos")

	_check(NickUtil.is_valid("IGOR"), "nick normal e valido")
	_check(NickUtil.is_valid("ab"), "nick de 2 caracteres e valido")
	_check(not NickUtil.is_valid("a"), "nick de 1 caractere e invalido")
	_check(not NickUtil.is_valid(""), "nick vazio e invalido")
	_check(not NickUtil.is_valid("..."), "nick so com pontuacao e invalido")
	_check(not NickUtil.is_valid("---"), "nick so com tracos e invalido")
	_check(NickUtil.is_valid("A1"), "letra + digito e valido")

	_eq(NickUtil.to_submittable("!!"), NickUtil.FALLBACK, "invalido cai no fallback")
	_eq(NickUtil.to_submittable("igor"), "IGOR", "valido passa sanitizado")
	_eq(NickUtil.for_display(""), NickUtil.FALLBACK, "exibicao de vazio usa o fallback")
	_eq(NickUtil.for_display("ABCDEFGHIJ", 4), "ABCD", "exibicao respeita o limite de colunas")

	# O regex do schema SQL precisa aceitar tudo que sanitize() produz.
	var regex := RegEx.create_from_string("^[A-Z0-9 ._-]{2,10}$")
	for raw in ["igor", "José", "dr.  house", "tj-pr_01", "ab", "ABCDEFGHIJKLMNOP", "!!", "0"]:
		var submittable := NickUtil.to_submittable(raw)
		_check(regex.search(submittable) != null,
			"'%s' -> '%s' passa no CHECK do schema" % [raw, submittable])


# ============================================================================
#  PixelFont
# ============================================================================

func _test_pixel_font() -> void:
	_begin("PixelFont")

	# Todo glifo tem exatamente 7 linhas de 5 caracteres, ou o atlas sai torto.
	for key in PixelFont.GLYPHS:
		var rows: Array = PixelFont.GLYPHS[key]
		_eq(rows.size(), PixelFont.GLYPH_H, "glifo '%s' tem %d linhas" % [key, PixelFont.GLYPH_H])
		for row in rows:
			_eq(str(row).length(), PixelFont.GLYPH_W, "glifo '%s' tem linhas de %d px" % [key, PixelFont.GLYPH_W])

	# Cobertura: todo caractere que o jogo escreve na tela precisa ter glifo.
	var used_strings: Array[String] = [
		"ARKANOIA", "TJ-PR * SECAO SECRETA DE JOGOS", "DIGITE SEU NICK", "JOGAR",
		"TOP 10 GLOBAL", "NENHUMA PONTUACAO AINDA", "CARREGANDO...",
		"JOGADOR", "PONTOS", "RECORDE", "FASE", "VIDAS", "COMBO X1.25",
		"PAUSE", "CONTINUAR", "SAIR PARA O INICIO",
		"P OU ESC TAMBEM CONTINUA", "TOQUE EM CONTINUAR",
		"FIM DE JOGO", "NOVO RECORDE PESSOAL", "JOGAR DE NOVO", "MENU", "ENTER", "ESC",
		"BOLA PERDIDA", "VIDA RESTANTE", "VIDAS RESTANTES", "FASE 1", "BONUS 1000",
		"CLIQUE OU ESPACO PARA LANCAR", "TOQUE PARA LANCAR",
		"MOUSE OU A D MOVE * CLIQUE LANCA", "P PAUSA DISCRETO * M LIGA O SOM",
		"ARRASTE MOVE * TOQUE LANCA", "TOQUE NO ICONE PAUSA * M LIGA O SOM",
		"PONTUACAO ENVIADA", "MUITOS ENVIOS, AGUARDE", "SEM CONEXAO",
		"LEADERBOARD NAO CONFIGURADO", "PONTUACAO INVALIDA", "RESPOSTA INVALIDA",
		"NICK: DE 2 A 10 CARACTERES", "PONTUACAO ZERO NAO E ENVIADA",
		"ENVIANDO PONTUACAO...", "ANONIMO", "ERRO 500 AO ENVIAR", "FALHA DE REDE (1)",
		"FALHA AO DESCOMPRIMIR", "FIM",
		"01 IGOR...... 012500 30/07/26", "--/--/--",
	]
	for text in used_strings:
		for i in text.length():
			var ch := text[i]
			_check(PixelFont.has_glyph(ch),
				"glifo existe para '%s' (usado em \"%s\")" % [ch, text])

	# As mensagens de fase concluida tambem.
	for message in LevelBuilder.CLEAR_MESSAGES:
		for i in message.length():
			_check(PixelFont.has_glyph(message[i]),
				"glifo existe para '%s' (usado em \"%s\")" % [message[i], message])

	# E os rotulos dos power-ups, varridos do catalogo em vez de mantidos a mao:
	# um nome novo sem glifo quebra o teste sozinho, sem ninguem lembrar de vir aqui.
	for id in PowerUps.all_ids():
		var powerup_label := PowerUps.label(str(id))
		_check(not powerup_label.is_empty(), "power-up '%s' tem rotulo" % id)
		for i in powerup_label.length():
			_check(PixelFont.has_glyph(powerup_label[i]),
				"glifo existe para '%s' (usado no power-up %s)" % [powerup_label[i], id])

	# Metrica de largura.
	_eq(PixelFont.text_width("", 1), 0, "texto vazio tem largura 0")
	_eq(PixelFont.text_width("A", 1), PixelFont.GLYPH_W, "1 caractere == largura do glifo")
	_eq(PixelFont.text_width("AB", 1), PixelFont.GLYPH_W * 2 + PixelFont.TRACKING, "2 caracteres somam o tracking")
	_eq(PixelFont.text_width("ABC", 2), PixelFont.text_width("ABC", 1) * 2, "escala 2 dobra a largura")
	_eq(PixelFont.text_height(3), PixelFont.GLYPH_H * 3, "altura escala com o fator")

	var previous := 0
	for length in range(1, 20):
		var width := PixelFont.text_width("A".repeat(length), 1)
		_check(width > previous, "largura cresce com %d caracteres" % length)
		previous = width

	# O atlas precisa ser construivel em headless (driver dummy).
	var texture := PixelFont.texture()
	_check(texture != null, "atlas de glifos e construido")
	if texture != null:
		_eq(texture.get_height(), PixelFont.GLYPH_H, "atlas tem a altura de um glifo")
		_eq(texture.get_width(), PixelFont.GLYPHS.size() * PixelFont.GLYPH_W,
			"atlas tem uma celula por glifo")

	# Caractere sem glifo cai no fallback em vez de estourar.
	_check(not PixelFont.has_glyph("ç"), "cedilha minuscula nao tem glifo proprio")


# ============================================================================
#  SupabaseConfig
# ============================================================================

func _test_supabase_config() -> void:
	_begin("SupabaseConfig")

	_eq(SupabaseConfig.table_url("https://x.supabase.co"), "https://x.supabase.co/rest/v1/scores",
		"URL de escrita aponta para a tabela scores")
	_eq(SupabaseConfig.table_url("https://x.supabase.co/"), "https://x.supabase.co/rest/v1/scores",
		"barra final na URL base nao duplica")

	var top := SupabaseConfig.top_scores_url("https://x.supabase.co")
	_check(top.contains("/rest/v1/leaderboard"), "leitura usa a view leaderboard")
	_check(top.contains("order=score.desc,created_at.asc"), "ordenacao por pontuacao e desempate por data")
	_check(top.contains("limit=10"), "limite padrao de 10")
	_check(top.contains("select=nick,score,created_at"), "seleciona apenas colunas publicas")
	_check(not top.contains("client_fingerprint"), "nao tenta ler coluna privada")

	_check(SupabaseConfig.top_scores_url("https://x.supabase.co", "leaderboard", 9999).contains("limit=100"),
		"limite e saturado em 100")
	_check(SupabaseConfig.top_scores_url("https://x.supabase.co", "leaderboard", -5).contains("limit=1"),
		"limite negativo e corrigido")

	var headers := SupabaseConfig.headers("chave-de-teste")
	var joined := "|".join(headers)
	_check(joined.contains("apikey: chave-de-teste"), "cabecalho apikey presente")
	_check(joined.contains("Authorization: Bearer chave-de-teste"), "cabecalho Authorization presente")
	_check(joined.contains("Content-Type: application/json"), "cabecalho Content-Type presente")

	var with_extra := SupabaseConfig.headers("k", PackedStringArray(["Prefer: return=minimal"]))
	_check("|".join(with_extra).contains("Prefer: return=minimal"), "cabecalhos extras sao anexados")
	_eq(with_extra.size(), headers.size() + 1, "extras nao substituem os padroes")

	# Corpo do POST: nick sanitizado, pontuacao saturada, JSON valido.
	var body := SupabaseConfig.submit_body("josé!", 1234, 3, 65000)
	var parsed: Variant = JSON.parse_string(body)
	_check(parsed is Dictionary, "corpo do POST e JSON valido")
	if parsed is Dictionary:
		_eq(str(parsed["nick"]), "JOSE", "nick vai sanitizado")
		_eq(int(parsed["score"]), 1234, "pontuacao preservada")
		_eq(int(parsed["level"]), 3, "fase preservada")
		_eq(int(parsed["duration_ms"]), 65000, "duracao preservada")
		_check(not parsed.has("created_at"), "cliente nao envia created_at")
		_check(not parsed.has("id"), "cliente nao envia id")
		_check(not parsed.has("client_fingerprint"), "cliente nao envia fingerprint")

	var clamped: Variant = JSON.parse_string(SupabaseConfig.submit_body("X", 99999999, 0, -50))
	_eq(int(clamped["score"]), ScoreRules.MAX_VALID_SCORE, "pontuacao acima do teto e saturada")
	_eq(int(clamped["level"]), 1, "fase minima e 1")
	_eq(int(clamped["duration_ms"]), 0, "duracao negativa vira 0")
	_eq(str(clamped["nick"]), NickUtil.FALLBACK, "nick curto demais cai no fallback")

	_check(SupabaseConfig.is_configured(SupabaseConfig.URL, SupabaseConfig.PUBLISHABLE_KEY),
		"a configuracao embutida e valida")
	_check(not SupabaseConfig.is_configured("http://x.co", SupabaseConfig.PUBLISHABLE_KEY),
		"URL sem https e rejeitada")
	_check(not SupabaseConfig.is_configured(SupabaseConfig.URL, "curta"), "chave curta e rejeitada")

	# Nunca embutir credencial de servidor no cliente.
	_check(not SupabaseConfig.PUBLISHABLE_KEY.contains("service_role"),
		"a chave embutida nao e service_role")
	_check(not SupabaseConfig.PUBLISHABLE_KEY.begins_with("postgresql://"),
		"a chave embutida nao e connection string")


# ============================================================================
#  Leaderboard (helpers puros)
# ============================================================================

func _test_leaderboard_helpers() -> void:
	_begin("TextUtil / LeaderboardView")

	_eq(TextUtil.format_iso_date("2026-07-30T13:45:12.123456+00:00"), "30/07/26",
		"data ISO do Postgres vira DD/MM/AA")
	_eq(TextUtil.format_iso_date("2026-01-05"), "05/01/26", "data sem hora tambem funciona")
	_eq(TextUtil.format_iso_date(""), TextUtil.INVALID_DATE, "data vazia nao quebra a tabela")
	_eq(TextUtil.format_iso_date("lixo"), TextUtil.INVALID_DATE, "data invalida nao quebra a tabela")
	_eq(TextUtil.format_iso_date("abcd-ef-gh"), TextUtil.INVALID_DATE,
		"data com letras no lugar dos numeros e rejeitada")

	_eq(TextUtil.pad_number(42, 6), "000042", "placar recebe zeros a esquerda")
	_eq(TextUtil.pad_number(-5, 3), "000", "valor negativo e tratado como zero")
	_eq(TextUtil.pad_number(1234567, 6), "1234567", "numero maior que o campo nao e truncado")

	# A largura da linha da tabela tem que caber no campo de jogo.
	_check(LeaderboardView.row_width() <= ArenaLayout.PLAY_WIDTH,
		"linha do ranking (%s px) cabe na largura do campo" % LeaderboardView.row_width())


# ============================================================================
#  PowerUps
# ============================================================================

func _test_power_ups() -> void:
	_begin("PowerUps")

	# --- Integridade do catalogo ---
	for id_variant in PowerUps.all_ids():
		var id := str(id_variant)
		_check(PowerUps.exists(id), "power-up '%s' existe" % id)
		_check(PowerUps.duration(id) >= 0.0, "'%s' tem duracao nao negativa" % id)
		_check(absf(PowerUps.shade(id)) <= 0.06 + EPS,
			"'%s' varia o tom em no maximo 6%% (capsulas quase identicas)" % id)

		var rows := PowerUps.sigil(id)
		_eq(rows.size(), 3, "sigilo de '%s' tem 3 linhas" % id)
		for row in rows:
			_eq(str(row).length(), 5, "linha do sigilo de '%s' tem 5 colunas" % id)
			for i in str(row).length():
				var ch := str(row)[i]
				_check(ch == "#" or ch == ".", "sigilo de '%s' so usa # e ." % id)

	# Nenhum sigilo repetido: duas capsulas iguais seriam impossiveis de aprender.
	var seen_sigils := {}
	for id_variant in PowerUps.all_ids():
		var key := "|".join(PackedStringArray(PowerUps.sigil(str(id_variant))))
		_check(not seen_sigils.has(key), "sigilo de '%s' e unico" % id_variant)
		seen_sigils[key] = true

	# --- Opostos ---
	for id_variant in PowerUps.all_ids():
		var id := str(id_variant)
		var pair := PowerUps.opposite(id)
		if pair.is_empty():
			continue
		_check(PowerUps.exists(pair), "oposto de '%s' existe no catalogo" % id)
		_eq(PowerUps.opposite(pair), id, "oposto de '%s' e simetrico" % id)

	# --- Conjunto ativo ---
	var active := PowerUps.apply({}, PowerUps.WIDE)
	_eq(active.size(), 1, "apanhar um item ativa um efeito")

	var twice := PowerUps.apply(active, PowerUps.WIDE)
	_eq(twice.size(), 1, "reapanhar o mesmo item nao empilha")
	_approx(PowerUps.paddle_width_scale(twice), PowerUps.paddle_width_scale(active), EPS,
		"reapanhar nao dobra o escalar")

	# Renovar leva o tempo de volta ao cheio, nunca o encurta.
	var half := {PowerUps.WIDE: 1.0}
	var renewed := PowerUps.apply(half, PowerUps.WIDE)
	_approx(float(renewed[PowerUps.WIDE]), PowerUps.duration(PowerUps.WIDE), EPS,
		"reapanhar renova a duracao")

	var cancelled := PowerUps.apply(PowerUps.apply({}, PowerUps.SLOW), PowerUps.FAST)
	_check(not cancelled.has(PowerUps.SLOW), "SURTO cancela CALMA")
	_check(cancelled.has(PowerUps.FAST), "SURTO fica ativo")

	var instant := PowerUps.apply({}, PowerUps.LIFE)
	_check(instant.is_empty(), "item instantaneo nunca entra no conjunto ativo")
	_check(PowerUps.is_instant(PowerUps.LIFE), "FOLEGO e instantaneo")
	_check(not PowerUps.is_instant(PowerUps.WIDE), "LUCIDEZ tem duracao")

	# --- Tick ---
	var ticked := PowerUps.tick({PowerUps.WIDE: 1.0}, 0.4)
	_eq(int(ticked["expired"].size()), 0, "efeito com tempo sobrando nao expira")
	_approx(float(ticked["active"][PowerUps.WIDE]), 0.6, EPS, "tick desconta o delta")

	var done := PowerUps.tick({PowerUps.WIDE: 0.2}, 0.4)
	_eq(int(done["active"].size()), 0, "efeito esgotado sai do conjunto")
	_eq(int(done["expired"].size()), 1, "efeito esgotado e anunciado uma unica vez")
	_eq(str(done["expired"][0]), PowerUps.WIDE, "o id anunciado e o certo")

	var empty := PowerUps.tick({}, 1.0)
	_eq(int(empty["active"].size()), 0, "tick em conjunto vazio nao inventa efeito")
	_eq(int(empty["expired"].size()), 0, "tick em conjunto vazio nao anuncia nada")

	# --- Escalares neutros sem efeito ---
	_approx(PowerUps.paddle_width_scale({}), 1.0, EPS, "sem efeito a raquete tem largura normal")
	_approx(PowerUps.ball_speed_scale({}), 1.0, EPS, "sem efeito a bola tem velocidade normal")
	_approx(PowerUps.paddle_axis_sign({}), 1.0, EPS, "sem efeito o controle nao inverte")
	_eq(PowerUps.risk_level({}), 0, "sem efeito o risco e zero")

	# --- Direcao dos escalares ---
	_check(PowerUps.paddle_width_scale(PowerUps.apply({}, PowerUps.WIDE)) > 1.0, "LUCIDEZ alarga a raquete")
	_check(PowerUps.paddle_width_scale(PowerUps.apply({}, PowerUps.NARROW)) < 1.0, "PANICO encurta a raquete")
	_check(PowerUps.ball_speed_scale(PowerUps.apply({}, PowerUps.SLOW)) < 1.0, "CALMA desacelera a bola")
	_check(PowerUps.ball_speed_scale(PowerUps.apply({}, PowerUps.FAST)) > 1.0, "SURTO acelera a bola")

	# Os escalares nunca escapam das travas, mesmo com tudo ativo de uma vez.
	var everything := {}
	for id_variant in PowerUps.all_ids():
		everything[str(id_variant)] = 10.0
	var width := PowerUps.paddle_width_scale(everything)
	_check(width >= ArenaLayout.PADDLE_MIN_WIDTH_SCALE - EPS and width <= ArenaLayout.PADDLE_MAX_WIDTH_SCALE + EPS,
		"largura da raquete fica na trava mesmo com tudo ativo (%.2f)" % width)
	var ball_scale := PowerUps.ball_speed_scale(everything)
	_check(ball_scale >= PowerUps.SPEED_MIN_SCALE - EPS and ball_scale <= PowerUps.SPEED_MAX_SCALE + EPS,
		"velocidade da bola fica na trava mesmo com tudo ativo (%.2f)" % ball_scale)

	# --- Risco: itens benignos custam pontos, itens ruins pagam ---
	_check(PowerUps.risk(PowerUps.WIDE) < 0, "LUCIDEZ tem risco negativo (vantagem custa pontos)")
	_check(PowerUps.risk(PowerUps.NARROW) > 0, "PANICO tem risco positivo")
	_check(PowerUps.risk_level(PowerUps.apply(PowerUps.apply({}, PowerUps.WIDE), PowerUps.SLOW)) < 0,
		"so vantagem deixa o risco negativo")

	# --- A REGRA DO CANAL VISUAL ---
	# Um efeito visual nao pode tocar em NENHUM escalar da simulacao: ele custa
	# pontos porque a mao do jogador piora, nao porque a fisica mudou. E este o
	# teste que impede uma alucinacao de virar trapaca.
	var visual_count := 0
	for id_variant in PowerUps.all_ids():
		var id := str(id_variant)
		if not PowerUps.is_visual(id):
			continue
		visual_count += 1
		var only := PowerUps.apply({}, id)
		_approx(PowerUps.paddle_width_scale(only), 1.0, EPS,
			"efeito visual '%s' nao mexe na largura da raquete" % id)
		_approx(PowerUps.ball_speed_scale(only), 1.0, EPS,
			"efeito visual '%s' nao mexe na velocidade da bola" % id)
		_approx(PowerUps.paddle_axis_sign(only), 1.0, EPS,
			"efeito visual '%s' nao inverte o controle" % id)
		_check(PowerUps.risk(id) > 0,
			"efeito visual '%s' ainda vale risco (a dificuldade e psicologica)" % id)
	_check(visual_count >= 5, "o cardapio tem alucinacoes de verdade (%d no canal visual)" % visual_count)

	# VERTIGEM e a UNICA alucinacao que mexe na simulacao, e por isso vive no
	# canal de jogo em vez do visual.
	_check(not PowerUps.is_visual(PowerUps.MIRROR), "VERTIGEM esta no canal de jogo")
	_approx(PowerUps.paddle_axis_sign(PowerUps.apply({}, PowerUps.MIRROR)), -1.0, EPS,
		"VERTIGEM inverte o eixo de controle")
	_approx(PowerUps.paddle_axis_sign(PowerUps.apply(PowerUps.apply({}, PowerUps.MIRROR), PowerUps.WIDE)), -1.0, EPS,
		"outro efeito junto nao desfaz a inversao")

	# --- MIRAGEM: a permutacao precisa ser BIJECAO ---
	# Sem bijecao, dois blocos cairiam na mesma celula, um sumiria, e a mentira
	# seria obvia no primeiro quadro.
	var shuffle_rng := RandomNumberGenerator.new()
	shuffle_rng.seed = 31337
	var alive_ids := [3, 8, 15, 22, 47, 61]
	var mapping := PowerUps.shuffle_map(alive_ids, shuffle_rng)

	_eq(mapping.size(), alive_ids.size(), "a permutacao cobre todo bloco vivo")
	var hit := {}
	for id_variant in alive_ids:
		_check(mapping.has(id_variant), "bloco %s tem destino na permutacao" % id_variant)
		var destination: Variant = mapping[id_variant]
		_check(alive_ids.has(destination), "destino %s e um bloco vivo" % destination)
		_check(not hit.has(destination), "destino %s aparece uma unica vez (bijecao)" % destination)
		hit[destination] = true
	_eq(hit.size(), alive_ids.size(), "nenhum bloco fica sem ser desenhado")

	var rng_x := RandomNumberGenerator.new()
	var rng_y := RandomNumberGenerator.new()
	rng_x.seed = 5
	rng_y.seed = 5
	_eq(PowerUps.shuffle_map(alive_ids, rng_x), PowerUps.shuffle_map(alive_ids, rng_y),
		"a permutacao e reproduzivel com a mesma semente")
	_eq(PowerUps.shuffle_map([], shuffle_rng).size(), 0, "parede vazia permuta para nada")
	_eq(PowerUps.shuffle_map([7], shuffle_rng), {7: 7}, "bloco unico so pode mapear em si mesmo")

	# --- DERIVA: a curva oscila, nao acumula ---
	# A integral sobre um periodo completo tem que ser ~0, senao a bola sairia
	# derivando num sentido so e acabaria orbitando a raquete para sempre - a
	# mesma classe de defeito que MIN_PADDLE_ANGLE existe para evitar.
	var period := TAU / PowerUps.CURVE_FREQUENCY
	var samples := 2000
	var sample_dt := period / float(samples)
	var integral := 0.0
	var peak := 0.0
	for i in samples:
		var phase := float(i) * sample_dt
		integral += PowerUps.curve_rotation(phase, sample_dt)
		peak = maxf(peak, absf(PowerUps.curve_rotation(phase, 1.0)))
	_approx(integral, 0.0, 0.001, "a rotacao da DERIVA soma zero num periodo (%.5f)" % integral)
	_approx(peak, PowerUps.CURVE_AMPLITUDE, 0.01, "o pico da curva bate com a amplitude")
	_eq(PowerUps.curve_rotation(0.0, 1.0), 0.0, "a curva comeca neutra")

	# --- CISAO: bolas irmas em leque simetrico ---
	var base_vel := Vector2(0.0, -240.0)
	var extras := PowerUps.split_velocities(base_vel, PowerUps.SPLIT_COUNT - 1, PowerUps.SPLIT_SPREAD)
	_eq(extras.size(), PowerUps.SPLIT_COUNT - 1,
		"CISAO gera as irmas que faltam para %d bolas" % PowerUps.SPLIT_COUNT)

	var sum_vel := base_vel
	for extra in extras:
		var extra_vel: Vector2 = extra
		_approx(extra_vel.length(), base_vel.length(), 1.0, "bola irma mantem a velocidade da original")
		_check(extra_vel.y < 0.0, "bola irma continua subindo")
		sum_vel += extra_vel
	# Leque simetrico: a divisao nao pode empurrar o conjunto para um dos lados.
	_approx(sum_vel.x, 0.0, 1.0, "o leque da CISAO e simetrico (soma em x = %.2f)" % sum_vel.x)

	_eq(PowerUps.split_velocities(Vector2.ZERO, 2, 0.4).size(), 0, "bola parada nao se divide")
	_eq(PowerUps.split_velocities(base_vel, 0, 0.4).size(), 0, "dividir em zero nao gera bola")

	# --- Tabelas de sorteio ---
	_check(PowerUps.drop_table(LevelBuilder.TYPE_NORMAL).is_empty(), "bloco comum nao solta capsula")
	_check(PowerUps.drop_table(LevelBuilder.TYPE_TJ_BLUE).is_empty(), "bloco azul TJ nao solta capsula")
	_check(not PowerUps.drop_table(LevelBuilder.TYPE_SPECIAL).is_empty(), "bloco especial fixo solta capsula")
	_check(not PowerUps.drop_table(LevelBuilder.TYPE_SPECIAL_SPAWNED).is_empty(), "bloco surgido solta capsula")

	for id_variant in PowerUps.drop_table(LevelBuilder.TYPE_SPECIAL):
		_eq(PowerUps.tier(str(id_variant)), PowerUps.TIER_COMMON, "bloco fixo so solta item comum")
	for id_variant in PowerUps.drop_table(LevelBuilder.TYPE_SPECIAL_SPAWNED):
		_eq(PowerUps.tier(str(id_variant)), PowerUps.TIER_RARE, "bloco surgido so solta item raro")

	# Sorteio reproduzivel: mesma semente, mesma sequencia.
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 4242
	rng_b.seed = 4242
	for i in 30:
		_eq(PowerUps.roll_drop(rng_a, LevelBuilder.TYPE_SPECIAL),
			PowerUps.roll_drop(rng_b, LevelBuilder.TYPE_SPECIAL),
			"sorteio %d reproduzivel com a mesma semente" % i)
	_eq(PowerUps.roll_drop(rng_a, LevelBuilder.TYPE_NORMAL), "", "bloco comum sorteia vazio")

	# --- Sorteio ponderado ---
	# SURTO e CISAO saem mais que os demais: sao os dois itens que mais mudam a
	# partida, um apertando o ritmo e o outro enchendo a tela de bolas.
	for id_variant in PowerUps.all_ids():
		_check(PowerUps.weight(str(id_variant)) > 0.0, "'%s' tem peso positivo" % id_variant)

	_check(PowerUps.weight(PowerUps.FAST) > PowerUps.weight(PowerUps.NARROW),
		"SURTO sai mais que os outros comuns")
	_check(PowerUps.weight(PowerUps.MULTI) > PowerUps.weight(PowerUps.SHUFFLE),
		"CISAO sai mais que as alucinacoes")

	var fast_chance := PowerUps.drop_chance(PowerUps.FAST, LevelBuilder.TYPE_SPECIAL)
	var multi_chance := PowerUps.drop_chance(PowerUps.MULTI, LevelBuilder.TYPE_SPECIAL_SPAWNED)
	_check(fast_chance > 0.4 and fast_chance < 0.6,
		"SURTO fica perto de metade das capsulas comuns (%.0f%%)" % (fast_chance * 100.0))
	_check(multi_chance > 0.2 and multi_chance < 0.35,
		"CISAO fica perto de um terco das capsulas raras (%.0f%%)" % (multi_chance * 100.0))
	_eq(PowerUps.drop_chance(PowerUps.FAST, LevelBuilder.TYPE_NORMAL), 0.0,
		"bloco comum nao solta SURTO")
	_eq(PowerUps.drop_chance(PowerUps.MULTI, LevelBuilder.TYPE_SPECIAL), 0.0,
		"bloco fixo nao solta CISAO")

	# Toda chance de um tier tem que somar 1: nenhum item fica inalcancavel e o
	# sorteio nunca "cai fora" da tabela.
	for brick_type in [LevelBuilder.TYPE_SPECIAL, LevelBuilder.TYPE_SPECIAL_SPAWNED]:
		var sum_chance := 0.0
		for id_variant in PowerUps.drop_table(brick_type):
			var chance := PowerUps.drop_chance(str(id_variant), brick_type)
			_check(chance > 0.0, "'%s' e alcancavel no sorteio" % id_variant)
			sum_chance += chance
		_approx(sum_chance, 1.0, EPS, "as chances do tipo %d somam 1" % brick_type)

	# E a frequencia observada precisa bater com o peso declarado.
	var tally := {}
	var trials := 20000
	var rng_w := RandomNumberGenerator.new()
	rng_w.seed = 20260730
	for i in trials:
		var id := PowerUps.roll_drop(rng_w, LevelBuilder.TYPE_SPECIAL_SPAWNED)
		tally[id] = int(tally.get(id, 0)) + 1
	var observed := float(int(tally.get(PowerUps.MULTI, 0))) / float(trials)
	_approx(observed, multi_chance, 0.02,
		"CISAO saiu %.1f%% das vezes, esperado %.1f%%" % [observed * 100.0, multi_chance * 100.0])
	_eq(tally.size(), PowerUps.drop_table(LevelBuilder.TYPE_SPECIAL_SPAWNED).size(),
		"em 20 mil sorteios todo item raro apareceu ao menos uma vez")

	# Ordem da faixa: a do catalogo, nao a de insercao. Sem isso os sigilos
	# dancariam na tela a cada efeito que expira.
	var inserted := PowerUps.apply(PowerUps.apply({}, PowerUps.FAST), PowerUps.WIDE)
	var order_a := PowerUps.ordered_ids(inserted)
	var reinserted := PowerUps.apply(PowerUps.apply({}, PowerUps.WIDE), PowerUps.FAST)
	_eq(order_a, PowerUps.ordered_ids(reinserted), "a ordem da faixa nao depende de quem chegou antes")


# ============================================================================
#  Capsules
# ============================================================================

func _test_capsules() -> void:
	_begin("Capsules")

	var cases := {
		"paisagem": Vector2(640, 360),
		"retrato": Vector2(640, 1385),
		"ultrawide": Vector2(853, 360),
		"quadrado": Vector2(700, 700),
	}

	for label in cases:
		var layout := ArenaLayout.compute(cases[label])
		var size := Capsules.size(layout)
		var speed := Capsules.speed(layout)

		_eq(size.x, Capsules.WIDTH, "%s: largura da capsula e fixa" % label)
		_check(size.y >= Capsules.MIN_HEIGHT - EPS and size.y <= Capsules.MAX_HEIGHT + EPS,
			"%s: altura da capsula dentro dos limites (%.1f)" % [label, size.y])
		_check(speed > 0.0, "%s: capsula cai" % label)

		# A capsula escala com o campo, como a bola: o tempo de queda de ponta a
		# ponta fica na mesma ordem em qualquer formato.
		var play: Rect2 = layout["play"]
		var full_fall := play.size.y / speed
		_check(full_fall > 2.0 and full_fall < 6.0,
			"%s: atravessar o campo leva %.1fs (comparavel entre formatos)" % [label, full_fall])

	# --- Coleta ---
	var layout_base := ArenaLayout.compute(Vector2(640, 360))
	var play_base: Rect2 = layout_base["play"]
	var size_base := Capsules.size(layout_base)
	var speed_base := Capsules.speed(layout_base)
	var paddle := ArenaLayout.paddle_rect(layout_base, play_base.get_center().x)

	var above := Vector2(paddle.get_center().x, paddle.position.y - 20.0)
	var caught := Capsules.step([Capsules.make(0, PowerUps.WIDE, above)], 1.0, play_base, paddle, speed_base, size_base)
	_eq(int(caught["caught"].size()), 1, "capsula que cruza a raquete e apanhada")
	_eq(str(caught["caught"][0]), PowerUps.WIDE, "o item apanhado e o da capsula")
	_eq(int(caught["capsules"].size()), 0, "capsula apanhada sai da lista")

	# A REGRESSAO QUE IMPORTA: com dt grande a capsula anda mais que a propria
	# altura num passo so. Um teste de intersecao simples deixaria passar direto.
	var far := Vector2(paddle.get_center().x, paddle.position.y - 140.0)
	var tunnel := Capsules.step([Capsules.make(0, PowerUps.SLOW, far)], 0.5, play_base, paddle, 400.0, size_base)
	_eq(int(tunnel["caught"].size()), 1, "capsula rapida nao atravessa a raquete (dt = 0.5s)")

	# Fora do alcance horizontal: nao apanha.
	var aside := Vector2(paddle.position.x - 60.0, paddle.position.y - 20.0)
	var missed_x := Capsules.step([Capsules.make(0, PowerUps.WIDE, aside)], 1.0, play_base, paddle, speed_base, size_base)
	_eq(int(missed_x["caught"].size()), 0, "capsula longe da raquete nao e apanhada")

	# Abaixo do campo: perdida.
	var below := Vector2(paddle.position.x - 60.0, play_base.end.y - 2.0)
	var missed := Capsules.step([Capsules.make(0, PowerUps.WIDE, below)], 1.0, play_base, paddle, speed_base, size_base)
	_eq(int(missed["missed"].size()), 1, "capsula que passa do campo e perdida")
	_eq(int(missed["capsules"].size()), 0, "capsula perdida sai da lista")

	# Uma capsula caindo no meio do campo continua caindo, sem sumir nem duplicar.
	var mid := Vector2(play_base.get_center().x, play_base.position.y + 40.0)
	var falling := Capsules.step([Capsules.make(0, PowerUps.WIDE, mid)], 1.0 / 60.0, play_base, paddle, speed_base, size_base)
	_eq(int(falling["capsules"].size()), 1, "capsula no meio do campo continua caindo")
	var moved: Vector2 = falling["capsules"][0]["pos"]
	_check(moved.y > mid.y, "a capsula desce")
	_approx(moved.x, mid.x, EPS, "a capsula nao deriva de lado")

	# --- Remapeamento ao girar a tela ---
	var layout_portrait := ArenaLayout.compute(Vector2(640, 1385))
	var play_portrait: Rect2 = layout_portrait["play"]
	var to_remap := [
		Capsules.make(0, PowerUps.WIDE, play_base.position + play_base.size * 0.25),
		Capsules.make(1, PowerUps.SLOW, play_base.get_center()),
		Capsules.make(2, PowerUps.FAST, play_base.position + play_base.size * 0.75),
	]
	var remapped := Capsules.remap(to_remap, play_base, play_portrait)
	_eq(int(remapped.size()), 3, "remapear nao perde capsula")
	for capsule in remapped:
		var pos: Vector2 = capsule["pos"]
		_check(play_portrait.grow(1.0).has_point(pos),
			"capsula remapeada continua dentro do campo novo (%s)" % pos)


# ============================================================================
#  SpecialBricks
# ============================================================================

func _test_special_bricks() -> void:
	_begin("SpecialBricks")

	var cases := {
		"paisagem": Vector2(640, 360),
		"retrato": Vector2(640, 1385),
		"ultrawide": Vector2(853, 360),
		"quadrado": Vector2(700, 700),
	}

	# A regra da altura minima vale para TODA geometria que uma fase pode declarar,
	# nao so para a parede classica: uma fase de 10 fileiras deixa menos campo
	# aberto abaixo do muro, e a faixa de surgimento tem que encolher junto.
	for label in cases:
		for rows in range(ArenaLayout.MIN_ROWS, ArenaLayout.MAX_ROWS + 1):
			var layout := ArenaLayout.compute(cases[label], ArenaLayout.DEFAULT_COLS, rows)
			var speed := Capsules.speed(layout)
			var max_row := SpecialBricks.max_spawn_row(layout, speed)
			var paddle_y := float(layout["paddle_y"])
			var tag := "%s %d linhas" % [label, rows]

			_check(max_row >= rows - 1,
				"%s: a parede original e sempre elegivel (row %d)" % [tag, max_row])
			_check(max_row <= rows - 1 + SpecialBricks.EXTRA_ROWS,
				"%s: o surgimento nao desce indefinidamente (row %d)" % [tag, max_row])

			# A REGRA QUE O USUARIO PEDIU: da fileira mais baixa possivel, a capsula
			# ainda leva pelo menos MIN_REACTION_SECONDS ate a raquete.
			var bottom := ArenaLayout.brick_rect(layout, 0, max_row).end.y
			var reaction := (paddle_y - bottom) / speed
			_check(reaction >= SpecialBricks.MIN_REACTION_SECONDS - EPS,
				"%s: da fileira %d sobram %.2fs de reacao" % [tag, max_row, reaction])

			# E o limite e JUSTO, nao folgado: a fileira seguinte ou violaria o tempo
			# de reacao, ou ja esta abaixo do teto de fileiras extras.
			var next_row := max_row + 1
			var next_bottom := ArenaLayout.brick_rect(layout, 0, next_row).end.y
			var next_reaction := (paddle_y - next_bottom) / speed
			_check(next_reaction < SpecialBricks.MIN_REACTION_SECONDS or next_row > rows - 1 + SpecialBricks.EXTRA_ROWS,
				"%s: a fileira %d ja seria apertada demais (%.2fs) ou passa do teto" % [tag, next_row, next_reaction])

			# E O QUE JUSTIFICA ArenaLayout.MAX_ROWS: com a parede cheia ainda tem
			# que sobrar celula livre para um bloco surgir. Sem esta folga o sorteio
			# nunca acharia lugar e o power-up raro sumiria da fase.
			_check(max_row >= rows,
				"%s: sobra fileira livre abaixo da parede cheia (max_row %d)" % [tag, max_row])

	# O teto de MAX_ROWS e DERIVADO, nao chutado: uma fileira a mais ja nao deixaria
	# campo aberto abaixo do muro em paisagem, que e o formato mais apertado.
	var over := ArenaLayout.compute(Vector2(640, 360), ArenaLayout.DEFAULT_COLS, ArenaLayout.MAX_ROWS + 2)
	var over_max_row := SpecialBricks.max_spawn_row(over, Capsules.speed(over))
	_check(over_max_row < ArenaLayout.MAX_ROWS + 2,
		"%d fileiras ja sufocariam a faixa de surgimento (por isso MAX_ROWS == %d)" % [
			ArenaLayout.MAX_ROWS + 2, ArenaLayout.MAX_ROWS])

	# --- Celulas livres ---
	var layout_base := ArenaLayout.compute(Vector2(640, 360))
	var bricks := LevelBuilder.build(1)
	for brick in bricks:
		brick["alive"] = true

	var wall_cols := LevelBuilder.cols(1)
	var wall_rows := LevelBuilder.rows(1)
	var max_row_base := SpecialBricks.max_spawn_row(layout_base, Capsules.speed(layout_base))
	var free := SpecialBricks.free_cells(bricks, max_row_base, wall_cols)

	# A parede da fase 1 e cheia, entao so sobram as fileiras abaixo dela.
	var expected := (max_row_base + 1 - wall_rows) * wall_cols
	_eq(free.size(), expected, "com a parede cheia so as fileiras abaixo estao livres")
	for cell in free:
		_check(cell.y >= wall_rows, "celula livre esta abaixo da parede cheia")
		_check(cell.y <= max_row_base, "celula livre respeita a altura minima")
		_check(cell.x < wall_cols, "celula livre respeita a largura da fase")

	# Ao destruir um bloco, a celula dele fica disponivel.
	bricks[0]["alive"] = false
	var free_after := SpecialBricks.free_cells(bricks, max_row_base, wall_cols)
	_eq(free_after.size(), free.size() + 1, "bloco destruido libera a celula")

	# free_cells respeita a largura da fase, e nao uma constante global: numa fase
	# de 7 colunas o sorteio nao pode oferecer a coluna 9.
	var narrow := SpecialBricks.free_cells([], 2, 7)
	_eq(narrow.size(), 21, "7 colunas x 3 fileiras dao 21 celulas livres")
	for cell in narrow:
		_check(cell.x < 7, "celula livre nunca passa da largura pedida")

	# --- Celula segura ---
	var cell_rect := ArenaLayout.brick_rect(layout_base, 5, 9)
	var radius := float(layout_base["ball_radius"])

	_check(not SpecialBricks.is_cell_safe(cell_rect, cell_rect.get_center(), Vector2.ZERO, radius, 0.5),
		"celula com a bola dentro nao e segura")

	var below_cell := cell_rect.get_center() + Vector2(0.0, 200.0)
	var towards := Vector2(0.0, -400.0)
	_check(not SpecialBricks.is_cell_safe(cell_rect, below_cell, towards, radius, SpecialBricks.BALL_LOOKAHEAD),
		"celula na trajetoria da bola nao e segura")
	_check(SpecialBricks.is_cell_safe(cell_rect, below_cell, -towards, radius, SpecialBricks.BALL_LOOKAHEAD),
		"a mesma celula e segura com a bola indo embora")

	# --- pick_cell ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	# Uma bola bem longe do campo: nenhuma celula fica bloqueada por ela.
	var far_balls := [{"pos": Vector2(-5000.0, -5000.0), "vel": Vector2.ZERO}]
	var picked := SpecialBricks.pick_cell(rng, free, layout_base, far_balls, radius)
	_check(picked.x >= 0, "com celulas livres e bola longe, sorteia alguma celula")
	_check(free.has(picked), "a celula sorteada esta entre as livres")

	var none := SpecialBricks.pick_cell(rng, [], layout_base, far_balls, radius)
	_eq(none, Vector2i(-1, -1), "sem celula livre devolve (-1,-1)")

	# Determinismo do surgimento.
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 7
	rng_b.seed = 7
	for i in 20:
		_approx(SpecialBricks.next_interval(rng_a), SpecialBricks.next_interval(rng_b), EPS,
			"intervalo %d reproduzivel com a mesma semente" % i)
		_eq(SpecialBricks.pick_cell(rng_a, free, layout_base, far_balls, radius),
			SpecialBricks.pick_cell(rng_b, free, layout_base, far_balls, radius),
			"celula %d reproduzivel com a mesma semente" % i)

	var interval := SpecialBricks.next_interval(rng_a)
	_check(interval >= SpecialBricks.ROLL_INTERVAL_MIN and interval <= SpecialBricks.ROLL_INTERVAL_MAX,
		"intervalo de sorteio fica na faixa (%.1fs)" % interval)

	# --- make_brick ---
	# Chave faltando aqui e crash em _draw_brick, entao a forma e verificada
	# explicitamente contra tudo que a Arena le de um bloco.
	var spawned := SpecialBricks.make_brick(88, Vector2i(3, 9), layout_base)
	for key in ["id", "col", "row", "hp", "max_hp", "type", "color", "points", "alive", "flash", "kind", "rect"]:
		_check(spawned.has(key), "bloco surgido tem a chave '%s'" % key)

	_eq(int(spawned["id"]), 88, "id do bloco surgido e o indice pedido")
	_eq(int(spawned["type"]), LevelBuilder.TYPE_SPECIAL_SPAWNED, "tipo do bloco surgido")
	_eq(int(spawned["hp"]), int(spawned["max_hp"]), "bloco surgido comeca inteiro")
	_check(int(spawned["hp"]) > LevelBuilder.SPECIAL_HP, "bloco surgido aguenta mais que o fixo")
	_check(int(spawned["points"]) > LevelBuilder.SPECIAL_POINTS, "bloco surgido vale mais que o fixo")
	_check(bool(spawned["alive"]), "bloco surgido nasce vivo")
	_eq(int(spawned["kind"]), BallPhysics.KIND_BRICK, "bloco surgido colide como bloco")
	_eq(Rect2(spawned["rect"]), ArenaLayout.brick_rect(layout_base, 3, 9),
		"retangulo do bloco surgido vem da mesma geometria da grade")


# ============================================================================
#  Espelho do schema: cliente e servidor nao podem divergir
# ============================================================================

func _test_schema_mirror() -> void:
	_begin("Espelho do schema")

	var sql := FileAccess.get_file_as_string("res://supabase/schema.sql")
	_check(not sql.is_empty(), "supabase/schema.sql e legivel")
	if sql.is_empty():
		return

	# O CHECK de plausibilidade e a unica trava que roda no servidor. Se estes
	# numeros divergirem de ScoreRules, o jogo passa a produzir placares que o
	# banco recusa - e o jogador so descobre no fim da partida.
	var plausible := "score <= %d * greatest(duration_ms / 1000, 1) + %d" % [
		ScoreRules.PLAUSIBLE_POINTS_PER_SECOND, ScoreRules.PLAUSIBLE_BASE
	]
	_check(sql.contains(plausible),
		"CHECK scores_plausible espelha ScoreRules (esperado \"%s\")" % plausible)

	var range_check := "score between 0 and %d" % ScoreRules.MAX_VALID_SCORE
	_check(sql.contains(range_check),
		"CHECK scores_score_range espelha MAX_VALID_SCORE (esperado \"%s\")" % range_check)

	# A migracao precisa levar o banco existente ao mesmo lugar do schema novo.
	var migration := FileAccess.get_file_as_string("res://supabase/migrations/001_teto_plausibilidade.sql")
	_check(not migration.is_empty(), "a migracao do teto e legivel")
	_check(migration.contains(plausible), "a migracao chega ao mesmo teto do schema")

	# E um placar realista continua passando com folga.
	var realistic_seconds := 200
	_check(ScoreRules.plausible_ceiling(realistic_seconds) > 40000,
		"uma partida de %ds aceita placares muito acima do que o jogo produz" % realistic_seconds)

	# --- Versao exibida no menu ---
	# Mesma defesa contra deriva: a versao mostrada no rodape do menu vem de
	# project.godot, e precisa bater com a entrada mais recente do CHANGELOG.
	var version := TextUtil.version()
	_check(not version.is_empty(), "o jogo declara uma versao em project.godot")
	_check(version.begins_with("V"), "a versao exibida comeca com V (%s)" % version)

	for i in version.length():
		_check(PixelFont.has_glyph(version[i]),
			"glifo existe para '%s' (usado na versao)" % version[i])

	var changelog := FileAccess.get_file_as_string("res://CHANGELOG.md")
	_check(not changelog.is_empty(), "CHANGELOG.md e legivel")
	if not changelog.is_empty():
		# A primeira linha "## vX.Y.Z" e a versao corrente.
		var latest := ""
		for line in changelog.split("\n"):
			if str(line).begins_with("## v"):
				latest = str(line).substr(3).split(" ")[0].strip_edges()
				break
		_eq(version, latest.to_upper(),
			"a versao do menu bate com a entrada mais recente do CHANGELOG")

	var readme := FileAccess.get_file_as_string("res://README.md")
	if not readme.is_empty():
		_check(readme.contains("**%s**" % version.substr(1)) or readme.contains(version.substr(1)),
			"o README cita a versao corrente (%s)" % version.substr(1))


# ============================================================================
#  Soak test: partida completa simulada
# ============================================================================

func _test_gameplay_soak() -> void:
	_begin("Soak (partida completa)")

	for label in ["paisagem", "retrato"]:
		var viewport := Vector2(640, 360) if label == "paisagem" else Vector2(640, 1385)

		var runs := {
			"off": _simulate_run(viewport, 400.0, 20260730, "off"),
			"catch": _simulate_run(viewport, 400.0, 20260730, "catch"),
			"dodge": _simulate_run(viewport, 400.0, 20260730, "dodge"),
		}

		for policy in runs:
			var run: Dictionary = runs[policy]
			var tag := "%s/%s" % [label, policy]

			_eq(int(run["alive"]), 0, "%s: parede inteira foi destruida" % tag)
			_eq(int(run["lost"]), 0, "%s: raquete perfeita nunca perde a bola" % tag)
			_check(bool(run["in_bounds"]), "%s: bola e capsulas nunca escaparam do campo" % tag)
			_check(float(run["elapsed"]) < 400.0, "%s: fase concluida dentro do orcamento (%.1fs)" % [tag, run["elapsed"]])
			_check(int(run["paddle_hits"]) > 0, "%s: a bola voltou a raquete" % tag)
			_check(int(run["score"]) > LevelBuilder.max_base_score(1), "%s: pontuacao supera a base" % tag)
			_check(ScoreRules.is_valid_score(int(run["score"])), "%s: pontuacao e enviavel" % tag)

			# O CHECK de plausibilidade do servidor, lido de ScoreRules em vez de
			# repetido a mao - o teste do espelho garante que os dois batem.
			var duration_seconds := maxi(int(float(run["elapsed"])), 1)
			var ceiling := ScoreRules.plausible_ceiling(duration_seconds)
			_check(int(run["score"]) <= ceiling,
				"%s: %d pontos em %ds passa no CHECK do schema (teto %d)" % [
					tag, int(run["score"]), duration_seconds, ceiling
				])

			# Guarda de folga: se o teto virar a restricao de balanceamento, o
			# jogo passa a ser limitado pela trava antifraude sem ninguem notar.
			var rate := float(run["score"]) / maxf(float(run["elapsed"]), 1.0)
			_check(rate < float(ScoreRules.PLAUSIBLE_POINTS_PER_SECOND) * 0.25,
				"%s: %.0f pts/s fica bem abaixo do teto de %d" % [
					tag, rate, ScoreRules.PLAUSIBLE_POINTS_PER_SECOND
				])

		# Os power-ups precisam mesmo acontecer, ou os testes acima nao provam nada.
		var catch_run: Dictionary = runs["catch"]
		var off_run: Dictionary = runs["off"]
		_check(int(catch_run["specials"]) > 0, "%s: blocos especiais surgiram durante a partida" % label)
		_check(int(catch_run["caught"]) > 0, "%s: a raquete apanhou capsulas" % label)
		_check(int(catch_run["caught"]) > int(runs["dodge"]["caught"]),
			"%s: apanhar de proposito rende mais capsulas que desviar" % label)
		_eq(int(off_run["caught"]), 0, "%s: a linha de base nao apanha nada" % label)
		_check(int(catch_run["score"]) != int(off_run["score"]),
			"%s: os power-ups mudam o placar" % label)

		# Determinismo: mesma semente, mesma partida.
		var repeat := _simulate_run(viewport, 400.0, 20260730, "catch")
		_eq(int(repeat["score"]), int(catch_run["score"]), "%s: mesma semente, mesmo placar" % label)
		_eq(int(repeat["caught"]), int(catch_run["caught"]), "%s: mesma semente, mesmas capsulas" % label)
		_eq(int(repeat["specials"]), int(catch_run["specials"]), "%s: mesma semente, mesmos surgimentos" % label)

		# ------------------------------------------------------------------
		# A PROVA DE QUE AS ALUCINACOES NAO SAO TRAPACA
		# ------------------------------------------------------------------
		# Forcando cada efeito do canal visual por uma partida inteira, a FISICA
		# tem que sair identica a da partida sem ele: mesmo tempo, mesmas
		# rebatidas, mesmo combo, mesma parede. Se um dia alguem ler um efeito
		# visual dentro de _simulate_balls ou de _update_paddle, este teste cai.
		#
		# A pontuacao NAO entra na comparacao de proposito: o risco multiplica
		# pontos, e e assim que a alucinacao paga o preco de atrapalhar.
		var clean := _simulate_run(viewport, 400.0, 20260730, "off")
		for id_variant in PowerUps.all_ids():
			var id := str(id_variant)
			if not PowerUps.is_visual(id):
				continue
			var hallucinated := _simulate_run(viewport, 400.0, 20260730, "off", id)
			var tag := "%s/%s" % [label, id]
			_approx(float(hallucinated["elapsed"]), float(clean["elapsed"]), EPS,
				"%s: a alucinacao nao muda a duracao da partida" % tag)
			_eq(int(hallucinated["paddle_hits"]), int(clean["paddle_hits"]),
				"%s: a alucinacao nao muda as rebatidas" % tag)
			_eq(int(hallucinated["max_combo"]), int(clean["max_combo"]),
				"%s: a alucinacao nao muda o combo" % tag)
			_eq(int(hallucinated["alive"]), int(clean["alive"]),
				"%s: a alucinacao nao muda a parede" % tag)
			_eq(int(hallucinated["lost"]), int(clean["lost"]),
				"%s: a alucinacao nao faz perder bola" % tag)

		# Controle: um efeito do canal de JOGO precisa mudar a fisica, ou o teste
		# acima passaria mesmo com o sistema inteiro quebrado.
		var slowed := _simulate_run(viewport, 400.0, 20260730, "off", PowerUps.SLOW)
		_check(absf(float(slowed["elapsed"]) - float(clean["elapsed"])) > 1.0,
			"%s: CALMA (canal de jogo) muda a partida de verdade" % label)

		# CISAO precisa cair de fato em alguma partida, ou o refactor de multiplas
		# bolas fica sem cobertura no soak.
		#
		# Varre algumas sementes em vez de fixar uma: qualquer ajuste de peso no
		# sorteio muda a sequencia do rng, e uma semente cravada aqui ja quebrou
		# tres vezes por causa de rebalanceamento, sem nada de errado no codigo.
		var multi := {}
		for candidate in [512, 7, 123, 17, 2026]:
			multi = _simulate_run(viewport, 400.0, candidate, "catch")
			if int(multi["max_balls"]) > 1:
				break
		_check(int(multi["max_balls"]) > 1,
			"%s: CISAO colocou %d bolas em jogo" % [label, int(multi["max_balls"])])
		_check(int(multi["max_balls"]) <= PowerUps.MAX_BALLS,
			"%s: a multibola respeita o teto de %d" % [label, PowerUps.MAX_BALLS])
		_eq(int(multi["alive"]), 0, "%s: a parede cai tambem com varias bolas" % label)
		_check(bool(multi["in_bounds"]), "%s: nenhuma bola escapou do campo com CISAO" % label)

		for policy in runs:
			var run: Dictionary = runs[policy]
			print("    %s/%s: %d pontos, %.1fs, %d rebatidas, combo maximo %d, %d capsulas, %d surgimentos" % [
				label, policy, int(run["score"]), float(run["elapsed"]),
				int(run["paddle_hits"]), int(run["max_combo"]),
				int(run["caught"]), int(run["specials"])
			])
		print("    %s/cisao: %d bolas simultaneas, %d capsulas" % [
			label, int(multi["max_balls"]), int(multi["caught"])
		])

	# --- TODA FASE DA ROTACAO E LIMPAVEL ---------------------------------------
	#
	# Esta e a razao de _simulate_run ter ganhado o parametro de fase. Um mapa
	# bonito no editor pode ser inlimpavel na pratica: um bloco encurralado onde a
	# bola nunca chega trava a fase para sempre, e a partida so acabaria quando o
	# jogador desistisse. Aqui a raquete e perfeita, entao "nao limpou em 400s"
	# significa geometria ruim, nao falta de pericia.
	#
	# Roda nos dois formatos porque a altura do bloco muda com o campo, e uma fase
	# de 10 fileiras se comporta de forma diferente em retrato e em paisagem.
	for level in range(1, LevelBuilder.level_count() + 1):
		var dims := LevelBuilder.dimensions(level)
		for label in ["paisagem", "retrato"]:
			var viewport := Vector2(640, 360) if label == "paisagem" else Vector2(640, 1385)
			var tag := "fase %d (%dx%d) %s" % [level, dims.x, dims.y, label]
			var run := _simulate_run(viewport, 400.0, 20260730, "catch", "", level)

			_eq(int(run["alive"]), 0, "%s: parede inteira foi destruida" % tag)
			_eq(int(run["lost"]), 0, "%s: raquete perfeita nunca perde a bola" % tag)
			_check(bool(run["in_bounds"]), "%s: bola e capsulas nunca escaparam do campo" % tag)
			_check(float(run["elapsed"]) < 400.0,
				"%s: fase concluida dentro do orcamento (%.1fs)" % [tag, run["elapsed"]])
			_check(int(run["score"]) > LevelBuilder.max_base_score(level),
				"%s: pontuacao supera a base da fase" % tag)

			var seconds := maxi(int(float(run["elapsed"])), 1)
			_check(int(run["score"]) <= ScoreRules.plausible_ceiling(seconds),
				"%s: %d pontos em %ds passa no CHECK do schema" % [tag, int(run["score"]), seconds])

			print("    fase %d %dx%d/%s: %d pontos, %.1fs, %d blocos" % [
				level, dims.x, dims.y, label, int(run["score"]), float(run["elapsed"]),
				LevelBuilder.build(level).size()
			])


## Simula uma partida usando exatamente a mesma matematica da Arena, com uma
## raquete automatica que persegue a bola. Sem nos, sem render, sem SceneTree.
##
## As chamadas de power-up aqui sao IDENTICAS as da Arena - PowerUps.tick,
## paddle_width_scale, ball_speed_scale, Capsules.step, SpecialBricks.pick_cell.
## E isso que faz deste soak uma verificacao de verdade, e nao uma segunda
## implementacao que pode concordar consigo mesma enquanto o jogo diverge.
##
## policy:
##   "off"   sem power-ups; reproduz a linha de base da v1.1.0
##   "catch" a raquete desvia para apanhar capsula ao alcance
##   "dodge" a raquete foge das capsulas, sem deixar a bola cair
## forced: id de efeito mantido permanentemente ativo, para provar que uma
##         alucinacao do canal visual nao altera a simulacao em nada.
## level:  fase simulada. Existe desde a v2.3.0, quando cada fase passou a ter a
##         sua geometria: sem isto, so a parede 11x8 teria cobertura de soak e uma
##         fase de 7x10 poderia ser inlimpavel sem ninguem descobrir.
func _simulate_run(viewport: Vector2, max_seconds: float, seed_value: int = 0,
		policy: String = "off", forced: String = "", level: int = 1) -> Dictionary:
	var dims := LevelBuilder.dimensions(level)
	var layout := ArenaLayout.compute(viewport, dims.x, dims.y)
	var play: Rect2 = layout["play"]
	var radius := float(layout["ball_radius"])
	var speed_scale := float(layout["speed_scale"])

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var bricks := LevelBuilder.build(level)
	for brick in bricks:
		brick["alive"] = true
		brick["kind"] = BallPhysics.KIND_BRICK
		brick["rect"] = ArenaLayout.brick_rect(layout, int(brick["col"]), int(brick["row"]))

	var alive := bricks.size()
	var total := bricks.size()
	var destroyed := 0
	var score := 0
	var combo := 0
	var max_combo := 0
	var paddle_hits := 0
	var lost := 0
	var in_bounds := true

	var powered := policy != "off"
	var effects: Dictionary = {}
	var capsules: Array = []
	var capsule_serial := 0
	var caught := 0
	var specials := 0
	var special_alive := 0
	var spawn_timer := SpecialBricks.next_interval(rng)
	var pending: Dictionary = {}

	var capsule_speed := Capsules.speed(layout)
	var capsule_size := Capsules.size(layout)

	var paddle_x := play.get_center().x
	var launch_speed := ScoreRules.ball_speed_for_level(level) * speed_scale
	var balls: Array = [{
		"pos": ArenaLayout.docked_ball_position(layout, paddle_x),
		"vel": BallPhysics.launch_velocity(launch_speed, 0.0),
		"phase": 0.0,
	}]
	var max_balls := 1

	var paddle_target := {"rect": Rect2(), "id": "paddle", "kind": BallPhysics.KIND_PADDLE, "vx": 0.0}
	var targets: Array = []

	var dt := 1.0 / 60.0
	var elapsed := 0.0
	var paddle_max_speed := 900.0 * speed_scale

	while elapsed < max_seconds and alive > 0:
		effects = PowerUps.tick(effects, dt)["active"]
		if not forced.is_empty():
			effects[forced] = 999.0
		var width_scale := PowerUps.paddle_width_scale(effects)
		var risk := PowerUps.risk_level(effects)
		var curving := effects.has(PowerUps.CURVE)

		# A raquete persegue a bola MAIS BAIXA: com CISAO ativa, e a que esta
		# prestes a cair que decide se a jogada sobrevive.
		var lowest := _lowest_ball(balls)
		var lowest_pos: Vector2 = lowest["pos"]
		var lowest_vel: Vector2 = lowest["vel"]

		# A bola SEMPRE tem prioridade quando esta perto de chegar: sem isso,
		# perseguir capsula custaria a vida e o teste passaria a medir a politica
		# em vez do sistema.
		var goal := lowest_pos.x
		if powered and not capsules.is_empty():
			var paddle_line := float(layout["paddle_y"])
			var ball_eta := 999.0
			if lowest_vel.y > 1.0:
				ball_eta = (paddle_line - lowest_pos.y) / lowest_vel.y
			if ball_eta > 0.8:
				var nearest := _nearest_capsule(capsules, paddle_line, capsule_speed)
				if not nearest.is_empty():
					var cx := float(nearest["x"])
					goal = cx if policy == "catch" else _flee_x(cx, play)

		var previous_x := paddle_x
		var step := paddle_max_speed * dt
		paddle_x = clampf(goal, paddle_x - step, paddle_x + step)
		var rect := ArenaLayout.paddle_rect(layout, paddle_x, width_scale)
		paddle_x = rect.get_center().x
		paddle_target["rect"] = rect
		paddle_target["vx"] = (paddle_x - previous_x) / dt

		var speed := ScoreRules.ball_speed_for_level(level) * speed_scale \
			* ScoreRules.ball_speed_multiplier(destroyed, total) \
			* PowerUps.ball_speed_scale(effects)

		var survivors: Array = []
		for ball in balls:
			var vel: Vector2 = ball["vel"]
			vel = vel.normalized() * speed
			if curving:
				ball["phase"] = float(ball["phase"]) + dt
				vel = BallPhysics.enforce_min_vertical(
					vel.rotated(PowerUps.curve_rotation(float(ball["phase"]), dt))
				)

			# Alvos remontados POR BOLA, como na Arena: o mapa "consumed" do
			# BallPhysics vale por chamada, e sem remontar duas bolas cobrariam o
			# mesmo bloco no mesmo quadro.
			targets.clear()
			targets.append(paddle_target)
			for brick in bricks:
				if brick["alive"]:
					targets.append(brick)

			var result := BallPhysics.advance(ball["pos"], vel, radius, dt, play, targets)
			ball["pos"] = result["pos"]
			ball["vel"] = result["vel"]

			for event in result["events"]:
				match str(event["type"]):
					"paddle":
						paddle_hits += 1
						combo = 0
					"brick":
						var brick: Dictionary = bricks[int(event["id"])]
						brick["hp"] = int(brick["hp"]) - 1
						if int(brick["hp"]) > 0:
							score += ScoreRules.chip_points(int(brick["points"]))
						else:
							brick["alive"] = false
							alive -= 1
							destroyed += 1
							combo += 1
							max_combo = maxi(max_combo, combo)
							score += ScoreRules.brick_points(int(brick["points"]), combo, risk)

							var brick_type := int(brick["type"])
							if brick_type == LevelBuilder.TYPE_SPECIAL_SPAWNED:
								special_alive = maxi(special_alive - 1, 0)
							if powered and capsules.size() < Capsules.MAX_ACTIVE:
								var item := PowerUps.roll_drop(rng, brick_type)
								if not item.is_empty():
									capsules.append(Capsules.make(capsule_serial, item, Rect2(brick["rect"]).get_center()))
									capsule_serial += 1

			var ball_pos: Vector2 = ball["pos"]
			if ball_pos.x < play.position.x - radius - 1.0 or ball_pos.x > play.end.x + radius + 1.0 \
					or ball_pos.y < play.position.y - radius - 1.0:
				in_bounds = false

			if not bool(result["lost"]):
				survivors.append(ball)

		balls = survivors
		max_balls = maxi(max_balls, balls.size())

		if powered and not capsules.is_empty():
			var stepped := Capsules.step(capsules, dt, play, rect, capsule_speed, capsule_size)
			capsules = stepped["capsules"]
			for item_variant in stepped["caught"]:
				var item := str(item_variant)
				caught += 1
				score += ScoreRules.capsule_points(PowerUps.tier(item), PowerUps.risk_level(effects))
				if item == PowerUps.BONUS:
					score += int(round(PowerUps.BONUS_POINTS * ScoreRules.risk_multiplier(PowerUps.risk_level(effects))))
				elif item == PowerUps.MULTI:
					var spawned: Array = []
					for ball in balls:
						for extra in PowerUps.split_velocities(ball["vel"], PowerUps.SPLIT_COUNT - 1, PowerUps.SPLIT_SPREAD):
							if balls.size() + spawned.size() < PowerUps.MAX_BALLS:
								spawned.append({"pos": Vector2(ball["pos"]), "vel": extra, "phase": 0.0})
					balls.append_array(spawned)
					max_balls = maxi(max_balls, balls.size())
				effects = PowerUps.apply(effects, item)

			for capsule in capsules:
				var pos: Vector2 = capsule["pos"]
				if not play.grow(capsule_size.y).has_point(pos):
					in_bounds = false

		# Surgimento do bloco especial, com o mesmo aviso previo da Arena.
		if powered:
			if not pending.is_empty():
				pending["timer"] = float(pending["timer"]) - dt
				if float(pending["timer"]) <= 0.0:
					var cell: Vector2i = pending["cell"]
					pending = {}
					var cell_rect := ArenaLayout.brick_rect(layout, cell.x, cell.y)
					if SpecialBricks.is_cell_safe_for_all(cell_rect, balls, radius, SpecialBricks.BALL_LOOKAHEAD):
						bricks.append(SpecialBricks.make_brick(bricks.size(), cell, layout))
						alive += 1
						special_alive += 1
						specials += 1
					else:
						spawn_timer = SpecialBricks.RETRY_SECONDS
			elif special_alive < SpecialBricks.MAX_ALIVE and alive >= SpecialBricks.STOP_WHEN_ALIVE_BELOW:
				spawn_timer -= dt
				if spawn_timer <= 0.0:
					var max_row := SpecialBricks.max_spawn_row(layout, capsule_speed)
					var cells := SpecialBricks.free_cells(bricks, max_row, int(layout["cols"]))
					var cell := SpecialBricks.pick_cell(rng, cells, layout, balls, radius)
					if cell.x < 0:
						spawn_timer = SpecialBricks.RETRY_SECONDS
					else:
						pending = {"cell": cell, "timer": SpecialBricks.TELEGRAPH_SECONDS}
						spawn_timer = SpecialBricks.next_interval(rng)

		# Uma vida so e perdida quando a ULTIMA bola cai.
		if balls.is_empty():
			lost += 1
			paddle_x = play.get_center().x
			balls = [{
				"pos": ArenaLayout.docked_ball_position(layout, paddle_x, width_scale),
				"vel": BallPhysics.launch_velocity(speed, 0.0),
				"phase": 0.0,
			}]
			effects = {}
			capsules = []

		elapsed += dt

	if alive == 0:
		score += ScoreRules.level_clear_bonus(1, ScoreRules.STARTING_LIVES)

	return {
		"alive": alive,
		"lost": lost,
		"score": score,
		"elapsed": elapsed,
		"paddle_hits": paddle_hits,
		"max_combo": max_combo,
		"in_bounds": in_bounds,
		"caught": caught,
		"specials": specials,
		"max_balls": max_balls,
	}


## A bola mais baixa em jogo - a que a raquete automatica persegue.
func _lowest_ball(balls: Array) -> Dictionary:
	var best: Dictionary = {"pos": Vector2.ZERO, "vel": Vector2.ZERO}
	var best_y := -INF
	for ball in balls:
		var pos: Vector2 = ball["pos"]
		if pos.y > best_y:
			best_y = pos.y
			best = ball
	return best


## Capsula mais proxima de chegar a linha da raquete, ou {} se nenhuma esta perto.
func _nearest_capsule(capsules: Array, paddle_line: float, fall_speed: float) -> Dictionary:
	var best := {}
	var best_eta := 1.2
	for capsule in capsules:
		var pos: Vector2 = capsule["pos"]
		if pos.y > paddle_line:
			continue
		var eta := (paddle_line - pos.y) / maxf(fall_speed, 0.001)
		if eta < best_eta:
			best_eta = eta
			best = {"x": pos.x, "eta": eta}
	return best


## Ponto para onde fugir de uma capsula: o lado oposto do campo.
func _flee_x(capsule_x: float, play: Rect2) -> float:
	var center := play.get_center().x
	return play.position.x + 12.0 if capsule_x > center else play.end.x - 12.0


# ============================================================================
#  Micro framework de asserts
# ============================================================================

func _begin(suite: String) -> void:
	_suite = suite
	print("")
	print("  [%s]" % suite)


func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s :: %s" % [_suite, description])
		print("    x %s" % description)


func _eq(actual: Variant, expected: Variant, description: String) -> void:
	var ok: bool = actual == expected
	if not ok and (actual is float or expected is float):
		ok = is_equal_approx(float(actual), float(expected))
	if ok:
		_passed += 1
	else:
		_failed += 1
		var message := "%s (obtido %s, esperado %s)" % [description, actual, expected]
		_failures.append("%s :: %s" % [_suite, message])
		print("    x %s" % message)


func _approx(actual: float, expected: float, tolerance: float, description: String) -> void:
	_check(absf(actual - expected) <= tolerance,
		"%s (obtido %s, esperado ~%s)" % [description, actual, expected])
