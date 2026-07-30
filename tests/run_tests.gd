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
		var last_brick := ArenaLayout.brick_rect(layout, ArenaLayout.COLS - 1, ArenaLayout.ROWS - 1)
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
		_eq(brick_size.x, ArenaLayout.BRICK_WIDTH, "%s: largura do bloco e fixa" % label)
		_check(brick_size.y >= ArenaLayout.BRICK_MIN_HEIGHT and brick_size.y <= ArenaLayout.BRICK_MAX_HEIGHT,
			"%s: altura do bloco dentro dos limites (%s)" % [label, brick_size.y])
		_eq(brick_size.y, floorf(brick_size.y), "%s: altura do bloco e inteira" % label)
		_approx(grid.size.y, ArenaLayout.ROWS * brick_size.y + (ArenaLayout.ROWS - 1) * ArenaLayout.BRICK_GAP,
			EPS, "%s: altura da grade bate com as linhas" % label)

		# O muro nunca deve dominar o campo nem sumir dentro dele.
		var wall_share := grid.size.y / play.size.y
		_check(wall_share > 0.15 and wall_share < 0.55,
			"%s: muro ocupa fracao razoavel do campo (%.2f)" % [label, wall_share])

		# Espaco de reacao entre o muro e a raquete.
		_check(float(layout["paddle_y"]) - grid.end.y > 80.0,
			"%s: sobra espaco de reacao abaixo do muro" % label)

	# Larguras de brick tem que ser exatas, ou a grade nao fecha em pixels.
	var layout_base := ArenaLayout.compute(Vector2(640, 360))
	var brick_size: Vector2 = layout_base["brick_size"]
	_eq(brick_size.x, ArenaLayout.BRICK_WIDTH, "brick_size.x == BRICK_WIDTH (grade fecha exata)")

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
	for index in bricks.size():
		var brick: Dictionary = bricks[index]
		_eq(int(brick["id"]), index, "id do bloco %d bate com o indice (lookup direto na Arena)" % index)

		var cell := Vector2i(int(brick["col"]), int(brick["row"]))
		_check(not seen_cells.has(cell), "celula %s aparece uma unica vez" % cell)
		seen_cells[cell] = true

		_check(int(brick["col"]) >= 0 and int(brick["col"]) < ArenaLayout.COLS, "coluna valida")
		_check(int(brick["row"]) >= 0 and int(brick["row"]) < ArenaLayout.ROWS, "linha valida")
		_check(int(brick["hp"]) >= 1 and int(brick["hp"]) == int(brick["max_hp"]), "hp inicial == max_hp")
		_check(int(brick["points"]) > 0, "bloco vale pontos")

		match int(brick["type"]):
			LevelBuilder.TYPE_TJ_BLUE:
				hard_blue += 1
				_eq(int(brick["hp"]), 2, "bloco azul TJ tem 2 hp")
			LevelBuilder.TYPE_TJ_GOLD:
				hard_gold += 1
				_eq(int(brick["hp"]), 2, "bloco dourado TJ tem 2 hp")

	_eq(hard_blue, 10, "easter egg: 10 blocos azuis desenham T e J")
	_eq(hard_gold, 2, "easter egg: 2 blocos dourados")

	# As letras precisam estar onde o mapa promete (linha 2, colunas 2-4 = topo do T).
	for col in [2, 3, 4]:
		_check(_brick_type_at(bricks, col, 2) == LevelBuilder.TYPE_TJ_BLUE,
			"barra do T em (%d,2)" % col)
	_check(_brick_type_at(bricks, 3, 4) == LevelBuilder.TYPE_TJ_BLUE, "haste do T em (3,4)")
	_check(_brick_type_at(bricks, 8, 3) == LevelBuilder.TYPE_TJ_BLUE, "haste do J em (8,3)")
	_check(_brick_type_at(bricks, 6, 4) == LevelBuilder.TYPE_TJ_BLUE, "base do J em (6,4)")

	# Fileiras de cima valem mais que as de baixo.
	for row in range(ArenaLayout.ROWS - 1):
		_check(LevelBuilder.ROW_POINTS[row] > LevelBuilder.ROW_POINTS[row + 1],
			"fileira %d vale mais que a %d" % [row, row + 1])

	_eq(LevelBuilder.max_base_score(1), 5000, "teto base da fase 1 == 5000 pontos")

	# Niveis acima do ultimo mapa repetem o ultimo, sem estourar.
	var high := LevelBuilder.build(99)
	_eq(high.size(), bricks.size(), "fase 99 reaproveita o ultimo mapa")


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

	# Velocidade sobe com a fase e satura.
	var previous_speed := 0.0
	for level in range(1, 40):
		var speed := ScoreRules.ball_speed_for_level(level)
		_check(speed >= previous_speed, "velocidade nao regride na fase %d" % level)
		_check(speed <= 340.0 + EPS, "velocidade satura em 340 px/s")
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
		"PAUSE", "P PARA CONTINUAR", "TOQUE PARA CONTINUAR",
		"FIM DE JOGO", "NOVO RECORDE PESSOAL", "JOGAR DE NOVO", "MENU", "ENTER", "ESC",
		"BOLA PERDIDA", "VIDA RESTANTE", "VIDAS RESTANTES", "FASE 1", "BONUS 1000",
		"CLIQUE OU ESPACO PARA LANCAR", "TOQUE PARA LANCAR",
		"MOUSE OU A D MOVE * CLIQUE LANCA", "P PAUSA DISCRETO * M LIGA O SOM",
		"ARRASTE MOVE * TOQUE LANCA", "TOQUE NO ICONE PAUSA * M LIGA O SOM",
		"PONTUACAO ENVIADA", "MUITOS ENVIOS, AGUARDE", "SEM CONEXAO",
		"LEADERBOARD NAO CONFIGURADO", "PONTUACAO INVALIDA", "RESPOSTA INVALIDA",
		"NICK: DE 2 A 10 CARACTERES", "PONTUACAO ZERO NAO E ENVIADA",
		"ENVIANDO PONTUACAO...", "ANONIMO", "ERRO 500 AO ENVIAR", "FALHA DE REDE (1)",
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
#  Soak test: partida completa simulada
# ============================================================================

func _test_gameplay_soak() -> void:
	_begin("Soak (partida completa)")

	for label in ["paisagem", "retrato"]:
		var viewport := Vector2(640, 360) if label == "paisagem" else Vector2(640, 1385)
		var run := _simulate_run(viewport, 400.0)

		_eq(int(run["alive"]), 0, "%s: parede inteira foi destruida" % label)
		_eq(int(run["lost"]), 0, "%s: raquete perfeita nunca perde a bola" % label)
		_check(bool(run["in_bounds"]), "%s: bola nunca escapou do campo" % label)
		_check(float(run["elapsed"]) < 400.0, "%s: fase concluida dentro do orcamento (%.1fs)" % [label, run["elapsed"]])
		_check(int(run["paddle_hits"]) > 0, "%s: a bola voltou a raquete" % label)
		_check(int(run["score"]) > LevelBuilder.max_base_score(1), "%s: pontuacao supera a base (combo + bonus)" % label)
		_check(ScoreRules.is_valid_score(int(run["score"])), "%s: pontuacao e enviavel" % label)

		# A partida simulada precisa passar no CHECK de plausibilidade do schema:
		#   score <= 1200 * greatest(duration_ms/1000, 1) + 5000
		var duration_seconds := maxi(int(float(run["elapsed"])), 1)
		var ceiling := 1200 * duration_seconds + 5000
		_check(int(run["score"]) <= ceiling,
			"%s: %d pontos em %ds passa no CHECK do schema (teto %d)" % [
				label, int(run["score"]), duration_seconds, ceiling
			])

		print("    %s: %d pontos, %.1fs, %d rebatidas, combo maximo %d" % [
			label, int(run["score"]), float(run["elapsed"]), int(run["paddle_hits"]), int(run["max_combo"])
		])


## Simula uma partida usando exatamente a mesma matematica da Arena, com uma
## raquete automatica que persegue a bola. Sem nos, sem render, sem SceneTree.
func _simulate_run(viewport: Vector2, max_seconds: float) -> Dictionary:
	var layout := ArenaLayout.compute(viewport)
	var play: Rect2 = layout["play"]
	var radius := float(layout["ball_radius"])
	var speed_scale := float(layout["speed_scale"])

	var bricks := LevelBuilder.build(1)
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

	var paddle_x := play.get_center().x
	var ball := ArenaLayout.docked_ball_position(layout, paddle_x)
	var vel := BallPhysics.launch_velocity(ScoreRules.ball_speed_for_level(1) * speed_scale, 0.0)

	var paddle_target := {"rect": Rect2(), "id": "paddle", "kind": BallPhysics.KIND_PADDLE, "vx": 0.0}
	var targets: Array = []

	var dt := 1.0 / 60.0
	var elapsed := 0.0
	var paddle_max_speed := 900.0 * speed_scale

	while elapsed < max_seconds and alive > 0:
		# Raquete automatica: persegue o X da bola com velocidade limitada.
		var previous_x := paddle_x
		var step := paddle_max_speed * dt
		paddle_x = clampf(ball.x, paddle_x - step, paddle_x + step)
		var rect := ArenaLayout.paddle_rect(layout, paddle_x)
		paddle_x = rect.get_center().x
		paddle_target["rect"] = rect
		paddle_target["vx"] = (paddle_x - previous_x) / dt

		var speed := ScoreRules.ball_speed_for_level(1) * speed_scale \
			* ScoreRules.ball_speed_multiplier(destroyed, total)
		vel = vel.normalized() * speed

		targets.clear()
		targets.append(paddle_target)
		for brick in bricks:
			if brick["alive"]:
				targets.append(brick)

		var result := BallPhysics.advance(ball, vel, radius, dt, play, targets)
		ball = result["pos"]
		vel = result["vel"]

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
						score += ScoreRules.brick_points(int(brick["points"]), combo)

		# A bola pode sair pelo fundo (perda), mas nunca pelos outros tres lados.
		if ball.x < play.position.x - radius - 1.0 or ball.x > play.end.x + radius + 1.0 \
				or ball.y < play.position.y - radius - 1.0:
			in_bounds = false

		if bool(result["lost"]):
			lost += 1
			paddle_x = play.get_center().x
			ball = ArenaLayout.docked_ball_position(layout, paddle_x)
			vel = BallPhysics.launch_velocity(speed, 0.0)

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
	}


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
