## Faixa de informacoes no topo da tela.
##
## Desenhada com PixelFont e retangulos - nenhum Label, para manter o alinhamento
## em pixels exatos. O botao de pause fica no canto direito, deliberadamente
## discreto (dois tracinhos cinza), e existe sobretudo para o mobile, onde nao ha
## tecla P.
class_name Hud
extends Control

signal pause_pressed

const LABEL_Y := 4.0
const VALUE_Y := 13.0
const MARGIN := 10.0

const LIFE_ICON_W := 11.0
const LIFE_ICON_H := 4.0
const LIFE_ICON_GAP := 3.0

const PAUSE_BUTTON_SIZE := 20.0

var _pause_rect := Rect2()
var _pause_hover := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# TOP_WIDE ancora a largura na viewport; a altura vem do offset inferior.
	# Escrever em size.y aqui seria sobrescrito pelo layout apos o _ready().
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = ArenaLayout.HUD_HEIGHT

	GameState.score_changed.connect(func(_v: int) -> void: queue_redraw())
	GameState.lives_changed.connect(func(_v: int) -> void: queue_redraw())
	GameState.level_changed.connect(func(_v: int) -> void: queue_redraw())
	GameState.combo_changed.connect(func(_v: int) -> void: queue_redraw())


func _process(_delta: float) -> void:
	# O retangulo do botao depende da largura, que muda com a viewport.
	var new_rect := Rect2(size.x - MARGIN - PAUSE_BUTTON_SIZE, 5.0, PAUSE_BUTTON_SIZE, PAUSE_BUTTON_SIZE)
	if new_rect != _pause_rect:
		_pause_rect = new_rect
		queue_redraw()

	var hover := _pause_rect.has_point(get_local_mouse_position())
	if hover != _pause_hover:
		_pause_hover = hover
		queue_redraw()


## Chamado pelo Main: o HUD ignora o mouse para nao roubar o movimento da
## raquete, entao o clique no botao de pause e testado explicitamente.
func try_press_pause(viewport_position: Vector2) -> bool:
	if not _pause_rect.has_point(viewport_position - global_position):
		return false
	pause_pressed.emit()
	return true


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, size.x, ArenaLayout.HUD_HEIGHT), Palette.BG, true)
	draw_rect(Rect2(0.0, ArenaLayout.HUD_HEIGHT - 1.0, size.x, 1.0), Palette.FRAME_DARK, true)

	_draw_left_group()
	_draw_right_group()
	_draw_pause_button()


func _draw_left_group() -> void:
	var x := MARGIN
	PixelFont.draw_text(self, Vector2(x, LABEL_Y), "JOGADOR", 1, Palette.TEXT_DIM)
	var nick := NickUtil.for_display(GameState.nick)
	PixelFont.draw_text(self, Vector2(x, VALUE_Y), nick, 1, Palette.TEXT)

	x += maxf(PixelFont.text_width("JOGADOR", 1), PixelFont.text_width(nick, 1)) + 22.0
	PixelFont.draw_text(self, Vector2(x, LABEL_Y), "PONTOS", 1, Palette.TEXT_DIM)
	PixelFont.draw_text(self, Vector2(x, VALUE_Y - 1.0), TextUtil.pad_number(GameState.score, 6), 2, Palette.TEXT)


func _draw_right_group() -> void:
	var right := size.x - MARGIN - PAUSE_BUTTON_SIZE - 12.0

	# Vidas restantes, desenhadas como raquetinhas.
	var lives_w := GameState.lives * LIFE_ICON_W + maxi(GameState.lives - 1, 0) * LIFE_ICON_GAP
	var lives_x := right - maxf(lives_w, PixelFont.text_width("VIDAS", 1))
	PixelFont.draw_text(self, Vector2(lives_x, LABEL_Y), "VIDAS", 1, Palette.TEXT_DIM)
	for i in GameState.lives:
		var icon_x := lives_x + i * (LIFE_ICON_W + LIFE_ICON_GAP)
		draw_rect(Rect2(icon_x, VALUE_Y + 2.0, LIFE_ICON_W, LIFE_ICON_H), Palette.PADDLE, true)
		draw_rect(Rect2(icon_x, VALUE_Y + 2.0, 2.0, LIFE_ICON_H), Palette.PADDLE_TIP, true)
		draw_rect(Rect2(icon_x + LIFE_ICON_W - 2.0, VALUE_Y + 2.0, 2.0, LIFE_ICON_H), Palette.PADDLE_TIP, true)

	var level_text := TextUtil.pad_number(GameState.level, 2)
	var level_x := lives_x - 26.0 - maxf(PixelFont.text_width("FASE", 1), PixelFont.text_width(level_text, 1))
	PixelFont.draw_text(self, Vector2(level_x, LABEL_Y), "FASE", 1, Palette.TEXT_DIM)
	PixelFont.draw_text(self, Vector2(level_x, VALUE_Y), level_text, 1, Palette.TEXT_ACCENT)

	var best_text := TextUtil.pad_number(GameState.best_score, 6)
	var best_x := level_x - 26.0 - maxf(PixelFont.text_width("RECORDE", 1), PixelFont.text_width(best_text, 1))
	if best_x > 200.0:
		PixelFont.draw_text(self, Vector2(best_x, LABEL_Y), "RECORDE", 1, Palette.TEXT_DIM)
		PixelFont.draw_text(self, Vector2(best_x, VALUE_Y), best_text, 1, Palette.TEXT)


func _draw_pause_button() -> void:
	var color := Palette.TEXT if _pause_hover else Palette.TEXT_DIM
	var cx := _pause_rect.position.x + _pause_rect.size.x * 0.5
	var cy := _pause_rect.position.y + _pause_rect.size.y * 0.5
	draw_rect(Rect2(cx - 4.0, cy - 5.0, 3.0, 10.0), color, true)
	draw_rect(Rect2(cx + 1.0, cy - 5.0, 3.0, 10.0), color, true)
