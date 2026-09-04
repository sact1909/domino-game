class_name LocalTransport
extends Transport

## Autoridad corriendo en este mismo proceso: un jugador humano y tres IA.
##
## Es delgado a propósito. La secuencia de la mano vive en GameSession, que es la
## misma que va a usar el servidor de salas; acá queda solo lo que es propio de jugar
## en una sola pantalla: el RITMO de los turnos, mover a las tres IA y mandarle todo a
## un único puesto.
##
## Hay que agregarlo al árbol de escenas antes de usarlo: las pausas entre turnos usan
## el temporizador del árbol, y fuera de él get_tree() es null.
##
## El día que entre el transporte de red va a implementar este mismo contrato hablando
## por un socket, y la pantalla no se entera del cambio.

## Pausa entre turnos. Es solo ritmo visual: sin ella las tres IA jugarían de golpe y
## no se vería quién hizo qué. El servidor no va a tener esta pausa sino un reloj de
## turno: la misma costura con otra política.
const TURN_DELAY := 0.9

var _session := GameSession.new()

## Puesto del jugador humano; los otros tres los mueve la IA.
var _human_seat: int = 0


func _init(human_seat: int = 0) -> void:
	_human_seat = human_seat
	# Los anuncios de la sesión calzan uno a uno con las señales del contrato, salvo
	# turn_ready: esa es la costura del ritmo y no sale hacia la pantalla.
	_session.events.connect(_emit_events)
	_session.state_changed.connect(_push_snapshot)
	_session.hand_started.connect(_emit_hand_started)
	_session.hand_ended.connect(_emit_hand_ended)
	_session.match_ended.connect(_emit_match_ended)
	_session.turn_ready.connect(_on_turn_ready)


# ===========================================================================
# Mensajes que llegan de la pantalla
# ===========================================================================
func begin() -> void:
	_emit_seat_assigned(_human_seat)
	# Los otros tres puestos son de la máquina, así que van sin nombre. Se manda igual
	# para que la pantalla no tenga que suponer nada según el modo.
	_emit_seats_changed(["", "", "", ""])
	# Un primer snapshot de mesa vacía para que la pantalla tenga de dónde dibujar
	# antes del primer reparto. En red es lo que manda el servidor al sentarte.
	_push_snapshot()


func start_match(config: Dictionary) -> void:
	_session.start_match(config)


func request_play(idx: int, end: String) -> void:
	# El puesto no viene del mensaje: lo pone la autoridad, y acá es siempre el
	# humano. Si la jugada no es legal, la sesión la rechaza y el estado no se toca.
	_session.play(_human_seat, idx, end)


func request_continue() -> void:
	_session.continue_after_hand()


# ===========================================================================
# Ritmo de los turnos
# ===========================================================================
# Le toca a "seat". Si es el humano y tiene con qué jugar no se hace nada: se espera
# el clic. En cualquier otro caso —pase forzado o una IA— lo mueve esta autoridad,
# después de una pausa para que se vea.
#
# El pase se aplica solo, para todos por igual. Nadie puede quedarse esperando un clic
# que no llega, y así el tranque (cuatro pases seguidos) siempre se detecta.
func _on_turn_ready(seat: int, must_pass: bool) -> void:
	if seat == _human_seat and not must_pass:
		return
	_take_turn(seat, must_pass, _session.hand_id)


func _take_turn(seat: int, must_pass: bool, hand_id: int) -> void:
	await get_tree().create_timer(TURN_DELAY).timeout
	# Al volver de la espera el mundo pudo cambiar: la mano cerró, o cerró y ya empezó
	# otra. Aplicar acá lo que quedó pendiente movería una mano que no es la que se
	# estaba jugando.
	if hand_id != _session.hand_id or _session.hand_over():
		return

	if must_pass:
		_session.force_pass(seat)
		return

	var choice: Dictionary = DominoAI.choose(_session.private_view(seat))
	if choice.is_empty():
		_session.force_pass(seat)
		return
	_session.play(seat, int(choice.idx), str(choice.end))


func _push_snapshot() -> void:
	_emit_snapshot(_session.public_view(), _session.private_view(_human_seat))
