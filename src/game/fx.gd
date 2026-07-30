## Efeitos visuais: particulas pixeladas, textos flutuantes, tremor e flash.
##
## Tudo e desenhado com draw_rect em coordenadas inteiras - nenhuma textura, nada
## de blur, coerente com o visual 8/16 bits. As particulas sao quadrados de 1 a 3
## pixels com gravidade, exatamente como nos jogos da epoca.
class_name Fx
extends Node2D

const MAX_PARTICLES := 320
const MAX_POPUPS := 24

const GRAVITY := 260.0
const DRAG := 0.90

const SHAKE_DECAY := 9.0
const SHAKE_MAX := 6.0
const FLASH_DECAY := 6.5

var shake_offset := Vector2.ZERO

var _particles: Array = []
var _popups: Array = []
var _shake := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## Explosao de particulas na posicao dada.
func burst(pos: Vector2, color: Color, count: int = 10, speed: float = 110.0) -> void:
	for _i in count:
		if _particles.size() >= MAX_PARTICLES:
			return
		var angle := _rng.randf_range(0.0, TAU)
		var magnitude := _rng.randf_range(speed * 0.35, speed)
		_particles.append({
			"pos": pos,
			"vel": Vector2(cos(angle), sin(angle)) * magnitude,
			"life": _rng.randf_range(0.28, 0.62),
			"age": 0.0,
			"size": float(_rng.randi_range(1, 3)),
			"color": color,
		})


## Faixa de particulas saindo de um bloco destruido (mais larga que redonda).
func brick_burst(rect: Rect2, color: Color) -> void:
	var center := rect.position + rect.size * 0.5
	for _i in 14:
		if _particles.size() >= MAX_PARTICLES:
			return
		var origin := Vector2(
			_rng.randf_range(rect.position.x, rect.end.x),
			_rng.randf_range(rect.position.y, rect.end.y)
		)
		var direction := (origin - center).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2.UP
		_particles.append({
			"pos": origin,
			"vel": direction * _rng.randf_range(40.0, 140.0) + Vector2(0.0, _rng.randf_range(-60.0, 10.0)),
			"life": _rng.randf_range(0.30, 0.70),
			"age": 0.0,
			"size": float(_rng.randi_range(1, 3)),
			"color": color if _rng.randf() > 0.3 else Palette.lighten(color, 0.5),
		})


## Faiscas curtas para rebote sem destruicao.
func spark(pos: Vector2, color: Color, normal: Vector2 = Vector2.ZERO) -> void:
	for _i in 4:
		if _particles.size() >= MAX_PARTICLES:
			return
		var base := normal if normal != Vector2.ZERO else Vector2.UP
		var angle := base.angle() + _rng.randf_range(-0.9, 0.9)
		_particles.append({
			"pos": pos,
			"vel": Vector2(cos(angle), sin(angle)) * _rng.randf_range(30.0, 90.0),
			"life": _rng.randf_range(0.10, 0.22),
			"age": 0.0,
			"size": 1.0,
			"color": color,
		})


## Texto que sobe e desaparece (pontos ganhos, combo).
func popup(pos: Vector2, text: String, color: Color, scale: int = 1) -> void:
	if _popups.size() >= MAX_POPUPS:
		_popups.pop_front()
	_popups.append({
		"pos": pos,
		"vel": Vector2(0.0, -34.0),
		"life": 0.75,
		"age": 0.0,
		"text": text,
		"color": color,
		"scale": scale,
	})


## Adiciona tremor de tela (acumulativo, saturado em SHAKE_MAX).
func shake(amount: float) -> void:
	_shake = minf(_shake + amount, SHAKE_MAX)


## Clarao rapido sobre o campo.
func flash(color: Color, strength: float = 0.35) -> void:
	_flash = maxf(_flash, clampf(strength, 0.0, 1.0))
	_flash_color = color


## Limpa todos os efeitos (troca de fase, reinicio de partida).
func clear() -> void:
	_particles.clear()
	_popups.clear()
	_shake = 0.0
	_flash = 0.0
	shake_offset = Vector2.ZERO


func _process(delta: float) -> void:
	var index := _particles.size() - 1
	while index >= 0:
		var p: Dictionary = _particles[index]
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) >= float(p["life"]):
			_particles.remove_at(index)
		else:
			var vel: Vector2 = p["vel"]
			vel.y += GRAVITY * delta
			vel *= pow(DRAG, delta * 60.0)
			p["vel"] = vel
			p["pos"] = Vector2(p["pos"]) + vel * delta
		index -= 1

	index = _popups.size() - 1
	while index >= 0:
		var t: Dictionary = _popups[index]
		t["age"] = float(t["age"]) + delta
		if float(t["age"]) >= float(t["life"]):
			_popups.remove_at(index)
		else:
			t["pos"] = Vector2(t["pos"]) + Vector2(t["vel"]) * delta
		index -= 1

	if _shake > 0.0:
		_shake = maxf(_shake - SHAKE_DECAY * delta, 0.0)
		shake_offset = Vector2(
			roundf(_rng.randf_range(-_shake, _shake)),
			roundf(_rng.randf_range(-_shake, _shake))
		)
	else:
		shake_offset = Vector2.ZERO

	if _flash > 0.0:
		_flash = maxf(_flash - FLASH_DECAY * delta, 0.0)

	queue_redraw()


func _draw() -> void:
	for p in _particles:
		var fade := 1.0 - float(p["age"]) / maxf(float(p["life"]), 0.0001)
		var color: Color = p["color"]
		color.a = clampf(fade, 0.0, 1.0)
		var size := float(p["size"])
		var pos: Vector2 = p["pos"]
		draw_rect(Rect2(roundf(pos.x), roundf(pos.y), size, size), color, true)

	for t in _popups:
		var progress := float(t["age"]) / maxf(float(t["life"]), 0.0001)
		var color: Color = t["color"]
		color.a = clampf(1.0 - progress * progress, 0.0, 1.0)
		var pos: Vector2 = t["pos"]
		PixelFont.draw_text_centered(self, pos.x, pos.y, str(t["text"]), int(t["scale"]), color)

	if _flash > 0.0:
		var overlay := _flash_color
		overlay.a = _flash * 0.5
		var view := get_viewport_rect()
		draw_rect(Rect2(view.position - Vector2(32, 32), view.size + Vector2(64, 64)), overlay, true)
