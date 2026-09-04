class_name GameSession
extends RefCounted

## Autoridad sobre una partida: la secuencia de una mano, de principio a fin.
##
## Es la capa que va entre las reglas y quien reparte la información. GameState
## responde preguntas y aplica jugadas; esta clase decide QUÉ pasa y EN QUÉ ORDEN se
## anuncia. No decide a quién se le manda ni con qué ritmo.
##
## Existe una sola porque hay dos autoridades que la necesitan y tienen que
## comportarse igual: LocalTransport (un humano y tres IA en este proceso) y el
## servidor de salas (cuatro jugadores por WebSocket). Si cada una llevara su propio
## ciclo de turnos habría dos secuencias que mantener sincronizadas, que es el mismo
## problema que evitamos al no reimplementar las reglas del otro lado.
##
## No tiene nodos ni temporizadores a propósito. El ritmo es de quien la usa: la
## pantalla quiere una pausa para que se vea quién jugó, y el servidor va a querer un
## reloj de turno. Eso también la hace probable sin abrir ventana y a toda velocidad.
##
## EL ORDEN DE LOS ANUNCIOS ES PARTE DEL CONTRATO:
##
##   reparto              state_changed -> hand_started -> turn_ready
##   jugada o pase        events -> state_changed -> (hand_ended | turn_ready)
##   acción rechazada     events, y nada más: no cambió nada
##   seguir tras la mano  match_ended, o la secuencia de reparto
##
## "events" va antes de "state_changed" para que el registro cuente lo que pasó
## mientras la pantalla todavía muestra el estado anterior, y "hand_ended" va al final
## para que el resumen se dibuje sobre la mesa ya actualizada.

# ---------------------------------------------------------------------------
# Anuncios
# ---------------------------------------------------------------------------
## Lo que acaba de pasar, en orden: jugadas, pases, bonificaciones, cierres.
signal events(list: Array)

## Hay estado nuevo que difundir. Quien escucha arma las vistas que le tocan (una
## sola en la pantalla, cuatro distintas en el servidor).
signal state_changed()

## Se repartió y hay mano nueva.
signal hand_started()

## Cerró la mano. "closing" es el evento de cierre (dominó o tranque) y "reveal" el
## destape de las cuatro manos para el conteo. El destape sale ÚNICAMENTE acá: antes
## de que la mano cierre sería filtrar las fichas de los demás.
signal hand_ended(closing: Dictionary, reveal: Dictionary)

## Una pareja llegó a la meta.
signal match_ended(winner_team: int)

## Le toca a "seat", y "must_pass" dice si ese puesto se quedó sin ficha jugable.
## Es la costura del ritmo: no sale hacia los jugadores, la atiende quien maneja el
## reloj para decidir si espera un clic, mueve una IA o aplica el pase.
signal turn_ready(seat: int, must_pass: bool)

## Sube con cada reparto. Quien maneje el ritmo lo usa para descartar una espera
## vieja: al volver de un await la mano pudo haber cerrado, y hasta haber empezado
## otra. Aplicar ahí lo que quedó pendiente movería una mano que no es la que se
## estaba jugando.
var hand_id: int = 0

var _state := GameState.new()

## Pareja que ganó la última mano, para desempatar si las dos llegan a la meta.
var _last_winner_team: int = -1


# ===========================================================================
# Órdenes de la autoridad
# ===========================================================================
## Configura y reparte la primera mano. Las claves que no vengan se quedan con lo que
## ya tiene GameState, que es el respaldo para quien no manda configuración.
func start_match(config: Dictionary) -> void:
	_state.target_score = int(config.get("target_score", _state.target_score))
	_state.bonus_pase_seguido = int(config.get("bonus_pase_seguido", _state.bonus_pase_seguido))
	_state.bonus_capicua = int(config.get("bonus_capicua", _state.bonus_capicua))
	_state.bonus_pase_salida = int(config.get("bonus_pase_salida", _state.bonus_pase_salida))
	_state.reset_match()
	_last_winner_team = -1
	deal_next_hand()


func deal_next_hand() -> void:
	hand_id += 1
	# El reparto es determinista a partir de una semilla, y ese azar es de la
	# autoridad: el cliente nunca la elige ni la conoce.
	_state.deal(randi())
	state_changed.emit()
	hand_started.emit()
	_announce_turn()


## Seguir después del conteo: reparte otra mano o cierra la partida.
func continue_after_hand() -> void:
	# winning_team() revisa las DOS parejas, no solo la que ganó la mano: las
	# bonificaciones se acreditan durante la mano y pueden llevar a la meta a
	# cualquiera de las dos. Devuelve -1 si nadie llegó.
	var champion: int = _state.winning_team(_last_winner_team)
	if champion >= 0:
		match_ended.emit(champion)
		return
	deal_next_hand()


## Coloca una ficha. El puesto lo pone quien llama, que es la autoridad; nunca sale
## de un mensaje del cliente. Una jugada ilegal se rechaza con un evento y el estado
## no se toca.
func play(seat: int, idx: int, end: String) -> void:
	_apply(_state.apply_play(seat, idx, end))


## Pasa el turno. No es una acción del jugador: solo se pasa cuando no hay ficha que
## calce, y eso lo dice needs_forced_pass().
func force_pass(seat: int) -> void:
	_apply(_state.apply_pass(seat))


# ===========================================================================
# Consultas
# ===========================================================================
func current_seat() -> int:
	return _state.current_player


func hand_over() -> bool:
	return _state.hand_over


## Si el de turno se quedó sin jugada. Es una consulta con AUTORIDAD, no una vista:
## un cliente no puede saber si otro tiene ficha, ni debería.
func needs_forced_pass() -> bool:
	return not _state.has_legal_move(_state.current_player)


func public_view() -> Dictionary:
	return _state.public_view()


func private_view(seat: int) -> Dictionary:
	return _state.private_view(seat)


# ===========================================================================
# Interno
# ===========================================================================
func _apply(list: Array) -> void:
	var closing: Dictionary = {}
	for e in list:
		var kind: String = str(e.get("type", ""))
		if kind == "hand_won" or kind == "tranque":
			closing = e

	# Un rechazo no cambió nada: no hay estado nuevo que difundir ni turno que volver
	# a anunciar. Se le contesta a quien mandó la acción y ahí termina. Además de ser
	# lo correcto, evita que alguien mandando jugadas inválidas en bucle haga que el
	# servidor le difunda un estado a los cuatro jugadores por cada intento.
	if _only_rejections(list):
		events.emit(list)
		return

	events.emit(list)
	state_changed.emit()

	if closing.is_empty():
		_announce_turn()
		return

	_last_winner_team = int(closing.get("winner_team", -1))
	hand_ended.emit(closing, _state.reveal_view())


func _announce_turn() -> void:
	if _state.hand_over:
		return
	turn_ready.emit(_state.current_player, needs_forced_pass())


func _only_rejections(list: Array) -> bool:
	if list.is_empty():
		return false
	for e in list:
		if str(e.get("type", "")) != "rejected":
			return false
	return true
