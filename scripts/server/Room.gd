class_name Room
extends RefCounted

## Una sala: hasta cuatro jugadores sentados alrededor de una GameSession.
##
## Es la AUTORIDAD del lado del servidor. Hace el mismo papel que LocalTransport, pero
## con cuatro destinatarios en vez de uno, y con dos diferencias que importan:
##
## - El ritmo va por tick(delta), no por await. Un servidor tiene que poder adelantar
##   su reloj: así las pruebas comprueban en un instante lo que en la vida real tarda
##   minutos, y no quedan corrutinas sueltas cuando una sala muere.
## - No sabe qué es un socket. Todo lo que quiere mandar sale por la señal "outbound",
##   y quien la escuche decide cómo se entrega. Por eso se puede probar una partida
##   entera sin abrir un puerto.
##
## Los puestos que nadie ocupa los juega la IA. Eso permite que dos o tres amigos
## jueguen sin esperar un cuarto, y es la misma maquinaria que hará falta para relevar
## a quien se desconecte.

## Lo que la sala quiere mandarle a un jugador. peer_id identifica la conexión; la
## sala no sabe nada más de ella.
signal outbound(peer_id: int, msg: Dictionary)

## Pausa antes de que juegue un puesto de la IA. Más corta que la del modo local
## porque acá hay gente esperando de verdad, pero no cero: sin pausa, tres puestos de
## IA jugarían en el mismo instante y nadie vería qué pasó.
const AI_TURN_DELAY := 0.6

## Una sala que se queda sin nadie se recoge pronto; una con gente adentro aguanta
## mucho más, porque "sin actividad" muchas veces es que están conversando.
const EMPTY_ROOM_TTL := 300.0
const IDLE_ROOM_TTL := 3600.0

## Largo máximo del nombre. Corto a propósito: entra en la mesa y no sirve para
## empujar el resto de la interfaz fuera de la pantalla.
const MAX_NAME_LENGTH := 16

enum Phase { LOBBY, PLAYING, FINISHED }

var code: String = ""
var phase: int = Phase.LOBBY

var _session: GameSession
var _config: Dictionary = {}

## peer a puesto y puesto a peer, siempre en espejo. Se guardan las dos direcciones
## porque las dos preguntas se hacen todo el tiempo: quién es este que me escribe, y a
## quién le mando lo del puesto 2.
var _seat_of: Dictionary = {}
var _peer_at: Dictionary = {}
var _names: Dictionary = {}

## Quién puede arrancar la partida. Si se va, lo hereda el puesto ocupado más bajo: de
## lo contrario la sala quedaría viva sin que nadie pueda empezar.
var _host_seat: int = -1

## Turno de la IA (o pase forzado) pendiente de cumplirse cuando venza la pausa.
var _pending: Dictionary = {}

## Segundos sin actividad, para la recolección de salas.
var _idle: float = 0.0

## Quién mandó la acción que se está aplicando. Un rechazo se le contesta SOLO a esa
## persona: no tiene por qué aparecerle en la mesa a los demás.
var _acting_peer: int = -1


func _init(room_code: String) -> void:
	code = room_code


# ===========================================================================
# Entrar, salir y sentarse
# ===========================================================================
## Sienta a alguien en el primer puesto libre. Devuelve el puesto, o -1 si la sala
## está llena o la partida ya empezó.
func add_member(peer_id: int, raw_name: String) -> int:
	if phase != Phase.LOBBY:
		return -1
	if _seat_of.has(peer_id):
		return int(_seat_of[peer_id])

	var seat: int = _first_free_seat()
	if seat < 0:
		return -1

	_seat_of[peer_id] = seat
	_peer_at[seat] = peer_id
	_names[seat] = sanitize_name(raw_name)
	if _host_seat < 0:
		_host_seat = seat

	_touch()
	# Acá NO se difunde el lobby: el registro lo hace justo después de anunciarle el
	# puesto a quien entra, para que reciba su silla antes que la lista de todas.
	return seat


func remove_member(peer_id: int) -> void:
	if not _seat_of.has(peer_id):
		return
	var seat: int = int(_seat_of[peer_id])
	_seat_of.erase(peer_id)
	_peer_at.erase(seat)
	# El nombre se borra solo en el lobby. Con la partida en curso el puesto sigue
	# siendo de esa persona (lo juega la IA mientras tanto) y el nombre tiene que
	# seguir a la vista para que los demás sepan de quién es la silla.
	if phase == Phase.LOBBY:
		_names.erase(seat)

	if _host_seat == seat:
		_host_seat = _lowest_occupied_seat()

	_touch()
	broadcast_lobby()


## Cambiar de silla en el lobby: es así como se eligen las parejas, porque los puestos
## enfrentados son compañeros. Solo se puede antes de empezar.
func set_seat(peer_id: int, seat: int) -> bool:
	if phase != Phase.LOBBY:
		_error(peer_id, "partida_en_curso")
		return false
	if not _seat_of.has(peer_id):
		_error(peer_id, "no_estas_en_la_sala")
		return false
	if seat < 0 or seat >= GameState.SEAT_COUNT:
		_error(peer_id, "puesto_invalido")
		return false
	if _peer_at.has(seat) and int(_peer_at[seat]) != peer_id:
		_error(peer_id, "puesto_ocupado")
		return false

	var old_seat: int = int(_seat_of[peer_id])
	if old_seat == seat:
		return true

	var player_name: String = str(_names.get(old_seat, ""))
	_peer_at.erase(old_seat)
	_names.erase(old_seat)
	_seat_of[peer_id] = seat
	_peer_at[seat] = peer_id
	_names[seat] = player_name
	if _host_seat == old_seat:
		_host_seat = seat

	_touch()
	# El lobby es una difusión: el mismo mensaje para los cuatro, así que no puede
	# decirle a cada uno cuál es SU silla. Por eso el puesto nuevo se le manda aparte a
	# quien se movió, y no se deja que lo deduzca de la lista.
	_send(peer_id, {"type": Protocol.S_SEAT_ASSIGNED, "seat": seat})
	broadcast_lobby()
	return true


# ===========================================================================
# La partida
# ===========================================================================
func start_match(peer_id: int, config: Dictionary) -> bool:
	if phase != Phase.LOBBY:
		_error(peer_id, "partida_en_curso")
		return false
	if not _seat_of.has(peer_id):
		_error(peer_id, "no_estas_en_la_sala")
		return false
	if int(_seat_of[peer_id]) != _host_seat:
		_error(peer_id, "solo_el_anfitrion")
		return false

	_config = config.duplicate()
	_session = GameSession.new()
	_session.events.connect(_on_session_events)
	_session.state_changed.connect(_on_session_state_changed)
	_session.hand_started.connect(_on_session_hand_started)
	_session.hand_ended.connect(_on_session_hand_ended)
	_session.match_ended.connect(_on_session_match_ended)
	_session.turn_ready.connect(_on_session_turn_ready)

	phase = Phase.PLAYING
	_touch()
	broadcast_lobby()
	_session.start_match(_config)
	return true


func handle_play(peer_id: int, idx: int, end: String) -> bool:
	if phase != Phase.PLAYING:
		_error(peer_id, "no_hay_partida")
		return false
	if not _seat_of.has(peer_id):
		_error(peer_id, "no_estas_en_la_sala")
		return false
	if _session.hand_over():
		# Cerrada la mano no se juega más: falta que alguien pida seguir. Se contesta
		# acá porque si no, el resultado dependería de a quién le tocaba el turno
		# cuando cerró, que no tiene nada que ver.
		_error(peer_id, "la_mano_termino")
		return false

	# El turno se comprueba acá, antes de tocar la sesión, para poder contestarle a
	# quien se equivocó sin que el resto de la mesa se entere. La sesión igual valida
	# de nuevo: esta comprobación es por cortesía, no es la que da la seguridad.
	var seat: int = int(_seat_of[peer_id])
	if seat != _session.current_seat():
		_error(peer_id, "no_es_su_turno")
		return false

	_acting_peer = peer_id
	# El puesto NO viene del mensaje: sale de quién mandó el paquete. Es lo que impide
	# jugar en nombre de otro por más que se modifique el cliente.
	_session.play(seat, idx, end)
	_acting_peer = -1
	_touch()
	return true


func handle_continue(peer_id: int) -> bool:
	if phase != Phase.PLAYING:
		_error(peer_id, "no_hay_partida")
		return false
	if not _seat_of.has(peer_id):
		_error(peer_id, "no_estas_en_la_sala")
		return false
	if not _session.hand_over():
		_error(peer_id, "la_mano_sigue")
		return false

	# Alcanza con que UNO pida seguir. Esperar a los cuatro deja la mesa colgada cuando
	# alguien se distrae, y lo único que se pierde es un rato mirando el conteo.
	_touch()
	_session.continue_after_hand()
	return true


# ===========================================================================
# Reloj
# ===========================================================================
## Avanza el reloj de la sala. El servidor lo llama una vez por cuadro, y las pruebas
## lo llaman con el salto que quieran.
func tick(delta: float) -> void:
	_idle += delta
	if _pending.is_empty():
		return

	_pending["wait"] = float(_pending.wait) - delta
	if float(_pending.wait) > 0.0:
		return

	var job: Dictionary = _pending
	_pending = {}

	# Entre que se agendó y ahora, la mano pudo cerrar y hasta empezar otra. Aplicar
	# la jugada agendada movería una mano que no es la que se estaba jugando.
	if int(job.hand_id) != _session.hand_id or _session.hand_over():
		return

	var seat: int = int(job.seat)
	if bool(job.must_pass):
		_session.force_pass(seat)
		return

	var choice: Dictionary = DominoAI.choose(_session.private_view(seat))
	if choice.is_empty():
		_session.force_pass(seat)
		return
	_session.play(seat, int(choice.idx), str(choice.end))


# ===========================================================================
# Estado de la sala
# ===========================================================================
func member_count() -> int:
	return _seat_of.size()


func is_empty() -> bool:
	return _seat_of.is_empty()


func seat_of(peer_id: int) -> int:
	return int(_seat_of.get(peer_id, -1))


func is_host(peer_id: int) -> bool:
	return _seat_of.has(peer_id) and int(_seat_of[peer_id]) == _host_seat


func host_seat() -> int:
	return _host_seat


func has_pending_turn() -> bool:
	return not _pending.is_empty()


## Una sala vacía se recoge pronto; una con gente adentro aguanta una hora.
func should_expire() -> bool:
	if is_empty():
		return _idle >= EMPTY_ROOM_TTL
	return _idle >= IDLE_ROOM_TTL


func seconds_idle() -> float:
	return _idle


## Recorta el nombre y le quita lo que podría romper la pantalla de los demás. Los
## corchetes salen porque el registro de la mesa se dibuja con BBCode: un nombre con
## etiquetas adentro le cambiaría colores y texto a todo el mundo. Un nombre ajeno es
## contenido que no controlamos, y este es el borde donde se limpia.
static func sanitize_name(raw: String) -> String:
	var out: String = ""
	for ch in raw:
		if ch == "[" or ch == "]":
			continue
		if ch.unicode_at(0) < 32:
			continue
		out += ch
	out = out.strip_edges()
	if out.length() > MAX_NAME_LENGTH:
		out = out.substr(0, MAX_NAME_LENGTH)
	if out.is_empty():
		return "Jugador"
	return out


# ===========================================================================
# Difusión
# ===========================================================================
## Estado del lobby: quién está en cada silla y quién puede arrancar. Los puestos
## libres viajan como no ocupados, y el cliente los muestra como IA.
func broadcast_lobby() -> void:
	var players: Array = []
	for seat in range(GameState.SEAT_COUNT):
		players.append({
			"seat": seat,
			"name": str(_names.get(seat, "")),
			"occupied": _peer_at.has(seat),
		})

	_broadcast({
		"type": Protocol.S_LOBBY,
		"code": code,
		"players": players,
		"host_seat": _host_seat,
		"phase": phase,
	})


## Le manda a cada puesto ocupado el estado público más SU propia mano. Es el punto
## exacto donde la información se separa: nadie recibe las fichas de otro, así que un
## cliente modificado no puede mostrar lo que nunca le llegó.
func _push_snapshots() -> void:
	var pub: Dictionary = Protocol.encode_public_view(_session.public_view())
	for seat in _peer_at.keys():
		var seat_index: int = int(seat)
		_send(int(_peer_at[seat_index]), {
			"type": Protocol.S_SNAPSHOT,
			"pub": pub,
			"mine": Protocol.encode_private_view(_session.private_view(seat_index)),
		})


func _broadcast(msg: Dictionary) -> void:
	for peer_id in _seat_of.keys():
		_send(int(peer_id), msg)


func _send(peer_id: int, msg: Dictionary) -> void:
	outbound.emit(peer_id, msg)


func _error(peer_id: int, reason: String) -> void:
	_send(peer_id, {"type": Protocol.S_ERROR, "reason": reason})


# ===========================================================================
# Lo que anuncia la sesión
# ===========================================================================
func _on_session_events(list: Array) -> void:
	# Una lista que solo trae rechazos no es noticia de la mesa: es la respuesta a
	# quien mandó algo inválido, y va solo para esa persona.
	if _only_rejections(list):
		if _acting_peer >= 0:
			_send(_acting_peer, {"type": Protocol.S_EVENTS, "list": Protocol.encode_events(list)})
		return
	_broadcast({"type": Protocol.S_EVENTS, "list": Protocol.encode_events(list)})


func _on_session_state_changed() -> void:
	_push_snapshots()


func _on_session_hand_started() -> void:
	_broadcast({"type": Protocol.S_HAND_STARTED})


func _on_session_hand_ended(closing: Dictionary, reveal: Dictionary) -> void:
	_broadcast({
		"type": Protocol.S_HAND_ENDED,
		"closing": Protocol.encode_event(closing),
		"reveal": Protocol.encode_reveal(reveal),
	})


func _on_session_match_ended(winner_team: int) -> void:
	phase = Phase.FINISHED
	_pending = {}
	_broadcast({"type": Protocol.S_MATCH_ENDED, "winner_team": winner_team})
	broadcast_lobby()


## Le toca a "seat". Si hay una persona sentada ahí y tiene con qué jugar, se espera su
## mensaje. Si no (silla vacía o pase forzado), lo mueve la sala tras una pausa.
func _on_session_turn_ready(seat: int, must_pass: bool) -> void:
	if _peer_at.has(seat) and not must_pass:
		return
	_pending = {
		"seat": seat,
		"must_pass": must_pass,
		"hand_id": _session.hand_id,
		"wait": AI_TURN_DELAY,
	}


# ===========================================================================
# Interno
# ===========================================================================
func _only_rejections(list: Array) -> bool:
	if list.is_empty():
		return false
	for e in list:
		if str(e.get("type", "")) != "rejected":
			return false
	return true


func _first_free_seat() -> int:
	for seat in range(GameState.SEAT_COUNT):
		if not _peer_at.has(seat):
			return seat
	return -1


func _lowest_occupied_seat() -> int:
	for seat in range(GameState.SEAT_COUNT):
		if _peer_at.has(seat):
			return seat
	return -1


func _touch() -> void:
	_idle = 0.0
