class_name LocalTransport
extends Transport

## Autoridad corriendo en este mismo proceso: un jugador humano y tres IA.
##
## Acá vive todo lo que en realidad es trabajo de servidor y que antes estaba
## mezclado con la pantalla: el estado con las reglas, el azar del reparto, el ritmo
## de los turnos, el pase forzado, la IA y la decisión de cuándo se acabó la
## partida. Main.gd ya no tiene nada de eso.
##
## Hay que agregarlo al árbol de escenas antes de usarlo: las pausas entre turnos
## usan el temporizador del árbol, y fuera de él get_tree() es null.
##
## El día que entre el transporte de red va a implementar este mismo contrato
## hablando por un socket, y la pantalla no se entera del cambio.

## Pausa entre turnos. Es solo ritmo visual: sin ella las tres IA jugarían de golpe
## y no se vería quién hizo qué.
const TURN_DELAY := 0.9

var _state := GameState.new()

## Puesto del jugador humano; los otros tres los mueve la IA.
var _human_seat: int = 0

## Cambia con cada reparto. Los turnos esperan con await, y al volver de esa espera
## el mundo pudo cambiar (cerró la mano, empezó otra). Comparar este número con el
## actual evita que una espera vieja aplique una jugada en la mano siguiente.
var _hand_id: int = 0

## Pareja que ganó la última mano, para desempatar si las dos llegan a la meta.
var _last_winner_team: int = -1


func _init(human_seat: int = 0) -> void:
	_human_seat = human_seat


# ===========================================================================
# Mensajes que llegan de la pantalla
# ===========================================================================
func begin() -> void:
	_emit_seat_assigned(_human_seat)
	# Un primer snapshot de mesa vacía para que la pantalla tenga de dónde dibujar
	# antes del primer reparto. En red es lo que manda el servidor al sentarte.
	_push_snapshot()


func start_match(config: Dictionary) -> void:
	var defaults: Dictionary = Transport.default_config()
	_state.target_score = int(config.get("target_score", defaults.target_score))
	_state.bonus_pase_seguido = int(config.get("bonus_pase_seguido", defaults.bonus_pase_seguido))
	_state.bonus_capicua = int(config.get("bonus_capicua", defaults.bonus_capicua))
	_state.bonus_pase_salida = int(config.get("bonus_pase_salida", defaults.bonus_pase_salida))
	_state.reset_match()
	_last_winner_team = -1
	_start_hand()


func request_play(idx: int, end: String) -> void:
	# El puesto lo pone la autoridad, no el mensaje: acá es siempre el humano.
	# Si la jugada no es legal, apply_play() devuelve un evento "rejected" y el
	# estado no se toca.
	_apply(_state.apply_play(_human_seat, idx, end))


func request_continue() -> void:
	# winning_team() revisa las DOS parejas (las bonificaciones se acreditan durante
	# la mano y pueden llevar a la meta a cualquiera) y devuelve -1 si nadie llegó.
	var champion: int = _state.winning_team(_last_winner_team)
	if champion >= 0:
		_emit_match_ended(champion)
	else:
		_start_hand()


# ===========================================================================
# Ciclo de la mano
# ===========================================================================
func _start_hand() -> void:
	_hand_id += 1
	# El reparto es determinista a partir de una semilla, y el azar de esa semilla
	# es de la autoridad: en red el servidor va a ser la única fuente.
	_state.deal(randi())
	_push_snapshot()
	_emit_hand_started()
	_pump()


# Mueve la mano hasta que le toque al humano. Tres casos: la mano cerró y no hay
# nada que hacer, el de turno no tiene ficha jugable (pase forzado), o le toca a una
# IA. Si le toca al humano no hace nada: se espera el clic.
func _pump() -> void:
	if _state.hand_over:
		return

	var seat: int = _state.current_player
	var hand_id: int = _hand_id

	# El pase se aplica solo, para todos por igual. Nadie puede quedarse esperando
	# un clic que no llega, y así el tranque (cuatro pases seguidos) siempre se
	# detecta. Esto consulta el estado con autoridad, no una vista: un cliente no
	# puede saber si otro tiene jugada, ni debería.
	if not _state.has_legal_move(seat):
		await _wait(TURN_DELAY)
		if _is_stale(hand_id):
			return
		_apply(_state.apply_pass(seat))
		return

	if seat == _human_seat:
		return

	await _wait(TURN_DELAY)
	if _is_stale(hand_id):
		return
	_ai_play(seat)


# Aplica lo que devolvió el motor y lo reparte a la pantalla: primero qué pasó,
# después el estado nuevo. Si la mano cerró, con el cierre va el destape; si no,
# se sigue moviendo la mesa.
func _apply(list: Array) -> void:
	var closing: Dictionary = {}
	for e in list:
		var kind: String = str(e.get("type", ""))
		if kind == "hand_won" or kind == "tranque":
			closing = e

	_emit_events(list)
	_push_snapshot()

	if not closing.is_empty():
		_last_winner_team = int(closing.get("winner_team", -1))
		_emit_hand_ended(closing, _state.reveal_view())
	else:
		_pump()


func _push_snapshot() -> void:
	_emit_snapshot(_state.public_view(), _state.private_view(_human_seat))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _is_stale(hand_id: int) -> bool:
	return hand_id != _hand_id or _state.hand_over


# ===========================================================================
# IA
# ===========================================================================
# La IA recibe la vista privada de su puesto, no el estado completo: así solo puede
# usar lo que un jugador de verdad vería. Cuando releve a alguien que se desconecte
# correrá en el servidor con esa misma limitación.
#
# Criterio: suelta primero los dobles y, entre fichas parecidas, la de más puntos —
# lo que haría cualquiera para no quedarse con peso muerto.
func _ai_play(seat: int) -> void:
	var view: Dictionary = _state.private_view(seat)
	var moves: Array = view.legal_moves
	if moves.is_empty():
		_apply(_state.apply_pass(seat))
		return

	var hand: Array = view.tiles
	var best: Dictionary = moves[0]
	for m in moves:
		var t: Domino = hand[m.idx]
		var bt: Domino = hand[best.idx]
		if t.is_double() and not bt.is_double():
			best = m
		elif t.is_double() == bt.is_double() and t.pips() > bt.pips():
			best = m

	var chosen_end: String = best.ends[0]
	if best.ends.size() > 1:
		chosen_end = best.ends[randi() % best.ends.size()]
	_apply(_state.apply_play(seat, best.idx, chosen_end))
