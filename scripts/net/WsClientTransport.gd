class_name WsClientTransport
extends Transport

## Cliente de red: el mismo contrato que LocalTransport, pero hablando con el servidor
## de salas por WebSocket.
##
## Lo importante de este archivo es lo que NO hace. No aplica reglas, no valida
## jugadas, no decide turnos, no reparte y no sabe qué tiene nadie en la mano. Empaqueta
## lo que la pantalla pide y desempaqueta lo que baja. Toda la autoridad está del otro
## lado, y modificar este archivo no sirve de nada: el servidor no le cree nada, y de
## las fichas ajenas nunca le llega ninguna.
##
## Además del contrato de Transport expone la parte de SALA —conectar, crear, entrar,
## elegir silla—, que en el modo local no existe porque no hay a quién esperar. Eso lo
## usa la pantalla del lobby; la pantalla de juego sigue viendo solo el contrato.

## A dónde conectar si no se dice otra cosa. Hoy apunta a un servidor local: la URL del
## servidor desplegado lleva la IP adentro, y ponerla acá la publica en el repositorio.
## Para jugar en internet se pasa --server-url=wss://... o se cambia esta constante.
const DEFAULT_URL := "ws://127.0.0.1:8090"

## Estado del enlace. Se distingue "conectando" de "abierto" porque mandar algo antes
## de que el socket esté listo se pierde sin aviso.
enum Link { IDLE, CONNECTING, OPEN, CLOSED }

# ---------------------------------------------------------------------------
# Señales de sala (además de las del contrato)
# ---------------------------------------------------------------------------
signal connected()
signal connection_failed(reason: String)
signal disconnected()

## Entraste a una sala: su código, tu silla y si te toca ser el anfitrión.
signal room_joined(code: String, seat: int, is_host: bool)

## Cambió algo del lobby: quién está en cada silla, quién manda y en qué anda la sala.
signal lobby_changed(players: Array, host_seat: int, room_phase: int)

## El servidor rechazó algo. El motivo viene como clave, no como texto: el idioma se
## resuelve en la pantalla, igual que con los eventos.
signal server_error(reason: String)

var _peer := WebSocketMultiplayerPeer.new()
var _url: String = ""
var _link: int = Link.IDLE


func _init(url: String = "") -> void:
	_url = url if not url.is_empty() else resolve_url()


## URL del servidor desde la línea de comandos, para poder probar contra un servidor
## local sin recompilar:  godot -- --server-url=ws://127.0.0.1:8090
static func resolve_url() -> String:
	for arg in OS.get_cmdline_user_args():
		var text: String = str(arg)
		if text.begins_with("--server-url="):
			var value: String = text.substr(13)
			if not value.is_empty():
				return value
	return DEFAULT_URL


func url() -> String:
	return _url


func is_open() -> bool:
	return _link == Link.OPEN


# ===========================================================================
# Contrato de Transport
# ===========================================================================
## Acá "sentarse a la mesa" es abrir el socket. El puesto no llega en el acto como en
## el modo local: llega cuando el servidor te sienta en una sala, que es lo que hace
## distinto a jugar en red.
func begin() -> void:
	if _link == Link.CONNECTING or _link == Link.OPEN:
		return
	var err: int = _peer.create_client(_url)
	if err != OK:
		_link = Link.CLOSED
		connection_failed.emit("url_invalida")
		return
	_link = Link.CONNECTING


func start_match(config: Dictionary) -> void:
	_send({"type": Protocol.C_START_MATCH, "config": config})


func request_play(idx: int, end: String) -> void:
	# No se manda el puesto y no es un olvido: el servidor lo sabe por la conexión. Es
	# lo que impide jugar en nombre de otro por más que se modifique este archivo.
	_send({"type": Protocol.C_PLAY, "idx": idx, "end": end})


func request_continue() -> void:
	_send({"type": Protocol.C_CONTINUE})


# ===========================================================================
# Sala
# ===========================================================================
func create_room(player_name: String) -> void:
	_send({"type": Protocol.C_CREATE_ROOM, "name": player_name, "protocol": Protocol.VERSION})


func join_room(code: String, player_name: String) -> void:
	_send({"type": Protocol.C_JOIN_ROOM, "code": code, "name": player_name, "protocol": Protocol.VERSION})


func set_seat(seat: int) -> void:
	_send({"type": Protocol.C_SET_SEAT, "seat": seat})


func leave_room() -> void:
	_send({"type": Protocol.C_LEAVE_ROOM})


func close() -> void:
	if _link == Link.IDLE or _link == Link.CLOSED:
		return
	_peer.close()
	_link = Link.CLOSED


# ===========================================================================
# Bombeo del socket
# ===========================================================================
func _process(_delta: float) -> void:
	if _link == Link.IDLE or _link == Link.CLOSED:
		return

	_peer.poll()
	var status: int = _peer.get_connection_status()

	if _link == Link.CONNECTING:
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			_link = Link.OPEN
			connected.emit()
		elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			_link = Link.CLOSED
			connection_failed.emit("no_se_pudo_conectar")
			return
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		# Se cayó con la partida en curso. La pantalla tiene que decirlo: si no, la
		# mesa se queda quieta y parece que el juego se colgó.
		_link = Link.CLOSED
		disconnected.emit()
		return

	while _peer.get_available_packet_count() > 0:
		_receive(_peer.get_packet())


func _send(msg: Dictionary) -> void:
	if _link != Link.OPEN:
		# Se avisa en vez de perderlo en silencio: un mensaje que no salió y nadie
		# reporta es de lo más difícil de rastrear.
		push_warning("WsClientTransport: se intentó mandar '%s' sin conexión abierta" % str(msg.get("type", "")))
		return
	_peer.set_target_peer(1)
	_peer.put_packet(JSON.stringify(msg).to_utf8_buffer())


# ===========================================================================
# Lo que baja del servidor
# ===========================================================================
# Cada mensaje se traduce a la señal del contrato que le corresponde. Los cinco del
# juego calzan uno a uno, así que esta capa solo desempaqueta: es la ganancia de haber
# definido el contrato antes de escribir la red.
func _receive(raw: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("WsClientTransport: llegó algo que no es un mensaje")
		return

	var msg: Dictionary = parsed
	match str(msg.get("type", "")):
		Protocol.S_HELLO:
			_on_hello(msg)
		Protocol.S_ROOM_JOINED:
			# El puesto se acata: sale del servidor, no de una elección de la pantalla.
			_emit_seat_assigned(int(msg.get("seat", -1)))
			room_joined.emit(str(msg.get("code", "")), int(msg.get("seat", -1)), bool(msg.get("is_host", false)))
		Protocol.S_SEAT_ASSIGNED:
			_emit_seat_assigned(int(msg.get("seat", -1)))
		Protocol.S_LOBBY:
			lobby_changed.emit(msg.get("players", []), int(msg.get("host_seat", -1)), int(msg.get("phase", 0)))
		Protocol.S_SNAPSHOT:
			_emit_snapshot(
				Protocol.decode_public_view(msg.get("pub", {})),
				Protocol.decode_private_view(msg.get("mine", {}))
			)
		Protocol.S_EVENTS:
			_emit_events(Protocol.decode_events(msg.get("list", [])))
		Protocol.S_HAND_STARTED:
			_emit_hand_started()
		Protocol.S_HAND_ENDED:
			_emit_hand_ended(
				Protocol.decode_event(msg.get("closing", {})),
				Protocol.decode_reveal(msg.get("reveal", {}))
			)
		Protocol.S_MATCH_ENDED:
			_emit_match_ended(int(msg.get("winner_team", -1)))
		Protocol.S_ERROR:
			server_error.emit(str(msg.get("reason", "")))
		Protocol.S_PONG:
			pass


## La versión se compara en los DOS lados. El servidor solo la revisa si el cliente se
## la manda, así que si acá no se comprobara, un cliente viejo contra un servidor nuevo
## seguiría adelante y fallaría más tarde con un mensaje incomprensible.
func _on_hello(msg: Dictionary) -> void:
	var server_version: int = int(msg.get("protocol", -1))
	if server_version == Protocol.VERSION:
		return
	push_error("Protocolo incompatible: el servidor habla v%d y este cliente v%d" % [server_version, Protocol.VERSION])
	close()
	connection_failed.emit("protocolo_incompatible")
