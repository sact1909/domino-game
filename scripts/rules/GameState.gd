class_name GameState
extends RefCounted

## Estado y reglas del dominó dominicano, sin nada de interfaz.
##
## Esta clase no conoce nodos, no dibuja, no escribe en el registro y no usa
## "await". Solo guarda el estado de la partida y responde preguntas sobre él. Eso
## es lo que permite correrla igual en el cliente y en el servidor dedicado: la
## autoridad del juego vive acá, y la interfaz solo la consulta.
##
## En esta etapa contiene el estado, las consultas y el reparto. Las transiciones
## (jugar, pasar, cerrar mano) todavía viven en Main.gd y se mudarán después.

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

## Bonificaciones ganadas en la mano: {"team": int, "pts": int, "reason": String}
var hand_bonuses: Array = []

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
