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


## Quantas bolas o jogador pode apostar num lancamento, dadas as vidas que tem.
##
## Mora aqui, e nao na Arena, porque carrega um invariante de seguranca que
## merece prova: apostar N custa N-1 vidas, entao o teto min(vidas, bolas)
## garante que SOBRA pelo menos uma vida depois de pagar. Sem isso, uma aposta
## grande daria fim de partida no proprio lancamento - a bola sairia da raquete e
## a corrida ja estaria encerrada.
##
## Com uma vida so o teto e 1, que e exatamente "nao da para apostar".
static func max_stake(lives: int, ball_cap: int) -> int:
	return clampi(mini(lives, ball_cap), 1, maxi(ball_cap, 1))


## Vidas cobradas por uma aposta de "stake" bolas.
static func stake_cost(stake: int) -> int:
	return maxi(stake - 1, 0)

const LIFE_BONUS := 500
const LEVEL_CLEAR_BONUS := 1000

## Teto do bonus de fase. Sem o teto, o bonus cresceria sem limite com o nivel e
## quebraria o CHECK de plausibilidade do schema (pontos por segundo de partida).
##
## Subiu de 5000 para 8000 na v2.3.0, junto com a rotacao de mapas: saturar na fase
## 5 fazia a 6a fase em diante pagar o mesmo que a 5a, e o bonus deixava de premiar
## quem foi longe. Continua bem abaixo de PLAUSIBLE_BASE, entao o pagamento maximo
## (8000 + 5 vidas * 500 = 10500) cabe com folga no termo aditivo do teto.
const LEVEL_CLEAR_BONUS_CAP := 8000

## Limite superior aceito pelo leaderboard. Precisa bater com o CHECK do
## schema SQL no Supabase (ver supabase/schema.sql).
const MAX_VALID_SCORE := 999999

## Teto de plausibilidade do servidor, espelhado pelo CHECK scores_plausible em
## supabase/schema.sql. Estas constantes sao a FONTE UNICA: o teste
## _test_schema_mirror le o SQL e falha se os numeros divergirem. Antes da v1.2.0
## eles estavam escritos a mao em tres lugares e nada impedia a deriva.
##
## A derivacao do 2400 esta em supabase/migrations/001_teto_plausibilidade.sql.
const PLAUSIBLE_POINTS_PER_SECOND := 2400
const PLAUSIBLE_BASE := 20000

## Multiplicador de risco dos power-ups. Cada nivel de risco vale 35% a mais.
const RISK_STEP := 0.35
const RISK_MULTIPLIER_MIN := 0.80
const RISK_MULTIPLIER_MAX := 2.50

## Pontos por apanhar uma capsula, por nivel (comum, raro), antes do risco.
const CAPSULE_POINTS: Array[int] = [120, 300]


## Multiplicador do combo. 0 ou 1 bloco -> 1.0; cresce 0.25 por bloco extra.
static func combo_multiplier(combo: int) -> float:
	if combo <= 1:
		return 1.0
	return minf(1.0 + (combo - 1) * COMBO_STEP, COMBO_MAX)


## Multiplicador de risco: quem aceita jogar com a raquete curta, a bola rapida ou
## o campo mentindo ganha mais por bloco.
##
## Itens benignos tem risco NEGATIVO, entao acumular so vantagem reduz o que se
## ganha. E isso que impede LUCIDEZ + CALMA de virar escolha obvia e mantem a
## decisao de apanhar uma capsula sendo, de fato, uma decisao.
static func risk_multiplier(risk_level: int) -> float:
	return clampf(1.0 + risk_level * RISK_STEP, RISK_MULTIPLIER_MIN, RISK_MULTIPLIER_MAX)


## Pontos concedidos ao destruir um bloco, ja com o combo e o risco aplicados.
##
## Os dois multiplicadores sao independentes de proposito: o combo premia pericia
## no instante (blocos em sequencia sem tocar a raquete), o risco premia uma
## decisao assumida que dura a fase inteira.
static func brick_points(base_points: int, combo: int, risk_level: int = 0) -> int:
	return int(round(base_points * combo_multiplier(combo) * risk_multiplier(risk_level)))


## Pontos por apanhar uma capsula, ja com o risco aplicado. Apanhar uma capsula
## rara ja estando amaldicoado e a jogada que mais paga no jogo.
static func capsule_points(tier: int, risk_level: int = 0) -> int:
	if CAPSULE_POINTS.is_empty():
		return 0
	var base := CAPSULE_POINTS[clampi(tier, 0, CAPSULE_POINTS.size() - 1)]
	return int(round(base * risk_multiplier(risk_level)))


## Teto que o servidor aceita para uma partida da duracao informada.
static func plausible_ceiling(duration_seconds: int) -> int:
	return PLAUSIBLE_POINTS_PER_SECOND * maxi(duration_seconds, 1) + PLAUSIBLE_BASE


## Pontos concedidos ao apenas trincar um bloco reforcado (sem destruir).
static func chip_points(base_points: int) -> int:
	return int(round(base_points * 0.25))


## Bonus por limpar a fase, proporcional as vidas restantes.
static func level_clear_bonus(level: int, lives_left: int) -> int:
	var level_part := mini(LEVEL_CLEAR_BONUS * maxi(level, 1), LEVEL_CLEAR_BONUS_CAP)
	return level_part + LIFE_BONUS * maxi(lives_left, 0)


## Velocidade da bola para uma fase, antes da escala de layout.
## Sobe de forma suave e satura, para a fase nunca virar ingogavel.
##
## O passo subiu de 18 para 20 e o teto de 340 para 380 na v2.3.0: com uma fase so,
## saturar na 9 nao tinha custo, mas com a rotacao de mapas o jogador chega bem
## alem disso e o jogo parava de mudar. O teto continua existindo - depois dele a
## variacao vem da forma da parede, nao da velocidade.
static func ball_speed_for_level(level: int) -> float:
	return minf(200.0 + (maxi(level, 1) - 1) * 20.0, 380.0)


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
