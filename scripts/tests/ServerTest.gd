class_name ServerTest
extends RefCounted

## Pruebas del lado del servidor, sin abrir ningún puerto.
##
## Se puede porque ni Room ni RoomRegistry saben qué es un socket: lo que quieren
## mandar sale por una señal, y acá se recoge en una lista. Y porque el ritmo va por
## tick(delta) en vez de await, así que una partida entera se juega en un instante
## adelantando el reloj a mano.
##
## Lo que más importa de todo esto son dos cosas que solo existen en red y que no se
## pueden comprobar jugando: que a nadie le lleguen las fichas de otro, y que un
## cliente modificado no pueda jugar en nombre ajeno.
##
## Corre dentro de "godot --headless -- --test", junto con las pruebas de reglas.

## Código fijo para las pruebas: no se generan al azar cuando lo que se prueba es otra
## cosa, así una falla siempre se lee igual.
const TEST_CODE := "BCDFG"

var failures: Array = []
var checks: int = 0

# Lo que la sala mandó, y el último estado que vio cada jugador. Es exactamente lo que
# tendría un cliente: nada de mirar por dentro.
var _sent: Array = []
var _last_pub: Dictionary = {}
var _mine_by_peer: Dictionary = {}
var _hand_ended_peers: Array = []
var _match_ended_peers: Array = []


func run() -> void:
	_test_room_code()
	_test_protocol_tiles()
	_test_protocol_views()
	_test_room_lobby()
	_test_name_sanitizing()
	_test_information_separation()
	_test_turn_ownership()
	_test_full_hand()
	_test_ai_seats()
	_test_registry()
	_test_expiry()


# ===========================================================================
# Códigos
# ===========================================================================
func _test_room_code() -> void:
	# Lo primero es el alfabeto en sí: es la decisión de diseño, y si alguien le
	# agrega una vocal o un cero "para tener más códigos", la prueba lo frena.
	for ch in "0O1IL":
		_check(not RoomCode.ALPHABET.contains(ch), "el alfabeto no debe traer %s" % ch)
	for ch in "AEIOU":
		_check(not RoomCode.ALPHABET.contains(ch), "el alfabeto no debe traer vocales (%s)" % ch)
	_check(RoomCode.ALPHABET.length() == 20, "el alfabeto debería tener 20 letras")

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var seen: Dictionary = {}
	for i in range(4000):
		var code: String = RoomCode.generate(rng)
		_check(RoomCode.is_valid(code), "código generado inválido: %s" % code)
		for ch in code:
			seen[ch] = true

	# Que las 20 letras salgan alguna vez: caza un error de rango en el sorteo, como
	# dejar afuera la última letra del alfabeto.
	_check(seen.size() == RoomCode.ALPHABET.length(), "el sorteo no usa todas las letras (%d de %d)" % [seen.size(), RoomCode.ALPHABET.length()])

	# Como lo teclea la gente: minúscula, guiones para leerlo, espacios de sobra.
	_check(RoomCode.normalize("  bcd-fg ") == "BCDFG", "normalize debería aceptar minúsculas, guiones y espacios")
	_check(RoomCode.normalize("bc.d f/g") == "BCDFG", "normalize debería descartar los separadores")
	_check(RoomCode.normalize("BCDFGH") == "BCDFGH", "normalize no debería recortar")

	_check(not RoomCode.is_valid("BCDF"), "un código corto no es válido")
	_check(not RoomCode.is_valid("BCDFGH"), "un código largo no es válido")
	_check(not RoomCode.is_valid("BCDFA"), "un código con vocal no es válido")
	_check(not RoomCode.is_valid("BCDF0"), "un código con cero no es válido")


# ===========================================================================
# Protocolo
# ===========================================================================
func _test_protocol_tiles() -> void:
	# Las 28 fichas, ida y vuelta. Es barato probarlas todas y así no queda ninguna
	# duda sobre el 0-0 ni sobre los dobles.
	for a in range(GameState.MAX_PIP + 1):
		for b in range(a, GameState.MAX_PIP + 1):
			var original := Domino.new(a, b)
			var back: Domino = Protocol.decode_tile(Protocol.encode_tile(original))
			if back == null:
				_fail("la ficha %d-%d no sobrevivió la ida y vuelta" % [a, b])
				continue
			_check(back.a == a and back.b == b, "la ficha %d-%d volvió como %s" % [a, b, str(back)])

	# Lo que puede llegar de un cliente modificado. Se rechaza en vez de inventar una
	# ficha: una ficha inventada en la mesa no da error, solo deja una mesa imposible.
	#
	# El decodificador avisa por consola cuando le llega basura, y eso es lo que
	# queremos: acá se le está dando basura a propósito, así que el ERROR que sale a
	# continuación es la prueba funcionando, no una falla.
	print("[test] (el ERROR que sigue es a propósito: se le da basura al decodificador)")
	_check(Protocol.decode_tile("6-5") == null, "un texto no es una ficha")
	_check(Protocol.decode_tile([6]) == null, "un par incompleto no es una ficha")
	_check(Protocol.decode_tile([6, 5, 4]) == null, "una lista de tres no es una ficha")
	_check(Protocol.decode_tile([7, 5]) == null, "una cara de 7 no existe")
	_check(Protocol.decode_tile([-1, 5]) == null, "una cara negativa no existe")

	# Media lista es peor que ninguna: el juego seguiría con un tablero al que le
	# faltan piezas y nadie se enteraría.
	_check(Protocol.decode_tiles([[6, 6], [9, 9]]).is_empty(), "una lista con una ficha mala se descarta entera")


func _test_protocol_views() -> void:
	# Un estado de verdad, con la mesa empezada, para que las vistas tengan contenido.
	var gs := GameState.new()
	gs.reset_match()
	gs.deal(777)
	var opener: int = gs.current_player
	var moves: Array = gs.legal_moves_for(opener)
	gs.apply_play(opener, int(moves[0].idx), str(moves[0].ends[0]))

	# Lo que de verdad hay que garantizar: que en lo codificado NO quede ningún objeto.
	# Se recorre todo en vez de mirar las claves conocidas, así que si mañana alguien
	# le agrega a una vista un campo con fichas adentro, esta prueba lo caza antes de
	# que el servidor mande un mensaje que el cliente no puede leer.
	_check_json_safe(Protocol.encode_public_view(gs.public_view()), "vista pública")
	_check_json_safe(Protocol.encode_private_view(gs.private_view(opener)), "vista privada")
	_check_json_safe(Protocol.encode_events([{"type": "played", "seat": 0, "tile": Domino.new(6, 6), "was_opening": true}]), "eventos")

	# Ida y vuelta pasando por JSON de verdad, que es lo que va a ocurrir en el cable.
	var pub_back: Dictionary = Protocol.decode_public_view(_through_json(Protocol.encode_public_view(gs.public_view())))
	var pub_board: Array = pub_back.board
	_check(pub_board.size() == gs.board.size(), "el tablero cambió de tamaño al ir y volver")
	for i in range(pub_board.size()):
		var before: Domino = gs.board[i]
		var after: Domino = pub_board[i]
		_check(after.a == before.a and after.b == before.b, "la ficha %d del tablero volvió distinta" % i)
	_check(int(pub_back.current_player) == gs.current_player, "current_player no sobrevivió")
	_check(int(pub_back.left_end) == gs.left_end, "left_end no sobrevivió")

	var mine_back: Dictionary = Protocol.decode_private_view(_through_json(Protocol.encode_private_view(gs.private_view(opener))))
	var tiles: Array = mine_back.tiles
	_check(tiles.size() == gs.hands[opener].size(), "la mano cambió de tamaño al ir y volver")
	var legal: Array = mine_back.legal_moves
	_check(legal.size() == gs.legal_moves_for(opener).size(), "las jugadas legales no sobrevivieron")

	# El destape: cuatro manos, y las 28 fichas repartidas entre manos y mesa.
	var reveal_back: Dictionary = Protocol.decode_reveal(_through_json(Protocol.encode_reveal(gs.reveal_view())))
	var hands: Array = reveal_back.hands
	_check(hands.size() == GameState.SEAT_COUNT, "el destape no trajo cuatro manos")
	var total: int = pub_board.size()
	for hand in hands:
		total += (hand as Array).size()
	_check(total == 28, "entre el destape y la mesa hay %d fichas, no 28" % total)

	# Un evento con ficha adentro, que es el único que la lleva.
	var events_back: Array = Protocol.decode_events(_through_json_array(Protocol.encode_events([
		{"type": "played", "seat": 2, "tile": Domino.new(4, 1), "was_opening": false},
	])))
	_check(events_back.size() == 1, "el evento se perdió")
	var tile_back: Domino = events_back[0].tile
	_check(tile_back != null and tile_back.a == 4 and tile_back.b == 1, "la ficha del evento volvió distinta")


# ===========================================================================
# Sala: lobby, sillas y anfitrión
# ===========================================================================
func _test_room_lobby() -> void:
	var room := _new_room()

	_check(room.add_member(101, "Ana") == 0, "el primero debería quedar en el puesto 0")
	_check(room.add_member(102, "Beto") == 1, "el segundo debería quedar en el puesto 1")
	_check(room.add_member(103, "Cami") == 2, "el tercero debería quedar en el puesto 2")
	_check(room.add_member(104, "Dani") == 3, "el cuarto debería quedar en el puesto 3")
	_check(room.add_member(105, "Quinto") == -1, "el quinto no cabe")
	_check(room.member_count() == 4, "la sala debería tener cuatro")

	# El anfitrión es quien la creó, y si se va lo hereda el puesto ocupado más bajo:
	# si no, la sala quedaría viva sin que nadie pueda arrancar.
	_check(room.is_host(101), "el primero debería ser el anfitrión")
	_check(not room.is_host(102), "el segundo no debería ser anfitrión")
	room.remove_member(101)
	_check(room.host_seat() == 1, "el anfitrión debería pasar al puesto 1")
	_check(room.is_host(102), "el segundo debería heredar el anfitrionazgo")

	# Cambiar de silla es lo que decide las parejas: los puestos enfrentados son
	# compañeros, así que moverse del 1 al 0 cambia con quién juegas.
	_check(room.set_seat(102, 0), "debería poder moverse al puesto 0, que quedó libre")
	_check(room.seat_of(102) == 0, "el puesto no se actualizó")
	_check(room.host_seat() == 0, "el anfitrión debería seguir a quien se movió")
	_check(not room.set_seat(103, 0), "no debería poder sentarse en una silla ocupada")
	_check(_last_error_for(103) == "puesto_ocupado", "el motivo debería ser puesto_ocupado")
	_check(not room.set_seat(103, 9), "no debería aceptar un puesto que no existe")
	_check(_last_error_for(103) == "puesto_invalido", "el motivo debería ser puesto_invalido")

	# Solo el anfitrión arranca.
	_check(not room.start_match(103, {}), "un jugador que no es anfitrión no debería arrancar")
	_check(_last_error_for(103) == "solo_el_anfitrion", "el motivo debería ser solo_el_anfitrion")
	_check(room.start_match(102, {"target_score": 100}), "el anfitrión debería poder arrancar")
	_check(room.phase == Room.Phase.PLAYING, "la sala debería estar jugando")

	# Con la partida en curso las sillas se congelan y no entra nadie más.
	_check(not room.set_seat(103, 3), "no debería poder cambiar de silla jugando")
	_check(_last_error_for(103) == "partida_en_curso", "el motivo debería ser partida_en_curso")
	_check(room.add_member(106, "Tarde") == -1, "no debería entrar nadie con la partida empezada")


func _test_name_sanitizing() -> void:
	# El registro de la mesa se dibuja con BBCode, así que un nombre con corchetes le
	# cambiaría colores y texto a TODOS los demás. El nombre ajeno es contenido que no
	# controlamos: este es el borde donde se limpia.
	_check(not Room.sanitize_name("[color=red]Ana[/color]").contains("["), "los corchetes deberían salir")
	_check(not Room.sanitize_name("Ana]x[").contains("]"), "los corchetes de cierre también")
	_check(Room.sanitize_name("Ana\nBeto") == "AnaBeto", "los saltos de línea deberían salir")
	_check(Room.sanitize_name("   ") == "Jugador", "un nombre vacío debería tener respaldo")
	_check(Room.sanitize_name("") == "Jugador", "una cadena vacía debería tener respaldo")
	_check(Room.sanitize_name("  Ana  ") == "Ana", "debería recortar los extremos")
	_check(Room.sanitize_name("A".repeat(50)).length() == Room.MAX_NAME_LENGTH, "debería recortar al largo máximo")


# ===========================================================================
# Lo que solo existe en red
# ===========================================================================
## A nadie le llegan las fichas de otro. Es la prueba que no se puede hacer jugando:
## en una sola pantalla la información nunca sale del proceso, y acá sí se reparte a
## cuatro destinatarios distintos. Se comprueba mirando SOLO lo que se mandó, igual
## que lo vería un cliente.
func _test_information_separation() -> void:
	var room := _new_room()
	var peers: Array = [201, 202, 203, 204]
	for i in range(peers.size()):
		room.add_member(int(peers[i]), "J%d" % i)
	room.start_match(201, {"target_score": 100})

	var owner_of: Dictionary = {}
	var total: int = 0
	for peer_id in peers:
		var mine: Dictionary = _mine_by_peer.get(peer_id, {})
		if mine.is_empty():
			_fail("el jugador %d no recibió su mano" % peer_id)
			continue
		var tiles: Array = mine.tiles
		_check(tiles.size() == GameState.TILES_PER_HAND, "el jugador %d recibió %d fichas" % [peer_id, tiles.size()])
		for t in tiles:
			var key: String = str(t)
			if owner_of.has(key):
				_fail("la ficha %s le llegó a %d y también a %d" % [key, owner_of[key], peer_id])
			owner_of[key] = peer_id
			total += 1

	# Cuatro manos de siete, las 28, sin una repetida: cada ficha le llegó a una sola
	# persona. Si el servidor mandara la mano de alguien a los cuatro, esto explota.
	_check(total == 28, "entre los cuatro llegaron %d fichas, no 28" % total)
	_check(owner_of.size() == 28, "hay fichas repetidas entre las manos")

	# Y lo que ve la mesa entera no puede traer fichas más allá del tablero.
	var board: Array = _last_pub.get("board", [])
	_check(board.is_empty(), "recién repartido el tablero debería estar vacío")
	_check(not _last_pub.has("hands"), "la vista pública no debería traer las manos")
	_check(not _last_pub.has("tiles"), "la vista pública no debería traer fichas de nadie")


## Un cliente modificado no puede jugar en nombre de otro, ni ensuciarle la mesa a los
## demás con sus errores.
func _test_turn_ownership() -> void:
	var room := _new_room()
	for i in range(4):
		room.add_member(300 + i, "J%d" % i)
	room.start_match(300, {"target_score": 100})

	var current: int = int(_last_pub.current_player)
	var intruder: int = 300 + ((current + 1) % GameState.SEAT_COUNT)

	# Intentar jugar fuera de turno: se rechaza y no cambia nada. El puesto sale de la
	# conexión, no del mensaje, así que no hay manera de decir "juego por el otro".
	var board_before: int = int(_last_pub.board.size())
	_sent = []
	_check(not room.handle_play(intruder, 0, "L"), "no debería poder jugar fuera de turno")
	_check(_last_error_for(intruder) == "no_es_su_turno", "el motivo debería ser no_es_su_turno")
	_check(int(_last_pub.board.size()) == board_before, "una jugada fuera de turno no debe tocar la mesa")

	# Y el resto de la mesa no se enteró: el error fue solo para quien se equivocó.
	for i in range(4):
		var peer_id: int = 300 + i
		if peer_id == intruder:
			continue
		_check(_messages_for(peer_id).is_empty(), "al jugador %d no debería llegarle el error de otro" % peer_id)

	# Ahora una jugada ilegal DE QUIEN SÍ le toca: la sesión la rechaza, y ese rechazo
	# también va solo para esa persona en vez de aparecer en la mesa de los cuatro.
	var actor: int = 300 + current
	var illegal: int = _find_illegal_index(actor)
	if illegal < 0:
		# En la primera mano sale el 6-6 forzado, así que casi siempre hay una ficha
		# no jugable. Si no la hubiera, no hay nada que comprobar acá.
		return
	_sent = []
	room.handle_play(actor, illegal, "L")
	var actor_msgs: Array = _messages_for(actor)
	_check(not actor_msgs.is_empty(), "el rechazo debería llegarle a quien jugó mal")
	for i in range(4):
		var peer_id: int = 300 + i
		if peer_id == actor:
			continue
		_check(_messages_for(peer_id).is_empty(), "el rechazo no debería llegarle al jugador %d" % peer_id)


# ===========================================================================
# Una mano completa, y las sillas vacías
# ===========================================================================
## Juega una mano de punta a punta actuando como cuatro clientes: cada uno solo usa lo
## que le llegó en su snapshot. Verifica que la mesa avance sola cuando toca un pase
## forzado y que el cierre llegue a los cuatro.
func _test_full_hand() -> void:
	var room := _new_room()
	var peers: Array = [401, 402, 403, 404]
	for i in range(peers.size()):
		room.add_member(int(peers[i]), "J%d" % i)
	room.start_match(401, {"target_score": 100})

	var guard: int = 0
	while _hand_ended_peers.is_empty():
		guard += 1
		if guard > 500:
			_fail("la mano no terminó en 500 pasos")
			return
		if not _try_client_play(room, peers):
			# Nadie puede jugar por su cuenta: le toca a la sala mover el pase forzado
			# cuando venza la pausa.
			room.tick(1.0)

	# El cierre es noticia de la mesa: le llega a los cuatro, no solo a quien cerró.
	for peer_id in peers:
		_check(_hand_ended_peers.has(peer_id), "el cierre de mano no le llegó a %d" % peer_id)

	# Con la mano cerrada, alcanza con que UNO pida seguir.
	_check(not room.handle_play(int(peers[0]), 0, "L"), "no debería aceptar jugadas con la mano cerrada")
	_hand_ended_peers = []
	_check(room.handle_continue(int(peers[1])), "cualquiera debería poder pedir seguir")
	_check(int(_last_pub.board.size()) <= 1, "tras seguir debería haber una mano nueva")


## Con dos jugadores, los otros dos puestos los juega la IA. Es lo que permite que dos
## amigos jueguen sin esperar un cuarto, y la misma maquinaria que hará falta para
## relevar a quien se desconecte.
func _test_ai_seats() -> void:
	var room := _new_room()
	room.add_member(501, "Ana")
	room.add_member(502, "Beto")
	room.start_match(501, {"target_score": 100})

	var plays: int = 0
	var guard: int = 0
	while _hand_ended_peers.is_empty():
		guard += 1
		if guard > 500:
			_fail("la mano con puestos de IA no terminó en 500 pasos")
			return
		if _try_client_play(room, [501, 502]):
			plays += 1
		else:
			room.tick(1.0)

	_check(plays > 0, "los dos humanos deberían haber jugado alguna ficha")
	_check(_hand_ended_peers.has(501) and _hand_ended_peers.has(502), "el cierre debería llegarle a los dos humanos")


## Si al de turno le toca y es humano con jugada, la sala NO agenda nada: espera su
## mensaje. Cualquier otro caso lo mueve ella.
func _try_client_play(room: Room, peers: Array) -> bool:
	var current: int = int(_last_pub.current_player)
	for peer_id in peers:
		if room.seat_of(int(peer_id)) != current:
			continue
		var mine: Dictionary = _mine_by_peer.get(peer_id, {})
		if mine.is_empty():
			return false
		var moves: Array = mine.legal_moves
		if moves.is_empty():
			return false
		var m: Dictionary = moves[0]
		return room.handle_play(int(peer_id), int(m.idx), str(m.ends[0]))
	return false


# ===========================================================================
# Registro de salas
# ===========================================================================
func _test_registry() -> void:
	var reg := _new_registry()

	var code: String = reg.create_room(601, "Ana")
	_check(RoomCode.is_valid(code), "el código creado debería ser válido: %s" % code)
	_check(reg.room_count() == 1, "debería haber una sala")

	# Entrar con el código tal como lo pega la gente: minúscula y con guiones.
	var pretty: String = code.to_lower().insert(2, "-")
	_check(reg.join_room(602, pretty, "Beto") == code, "debería entrar con el código escrito a mano: %s" % pretty)
	_check(reg.room_for(602) != null, "el segundo debería estar en la sala")
	_check(reg.room_for(602).code == code, "debería ser la misma sala")

	# Uno no puede estar en dos salas a la vez: si no, sus mensajes serían ambiguos.
	_check(reg.create_room(602, "Beto").is_empty(), "no debería poder crear otra sala estando en una")
	_check(_last_error_for(602) == "ya_estas_en_una_sala", "el motivo debería ser ya_estas_en_una_sala")
	_check(reg.join_room(602, code, "Beto").is_empty(), "no debería poder entrar dos veces")

	# Códigos que no sirven. Se distinguen los dos motivos porque son cosas distintas
	# para quien espera: una sala llena no se arregla, un código mal escrito sí.
	_check(reg.join_room(603, "XX", "Cami").is_empty(), "un código corto no debería entrar")
	_check(_last_error_for(603) == "codigo_invalido", "el motivo debería ser codigo_invalido")
	_check(reg.join_room(603, "ZZZZZ", "Cami").is_empty(), "una sala que no existe no debería entrar")
	_check(_last_error_for(603) == "sala_no_existe", "el motivo debería ser sala_no_existe")

	# La quinta persona no cabe.
	reg.join_room(603, code, "Cami")
	reg.join_room(604, code, "Dani")
	_check(reg.join_room(605, code, "Quinto").is_empty(), "el quinto no debería entrar")
	_check(_last_error_for(605) == "sala_llena", "el motivo debería ser sala_llena")

	# Con la partida empezada tampoco, y el motivo es otro.
	reg.room_for(601).start_match(601, {"target_score": 100})
	_check(reg.join_room(606, code, "Tarde").is_empty(), "no debería entrar con la partida empezada")
	_check(_last_error_for(606) == "partida_en_curso", "el motivo debería ser partida_en_curso")

	# Tope de salas: sin él, mandar create_room en bucle llena la memoria del servidor.
	var full := _new_registry()
	for i in range(RoomRegistry.MAX_ROOMS):
		full.create_room(7000 + i, "J%d" % i)
	_check(full.room_count() == RoomRegistry.MAX_ROOMS, "debería haber llegado al tope")
	_check(full.create_room(9999, "Uno más").is_empty(), "pasado el tope no debería crear más salas")
	_check(_last_error_for(9999) == "servidor_lleno", "el motivo debería ser servidor_lleno")


func _test_expiry() -> void:
	var reg := _new_registry()
	var code: String = reg.create_room(701, "Ana")

	# Con gente adentro la sala aguanta mucho: "sin actividad" muchas veces es que
	# están conversando antes de empezar.
	reg.tick(Room.EMPTY_ROOM_TTL + 1.0)
	_check(reg.room_count() == 1, "una sala con gente no debería vencer tan pronto")

	# Vacía, se recoge. Pero no en el acto: se le da un rato para que quien se cayó y
	# vuelve enseguida encuentre su mesa donde estaba.
	reg.leave(701)
	_check(reg.room_by_code(code) != null, "la sala no debería desaparecer al quedar vacía")
	reg.tick(Room.EMPTY_ROOM_TTL - 1.0)
	_check(reg.room_count() == 1, "todavía no debería haber vencido")
	reg.tick(2.0)
	_check(reg.room_count() == 0, "la sala vacía debería haberse recogido")

	# Y quien apuntaba a esa sala queda libre para crear otra.
	_check(not reg.create_room(701, "Ana").is_empty(), "debería poder crear una sala nueva")

	# Una sala con gente pero abandonada del todo también vence, con mucha más
	# paciencia: si no, una partida colgada vive para siempre.
	var idle := _new_registry()
	idle.create_room(801, "Ana")
	idle.tick(Room.IDLE_ROOM_TTL + 1.0)
	_check(idle.room_count() == 0, "una sala abandonada debería vencer al final")


# ===========================================================================
# Andamios
# ===========================================================================
## Recoge lo que la sala quiso mandar y mantiene, por cada jugador, lo último que vio.
## Es exactamente lo que tendría un cliente: acá no se mira nada por dentro.
func _collect(peer_id: int, msg: Dictionary) -> void:
	_sent.append({"peer": peer_id, "msg": msg})
	var kind: String = str(msg.get("type", ""))
	if kind == Protocol.S_SNAPSHOT:
		_last_pub = Protocol.decode_public_view(msg.pub)
		_mine_by_peer[peer_id] = Protocol.decode_private_view(msg.mine)
	elif kind == Protocol.S_HAND_ENDED:
		_hand_ended_peers.append(peer_id)
	elif kind == Protocol.S_MATCH_ENDED:
		_match_ended_peers.append(peer_id)


func _new_room() -> Room:
	_reset_capture()
	var room := Room.new(TEST_CODE)
	room.outbound.connect(_collect)
	return room


func _new_registry() -> RoomRegistry:
	_reset_capture()
	var reg := RoomRegistry.new()
	reg.outbound.connect(_collect)
	return reg


func _reset_capture() -> void:
	_sent = []
	_last_pub = {}
	_mine_by_peer = {}
	_hand_ended_peers = []
	_match_ended_peers = []


func _last_error_for(peer_id: int) -> String:
	for i in range(_sent.size() - 1, -1, -1):
		var entry: Dictionary = _sent[i]
		if int(entry.peer) != peer_id:
			continue
		var msg: Dictionary = entry.msg
		if str(msg.get("type", "")) == Protocol.S_ERROR:
			return str(msg.get("reason", ""))
	return ""


func _messages_for(peer_id: int) -> Array:
	var out: Array = []
	for entry in _sent:
		if int(entry.peer) == peer_id:
			out.append(entry.msg)
	return out


## Un índice de la mano que NO está entre las jugadas legales, para poder mandar algo
## inválido como lo haría un cliente modificado. -1 si todas son jugables.
func _find_illegal_index(peer_id: int) -> int:
	var mine: Dictionary = _mine_by_peer.get(peer_id, {})
	if mine.is_empty():
		return -1
	var legal: Dictionary = {}
	for m in mine.legal_moves:
		legal[int(m.idx)] = true
	var tiles: Array = mine.tiles
	for i in range(tiles.size()):
		if not legal.has(i):
			return i
	return -1


## Recorre todo lo codificado buscando dos cosas que no deben viajar. Se hace así, y
## no mirando las claves conocidas, para que si mañana alguien le agrega un campo a una
## vista, la prueba lo cace antes de que rompa algo en producción.
##
## Objetos: JSON no los puede mandar, así que el mensaje saldría ilegible.
##
## Flotantes: al volver, el decodificador convierte TODO número a entero, porque JSON
## manda los enteros como flotantes y la pantalla los usa de índice. Hoy en estas
## vistas no hay ni un número fraccionario, y esa conversión es exacta. El día que se
## agregue uno, lo destruiría en silencio — así que se frena acá.
func _check_json_safe(value: Variant, what: String) -> void:
	checks += 1
	var kind: int = typeof(value)
	if kind == TYPE_OBJECT:
		_fail("%s trae un objeto (%s) y JSON no lo puede mandar" % [what, str(value)])
		return
	if kind == TYPE_FLOAT:
		_fail("%s trae un flotante (%s): Protocol.to_ints() lo redondearía al volver, así que necesita una excepción ahí" % [what, str(value)])
		return
	if kind == TYPE_DICTIONARY:
		var dict: Dictionary = value
		for key in dict.keys():
			_check_json_safe(dict[key], "%s/%s" % [what, str(key)])
		return
	if kind == TYPE_ARRAY:
		var list: Array = value
		for i in range(list.size()):
			_check_json_safe(list[i], "%s[%d]" % [what, i])


## Pasa el mensaje por JSON de verdad, que es lo que va a ocurrir en el cable: si algo
## no se puede serializar, se nota acá y no cuando ya hay gente jugando.
func _through_json(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("el mensaje no sobrevivió el paso por JSON")
		return {}
	return parsed


func _through_json_array(value: Array) -> Array:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	if typeof(parsed) != TYPE_ARRAY:
		_fail("la lista no sobrevivió el paso por JSON")
		return []
	return parsed


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures.append("[servidor] %s" % what)


func _fail(what: String) -> void:
	checks += 1
	failures.append("[servidor] %s" % what)
