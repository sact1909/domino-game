class_name Transport
extends Node

## Contrato entre la pantalla y quien tiene la AUTORIDAD del juego.
##
## La interfaz no aplica reglas: manda intenciones ("quiero jugar esta ficha") y
## dibuja lo que le contesten. Quien decide puede ser este mismo proceso
## (LocalTransport: un humano contra tres IA) o un servidor al otro lado de un
## WebSocket. La pantalla no distingue una cosa de la otra.
##
## Cada señal de acá es un mensaje que BAJA del servidor y cada método público uno
## que SUBE del cliente. La lista es corta a propósito: es la superficie del
## protocolo, y todo lo que se agregue hay que validarlo del lado del servidor.

# ---------------------------------------------------------------------------
# Del servidor al cliente
# ---------------------------------------------------------------------------
## En qué puesto quedaste sentado. La pantalla no lo elige: lo acata. Hoy lo define
## un argumento de línea de comandos; en red lo dirá la sala.
signal seat_assigned(seat: int)

## Estado del juego después de cualquier cambio: "pub" es lo que ve la mesa entera
## y "mine" las fichas del puesto local. Es lo ÚNICO de lo que se dibuja.
signal snapshot(pub: Dictionary, mine: Dictionary)

## Lo que acaba de pasar, en orden, para el registro y los avisos flotantes. Los
## eventos llegan ya resueltos (quién jugó qué, quién pasó, qué bonificación cayó);
## la pantalla solo los redacta.
signal events(list: Array)

## Se repartió y hay mano nueva. Llega siempre DESPUÉS del snapshot del reparto,
## para que el mensaje de apertura pueda leer quién sale.
signal hand_started()

## Cerró la mano. "closing" es el evento de cierre (dominó o tranque) y "reveal" el
## destape de las cuatro manos para el conteo. El destape viaja SOLO acá: mandarlo
## antes sería filtrar las fichas de los demás.
signal hand_ended(closing: Dictionary, reveal: Dictionary)

## Una pareja llegó a la meta. Lo decide la autoridad, no la pantalla.
signal match_ended(winner_team: int)

# ---------------------------------------------------------------------------
# Del cliente al servidor
# ---------------------------------------------------------------------------
## Sentarse a la mesa. Contesta con seat_assigned y un primer snapshot.
func begin() -> void:
	push_error("Transport.begin() sin implementar")


## Arrancar la partida con lo elegido en la pantalla de inicio (meta y las tres
## bonificaciones). En red esto solo lo podrá mandar el anfitrión.
func start_match(_config: Dictionary) -> void:
	push_error("Transport.start_match() sin implementar")


## Jugar una ficha de la mano propia. Ojo: NO lleva puesto. El cliente no dice en
## nombre de quién juega — eso lo sabe la autoridad por la conexión. Es justo lo que
## impide que alguien mande jugadas por otro.
func request_play(_idx: int, _end: String) -> void:
	push_error("Transport.request_play() sin implementar")


## Seguir después de la pantalla de fin de mano: reparte otra o cierra la partida.
func request_continue() -> void:
	push_error("Transport.request_continue() sin implementar")


# No hay request_pass(), y no es un olvido: en el dominó dominicano no se pasa por
# voluntad, se pasa porque no hay ficha que calce. Eso lo determina la autoridad
# mirando la mano, así que el pase nunca es una acción del cliente — llega como
# evento, igual que todo lo demás.

# ---------------------------------------------------------------------------
# Emisores (para las subclases)
# ---------------------------------------------------------------------------
# Las señales se declaran acá pero las dispara quien implemente el contrato. Se
# pasa por estos emisores en vez de emitir directo para que el contrato completo
# —qué señal existe y con qué carga viaja— quede en un solo archivo.
func _emit_seat_assigned(seat: int) -> void:
	seat_assigned.emit(seat)


func _emit_snapshot(pub: Dictionary, mine: Dictionary) -> void:
	snapshot.emit(pub, mine)


func _emit_events(list: Array) -> void:
	events.emit(list)


func _emit_hand_started() -> void:
	hand_started.emit()


func _emit_hand_ended(closing: Dictionary, reveal: Dictionary) -> void:
	hand_ended.emit(closing, reveal)


func _emit_match_ended(winner_team: int) -> void:
	match_ended.emit(winner_team)


## Valores con los que arranca la pantalla de configuración y que después viajan en
## start_match(). Viven acá, en el protocolo, porque es la pantalla de inicio la que
## los propone; los de GameState son solo el respaldo para el código que nunca manda
## configuración (el arnés de pruebas).
static func default_config() -> Dictionary:
	return {
		"target_score": 200,
		"bonus_pase_seguido": 30,
		"bonus_capicua": 30,
		"bonus_pase_salida": 30,
	}
