## Formatacao de texto para a UI. Codigo puro e testavel.
##
## Vive fora dos autoloads de proposito: a suite headless (--script) roda sem
## autoloads, e formatacao e justamente o tipo de coisa que precisa de teste.
class_name TextUtil
extends RefCounted

const INVALID_DATE := "--/--/--"


## Converte um timestamptz do Postgres ("2026-07-30T13:45:12+00:00") em DD/MM/AA.
static func format_iso_date(iso: String) -> String:
	if iso.length() < 10:
		return INVALID_DATE
	var parts := iso.substr(0, 10).split("-")
	if parts.size() != 3:
		return INVALID_DATE
	if not (parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int()):
		return INVALID_DATE
	return "%s/%s/%s" % [parts[2], parts[1], parts[0].substr(2, 2)]


## Numero com zeros a esquerda, para o placar em fonte de largura fixa.
static func pad_number(value: int, digits: int) -> String:
	return str(maxi(value, 0)).lpad(digits, "0")
