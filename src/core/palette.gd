## Paleta fixa do jogo: pixel art anos 80 com acentos institucionais do TJ-PR.
##
## Todas as cores sao constantes para que o look nao dependa de recursos
## externos - o jogo inteiro roda sem nenhum asset binario.
class_name Palette
extends RefCounted

# --- Cenario -----------------------------------------------------------------
const BG := Color(0.055, 0.047, 0.086)          # #0E0C16
const PLAY_BG := Color(0.078, 0.070, 0.125)     # #141220
const FRAME_DARK := Color(0.141, 0.118, 0.220)  # #241E38
const FRAME_MID := Color(0.290, 0.247, 0.420)   # #4A3F6B
const FRAME_LIGHT := Color(0.431, 0.373, 0.627) # #6E5FA0

# --- Elementos ---------------------------------------------------------------
const BALL := Color(1.0, 1.0, 1.0)
const BALL_TRAIL := Color(0.702, 0.780, 1.0)
const PADDLE := Color(0.784, 0.831, 0.894)      # #C8D4E4
const PADDLE_DARK := Color(0.478, 0.541, 0.651) # #7A8AA6
const PADDLE_TIP := Color(0.878, 0.314, 0.235)  # #E0503C

# --- Texto -------------------------------------------------------------------
const TEXT := Color(0.957, 0.957, 0.973)        # #F4F4F8
const TEXT_DIM := Color(0.416, 0.392, 0.533)    # #6A6488
const TEXT_ACCENT := Color(0.941, 0.784, 0.282) # #F0C848

# --- Blocos especiais e capsulas ---------------------------------------------
const SPECIAL := Color(0.541, 0.451, 0.784)        # bloco que solta power-up
const SPECIAL_LIGHT := Color(0.720, 0.647, 0.910)
const SPAWN_TELEGRAPH := Color(0.941, 0.784, 0.282) # contorno do aviso previo

## TODAS as capsulas usam esta mesma base. O que distingue uma da outra e o
## sigilo de 5x3 pixels e uma variacao de tom de no maximo 6%, sem relacao com o
## efeito: a confusao e intencional, e so quem decora os sigilos passa a acertar.
##
## O tom e um osso quente, deliberadamente distante do azul frio da raquete e do
## branco da bola - uma capsula nunca se perde contra o que esta prestes a toca-la.
const CAPSULE := Color(0.839, 0.796, 0.643)
const CAPSULE_SIGIL := Color(0.180, 0.145, 0.106)

# --- Acentos TJ-PR -----------------------------------------------------------
const TJ_BLUE := Color(0.122, 0.306, 0.612)     # #1F4E9C
const TJ_BLUE_LIGHT := Color(0.259, 0.478, 0.804)
const TJ_GOLD := Color(0.784, 0.635, 0.290)     # #C8A24A
const TJ_GOLD_LIGHT := Color(0.925, 0.796, 0.451)

# --- Pause discreto (modo escritorio) ---------------------------------------
const PAUSE_BG := Color(1.0, 1.0, 1.0)
const PAUSE_TEXT := Color(0.741, 0.749, 0.780)  # cinza claro, quase invisivel
const PAUSE_HINT := Color(0.855, 0.859, 0.878)

# Botoes do menu de pause. Tons de cinza sobre branco: de longe a tela continua
# parecendo um documento, nao um jogo.
const PAUSE_BUTTON := Color(0.969, 0.973, 0.980)
const PAUSE_BUTTON_HOVER := Color(0.906, 0.914, 0.933)
const PAUSE_BUTTON_BORDER := Color(0.831, 0.839, 0.863)

## Cores das 8 fileiras padrao de blocos (indice 0 = fileira do topo).
const BRICK_ROWS: Array[Color] = [
	Color(0.878, 0.290, 0.235), # 0 vermelho  #E04A3C
	Color(0.941, 0.502, 0.251), # 1 laranja   #F08040
	Color(0.941, 0.784, 0.282), # 2 amarelo   #F0C848
	Color(0.345, 0.753, 0.353), # 3 verde     #58C05A
	Color(0.247, 0.682, 0.753), # 4 ciano     #3FAEC0
	Color(0.290, 0.498, 0.878), # 5 azul      #4A7FE0
	Color(0.604, 0.373, 0.816), # 6 roxo      #9A5FD0
	Color(0.722, 0.753, 0.800), # 7 prata     #B8C0CC
]

## Clareia uma cor para o chanfro superior/esquerdo do bloco.
static func lighten(c: Color, amount: float = 0.35) -> Color:
	return c.lerp(Color(1.0, 1.0, 1.0), amount)

## Escurece uma cor para o chanfro inferior/direito do bloco.
static func darken(c: Color, amount: float = 0.40) -> Color:
	return c.lerp(Color(0.0, 0.0, 0.0), amount)

## Cor da fileira, com wrap seguro caso o indice exceda a paleta.
static func row_color(index: int) -> Color:
	if BRICK_ROWS.is_empty():
		return TEXT
	return BRICK_ROWS[posmod(index, BRICK_ROWS.size())]
