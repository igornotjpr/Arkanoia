## Construcao de fases a partir de mapas em texto. Codigo puro e testavel.
##
## Legenda dos mapas (11 colunas x 8 linhas):
##   '.'      celula vazia
##   '0'-'7'  bloco comum de 1 hp, cor da fileira indicada
##   'B'      bloco reforcado azul TJ-PR, 2 hp
##   'G'      bloco dourado TJ-PR, 2 hp, pontuacao alta
##
## A fase 1 desenha discretamente as letras "T" e "J" com blocos reforcados no
## meio da parede - o easter egg fica visivel apenas para quem presta atencao.
class_name LevelBuilder
extends RefCounted

const COLS := ArenaLayout.COLS
const ROWS := ArenaLayout.ROWS

const TYPE_NORMAL := 0
const TYPE_TJ_BLUE := 1
const TYPE_TJ_GOLD := 2

## Pontos base por fileira (topo vale mais, como no original).
const ROW_POINTS: Array[int] = [80, 70, 60, 50, 40, 30, 20, 10]

const TJ_BLUE_POINTS := 120
const TJ_GOLD_POINTS := 200

const LEVEL_1 := [
	"00000000000",
	"11111111111",
	"22BBB22BB22",
	"333B3333B33",
	"444B44BB444",
	"55555555555",
	"6G666666G66",
	"77777777777",
]

const LEVELS := [LEVEL_1]

## Mensagem exibida ao limpar a parede - o easter egg juridico do TJ-PR.
## Fica aqui, e nao na Arena, para ser conteudo de fase testavel sem SceneTree.
const CLEAR_MESSAGES: Array[String] = [
	"AUTOS BAIXADOS",
	"TRANSITADO EM JULGADO",
	"SENTENCA CUMPRIDA",
	"PAUTA LIMPA",
	"ACERVO ZERADO",
]


## Mensagem de fase concluida para o nivel informado.
static func clear_message(level: int) -> String:
	if CLEAR_MESSAGES.is_empty():
		return "FASE CONCLUIDA"
	return CLEAR_MESSAGES[posmod(maxi(level, 1) - 1, CLEAR_MESSAGES.size())]


## Numero de fases disponiveis.
static func level_count() -> int:
	return LEVELS.size()


## Mapa da fase pedida. Fases alem da ultima repetem a ultima (dificuldade sobe
## pela velocidade da bola, tratado em GameState).
static func map_for_level(level: int) -> Array:
	if LEVELS.is_empty():
		return []
	var index := clampi(level - 1, 0, LEVELS.size() - 1)
	return LEVELS[index]


## Constroi a lista de blocos da fase.
##
## Cada bloco e um Dictionary:
##   { id, col, row, hp, max_hp, type, color, points }
static func build(level: int) -> Array:
	var map := map_for_level(level)
	var bricks: Array = []
	var next_id := 0

	for row in range(min(ROWS, map.size())):
		var line: String = map[row]
		for col in range(min(COLS, line.length())):
			var symbol := line[col]
			if symbol == ".":
				continue

			var brick := {
				"id": next_id,
				"col": col,
				"row": row,
				"hp": 1,
				"max_hp": 1,
				"type": TYPE_NORMAL,
				"color": Palette.row_color(row),
				"points": _row_points(row),
			}

			match symbol:
				"B":
					brick["hp"] = 2
					brick["max_hp"] = 2
					brick["type"] = TYPE_TJ_BLUE
					brick["color"] = Palette.TJ_BLUE
					brick["points"] = TJ_BLUE_POINTS
				"G":
					brick["hp"] = 2
					brick["max_hp"] = 2
					brick["type"] = TYPE_TJ_GOLD
					brick["color"] = Palette.TJ_GOLD
					brick["points"] = TJ_GOLD_POINTS
				_:
					if symbol.is_valid_int():
						var color_index := symbol.to_int()
						brick["color"] = Palette.row_color(color_index)

			bricks.append(brick)
			next_id += 1

	return bricks


static func _row_points(row: int) -> int:
	if ROW_POINTS.is_empty():
		return 10
	return ROW_POINTS[clampi(row, 0, ROW_POINTS.size() - 1)]


## Soma de todos os pontos obtiveis na fase, sem contar combo nem bonus.
## Usado nos testes como sanidade de balanceamento.
static func max_base_score(level: int) -> int:
	var total := 0
	for brick in build(level):
		total += int(brick["points"])
	return total
