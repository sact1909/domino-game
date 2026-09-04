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

## Entraste a una sala: su código, tu silla y si te toca ser el anfitrión.
signal room_joined(code: String, seat: int, is_host: bool)

## Cambió algo del lobby: quién está en cada silla, quién manda y en qué anda la sala.
signal lobby_changed(players: Array, host_seat: int, room_phase: int)

var _peer := WebSocketMultiplayerPeer.new()
var _url: String = ""
var _link: int = Link.IDLE

## Lo último que dijo el servidor sobre la mesa: qué puesto me tocó y quién está en cada
## silla. Se guarda para poder REANUNCIARLO cuando la pantalla de juego recibe este
## transporte ya conectado desde el lobby. En ese momento los anuncios originales ya
## pasaron, y quien los escuchó era el lobby: sin esto la mesa no sabría en qué puesto
## está ni cómo se llaman los demás.
var _seat: int = -1
var _seat_names: Array = ["", "", "", ""]

## Y también el último estado que bajó. Hace falta por una razón menos obvia: los
## paquetes se drenan TODOS los que llegaron en el mismo poll(), así que si el aviso de
## "la partida arrancó" y el primer snapshot vienen juntos, el lobby procesa el primero,
## suelta el socket para el traspaso, y el bucle sigue emitiendo el snapshot a nadie —
## la mesa todavía no existe. Guardándolo, la mesa lo recibe al reengancharse y no queda
## en blanco esperando un mensaje que ya pasó.
var _last_pub: Dictionary = {}
var _last_mine: Dictionary = {}
var _hand_live: bool = false

## Y lo mismo para la sala, porque el traspaso también va de vuelta: al terminar una
## partida se puede volver al lobby sin soltar el socket, y el lobby necesita saber en
## qué sala está y cómo está compuesta.
var _room_code: String = ""
var _is_host: bool = false
var _last_players: Array = []
var _last_host_seat: int = -1
var _last_room_phase: int = Protocol.ROOM_LOBBY


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
	if _link == Link.CONNECTING:
		return
	if _link == Link.OPEN:
		# Ya conectado: alguien está reenganchando un socket que ya venía andando. Pasa
		# en las dos direcciones — del lobby a la mesa cuando arranca la partida, y de
		# la mesa al lobby cuando se pide revancha.
		#
		# No hay nada que conectar, pero sí hay que repetir todo lo que se anunció
		# mientras escuchaba la pantalla anterior. Sin esto, quien reengancha se queda
		# esperando mensajes que ya pasaron: la mesa saldría en blanco y el lobby no
		# sabría ni en qué sala está.
		_replay()
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


## Solo la manda el anfitrión: el servidor rechaza el resto. Acá no se comprueba porque
## el cliente no es quien decide eso, y esconder el botón es cosa de la pantalla.
func swap_seats(a: int, b: int) -> void:
	_send({"type": Protocol.C_SWAP_SEATS, "a": a, "b": b})


func leave_room() -> void:
	_send({"type": Protocol.C_LEAVE_ROOM})
	# Se olvida en el acto: ya no somos parte de esa sala, y si no, al volver al lobby el
	# reengancho repetiría una sala en la que ya no estamos.
	_forget_room()


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
		_emit_disconnected()
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
			_seat = int(msg.get("seat", -1))
			_room_code = str(msg.get("code", ""))
			_is_host = bool(msg.get("is_host", false))
			_emit_seat_assigned(_seat)
			room_joined.emit(_room_code, _seat, _is_host)
		Protocol.S_SEAT_ASSIGNED:
			_seat = int(msg.get("seat", -1))
			_emit_seat_assigned(_seat)
		Protocol.S_ROOM_CLOSED:
			_forget_room()
			_emit_server_error("sala_cerrada")
		Protocol.S_LOBBY:
			_last_players = msg.get("players", [])
			_last_host_seat = int(msg.get("host_seat", -1))
			_last_room_phase = int(msg.get("phase", Protocol.ROOM_LOBBY))
			_is_host = (_seat >= 0 and _seat == _last_host_seat)
			lobby_changed.emit(_last_players, _last_host_seat, _last_room_phase)
			# El lobby también llega durante la partida, cada vez que alguien entra o se
			# va, así que los nombres de la mesa se mantienen al día solos.
			_seat_names = _names_from(_last_players)
			_emit_seats_changed(_seat_names)
		Protocol.S_SNAPSHOT:
			_last_pub = Protocol.decode_public_view(msg.get("pub", {}))
			_last_mine = Protocol.decode_private_view(msg.get("mine", {}))
			_emit_snapshot(_last_pub, _last_mine)
		Protocol.S_EVENTS:
			_emit_events(Protocol.decode_events(msg.get("list", [])))
		Protocol.S_HAND_STARTED:
			_hand_live = true
			_emit_hand_started()
		Protocol.S_HAND_ENDED:
			_hand_live = false
			_emit_hand_ended(
				Protocol.decode_event(msg.get("closing", {})),
				Protocol.decode_reveal(msg.get("reveal", {}))
			)
		Protocol.S_MATCH_ENDED:
			_emit_match_ended(int(msg.get("winner_team", -1)))
		Protocol.S_ERROR:
			_emit_server_error(str(msg.get("reason", "")))
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


func seat() -> int:
	return _seat


## Los nombres por puesto, tal como los espera el contrato: el nombre si hay alguien
## sentado, cadena vacía si la silla la juega la máquina.
func _names_from(players: Array) -> Array:
	var names: Array = []
	for entry in players:
		var seat_info: Dictionary = entry
		if bool(seat_info.get("occupied", false)):
			names.append(str(seat_info.get("name", "")))
		else:
			names.append("")
	return names


# ===========================================================================
# Sala: revancha y cierre
# ===========================================================================
func play_again() -> void:
	_send({"type": Protocol.C_PLAY_AGAIN})


func close_room() -> void:
	_send({"type": Protocol.C_CLOSE_ROOM})
	_forget_room()


func room_code() -> String:
	return _room_code


func is_host() -> bool:
	return _is_host


func in_room() -> bool:
	return not _room_code.is_empty()


## Se olvida la sala pero NO se cierra el socket: quien se quedó sin sala puede crear o
## entrar a otra con la misma conexión.
func _forget_room() -> void:
	_room_code = ""
	_is_host = false
	_seat = -1
	_last_players = []
	_last_host_seat = -1
	_last_room_phase = Protocol.ROOM_LOBBY
	_last_pub = {}
	_last_mine = {}
	_hand_live = false


## Repite lo último que se supo, en el mismo orden en que bajó la primera vez, para que
## la pantalla que reengancha no tenga que distinguir esto de una partida que empieza.
func _replay() -> void:
	if not _room_code.is_empty():
		room_joined.emit(_room_code, _seat, _is_host)
	if _seat >= 0:
		_emit_seat_assigned(_seat)
	_emit_seats_changed(_seat_names)
	if not _last_players.is_empty():
		lobby_changed.emit(_last_players, _last_host_seat, _last_room_phase)
	if not _last_pub.is_empty():
		_emit_snapshot(_last_pub, _last_mine)
	if _hand_live:
		_emit_hand_started()
