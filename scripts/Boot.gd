extends Node

## Punto de entrada del proyecto. Decide si arrancar el juego con interfaz o el
## servidor dedicado, y carga la escena correspondiente.
##
## Modo servidor si se cumple cualquiera de estas condiciones:
##   - El binario se exportó con la plantilla "dedicated server" (feature tag).
##   - Se pasó "--server" en la línea de comandos.
##
## Con "--test" corre el arnés de pruebas de las reglas en vez del juego.
##
## Para probar en local, sin exportar nada:
##   godot --headless -- --server
##   godot --headless -- --test
##
## Con "--test-net" corre la prueba de red, que necesita un servidor escuchando aparte.
##
## Se usa una escena de arranque (en vez de ramificar dentro del juego) porque el
## escenario principal es un ajuste del proyecto, no del preset de exportación: así
## el mismo binario sirve para las cuatro cosas.

const GAME_SCENE := "res://scenes/Main.tscn"
const SERVER_SCENE := "res://scenes/Server.tscn"
const TEST_SCENE := "res://scenes/Test.tscn"
const TEST_NET_SCENE := "res://scenes/NetTest.tscn"


func _ready() -> void:
	var scene: String = GAME_SCENE
	if _has_flag("--test"):
		scene = TEST_SCENE
	elif _has_flag("--test-net"):
		scene = TEST_NET_SCENE
	elif _is_server_mode():
		scene = SERVER_SCENE
	# Se aplaza un frame a propósito: dentro de _ready() el árbol todavía está
	# ocupado agregando este nodo, y cambiar de escena ahí intenta quitarlo en pleno
	# proceso — falla con "Parent node is busy adding/removing children" y el cambio
	# nunca ocurre, dejando el proceso corriendo sin hacer nada.
	get_tree().change_scene_to_file.call_deferred(scene)


func _is_server_mode() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	return _has_flag("--server")


# Los argumentos después de "--" llegan en get_cmdline_user_args(); se revisan los
# dos arreglos porque según cómo se invoque el binario caen en uno o en otro.
func _has_flag(flag: String) -> bool:
	if OS.get_cmdline_user_args().has(flag):
		return true
	return OS.get_cmdline_args().has(flag)
