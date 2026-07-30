## Normalizacao e validacao do nick. Codigo puro e testavel.
##
## O nick vai para um leaderboard publico embutido numa pagina institucional,
## portanto a sanitizacao e conservadora: apenas A-Z, 0-9 e alguns separadores.
## Isso tambem elimina qualquer risco de injecao de markup ao renderizar a lista.
class_name NickUtil
extends RefCounted

const MIN_LEN := 2
const MAX_LEN := 10
const ALLOWED_EXTRA := "-_. "
const FALLBACK := "ANONIMO"

## Substituicoes de acentuacao, para o jogador digitar naturalmente em portugues.
const DEACCENT := {
	"Á": "A", "À": "A", "Ã": "A", "Â": "A", "Ä": "A",
	"É": "E", "È": "E", "Ê": "E", "Ë": "E",
	"Í": "I", "Ì": "I", "Î": "I", "Ï": "I",
	"Ó": "O", "Ò": "O", "Õ": "O", "Ô": "O", "Ö": "O",
	"Ú": "U", "Ù": "U", "Û": "U", "Ü": "U",
	"Ç": "C", "Ñ": "N",
}


## Converte entrada crua em um nick canonico: maiusculas, sem acento, sem
## caracteres estranhos, sem espacos duplicados, truncado em MAX_LEN.
static func sanitize(raw: String) -> String:
	var upper := raw.to_upper()
	var out := ""

	for i in upper.length():
		var ch := upper[i]
		if DEACCENT.has(ch):
			ch = DEACCENT[ch]
		if _is_allowed(ch):
			# Nunca dois separadores seguidos, e nunca separador no inicio.
			if ch == " " and (out.is_empty() or out.ends_with(" ")):
				continue
			out += ch
		if out.length() >= MAX_LEN:
			break

	return out.strip_edges()


## Um nick e valido se, apos sanitizar, tem tamanho adequado e ao menos um
## caractere alfanumerico (evita nicks compostos so de pontos e tracos).
static func is_valid(nick: String) -> bool:
	var clean := sanitize(nick)
	if clean.length() < MIN_LEN or clean.length() > MAX_LEN:
		return false
	for i in clean.length():
		if _is_alphanumeric(clean[i]):
			return true
	return false


## Nick pronto para envio: sanitizado, ou FALLBACK se invalido.
static func to_submittable(raw: String) -> String:
	var clean := sanitize(raw)
	return clean if is_valid(clean) else FALLBACK


## Recorta o nick para exibicao em espaco limitado (ex.: leaderboard estreito).
static func for_display(raw: String, max_chars: int = MAX_LEN) -> String:
	var clean := sanitize(raw)
	if clean.is_empty():
		clean = FALLBACK
	if clean.length() <= max_chars:
		return clean
	return clean.substr(0, max_chars)


static func _is_allowed(ch: String) -> bool:
	return _is_alphanumeric(ch) or ALLOWED_EXTRA.contains(ch)


static func _is_alphanumeric(ch: String) -> bool:
	if ch.length() != 1:
		return false
	var code := ch.unicode_at(0)
	var is_digit := code >= 48 and code <= 57   # 0-9
	var is_upper := code >= 65 and code <= 90   # A-Z
	return is_digit or is_upper
