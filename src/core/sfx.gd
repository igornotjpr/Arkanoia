## Sintetizador de efeitos sonoros chiptune, gerado em tempo de execucao.
##
## Autoload: Sfx
##
## Nenhum arquivo de audio e distribuido - todas as ondas (quadrada, triangular,
## serra e ruido) sao sintetizadas na inicializacao em AudioStreamWAV de 16 bits.
## Isso mantem o build web leve e o repositorio sem assets binarios.
##
## O jogo roda em ambiente de escritorio, portanto o audio comeca em volume
## moderado, pode ser silenciado com M, e o modo pause silencia tudo
## automaticamente (ver PauseOverlay).
extends Node

const MIX_RATE := 22050
const POOL_SIZE := 12

const WAVE_SQUARE := 0
const WAVE_TRIANGLE := 1
const WAVE_SAW := 2
const WAVE_NOISE := 3

## Envelope: fracao da duracao gasta no ataque, e curva do decaimento.
const ATTACK_FRACTION := 0.06
const DECAY_EXPONENT := 1.5

const DEFAULT_VOLUME_DB := -8.0

var muted := false:
	set(value):
		muted = value
		_apply_volume()

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _duck_db := 0.0


func _ready() -> void:
	# Sons de interface precisam funcionar mesmo com a arvore pausada.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_streams()
	_build_pool()
	_apply_volume()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		muted = not muted
		if not muted:
			play("ui_confirm")


## Toca um efeito pelo nome. "pitch" e "volume_db" ajustam a variacao.
func play(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if muted or not _streams.has(name) or _players.is_empty():
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = _streams[name]
	player.pitch_scale = clampf(pitch, 0.25, 4.0)
	player.volume_db = DEFAULT_VOLUME_DB + volume_db + _duck_db
	player.play()


## Efeito de bloco quebrado, com o tom subindo junto com o combo.
func play_brick(combo: int) -> void:
	play("brick", 1.0 + clampf((combo - 1) * 0.06, 0.0, 0.9))


## Silencia (ou restaura) o audio sem alterar a preferencia do jogador.
## Usado pelo pause: o "modo escritorio" precisa ficar mudo instantaneamente.
func set_ducked(ducked: bool) -> void:
	_duck_db = -60.0 if ducked else 0.0
	if ducked:
		stop_all()


## Interrompe tudo que estiver tocando. Necessario antes de encerrar o processo:
## um stream em execucao no momento do quit fica pendurado no ObjectDB.
func stop_all() -> void:
	for player in _players:
		if player.playing:
			player.stop()


func _apply_volume() -> void:
	for player in _players:
		player.volume_db = DEFAULT_VOLUME_DB + _duck_db


func _build_pool() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.bus = &"Master"
		add_child(player)
		_players.append(player)


func _build_streams() -> void:
	_streams["launch"] = _tone(0.10, 300.0, 720.0, WAVE_SQUARE, 0.55, 0.5)
	_streams["paddle"] = _tone(0.06, 430.0, 300.0, WAVE_SQUARE, 0.60, 0.5)
	_streams["wall"] = _tone(0.035, 260.0, 240.0, WAVE_SQUARE, 0.35, 0.25)
	_streams["brick"] = _tone(0.055, 700.0, 990.0, WAVE_SQUARE, 0.55, 0.5)
	_streams["brick_chip"] = _tone(0.07, 200.0, 150.0, WAVE_NOISE, 0.40, 0.5)
	_streams["brick_hard"] = _tone(0.10, 540.0, 240.0, WAVE_SQUARE, 0.60, 0.25)
	_streams["life_lost"] = _tone(0.45, 420.0, 70.0, WAVE_SAW, 0.50, 0.5)
	_streams["ui_move"] = _tone(0.03, 620.0, 620.0, WAVE_SQUARE, 0.30, 0.5)
	_streams["ui_type"] = _tone(0.025, 880.0, 880.0, WAVE_SQUARE, 0.22, 0.125)
	_streams["ui_back"] = _tone(0.07, 400.0, 260.0, WAVE_SQUARE, 0.35, 0.5)

	_streams["ui_confirm"] = _sequence([
		{"freq": 660.0, "duration": 0.05},
		{"freq": 990.0, "duration": 0.08},
	], WAVE_SQUARE, 0.50)

	_streams["level_clear"] = _sequence([
		{"freq": 523.0, "duration": 0.09},
		{"freq": 659.0, "duration": 0.09},
		{"freq": 784.0, "duration": 0.09},
		{"freq": 1047.0, "duration": 0.20},
	], WAVE_TRIANGLE, 0.55)

	_streams["game_over"] = _sequence([
		{"freq": 392.0, "duration": 0.16},
		{"freq": 330.0, "duration": 0.16},
		{"freq": 262.0, "duration": 0.16},
		{"freq": 196.0, "duration": 0.34},
	], WAVE_SQUARE, 0.50)

	_streams["highscore"] = _sequence([
		{"freq": 784.0, "duration": 0.07},
		{"freq": 988.0, "duration": 0.07},
		{"freq": 1175.0, "duration": 0.07},
		{"freq": 1568.0, "duration": 0.18},
	], WAVE_SQUARE, 0.55)


## Uma nota com varredura de frequencia e envelope percussivo.
func _tone(duration: float, freq_start: float, freq_end: float, wave: int, volume: float, duty: float = 0.5) -> AudioStreamWAV:
	var frames := maxi(int(MIX_RATE * duration), 1)
	var data := PackedByteArray()
	data.resize(frames * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260730  # ruido deterministico: o som e sempre identico
	var phase := 0.0

	for i in frames:
		var t := float(i) / float(frames)
		var freq := lerpf(freq_start, freq_end, t)
		phase = fposmod(phase + freq / float(MIX_RATE), 1.0)
		var sample := _waveform(wave, phase, duty, rng)
		data.encode_s16(i * 2, int(clampf(sample * _envelope(t) * volume, -1.0, 1.0) * 32767.0))

	return _wrap(data)


## Varias notas em sequencia, para jingles curtos.
func _sequence(notes: Array, wave: int, volume: float, duty: float = 0.5) -> AudioStreamWAV:
	var total := 0.0
	for note in notes:
		total += float(note["duration"])

	var data := PackedByteArray()
	data.resize(maxi(int(MIX_RATE * total), 1) * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260730
	var phase := 0.0
	var cursor := 0

	for note in notes:
		var freq := float(note["freq"])
		var frames := maxi(int(MIX_RATE * float(note["duration"])), 1)
		for i in frames:
			if (cursor + 1) * 2 > data.size():
				break
			var t := float(i) / float(frames)
			phase = fposmod(phase + freq / float(MIX_RATE), 1.0)
			var sample := _waveform(wave, phase, duty, rng)
			data.encode_s16(cursor * 2, int(clampf(sample * _envelope(t) * volume, -1.0, 1.0) * 32767.0))
			cursor += 1

	return _wrap(data)


func _waveform(wave: int, phase: float, duty: float, rng: RandomNumberGenerator) -> float:
	match wave:
		WAVE_TRIANGLE:
			return 4.0 * absf(phase - 0.5) - 1.0
		WAVE_SAW:
			return phase * 2.0 - 1.0
		WAVE_NOISE:
			return rng.randf_range(-1.0, 1.0)
		_:
			return 1.0 if phase < duty else -1.0


func _envelope(t: float) -> float:
	if t < ATTACK_FRACTION:
		return t / ATTACK_FRACTION
	var decay_t := (t - ATTACK_FRACTION) / maxf(1.0 - ATTACK_FRACTION, 0.0001)
	return pow(clampf(1.0 - decay_t, 0.0, 1.0), DECAY_EXPONENT)


func _wrap(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
