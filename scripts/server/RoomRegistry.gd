class_name RoomRegistry
extends RefCounted

## Todas las salas vivas del servidor, y quién está en cuál.
##
## Es lo único que sabe crear y encontrar salas por código, y lo único que las recoge
## cuando vencen. Igual que Room, no sabe qué es un socket: lo que quiere mandar sale
## por "outbound".

## Tope duro de salas. No es la capacidad del servidor: medido, mil salas con partida
## empezada ocupan 40 MB y medio milisegundo de cada cuadro, así que de capacidad va
## sobrado. Es un FUSIBLE, y está por lo que pasa sin él: la memoria crece hasta que el
## sistema mata el proceso, y ahí se caen todas las salas, incluidas las que tenían gente
## jugando. Con tope, lo peor que pasa es que un rato no se puedan crear salas nuevas.
const MAX_ROOMS := 1000

## Cuántas salas puede crear una MISMA conexión en un minuto.
##
## No para a quien quiera abusar —le basta con reconectar para tener otra cuota, porque la
## identidad de una conexión no es la identidad de una persona— y no pretende hacerlo.
## Está para el caso aburrido y más probable: un cliente con un error que pide sala en
## bucle. A ese lo frena en seco y con un motivo legible.
const CREATE_PER_PEER := 3

## Y cuántas puede crear el servidor entero en un minuto, contando a todos.
##
## Este sí es el freno de verdad, porque no depende de saber quién pide. Sesenta por
## minuto es un número al que cuatro amigos no se acercan ni jugando toda la noche, y a
## quien quiera llenar el cupo lo deja en unas treinta salas a la vez: las que alcanza a
## crear antes de que las primeras venzan a los treinta segundos. Nunca llega al tope.
##
## Limitar por IP sería lo natural, pero acá no sirve: detrás del proxy TLS todas las
## conexiones llegan con la dirección del proxy, así que un límite por IP las contaría
## como una sola y los amigos se bloquearían entre ellos.
const CREATE_PER_SERVER := 60

## La ventana de los dos límites de arriba.
const CREATE_WINDOW := 60.0

## Intentos para encontrar un código libre. Con 3.2 millones de combinaciones y mil
## salas como máximo, la probabilidad de fallar veinte veces seguidas es despreciable;
## el tope está para que un error de programación no deje el servidor girando.
const CODE_ATTEMPTS := 20

signal outbound(peer_id: int, msg: Dictionary)

var _rooms: Dictionary = {}
var _room_of_peer: Dictionary = {}
var _rng := RandomNumberGenerator.new()

## Instantes en que se creó cada sala, para los dos límites por minuto: la lista de una
## conexión y la del servidor entero.
##
## Los instantes salen del reloj propio del registro y no de la hora del sistema, por lo
## mismo que el resto del servidor va por tick(delta): así una prueba adelanta un minuto
## en una línea en vez de tener que esperarlo.
var _creates_by_peer: Dictionary = {}
var _creates: Array = []
var _uptime: float = 0.0


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
	if not _may_create(peer_id):
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
	# Se apunta cuando la sala existe de verdad, no al pedirla: un intento que falló por
	# el tope o por un código repetido no gastó nada y no debería gastar cuota.
	_note_create(peer_id)
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


## Vuelve a sentar a alguien en su silla con la credencial que se le dio al entrar.
##
## Es lo que hace útil que la sala no se destruya al quedarse vacía: se cae la conexión,
## el cliente vuelve a marcar, presenta su credencial y sigue la misma mano.
func rejoin_room(peer_id: int, raw_code: String, token: String) -> String:
	if _room_of_peer.has(peer_id):
		_error(peer_id, "ya_estas_en_una_sala")
		return ""

	var code: String = RoomCode.normalize(raw_code)
	if not RoomCode.is_valid(code):
		_error(peer_id, "codigo_invalido")
		return ""
	if not _rooms.has(code):
		_error(peer_id, "sala_no_existe")
		return ""

	var room: Room = _rooms[code]
	# El motivo del rechazo lo manda la sala, que es la que sabe si falló la credencial
	# o si la silla ya tiene a alguien.
	if room.rejoin(peer_id, token) < 0:
		return ""

	_room_of_peer[peer_id] = code
	_announce_joined(peer_id, room)
	# Y después de la lista de la sala, la mesa: el estado, la mano y el reloj. Va en ese
	# orden para que reciba su silla antes que las fichas que hay en ella.
	room.catch_up(peer_id)
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
	_uptime += delta

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


## Si esta conexión puede crear una sala ahora. Manda el motivo si no, porque los dos
## casos se arreglan de maneras distintas: uno esperando un rato, el otro no.
func _may_create(peer_id: int) -> bool:
	_forget_old_creates()

	var mine: Array = _creates_by_peer.get(peer_id, [])
	if mine.size() >= CREATE_PER_PEER:
		_error(peer_id, "demasiadas_salas")
		return false
	if _creates.size() >= CREATE_PER_SERVER:
		_error(peer_id, "servidor_ocupado")
		return false
	return true


func _note_create(peer_id: int) -> void:
	_creates.append(_uptime)
	var mine: Array = _creates_by_peer.get(peer_id, [])
	mine.append(_uptime)
	_creates_by_peer[peer_id] = mine


## Suelta lo que ya salió de la ventana. Se limpia al preguntar y no en cada cuadro:
## así la cuenta no cuesta nada mientras nadie esté creando salas.
func _forget_old_creates() -> void:
	var cutoff: float = _uptime - CREATE_WINDOW
	_creates = _after(_creates, cutoff)
	for peer_id in _creates_by_peer.keys():
		var mine: Array = _after(_creates_by_peer[peer_id], cutoff)
		if mine.is_empty():
			_creates_by_peer.erase(peer_id)
		else:
			_creates_by_peer[peer_id] = mine


func _after(stamps: Array, cutoff: float) -> Array:
	var kept: Array = []
	for t in stamps:
		if float(t) > cutoff:
			kept.append(t)
	return kept


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
		"token": room.token_of(peer_id),
	})
	room.broadcast_lobby()


func _on_room_outbound(peer_id: int, msg: Dictionary) -> void:
	outbound.emit(peer_id, msg)


func _send(peer_id: int, msg: Dictionary) -> void:
	outbound.emit(peer_id, msg)


func _error(peer_id: int, reason: String) -> void:
	_send(peer_id, {"type": Protocol.S_ERROR, "reason": reason})


## Cierra una sala del todo: avisa a los que estaban dentro y la borra. Solo el anfitrión
## puede, porque es quien la creó. Es distinto de que se vaya el último: eso deja la sala
## vencer sola por si alguien vuelve, y esto la termina a propósito.
func close_room(peer_id: int) -> bool:
	var room: Room = room_for(peer_id)
	if room == null:
		_error(peer_id, "no_estas_en_una_sala")
		return false
	if not room.is_host(peer_id):
		_error(peer_id, "solo_el_anfitrion")
		return false
	room.announce_closed()
	_drop_room(room.code)
	return true
