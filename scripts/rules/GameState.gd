class_name GameState
extends RefCounted

## Estado y reglas del dominó dominicano, sin nada de interfaz.
##
## Esta clase no conoce nodos, no dibuja, no escribe en el registro y no usa
## "await". Solo guarda el estado de la partida y responde preguntas sobre él. Eso
## es lo que permite correrla igual en el cliente y en el servidor dedicado: la
## autoridad del juego vive acá, y la interfaz solo la consulta.
##
## Las transiciones (apply_play, apply_pass) devuelven una lista de EVENTOS que
## describen lo que pasó, en vez de escribir en pantalla. Cada evento es un
## Dictionary con la clave "type":
##
##   played                 seat, tile, was_opening
##   passed                 seat, left_end, right_end
##   bonus                  team, pts, kind, seat, other_seat
##   opening_pass_cancelled lead_seat, partner_seat
##   hand_won               winner_seat, winner_team, pts, totals, capicua
##   tranque                winner_seat, winner_team, closer, challenger,
##                          closer_pips, challenger_pips, tie, pts, totals
##   rejected               seat, reason
##
## Quien consume los eventos decide qué hacer con ellos: la interfaz los convierte
## en texto y avisos; el servidor los difundirá a los clientes.

const SEAT_COUNT := 4
const TILES_PER_HAND := 7
const MAX_PIP := 6

## Los puestos se alternan, así que los compañeros quedan enfrentados:
## asientos 0 y 2 forman una pareja, 1 y 3 la otra.
const TEAM_OF_SEAT := [0, 1, 0, 1]

# ---------------------------------------------------------------------------
# Configuración de la mesa (se fija antes de empezar la partida)
# ---------------------------------------------------------------------------
var target_score: int = 200
var bonus_pase_seguido: int = 30
var bonus_capicua: int = 30
var bonus_pase_salida: int = 30

# ---------------------------------------------------------------------------
# Estado de la partida (persiste entre manos)
# ---------------------------------------------------------------------------
var team_score: Array = [0, 0]
var is_first_hand_of_game: bool = true

# ---------------------------------------------------------------------------
# Estado de la mano en curso
# ---------------------------------------------------------------------------
var hands: Array = [[], [], [], []]
var board: Array = []
var left_end: int = -1
var right_end: int = -1

var current_player: int = 0
var lead_player: int = 0
var consecutive_passes: int = 0

## Quién puso la última ficha: en un tranque, sus fichas se comparan con las del
## jugador que le seguía en el turno para decidir quién gana la mano.
var last_player_to_play: int = -1

## Solo en la primera mano de la partida sale forzosamente el 6-6 (el burro).
var must_open_with_double_six: bool = false

## Índice dentro de "board" de la ficha inicial (el ancla fija de la hilera). Todo
## lo que se juega hacia la izquierda le suma 1 (porque se inserta antes).
var opening_tile_index: int = -1

## Etapa del "pase de salida": -1 inactivo, 0 esperando el turno del que sigue al
## que salió, 1 ese jugador pasó y falta ver si la pareja también.
var opening_pass_stage: int = -1

## ¿La última ficha jugada calzaba en las dos puntas? (para la capicúa)
var last_play_was_capicua: bool = false

## Bonificaciones ganadas en la mano. Se guarda el dato estructurado (qué tipo y
## quién lo provocó), no el texto: redactar el mensaje es cosa de la interfaz.
## {"team": int, "pts": int, "kind": String, "seat": int, "other_seat": int}
var hand_bonuses: Array = []

## La mano terminó (alguien se pegó o hubo tranque) y no acepta más jugadas. Es
## distinto de la "fase" de la interfaz: esto es un hecho de las reglas.
var hand_over: bool = false

## Semilla del reparto de la mano actual. Se guarda para poder reproducir una mano
## exacta cuando haya que depurar algo, y para que el servidor sea la única fuente
## del azar cuando se juegue en red.
var deal_seed: int = 0


# ===========================================================================
# Partida
# ===========================================================================
func reset_match() -> void:
	team_score = [0, 0]
	is_first_hand_of_game = true


func team_of(seat: int) -> int:
	return TEAM_OF_SEAT[seat]


# ===========================================================================
# Reparto
# ===========================================================================
func build_deck() -> Array:
	var deck: Array = []
	for i in range(MAX_PIP + 1):
		for j in range(i, MAX_PIP + 1):
			deck.append(Domino.new(i, j))
	return deck


## Reparte una mano nueva de forma determinista a partir de la semilla: la misma
## semilla siempre da el mismo reparto. Se usa un Fisher-Yates con RNG propio en
## vez de Array.shuffle(), porque shuffle() usa el generador global y no se puede
## fijar por semilla.
func deal(seed_value: int) -> void:
	deal_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var deck: Array = build_deck()
	for i in range(deck.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp

	hands = [[], [], [], []]
	for seat in range(SEAT_COUNT):
		for k in range(TILES_PER_HAND):
			hands[seat].append(deck.pop_back())

	board = []
	left_end = -1
	right_end = -1
	opening_tile_index = -1
	consecutive_passes = 0
	last_player_to_play = -1
	opening_pass_stage = -1
	last_play_was_capicua = false
	hand_bonuses = []
	hand_over = false

	if is_first_hand_of_game:
		var burro: int = find_seat_with_double_six()
		if burro >= 0:
			current_player = burro
			lead_player = burro
		must_open_with_double_six = true
		is_first_hand_of_game = false
	else:
		current_player = lead_player
		must_open_with_double_six = false


func find_seat_with_double_six() -> int:
	for seat in range(SEAT_COUNT):
		for t in hands[seat]:
			if t.a == MAX_PIP and t.b == MAX_PIP:
				return seat
	return -1


# ===========================================================================
# Consultas
# ===========================================================================
## Jugadas legales de un puesto: [{"idx": índice en la mano, "ends": ["L","R"]}].
## Con la mesa vacía se puede abrir con cualquier ficha, salvo en la primera mano
## de la partida, donde el que salió está obligado a poner el 6-6.
func legal_moves_for(seat: int) -> Array:
	var moves: Array = []
	var hand: Array = hands[seat]

	if board.is_empty():
		if must_open_with_double_six and seat == lead_player:
			for i in range(hand.size()):
				if hand[i].a == MAX_PIP and hand[i].b == MAX_PIP:
					moves.append({"idx": i, "ends": ["L", "R"]})
			return moves
		for i in range(hand.size()):
			moves.append({"idx": i, "ends": ["L", "R"]})
		return moves

	for i in range(hand.size()):
		var t: Domino = hand[i]
		var ends: Array = []
		if t.has_value(left_end):
			ends.append("L")
		if t.has_value(right_end):
			ends.append("R")
		if ends.size() > 0:
			moves.append({"idx": i, "ends": ends})
	return moves


func has_legal_move(seat: int) -> bool:
	return not legal_moves_for(seat).is_empty()


func seat_pips(seat: int) -> int:
	var total := 0
	for t in hands[seat]:
		total += t.pips()
	return total


func team_pip_totals() -> Array:
	var totals := [0, 0]
	for s in range(SEAT_COUNT):
		totals[TEAM_OF_SEAT[s]] += seat_pips(s)
	return totals


func is_game_over() -> bool:
	return team_score[0] >= target_score or team_score[1] >= target_score


## Pareja que gana la partida. Se revisan las DOS, no solo la que ganó la última
## mano: las bonificaciones se acreditan durante la mano y pueden llevar a la meta
## a cualquiera de las dos. Si las dos llegaron, gana la de más puntos; si empatan,
## la que indique "tiebreak_team" (normalmente la que ganó la mano).
func winning_team(tiebreak_team: int) -> int:
	var reached_0: bool = team_score[0] >= target_score
	var reached_1: bool = team_score[1] >= target_score
	if reached_0 and reached_1:
		if team_score[0] > team_score[1]:
			return 0
		if team_score[1] > team_score[0]:
			return 1
		return tiebreak_team
	if reached_0:
		return 0
	if reached_1:
		return 1
	return -1


# ===========================================================================
# Transiciones
# ===========================================================================
## Coloca una ficha de la mano de "seat" en la punta "end" ("L" o "R"). Valida
## contra las jugadas legales: una jugada inventada se rechaza en vez de aplicarse.
## Esa validación es la base de la autoridad del servidor.
func apply_play(seat: int, idx: int, end: String) -> Array:
	if hand_over:
		return [{"type": "rejected", "seat": seat, "reason": "mano_terminada"}]
	if seat != current_player:
		return [{"type": "rejected", "seat": seat, "reason": "no_es_su_turno"}]

	var chosen: Dictionary = {}
	for m in legal_moves_for(seat):
		if m.idx == idx:
			chosen = m
			break
	if chosen.is_empty():
		return [{"type": "rejected", "seat": seat, "reason": "ficha_no_jugable"}]

	var was_opening: bool = board.is_empty()
	# Con la mesa vacía la punta es indistinta; en cualquier otro caso la ficha
	# tiene que calzar de verdad en el lado pedido.
	if not was_opening and not chosen.ends.has(end):
		return [{"type": "rejected", "seat": seat, "reason": "punta_invalida"}]

	var events: Array = []
	var t: Domino = hands[seat][idx]

	# Capicúa: la ficha calzaba en las DOS puntas y tiene las caras distintas (los
	# dobles no cuentan). Se comprueba antes de colocarla, con las puntas de ahora.
	last_play_was_capicua = (not was_opening) and (not t.is_double()) \
		and t.has_value(left_end) and t.has_value(right_end)

	hands[seat].remove_at(idx)

	if was_opening:
		board.push_back(t)
		left_end = t.a
		right_end = t.b
		opening_tile_index = 0
	elif end == "L":
		var other_v := t.other(left_end)
		board.push_front(t)
		left_end = other_v
		opening_tile_index += 1
	else:
		var other_v := t.other(right_end)
		board.push_back(t)
		right_end = other_v

	must_open_with_double_six = false
	consecutive_passes = 0
	last_player_to_play = seat
	events.append({"type": "played", "seat": seat, "tile": t, "was_opening": was_opening})

	if was_opening:
		# Empieza la ventana del pase de salida: hay que ver qué hace el siguiente.
		opening_pass_stage = 0
	else:
		_resolve_opening_pass(seat, false, events)

	if hands[seat].is_empty():
		_finish_hand_by_domino(seat, events)
	else:
		_advance_turn()
		_check_pase_seguido(events)

	return events


## Pasa el turno. Solo es válido si de verdad no hay ninguna jugada posible: la
## regla "si puedes jugar, debes jugar" se hace cumplir acá, no en la interfaz.
func apply_pass(seat: int) -> Array:
	if hand_over:
		return [{"type": "rejected", "seat": seat, "reason": "mano_terminada"}]
	if seat != current_player:
		return [{"type": "rejected", "seat": seat, "reason": "no_es_su_turno"}]
	if has_legal_move(seat):
		return [{"type": "rejected", "seat": seat, "reason": "tiene_jugada"}]

	var events: Array = []
	consecutive_passes += 1
	events.append({"type": "passed", "seat": seat, "left_end": left_end, "right_end": right_end})

	_resolve_opening_pass(seat, true, events)

	if consecutive_passes >= SEAT_COUNT:
		_resolve_tranque(events)
	else:
		_advance_turn()
		_check_pase_seguido(events)

	return events


func _advance_turn() -> void:
	current_player = (current_player + 1) % SEAT_COUNT


# ---------------------------------------------------------------------------
# Bonificaciones
# ---------------------------------------------------------------------------
func _award_bonus(team: int, pts: int, kind: String, seat: int, other_seat: int, events: Array) -> void:
	if pts <= 0:
		return
	team_score[team] += pts
	var entry := {"team": team, "pts": pts, "kind": kind, "seat": seat, "other_seat": other_seat}
	hand_bonuses.append(entry)
	events.append({
		"type": "bonus",
		"team": team,
		"pts": pts,
		"kind": kind,
		"seat": seat,
		"other_seat": other_seat,
	})


## Pase de salida: si el jugador que sigue al que salió no puede jugar, la pareja
## del que salió gana la bonificación... salvo que su propio compañero tampoco
## pueda jugar en su primer turno, caso en el que se anula.
func _resolve_opening_pass(seat: int, passed: bool, events: Array) -> void:
	if opening_pass_stage < 0:
		return
	var next_seat: int = (lead_player + 1) % SEAT_COUNT
	var partner_seat: int = (lead_player + 2) % SEAT_COUNT

	if opening_pass_stage == 0 and seat == next_seat:
		opening_pass_stage = 1 if passed else -1
	elif opening_pass_stage == 1 and seat == partner_seat:
		opening_pass_stage = -1
		if passed:
			events.append({
				"type": "opening_pass_cancelled",
				"lead_seat": lead_player,
				"partner_seat": partner_seat,
			})
		else:
			_award_bonus(TEAM_OF_SEAT[lead_player], bonus_pase_salida,
				"pase_salida", lead_player, next_seat, events)


## Pase seguido: el jugador que acaba de jugar hizo pasar a los otros TRES y él sí
## puede seguir jugando. Es acumulativo: cada vez que lo logra vuelve a sumar.
## Se evalúa justo después de rotar el turno, cuando le vuelve a tocar a él.
func _check_pase_seguido(events: Array) -> void:
	if consecutive_passes != SEAT_COUNT - 1 or last_player_to_play < 0:
		return
	if current_player != last_player_to_play:
		return
	if not has_legal_move(current_player):
		return
	_award_bonus(TEAM_OF_SEAT[current_player], bonus_pase_seguido,
		"pase_seguido", current_player, -1, events)


# ---------------------------------------------------------------------------
# Cierre de mano
# ---------------------------------------------------------------------------
## Regla de la mesa: la pareja ganadora suma los puntos de TODAS las fichas que
## quedaron sobre la mesa, las de la propia pareja incluidas — no solo las del rival.
func _finish_hand_by_domino(winner_seat: int, events: Array) -> void:
	hand_over = true
	var winner_team: int = TEAM_OF_SEAT[winner_seat]
	var totals: Array = team_pip_totals()
	var pts: int = totals[0] + totals[1]
	team_score[winner_team] += pts

	var capicua: bool = last_play_was_capicua
	if capicua:
		_award_bonus(winner_team, bonus_capicua, "capicua", winner_seat, -1, events)

	lead_player = winner_seat
	events.append({
		"type": "hand_won",
		"winner_seat": winner_seat,
		"winner_team": winner_team,
		"pts": pts,
		"totals": totals,
		"capicua": capicua,
	})


## Regla de la mesa: el tranque se decide cara a cara entre quien puso la última
## ficha y el jugador que le seguía en el turno (siempre de la pareja contraria,
## porque los puestos se alternan). Gana la mano la pareja de quien tenga menos
## puntos, y los puntos que suma son los de TODAS las fichas de la mesa, incluidas
## las dos manos que se compararon.
func _resolve_tranque(events: Array) -> void:
	hand_over = true
	var totals: Array = team_pip_totals()
	var pts: int = totals[0] + totals[1]

	var closer: int = last_player_to_play if last_player_to_play >= 0 else lead_player
	var challenger: int = (closer + 1) % SEAT_COUNT
	var closer_pips: int = seat_pips(closer)
	var challenger_pips: int = seat_pips(challenger)

	var tie: bool = closer_pips == challenger_pips
	var winner_seat: int
	if closer_pips < challenger_pips:
		winner_seat = closer
	elif challenger_pips < closer_pips:
		winner_seat = challenger
	else:
		# Empate entre los dos: se resuelve a favor de la pareja que tiene la mano.
		winner_seat = closer if TEAM_OF_SEAT[closer] == TEAM_OF_SEAT[lead_player] else challenger

	var winner_team: int = TEAM_OF_SEAT[winner_seat]
	team_score[winner_team] += pts

	# Dentro de la pareja ganadora, sale en la próxima mano quien se quedó con
	# menos puntos en la mano.
	var best_seat := -1
	var best_pips := 9999
	for s in range(SEAT_COUNT):
		if TEAM_OF_SEAT[s] == winner_team:
			var sp: int = seat_pips(s)
			if sp < best_pips:
				best_pips = sp
				best_seat = s
	lead_player = best_seat

	events.append({
		"type": "tranque",
		"winner_seat": winner_seat,
		"winner_team": winner_team,
		"closer": closer,
		"challenger": challenger,
		"closer_pips": closer_pips,
		"challenger_pips": challenger_pips,
		"tie": tie,
		"pts": pts,
		"totals": totals,
	})
