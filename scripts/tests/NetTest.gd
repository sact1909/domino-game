extends Node

## Prueba de red de punta a punta: dos clientes de verdad, con sockets de verdad,
## contra el servidor de salas.
##
## No corre con el resto del arnés porque NECESITA un servidor escuchando, y un arnés
## que depende de otro proceso no sirve para CI. Se corre a mano, en dos terminales:
##
##   godot --headless -- --server
##   godot --headless -- --test-net
##
## Con --server-url=... apunta a otro servidor (por ejemplo el desplegado).
##
## Lo que prueba y el arnés normal no puede: que el JSON sobreviva el viaje, que los
## puestos los asigne el servidor, que a cada cliente le lleguen SOLO sus fichas, y que
## los números vuelvan como enteros y no como flotantes — que es lo que rompería la
## pantalla al usarlos como índice.

## Meta baja a propósito: el mínimo que acepta el servidor. Así la partida termina en
## una o dos manos y "match_ended" se prueba de verdad, en vez de quedar sin cobertura.
## Con metas altas la prueba tardaría minutos y ese mensaje no llegaría nunca.
const TARGET_SCORE := 50

## Tope de manos, solo para no quedarse girando si algo impidiera llegar a la meta.
const MAX_HANDS := 8

## Topes de espera, en segundos. Generosos a propósito: contra un servidor remoto hay
## latencia, y los puestos de la IA se mueven cada 0.6 s.
const CONNECT_TIMEOUT := 15.0
const STEP_TIMEOUT := 20.0
const HAND_TIMEOUT := 120.0

var _clients: Array = []
var _failures: Array = []
var _step: int = 0
var _elapsed: float = 0.0
var _code: String = ""
var _hands_done: int = 0
var _plays_sent: int = 0
var _finished: bool = false

## Si se mandó una jugada y todavía no llegó el estado nuevo. Sin esto el guion vuelve
## a mandar la misma jugada en cada cuadro hasta que el snapshot la confirme, y el
## servidor las rechaza: fue así como salió a la luz que el cliente necesita lo mismo.
var _awaiting: bool = false

## La partida terminó y con qué pareja. Es un final legítimo, no una falla: sin esto la
## prueba seguía pidiendo jugadas a una partida cerrada hasta agotar la espera.
var _match_over: bool = false
var _winner_team: int = -1


func _ready() -> void:
	var url: String = WsClientTransport.resolve_url()
	print("[red] conectando dos clientes a %s" % url)

	for i in range(2):
		var t := WsClientTransport.new(url)
		_clients.append({
			"transport": t,
			"seat": -1,
			"pub": {},
			"mine": {},
			"errors": [],
			"joined": false,
			"is_host": false,
			"hand_ended": false,
			"reveal": {},
			"hands_started": 0,
			"connected": false,
		})
		t.connected.connect(_on_connected.bind(i))
		t.connection_failed.connect(_on_connection_failed.bind(i))
		t.room_joined.connect(_on_room_joined.bind(i))
		t.seat_assigned.connect(_on_seat_assigned.bind(i))
		t.snapshot.connect(_on_snapshot.bind(i))
		t.hand_started.connect(_on_hand_started.bind(i))
		t.hand_ended.connect(_on_hand_ended.bind(i))
		t.match_ended.connect(_on_match_ended.bind(i))
		t.server_error.connect(_on_server_error.bind(i))
		add_child(t)
		t.begin()


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	var limit: float = CONNECT_TIMEOUT if _step == 0 else (HAND_TIMEOUT if _step >= 6 else STEP_TIMEOUT)
	if _elapsed > limit:
		_fail("se agotó la espera en el paso %d" % _step)
		_report()
		return
	_advance()


func _next_step() -> void:
	_step += 1
	_elapsed = 0.0


# ===========================================================================
# El guion
# ===========================================================================
func _advance() -> void:
	if _step == 0:
		if bool(_clients[0].connected) and bool(_clients[1].connected):
			print("[red] los dos clientes conectados")
			_transport(0).create_room("Ana")
			_next_step()
		return

	if _step == 1:
		if not bool(_clients[0].joined):
			return
		_check(RoomCode.is_valid(_code), "el código no es válido: %s" % _code)
		_check(int(_clients[0].seat) == 0, "quien crea la sala debería quedar en el puesto 0")
		_check(bool(_clients[0].is_host), "quien crea la sala debería ser el anfitrión")
		print("[red] sala creada: %s" % _code)
		# Con el código tal como lo pega la gente: minúscula y con un guion.
		_transport(1).join_room(_code.to_lower().insert(2, "-"), "Beto")
		_next_step()
		return

	if _step == 2:
		if not bool(_clients[1].joined):
			return
		_check(int(_clients[1].seat) == 1, "el segundo debería entrar en el puesto 1")
		print("[red] entró el segundo en el puesto %d" % int(_clients[1].seat))
		# Quien organiza es el anfitrión, no cada uno por su cuenta. Intercambia las sillas
		# 1 y 2 para que los dos humanos queden enfrentados, que es ser compañeros.
		_transport(0).swap_seats(1, 2)
		_next_step()
		return

	if _step == 3:
		if int(_clients[1].seat) != 2:
			return
		print("[red] el anfitrión reorganizó: el segundo pasó al puesto 2 y quedan de pareja")
		_transport(0).start_match({"target_score": TARGET_SCORE})
		_next_step()
		return

	if _step == 4:
		if _mine(0).is_empty() or _mine(1).is_empty():
			return
		_check_deal()
		_check_reattach()
		_next_step()
		return

	if _step == 5:
		# Jugar fuera de turno tiene que rebotar del servidor. Es la comprobación de
		# que el puesto sale de la conexión y no del mensaje.
		var current: int = int(_pub(0).current_player)
		var intruder: int = 1 if int(_clients[0].seat) == current else 0
		_clients[intruder].errors = []
		_transport(intruder).request_play(0, "L")
		_next_step()
		return

	if _step == 6:
		var pending: Array = _clients[0].errors + _clients[1].errors
		if pending.is_empty():
			return
		_check(str(pending[0]) == "no_es_su_turno", "el rechazo llegó con el motivo %s" % str(pending[0]))
		print("[red] jugada fuera de turno rechazada por el servidor: %s" % str(pending[0]))
		_next_step()
		return

	if _step == 7:
		_play_hands()
		return


## Juega como jugarían dos personas: cada uno solo usa lo que le llegó en su snapshot.
## Los otros dos puestos están vacíos y los mueve la IA del servidor, cada 0.6 s.
##
## Hay dos finales posibles y los dos son legítimos: que cierre una mano y siga otra, o
## que alguien llegue a la meta y termine la partida. La meta es baja a propósito para
## que el segundo ocurra rápido — así "match_ended" queda probado por el cable, que es
## el único mensaje del servidor que no tenía ninguna cobertura.
func _play_hands() -> void:
	if _match_over:
		_check_match_end()
		_report()
		return

	if bool(_clients[0].hand_ended) and bool(_clients[1].hand_ended):
		_check_hand_end()
		_hands_done += 1
		if _hands_done > MAX_HANDS:
			_fail("se jugaron %d manos sin que nadie llegara a la meta de %d" % [_hands_done, TARGET_SCORE])
			_report()
			return
		for c in _clients:
			c.hand_ended = false
			c.reveal = {}
		_elapsed = 0.0
		_transport(0).request_continue()
		return

	# Con una jugada en vuelo no se manda otra: si no, se vuelve a mandar la misma en
	# cada cuadro hasta que llegue el estado nuevo, y el servidor las rechaza.
	if _awaiting:
		return

	var current: int = int(_pub(0).current_player)
	for i in range(2):
		if int(_clients[i].seat) != current:
			continue
		var moves: Array = _mine(i).legal_moves
		if moves.is_empty():
			return
		var m: Dictionary = moves[0]
		_awaiting = true
		_transport(i).request_play(int(m.idx), str(m.ends[0]))
		_plays_sent += 1
		_elapsed = 0.0
		return


# ===========================================================================
# Comprobaciones
# ===========================================================================
func _check_deal() -> void:
	var tiles_a: Array = _mine(0).tiles
	var tiles_b: Array = _mine(1).tiles
	_check(tiles_a.size() == GameState.TILES_PER_HAND, "el primero recibió %d fichas" % tiles_a.size())
	_check(tiles_b.size() == GameState.TILES_PER_HAND, "el segundo recibió %d fichas" % tiles_b.size())

	# Lo que solo se puede comprobar con dos conexiones de verdad: por el cable no le
	# viaja a nadie una ficha ajena.
	for ta in tiles_a:
		for tb in tiles_b:
			if str(ta) == str(tb):
				_fail("la ficha %s les llegó a los dos" % str(ta))

	# Y que cada uno reciba SU mano, no la del otro.
	_check(int(_mine(0).seat) == int(_clients[0].seat), "la vista privada del primero no es de su puesto")
	_check(int(_mine(1).seat) == int(_clients[1].seat), "la vista privada del segundo no es de su puesto")

	# Los números tienen que volver como ENTEROS. JSON los manda como flotantes, y la
	# pantalla los usa de índice (SEAT_NAMES[pub.current_player]): con un flotante ahí,
	# GDScript falla. Se comprueba el tipo, no el valor, porque 2.0 == 2 es verdadero y
	# el error no aparecería hasta el momento de indexar.
	var pub: Dictionary = _pub(0)
	_check(typeof(pub.current_player) == TYPE_INT, "current_player volvió como %s" % type_string(typeof(pub.current_player)))
	_check(typeof(pub.left_end) == TYPE_INT, "left_end volvió como %s" % type_string(typeof(pub.left_end)))
	_check(typeof(pub.target_score) == TYPE_INT, "target_score volvió como %s" % type_string(typeof(pub.target_score)))
	var counts: Array = pub.hand_counts
	_check(typeof(counts[0]) == TYPE_INT, "hand_counts volvió como %s" % type_string(typeof(counts[0])))
	var moves: Array = _mine(0).legal_moves
	if not moves.is_empty():
		_check(typeof(moves[0].idx) == TYPE_INT, "el índice de jugada volvió como %s" % type_string(typeof(moves[0].idx)))

	print("[red] repartido: 7 y 7 fichas sin ninguna repetida, y los números volvieron enteros")


## Simula el traspaso del lobby a la mesa: el transporte sale del árbol y vuelve, y quien
## lo reengancha tiene que recibir el estado aunque los mensajes originales ya hayan
## pasado.
##
## Es el caso que dejaba la mesa en blanco. Los paquetes se drenan todos los que llegaron
## en el mismo poll(), así que cuando el aviso de "arrancó la partida" y el primer
## snapshot vienen juntos, el lobby procesa el primero, suelta el socket para el
## traspaso, y el bucle sigue emitiendo el snapshot a nadie: la mesa todavía no existe.
## Acá se fuerza ese orden a propósito —primero se recibe todo, después se reengancha— y
## se comprueba que el transporte lo repita.
func _check_reattach() -> void:
	var t: WsClientTransport = _transport(0)
	var seat_before: int = int(_clients[0].seat)
	var starts_before: int = int(_clients[0].hands_started)

	# Se borra lo que ya se vio: si el reengancho no repite nada, esto queda vacío, que es
	# exactamente lo que le pasaba a la pantalla.
	_clients[0].pub = {}
	_clients[0].mine = {}
	_clients[0].seat = -1

	var parent: Node = t.get_parent()
	parent.remove_child(t)
	parent.add_child(t)
	t.begin()

	_check(int(_clients[0].seat) == seat_before, "al reengancharse no se repitió el puesto")
	_check(int(_clients[0].hands_started) > starts_before, "al reengancharse no se repitió el aviso de mano en curso")
	_check(not _mine(0).is_empty(), "al reengancharse no se repitió el snapshot: la mesa quedaría en blanco")
	if _mine(0).is_empty():
		return
	var tiles: Array = _mine(0).tiles
	_check(tiles.size() == GameState.TILES_PER_HAND, "el snapshot repetido trajo %d fichas" % tiles.size())
	print("[red] reengancho: el transporte repitió el puesto, la mano y el estado de la partida")


func _check_hand_end() -> void:
	for i in range(2):
		var reveal: Dictionary = _clients[i].reveal
		_check(not reveal.is_empty(), "al cliente %d no le llegó el destape" % i)
		if reveal.is_empty():
			continue
		_check(bool(reveal.hand_over), "el destape llegó sin la mano marcada como cerrada")
		var hands: Array = reveal.hands
		_check(hands.size() == GameState.SEAT_COUNT, "el destape trajo %d manos" % hands.size())
	print("[red] mano cerrada: el destape llegó a los dos con las cuatro manos")


## El otro final: alguien llegó a la meta. El servidor no cierra una partida sin que se
## haya llegado de verdad, así que se comprueba contra el marcador que ya viajó.
func _check_match_end() -> void:
	_check(_hands_done >= 1, "la partida terminó sin que se cerrara ninguna mano")
	_check(_winner_team == 0 or _winner_team == 1, "la pareja ganadora llegó como %d" % _winner_team)
	if _winner_team != 0 and _winner_team != 1:
		return

	var scores: Array = _pub(0).team_score
	_check(int(scores[_winner_team]) >= TARGET_SCORE, "gana la pareja %d con %d puntos, sin llegar a la meta de %d" % [_winner_team, int(scores[_winner_team]), TARGET_SCORE])

	# Dos puestos humanos, siete fichas cada uno: por mano no pueden salir más de 14
	# jugadas. Si se pasa, se están mandando duplicadas.
	var ceiling: int = _hands_done * 2 * GameState.TILES_PER_HAND
	_check(_plays_sent <= ceiling, "se mandaron %d jugadas y el máximo posible era %d: hay duplicadas" % [_plays_sent, ceiling])

	print("[red] partida terminada en %d mano(s): gana la pareja %d, marcador %d-%d" % [_hands_done, _winner_team, int(scores[0]), int(scores[1])])
	print("[red] %d jugadas mandadas por los humanos (máximo posible %d)" % [_plays_sent, ceiling])
	print("[red] el cliente de red funciona de punta a punta")


# ===========================================================================
# Recepción
# ===========================================================================
func _on_connected(i: int) -> void:
	_clients[i].connected = true


func _on_connection_failed(reason: String, i: int) -> void:
	_fail("el cliente %d no pudo conectar: %s" % [i, reason])
	printerr("[red] ¿está corriendo el servidor?  godot --headless -- --server")
	_report()


func _on_room_joined(code: String, seat: int, is_host: bool, i: int) -> void:
	_code = code
	_clients[i].seat = seat
	_clients[i].is_host = is_host
	_clients[i].joined = true


func _on_seat_assigned(seat: int, i: int) -> void:
	_clients[i].seat = seat


func _on_snapshot(pub: Dictionary, mine: Dictionary, i: int) -> void:
	_clients[i].pub = pub
	_clients[i].mine = mine
	_awaiting = false


func _on_hand_started(i: int) -> void:
	_clients[i].hands_started = int(_clients[i].hands_started) + 1


func _on_hand_ended(closing: Dictionary, reveal: Dictionary, i: int) -> void:
	_clients[i].hand_ended = true
	_clients[i].reveal = reveal


# Les llega a los dos, así que entra dos veces: por eso solo anota, sin acumular.
func _on_match_ended(winner_team: int, _i: int) -> void:
	_match_over = true
	_winner_team = winner_team


func _on_server_error(reason: String, i: int) -> void:
	_clients[i].errors.append(reason)
	# Un rechazo no trae estado nuevo, así que hay que desbloquear igual: si no, el
	# guion se quedaría esperando un snapshot que no va a llegar.
	_awaiting = false


# ===========================================================================
# Andamios
# ===========================================================================
func _transport(i: int) -> WsClientTransport:
	return _clients[i].transport


func _pub(i: int) -> Dictionary:
	return _clients[i].pub


func _mine(i: int) -> Dictionary:
	return _clients[i].mine


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _fail(what: String) -> void:
	_failures.append(what)


func _report() -> void:
	_finished = true
	if _failures.is_empty():
		print("[red] TODO BIEN")
		get_tree().quit(0)
		return
	printerr("[red] %d fallo(s):" % _failures.size())
	for f in _failures:
		printerr("  - %s" % f)
	get_tree().quit(1)
