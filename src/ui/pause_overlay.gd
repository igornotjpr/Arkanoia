## Pause discreto - "modo escritorio".
##
## Cobre a tela inteira de branco e escreve PAUSE em cinza claro no centro.
## Nada de cores, nada de logo, nada que denuncie um jogo a dois metros de
## distancia. O audio tambem e silenciado (ver Main._set_paused).
class_name PauseOverlay
extends Control

signal resume_requested

const TITLE := "PAUSE"
const TITLE_SCALE := 4
const HINT_SCALE := 1


func _ready() -> void:
	# Precisa continuar processando e recebendo cliques com a arvore pausada.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _gui_input(event: InputEvent) -> void:
	var clicked := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	if clicked:
		accept_event()
		resume_requested.emit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.PAUSE_BG, true)

	var cx := size.x * 0.5
	var cy := size.y * 0.5
	PixelFont.draw_text_centered(self, cx, cy - PixelFont.text_height(TITLE_SCALE) * 0.5, TITLE, TITLE_SCALE, Palette.PAUSE_TEXT)

	var hint := "TOQUE PARA CONTINUAR" if DisplayServer.is_touchscreen_available() else "P PARA CONTINUAR"
	PixelFont.draw_text_centered(self, cx, cy + 22.0, hint, HINT_SCALE, Palette.PAUSE_HINT)
