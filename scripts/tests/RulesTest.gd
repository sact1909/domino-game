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

var _failures: Array = []
var _hands_played := 0
var _actions := 0
var _tranques := 0
var _capicuas := 0


func _ready() -> void:
	print("[test] arrancando con semilla %d" % HARNESS_SEED)
	_test_rejections()
	_test_capicua_cases()
	_test_random_matches()
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
