class_name RoomRegistry
extends RefCounted

## Todas las salas vivas del servidor, y quién está en cuál.
##
## Es lo único que sabe crear y encontrar salas por código, y lo único que las recoge
## cuando vencen. Igual que Room, no sabe qué es un socket: lo que quiere mandar sale
## por "outbound".

## Tope duro de salas. Sin él, cualquiera que mande create_room en bucle llena la
## memoria del servidor: es la defensa más simple y la más necesaria en un puerto
## abierto a internet. Limitar cuántas veces se puede pedir por minuto es lo que
## falta, y va con el resto de la robustez.
const MAX_ROOMS := 200

## Intentos para encontrar un código libre. Con 3.2 millones de combinaciones y 200
## salas como máximo, la probabilidad de fallar veinte veces seguidas es despreciable;
## el tope está para que un error de programación no deje el servidor girando.
const CODE_ATTEMPTS := 20

signal outbound(peer_id: int, msg: Dictionary)

var _rooms: Dictionary = {}
var _room_of_peer: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


# ===========================================================================
# Crear, entrar y salir
# ===========================================================================
## Devuelve el código de la sala nueva, o una cadena vacía si no se pudo (y en ese
## caso ya se le explicó el motivo a quien la pidió).
func create_room(peer_id: int, player_name: String) -> String:
	if _room_of_peer.has(peer_id):
		_error(peer_id, "ya_estas_en_una_sala")
		return ""
	if _rooms.size() >= MAX_ROOMS:
		_error(peer_id, "servidor_lleno")
		return ""

	var code: String = _free_code()
	if code.is_empty():
		_error(peer_id, "no_se_pudo_generar_codigo")
		return ""

	var room := Room.new(code)
	room.outbound.connect(_on_room_outbound)
	_rooms[code] = room

	var seat: int = room.add_member(peer_id, player_name)
	if seat < 0:
		# No debería ocurrir en una sala recién creada; si ocurre, es mejor no dejar
		# la sala colgada sin nadie adentro.
		_rooms.erase(code)
		_error(peer_id, "no_se_pudo_entrar")
		return ""

	_room_of_peer[peer_id] = code
	_announce_joined(peer_id, room)
	return code


func join_room(peer_id: int, raw_code: String, player_name: String) -> String:
	if _room_of_peer.has(peer_id):
		_error(peer_id, "ya_estas_en_una_sala")
		return ""

	# Se normaliza antes de validar: la gente escribe en minúscula, pega espacios de
	# sobra o mete guiones para leerlo mejor, y nada de eso debería dejarla afuera.
	var code: String = RoomCode.normalize(raw_code)
	if not RoomCode.is_valid(code):
		_error(peer_id, "codigo_invalido")
		return ""
	if not _rooms.has(code):
		_error(peer_id, "sala_no_existe")
		return ""

	var room: Room = _rooms[code]
	var seat: int = room.add_member(peer_id, player_name)
	if seat < 0:
		# Los dos motivos se distinguen porque son cosas distintas para quien está
		# esperando: una sala llena no se arregla, una partida en curso sí.
		if room.phase != Room.Phase.LOBBY:
			_error(peer_id, "partida_en_curso")
		else:
			_error(peer_id, "sala_llena")
		return ""

	_room_of_peer[peer_id] = code
	_announce_joined(peer_id, room)
	return code


## Saca a alguien de su sala. La sala NO se destruye al quedar vacía: se deja vencer
## sola, así quien se cayó y vuelve enseguida encuentra su mesa donde estaba.
func leave(peer_id: int) -> void:
	if not _room_of_peer.has(peer_id):
		return
	var code: String = str(_room_of_peer[peer_id])
	_room_of_peer.erase(peer_id)
	if not _rooms.has(code):
		return
	var room: Room = _rooms[code]
	room.remove_member(peer_id)


# ===========================================================================
# Consultas
# ===========================================================================
func room_for(peer_id: int) -> Room:
	if not _room_of_peer.has(peer_id):
		return null
	var code: String = str(_room_of_peer[peer_id])
	if not _rooms.has(code):
		return null
	return _rooms[code]


func room_by_code(code: String) -> Room:
	if not _rooms.has(code):
		return null
	return _rooms[code]


func room_count() -> int:
	return _rooms.size()


# ===========================================================================
# Reloj
# ===========================================================================
## Avanza el reloj de todas las salas y recoge las que vencieron.
func tick(delta: float) -> void:
	# Se recolectan los códigos primero y se borran después: modificar el diccionario
	# mientras se recorre es pedir problemas.
	var expired: Array = []
	for code in _rooms.keys():
		var room: Room = _rooms[code]
		room.tick(delta)
		if room.should_expire():
			expired.append(str(code))

	for code in expired:
		_drop_room(str(code))


# ===========================================================================
# Interno
# ===========================================================================
func _drop_room(code: String) -> void:
	if not _rooms.has(code):
		return
	_rooms.erase(code)
	# Quien todavía apuntara a esa sala queda libre para crear o entrar a otra.
	for peer_id in _room_of_peer.keys():
		if str(_room_of_peer[peer_id]) == code:
			_room_of_peer.erase(peer_id)


func _free_code() -> String:
	for i in range(CODE_ATTEMPTS):
		var code: String = RoomCode.generate(_rng)
		if not _rooms.has(code):
			return code
	return ""


## El puesto se anuncia ANTES del lobby, para que quien entra sepa cuál es su silla
## cuando le llegue la lista de todas.
func _announce_joined(peer_id: int, room: Room) -> void:
	_send(peer_id, {
		"type": Protocol.S_ROOM_JOINED,
		"code": room.code,
		"seat": room.seat_of(peer_id),
		"is_host": room.is_host(peer_id),
	})
	room.broadcast_lobby()


func _on_room_outbound(peer_id: int, msg: Dictionary) -> void:
	outbound.emit(peer_id, msg)


func _send(peer_id: int, msg: Dictionary) -> void:
	outbound.emit(peer_id, msg)


func _error(peer_id: int, reason: String) -> void:
	_send(peer_id, {"type": Protocol.S_ERROR, "reason": reason})
