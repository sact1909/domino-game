extends Control

## Pantalla de entrada y lobby para jugar en red.
##
## Tiene dos caras sobre el mismo fondo: la de ENTRADA (nombre, servidor, crear o entrar
## con código) y la de SALA (las cuatro sillas, quién está en cada una, y el botón de
## empezar si sos el anfitrión).
##
## Es la única pantalla que conoce el tipo concreto WsClientTransport, porque necesita la
## parte de sala que no está en el contrato: conectar, crear, entrar, cambiar de silla.
## La pantalla de juego no ve nada de eso — recibe el transporte ya conectado por el
## buzón de TransportHandoff y solo usa el contrato.
##
## Se construye por código igual que la mesa, para no depender de escenas del editor.

const GAME_SCENE := "res://scenes/Main.tscn"

## Dónde se recuerdan el nombre y el servidor. "user://" es la carpeta de datos del
## jugador, aparte del juego: sirve igual en un ejecutable repartido, donde la carpeta de
## instalación puede ser de solo lectura.
const SETTINGS_PATH := "user://lobby.cfg"

## Nombres de los puestos, en el mismo orden que en la mesa. Acá son la IDENTIDAD de la
## silla: los enfrentados (0-2 y 1-3) son compañeros, y por eso elegir silla es elegir
## pareja.
const SEAT_NAMES := ["Sur", "Este", "Norte", "Oeste"]
const TEAM_NAMES := ["Sur-Norte", "Este-Oeste"]

## Orden en que se listan las sillas: por lado, para que los compañeros queden juntos y
## se lea de un vistazo quién juega con quién.
const SEAT_ORDER := [0, 2, 1, 3]

enum Screen { ENTRY, ROOM }

var transport: WsClientTransport

## Qué se quiso hacer al apretar el botón. Se guarda porque conectar tarda: la acción se
## manda recién cuando el socket está abierto.
var _pending: Dictionary = {}

var _screen: int = Screen.ENTRY
var _code: String = ""
var _my_seat: int = -1
var _is_host: bool = false

# Nodos de la cara de entrada.
var entry_panel: PanelContainer
var name_field: LineEdit
var url_field: LineEdit
var code_field: LineEdit
var status_label: Label
var entry_buttons: Array = []

# Nodos de la cara de sala.
var room_panel: PanelContainer
var code_label: Label
var seat_rows: Array = []
var seats_hint: Label

## Silla que el anfitrión tocó primero, esperando la segunda para intercambiar. -1 si no
## hay ninguna elegida.
var _picked_seat: int = -1

## Último lobby recibido, para poder repintar las filas sin esperar otro mensaje (por
## ejemplo al elegir una silla, que es un cambio solo de esta pantalla).
var _last_players: Array = []
var _last_host_seat: int = -1
var host_box: VBoxContainer
var start_button: Button
var room_status: Label
var spin_target: SpinBox
var spin_pase_seguido: SpinBox
var spin_capicua: SpinBox
var spin_pase_salida: SpinBox


# ===========================================================================
# Construcción
# ===========================================================================
func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.28, 0.16)
	bg.position = Vector2.ZERO
	bg.size = Vector2(1280, 900)
	add_child(bg)

	_build_entry()
	_build_room()
	_show_screen(Screen.ENTRY)

	# Queda en el registro a qué servidor apunta esta copia. Es lo primero que hay que
	# saber cuando alguien reporta que "no conecta", y en un ejecutable repartido es la
	# única forma de averiguarlo sin el campo a la vista.
	print("[lobby] servidor: %s" % url_field.text.strip_edges())

	# Puede haber un socket esperando en el buzón: es la vuelta desde la mesa cuando se
	# pide revancha. En ese caso no hay nada que conectar, la sala sigue siendo la misma
	# y begin() repite el estado para volver a pintarla.
	var handed: Transport = TransportHandoff.take()
	if handed != null:
		transport = handed as WsClientTransport
		_wire(transport)
		add_child(transport)
		transport.begin()


func _build_entry() -> void:
	entry_panel = PanelContainer.new()
	_style(entry_panel)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(entry_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	entry_panel.add_child(vb)

	vb.add_child(_title("Jugar en línea"))

	var intro := Label.new()
	intro.text = "Crea una sala y comparte el código, o entra al código que te dieron.\nLos puestos que queden vacíos los juega la máquina."
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	intro.custom_minimum_size = Vector2(520, 0)
	intro.add_theme_font_size_override("font_size", 13)
	vb.add_child(intro)

	name_field = _field(vb, "Tu nombre", "Jugador")
	name_field.max_length = 16

	# El campo del servidor solo aparece si este ejecutable NO trae la dirección horneada.
	# Cuando la trae —que es como se reparte a los amigos— no hay nada que escribir, y un
	# campo con una dirección rara es una invitación a romperlo sin querer.
	url_field = _field(vb, "Servidor", WsClientTransport.resolve_url())
	if not WsClientTransport.baked_url().is_empty():
		url_field.get_parent().visible = false

	var create_btn := Button.new()
	create_btn.text = "Crear una sala nueva"
	create_btn.custom_minimum_size = Vector2(260, 40)
	create_btn.pressed.connect(_on_create_pressed)
	vb.add_child(_centered(create_btn))
	entry_buttons.append(create_btn)

	var sep := HSeparator.new()
	vb.add_child(sep)

	code_field = _field(vb, "Código de la sala", "")
	code_field.placeholder_text = "%d letras" % RoomCode.LENGTH
	code_field.max_length = 12

	var join_btn := Button.new()
	join_btn.text = "Entrar con el código"
	join_btn.custom_minimum_size = Vector2(260, 40)
	join_btn.pressed.connect(_on_join_pressed)
	vb.add_child(_centered(join_btn))
	entry_buttons.append(join_btn)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	status_label.custom_minimum_size = Vector2(520, 20)
	status_label.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	vb.add_child(status_label)

	_load_settings()

	var back_btn := Button.new()
	back_btn.text = "Volver a jugar contra la máquina"
	back_btn.custom_minimum_size = Vector2(260, 32)
	back_btn.pressed.connect(_on_back_pressed)
	vb.add_child(_centered(back_btn))
	entry_buttons.append(back_btn)


func _build_room() -> void:
	room_panel = PanelContainer.new()
	_style(room_panel)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(room_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	room_panel.add_child(vb)

	vb.add_child(_title("Sala"))

	# El código va grande porque su único propósito es que alguien lo lea y lo pase.
	code_label = Label.new()
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.add_theme_font_size_override("font_size", 42)
	code_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	vb.add_child(code_label)

	var hint := Label.new()
	hint.text = "Pásales este código a tus amigos para que entren"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	vb.add_child(hint)

	seats_hint = Label.new()
	seats_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seats_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	seats_hint.custom_minimum_size = Vector2(520, 0)
	seats_hint.add_theme_font_size_override("font_size", 13)
	vb.add_child(seats_hint)

	# Las cuatro sillas, ordenadas por lado para que los compañeros queden juntos a la
	# vista. Solo el anfitrión las puede tocar: toca una, toca otra, y se intercambian.
	# Con una sola persona repartiendo no hay carrera ni rechazos que explicar.
	seat_rows = []
	for i in range(SEAT_ORDER.size()):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(520, 40)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_seat_pressed.bind(int(SEAT_ORDER[i])))
		vb.add_child(btn)
		seat_rows.append(btn)
	# Los ajustes de la partida los ve solo el anfitrión: es quien los manda.
	host_box = VBoxContainer.new()
	host_box.add_theme_constant_override("separation", 6)
	vb.add_child(host_box)

	var config_title := Label.new()
	config_title.text = "Ajustes de la partida"
	config_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	config_title.add_theme_font_size_override("font_size", 15)
	config_title.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	host_box.add_child(config_title)

	var defaults: Dictionary = Transport.default_config()
	spin_target = _spin(host_box, "Meta de puntos", int(defaults.target_score), 50, 1000)
	spin_pase_seguido = _spin(host_box, "Valor del Pase seguido", int(defaults.bonus_pase_seguido), 0, 500)
	spin_capicua = _spin(host_box, "Valor de la Capicúa", int(defaults.bonus_capicua), 0, 500)
	spin_pase_salida = _spin(host_box, "Valor del Pase de Salida", int(defaults.bonus_pase_salida), 0, 500)

	start_button = Button.new()
	start_button.text = "Comenzar partida"
	start_button.custom_minimum_size = Vector2(260, 42)
	start_button.pressed.connect(_on_start_pressed)
	host_box.add_child(_centered(start_button))

	room_status = Label.new()
	room_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	room_status.custom_minimum_size = Vector2(520, 20)
	room_status.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	vb.add_child(room_status)

	var leave_btn := Button.new()
	leave_btn.text = "Salir de la sala"
	leave_btn.custom_minimum_size = Vector2(260, 32)
	leave_btn.pressed.connect(_on_leave_pressed)
	vb.add_child(_centered(leave_btn))


# ===========================================================================
# Lo que hace el usuario
# ===========================================================================
func _on_create_pressed() -> void:
	_connect_and({"kind": "create"})


func _on_join_pressed() -> void:
	# Se normaliza antes de validar: la gente lo escribe en minúscula, con guiones o con
	# espacios de sobra, y nada de eso debería dejarla afuera.
	var code: String = RoomCode.normalize(code_field.text)
	if not RoomCode.is_valid(code):
		_set_status("Ese código no parece válido: son %d letras, sin números ni vocales." % RoomCode.LENGTH)
		return
	_connect_and({"kind": "join", "code": code})


## Abre el socket y deja la acción anotada. No se manda nada todavía: conectar tarda, y
## un mensaje puesto antes de que el socket esté abierto se pierde sin aviso.
func _connect_and(action: Dictionary) -> void:
	if transport != null:
		return
	_pending = action
	_save_settings()
	_set_status("Conectando…")
	_set_entry_enabled(false)

	transport = WsClientTransport.new(url_field.text.strip_edges())
	_wire(transport)
	add_child(transport)
	transport.begin()


func _wire(t: WsClientTransport) -> void:
	t.connected.connect(_on_connected)
	# Sin esto, la idea que tiene esta pantalla de en qué silla está se queda vieja en
	# cuanto el anfitrión reorganiza: la marca de "tú" apuntaría a la silla equivocada y
	# el cálculo de quién es anfitrión podría fallar.
	t.seat_assigned.connect(_on_seat_assigned)
	t.connection_failed.connect(_on_connection_failed)
	t.disconnected.connect(_on_lost_connection)
	t.room_joined.connect(_on_room_joined)
	t.lobby_changed.connect(_on_lobby_changed)
	t.server_error.connect(_on_server_error)


## Reorganizar la mesa: se toca una silla y después otra, y se intercambian. Solo el
## anfitrión; a los demás los botones les llegan deshabilitados.
func _on_seat_pressed(seat: int) -> void:
	if transport == null or not _is_host:
		return
	if _picked_seat < 0:
		_picked_seat = seat
		_refresh_seat_rows()
		_set_room_status("Ahora toca la otra silla para intercambiarlas.")
		return
	if _picked_seat == seat:
		# Tocar la misma dos veces cancela: es la forma natural de arrepentirse.
		_picked_seat = -1
		_refresh_seat_rows()
		_set_room_status("")
		return
	var first: int = _picked_seat
	_picked_seat = -1
	_set_room_status("")
	# Se pide y se espera: el servidor decide y contesta con el lobby actualizado.
	transport.swap_seats(first, seat)


func _on_start_pressed() -> void:
	if transport == null or not _is_host:
		return
	start_button.disabled = true
	_set_room_status("Repartiendo…")
	transport.start_match({
		"target_score": int(spin_target.value),
		"bonus_pase_seguido": int(spin_pase_seguido.value),
		"bonus_capicua": int(spin_capicua.value),
		"bonus_pase_salida": int(spin_pase_salida.value),
	})


func _on_leave_pressed() -> void:
	if transport != null:
		transport.leave_room()
		transport.close()
		transport.queue_free()
		transport = null
	_code = ""
	_my_seat = -1
	_is_host = false
	_picked_seat = -1
	_pending = {}
	_set_entry_enabled(true)
	_set_status("")
	_show_screen(Screen.ENTRY)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


# ===========================================================================
# Lo que llega del servidor
# ===========================================================================
func _on_connected() -> void:
	var player_name: String = name_field.text.strip_edges()
	if str(_pending.get("kind", "")) == "create":
		_set_status("Creando la sala…")
		transport.create_room(player_name)
		return
	_set_status("Entrando…")
	transport.join_room(str(_pending.get("code", "")), player_name)


func _on_connection_failed(reason: String) -> void:
	_teardown()
	if reason == "protocolo_incompatible":
		_set_status("El servidor habla otra versión del protocolo. Hay que actualizar el juego o el servidor.")
		return
	_set_status("No se pudo conectar a %s. ¿Está corriendo el servidor?" % url_field.text.strip_edges())


func _on_lost_connection() -> void:
	_teardown()
	_show_screen(Screen.ENTRY)
	_set_status("Se perdió la conexión con el servidor.")


## El servidor dice en qué silla quedaste. Llega al entrar y cada vez que el anfitrión
## reorganiza la mesa.
func _on_seat_assigned(seat: int) -> void:
	_my_seat = seat
	_is_host = (_last_host_seat >= 0 and _my_seat == _last_host_seat)
	_refresh_seat_rows()


func _on_room_joined(code: String, seat: int, is_host: bool) -> void:
	_code = code
	_my_seat = seat
	_is_host = is_host
	code_label.text = code
	_set_room_status("")
	_show_screen(Screen.ROOM)


## El lobby cambió: alguien entró, salió o se cambió de silla. También es lo que avisa
## que la partida arrancó, y llega ANTES de los primeros snapshots — así que es el
## momento exacto para irse a la mesa.
func _on_lobby_changed(players: Array, host_seat: int, room_phase: int) -> void:
	_is_host = (_my_seat >= 0 and _my_seat == host_seat)
	host_box.visible = _is_host

	_last_players = players
	_last_host_seat = host_seat
	_refresh_seat_rows()

	if room_phase == Protocol.ROOM_PLAYING:
		_hand_off()


func _on_server_error(reason: String) -> void:
	var text: String = _error_text(reason)
	if reason == "sala_cerrada":
		# El anfitrión cerró la sala. El socket sigue abierto: se puede crear otra o
		# entrar a una distinta sin reconectar.
		_code = ""
		_my_seat = -1
		_is_host = false
		_picked_seat = -1
		_set_entry_enabled(true)
		_show_screen(Screen.ENTRY)
		_set_status(text)
		return
	if _screen == Screen.ENTRY:
		_teardown()
		_set_status(text)
		return
	# Ya dentro de la sala: el error es sobre lo último que se pidió (una silla ocupada,
	# no ser el anfitrión), así que no hay que desconectar nada.
	start_button.disabled = false
	_set_room_status(text)


# ===========================================================================
# Traspaso a la mesa
# ===========================================================================
## Se lleva el socket ya conectado a la pantalla de juego. Hay que sacarlo del árbol
## ANTES de cambiar de escena: si siguiera colgando de este nodo, se destruiría con él y
## la conexión se cortaría justo al empezar a jugar.
##
## Mientras está fuera del árbol no corre su _process, así que no lee el socket. Los
## mensajes que manda el servidor en ese rato no se pierden: quedan en la cola del peer y
## se leen en cuanto la mesa lo vuelve a colgar del árbol.
func _hand_off() -> void:
	if transport == null:
		return
	var going: WsClientTransport = transport
	transport = null
	remove_child(going)
	TransportHandoff.put(going)
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


# ===========================================================================
# Andamios
# ===========================================================================
func _teardown() -> void:
	if transport == null:
		return
	transport.close()
	transport.queue_free()
	transport = null
	_pending = {}
	_set_entry_enabled(true)


func _show_screen(which: int) -> void:
	_screen = which
	entry_panel.get_parent().visible = (which == Screen.ENTRY)
	room_panel.get_parent().visible = (which == Screen.ROOM)


## Repinta las cuatro sillas con lo último que se sabe. Se hace aparte del mensaje del
## servidor porque elegir una silla para intercambiar es un cambio solo de esta pantalla:
## no hay nada que pedirle a nadie hasta que se toque la segunda.
func _refresh_seat_rows() -> void:
	var can_organize: bool = _is_host
	seats_hint.text = "Toca dos sillas para intercambiarlas y armar los equipos." if can_organize else "El anfitrión arma los equipos."

	for i in range(seat_rows.size()):
		var seat: int = int(SEAT_ORDER[i])
		var btn: Button = seat_rows[i]
		btn.text = _seat_text(seat)
		btn.disabled = not can_organize


## Una silla: de qué lado es, quién está en ella y las marcas que le corresponden.
func _seat_text(seat: int) -> String:
	var team: String = TEAM_NAMES[GameState.TEAM_OF_SEAT[seat]]
	var picked: String = "►  " if _picked_seat == seat else "     "
	return "%s%s (%s):   %s" % [picked, SEAT_NAMES[seat], team, _who_at(seat)]


func _who_at(seat: int) -> String:
	if not _seat_occupied(_last_players, seat):
		return "libre (la juega la máquina)"
	var who: String = str((_last_players[seat] as Dictionary).get("name", ""))
	if seat == _last_host_seat:
		who += "  ·anfitrión"
	if seat == _my_seat:
		who += "  ·tú"
	return who


func _seat_occupied(players: Array, seat: int) -> bool:
	if seat >= players.size():
		return false
	return bool((players[seat] as Dictionary).get("occupied", false))


## Los motivos vienen como clave, no como texto: el idioma se resuelve acá, igual que en
## la mesa. Los que no se reconocen se muestran tal cual, que es mejor que esconderlos.
func _error_text(reason: String) -> String:
	match reason:
		"sala_no_existe":
			return "No existe ninguna sala con ese código. Revísalo con quien te lo pasó."
		"codigo_invalido":
			return "Ese código no tiene la forma correcta."
		"sala_llena":
			return "Esa sala ya tiene cuatro jugadores."
		"partida_en_curso":
			return "Esa sala ya empezó a jugar."
		"puesto_ocupado":
			return "Alguien se sentó ahí antes que tú."
		"puesto_invalido":
			return "Esa silla no existe."
		"solo_el_anfitrion":
			return "Solo quien creó la sala puede empezar la partida."
		"ya_estas_en_una_sala":
			return "Ya estás en una sala."
		"servidor_lleno":
			return "El servidor no tiene lugar para más salas ahora mismo."
		"protocolo_incompatible":
			return "El servidor habla otra versión del protocolo."
		"sala_cerrada":
			return "El anfitrión cerró la sala."
		"sillas_vacias":
			return "Las dos sillas están vacías: no hay nada que intercambiar."
	return "El servidor rechazó la petición (%s)." % reason


func _set_status(text: String) -> void:
	status_label.text = text


func _set_room_status(text: String) -> void:
	room_status.text = text


func _set_entry_enabled(enabled: bool) -> void:
	for b in entry_buttons:
		(b as Button).disabled = not enabled


func _title(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 30)
	return lbl


func _centered(node: Control) -> CenterContainer:
	var box := CenterContainer.new()
	box.add_child(node)
	return box


func _field(parent: VBoxContainer, label_text: String, initial: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(180, 0)
	row.add_child(lbl)

	var field := LineEdit.new()
	field.text = initial
	field.custom_minimum_size = Vector2(320, 32)
	row.add_child(field)
	return field


func _spin(parent: VBoxContainer, label_text: String, initial: int, low: int, high: int) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(220, 0)
	row.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = 5
	spin.value = initial
	spin.custom_minimum_size = Vector2(120, 30)
	row.add_child(spin)
	return spin


## El fondo de un PanelContainer no es opaco por defecto, y sin esto se vería el verde de
## la mesa atravesando el texto.
func _style(panel: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.14, 0.11, 1.0)
	sb.border_color = Color(0.9, 0.85, 0.7)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)


# ===========================================================================
# Lo que se recuerda entre sesiones
# ===========================================================================
## El nombre y el servidor se guardan para no volver a escribirlos. Importa más de lo que
## parece: si el juego se reparte sin la dirección horneada, cada jugador la pega una vez
## y no la vuelve a ver nunca.
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return

	var saved_name: String = str(cfg.get_value("lobby", "name", ""))
	if not saved_name.is_empty():
		name_field.text = saved_name

	# La URL guardada solo se usa si el jugador de verdad puede elegirla. Si vino por
	# línea de comandos se escribió a propósito para esta corrida, y si viene horneada el
	# campo ni se muestra: en los dos casos una dirección vieja del disco solo estorba.
	if not WsClientTransport.url_from_command_line().is_empty():
		return
	if not WsClientTransport.baked_url().is_empty():
		return
	var saved_url: String = str(cfg.get_value("lobby", "url", ""))
	if not saved_url.is_empty():
		url_field.text = saved_url


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("lobby", "name", name_field.text.strip_edges())
	cfg.set_value("lobby", "url", url_field.text.strip_edges())
	# Si no se puede escribir no pasa nada grave: solo hay que volver a teclearlos.
	var err: int = cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("No se pudieron guardar los ajustes del lobby (error %d)." % err)
