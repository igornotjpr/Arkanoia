## Arena: maquina de estados da partida, entrada do jogador e renderizacao.
##
## Toda a matematica pesada vive em ArenaLayout / BallPhysics / ScoreRules /
## LevelBuilder (codigo puro, coberto por testes headless). Este no cuida de
## orquestrar, tocar som, disparar efeitos e desenhar.
##
## Controles:
##   mouse         move a raquete (1:1, absoluto)
##   A / D / setas move a raquete pelo teclado
##   clique / W / espaco  lanca a bola
##   arrastar      move a raquete no toque; toque curto lanca
##
## Power-ups: a regra toda mora em PowerUps / Capsules / SpecialBricks, que sao
## puros e cobertos por teste. Este no so orquestra - sorteia com um rng semeado,
## desenha, toca som e cobra o tempo.
class_name Arena
extends Node2D

signal life_lost(lives_left: int)
signal level_cleared(level: int, bonus: int)
signal run_over(score: int)

enum State { DOCKED, PLAYING, LOST, CLEARED, OVER }
enum InputMode { KEYBOARD, MOUSE }

const TRAIL_LENGTH := 9
const PADDLE_KEY_SPEED := 340.0
const LOST_DELAY := 1.2
const CLEARED_DELAY := 2.2
const LEVEL_INTRO_DELAY := 1.3
const COMBO_POPUP_MIN := 3

var _layout: Dictionary = {}
var _bricks: Array = []
var _alive_count := 0

var _paddle_x := 0.0
var _paddle_prev_x := 0.0
var _paddle_vx := 0.0

var _ball_pos := Vector2.ZERO
var _ball_vel := Vector2.ZERO
var _trail: Array[Vector2] = []

var _state: State = State.DOCKED
var _state_timer := 0.0
var _intro_timer := 0.0
var _message := ""
var _message_sub := ""
var _blink := 0.0

var _input_mode: InputMode = InputMode.MOUSE
var _last_mouse_pos := Vector2.INF
var _has_touch := false

## Piloto automatico. Usado apenas pelo autoteste de integracao headless
## (main.gd --arkanoia-selftest); no jogo normal permanece desligado.
var autopilot := false
## Quando o piloto automatico deve errar de proposito, para exercitar a perda de
## vidas e o fim de partida.
var autopilot_miss := false

var _fx: Fx
var _targets: Array = []
var _paddle_target := {"rect": Rect2(), "id": "paddle", "kind": BallPhysics.KIND_PADDLE, "vx": 0.0}

## --- Power-ups -------------------------------------------------------------
## Toda a regra vive em PowerUps / Capsules / SpecialBricks, que sao puros. Este
## no so orquestra: sorteia, desenha, toca som e cobra o tempo.

## Semeado a partir de GameState.run_seed, para uma corrida ser reproduzivel.
var _rng := RandomNumberGenerator.new()

## Conjunto ativo: { id -> segundos restantes }. Dado puro, sem classe e sem no,
## exatamente para o soak test poder manipular o mesmo formato sem SceneTree.
var _effects: Dictionary = {}

var _capsules: Array = []
var _capsule_serial := 0

var _spawn_timer := 0.0
var _special_alive := 0

## Aviso previo do bloco que vai materializar: { "cell": Vector2i, "timer": float }.
var _pending_spawn: Dictionary = {}

## Contadores lidos pelo autoteste de integracao.
var specials_spawned := 0
var capsules_caught := 0


func _ready() -> void:
	_has_touch = DisplayServer.is_touchscreen_available()
	_fx = Fx.new()
	add_child(_fx)

	_layout = ArenaLayout.compute(get_viewport_rect().size)
	_paddle_x = play_rect().get_center().x
	_paddle_prev_x = _paddle_x

	get_viewport().size_changed.connect(_on_viewport_resized)
	start_level()


## --- Ciclo de vida da fase -------------------------------------------------

## Monta a fase atual de GameState e encaixa a bola na raquete.
func start_level() -> void:
	_bricks = LevelBuilder.build(GameState.level)
	for brick in _bricks:
		brick["alive"] = true
		brick["flash"] = 0.0
		brick["kind"] = BallPhysics.KIND_BRICK
		brick["rect"] = ArenaLayout.brick_rect(_layout, int(brick["col"]), int(brick["row"]))

	_alive_count = _bricks.size()
	GameState.bricks_total = _alive_count
	_fx.clear()

	# A semente combina corrida e fase: repetir a fase 2 da mesma partida da a
	# mesma sequencia de surgimentos, e trocar de fase muda a sequencia.
	_rng.seed = GameState.run_seed + GameState.level * 1000
	_effects.clear()
	_capsules.clear()
	_capsule_serial = 0
	_special_alive = 0
	_pending_spawn.clear()
	_spawn_timer = SpecialBricks.next_interval(_rng)

	_intro_timer = LEVEL_INTRO_DELAY
	_message = "FASE %d" % GameState.level
	_message_sub = ""
	dock_ball()


## Recoloca a bola sobre a raquete, aguardando o lancamento.
##
## A raquete NAO volta ao centro: ela fica onde o jogador deixou. No mouse isso
## era invisivel (o cursor reassume a posicao no quadro seguinte), mas no teclado
## o recuo ao centro teleportava a raquete a cada vida perdida e a cada fase
## nova. A posicao inicial de uma partida e definida uma unica vez, em _ready.
func dock_ball() -> void:
	_paddle_x = ArenaLayout.paddle_rect(_layout, _paddle_x, _paddle_scale()).get_center().x
	_paddle_prev_x = _paddle_x
	_paddle_vx = 0.0
	_ball_pos = ArenaLayout.docked_ball_position(_layout, _paddle_x, _paddle_scale())
	_ball_vel = Vector2.ZERO
	_trail.clear()
	_state = State.DOCKED


## Lanca a bola a partir da raquete.
func launch_ball() -> void:
	if _state != State.DOCKED or _intro_timer > 0.0:
		return
	var bias := clampf(_paddle_vx / 320.0, -1.0, 1.0)
	_ball_vel = BallPhysics.launch_velocity(current_ball_speed(), bias)
	_state = State.PLAYING
	_message = ""
	Sfx.play("launch")


## Velocidade atual da bola: fase + escala do layout + progresso + power-ups.
##
## Como _simulate_ball renormaliza o modulo todo quadro, este multiplicador e a
## implementacao inteira de CALMA e SURTO - a direcao nunca e tocada.
func current_ball_speed() -> float:
	var base := ScoreRules.ball_speed_for_level(GameState.level)
	var progress := ScoreRules.ball_speed_multiplier(GameState.bricks_destroyed, maxi(GameState.bricks_total, 1))
	return base * float(_layout["speed_scale"]) * progress * PowerUps.ball_speed_scale(_effects)


## Largura da raquete sob os efeitos ativos. Todo paddle_rect passa por aqui.
func _paddle_scale() -> float:
	return PowerUps.paddle_width_scale(_effects)


func is_playing() -> bool:
	return _state == State.PLAYING


## --- Loop ------------------------------------------------------------------

func _process(delta: float) -> void:
	position = _fx.shake_offset
	_blink += delta

	if _intro_timer > 0.0:
		_intro_timer = maxf(_intro_timer - delta, 0.0)
		if _intro_timer == 0.0 and _state == State.DOCKED:
			_message = ""

	_update_paddle(delta)
	_decay_brick_flashes(delta)

	# Antes do match de estado, de proposito: um efeito precisa continuar
	# expirando durante LOST e CLEARED, senao ele "congela" e volta inteiro.
	_update_effects(delta)
	_update_capsules(delta)
	_update_spawn(delta)

	match _state:
		State.DOCKED:
			_ball_pos = ArenaLayout.docked_ball_position(_layout, _paddle_x, _paddle_scale())
			if autopilot or Input.is_action_just_pressed(InputSetup.LAUNCH):
				launch_ball()
		State.PLAYING:
			_simulate_ball(delta)
		State.LOST, State.CLEARED:
			_advance_state_timer(delta)
		State.OVER:
			pass

	queue_redraw()


func _update_paddle(delta: float) -> void:
	var target := _paddle_x

	if autopilot:
		var play := play_rect()
		target = play.position.x + 4.0 if autopilot_miss else _ball_pos.x
		var rect_auto := ArenaLayout.paddle_rect(_layout, target, _paddle_scale())
		_paddle_prev_x = _paddle_x
		_paddle_x = rect_auto.get_center().x
		_paddle_vx = (_paddle_x - _paddle_prev_x) / maxf(delta, 0.0001)
		return

	# O teclado assume o controle enquanto uma tecla estiver pressionada, e parte
	# sempre de _paddle_x - o ponto onde o mouse deixou a raquete, sem salto para
	# o centro. Ao soltar a tecla o modo continua KEYBOARD: a raquete so volta a
	# seguir o cursor apos um movimento real do mouse, detectado em _input.
	# paddle_axis_sign vale 1.0 com o cardapio da v1.2.0. Ele ja entra aqui para
	# que VERTIGEM, na v2.0.0, seja so uma entrada nova no catalogo.
	var axis := Input.get_axis(InputSetup.LEFT, InputSetup.RIGHT) * PowerUps.paddle_axis_sign(_effects)
	if not is_zero_approx(axis):
		_input_mode = InputMode.KEYBOARD
		target += axis * PADDLE_KEY_SPEED * float(_layout["speed_scale"]) * delta
	elif _input_mode == InputMode.MOUSE:
		target = get_viewport().get_mouse_position().x

	var rect := ArenaLayout.paddle_rect(_layout, target, _paddle_scale())
	_paddle_prev_x = _paddle_x
	_paddle_x = rect.position.x + rect.size.x * 0.5
	_paddle_vx = (_paddle_x - _paddle_prev_x) / maxf(delta, 0.0001)


func _simulate_ball(delta: float) -> void:
	# Reajusta o modulo mantendo a direcao: a velocidade sobe com o progresso.
	if _ball_vel != Vector2.ZERO:
		_ball_vel = _ball_vel.normalized() * current_ball_speed()

	# A MESMA escala usada no desenho. Divergir aqui faria a raquete desenhar
	# larga e colidir estreita - o pior bug possivel neste jogo.
	_paddle_target["rect"] = ArenaLayout.paddle_rect(_layout, _paddle_x, _paddle_scale())
	_paddle_target["vx"] = _paddle_vx

	_targets.clear()
	_targets.append(_paddle_target)
	for brick in _bricks:
		if brick["alive"]:
			_targets.append(brick)

	var result := BallPhysics.advance(
		_ball_pos, _ball_vel, float(_layout["ball_radius"]), delta, play_rect(), _targets
	)
	_ball_pos = result["pos"]
	_ball_vel = result["vel"]

	for event in result["events"]:
		_handle_collision(event)

	_push_trail(_ball_pos)

	if result["lost"]:
		_on_ball_lost()
	elif _alive_count == 0:
		_on_level_cleared()


func _handle_collision(event: Dictionary) -> void:
	match str(event["type"]):
		"wall":
			Sfx.play("wall")
			_fx.spark(event["point"], Palette.FRAME_LIGHT, event["normal"])
		"paddle":
			Sfx.play("paddle")
			GameState.reset_combo()
			_fx.spark(event["point"], Palette.PADDLE, Vector2.UP)
		"brick":
			var id: int = int(event["id"])
			if id >= 0 and id < _bricks.size():
				_hit_brick(_bricks[id], event["point"])


func _hit_brick(brick: Dictionary, point: Vector2) -> void:
	brick["hp"] = int(brick["hp"]) - 1
	var color: Color = brick["color"]

	if int(brick["hp"]) > 0:
		# Bloco reforcado apenas trincou.
		brick["flash"] = 1.0
		GameState.add_score(ScoreRules.chip_points(int(brick["points"])))
		Sfx.play("brick_chip")
		_fx.spark(point, Palette.lighten(color, 0.45))
		_fx.shake(0.9)
		return

	brick["alive"] = false
	_alive_count -= 1
	GameState.register_brick_destroyed()

	var points := ScoreRules.brick_points(int(brick["points"]), GameState.combo, PowerUps.risk_level(_effects))
	GameState.add_score(points)

	# _visual_rect, e nao brick["rect"]: na v2.0.0 MIRAGEM embaralha as posicoes
	# desenhadas, e uma explosao na posicao verdadeira entregaria a mentira.
	var rect := _visual_rect(brick)
	_fx.brick_burst(rect, color)
	_fx.shake(1.3)

	var brick_type := int(brick["type"])
	if brick_type == LevelBuilder.TYPE_NORMAL:
		Sfx.play_brick(GameState.combo)
	else:
		Sfx.play("brick_hard")
		_fx.flash(Palette.TJ_GOLD if brick_type == LevelBuilder.TYPE_TJ_GOLD else Palette.TJ_BLUE_LIGHT, 0.18)

	_drop_capsule(brick, rect)

	var label := str(points)
	var label_color := Palette.TEXT
	if GameState.combo >= COMBO_POPUP_MIN:
		label = "%d X%.2f" % [points, ScoreRules.combo_multiplier(GameState.combo)]
		label_color = Palette.TEXT_ACCENT
	_fx.popup(rect.get_center(), label, label_color)


## --- Power-ups -------------------------------------------------------------

## Retangulo em que o bloco e DESENHADO. Identidade na v1.2.0.
##
## Existe desde ja, e usado em todos os pontos de desenho e de efeito, para que
## MIRAGEM (v2.0.0) seja uma mudanca de tres linhas aqui dentro, numa funcao que
## a essa altura ja rodou uma versao inteira em producao. A colisao NUNCA passa
## por aqui: _targets continua lendo brick["rect"], a verdade.
func _visual_rect(brick: Dictionary) -> Rect2:
	return brick["rect"]


func _update_effects(delta: float) -> void:
	if _effects.is_empty():
		return

	var ticked := PowerUps.tick(_effects, delta)
	_effects = ticked["active"]

	for id in ticked["expired"]:
		Sfx.play("effect_end")
		_fx.popup(_paddle_center(), PowerUps.label(id) + " FIM", Palette.TEXT_DIM)


func _update_capsules(delta: float) -> void:
	if _capsules.is_empty():
		return

	var stepped := Capsules.step(
		_capsules, delta, play_rect(),
		ArenaLayout.paddle_rect(_layout, _paddle_x, _paddle_scale()),
		Capsules.speed(_layout), Capsules.size(_layout)
	)
	_capsules = stepped["capsules"]

	for item in stepped["caught"]:
		_collect(str(item))


## Sorteia, avisa e materializa o bloco especial que surge durante a fase.
func _update_spawn(delta: float) -> void:
	if _state != State.PLAYING or _intro_timer > 0.0:
		return

	if not _pending_spawn.is_empty():
		_pending_spawn["timer"] = float(_pending_spawn["timer"]) - delta
		if float(_pending_spawn["timer"]) <= 0.0:
			_materialize_spawn()
		return

	if _special_alive >= SpecialBricks.MAX_ALIVE or _alive_count < SpecialBricks.STOP_WHEN_ALIVE_BELOW:
		return

	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return

	var max_row := SpecialBricks.max_spawn_row(_layout, Capsules.speed(_layout))
	var cells := SpecialBricks.free_cells(_bricks, max_row)
	var cell := SpecialBricks.pick_cell(
		_rng, cells, _layout, _ball_pos, _ball_vel, float(_layout["ball_radius"])
	)

	if cell.x < 0:
		_spawn_timer = SpecialBricks.RETRY_SECONDS
		return

	_pending_spawn = {"cell": cell, "timer": SpecialBricks.TELEGRAPH_SECONDS}
	_spawn_timer = SpecialBricks.next_interval(_rng)
	Sfx.play("special_spawn")


func _materialize_spawn() -> void:
	var cell: Vector2i = _pending_spawn["cell"]
	_pending_spawn.clear()

	# Segunda checagem: a bola andou durante o aviso previo. Materializar em cima
	# dela faria BallPhysics eject-la pelo eixo de menor penetracao - um teleporte
	# visivel e inexplicavel para quem esta jogando.
	var cell_rect := ArenaLayout.brick_rect(_layout, cell.x, cell.y)
	if not SpecialBricks.is_cell_safe(cell_rect, _ball_pos, _ball_vel, float(_layout["ball_radius"]), SpecialBricks.BALL_LOOKAHEAD):
		_spawn_timer = SpecialBricks.RETRY_SECONDS
		return

	var brick := SpecialBricks.make_brick(_bricks.size(), cell, _layout)
	_bricks.append(brick)

	# So _alive_count, nunca GameState.bricks_total: este ultimo alimenta
	# ScoreRules.ball_speed_multiplier, e aumenta-lo no meio da fase faria a bola
	# DESACELERAR no instante em que um bloco ameacador aparece.
	_alive_count += 1
	_special_alive += 1
	specials_spawned += 1

	_fx.burst(cell_rect.get_center(), Palette.SPECIAL_LIGHT, 12, 90.0)
	_fx.shake(1.6)


func _drop_capsule(brick: Dictionary, rect: Rect2) -> void:
	var brick_type := int(brick["type"])
	if brick_type == LevelBuilder.TYPE_SPECIAL_SPAWNED:
		_special_alive = maxi(_special_alive - 1, 0)

	if _capsules.size() >= Capsules.MAX_ACTIVE:
		return

	var item := PowerUps.roll_drop(_rng, brick_type)
	if item.is_empty():
		return

	_capsules.append(Capsules.make(_capsule_serial, item, rect.get_center()))
	_capsule_serial += 1
	Sfx.play("capsule_drop")


func _collect(item: String) -> void:
	if not PowerUps.exists(item):
		return

	capsules_caught += 1
	GameState.capsules_caught += 1
	Sfx.play("capsule_catch")

	# O risco vale o do instante da coleta, ANTES do efeito novo: apanhar uma
	# capsula rara ja estando amaldicoado e a jogada que mais paga no jogo.
	var risk := PowerUps.risk_level(_effects)
	GameState.add_score(ScoreRules.capsule_points(PowerUps.tier(item), risk))

	if item == PowerUps.LIFE:
		GameState.gain_life()
	elif item == PowerUps.BONUS:
		GameState.add_score(int(round(PowerUps.BONUS_POINTS * ScoreRules.risk_multiplier(risk))))

	_effects = PowerUps.apply(_effects, item)
	_fx.popup(_paddle_center(), PowerUps.label(item), Palette.TEXT_ACCENT)


func _paddle_center() -> Vector2:
	var rect := ArenaLayout.paddle_rect(_layout, _paddle_x, _paddle_scale())
	return Vector2(rect.get_center().x, rect.position.y - 12.0)


func _on_ball_lost() -> void:
	_state = State.LOST
	_state_timer = LOST_DELAY
	_ball_vel = Vector2.ZERO
	_trail.clear()

	# Perder uma vida derruba as bencaos E as maldicoes: uma maldicao nao
	# atravessa uma morte que o jogador ja pagou.
	_effects.clear()
	_capsules.clear()
	_pending_spawn.clear()

	Sfx.play("life_lost")
	_fx.shake(4.5)
	_fx.flash(Palette.PADDLE_TIP, 0.22)

	var left := GameState.lose_life()
	life_lost.emit(left)

	if left > 0:
		_message = "BOLA PERDIDA"
		_message_sub = "%d %s" % [left, "VIDA RESTANTE" if left == 1 else "VIDAS RESTANTES"]
	else:
		_message = "FIM DE JOGO"
		_message_sub = ""


func _on_level_cleared() -> void:
	_state = State.CLEARED
	_state_timer = CLEARED_DELAY
	_ball_vel = Vector2.ZERO
	_trail.clear()

	var bonus := ScoreRules.level_clear_bonus(GameState.level, GameState.lives)
	GameState.add_score(bonus)

	Sfx.play("level_clear")
	_fx.flash(Palette.TJ_GOLD, 0.35)
	_fx.burst(play_rect().get_center(), Palette.TJ_GOLD_LIGHT, 40, 180.0)

	_message = LevelBuilder.clear_message(GameState.level)
	_message_sub = "BONUS %d" % bonus
	level_cleared.emit(GameState.level, bonus)


func _advance_state_timer(delta: float) -> void:
	_state_timer = maxf(_state_timer - delta, 0.0)
	if _state_timer > 0.0:
		return

	if _state == State.LOST:
		if GameState.lives <= 0:
			_state = State.OVER
			_message = ""
			_message_sub = ""
			run_over.emit(GameState.score)
		else:
			_message = ""
			_message_sub = ""
			dock_ball()
	elif _state == State.CLEARED:
		GameState.advance_level()
		start_level()


func _decay_brick_flashes(delta: float) -> void:
	for brick in _bricks:
		var flash := float(brick["flash"])
		if flash > 0.0:
			brick["flash"] = maxf(flash - delta * 5.0, 0.0)


func _push_trail(pos: Vector2) -> void:
	_trail.append(pos)
	while _trail.size() > TRAIL_LENGTH:
		_trail.pop_front()


## --- Entrada ---------------------------------------------------------------

## No mobile, project.godot ativa emulate_mouse_from_touch: arrastar chega como
## InputEventMouseMotion e o toque como clique. Assim ha um unico caminho de
## codigo para mouse e toque, e os Controls da UI continuam funcionando.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _last_mouse_pos == Vector2.INF or motion.position.distance_to(_last_mouse_pos) > 0.5:
			_input_mode = InputMode.MOUSE
		_last_mouse_pos = motion.position

	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		# So lanca com clique dentro do campo: evita disparar a bola ao clicar no
		# HUD (onde fica o botao de pause) ou nas bordas da pagina.
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			var frame: Rect2 = _layout["frame"]
			if frame.has_point(button.position):
				launch_ball()


func _on_viewport_resized() -> void:
	var old_play := play_rect()
	_layout = ArenaLayout.compute(get_viewport_rect().size)
	var new_play := play_rect()

	for brick in _bricks:
		brick["rect"] = ArenaLayout.brick_rect(_layout, int(brick["col"]), int(brick["row"]))

	# Remapeia a bola, a raquete e as capsulas proporcionalmente para o novo campo.
	_paddle_x = ArenaLayout.remap_axis(_paddle_x, old_play.position.x, old_play.end.x, new_play.position.x, new_play.end.x)
	_ball_pos = Vector2(
		ArenaLayout.remap_axis(_ball_pos.x, old_play.position.x, old_play.end.x, new_play.position.x, new_play.end.x),
		ArenaLayout.remap_axis(_ball_pos.y, old_play.position.y, old_play.end.y, new_play.position.y, new_play.end.y)
	)
	_capsules = Capsules.remap(_capsules, old_play, new_play)
	_trail.clear()
	if _state == State.DOCKED:
		_ball_pos = ArenaLayout.docked_ball_position(_layout, _paddle_x, _paddle_scale())


func play_rect() -> Rect2:
	return _layout["play"]


## --- Desenho ---------------------------------------------------------------

## As capsulas ficam ABAIXO da raquete na ordem de desenho: a coleta le como a
## raquete engolindo a capsula, e nao como a capsula passando por cima dela.
func _draw() -> void:
	_draw_field()
	for brick in _bricks:
		if brick["alive"]:
			_draw_brick(brick)
	_draw_pending_spawn()
	_draw_capsules()
	_draw_paddle()
	_draw_ball()
	_draw_combo()
	_draw_effects()
	_draw_message()


func _draw_field() -> void:
	var frame: Rect2 = _layout["frame"]
	var play := play_rect()

	draw_rect(frame, Palette.FRAME_MID, true)
	draw_rect(Rect2(frame.position, Vector2(frame.size.x, 2)), Palette.FRAME_LIGHT, true)
	draw_rect(Rect2(frame.position, Vector2(2, frame.size.y)), Palette.FRAME_LIGHT, true)
	draw_rect(Rect2(frame.position.x, frame.end.y - 2, frame.size.x, 2), Palette.FRAME_DARK, true)
	draw_rect(Rect2(frame.end.x - 2, frame.position.y, 2, frame.size.y), Palette.FRAME_DARK, true)

	draw_rect(play, Palette.PLAY_BG, true)

	# Scanlines discretas: dao textura de CRT sem custar desempenho.
	var line_color := Color(1.0, 1.0, 1.0, 0.022)
	var y := play.position.y
	while y < play.end.y:
		draw_rect(Rect2(play.position.x, y, play.size.x, 1), line_color, true)
		y += 4.0


func _draw_brick(brick: Dictionary) -> void:
	var rect := _visual_rect(brick)
	var color: Color = brick["color"]
	var flash := float(brick["flash"])
	if flash > 0.0:
		color = color.lerp(Color.WHITE, flash * 0.7)

	draw_rect(rect, color, true)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), Palette.lighten(color, 0.45), true)
	draw_rect(Rect2(rect.position, Vector2(1, rect.size.y)), Palette.lighten(color, 0.30), true)
	draw_rect(Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), Palette.darken(color, 0.45), true)
	draw_rect(Rect2(rect.end.x - 1, rect.position.y, 1, rect.size.y), Palette.darken(color, 0.35), true)

	var brick_type := int(brick["type"])
	if brick_type != LevelBuilder.TYPE_NORMAL:
		# Blocos reforcados TJ-PR ganham um filete interno metalico. Os especiais
		# usam o mesmo filete em tom proprio - a leitura "este bloco vale a pena"
		# vem do formato, nao de um enfeite exclusivo.
		var accent := Palette.TJ_BLUE_LIGHT
		match brick_type:
			LevelBuilder.TYPE_TJ_GOLD:
				accent = Palette.TJ_GOLD_LIGHT
			LevelBuilder.TYPE_SPECIAL, LevelBuilder.TYPE_SPECIAL_SPAWNED:
				accent = Palette.SPECIAL_LIGHT
		draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(rect.size.x - 4, 1)), accent, true)
		draw_rect(Rect2(rect.position + Vector2(2, rect.size.y - 3), Vector2(rect.size.x - 4, 1)), accent, true)

	# Trinca visivel quando o bloco reforcado ja levou um toque.
	if int(brick["hp"]) < int(brick["max_hp"]):
		var crack := Palette.darken(color, 0.6)
		var cx := rect.position.x + rect.size.x * 0.5
		var cy := rect.position.y + rect.size.y * 0.5
		draw_rect(Rect2(cx - 4, cy - 3, 2, 2), crack, true)
		draw_rect(Rect2(cx - 1, cy - 1, 2, 2), crack, true)
		draw_rect(Rect2(cx + 2, cy + 1, 2, 2), crack, true)


func _draw_paddle() -> void:
	var rect := ArenaLayout.paddle_rect(_layout, _paddle_x, _paddle_scale())
	var tip := minf(7.0, rect.size.x * 0.25)

	draw_rect(rect, Palette.PADDLE, true)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2)), Palette.lighten(Palette.PADDLE, 0.5), true)
	draw_rect(Rect2(rect.position.x, rect.end.y - 3, rect.size.x, 3), Palette.PADDLE_DARK, true)

	draw_rect(Rect2(rect.position, Vector2(tip, rect.size.y)), Palette.PADDLE_TIP, true)
	draw_rect(Rect2(rect.end.x - tip, rect.position.y, tip, rect.size.y), Palette.PADDLE_TIP, true)
	draw_rect(Rect2(rect.position, Vector2(tip, 1)), Palette.lighten(Palette.PADDLE_TIP, 0.4), true)
	draw_rect(Rect2(rect.end.x - tip, rect.position.y, tip, 1), Palette.lighten(Palette.PADDLE_TIP, 0.4), true)


func _draw_ball() -> void:
	# Rastro: quadrados de 4 px com alpha crescente ate a bola.
	var count := _trail.size()
	for i in count:
		var alpha := (float(i + 1) / float(count)) * 0.30
		var color := Palette.BALL_TRAIL
		color.a = alpha
		var p: Vector2 = _trail[i]
		draw_rect(Rect2(roundf(p.x) - 2, roundf(p.y) - 2, 4, 4), color, true)

	# Bola: circulo pixelado 8x8 montado com tres retangulos.
	var x := roundf(_ball_pos.x) - 4.0
	var y := roundf(_ball_pos.y) - 4.0
	draw_rect(Rect2(x + 2, y, 4, 8), Palette.BALL, true)
	draw_rect(Rect2(x + 1, y + 1, 6, 6), Palette.BALL, true)
	draw_rect(Rect2(x, y + 2, 8, 4), Palette.BALL, true)


## Contorno piscando onde um bloco especial vai materializar. Nada aparece sem
## aviso: a espessura cresce conforme o tempo acaba.
func _draw_pending_spawn() -> void:
	if _pending_spawn.is_empty():
		return

	var cell: Vector2i = _pending_spawn["cell"]
	var timer := float(_pending_spawn["timer"])
	if fmod(timer, 0.24) > 0.14:
		return

	var rect := ArenaLayout.brick_rect(_layout, cell.x, cell.y)
	var progress := 1.0 - clampf(timer / SpecialBricks.TELEGRAPH_SECONDS, 0.0, 1.0)
	draw_rect(rect, Palette.SPAWN_TELEGRAPH, false, 1.0 + progress * 2.0)


func _draw_capsules() -> void:
	if _capsules.is_empty():
		return
	var capsule_size := Capsules.size(_layout)
	for capsule in _capsules:
		_draw_capsule(capsule, capsule_size)


## Capsula: corpo, chanfro e sigilo.
##
## O corpo e o chanfro sao IDENTICOS para todo item - so o sigilo de 5x3 e uma
## variacao de tom de no maximo 6% distinguem um do outro, e o tom nao tem relacao
## com o efeito. Quem decora os sigilos passa a ler a capsula na queda; quem nao
## decora aposta. Era esse o pedido.
func _draw_capsule(capsule: Dictionary, capsule_size: Vector2) -> void:
	var item := str(capsule["item"])
	var rect := Capsules.rect(capsule, capsule_size)
	var body := Palette.lighten(Palette.CAPSULE, PowerUps.shade(item))

	draw_rect(rect, body, true)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), Palette.lighten(body, 0.40), true)
	draw_rect(Rect2(rect.position, Vector2(1, rect.size.y)), Palette.lighten(body, 0.28), true)
	draw_rect(Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), Palette.darken(body, 0.40), true)
	draw_rect(Rect2(rect.end.x - 1, rect.position.y, 1, rect.size.y), Palette.darken(body, 0.30), true)

	_draw_sigil(item, rect.get_center(), 2.0, Palette.CAPSULE_SIGIL)


## Desenha o sigilo de 5x3 centrado no ponto, com o pixel na escala pedida.
##
## Deliberadamente NAO usa a PixelFont: uma letra de 5x7 seria legivel de imediato
## e mataria a mecanica das capsulas quase identicas.
func _draw_sigil(item: String, center: Vector2, pixel: float, color: Color) -> void:
	var rows := PowerUps.sigil(item)
	if rows.is_empty():
		return

	var origin := center - Vector2(5.0 * pixel, float(rows.size()) * pixel) * 0.5
	for row in rows.size():
		var line := str(rows[row])
		for col in line.length():
			if line[col] != "#":
				continue
			draw_rect(Rect2(origin + Vector2(col * pixel, row * pixel), Vector2(pixel, pixel)), color, true)


## Faixa de efeitos ativos, no canto superior esquerdo do campo.
##
## Desenha os MESMOS sigilos das capsulas, e e isso que torna o sistema justo: o
## jogador apanha, ve o sigilo aceso enquanto o efeito corre, e aprende a
## associacao sem uma linha de tutorial. Sem texto, tambem, para nao gastar
## glifos novos da PixelFont.
func _draw_effects() -> void:
	if _effects.is_empty():
		return

	var play := play_rect()
	var x := play.position.x + 8.0
	var y := play.position.y + 8.0

	for id in PowerUps.ordered_ids(_effects):
		var total := PowerUps.duration(id)
		var remaining := float(_effects[id])

		_draw_sigil(id, Vector2(x + 5.0, y + 3.0), 2.0, Palette.TEXT_ACCENT)

		var fraction := clampf(remaining / maxf(total, 0.001), 0.0, 1.0)
		draw_rect(Rect2(x, y + 10.0, 10.0, 1.0), Palette.FRAME_MID, true)
		draw_rect(Rect2(x, y + 10.0, 10.0 * fraction, 1.0), Palette.TEXT_ACCENT, true)

		x += 16.0


func _draw_combo() -> void:
	if GameState.combo < COMBO_POPUP_MIN or _state != State.PLAYING:
		return
	var play := play_rect()
	var text := "COMBO X%.2f" % ScoreRules.combo_multiplier(GameState.combo)
	PixelFont.draw_text_centered(self, play.get_center().x, play.position.y + 8.0, text, 1, Palette.TEXT_ACCENT)


func _draw_message() -> void:
	var play := play_rect()
	var center_x := play.get_center().x
	var center_y := play.get_center().y

	if not _message.is_empty():
		var shadow := Color(0.0, 0.0, 0.0, 0.55)
		PixelFont.draw_text_centered(self, center_x + 2.0, center_y - 12.0, _message, 3, shadow)
		PixelFont.draw_text_centered(self, center_x, center_y - 14.0, _message, 3, Palette.TEXT)
		if not _message_sub.is_empty():
			PixelFont.draw_text_centered(self, center_x, center_y + 16.0, _message_sub, 1, Palette.TEXT_ACCENT)

	if _state == State.DOCKED and _intro_timer == 0.0:
		# Dica piscando, com o texto conforme o dispositivo.
		if fmod(_blink, 1.0) < 0.62:
			var hint := "TOQUE PARA LANCAR" if _has_touch else "CLIQUE OU ESPACO PARA LANCAR"
			PixelFont.draw_text_centered(self, center_x, center_y + 24.0, hint, 1, Palette.TEXT_DIM)
