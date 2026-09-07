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

## Cuánto se espera por una PERSONA antes de jugarle su ficha.
##
## Es lo que evita que la mesa se quede quieta cuando alguien se levanta de la silla sin
## cerrar el juego. No es el mismo caso que caerse: ahí el socket se corta y la sala se
## entera en el acto; acá sigue conectado, así que para la sala esa persona está sentada
## y su turno le pertenece — hasta que se acabe el tiempo.
##
## Al vencerse NO se pasa. En el dominó dominicano no se pasa por gusto: si tienes con
## qué jugar, juegas. Así que se le juega la ficha que elegiría la IA, la misma que
## cubre las sillas vacías.
##
## 45 segundos es de sobra para pensar una jugada y poco para aguantar mirando a nadie.
const TURN_TIMEOUT := 45.0

## Una sala que se queda sin nadie se recoge pronto; una con gente adentro aguanta
## mucho más, porque "sin actividad" muchas veces es que están conversando.
const EMPTY_ROOM_TTL := 300.0
const IDLE_ROOM_TTL := 3600.0

## Y una sala que se queda vacía SIN haber empezado ninguna partida se recoge enseguida.
##
## Los cinco minutos de arriba existen por una razón concreta: que quien se cayó vuelva y
## encuentre su mesa. En una sala donde nunca se repartió no hay nada de eso — nadie tiene
## silla ni mano a la que volver, así que guardarla cinco minutos no le sirve a nadie y sí
## le sirve a quien quiera ocupar el cupo del servidor sin jugar.
##
## Treinta segundos y no cero: si a quien acaba de crear la sala se le cae la conexión
## justo después de repartir el código a sus amigos, tiene tiempo de volver a la misma.
const UNPLAYED_ROOM_TTL := 30.0

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

## Reloj del turno de una persona: por quién se espera, en qué mano y cuánto le queda.
## Vive aparte de "_pending" porque son cosas distintas: ese es un relevo agendado, y
## este es la espera por alguien que todavía tiene su turno.
var _turn_clock: Dictionary = {}

## Credencial de cada silla, para poder volver a sentarse después de una caída.
##
## Hace falta una porque la identidad de una conexión no sobrevive a la caída: al volver,
## el socket es otro y el servidor no tiene manera de reconocer a nadie. Y no puede ser el
## nombre: cualquiera que sepa el código de la sala podría decir que es Juan, sentarse en
## su silla y ver sus fichas. Con una credencial que solo tiene su cliente, no.
##
## Sale de un generador APARTE del de la partida. Si saliera del mismo, entregarle a un
## cliente 64 bits de esa secuencia le daría con qué adivinar la semilla del próximo
## reparto — que sale del mismo randi().
var _tokens: Dictionary = {}
var _token_rng := RandomNumberGenerator.new()

## Segundos sin actividad, para la recolección de salas.
var _idle: float = 0.0

## Si en esta sala se llegó a repartir alguna vez. Es lo que separa una mesa de verdad
## que se quedó vacía un momento —y a la que alguien puede volver— de una sala que solo
## ocupó sitio.
var _ever_played: bool = false

## Quién mandó la acción que se está aplicando. Un rechazo se le contesta SOLO a esa
## persona: no tiene por qué aparecerle en la mesa a los demás.
var _acting_peer: int = -1


func _init(room_code: String) -> void:
	code = room_code
	_token_rng.randomize()


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
	# Credencial nueva: sentarse en una silla invalida la del que estuvo antes en ella.
	_tokens[seat] = _new_token()
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
	# El nombre y la credencial se borran SOLO en el lobby. Con la partida en curso el
	# puesto sigue siendo de esa persona y lo juega la IA mientras tanto: el nombre tiene
	# que seguir a la vista para que los demás sepan de quién es la silla, y la credencial
	# es lo único que le va a permitir volver a sentarse.
	if phase == Phase.LOBBY:
		_names.erase(seat)
		_tokens.erase(seat)

	if _host_seat == seat:
		_host_seat = _lowest_occupied_seat()

	# Si se fue justo quien tenía el turno, hay que volver a mirar de quién es. Mientras
	# la silla estuvo ocupada la sala no agendó nada —le tocaba a esa persona y se
	# esperaba su mensaje—, así que el aviso de turno ya pasó y al quedarse sola no hay
	# nadie que juegue ni nada que despierte la mano: se quedaría quieta hasta que la
	# sala venciera, una hora después. Volver a anunciar el turno es lo mismo que habría
	# pasado si la silla hubiera estado vacía desde el principio, que ya funciona.
	if phase == Phase.PLAYING and not _session.hand_over() and _session.current_seat() == seat:
		_on_session_turn_ready(seat, _session.needs_forced_pass())

	_touch()
	broadcast_lobby()


## Vuelve a sentar a alguien en SU silla, con la credencial que se le dio al entrar.
## Devuelve el puesto, o -1 si la credencial no vale o si esa silla ya tiene a alguien.
##
## Funciona en cualquier fase. Con la partida en curso es el caso que importa —volver de
## una caída sin perder la mano—, pero también sirve en el lobby: si se cayó esperando,
## recupera su sitio en vez de que le toque otro y se le desarme la pareja.
func rejoin(peer_id: int, token: String) -> int:
	if _seat_of.has(peer_id):
		return int(_seat_of[peer_id])

	var seat: int = _seat_for_token(token)
	if seat < 0:
		_error(peer_id, "credencial_invalida")
		return -1
	# Ocupada quiere decir que alguien más está sentado ahí ahora. No se echa a nadie
	# de una silla en la que está jugando, ni con la credencial correcta.
	if _peer_at.has(seat):
		_error(peer_id, "silla_ocupada")
		return -1

	_seat_of[peer_id] = seat
	_peer_at[seat] = peer_id
	# Si mientras estuvo fuera se quedó la sala sin anfitrión, lo es quien vuelve: sin
	# eso la sala queda viva y nadie puede empezar ni cerrarla.
	if _host_seat < 0:
		_host_seat = seat

	_touch()
	return seat


## Le pone al día la mesa a quien acaba de volver: el estado, la mano en curso y el
## reloj del turno, todo SOLO para él — los demás no se enteran de nada porque para
## ellos no cambió nada.
##
## El orden es el mismo con el que viaja en vivo (primero el estado y después "empezó la
## mano") porque la pantalla lo necesita así: el aviso de mano nueva se dibuja leyendo el
## estado que ya tiene que estar puesto.
func catch_up(peer_id: int) -> void:
	if _session == null or not _seat_of.has(peer_id):
		return

	var seat: int = int(_seat_of[peer_id])
	_send(peer_id, {
		"type": Protocol.S_SNAPSHOT,
		"pub": Protocol.encode_public_view(_session.public_view()),
		"mine": Protocol.encode_private_view(_session.private_view(seat)),
	})

	if phase != Phase.PLAYING or _session.hand_over():
		return
	_send(peer_id, {"type": Protocol.S_HAND_STARTED})

	# Si volvió justo cuando le tocaba, la sala tenía agendado jugarle por silla vacía:
	# se vuelve a anunciar el turno y con la silla ocupada eso cancela el relevo y le
	# arranca su reloj. Si le toca a otro, solo se le dice cuánto le queda a ese.
	if _session.current_seat() == seat:
		_on_session_turn_ready(seat, _session.needs_forced_pass())
		return
	_send(peer_id, {
		"type": Protocol.S_TURN_CLOCK,
		"seat": int(_turn_clock.get("seat", -1)),
		"seconds": seconds_left_for_turn(),
	})


## La credencial de quien está sentado en un puesto, para poder mandársela al entrar.
func token_of(peer_id: int) -> String:
	if not _seat_of.has(peer_id):
		return ""
	return str(_tokens.get(int(_seat_of[peer_id]), ""))


func _seat_for_token(token: String) -> int:
	if token.is_empty():
		return -1
	for seat in _tokens.keys():
		if str(_tokens[seat]) == token:
			return int(seat)
	return -1


## 64 bits en hexadecimal. No se escribe a mano ni se dicta, así que no hace falta que
## sea corta ni que evite letras que se confundan, al contrario del código de la sala.
func _new_token() -> String:
	return "%08x%08x" % [_token_rng.randi(), _token_rng.randi()]

## Intercambia lo que hay en dos sillas. Es la ÚNICA manera de reorganizar la mesa, y
## solo la puede usar el anfitrión.
##
## Antes cada quien elegía su lado, y eso traía una carrera fea: dos personas apuntando
## al mismo sitio y una llevándose un rechazo. Con una sola persona repartiendo no hay
## nada que negociar, que es como funciona en una mesa de verdad — quien invita dice
## quién se sienta con quién.
##
## Se intercambian SILLAS y no "lados" porque con la mesa llena mover a alguien de lado
## obliga a que otro salga, y el intercambio dice exactamente quién. Con eso se llega a
## cualquier reparto de equipos, cosa que "pasar al otro lado" no garantiza.
func swap_seats(peer_id: int, a: int, b: int) -> bool:
	if phase != Phase.LOBBY:
		_error(peer_id, "partida_en_curso")
		return false
	if not _seat_of.has(peer_id):
		_error(peer_id, "no_estas_en_la_sala")
		return false
	if int(_seat_of[peer_id]) != _host_seat:
		_error(peer_id, "solo_el_anfitrion")
		return false
	if a < 0 or a >= GameState.SEAT_COUNT or b < 0 or b >= GameState.SEAT_COUNT:
		_error(peer_id, "puesto_invalido")
		return false
	if a == b:
		return true
	if not _peer_at.has(a) and not _peer_at.has(b):
		# Cambiar dos sillas vacías no hace nada, pero conviene decirlo: si no, el
		# anfitrión cree que tocó algo y no ve ningún cambio.
		_error(peer_id, "sillas_vacias")
		return false

	var peer_a: int = int(_peer_at.get(a, -1))
	var peer_b: int = int(_peer_at.get(b, -1))
	var name_a: String = str(_names.get(a, ""))
	var name_b: String = str(_names.get(b, ""))

	_peer_at.erase(a)
	_peer_at.erase(b)
	_names.erase(a)
	_names.erase(b)
	if peer_a >= 0:
		_peer_at[b] = peer_a
		_names[b] = name_a
		_seat_of[peer_a] = b
	if peer_b >= 0:
		_peer_at[a] = peer_b
		_names[a] = name_b
		_seat_of[peer_b] = a

	if _host_seat == a:
		_host_seat = b
	elif _host_seat == b:
		_host_seat = a

	_touch()
	# A cada uno que se movió se le dice su silla nueva aparte: el lobby es una difusión,
	# el mismo mensaje para los cuatro, y no puede decirle a cada uno cuál es la suya.
	if peer_a >= 0:
		_send(peer_a, {"type": Protocol.S_SEAT_ASSIGNED, "seat": b})
	if peer_b >= 0:
		_send(peer_b, {"type": Protocol.S_SEAT_ASSIGNED, "seat": a})
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
	# Desde acá la sala ya vale la pena guardarla un rato aunque se quede vacía: hay
	# manos repartidas y sillas con dueño, o sea gente que puede volver.
	_ever_played = true
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
	_tick_turn_clock(delta)

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

	_play_for(int(job.seat), bool(job.must_pass))


## Le descuenta el tiempo a quien tiene el turno y, si se le acaba, le juega la ficha.
##
## La comprobación de la mano es la misma que en los relevos agendados y por lo mismo:
## entre que arrancó el reloj y ahora, la mano pudo cerrar y empezar otra, y jugarle a
## la silla movería una mano que ya no es la que se estaba jugando.
func _tick_turn_clock(delta: float) -> void:
	if _turn_clock.is_empty():
		return

	_turn_clock["left"] = float(_turn_clock.left) - delta
	if float(_turn_clock.left) > 0.0:
		return

	var job: Dictionary = _turn_clock
	_turn_clock = {}
	if int(job.hand_id) != _session.hand_id or _session.hand_over():
		return

	print("[sala %s] se le acabó el tiempo al puesto %d: le juega la sala" % [code, int(job.seat)])
	_play_for(int(job.seat), false)


## Juega por una silla. Es el MISMO relevo para los tres casos en que la sala mueve por
## alguien —silla vacía, pase forzado y reloj vencido—, así que los tres se comportan
## igual y no hay tres maneras distintas de jugarle a un puesto.
func _play_for(seat: int, must_pass: bool) -> void:
	if must_pass:
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


## Segundos que le quedan a quien tiene el turno, o 0 si no se está esperando por nadie
## (silla vacía, pase forzado o mano cerrada: en esos casos mueve la sala).
func seconds_left_for_turn() -> float:
	if _turn_clock.is_empty():
		return 0.0
	return maxf(0.0, float(_turn_clock.left))


## Cuándo recoger esta sala. Son tres plazos distintos porque son tres situaciones
## distintas: vacía sin haber jugado no le sirve a nadie, vacía después de jugar puede
## estar esperando a que vuelva quien se cayó, y con gente adentro puede ser simplemente
## que estén conversando.
func should_expire() -> bool:
	if is_empty():
		return _idle >= (EMPTY_ROOM_TTL if _ever_played else UNPLAYED_ROOM_TTL)
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
	# Con la mano cerrada no se espera por nadie: lo que sigue es que alguien pida
	# seguir, y para eso alcanza con uno cualquiera, así que no hace falta reloj.
	_turn_clock = {}
	_broadcast({
		"type": Protocol.S_HAND_ENDED,
		"closing": Protocol.encode_event(closing),
		"reveal": Protocol.encode_reveal(reveal),
	})


func _on_session_match_ended(winner_team: int) -> void:
	phase = Phase.FINISHED
	_pending = {}
	_turn_clock = {}
	_broadcast({"type": Protocol.S_MATCH_ENDED, "winner_team": winner_team})
	broadcast_lobby()


## Le toca a "seat".
##
## Si hay una persona sentada ahí y tiene con qué jugar, se espera SU mensaje, pero con
## un reloj corriendo: al vencerse le juega la sala (ver TURN_TIMEOUT). Si la silla está
## vacía o toca pase forzado, lo mueve la sala tras una pausa corta.
##
## En los dos casos se le dice a la mesa cuánto se espera por ese puesto, y cuando no se
## espera nada va en cero: así el cliente no tiene que adivinar si hay reloj o no.
func _on_session_turn_ready(seat: int, must_pass: bool) -> void:
	# Un aviso de turno nuevo deja sin valor cualquier relevo agendado: era para el turno
	# anterior, y cumplirlo ahora movería la silla equivocada.
	_pending = {}
	_turn_clock = {}

	if _peer_at.has(seat) and not must_pass:
		_turn_clock = {
			"seat": seat,
			"hand_id": _session.hand_id,
			"left": TURN_TIMEOUT,
		}
		_announce_turn_clock(seat, TURN_TIMEOUT)
		return

	_pending = {
		"seat": seat,
		"must_pass": must_pass,
		"hand_id": _session.hand_id,
		"wait": AI_TURN_DELAY,
	}
	_announce_turn_clock(seat, 0.0)


func _announce_turn_clock(seat: int, seconds: float) -> void:
	_broadcast({
		"type": Protocol.S_TURN_CLOCK,
		"seat": seat,
		"seconds": seconds,
	})


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


# ===========================================================================
# Lados, revancha y cierre
# ===========================================================================
## Volver al lobby con la sala intacta: las mismas personas en las mismas sillas.
##
## Alcanza con que UNO lo pida, igual que para seguir tras una mano: esperar a los cuatro
## deja la sala colgada en cuanto alguien se distrae, y quien todavía esté mirando el
## resultado se entera por la difusión del lobby.
func play_again(peer_id: int) -> bool:
	if not _seat_of.has(peer_id):
		_error(peer_id, "no_estas_en_la_sala")
		return false
	if phase == Phase.LOBBY:
		# Alguien se adelantó. No es un error: solo hay que ponerlo al día.
		broadcast_lobby()
		return true
	if phase != Phase.FINISHED:
		_error(peer_id, "partida_en_curso")
		return false

	phase = Phase.LOBBY
	# La sesión se suelta entera. Reusarla arrastraría el marcador y el reparto de la
	# partida anterior, y esto es una partida nueva con la misma gente.
	_session = null
	_pending = {}
	_turn_clock = {}
	_acting_peer = -1
	_touch()
	broadcast_lobby()
	return true


## Avisa a todos que la sala se cierra. Quien la borra es el registro, que es el que
## lleva la cuenta de las salas vivas.
func announce_closed() -> void:
	_broadcast({"type": Protocol.S_ROOM_CLOSED})


