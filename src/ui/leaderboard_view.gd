## Tabela do leaderboard global, compartilhada entre a tela de titulo e o fim de
## jogo.
##
## Formato de cada linha (29 caracteres, largura fixa em fonte monoespacada):
##   "01 IGOR........ 012500 30/07/26"
class_name LeaderboardView
extends Control

const MAX_ROWS := 10
const ROW_HEIGHT := 9.0
const HEADER_GAP := 5.0
const NICK_WIDTH := 10
const SCORE_DIGITS := 6

var title := "TOP 10 GLOBAL"
var rows: Array = []
var status := "CARREGANDO..."
var highlight_nick := ""
var highlight_score := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Altura total ocupada, para o layout da tela que hospeda a tabela.
func content_height() -> float:
	return PixelFont.text_height(1) + HEADER_GAP + MAX_ROWS * ROW_HEIGHT


## Largura de uma linha renderizada, usada para centralizar.
static func row_width() -> float:
	return PixelFont.text_width("00 ##########  000000 00/00/00", 1)


func set_rows(new_rows: Array) -> void:
	rows = new_rows
	status = ""
	queue_redraw()


func set_status(message: String) -> void:
	status = message
	queue_redraw()


## Destaca a linha do jogador atual (nick + pontuacao exatos).
func set_highlight(nick: String, score: int) -> void:
	highlight_nick = NickUtil.for_display(nick)
	highlight_score = score
	queue_redraw()


func _draw() -> void:
	var width := row_width()
	var left := floorf((size.x - width) * 0.5)
	var y := 0.0

	PixelFont.draw_text_centered(self, size.x * 0.5, y, title, 1, Palette.TEXT_ACCENT)
	y += PixelFont.text_height(1) + HEADER_GAP

	if not status.is_empty():
		PixelFont.draw_text_centered(self, size.x * 0.5, y + ROW_HEIGHT, status, 1, Palette.TEXT_DIM)
		return

	if rows.is_empty():
		PixelFont.draw_text_centered(self, size.x * 0.5, y + ROW_HEIGHT, "NENHUMA PONTUACAO AINDA", 1, Palette.TEXT_DIM)
		return

	for index in mini(rows.size(), MAX_ROWS):
		var row: Dictionary = rows[index]
		var nick := NickUtil.for_display(str(row.get("nick", "")))
		var score := int(row.get("score", 0))
		var is_player := nick == highlight_nick and score == highlight_score

		if is_player:
			draw_rect(Rect2(left - 3.0, y - 1.0, width + 6.0, ROW_HEIGHT), Palette.TJ_BLUE, true)

		var color := Palette.TEXT if is_player else _rank_color(index)
		var line := "%s %s  %s %s" % [
			str(index + 1).lpad(2, "0"),
			nick.rpad(NICK_WIDTH, "."),
			str(score).lpad(SCORE_DIGITS, "0"),
			TextUtil.format_iso_date(str(row.get("created_at", ""))),
		]
		PixelFont.draw_text(self, Vector2(left, y), line, 1, color)
		y += ROW_HEIGHT


## Ouro, prata e bronze para o podio; branco discreto para o resto.
static func _rank_color(index: int) -> Color:
	match index:
		0:
			return Palette.TJ_GOLD_LIGHT
		1:
			return Palette.PADDLE
		2:
			return Palette.lighten(Palette.PADDLE_TIP, 0.25)
		_:
			return Palette.TEXT_DIM
