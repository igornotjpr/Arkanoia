## Cliente do leaderboard global.
##
## Autoload: Leaderboard
##
## Esta e a UNICA camada que conhece o transporte. O jogo so usa
## fetch_top() / submit() e os sinais - trocar o REST direto por uma Edge
## Function de validacao (etapa 2 do plano antifraude) nao exige mexer em mais
## nada. Ver README, secao "Endurecer o leaderboard".
extends Node

signal top_scores_received(rows: Array)
signal top_scores_failed(message: String)
signal submit_finished(ok: bool, message: String)

const MAX_ROWS := 10

## Nomes dos codigos de HTTPRequest.Result. Sem isso, toda falha de transporte
## vira um "SEM CONEXAO" indistinguivel, e nao ha como diferenciar DNS, TLS e
## timeout ao depurar em producao.
const RESULT_NAMES := {
	HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH: "CORPO INCONSISTENTE",
	HTTPRequest.RESULT_CANT_CONNECT: "NAO CONECTOU",
	HTTPRequest.RESULT_CANT_RESOLVE: "DNS FALHOU",
	HTTPRequest.RESULT_CONNECTION_ERROR: "ERRO DE CONEXAO",
	HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "FALHA DE TLS",
	HTTPRequest.RESULT_NO_RESPONSE: "SEM RESPOSTA",
	HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: "RESPOSTA GRANDE DEMAIS",
	HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED: "FALHA AO DESCOMPRIMIR",
	HTTPRequest.RESULT_REQUEST_FAILED: "REQUISICAO FALHOU",
	HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN: "ARQUIVO INACESSIVEL",
	HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR: "ERRO DE ESCRITA",
	HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: "REDIRECIONOU DEMAIS",
	HTTPRequest.RESULT_TIMEOUT: "TEMPO ESGOTADO",
}

var base_url := SupabaseConfig.URL
var api_key := SupabaseConfig.PUBLISHABLE_KEY

## Ultimo top baixado com sucesso, para exibir algo mesmo offline.
var cached_rows: Array = []
var last_error := ""

var _fetch_request: HTTPRequest
var _submit_request: HTTPRequest
var _fetching := false
var _submitting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_web_overrides()

	_fetch_request = _make_request(_on_fetch_completed)
	_submit_request = _make_request(_on_submit_completed)


## True enquanto houver requisicao em voo (a UI usa para mostrar "CARREGANDO").
func is_busy() -> bool:
	return _fetching or _submitting


## Baixa o top N. Emite top_scores_received ou top_scores_failed.
func fetch_top(limit: int = MAX_ROWS) -> void:
	if _fetching:
		return
	if not SupabaseConfig.is_configured(base_url, api_key):
		_fail_fetch("LEADERBOARD NAO CONFIGURADO")
		return

	_fetching = true
	var url := SupabaseConfig.top_scores_url(base_url, SupabaseConfig.READ_VIEW, limit)
	var error := _fetch_request.request(url, SupabaseConfig.headers(api_key), HTTPClient.METHOD_GET)
	if error != OK:
		_fetching = false
		_fail_fetch("FALHA DE REDE (%d)" % error)


## Envia a pontuacao da partida. Emite submit_finished.
func submit(nick: String, score: int, level: int, duration_ms: int) -> void:
	if _submitting:
		return
	if not ScoreRules.is_valid_score(score):
		submit_finished.emit(false, "PONTUACAO INVALIDA")
		return
	if not SupabaseConfig.is_configured(base_url, api_key):
		submit_finished.emit(false, "LEADERBOARD NAO CONFIGURADO")
		return

	_submitting = true
	var url := SupabaseConfig.table_url(base_url)
	var headers := SupabaseConfig.headers(api_key, PackedStringArray(["Prefer: return=minimal"]))
	var body := SupabaseConfig.submit_body(nick, score, level, duration_ms)
	var error := _submit_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		_submitting = false
		submit_finished.emit(false, "FALHA DE REDE (%d)" % error)


func _make_request(callback: Callable) -> HTTPRequest:
	var request := HTTPRequest.new()
	request.process_mode = Node.PROCESS_MODE_ALWAYS
	request.timeout = SupabaseConfig.TIMEOUT_SECONDS
	request.use_threads = not OS.has_feature("web")
	# No build web quem faz a requisicao e o fetch() do navegador, que ja entrega
	# o corpo descomprimido - mas continua expondo o cabecalho "Content-Encoding:
	# gzip" que a Cloudflare do Supabase manda. Com accept_gzip ligado, o Godot
	# acredita no cabecalho e tenta descomprimir JSON puro, o que falha com
	# RESULT_BODY_DECOMPRESS_FAILED e derruba o ranking inteiro. Fora da web o
	# Godot fala HTTP direto e a descompressao e legitima.
	request.accept_gzip = not OS.has_feature("web")
	add_child(request)
	request.request_completed.connect(callback)
	return request


func _on_fetch_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_fetching = false

	if result != HTTPRequest.RESULT_SUCCESS:
		_fail_fetch(result_name(result))
		return
	if response_code < 200 or response_code >= 300:
		_fail_fetch("ERRO %d NO SERVIDOR" % response_code)
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Array):
		_fail_fetch("RESPOSTA INVALIDA")
		return

	cached_rows = _normalize_rows(parsed)
	last_error = ""
	top_scores_received.emit(cached_rows)


func _on_submit_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_submitting = false

	if result != HTTPRequest.RESULT_SUCCESS:
		submit_finished.emit(false, result_name(result))
		return
	if response_code >= 200 and response_code < 300:
		submit_finished.emit(true, "PONTUACAO ENVIADA")
		return

	# 429 vem do rate limit por IP definido no schema; a mensagem e amigavel.
	if response_code == 429:
		submit_finished.emit(false, "MUITOS ENVIOS, AGUARDE")
		return

	var detail := body.get_string_from_utf8()
	push_warning("Arkanoia: falha ao enviar pontuacao (%d): %s" % [response_code, detail])
	submit_finished.emit(false, "ERRO %d AO ENVIAR" % response_code)


## Converte a resposta crua em linhas seguras para exibicao.
func _normalize_rows(raw: Array) -> Array:
	var rows: Array = []
	for entry in raw:
		if not (entry is Dictionary):
			continue
		rows.append({
			"nick": NickUtil.for_display(str(entry.get("nick", ""))),
			"score": maxi(int(entry.get("score", 0)), 0),
			"created_at": str(entry.get("created_at", "")),
		})
	return rows


func _fail_fetch(message: String) -> void:
	last_error = message
	top_scores_failed.emit(message)


## Descricao legivel de um HTTPRequest.Result.
static func result_name(result: int) -> String:
	return str(RESULT_NAMES.get(result, "FALHA DE REDE (%d)" % result))


## Permite a pagina HTML hospedeira apontar o jogo para outro projeto Supabase
## sem recompilar - util para separar ambiente de teste e producao.
func _apply_web_overrides() -> void:
	if not OS.has_feature("web"):
		return
	var window: Variant = JavaScriptBridge.get_interface("window")
	if window == null:
		return
	var url_override: Variant = window.ARKANOIA_SUPABASE_URL
	var key_override: Variant = window.ARKANOIA_SUPABASE_KEY
	if url_override != null and str(url_override).begins_with("https://"):
		base_url = str(url_override)
	if key_override != null and str(key_override).length() > 20:
		api_key = str(key_override)
