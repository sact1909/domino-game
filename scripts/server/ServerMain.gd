extends Node

## Servidor dedicado de salas.
##
## Es la capa más delgada del servidor a propósito: abre el puerto, desempaqueta JSON,
## comprueba que lo que llegó tenga la forma que dice tener, y se lo pasa al registro
## de salas. Nada de reglas ni de turnos vive acá.
##
## Este es el BORDE del sistema: todo lo que entra por el socket viene de un cliente
## que no controlamos y podría estar modificado. Por eso cada campo se valida y se
## acota antes de bajar, y ningún mensaje dice en nombre de qué puesto habla: eso se
## deduce de la conexión.
##
## Protocolo: un mensaje = un paquete = JSON con la clave "type" (ver Protocol.gd).
##
## Puerto: variable de entorno PORT (Coolify la inyecta), o DEFAULT_PORT en local.
##
## Para probar en local:
##   godot --headless -- --server

const DEFAULT_PORT := 8090

## Topes de la configuración que manda el anfitrión. Se acotan acá y no en las reglas
## porque este es el borde: un cliente modificado podría pedir una meta de mil millones
## y dejar la mesa jugando para siempre.
const MIN_TARGET := 50
const MAX_TARGET := 1000
const MAX_BONUS := 500

var _peer := WebSocketMultiplayerPeer.new()
var _registry := RoomRegistry.new()


func _ready() -> void:
	var port := _resolve_port()
	var err := _peer.create_server(port)
	if err != OK:
		push_error("No se pudo abrir el servidor en el puerto %d (error %d)." % [port, err])
		get_tree().quit(1)
		return

	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	_registry.outbound.connect(_send)

	# Este print es la señal de vida que se ve en los logs de Coolify.
	print("[servidor] Dominó Dominicano — protocolo v%d escuchando en el puerto %d" % [Protocol.VERSION, port])


func _process(delta: float) -> void:
	_peer.poll()
	# get_packet_peer() informa de quién viene el SIGUIENTE paquete, así que se
	# consulta antes de sacarlo de la cola.
	while _peer.get_available_packet_count() > 0:
		var from: int = _peer.get_packet_peer()
		var raw: PackedByteArray = _peer.get_packet()
		_handle_packet(from, raw)

	# El reloj de las salas: mueve los puestos de la IA y recoge las que vencieron.
	_registry.tick(delta)


func _on_peer_connected(id: int) -> void:
	print("[servidor] conectado: %d" % id)
	_send(id, {
		"type": Protocol.S_HELLO,
		"protocol": Protocol.VERSION,
	})


func _on_peer_disconnected(id: int) -> void:
	print("[servidor] desconectado: %d" % id)
	# La sala no se destruye al quedar vacía: vence sola, así quien se cayó y vuelve
	# enseguida todavía encuentra su mesa.
	_registry.leave(id)


# ===========================================================================
# Enrutado
# ===========================================================================
func _handle_packet(from: int, raw: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_error(from, "mensaje_invalido")
		return

	var msg: Dictionary = parsed
	var msg_type: String = str(msg.get("type", ""))

	if msg_type == Protocol.C_CREATE_ROOM:
		if not _protocol_ok(from, msg):
			return
		_registry.create_room(from, str(msg.get("name", "")))
		return

	if msg_type == Protocol.C_JOIN_ROOM:
		if not _protocol_ok(from, msg):
			return
		_registry.join_room(from, str(msg.get("code", "")), str(msg.get("name", "")))
		return

	if msg_type == Protocol.C_LEAVE_ROOM:
		_registry.leave(from)
		return

	if msg_type == Protocol.C_PING:
		_send(from, {"type": Protocol.S_PONG, "echo": msg.get("payload", null)})
		return

	# Lo que queda solo tiene sentido dentro de una sala.
	var room: Room = _registry.room_for(from)
	if room == null:
		_error(from, "no_estas_en_una_sala")
		return

	if msg_type == Protocol.C_SWAP_SEATS:
		room.swap_seats(from, int(msg.get("a", -1)), int(msg.get("b", -1)))
		return

	if msg_type == Protocol.C_PLAY_AGAIN:
		room.play_again(from)
		return

	if msg_type == Protocol.C_CLOSE_ROOM:
		# Va al registro y no a la sala: cerrarla implica borrarla de las salas vivas.
		_registry.close_room(from)
		return

	if msg_type == Protocol.C_START_MATCH:
		room.start_match(from, _read_config(msg))
		return

	if msg_type == Protocol.C_PLAY:
		_handle_play(from, room, msg)
		return

	if msg_type == Protocol.C_CONTINUE:
		room.handle_continue(from)
		return

	_error(from, "tipo_desconocido")


## La jugada se valida en la forma antes de bajar: el índice tiene que caber en una
## mano y la punta tiene que ser una de las dos. Que la ficha SEA jugable lo decide la
## sesión, que es la autoridad; esto solo evita pasarle basura.
func _handle_play(from: int, room: Room, msg: Dictionary) -> void:
	var idx: int = int(msg.get("idx", -1))
	if idx < 0 or idx >= GameState.TILES_PER_HAND:
		_error(from, "indice_invalido")
		return

	var end: String = str(msg.get("end", ""))
	if end != "L" and end != "R":
		_error(from, "punta_invalida")
		return

	room.handle_play(from, idx, end)


## Configuración con la que el anfitrión quiere empezar, acotada. Lo que no venga o
## venga mal se reemplaza por el valor por defecto del protocolo.
func _read_config(msg: Dictionary) -> Dictionary:
	var config: Dictionary = {}
	var raw: Variant = msg.get("config", {})
	if typeof(raw) == TYPE_DICTIONARY:
		config = raw

	var defaults: Dictionary = Transport.default_config()
	return {
		"target_score": clampi(int(config.get("target_score", defaults.target_score)), MIN_TARGET, MAX_TARGET),
		"bonus_pase_seguido": clampi(int(config.get("bonus_pase_seguido", defaults.bonus_pase_seguido)), 0, MAX_BONUS),
		"bonus_capicua": clampi(int(config.get("bonus_capicua", defaults.bonus_capicua)), 0, MAX_BONUS),
		"bonus_pase_salida": clampi(int(config.get("bonus_pase_salida", defaults.bonus_pase_salida)), 0, MAX_BONUS),
	}


## La versión se comprueba al entrar a una sala, que es la primera cosa útil que hace
## cualquiera. Cortar acá da un mensaje claro; dejarlo pasar da un error incomprensible
## tres mensajes después, cuando un lado manda un campo que el otro no conoce.
func _protocol_ok(from: int, msg: Dictionary) -> bool:
	if not msg.has("protocol"):
		return true
	if int(msg.protocol) == Protocol.VERSION:
		return true
	_send(from, {
		"type": Protocol.S_ERROR,
		"reason": "protocolo_incompatible",
		"server_protocol": Protocol.VERSION,
	})
	return false


# ===========================================================================
# Salida
# ===========================================================================
func _send(peer_id: int, msg: Dictionary) -> void:
	_peer.set_target_peer(peer_id)
	_peer.put_packet(JSON.stringify(msg).to_utf8_buffer())


func _error(peer_id: int, reason: String) -> void:
	_send(peer_id, {"type": Protocol.S_ERROR, "reason": reason})


func _resolve_port() -> int:
	var from_env: String = OS.get_environment("PORT")
	if from_env.is_valid_int():
		return int(from_env)
	# Si PORT viene con basura conviene que se vea en los logs: si no, el servidor
	# arrancaría en el puerto por defecto y el proxy no encontraría a nadie.
	if not from_env.is_empty():
		push_warning("PORT no es un número válido (%s); se usa el puerto %d." % [from_env, DEFAULT_PORT])
	return DEFAULT_PORT
