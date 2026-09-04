extends Node

## Punto de entrada del proyecto. Decide si arrancar el juego con interfaz o el
## servidor dedicado, y carga la escena correspondiente.
##
## Modo servidor si se cumple cualquiera de estas condiciones:
##   - El binario se exportó con la plantilla "dedicated server" (feature tag).
##   - Se pasó "--server" en la línea de comandos.
##
## Para probar el servidor en local, sin exportar nada:
##   godot --headless -- --server
##
## Se usa una escena de arranque (en vez de ramificar dentro del juego) porque el
## escenario principal es un ajuste del proyecto, no del preset de exportación: así
## el mismo binario sirve para las dos cosas.

const GAME_SCENE := "res://scenes/Main.tscn"
const SERVER_SCENE := "res://scenes/Server.tscn"


func _ready() -> void:
	var scene: String = SERVER_SCENE if _is_server_mode() else GAME_SCENE
	# Se aplaza un frame a propósito: dentro de _ready() el árbol todavía está
	# ocupado agregando este nodo, y cambiar de escena ahí intenta quitarlo en pleno
	# proceso — falla con "Parent node is busy adding/removing children" y el cambio
	# nunca ocurre, dejando el proceso corriendo sin hacer nada.
	get_tree().change_scene_to_file.call_deferred(scene)


func _is_server_mode() -> bool:
	if OS.has_feature("dedicated_server"):
		return true
	# Los argumentos después de "--" llegan en get_cmdline_user_args(); se revisan
	# los dos arreglos porque según cómo se invoque el binario cae en uno o en otro.
	if OS.get_cmdline_user_args().has("--server"):
		return true
	if OS.get_cmdline_args().has("--server"):
		return true
	return false
