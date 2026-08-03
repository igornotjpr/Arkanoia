## Construcao de fases a partir de mapas em texto. Codigo puro e testavel.
##
## Legenda dos mapas:
##   '.'      celula vazia
##   '0'-'7'  bloco comum de 1 hp, cor da fileira indicada
##   'B'      bloco reforcado azul TJ-PR, 2 hp
##   'G'      bloco dourado TJ-PR, 2 hp, pontuacao alta
##   'S'      bloco especial, 2 hp, solta uma capsula de power-up ao morrer
##
## O MAPA E A DECLARACAO DA GEOMETRIA
## ----------------------------------
## Ate a v2.2.0 toda fase era 11x8, porque a largura do bloco era a constante
## ArenaLayout.BRICK_WIDTH = 50, que so fecha em pixel exato com 11 colunas. Agora
## a largura e derivada (ArenaLayout.brick_width), entao cada fase pode ter a sua
## dimensao - e ela nao e declarada em lugar nenhum: sai do proprio desenho, com
## rows = numero de linhas e cols = comprimento da linha. Um mapa e sua unica
## fonte de verdade, e nao ha como o desenho e a dimensao divergirem.
##
## Quem garante que os mapas sao retangulares e cabem nos limites e o teste, via
## map_is_valid() - ver _test_level_builder.
##
## A fase 1 desenha discretamente as letras "T" e "J" com blocos reforcados no
## meio da parede - o easter egg fica visivel apenas para quem presta atencao.
class_name LevelBuilder
extends RefCounted

const TYPE_NORMAL := 0
const TYPE_TJ_BLUE := 1
const TYPE_TJ_GOLD := 2

## Bloco especial declarado no mapa, em posicao fixa desde o inicio da partida.
const TYPE_SPECIAL := 3

## Bloco especial que materializa durante a fase. Nao aparece em mapa nenhum:
## quem o cria e SpecialBricks.make_brick, em tempo de jogo.
const TYPE_SPECIAL_SPAWNED := 4

## Pontos base por fileira (topo vale mais, como no original).
##
## Tem 8 entradas de proposito, mesmo com fases de ate 10 fileiras: as fileiras
## extras ficam no VALOR MINIMO. Elas sao as mais baixas e portanto as mais faceis
## de acertar, entao dar a elas uma faixa de pontos propria premiaria o alvo mais
## simples da parede.
const ROW_POINTS: Array[int] = [80, 70, 60, 50, 40, 30, 20, 10]

const TJ_BLUE_POINTS := 120
const TJ_GOLD_POINTS := 200

const SPECIAL_HP := 2
const SPECIAL_POINTS := 150

## Simbolos aceitos num mapa. Existe para map_is_valid() pegar um caractere
## digitado errado, que build() trataria como bloco comum sem reclamar.
const SYMBOLS := [".", "0", "1", "2", "3", "4", "5", "6", "7", "B", "G", "S"]

## Os dois 'S' ocupam o lugar de blocos comuns nas pontas, longe das colunas que
## desenham o "T" e o "J" com blocos reforcados - o easter egg fica intacto.
##
## 11x8, e assim tem que continuar: e a fase que ja esta no ar desde a v1.0.0, e as
## assercoes de 88 blocos e 5220 pontos sao a prova de que liberar a geometria nao
## mexeu no que ja existia.
const LEVEL_1 := [
	"00000000000",
	"11111111111",
	"22BBB22BB22",
	"S33B3333B33",
	"444B44BB444",
	"5555555555S",
	"6G666666G66",
	"77777777777",
]

## ARCO - 11x8. Nave de catedral: o centro e oco e os pilares sao grossos. A bola
## entra pelas laterais do topo e passa a ricochetear dentro do vao.
const LEVEL_ARCO := [
	"...BBBBB...",
	"..1111111..",
	".22.....22.",
	"33.......33",
	"44.......44",
	"S5.......5S",
	"66.......66",
	"GG.......GG",
]

## FUNIL - 13x9. Losango: denso no topo, afunilando ate o dourado no meio, e com
## duas torres reforcadas embaixo para a fase nao terminar sozinha.
const LEVEL_FUNIL := [
	"0000000000000",
	".11111111111.",
	"..222222222..",
	"...3333333...",
	"....44444....",
	".....SGS.....",
	"....66666....",
	"...7777777...",
	"..BB.....BB..",
]

## FORTALEZA - 11x9. Dois aneis em volta de um nucleo dourado. E a unica fase em
## que a ordem importa: da para entrar pelos portoes, mas o ouro so cai depois de
## abrir caminho ate o centro.
##
## Os aneis tem VAOS de proposito. Fechados, o soak levava 300s em paisagem contra
## 242s da fase 1: a bola gastava a partida inteira raspando a muralha externa sem
## nunca alcancar o miolo. Os portoes deixam a bola entrar cedo e transformam a
## fase em navegacao, que era a ideia, em vez de escavacao.
const LEVEL_FORTALEZA := [
	"BBBB...BBBB",
	"B.........B",
	"B.33...33.B",
	"B.3.....3.B",
	"B.3.GGG.3.B",
	"B.3.....3.B",
	"B.33...33.B",
	"B.........B",
	"SBBB...BBBS",
]

## CORREDOR - 7x10. A parede mais estreita e mais alta do jogo. Com 7 colunas o
## bloco fica com 79 px de largura, entao cada acerto conta muito mais.
const LEVEL_CORREDOR := [
	"BBBBBBB",
	"0000000",
	"11...11",
	"S22222S",
	"33...33",
	"4444444",
	"55...55",
	"G66666G",
	"77...77",
	"BBBBBBB",
]

## CHUVA - 15x8. Faixas diagonais na parede mais larga do jogo. Os blocos ficam com
## 36 px, e as diagonais mantem trechos continuos - diferente de um xadrez, onde
## cada bloco seria uma ilha e a bola passaria a vida inteira pelos vaos.
const LEVEL_CHUVA := [
	".000.000.000.00",
	"111.111.111.111",
	"S2.222.222.222.",
	"3.333.333.333.3",
	".GG4.444.444.44",
	"555.555.555.55S",
	"66.666.666.666.",
	"7.777.777.777.7",
]

## A ordem e a progressao: a classica, uma fase arejada para o jogador respirar,
## e dai subindo em densidade ate a fortaleza. Depois da ultima a lista ROTACIONA
## (ver map_for_level) - a dificuldade continua subindo pela velocidade da bola.
const LEVELS := [
	LEVEL_1,
	LEVEL_ARCO,
	LEVEL_FUNIL,
	LEVEL_FORTALEZA,
	LEVEL_CORREDOR,
	LEVEL_CHUVA,
]

## Barreiras moveis por fase, em CELULAS da grade - nunca em pixels.
##
## Declarar em celula e o que faz a barreira sobreviver a rotacao de tela de graca,
## do mesmo jeito que os blocos: quem converte para pixel e Movers.rect_for, a
## partir do layout do momento.
##
## Toda barreira patrulha um trecho VAZIO do mapa. Nao e decoracao da regra: uma
## barra sobreposta a um bloco deixaria a bola quicando entre os dois num espaco
## menor que ela, e a resolucao por menor penetracao a expulsaria para um lado
## imprevisivel. O teste confere celula por celula.
##
## A fase 1 nao tem barreira de proposito: e a parede que esta no ar desde a
## v1.0.0, e a abertura do jogo continua sendo o Arkanoid classico.
const MOVERS := {
	2: [{"row": 4, "col_min": 2, "col_max": 8, "speed": 62.0, "t": 0.0}],
	4: [{"row": 7, "col_min": 1, "col_max": 9, "speed": 74.0, "t": 0.5}],
	5: [{"row": 4, "col_min": 2, "col_max": 4, "speed": 48.0, "t": 0.0}],
}


## Especificacoes das barreiras da fase, ja considerando a rotacao dos mapas.
static func movers_for_level(level: int) -> Array:
	if LEVELS.is_empty():
		return []
	var index := posmod(maxi(level, 1) - 1, LEVELS.size()) + 1
	return MOVERS.get(index, [])


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


## Mapa da fase pedida. Depois da ultima a lista ROTACIONA, no mesmo padrao que
## clear_message ja usa - antes disto um clampi travava na ultima fase e o jogo
## repetia o mesmo mapa para sempre.
static func map_for_level(level: int) -> Array:
	if LEVELS.is_empty():
		return []
	return LEVELS[posmod(maxi(level, 1) - 1, LEVELS.size())]


## Numero de colunas e de linhas da fase, lidos do proprio mapa.
static func dimensions(level: int) -> Vector2i:
	return map_dimensions(map_for_level(level))


static func map_dimensions(map: Array) -> Vector2i:
	if map.is_empty():
		return Vector2i.ZERO
	return Vector2i(String(map[0]).length(), map.size())


static func cols(level: int) -> int:
	return dimensions(level).x


static func rows(level: int) -> int:
	return dimensions(level).y


## True quando o mapa e retangular e cabe nos limites de geometria.
##
## Nao e chamada por build(): e o TESTE que a roda sobre LEVELS inteiro. Deixar a
## validacao fora do caminho quente e deliberado - um mapa torto e erro de quem
## escreveu a fase, e tem que quebrar a suite, nao degradar em silencio no jogo.
static func map_is_valid(map: Array) -> bool:
	var dims := map_dimensions(map)
	if dims.x < ArenaLayout.MIN_COLS or dims.x > ArenaLayout.MAX_COLS:
		return false
	if dims.y < ArenaLayout.MIN_ROWS or dims.y > ArenaLayout.MAX_ROWS:
		return false

	for line in map:
		var text := String(line)
		if text.length() != dims.x:
			return false
		for index in text.length():
			if not SYMBOLS.has(text[index]):
				return false

	return true


## Constroi a lista de blocos da fase.
##
## Cada bloco e um Dictionary:
##   { id, col, row, hp, max_hp, type, color, points }
static func build(level: int) -> Array:
	var map := map_for_level(level)
	var bricks: Array = []
	var next_id := 0

	# A dimensao vem do mapa, nao de constante: e o que permite fases de 7x10 e
	# 15x8 conviverem na mesma lista.
	for row in range(map.size()):
		var line: String = map[row]
		for col in range(line.length()):
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
				"S":
					brick["hp"] = SPECIAL_HP
					brick["max_hp"] = SPECIAL_HP
					brick["type"] = TYPE_SPECIAL
					brick["color"] = Palette.SPECIAL
					brick["points"] = SPECIAL_POINTS
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
