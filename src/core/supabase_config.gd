## Configuracao do Supabase e construcao de URLs. Codigo puro e testavel.
##
## A chave abaixo e "publishable" (sb_publishable_*): ela e projetada para viver
## no cliente e nao concede nada alem do que as politicas de RLS permitirem. A
## seguranca do leaderboard vem do schema em supabase/schema.sql, nao do sigilo
## da chave.
##
## NUNCA coloque aqui a connection string do Postgres nem uma service_role key -
## o build web e publico e qualquer pessoa consegue ler estes valores.
##
## Em web, a pagina hospedeira pode sobrescrever URL e chave definindo
##   window.ARKANOIA_SUPABASE_URL / window.ARKANOIA_SUPABASE_KEY
## antes de carregar o jogo (ver Leaderboard._apply_web_overrides).
class_name SupabaseConfig
extends RefCounted

const URL := "https://aqcpaqjvsdsyxlmnbvav.supabase.co"
const PUBLISHABLE_KEY := "sb_publishable_yRwdXckFR-clBV2iinYodw_Ln8xCRNr"

## Tabela de escrita. O cliente so tem privilegio de INSERT nela.
const TABLE := "scores"

## View de leitura: a melhor pontuacao de cada nick, para um unico jogador nao
## ocupar as dez posicoes do ranking (ver supabase/schema.sql).
const READ_VIEW := "leaderboard"

const TOP_LIMIT := 10
const TIMEOUT_SECONDS := 8.0


## Endpoint REST de uma tabela ou view.
static func table_url(base_url: String, table: String = TABLE) -> String:
	return "%s/rest/v1/%s" % [base_url.rstrip("/"), table]


## URL de consulta do top N, ordenado por pontuacao e, em empate, pelo envio mais antigo.
static func top_scores_url(base_url: String, view: String = READ_VIEW, limit: int = TOP_LIMIT) -> String:
	var safe_limit := clampi(limit, 1, 100)
	return "%s?select=nick,score,created_at&order=score.desc,created_at.asc&limit=%d" % [
		table_url(base_url, view), safe_limit
	]


## Cabecalhos comuns. A chave publishable vai em "apikey" e tambem como Bearer,
## que e o formato aceito pelo PostgREST do Supabase.
static func headers(key: String, extra: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var result := PackedStringArray([
		"apikey: " + key,
		"Authorization: Bearer " + key,
		"Accept: application/json",
		"Content-Type: application/json",
	])
	result.append_array(extra)
	return result


## Corpo do POST de envio de pontuacao.
static func submit_body(nick: String, score: int, level: int, duration_ms: int) -> String:
	return JSON.stringify({
		"nick": NickUtil.to_submittable(nick),
		"score": clampi(score, 0, ScoreRules.MAX_VALID_SCORE),
		"level": maxi(level, 1),
		"duration_ms": maxi(duration_ms, 0),
	})


## True se a configuracao parece utilizavel (evita requisicoes obviamente furadas).
static func is_configured(base_url: String, key: String) -> bool:
	return base_url.begins_with("https://") and key.length() > 20
