## Fonte bitmap 5x7 gerada em tempo de execucao.
##
## O jogo nao depende de nenhum arquivo de fonte: os glifos estao embutidos como
## 7 linhas de 5 caracteres e sao compilados uma unica vez num atlas de textura.
## Isso garante texto genuinamente pixelado (sem antialiasing) e mantem o
## repositorio livre de assets binarios.
##
## Uso:
##   PixelFont.draw_text(self, Vector2(8, 8), "SCORE 1200", 2, Palette.TEXT)
##   PixelFont.draw_text_centered(self, 320.0, 100.0, "PAUSE", 4, Palette.PAUSE_TEXT)
class_name PixelFont
extends RefCounted

const GLYPH_W := 5
const GLYPH_H := 7
const TRACKING := 1  # espaco entre glifos, em pixels de fonte

const GLYPHS := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#...#", "#.#.#", "##.##", "#...#"],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],

	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["#..#.", "#..#.", "#..#.", "#####", "...#.", "...#.", "...#."],
	"5": ["#####", "#....", "#....", "####.", "....#", "#...#", ".###."],
	"6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],

	" ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
	".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
	",": [".....", ".....", ".....", ".....", ".##..", ".##..", ".#..."],
	":": [".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."],
	";": [".....", ".##..", ".##..", ".....", ".##..", ".##..", ".#..."],
	"-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
	"_": [".....", ".....", ".....", ".....", ".....", ".....", "#####"],
	"!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
	"?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	"'": ["..#..", "..#..", ".....", ".....", ".....", ".....", "....."],
	"\"": [".#.#.", ".#.#.", ".....", ".....", ".....", ".....", "....."],
	"/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
	"\\": ["#....", "#....", ".#...", "..#..", "...#.", "....#", "....#"],
	"(": ["...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#."],
	")": [".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#..."],
	"[": ["..###", "..#..", "..#..", "..#..", "..#..", "..#..", "..###"],
	"]": ["###..", "..#..", "..#..", "..#..", "..#..", "..#..", "###.."],
	"<": ["...#.", "..#..", ".#...", "#....", ".#...", "..#..", "...#."],
	">": [".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#..."],
	"+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
	"=": [".....", ".....", "#####", ".....", "#####", ".....", "....."],
	"*": [".....", "#.#.#", ".###.", "#####", ".###.", "#.#.#", "....."],
	"%": ["#...#", "#..#.", "...#.", "..#..", ".#...", ".#..#", "#...#"],
	"#": [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", "....."],
	"@": [".###.", "#...#", "#.###", "#.#.#", "#.###", "#....", ".###."],
	"|": ["..#..", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
}

## Caractere usado quando o glifo pedido nao existe.
const FALLBACK_GLYPH := "?"

static var _texture: ImageTexture = null
static var _offsets: Dictionary = {}


## Atlas de glifos (construido no primeiro uso).
static func texture() -> ImageTexture:
	if _texture == null:
		_build()
	return _texture


## Largura em pixels de tela de um texto renderizado na escala dada.
static func text_width(text: String, scale: int = 1) -> int:
	if text.is_empty():
		return 0
	var glyphs := text.length()
	return (glyphs * GLYPH_W + (glyphs - 1) * TRACKING) * maxi(scale, 1)


## Altura em pixels de tela de uma linha na escala dada.
static func text_height(scale: int = 1) -> int:
	return GLYPH_H * maxi(scale, 1)


## Desenha o texto com o canto superior esquerdo em "pos".
static func draw_text(ci: CanvasItem, pos: Vector2, text: String, scale: int = 1, color: Color = Color.WHITE) -> void:
	if text.is_empty():
		return
	var tex := texture()
	var s := maxi(scale, 1)
	var advance := (GLYPH_W + TRACKING) * s
	var x := floorf(pos.x)
	var y := floorf(pos.y)
	var upper := text.to_upper()

	for i in upper.length():
		var ch := upper[i]
		if ch != " ":
			ci.draw_texture_rect_region(
				tex,
				Rect2(x, y, GLYPH_W * s, GLYPH_H * s),
				_region_for(ch),
				color
			)
		x += advance


## Desenha o texto centralizado horizontalmente em "center_x".
static func draw_text_centered(ci: CanvasItem, center_x: float, y: float, text: String, scale: int = 1, color: Color = Color.WHITE) -> void:
	draw_text(ci, Vector2(floorf(center_x - text_width(text, scale) * 0.5), y), text, scale, color)


## Desenha o texto alinhado a direita, terminando em "right_x".
static func draw_text_right(ci: CanvasItem, right_x: float, y: float, text: String, scale: int = 1, color: Color = Color.WHITE) -> void:
	draw_text(ci, Vector2(floorf(right_x - text_width(text, scale)), y), text, scale, color)


## True se o caractere tem glifo proprio (usado nos testes de cobertura).
static func has_glyph(ch: String) -> bool:
	return GLYPHS.has(ch.to_upper())


static func _region_for(ch: String) -> Rect2:
	if _offsets.is_empty():
		_build()
	var key := ch if _offsets.has(ch) else FALLBACK_GLYPH
	return Rect2(int(_offsets[key]), 0, GLYPH_W, GLYPH_H)


static func _build() -> void:
	var keys := GLYPHS.keys()
	keys.sort()

	var image := Image.create(keys.size() * GLYPH_W, GLYPH_H, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))

	_offsets = {}
	var cursor := 0
	var lit_color := Color(1.0, 1.0, 1.0, 1.0)

	for key in keys:
		var rows: Array = GLYPHS[key]
		_offsets[key] = cursor
		for row in mini(GLYPH_H, rows.size()):
			var line: String = rows[row]
			for col in mini(GLYPH_W, line.length()):
				if line[col] == "#":
					image.set_pixel(cursor + col, row, lit_color)
		cursor += GLYPH_W

	_texture = ImageTexture.create_from_image(image)
