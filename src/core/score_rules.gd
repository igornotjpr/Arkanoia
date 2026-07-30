## Regras de pontuacao. Codigo puro e testavel.
##
## O combo conta blocos destruidos em sequencia sem que a bola toque a raquete -
## recompensa quem consegue manter a bola presa na parede de blocos.
class_name ScoreRules
extends RefCounted

const COMBO_STEP := 0.25
const COMBO_MAX := 4.0

const STARTING_LIVES := 3
const MAX_LIVES := 5

const LIFE_BONUS := 500
const LEVEL_CLEAR_BONUS := 1000

## Teto do bonus de fase. Sem o teto, o bonus cresceria sem limite com o nivel e
## quebraria o CHECK de plausibilidade do schema (pontos por segundo de partida).
const LEVEL_CLEAR_BONUS_CAP := 5000

## Limite superior aceito pelo leaderboard. Precisa bater com o CHECK do
## schema SQL no Supabase (ver supabase/schema.sql).
const MAX_VALID_SCORE := 999999


## Multiplicador do combo. 0 ou 1 bloco -> 1.0; cresce 0.25 por bloco extra.
static func combo_multiplier(combo: int) -> float:
	if combo <= 1:
		return 1.0
	return minf(1.0 + (combo - 1) * COMBO_STEP, COMBO_MAX)


## Pontos concedidos ao destruir um bloco, ja com o combo aplicado.
static func brick_points(base_points: int, combo: int) -> int:
	return int(round(base_points * combo_multiplier(combo)))


## Pontos concedidos ao apenas trincar um bloco reforcado (sem destruir).
static func chip_points(base_points: int) -> int:
	return int(round(base_points * 0.25))


## Bonus por limpar a fase, proporcional as vidas restantes.
static func level_clear_bonus(level: int, lives_left: int) -> int:
	var level_part := mini(LEVEL_CLEAR_BONUS * maxi(level, 1), LEVEL_CLEAR_BONUS_CAP)
	return level_part + LIFE_BONUS * maxi(lives_left, 0)


## Velocidade da bola para uma fase, antes da escala de layout.
## Sobe de forma suave e satura, para a fase nunca virar ingogavel.
static func ball_speed_for_level(level: int) -> float:
	return minf(200.0 + (maxi(level, 1) - 1) * 18.0, 340.0)


## Aceleracao progressiva dentro da fase: a bola ganha velocidade conforme a
## parede vai sendo destruida.
static func ball_speed_multiplier(bricks_destroyed: int, bricks_total: int) -> float:
	if bricks_total <= 0:
		return 1.0
	var progress := clampf(float(bricks_destroyed) / float(bricks_total), 0.0, 1.0)
	return 1.0 + progress * 0.35


## Placar valido para envio ao leaderboard.
static func is_valid_score(score: int) -> bool:
	return score >= 0 and score <= MAX_VALID_SCORE
