## Estado global da partida e preferencias persistidas.
##
## Autoload: GameState
##
## Mantem apenas dados - nao conhece nos nem desenho. A arena e a UI leem daqui
## e reagem aos sinais. A persistencia usa user://, que no export web e mapeado
## para IndexedDB pelo proprio Godot.
extends Node

signal score_changed(score: int)
signal lives_changed(lives: int)
signal level_changed(level: int)
signal combo_changed(combo: int)
signal game_finished(score: int, is_local_best: bool)

const SAVE_PATH := "user://arkanoia.cfg"

## As regras numericas vivem em ScoreRules, que e codigo puro e testavel.
const STARTING_LIVES := ScoreRules.STARTING_LIVES
const MAX_LIVES := ScoreRules.MAX_LIVES

var nick := ""
var score := 0
var lives := STARTING_LIVES
var level := 1
var combo := 0
var best_score := 0
var muted_preference := false
var run_started_at_ms := 0
var bricks_destroyed := 0
var bricks_total := 0

## Semente da partida. Toda aleatoriedade de power-up deriva daqui, para que uma
## corrida seja reproduzivel: os testes fixam a semente e obtem a mesma sequencia
## de surgimentos e de sorteios de capsula.
var run_seed := 0
var capsules_caught := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	Sfx.muted = muted_preference


## Prepara uma partida nova. Chamado ao sair da tela de titulo.
func start_run(player_nick: String) -> void:
	nick = NickUtil.sanitize(player_nick)
	score = 0
	lives = STARTING_LIVES
	level = 1
	combo = 0
	bricks_destroyed = 0
	bricks_total = 0
	run_started_at_ms = Time.get_ticks_msec()
	run_seed = randi()
	capsules_caught = 0
	score_changed.emit(score)
	lives_changed.emit(lives)
	level_changed.emit(level)
	combo_changed.emit(combo)


func add_score(amount: int) -> void:
	if amount == 0:
		return
	score = clampi(score + amount, 0, ScoreRules.MAX_VALID_SCORE)
	score_changed.emit(score)


func lose_life() -> int:
	lives = maxi(lives - 1, 0)
	reset_combo()
	lives_changed.emit(lives)
	return lives


func gain_life() -> void:
	lives = mini(lives + 1, MAX_LIVES)
	lives_changed.emit(lives)


func advance_level() -> void:
	level += 1
	bricks_destroyed = 0
	reset_combo()
	level_changed.emit(level)


func register_brick_destroyed() -> void:
	bricks_destroyed += 1
	combo += 1
	combo_changed.emit(combo)


func reset_combo() -> void:
	if combo == 0:
		return
	combo = 0
	combo_changed.emit(combo)


## Duracao da partida em segundos - usada como metadado antifraude no envio.
func run_duration_seconds() -> float:
	if run_started_at_ms == 0:
		return 0.0
	return float(Time.get_ticks_msec() - run_started_at_ms) / 1000.0


## Encerra a partida, atualiza o recorde local e avisa a UI.
func finish_run() -> void:
	var is_best := score > best_score
	if is_best:
		best_score = score
		_save()
	game_finished.emit(score, is_best)


func set_muted_preference(value: bool) -> void:
	muted_preference = value
	Sfx.muted = value
	_save()


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	nick = NickUtil.sanitize(str(config.get_value("player", "nick", "")))
	best_score = maxi(int(config.get_value("player", "best_score", 0)), 0)
	muted_preference = bool(config.get_value("audio", "muted", false))


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "nick", nick)
	config.set_value("player", "best_score", best_score)
	config.set_value("audio", "muted", muted_preference)
	config.save(SAVE_PATH)


## Persiste o nick assim que o jogador confirma, para nao redigitar na proxima vez.
func remember_nick(player_nick: String) -> void:
	nick = NickUtil.sanitize(player_nick)
	_save()
