## Tela de titulo: entrada do nick e leaderboard global.
##
## O nick e digitado num LineEdit invisivel sobreposto a caixa desenhada. Assim o
## visual continua 100%% pixel art, mas ganhamos de graca o teclado virtual do
## celular, colar/copiar e o IME - coisas que uma captura manual de teclas nao
## entregaria.
class_name TitleScreen
extends Control

signal start_requested(nick: String)

const TITLE := "ARKANOIA"
const SUBTITLE := "TJ-PR * SECAO SECRETA DE JOGOS"

const TITLE_SCALE := 4
const NICK_BOX_SIZE := Vector2(136.0, 22.0)
const BUTTON_SIZE := Vector2(132.0, 22.0)
const TEXT_PADDING := 6.0
const VERSION_MARGIN := 6.0

var _nick_edit: LineEdit
var _board: LeaderboardView

var _title_y := 0.0
var _subtitle_y := 0.0
var _nick_label_y := 0.0
var _nick_box := Rect2()
var _warning_y := 0.0
var _play_button := Rect2()
var _legend_y := 0.0

var _warning := ""
var _blink := 0.0
var _syncing_text := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_board = LeaderboardView.new()
	add_child(_board)

	_nick_edit = LineEdit.new()
	_nick_edit.modulate = Color(1.0, 1.0, 1.0, 0.0)  # invisivel: o desenho e nosso
	_nick_edit.flat = true
	_nick_edit.max_length = NickUtil.MAX_LEN
	_nick_edit.text = GameState.nick
	_nick_edit.placeholder_text = ""
	_nick_edit.text_changed.connect(_on_text_changed)
	_nick_edit.text_submitted.connect(_on_text_submitted)
	add_child(_nick_edit)

	resized.connect(_layout_ui)
	Leaderboard.top_scores_received.connect(_on_scores_received)
	Leaderboard.top_scores_failed.connect(_on_scores_failed)

	_layout_ui()
	refresh()


## Chamado pelo Main sempre que a tela volta a ficar visivel.
func refresh() -> void:
	_warning = ""
	_nick_edit.text = GameState.nick
	_nick_edit.caret_column = _nick_edit.text.length()
	_board.set_highlight("", -1)
	if Leaderboard.cached_rows.is_empty():
		_board.set_status("CARREGANDO...")
	else:
		_board.set_rows(Leaderboard.cached_rows)
	Leaderboard.fetch_top()
	_nick_edit.call_deferred("grab_focus")


func _process(delta: float) -> void:
	_blink += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			if _play_button.has_point(button.position):
				accept_event()
				_try_start()
			else:
				# Toque em qualquer outro lugar devolve o foco ao campo do nick,
				# o que reabre o teclado virtual no celular.
				_nick_edit.grab_focus()
	elif event.is_action_pressed(InputSetup.CONFIRM):
		accept_event()
		_try_start()


func _layout_ui() -> void:
	var cx := size.x * 0.5
	var board_height := _board.content_height()

	var content_height := (
		PixelFont.text_height(TITLE_SCALE) + 5.0
		+ PixelFont.text_height(1) + 16.0
		+ PixelFont.text_height(1) + 4.0
		+ NICK_BOX_SIZE.y + 5.0
		+ PixelFont.text_height(1) + 8.0
		+ BUTTON_SIZE.y + 14.0
		+ board_height + 12.0
		+ PixelFont.text_height(1) * 2.0 + 2.0
	)

	var y := maxf(floorf((size.y - content_height) * 0.5), 10.0)

	_title_y = y
	y += PixelFont.text_height(TITLE_SCALE) + 5.0
	_subtitle_y = y
	y += PixelFont.text_height(1) + 16.0
	_nick_label_y = y
	y += PixelFont.text_height(1) + 4.0
	_nick_box = Rect2(floorf(cx - NICK_BOX_SIZE.x * 0.5), y, NICK_BOX_SIZE.x, NICK_BOX_SIZE.y)
	y += NICK_BOX_SIZE.y + 5.0
	_warning_y = y
	y += PixelFont.text_height(1) + 8.0
	_play_button = Rect2(floorf(cx - BUTTON_SIZE.x * 0.5), y, BUTTON_SIZE.x, BUTTON_SIZE.y)
	y += BUTTON_SIZE.y + 14.0

	_board.position = Vector2(0.0, y)
	_board.size = Vector2(size.x, board_height)
	y += board_height + 12.0
	_legend_y = y

	# O campo invisivel ocupa exatamente a caixa desenhada.
	_nick_edit.position = _nick_box.position
	_nick_edit.size = _nick_box.size
	queue_redraw()


func _try_start() -> void:
	var nick := _nick_edit.text
	if not NickUtil.is_valid(nick):
		_warning = "NICK: DE %d A %d CARACTERES" % [NickUtil.MIN_LEN, NickUtil.MAX_LEN]
		Sfx.play("ui_back")
		queue_redraw()
		return

	var clean := NickUtil.sanitize(nick)
	GameState.remember_nick(clean)
	Sfx.play("ui_confirm")
	start_requested.emit(clean)


func _on_text_changed(new_text: String) -> void:
	if _syncing_text:
		return
	var clean := NickUtil.sanitize(new_text)
	if clean != new_text:
		_syncing_text = true
		_nick_edit.text = clean
		_nick_edit.caret_column = clean.length()
		_syncing_text = false
	_warning = ""
	Sfx.play("ui_type")


func _on_text_submitted(_text: String) -> void:
	_try_start()


func _on_scores_received(rows: Array) -> void:
	if visible:
		_board.set_rows(rows)


func _on_scores_failed(message: String) -> void:
	if not visible:
		return
	if Leaderboard.cached_rows.is_empty():
		_board.set_status(message)
	else:
		_board.set_rows(Leaderboard.cached_rows)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG, true)

	var cx := size.x * 0.5

	# Titulo com sombra dupla, no estilo dos letreiros de fliperama.
	PixelFont.draw_text_centered(self, cx + 3.0, _title_y + 3.0, TITLE, TITLE_SCALE, Palette.TJ_BLUE)
	PixelFont.draw_text_centered(self, cx + 1.0, _title_y + 1.0, TITLE, TITLE_SCALE, Palette.TJ_GOLD)
	PixelFont.draw_text_centered(self, cx, _title_y, TITLE, TITLE_SCALE, Palette.TEXT)
	PixelFont.draw_text_centered(self, cx, _subtitle_y, SUBTITLE, 1, Palette.TEXT_DIM)

	PixelFont.draw_text_centered(self, cx, _nick_label_y, "DIGITE SEU NICK", 1, Palette.TEXT_DIM)
	_draw_nick_box()

	if not _warning.is_empty():
		PixelFont.draw_text_centered(self, cx, _warning_y, _warning, 1, Palette.PADDLE_TIP)

	_draw_play_button()
	_draw_legend()
	_draw_version()


## Versao no canto inferior direito, discreta.
##
## Alinhada a direita e presa ao rodape da tela, e nao ao bloco central: assim
## ela nunca disputa espaco com a legenda, que e centrada e cresce para os lados.
func _draw_version() -> void:
	var text := TextUtil.version()
	if text.is_empty():
		return
	PixelFont.draw_text_right(
		self, size.x - VERSION_MARGIN, size.y - PixelFont.text_height(1) - VERSION_MARGIN,
		text, 1, Palette.FRAME_LIGHT
	)


func _draw_nick_box() -> void:
	var focused := _nick_edit.has_focus()
	var border := Palette.TEXT_ACCENT if focused else Palette.FRAME_LIGHT

	draw_rect(_nick_box, Palette.FRAME_DARK, true)
	draw_rect(_nick_box, border, false, 1.0)

	var text := _nick_edit.text
	var text_x := _nick_box.position.x + TEXT_PADDING
	var text_y := _nick_box.position.y + (_nick_box.size.y - PixelFont.text_height(2)) * 0.5
	PixelFont.draw_text(self, Vector2(text_x, text_y), text, 2, Palette.TEXT)

	if focused and fmod(_blink, 1.0) < 0.55:
		var caret_x := text_x + PixelFont.text_width(text, 2) + (2.0 if not text.is_empty() else 0.0)
		draw_rect(Rect2(caret_x, text_y, 2.0, PixelFont.text_height(2)), Palette.TEXT_ACCENT, true)


func _draw_play_button() -> void:
	var hover := _play_button.has_point(get_local_mouse_position())
	draw_rect(_play_button, Palette.TJ_BLUE if hover else Palette.FRAME_DARK, true)
	draw_rect(_play_button, Palette.TEXT_ACCENT if hover else Palette.FRAME_LIGHT, false, 1.0)

	var label := "JOGAR"
	var label_y := _play_button.position.y + (_play_button.size.y - PixelFont.text_height(2)) * 0.5
	PixelFont.draw_text_centered(self, _play_button.get_center().x, label_y, label, 2, Palette.TEXT)


func _draw_legend() -> void:
	var cx := size.x * 0.5
	var touch := DisplayServer.is_touchscreen_available()
	var line_a := "ARRASTE MOVE * TOQUE LANCA" if touch else "MOUSE OU A D MOVE * CLIQUE LANCA"
	var line_b := "TOQUE NO ICONE PAUSA * M LIGA O SOM" if touch else "P PAUSA DISCRETO * M LIGA O SOM"
	PixelFont.draw_text_centered(self, cx, _legend_y, line_a, 1, Palette.TEXT_DIM)
	PixelFont.draw_text_centered(self, cx, _legend_y + PixelFont.text_height(1) + 2.0, line_b, 1, Palette.TEXT_DIM)
