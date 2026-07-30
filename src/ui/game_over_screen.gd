## Tela de fim de partida: resultado, envio ao leaderboard e ranking global.
##
## O envio acontece aqui e nao na Arena porque esta e a unica tela que pode
## mostrar o resultado da operacao ao jogador e permitir uma nova tentativa.
class_name GameOverScreen
extends Control

signal play_again_requested
signal menu_requested

const TITLE_SCALE := 3
const BUTTON_SIZE := Vector2(150.0, 22.0)
const BUTTON_GAP := 10.0

var _board: LeaderboardView

var _title_y := 0.0
var _best_y := 0.0
var _score_y := 0.0
var _detail_y := 0.0
var _status_y := 0.0
var _again_button := Rect2()
var _menu_button := Rect2()

var _final_score := 0
var _final_level := 1
var _is_local_best := false
var _status := ""
var _status_color := Palette.TEXT_DIM
var _blink := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	_board = LeaderboardView.new()
	_board.title = "TOP 10 GLOBAL"
	add_child(_board)

	resized.connect(_layout_ui)
	Leaderboard.submit_finished.connect(_on_submit_finished)
	Leaderboard.top_scores_received.connect(_on_scores_received)
	Leaderboard.top_scores_failed.connect(_on_scores_failed)

	_layout_ui()


## Exibe o resultado e dispara o envio da pontuacao.
func present(score: int, level: int, is_local_best: bool, duration_ms: int) -> void:
	_final_score = score
	_final_level = level
	_is_local_best = is_local_best

	_board.set_highlight(GameState.nick, score)
	if Leaderboard.cached_rows.is_empty():
		_board.set_status("CARREGANDO...")
	else:
		_board.set_rows(Leaderboard.cached_rows)

	if score <= 0:
		_set_status("PONTUACAO ZERO NAO E ENVIADA", Palette.TEXT_DIM)
		Leaderboard.fetch_top()
	else:
		_set_status("ENVIANDO PONTUACAO...", Palette.TEXT_DIM)
		Leaderboard.submit(GameState.nick, score, level, duration_ms)

	visible = true
	_layout_ui()


func _process(delta: float) -> void:
	_blink += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			if _again_button.has_point(button.position):
				accept_event()
				Sfx.play("ui_confirm")
				play_again_requested.emit()
			elif _menu_button.has_point(button.position):
				accept_event()
				Sfx.play("ui_back")
				menu_requested.emit()
		return

	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.keycode == KEY_ESCAPE:
			accept_event()
			Sfx.play("ui_back")
			menu_requested.emit()
		elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE:
			accept_event()
			Sfx.play("ui_confirm")
			play_again_requested.emit()


func _layout_ui() -> void:
	var cx := size.x * 0.5
	var board_height := _board.content_height()

	var content_height := (
		PixelFont.text_height(TITLE_SCALE) + 6.0
		+ PixelFont.text_height(1) + 8.0
		+ PixelFont.text_height(2) + 4.0
		+ PixelFont.text_height(1) + 8.0
		+ PixelFont.text_height(1) + 12.0
		+ BUTTON_SIZE.y + 14.0
		+ board_height
	)

	var y := maxf(floorf((size.y - content_height) * 0.5), 10.0)

	_title_y = y
	y += PixelFont.text_height(TITLE_SCALE) + 6.0
	_best_y = y
	y += PixelFont.text_height(1) + 8.0
	_score_y = y
	y += PixelFont.text_height(2) + 4.0
	_detail_y = y
	y += PixelFont.text_height(1) + 8.0
	_status_y = y
	y += PixelFont.text_height(1) + 12.0

	var total_buttons := BUTTON_SIZE.x * 2.0 + BUTTON_GAP
	_again_button = Rect2(floorf(cx - total_buttons * 0.5), y, BUTTON_SIZE.x, BUTTON_SIZE.y)
	_menu_button = Rect2(_again_button.end.x + BUTTON_GAP, y, BUTTON_SIZE.x, BUTTON_SIZE.y)
	y += BUTTON_SIZE.y + 14.0

	_board.position = Vector2(0.0, y)
	_board.size = Vector2(size.x, board_height)
	queue_redraw()


func _set_status(message: String, color: Color) -> void:
	_status = message
	_status_color = color
	queue_redraw()


func _on_submit_finished(ok: bool, message: String) -> void:
	if not visible:
		return
	_set_status(message, Palette.TJ_GOLD_LIGHT if ok else Palette.PADDLE_TIP)
	# Recarrega o ranking para o jogador ver a propria posicao.
	Leaderboard.fetch_top()


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

	PixelFont.draw_text_centered(self, cx + 2.0, _title_y + 2.0, "FIM DE JOGO", TITLE_SCALE, Color(0.0, 0.0, 0.0, 0.6))
	PixelFont.draw_text_centered(self, cx, _title_y, "FIM DE JOGO", TITLE_SCALE, Palette.PADDLE_TIP)

	if _is_local_best and fmod(_blink, 1.0) < 0.7:
		PixelFont.draw_text_centered(self, cx, _best_y, "NOVO RECORDE PESSOAL", 1, Palette.TEXT_ACCENT)

	PixelFont.draw_text_centered(self, cx, _score_y, TextUtil.pad_number(_final_score, 6), 2, Palette.TEXT)
	PixelFont.draw_text_centered(self, cx, _detail_y, "JOGADOR %s * FASE %d" % [
		NickUtil.for_display(GameState.nick), _final_level
	], 1, Palette.TEXT_DIM)

	if not _status.is_empty():
		PixelFont.draw_text_centered(self, cx, _status_y, _status, 1, _status_color)

	_draw_button(_again_button, "JOGAR DE NOVO", "ENTER")
	_draw_button(_menu_button, "MENU", "ESC")


func _draw_button(rect: Rect2, label: String, key_hint: String) -> void:
	var hover := rect.has_point(get_local_mouse_position())
	draw_rect(rect, Palette.TJ_BLUE if hover else Palette.FRAME_DARK, true)
	draw_rect(rect, Palette.TEXT_ACCENT if hover else Palette.FRAME_LIGHT, false, 1.0)

	PixelFont.draw_text_centered(self, rect.get_center().x, rect.position.y + 4.0, label, 1, Palette.TEXT)
	PixelFont.draw_text_centered(self, rect.get_center().x, rect.position.y + 13.0, key_hint, 1, Palette.TEXT_DIM)
