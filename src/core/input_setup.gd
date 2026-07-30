## Registro das acoes de entrada em tempo de execucao.
##
## Feito por codigo, e nao pelo InputMap do project.godot, para que o mapeamento
## fique versionado de forma legivel e imune a mudancas de formato do arquivo de
## projeto entre versoes do Godot.
class_name InputSetup
extends RefCounted

const LEFT := &"arkanoia_left"
const RIGHT := &"arkanoia_right"
const LAUNCH := &"arkanoia_launch"
const PAUSE := &"arkanoia_pause"
const CONFIRM := &"arkanoia_confirm"

## Teclas por acao. W/S/A/D e as setas, conforme o pedido original.
const BINDINGS := {
	LEFT: [KEY_A, KEY_LEFT],
	RIGHT: [KEY_D, KEY_RIGHT],
	LAUNCH: [KEY_W, KEY_UP, KEY_SPACE],
	PAUSE: [KEY_P, KEY_ESCAPE],
	CONFIRM: [KEY_ENTER, KEY_KP_ENTER],
}


## Idempotente: pode ser chamado varias vezes sem duplicar eventos.
static func register() -> void:
	for action in BINDINGS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.2)
		for keycode in BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
