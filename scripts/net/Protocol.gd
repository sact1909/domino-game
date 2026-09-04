class_name Protocol
extends RefCounted

## Formato de los mensajes que van por el socket, y único lugar donde se traduce entre
## lo que usa el juego y lo que cabe en JSON.
##
## El problema concreto es corto: las vistas y los eventos llevan objetos Domino, y
## JSON no sabe qué hacer con una clase. Todo lo demás —números, textos, listas,
## mapas— pasa tal cual. Así que la traducción está acotada a los cuatro lugares
## donde de verdad hay fichas:
##
##   public_view().board      lista de fichas
##   private_view().tiles     lista de fichas
##   reveal_view().hands      cuatro listas de fichas
##   evento "played".tile     una ficha
##
## Las dos direcciones viven en el mismo archivo a propósito. Si quien manda y quien
## recibe se escriben por separado, tarde o temprano se desfasan, y eso no se ve como
## un error: se ve como un tablero raro en la pantalla de otra persona, que es de lo
## más difícil de rastrear.
##
## Una ficha viaja como [a, b], no como texto ni como mapa: es el formato más corto, y
## en una mano se mandan hasta 28.

## Sube cuando un cambio rompe la compatibilidad. El cliente y el servidor se lo
## comparan al conectar y cortan si no coinciden, en vez de fallar más adelante con un
## mensaje que el otro lado no entiende.
const VERSION := 1

# ---------------------------------------------------------------------------
# Nombres de los mensajes
# ---------------------------------------------------------------------------
# Del cliente al servidor.
const C_CREATE_ROOM := "create_room"
const C_JOIN_ROOM := "join_room"
## Intercambiar dos sillas. Es la única manera de reorganizar la mesa y solo la usa el
## anfitrión: con una sola persona repartiendo los equipos no hay nada que negociar ni
## carrera que perder.
const C_SWAP_SEATS := "swap_seats"
## Volver al lobby con la sala intacta, o cerrarla del todo (solo el anfitrión).
const C_PLAY_AGAIN := "play_again"
const C_CLOSE_ROOM := "close_room"
const C_START_MATCH := "start_match"
const C_PLAY := "play"
const C_CONTINUE := "continue"
const C_LEAVE_ROOM := "leave_room"
const C_PING := "ping"

# Del servidor al cliente. Los cinco de la mitad calzan uno a uno con las señales del
# contrato de Transport: por eso el transporte de red no va a tener que interpretar
# nada, solo desempacar.
const S_HELLO := "hello"
const S_ROOM_JOINED := "room_joined"
const S_SEAT_ASSIGNED := "seat_assigned"
const S_LOBBY := "lobby"
const S_SNAPSHOT := "snapshot"
const S_EVENTS := "events"
const S_HAND_STARTED := "hand_started"
const S_HAND_ENDED := "hand_ended"
const S_MATCH_ENDED := "match_ended"
const S_ROOM_CLOSED := "room_closed"
const S_ERROR := "error"
const S_PONG := "pong"

# Estado de una sala, tal como viaja en el mensaje de lobby. Vive acá porque es
# vocabulario del PROTOCOLO: el cliente lo necesita para saber cuándo pasar a la mesa, y
# no debería tener que conocer una clase del servidor para eso. El arnés comprueba que
# estos valores sigan coincidiendo con los de Room.
const ROOM_LOBBY := 0
const ROOM_PLAYING := 1
const ROOM_FINISHED := 2


# ---------------------------------------------------------------------------
# Fichas
# ---------------------------------------------------------------------------
static func encode_tile(t: Domino) -> Array:
	return [t.a, t.b]


## Devuelve null si el par no es una ficha válida. Quien llame tiene que tratar ese
## null como falla de protocolo y no seguir: una ficha inventada en el tablero se
## vería como una mesa imposible, sin ningún error a la vista.
static func decode_tile(raw: Variant) -> Domino:
	if typeof(raw) != TYPE_ARRAY:
		return null
	var pair: Array = raw
	if pair.size() != 2:
		return null
	var a: int = int(pair[0])
	var b: int = int(pair[1])
	if a < 0 or a > GameState.MAX_PIP or b < 0 or b > GameState.MAX_PIP:
		return null
	return Domino.new(a, b)


static func encode_tiles(tiles: Array) -> Array:
	var out: Array = []
	for t in tiles:
		out.append(encode_tile(t))
	return out


## Devuelve una lista vacía si CUALQUIER ficha viene mal. Se descarta la lista entera
## en vez de saltarse las fichas malas de a una: media lista es peor que ninguna,
## porque el juego seguiría con un tablero al que le faltan piezas.
static func decode_tiles(raw: Variant) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		push_error("Protocol: se esperaba una lista de fichas")
		return []
	var out: Array = []
	for entry in raw:
		var t: Domino = decode_tile(entry)
		if t == null:
			push_error("Protocol: ficha inválida en la lista (%s)" % str(entry))
			return []
		out.append(t)
	return out


# ---------------------------------------------------------------------------
# Vistas
# ---------------------------------------------------------------------------
# Se copia el diccionario y se reemplaza solo la clave que tiene fichas. Así, si
# mañana GameState agrega un campo a una vista, viaja solo sin tocar nada de acá — y
# si ese campo trajera fichas, la prueba de ida y vuelta lo caza.
static func encode_public_view(pub: Dictionary) -> Dictionary:
	var out: Dictionary = pub.duplicate()
	out["board"] = encode_tiles(pub.board)
	return out


static func decode_public_view(raw: Dictionary) -> Dictionary:
	var out: Dictionary = to_ints(raw)
	out["board"] = decode_tiles(out.get("board", []))
	return out


static func encode_private_view(mine: Dictionary) -> Dictionary:
	var out: Dictionary = mine.duplicate()
	out["tiles"] = encode_tiles(mine.tiles)
	return out


static func decode_private_view(raw: Dictionary) -> Dictionary:
	var out: Dictionary = to_ints(raw)
	out["tiles"] = decode_tiles(out.get("tiles", []))
	return out


static func encode_reveal(reveal: Dictionary) -> Dictionary:
	var out: Dictionary = reveal.duplicate()
	var hands: Array = []
	for hand in reveal.hands:
		hands.append(encode_tiles(hand))
	out["hands"] = hands
	return out


static func decode_reveal(raw: Dictionary) -> Dictionary:
	var out: Dictionary = to_ints(raw)
	var hands: Array = []
	for hand in out.get("hands", []):
		hands.append(decode_tiles(hand))
	out["hands"] = hands
	return out


# ---------------------------------------------------------------------------
# Eventos
# ---------------------------------------------------------------------------
static func encode_events(list: Array) -> Array:
	var out: Array = []
	for e in list:
		out.append(encode_event(e))
	return out


static func decode_events(raw: Variant) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		push_error("Protocol: se esperaba una lista de eventos")
		return []
	var out: Array = []
	for e in raw:
		if typeof(e) != TYPE_DICTIONARY:
			push_error("Protocol: evento que no es un mapa (%s)" % str(e))
			return []
		out.append(decode_event(e))
	return out


static func encode_event(e: Dictionary) -> Dictionary:
	var out: Dictionary = e.duplicate()
	if e.has("tile"):
		out["tile"] = encode_tile(e.tile)
	return out


static func decode_event(raw: Dictionary) -> Dictionary:
	var out: Dictionary = to_ints(raw)
	if out.has("tile"):
		out["tile"] = decode_tile(out.tile)
	return out


# ---------------------------------------------------------------------------
# Números
# ---------------------------------------------------------------------------
## JSON tiene un solo tipo numérico, así que al volver TODO llega como flotante: un
## puesto 2 vuelve como 2.0. Eso rompe de una manera fea, porque en GDScript indexar
## un arreglo con un flotante es un error, y las vistas están llenas de números que se
## usan justo así (`SEAT_NAMES[pub.current_player]`, `pub.hand_counts[seat]`).
##
## Se arregla acá y no en la pantalla: la pantalla no debería enterarse nunca de que el
## dato pasó por un cable, y ponerle int() a cada uso son decenas de lugares donde
## olvidarse de uno.
##
## Vale porque en estas vistas y eventos NO hay ni un número fraccionario: son puestos,
## puntos, índices y cantidades. Si alguna vez se agrega uno, hay que exceptuarlo acá —
## y el arnés lo avisa, porque comprueba que en lo codificado no viaje ningún flotante.
static func to_ints(value: Variant) -> Variant:
	var kind: int = typeof(value)
	if kind == TYPE_FLOAT:
		return int(value)
	if kind == TYPE_DICTIONARY:
		var out: Dictionary = {}
		for key in (value as Dictionary).keys():
			out[key] = to_ints((value as Dictionary)[key])
		return out
	if kind == TYPE_ARRAY:
		var list: Array = []
		for entry in value:
			list.append(to_ints(entry))
		return list
	return value
