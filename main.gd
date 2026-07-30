## Raiz do jogo: monta a arvore, alterna as telas e controla o pause.
##
## A arvore e construida por codigo em vez de .tscn a mao. Todos os nos sao
## simples (Node2D / Control com _draw proprio), entao cenas empacotadas so
## adicionariam arquivos fragilizados por UIDs sem trazer beneficio.
##
##   Main (PROCESS_MODE_ALWAYS, para poder despausar)
##   |- GameRoot (Node2D) ---- Arena (criada ao iniciar a partida)
##   |- UILayer (CanvasLayer 1) -- Hud, TitleScreen, GameOverScreen
##   |- PauseLayer (CanvasLayer 10) -- PauseOverlay (cobre tudo, inclusive o HUD)
extends Node2D

enum Screen { TITLE, PLAYING, GAME_OVER }

## Autoteste de integracao headless. Exercita a arvore real (Arena, HUD, Fx,
## telas, envio ao leaderboard) sem depender de entrada humana:
##
##   Godot --headless --path . -- --arkanoia-selftest
##
## Fases: joga com piloto automatico, depois erra de proposito para gastar as
## vidas, verifica o fim de partida e sai com codigo 0 ou 1.
##
## Nao use --fixed-fps aqui: o timeout do HTTPRequest conta tempo de
## processamento, e com o relogio acelerado a chamada ao Supabase expira antes de
## qualquer resposta chegar.
const SELFTEST_FLAG := "--arkanoia-selftest"
const SELFTEST_PLAY_SECONDS := 8.0
const SELFTEST_TIMEOUT := 90.0
const SELFTEST_SETTLE_SECONDS := 6.0

var _game_root: Node2D
var _arena: Arena
var _hud: Hud
var _title: TitleScreen
var _game_over: GameOverScreen
var _pause: PauseOverlay

var _screen: Screen = Screen.TITLE
var _paused := false

var _selftest := false
var _selftest_time := 0.0
var _selftest_over_at := -1.0
var _selftest_over_ms := 0
var _selftest_events: Array[String] = []


func _ready() -> void:
	InputSetup.register()
	process_mode = Node.PROCESS_MODE_ALWAYS

	_game_root = Node2D.new()
	_game_root.name = "GameRoot"
	add_child(_game_root)

	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UILayer"
	ui_layer.layer = 1
	add_child(ui_layer)

	_hud = Hud.new()
	_hud.name = "Hud"
	_hud.pause_pressed.connect(_on_pause_pressed)
	ui_layer.add_child(_hud)

	_title = TitleScreen.new()
	_title.name = "TitleScreen"
	_title.start_requested.connect(_start_run)
	ui_layer.add_child(_title)

	_game_over = GameOverScreen.new()
	_game_over.name = "GameOverScreen"
	_game_over.play_again_requested.connect(_on_play_again)
	_game_over.menu_requested.connect(show_title)
	ui_layer.add_child(_game_over)

	var pause_layer := CanvasLayer.new()
	pause_layer.name = "PauseLayer"
	pause_layer.layer = 10
	add_child(pause_layer)

	_pause = PauseOverlay.new()
	_pause.name = "PauseOverlay"
	_pause.resume_requested.connect(func() -> void: _set_paused(false))
	pause_layer.add_child(_pause)

	GameState.game_finished.connect(_on_game_finished)

	show_title()

	_selftest = SELFTEST_FLAG in OS.get_cmdline_args() or SELFTEST_FLAG in OS.get_cmdline_user_args()
	if _selftest:
		_begin_selftest()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(InputSetup.PAUSE) and _screen == Screen.PLAYING:
		_set_paused(not _paused)

	if _selftest:
		_selftest_tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	# O HUD ignora o mouse para nao atrapalhar o controle da raquete, portanto o
	# clique no botao de pause e roteado aqui.
	if _screen != Screen.PLAYING or _paused:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT and _hud.try_press_pause(button.position):
			get_viewport().set_input_as_handled()


## --- Telas -----------------------------------------------------------------

func show_title() -> void:
	_set_paused(false)
	_free_arena()
	_screen = Screen.TITLE
	_hud.visible = false
	_game_over.visible = false
	_title.visible = true
	_title.refresh()


func _start_run(nick: String) -> void:
	_set_paused(false)
	GameState.start_run(nick)
	_free_arena()

	_arena = Arena.new()
	_arena.name = "Arena"
	_arena.run_over.connect(_on_run_over)
	_game_root.add_child(_arena)

	_screen = Screen.PLAYING
	_title.visible = false
	_game_over.visible = false
	_hud.visible = true


func _on_play_again() -> void:
	_start_run(GameState.nick)


func _on_run_over(_score: int) -> void:
	# GameState decide se houve recorde local e emite game_finished.
	GameState.finish_run()


func _on_game_finished(score: int, is_local_best: bool) -> void:
	_screen = Screen.GAME_OVER
	_hud.visible = false
	if is_local_best:
		Sfx.play("highscore")
	else:
		Sfx.play("game_over")
	_game_over.present(score, GameState.level, is_local_best, int(GameState.run_duration_seconds() * 1000.0))


func _free_arena() -> void:
	if _arena != null:
		_arena.queue_free()
		_arena = null


## --- Pause -----------------------------------------------------------------

func _on_pause_pressed() -> void:
	if _screen == Screen.PLAYING:
		_set_paused(true)


func _set_paused(value: bool) -> void:
	if _paused == value:
		return
	_paused = value
	get_tree().paused = value
	_pause.visible = value
	# Modo emergencia: o audio precisa sumir junto com a tela.
	Sfx.set_ducked(value)


## --- Autoteste de integracao ----------------------------------------------

func _begin_selftest() -> void:
	print("")
	print("=== ARKANOIA :: AUTOTESTE DE INTEGRACAO ===")
	print("viewport: %s" % get_viewport().get_visible_rect().size)
	_start_run("SELFTEST")
	_arena.autopilot = true
	_arena.life_lost.connect(func(left: int) -> void:
		_selftest_events.append("vida perdida, restam %d" % left))
	_arena.level_cleared.connect(func(level: int, bonus: int) -> void:
		_selftest_events.append("fase %d limpa, bonus %d" % [level, bonus]))


func _selftest_tick(delta: float) -> void:
	_selftest_time += delta

	# Fase 1: joga bem. Fase 2: erra de proposito para gastar as tres vidas.
	if _arena != null:
		_arena.autopilot = true
		_arena.autopilot_miss = _selftest_time > SELFTEST_PLAY_SECONDS

	if _screen == Screen.GAME_OVER and _selftest_over_at < 0.0:
		_selftest_over_at = _selftest_time
		_selftest_over_ms = Time.get_ticks_msec()
		_selftest_events.append("fim de jogo com %d pontos" % GameState.score)

	# A espera do leaderboard e em tempo REAL, nao em tempo de jogo: com
	# --fixed-fps o loop roda muito mais rapido que o relogio, e uma janela em
	# tempo de jogo terminaria antes de qualquer resposta HTTP chegar.
	var settled := _selftest_over_at >= 0.0 \
		and float(Time.get_ticks_msec() - _selftest_over_ms) / 1000.0 > SELFTEST_SETTLE_SECONDS \
		and not Leaderboard.is_busy()

	if settled or _selftest_time > SELFTEST_TIMEOUT:
		_finish_selftest(_selftest_over_at >= 0.0)


func _finish_selftest(reached_game_over: bool) -> void:
	_selftest = false
	Sfx.stop_all()

	var problems: Array[String] = []
	if not reached_game_over:
		problems.append("nao chegou ao fim de jogo em %.0fs" % SELFTEST_TIMEOUT)
	if _screen != Screen.GAME_OVER:
		problems.append("tela final esperada era GAME_OVER, obtida %d" % _screen)
	if GameState.lives != 0:
		problems.append("vidas deveriam ser 0, sao %d" % GameState.lives)
	if GameState.score <= 0:
		problems.append("pontuacao deveria ser positiva, e %d" % GameState.score)
	if not ScoreRules.is_valid_score(GameState.score):
		problems.append("pontuacao %d fora da faixa enviavel" % GameState.score)
	if GameState.best_score < GameState.score:
		problems.append("recorde local nao foi atualizado")

	print("")
	for event in _selftest_events:
		print("  * %s" % event)
	print("")
	print("  pontuacao final ...... %d" % GameState.score)
	print("  fase alcancada ....... %d" % GameState.level)
	print("  blocos destruidos .... %d de %d" % [GameState.bricks_destroyed, GameState.bricks_total])
	print("  duracao .............. %.1fs" % GameState.run_duration_seconds())
	print("  leaderboard .......... %s" % (
		"%d linhas recebidas" % Leaderboard.cached_rows.size() if Leaderboard.last_error.is_empty()
		else "resposta: %s" % Leaderboard.last_error
	))
	print("  endpoint ............. %s" % SupabaseConfig.top_scores_url(Leaderboard.base_url))

	print("")
	if problems.is_empty():
		print("AUTOTESTE OK")
	else:
		for problem in problems:
			print("AUTOTESTE FALHOU: %s" % problem)
	print("")

	get_tree().quit(0 if problems.is_empty() else 1)
