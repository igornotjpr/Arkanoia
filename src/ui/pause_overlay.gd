## Menu de pause - "modo escritorio".
##
## Cobre a tela inteira de branco e escreve PAUSE em cinza claro no centro, com
## dois botoes discretos: continuar a partida ou abandona-la e voltar ao inicio.
## Nada de cores, nada de logo, nada que denuncie um jogo a dois metros de
## distancia. O audio tambem e silenciado (ver Main._set_paused).
##
## Clique fora dos botoes nao faz nada: com um menu na tela, sair da partida por
## engano custa a pontuacao da corrida inteira. Para o despause de emergencia
## continuam valendo P e ESC, tratados em Main._process.
class_name PauseOverlay
extends Control

signal resume_requested
signal menu_requested

const TITLE := "PAUSE"
const TITLE_SCALE := 4
const HINT_SCALE := 1
const BUTTON_SIZE := Vector2(190.0, 24.0)
const BUTTON_GAP := 8.0

var _title_y := 0.0
var _resume_button := Rect2()
var _menu_button := Rect2()
var _hint_y := 0.0
var _hovered := Rect2()


func _ready() -> void:
	# Precisa continuar processando e recebendo cliques com a arvore pausada.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	resized.connect(_layout_ui)
	_layout_ui()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not (button.pressed and button.button_index == MOUSE_BUTTON_LEFT):
			return
		# No toque nao ha movimento previo do cursor: o hover so existe a partir
		# do proprio clique, entao a posicao dele e a fonte da verdade.
		_update_hover(button.position)
		if _resume_button.has_point(button.position):
			accept_event()
			Sfx.play("ui_confirm")
			resume_requested.emit()
		elif _menu_button.has_point(button.position):
			accept_event()
			Sfx.play("ui_back")
			menu_requested.emit()


func _layout_ui() -> void:
	var cx := size.x * 0.5
	var cy := size.y * 0.5
	var title_height := float(PixelFont.text_height(TITLE_SCALE))

	# Bloco centrado: titulo, os dois botoes e a dica de teclado.
	var content_height := (
		title_height + 26.0
		+ BUTTON_SIZE.y * 2.0 + BUTTON_GAP
		+ 20.0 + float(PixelFont.text_height(HINT_SCALE))
	)

	var y := maxf(cy - content_height * 0.5, 10.0)
	_title_y = y
	y += title_height + 26.0

	var left := floorf(cx - BUTTON_SIZE.x * 0.5)
	_resume_button = Rect2(left, floorf(y), BUTTON_SIZE.x, BUTTON_SIZE.y)
	y += BUTTON_SIZE.y + BUTTON_GAP
	_menu_button = Rect2(left, floorf(y), BUTTON_SIZE.x, BUTTON_SIZE.y)
	y += BUTTON_SIZE.y + 20.0

	_hint_y = floorf(y)
	queue_redraw()


## Redesenha so quando o botao sob o cursor muda - a tela fica parada o resto do
## tempo, e nao ha razao para gastar quadros com a arvore pausada.
func _update_hover(pos: Vector2) -> void:
	var current := Rect2()
	if _resume_button.has_point(pos):
		current = _resume_button
	elif _menu_button.has_point(pos):
		current = _menu_button

	if current != _hovered:
		_hovered = current
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.PAUSE_BG, true)

	var cx := size.x * 0.5
	PixelFont.draw_text_centered(self, cx, _title_y, TITLE, TITLE_SCALE, Palette.PAUSE_TEXT)

	_draw_button(_resume_button, "CONTINUAR")
	_draw_button(_menu_button, "SAIR PARA O INICIO")

	var hint := "TOQUE EM CONTINUAR" if DisplayServer.is_touchscreen_available() else "P OU ESC TAMBEM CONTINUA"
	PixelFont.draw_text_centered(self, cx, _hint_y, hint, HINT_SCALE, Palette.PAUSE_HINT)


func _draw_button(rect: Rect2, label: String) -> void:
	var hover := rect == _hovered
	draw_rect(rect, Palette.PAUSE_BUTTON_HOVER if hover else Palette.PAUSE_BUTTON, true)
	draw_rect(rect, Palette.PAUSE_BUTTON_BORDER, false, 1.0)

	var text_y := rect.position.y + (rect.size.y - float(PixelFont.text_height(HINT_SCALE))) * 0.5
	PixelFont.draw_text_centered(self, rect.get_center().x, floorf(text_y), label, HINT_SCALE, Palette.PAUSE_TEXT)
