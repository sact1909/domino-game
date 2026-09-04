extends Node

## Arnés de pruebas de las reglas, sin interfaz.
##
## Juega miles de manos completas eligiendo jugadas legales al azar y, después de
## CADA acción, verifica invariantes: cosas que tienen que ser verdad siempre, no
## importa cómo venga el reparto. Si alguna se rompe, informa la mano y la semilla
## para poder reproducirla exacta.
##
## Correr:
##   godot --headless -- --test
##
## Sale con código 0 si todo pasa y 1 si algo falla, así sirve tal cual en CI.
##
## Esto es posible porque GameState es puro: no toca nodos y no usa "await". Sin esa
## separación habría que jugar a mano para probar cada regla.

const MATCHES := 300
const HARNESS_SEED := 20260904
## Tope de acciones por mano. Una mano real no pasa de 28 jugadas más los pases;
## si se supera con holgura, es que la mano no termina y hay que avisar.
const MAX_ACTIONS_PER_HAND := 400

## Partidas que se juegan a través de GameSession para verificar el ORDEN de los
## anuncios. Van a meta 100 y sin pausas, así que son baratas.
const SESSION_MATCHES := 60
const MAX_SESSION_STEPS := 4000

var _failures: Array = []
var _hands_played := 0
var _actions := 0
var _tranques := 0
var _capicuas := 0

# Estado del recorrido de GameSession: la secuencia de anuncios de la acción en
# curso, el turno que la sesión dejó anunciado y los contadores del informe.
var _session: GameSession
var _session_ctx: String = ""
var _seq: Array = []
var _pending_turn: Dictionary = {}
var _session_champion: int = -1
var _last_session_hand_id: int = 0
var _session_hands: int = 0
var _session_actions: int = 0

# Resultado de las pruebas del servidor, que corren en su propio archivo porque no
# comparten nada con estas: ni reglas ni estado, solo el informe final.
var _server_checks: int = 0


func _ready() -> void:
	print("[test] arrancando con semilla %d" % HARNESS_SEED)
	_test_rejections()
	_test_capicua_cases()
	_test_random_matches()
	_test_session_sequence()
	_test_server()
	_report()


# ===========================================================================
# Capicúa: casos concretos
# ===========================================================================
## Las partidas al azar comprueban la regla contra una segunda formulación, pero
## eso no dice qué pasa en los casos que importan. Acá se arma la situación a mano
## y se verifica caso por caso.
func _test_capicua_cases() -> void:
	_check_capicua_case(Domino.new(5, 6), 5, 6, true, "6-5 con puntas 5 y 6")
	_check_capicua_case(Domino.new(5, 6), 6, 5, true, "6-5 con puntas 6 y 5")
	_check_capicua_case(Domino.new(5, 6), 6, 6, false, "6-5 con las dos puntas en 6")
	_check_capicua_case(Domino.new(5, 6), 5, 5, false, "6-5 con las dos puntas en 5")
	_check_capicua_case(Domino.new(6, 6), 6, 6, false, "doble 6 con las dos puntas en 6")
	_check_capicua_case(Domino.new(0, 0), 0, 0, false, "blanca doble con las dos puntas en blanco")
	_check_capicua_case(Domino.new(3, 3), 3, 3, false, "doble 3 con las dos puntas en 3")
	_check_capicua_case(Domino.new(3, 5), 5, 6, false, "3-5 que solo cierra la punta del 5")


func _check_capicua_case(tile: Domino, left: int, right: int, expected: bool, what: String) -> void:
	var gs := GameState.new()
	gs.deal(1)

	# Se arma la situación a mano: un jugador con una sola ficha (la que va a
	# cerrar) y las puntas que interesan. La ficha de relleno de la mesa solo está
	# para que no esté vacía.
	var seat := 0
	gs.hands = [[], [], [], []]
	gs.hands[seat] = [tile]
	gs.board = [Domino.new(min(left, right), max(left, right))]
	gs.left_end = left
	gs.right_end = right
	gs.opening_tile_index = 0
	gs.current_player = seat
	gs.lead_player = seat
	gs.must_open_with_double_six = false
	gs.consecutive_passes = 0
	gs.last_player_to_play = -1
	gs.opening_pass_stage = -1
	gs.hand_bonuses = []
	gs.hand_over = false

	var moves: Array = gs.legal_moves_for(seat)
	if moves.is_empty():
		_fail("capicúa '%s': la ficha no es jugable, el caso está mal armado" % what)
		return

	var got := false
	for e in gs.apply_play(seat, 0, moves[0].ends[0]):
		if str(e.get("type", "")) == "hand_won":
			got = e.capicua

	if got != expected:
		_fail("capicúa '%s': dio %s, se esperaba %s" % [what, got, expected])


# ===========================================================================
# Pruebas negativas: lo que NO se debe poder hacer
# ===========================================================================
func _test_rejections() -> void:
	var gs := GameState.new()
	gs.deal(1)

	var seat: int = gs.current_player
	var other: int = (seat + 1) % GameState.SEAT_COUNT
	var before: int = gs.hands[seat].size()

	# Jugar en el turno de otro.
	_expect_rejected(gs.apply_play(other, 0, "L"), "no_es_su_turno", "jugar fuera de turno")

	# Pasar teniendo jugada: la regla "si puedes jugar, debes jugar" se hace cumplir
	# en las reglas, no en la interfaz.
	_expect_rejected(gs.apply_pass(seat), "tiene_jugada", "pasar teniendo jugada")

	# En la primera mano el que sale está obligado al 6-6, así que cualquier otra
	# ficha de su mano tiene que rechazarse.
	var illegal_idx := -1
	for i in range(gs.hands[seat].size()):
		var t: Domino = gs.hands[seat][i]
		if not (t.a == GameState.MAX_PIP and t.b == GameState.MAX_PIP):
			illegal_idx = i
			break
	if illegal_idx >= 0:
		_expect_rejected(gs.apply_play(seat, illegal_idx, "L"), "ficha_no_jugable",
			"abrir la primera mano con algo que no es el 6-6")

	# Un rechazo no debe tocar el estado.
	if gs.hands[seat].size() != before:
		_fail("un rechazo alteró la mano: quedó en %d, debía quedar en %d" % [gs.hands[seat].size(), before])
	if not gs.board.is_empty():
		_fail("un rechazo colocó una ficha en la mesa")

	# Ya con la mesa abierta, pedir una punta donde la ficha no calza.
	gs.apply_play(seat, _index_of_double_six(gs, seat), "L")
	var next_seat: int = gs.current_player
	for m in gs.legal_moves_for(next_seat):
		if m.ends.size() == 1:
			var wrong_end: String = "R" if m.ends[0] == "L" else "L"
			_expect_rejected(gs.apply_play(next_seat, m.idx, wrong_end), "punta_invalida",
				"jugar en una punta donde la ficha no calza")
			break


func _index_of_double_six(gs: GameState, seat: int) -> int:
	for i in range(gs.hands[seat].size()):
		var t: Domino = gs.hands[seat][i]
		if t.a == GameState.MAX_PIP and t.b == GameState.MAX_PIP:
			return i
	return -1


func _expect_rejected(events: Array, reason: String, what: String) -> void:
	if events.size() != 1:
		_fail("%s: se esperaba un solo evento de rechazo, llegaron %d" % [what, events.size()])
		return
	var e: Dictionary = events[0]
	if str(e.get("type", "")) != "rejected":
		_fail("%s: se esperaba 'rejected', llegó '%s'" % [what, str(e.get("type", ""))])
		return
	if str(e.get("reason", "")) != reason:
		_fail("%s: se esperaba el motivo '%s', llegó '%s'" % [what, reason, str(e.get("reason", ""))])


# ===========================================================================
# Partidas al azar
# ===========================================================================
func _test_random_matches() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = HARNESS_SEED

	for match_index in range(MATCHES):
		var gs := GameState.new()
		gs.target_score = 200
		gs.reset_match()

		var guard := 0
		while not gs.is_game_over():
			guard += 1
			if guard > 100:
				_fail("partida %d: no termina después de 100 manos" % match_index)
				break

			var deal_seed: int = rng.randi()
			gs.deal(deal_seed)
			var ctx: String = "partida %d, mano con semilla %d" % [match_index, deal_seed]

			_check_tiles(gs, ctx + " (recién repartida)")
			_play_one_hand(gs, ctx)


func _play_one_hand(gs: GameState, ctx: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = gs.deal_seed

	var first_play_checked := false
	var must_open_with_burro: bool = gs.must_open_with_double_six
	var scores_before: Array = [gs.team_score[0], gs.team_score[1]]
	var steps := 0

	while not gs.hand_over:
		steps += 1
		_actions += 1
		if steps > MAX_ACTIONS_PER_HAND:
			_fail("%s: la mano no terminó en %d acciones" % [ctx, MAX_ACTIONS_PER_HAND])
			return

		var seat: int = gs.current_player
		var moves: Array = gs.legal_moves_for(seat)
		var events: Array = []
		var expect_capicua := false

		if moves.is_empty():
			events = gs.apply_pass(seat)
		else:
			var m: Dictionary = moves[rng.randi_range(0, moves.size() - 1)]
			var end: String = m.ends[rng.randi_range(0, m.ends.size() - 1)]

			# La condición de capicúa se calcula ACÁ, con las puntas de antes de la
			# jugada, y escrita tal como se describió la regla: la ficha no es doble,
			# las dos puntas son distintas, y sus dos caras corresponden una a cada
			# punta. Después se compara contra lo que informó GameState, así las dos
			# formulaciones tienen que coincidir.
			var t: Domino = gs.hands[seat][m.idx]
			expect_capicua = gs.hands[seat].size() == 1 \
				and not gs.board.is_empty() \
				and not t.is_double() \
				and gs.left_end != gs.right_end \
				and ((t.a == gs.left_end and t.b == gs.right_end) or (t.a == gs.right_end and t.b == gs.left_end))

			events = gs.apply_play(seat, m.idx, end)

		# Una acción tomada de las jugadas legales nunca debería rechazarse.
		for e in events:
			if str(e.get("type", "")) == "rejected":
				_fail("%s: se rechazó una jugada legal (%s)" % [ctx, str(e.get("reason", ""))])
				return

		# La primera ficha de la primera mano de la partida tiene que ser el burro.
		if must_open_with_burro and not first_play_checked:
			first_play_checked = true
			for e in events:
				if str(e.get("type", "")) == "played":
					var t: Domino = e.tile
					if not (t.a == GameState.MAX_PIP and t.b == GameState.MAX_PIP):
						_fail("%s: la primera mano abrió con %s en vez del 6-6" % [ctx, str(t)])

		# El turno avanza exactamente un puesto, salvo que la mano haya terminado.
		if not gs.hand_over and gs.current_player != (seat + 1) % GameState.SEAT_COUNT:
			_fail("%s: el turno pasó de %d a %d" % [ctx, seat, gs.current_player])
			return

		for e in events:
			if str(e.get("type", "")) == "hand_won" and e.capicua != expect_capicua:
				_fail("%s: capicúa informada como %s, se esperaba %s" % [ctx, e.capicua, expect_capicua])

		_check_tiles(gs, ctx)
		_check_chain(gs, ctx)
		_check_events(gs, events, ctx)
		_check_views(gs, ctx)

	_hands_played += 1

	# Los marcadores solo suben.
	for team in range(2):
		if gs.team_score[team] < scores_before[team]:
			_fail("%s: el marcador del equipo %d bajó de %d a %d" % [ctx, team, scores_before[team], gs.team_score[team]])


# ===========================================================================
# Invariantes
# ===========================================================================
## Las 28 fichas están siempre contabilizadas entre las manos y la mesa, sin
## repetirse ni perderse.
func _check_tiles(gs: GameState, ctx: String) -> void:
	var seen := {}
	var total := 0

	for seat in range(GameState.SEAT_COUNT):
		for t in gs.hands[seat]:
			total += 1
			seen["%d-%d" % [t.a, t.b]] = true
	for t in gs.board:
		total += 1
		seen["%d-%d" % [t.a, t.b]] = true

	if total != 28:
		_fail("%s: hay %d fichas en juego, deberían ser 28" % [ctx, total])
	if seen.size() != total:
		_fail("%s: hay fichas repetidas (%d distintas de %d)" % [ctx, seen.size(), total])


## La mesa leída de izquierda a derecha es una cadena válida: cada ficha calza con
## la anterior, y las puntas guardadas coinciden con las caras libres de verdad.
## Este invariante es exactamente lo que el dibujado del tablero da por sentado.
func _check_chain(gs: GameState, ctx: String) -> void:
	if gs.board.is_empty():
		return

	var v: int = gs.left_end
	for i in range(gs.board.size()):
		var t: Domino = gs.board[i]
		if not t.has_value(v):
			_fail("%s: la ficha %s (posición %d) no calza con %d" % [ctx, str(t), i, v])
			return
		v = t.other(v)

	if v != gs.right_end:
		_fail("%s: la cadena queda abierta en %d pero right_end dice %d" % [ctx, v, gs.right_end])

	if gs.opening_tile_index < 0 or gs.opening_tile_index >= gs.board.size():
		_fail("%s: opening_tile_index=%d está fuera de la mesa (%d fichas)" % [ctx, gs.opening_tile_index, gs.board.size()])


## La vista pública no puede contener NINGUNA ficha que no esté en la mesa. Se
## recorre entera buscando fichas en vez de mirar solo las claves conocidas: así,
## si alguien agrega un campo nuevo que sin darse cuenta arrastra manos ajenas, la
## prueba lo caza. En red, ese descuido es que un cliente modificado te vea la mano.
func _check_views(gs: GameState, ctx: String) -> void:
	var pub: Dictionary = gs.public_view()

	var on_board := {}
	for t in gs.board:
		on_board["%d-%d" % [t.a, t.b]] = true

	var found: Array = []
	_collect_dominoes(pub, found)
	for t in found:
		if not on_board.has("%d-%d" % [t.a, t.b]):
			_fail("%s: la vista pública filtra la ficha %s, que no está en la mesa" % [ctx, str(t)])
			return

	# Las cantidades tienen que reflejar las manos reales, sin revelar cuáles son.
	for seat in range(GameState.SEAT_COUNT):
		if pub.hand_counts[seat] != gs.hands[seat].size():
			_fail("%s: la vista pública dice %d fichas para el puesto %d, tiene %d" % [ctx, pub.hand_counts[seat], seat, gs.hands[seat].size()])
			return

	# La vista privada trae exactamente las fichas de ese puesto, y nada más.
	for seat in range(GameState.SEAT_COUNT):
		var priv: Dictionary = gs.private_view(seat)
		if priv.tiles.size() != gs.hands[seat].size():
			_fail("%s: la vista privada del puesto %d trae %d fichas, tiene %d" % [ctx, seat, priv.tiles.size(), gs.hands[seat].size()])
			return
		for i in range(priv.tiles.size()):
			var mine: Domino = priv.tiles[i]
			var real: Domino = gs.hands[seat][i]
			if mine.a != real.a or mine.b != real.b:
				_fail("%s: la vista privada del puesto %d no coincide con su mano" % [ctx, seat])
				return

	# Modificar una vista no debe tocar el estado: se entregan copias, no referencias.
	var board_size: int = gs.board.size()
	pub.board.clear()
	if gs.board.size() != board_size:
		_fail("%s: vaciar la vista pública vació la mesa de verdad (se entregó una referencia)" % ctx)


func _collect_dominoes(value: Variant, out: Array) -> void:
	if value is Domino:
		out.append(value)
	elif value is Array:
		for item in value:
			_collect_dominoes(item, out)
	elif value is Dictionary:
		for key in value:
			_collect_dominoes(value[key], out)


func _check_events(gs: GameState, events: Array, ctx: String) -> void:
	for e in events:
		match str(e.get("type", "")):
			"hand_won":
				if e.pts != e.totals[0] + e.totals[1]:
					_fail("%s: los puntos de la mano (%d) no son la suma de la mesa (%d + %d)" % [ctx, e.pts, e.totals[0], e.totals[1]])
				if not gs.hands[e.winner_seat].is_empty():
					_fail("%s: %d ganó la mano pero le quedan fichas" % [ctx, e.winner_seat])
				if e.capicua:
					_capicuas += 1
			"tranque":
				_tranques += 1
				if e.pts != e.totals[0] + e.totals[1]:
					_fail("%s: los puntos del tranque (%d) no son la suma de la mesa (%d + %d)" % [ctx, e.pts, e.totals[0], e.totals[1]])
				# El que trancó y el siguiente son de parejas contrarias, siempre.
				if GameState.TEAM_OF_SEAT[e.closer] == GameState.TEAM_OF_SEAT[e.challenger]:
					_fail("%s: se comparó a %d con %d, que son de la misma pareja" % [ctx, e.closer, e.challenger])
				# Gana quien tenga menos puntos, salvo empate.
				if not e.tie:
					var winner_pips: int = e.closer_pips if e.winner_seat == e.closer else e.challenger_pips
					var loser_pips: int = e.challenger_pips if e.winner_seat == e.closer else e.closer_pips
					if winner_pips > loser_pips:
						_fail("%s: ganó el tranque quien tenía más puntos (%d contra %d)" % [ctx, winner_pips, loser_pips])
			"bonus":
				if e.pts <= 0:
					_fail("%s: bonificación de %d puntos" % [ctx, e.pts])


# ===========================================================================
# Informe
# ===========================================================================
func _fail(msg: String) -> void:
	_failures.append(msg)


func _report() -> void:
	print("[test] %d manos, %d acciones, %d tranques, %d capicúas" % [_hands_played, _actions, _tranques, _capicuas])
	print("[test] sesión: %d manos, %d acciones en %d partidas" % [_session_hands, _session_actions, SESSION_MATCHES])
	print("[test] servidor: %d comprobaciones" % _server_checks)

	if _failures.is_empty():
		print("[test] TODO BIEN")
		get_tree().quit(0)
		return

	printerr("[test] %d fallo(s):" % _failures.size())
	# Se muestran las primeras: si algo se rompe, suele romperse muchas veces y el
	# resto del listado no agrega información.
	var shown: int = min(_failures.size(), 20)
	for i in range(shown):
		printerr("  - %s" % _failures[i])
	if _failures.size() > shown:
		printerr("  ... y %d más" % (_failures.size() - shown))
	get_tree().quit(1)


# ===========================================================================
# GameSession: el orden de los anuncios
# ===========================================================================
## Todo lo de arriba llama a GameState directo, así que prueba las REGLAS pero no la
## secuencia en que se anuncia lo que pasa. Esa secuencia es contrato: la pantalla y
## el servidor dependen de ella, y romperla no rompe ninguna regla — se vería como un
## resumen dibujado sobre la mesa vieja, o un registro que cuenta el final antes de
## contar la última jugada.
##
## Se puede correr a toda velocidad porque GameSession no tiene temporizadores: acá
## los cuatro puestos los mueve la IA y no hay ninguna pausa.
func _test_session_sequence() -> void:
	# La sesión reparte con randi() —el azar es de la autoridad, no de quien llama—,
	# así que se fija el generador global para que una falla se pueda reproducir.
	seed(HARNESS_SEED + 7)
	for m in range(SESSION_MATCHES):
		_run_session_match("sesión %d" % m)


func _run_session_match(ctx: String) -> void:
	_session_ctx = ctx
	_session = GameSession.new()
	_pending_turn = {}
	_session_champion = -1
	_last_session_hand_id = 0
	_session.events.connect(_on_session_events)
	_session.state_changed.connect(_on_session_state_changed)
	_session.hand_started.connect(_on_session_hand_started)
	_session.hand_ended.connect(_on_session_hand_ended)
	_session.match_ended.connect(_on_session_match_ended)
	_session.turn_ready.connect(_on_session_turn_ready)

	# Meta baja: la secuencia no depende del puntaje y así cada partida es corta.
	_seq = []
	_session.start_match({"target_score": 100})
	if not _seq_is(["state", "hand_started", "turn_ready"]):
		_fail("%s: secuencia inesperada en el reparto inicial: %s" % [ctx, str(_seq)])
		return

	# Una acción inválida no cambió nada, así que solo debe anunciar el rechazo: ni
	# estado nuevo ni turno otra vez. Importa en red, donde lo contrario significaría
	# que alguien mandando jugadas inválidas en bucle hace que el servidor le difunda
	# el estado a los cuatro jugadores por cada intento.
	var intruder: int = (_session.current_seat() + 1) % GameState.SEAT_COUNT
	var turn_before: int = _session.current_seat()
	_seq = []
	_session.play(intruder, 0, "L")
	if not _seq_is(["events"]):
		_fail("%s: una jugada fuera de turno anunció %s" % [ctx, str(_seq)])
		return
	if _session.current_seat() != turn_before:
		_fail("%s: una jugada fuera de turno movió el turno" % ctx)
		return

	var guard: int = 0
	while _session_champion < 0:
		guard += 1
		if guard > MAX_SESSION_STEPS:
			_fail("%s: la partida no terminó en %d pasos" % [ctx, MAX_SESSION_STEPS])
			return

		if not _pending_turn.is_empty():
			if not _session_take_turn(ctx):
				return
			continue

		if _session.hand_over():
			_seq = []
			_session.continue_after_hand()
			if not _seq_is(["match_ended"]) and not _seq_is(["state", "hand_started", "turn_ready"]):
				_fail("%s: secuencia inesperada al seguir tras la mano: %s" % [ctx, str(_seq)])
				return
			continue

		# Ni turno pendiente ni mano cerrada: la sesión se quedó sin decir qué sigue,
		# y nadie la podría mover.
		_fail("%s: la sesión quedó sin turno pendiente y sin mano cerrada" % ctx)
		return


## Mueve el turno anunciado. Devuelve false si algo falló y hay que abandonar.
func _session_take_turn(ctx: String) -> bool:
	var turn: Dictionary = _pending_turn
	_pending_turn = {}
	var seat: int = int(turn.seat)
	_seq = []
	_session_actions += 1

	if bool(turn.must_pass):
		_session.force_pass(seat)
	else:
		var choice: Dictionary = DominoAI.choose(_session.private_view(seat))
		if choice.is_empty():
			_fail("%s: must_pass era falso pero la IA no encontró jugada" % ctx)
			return false
		_session.play(seat, int(choice.idx), str(choice.end))

	# Toda acción termina de una de dos maneras: la mesa sigue, o la mano cerró.
	if _seq_is(["events", "state", "turn_ready"]) or _seq_is(["events", "state", "hand_ended"]):
		return true
	_fail("%s: secuencia inesperada tras la acción: %s" % [ctx, str(_seq)])
	return false


func _seq_is(expected: Array) -> bool:
	if _seq.size() != expected.size():
		return false
	for i in range(expected.size()):
		if str(_seq[i]) != str(expected[i]):
			return false
	return true


func _on_session_events(_list: Array) -> void:
	_seq.append("events")


func _on_session_state_changed() -> void:
	_seq.append("state")


func _on_session_hand_started() -> void:
	_seq.append("hand_started")
	if _session.hand_id <= _last_session_hand_id:
		_fail("%s: hand_id no subió con el reparto (quedó en %d)" % [_session_ctx, _session.hand_id])
	_last_session_hand_id = _session.hand_id


func _on_session_hand_ended(closing: Dictionary, reveal: Dictionary) -> void:
	_seq.append("hand_ended")
	_session_hands += 1

	# El destape solo tiene sentido con la mano cerrada, y quien lo recibe tiene que
	# poder comprobarlo por su cuenta: para eso viaja "hand_over" dentro.
	if not bool(reveal.hand_over):
		_fail("%s: el destape llegó sin la mano marcada como cerrada" % _session_ctx)
	if not _session.hand_over():
		_fail("%s: hand_ended con la sesión sin mano cerrada" % _session_ctx)

	var hands: Array = reveal.hands
	if hands.size() != GameState.SEAT_COUNT:
		_fail("%s: el destape trae %d manos, no %d" % [_session_ctx, hands.size(), GameState.SEAT_COUNT])

	var kind: String = str(closing.get("type", ""))
	if kind != "hand_won" and kind != "tranque":
		_fail("%s: cierre de tipo inesperado (%s)" % [_session_ctx, kind])


func _on_session_match_ended(winner_team: int) -> void:
	_seq.append("match_ended")
	_session_champion = winner_team

	# La partida no puede cerrarse con el supuesto campeón por debajo de la meta.
	var pub: Dictionary = _session.public_view()
	var scores: Array = pub.team_score
	if int(scores[winner_team]) < int(pub.target_score):
		_fail("%s: match_ended con el equipo %d en %d puntos, sin llegar a la meta de %d" % [
			_session_ctx, winner_team, int(scores[winner_team]), int(pub.target_score),
		])


func _on_session_turn_ready(seat: int, must_pass: bool) -> void:
	_seq.append("turn_ready")
	_pending_turn = {"seat": seat, "must_pass": must_pass}

	if seat != _session.current_seat():
		_fail("%s: turn_ready anunció el puesto %d pero el de turno es %d" % [_session_ctx, seat, _session.current_seat()])
	if _session.hand_over():
		_fail("%s: turn_ready con la mano ya cerrada" % _session_ctx)

	# "must_pass" se comprueba contra la vista privada de ese puesto, que es otra
	# manera de llegar al mismo dato sin volver a preguntarle a la sesión.
	var moves: Array = _session.private_view(seat).legal_moves
	if must_pass != moves.is_empty():
		_fail("%s: must_pass=%s pero el puesto %d tiene %d jugadas posibles" % [
			_session_ctx, str(must_pass), seat, moves.size(),
		])


# ===========================================================================
# Servidor de salas
# ===========================================================================
## Las pruebas del servidor viven en ServerTest porque no comparten nada con estas:
## no tocan reglas ni estado, prueban salas, códigos y el formato de los mensajes. Se
## corren desde acá para que "godot --headless -- --test" siga siendo un solo comando.
func _test_server() -> void:
	var suite := ServerTest.new()
	suite.run()
	_server_checks = suite.checks
	for f in suite.failures:
		_failures.append(f)
