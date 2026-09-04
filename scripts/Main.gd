extends Control

# ---------------------------------------------------------------------------
# Constantes de la mesa
# ---------------------------------------------------------------------------
# Los nombres son la IDENTIDAD del puesto, no su lugar en pantalla: el asiento 0 es
# Sur siempre, aunque quien juegue en esta pantalla sea Norte. El orden de turno va
# en sentido contrario a las agujas del reloj: 0 -> 1 -> 2 -> 3 -> 0.
const SEAT_NAMES := ["Sur", "Este", "Norte", "Oeste"]
const TEAM_NAMES := ["Sur-Norte", "Este-Oeste"]

# La mesa tiene cuatro puestos. Que sean cuatro es un dato de la PANTALLA, no de las
# reglas: son los cuatro paneles que se dibujan, uno por lado, y coincide con la
# cantidad de nombres de arriba.
const SEAT_COUNT := 4

# Posiciones de la pantalla, siempre vistas desde el jugador local.
const POS_BOTTOM := 0
const POS_RIGHT := 1
const POS_TOP := 2
const POS_LEFT := 3

# Cada lado de la hilera avanza en fila (máx. 5 fichas seguidas); al llegar a esa
# cantidad, dobla UNA sola vez en toda la partida (el lado derecho hacia arriba, el
# izquierdo hacia abajo) y desde ahí sigue derecho en el sentido contrario el resto
# de la mano, igual que en una mesa real cuando la cadena se acerca al borde.
const ROW_LENGTH := 5

const LOBBY_SCENE := "res://scenes/Lobby.tscn"

enum Phase { SETUP, PLAYING, HAND_OVER, GAME_OVER }

# ---------------------------------------------------------------------------
# Estado
# ---------------------------------------------------------------------------
# Este script es SOLO cliente: dibuja, atiende al usuario y redacta mensajes. No
# tiene las reglas ni las puede consultar — no conoce GameState. Todo lo que sabe
# del juego le llega por el transporte, y todo lo que quiere hacer se lo pide.
#
# Hoy el transporte es LocalTransport, que corre las reglas y la IA en este mismo
# proceso. Cuando el juego sea en red se cambia por uno que hable con el servidor y
# este archivo no se toca.
var transport: Transport


## Si la partida es en red. Cambia poco: no se muestra la pantalla de configuración
## —eso ya lo decidió el anfitrión en el lobby— y al terminar se vuelve al lobby en vez
## de reconfigurar acá.
var online_mode: bool = false

# Si se cayó la conexión. Cambia qué ofrece la pantalla de fin: sin socket no hay sala a
# la que volver ni que cerrar.
var connection_lost: bool = false

# Quién está en cada puesto: el nombre si es una persona, vacío si la juega la máquina.
# Llega del transporte y se mantiene al día durante la partida.
var seat_owners: Array = ["", "", "", ""]

# Puesto que juega en ESTA pantalla. Su mano va siempre abajo y los otros tres se
# acomodan alrededor según su lugar en el orden de turno. NO se elige acá: llega en
# seat_assigned y se acata. Hoy detrás de eso hay un argumento de línea de comandos;
# en red será la sala.
var local_seat: int = 0

# Todo el dibujado sale de estas dos vistas y de nada más: "pub" es lo que ve la mesa
# entera y "mine" son las fichas del puesto local. Llegan armadas en cada snapshot,
# así que en pantalla no puede aparecer nada que en red no hubiera venido del
# servidor.
var pub: Dictionary = {}
var mine: Dictionary = {}

# Destape de fin de mano: las cuatro manos, para el resumen de puntos. Llega solo
# junto con el cierre de la mano — antes de eso sería filtrar las fichas de los
# demás.
var reveal: Dictionary = {}

# "phase" es de la interfaz, no de las reglas: controla qué se puede tocar en
# pantalla. La mueven las señales del transporte, no este script por su cuenta.
var phase: int = Phase.SETUP

# ---------------------------------------------------------------------------
# Referencias a nodos de interfaz (creados en tiempo de ejecución)
# ---------------------------------------------------------------------------
var lbl_target: Label
var lbl_score0: Label
var lbl_score1: Label
var lbl_turn: Label
var lbl_ends: Label

var top_title: Label
var top_row: HBoxContainer
var own_hand_row: HBoxContainer
var pass_status: Label

var left_title: Label
var left_stack: VBoxContainer
var right_title: Label
var right_stack: VBoxContainer

var board_viewport: Control

var log_rt: RichTextLabel

var start_overlay: Control
var selected_target: int = 200
var target_option_buttons: Array = []
var spin_pase_seguido: SpinBox
var spin_capicua: SpinBox
var spin_pase_salida: SpinBox

var end_choice_popup: PanelContainer
var pending_hand_idx: int = -1

# Si se mandó una jugada y todavía no llegó el estado nuevo. Jugando en local se aclara
# en el mismo instante, pero en red pasan cientos de milisegundos con la mano todavía
# habilitada: un segundo clic manda una jugada duplicada que el servidor rechaza, y el
# jugador ve un error que no entiende. Mientras esto está puesto, la mano se apaga.
var awaiting_play: bool = false

# Aviso flotante (pases, bonificaciones) y las bolitas de turno de cada puesto.
var toast_panel: PanelContainer
var toast_label: Label
var toast_tween: Tween
var turn_dots: Array = [null, null, null, null]
var own_title: Label

# Pantalla de fin de mano: se queda esperando el botón "Continuar" en vez de seguir
# sola, para que se pueda revisar de dónde salieron los puntos.
var hand_result_overlay: Control
var hand_result_content: VBoxContainer
var pending_winner_team: int = -1

var game_over_overlay: Control
var game_over_label: Label
var again_button: Button
var leave_button: Button


# ===========================================================================
# Construcción de la interfaz
# ===========================================================================
func _ready() -> void:
	_build_background()
	_build_top_bar()
	_build_ends_label()
	_build_top_panel()
	_build_own_panel()
	_build_left_panel()
	_build_right_panel()
	_build_board_area()
	_build_log_panel()
	_build_end_choice_popup()
	_build_toast()
	_build_hand_result_overlay()
	_build_game_over_overlay()
	_build_start_overlay()

	# El transporte se engancha con la interfaz ya construida, porque begin() puede
	# contestar en el acto —en local lo hace— y esos manejadores ya dibujan.
	transport = _take_transport()
	if online_mode:
		# La configuración ya se eligió en el lobby, y el reparto lo manda el servidor:
		# no hay nada que preguntar acá.
		start_overlay.visible = false
	transport.seat_assigned.connect(_on_seat_assigned)
	transport.snapshot.connect(_on_snapshot)
	transport.events.connect(_on_events)
	transport.hand_started.connect(_on_hand_started)
	transport.hand_ended.connect(_on_hand_ended)
	transport.match_ended.connect(_on_match_ended)
	transport.server_error.connect(_on_server_error)
	transport.disconnected.connect(_on_disconnected)
	transport.seats_changed.connect(_on_seats_changed)
	add_child(transport)
	transport.begin()


## De dónde sale el transporte. Si el lobby dejó uno conectado en el buzón se usa ese;
## si no, se arma el local. take() vacía el buzón, así que volver a esta pantalla más
## tarde no reusa un socket ya cerrado.
func _take_transport() -> Transport:
	var handed: Transport = TransportHandoff.take()
	if handed != null:
		online_mode = true
		return handed
	return LocalTransport.new(_resolve_local_seat())


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.33, 0.16)
	bg.position = Vector2.ZERO
	bg.size = Vector2(1280, 900)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.position = Vector2(0, 0)
	bar.size = Vector2(1280, 50)
	add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(row)

	lbl_target = Label.new()
	lbl_target.add_theme_font_size_override("font_size", 18)
	row.add_child(lbl_target)

	lbl_score0 = Label.new()
	lbl_score0.add_theme_font_size_override("font_size", 18)
	row.add_child(lbl_score0)

	lbl_score1 = Label.new()
	lbl_score1.add_theme_font_size_override("font_size", 18)
	row.add_child(lbl_score1)

	lbl_turn = Label.new()
	lbl_turn.add_theme_font_size_override("font_size", 18)
	lbl_turn.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	row.add_child(lbl_turn)


# Va en su propia franja, debajo del panel de Norte: antes quedaba detrás de las
# fichas de Norte y no se leía.
func _build_ends_label() -> void:
	lbl_ends = Label.new()
	lbl_ends.position = Vector2(180, 178)
	lbl_ends.size = Vector2(920, 22)
	lbl_ends.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_ends.add_theme_font_size_override("font_size", 15)
	add_child(lbl_ends)


func _build_top_panel() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(440, 54)
	panel.size = Vector2(400, 120)
	panel.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(panel)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 8)
	panel.add_child(title_row)

	turn_dots[POS_TOP] = _make_turn_dot()
	title_row.add_child(turn_dots[POS_TOP])

	top_title = Label.new()
	top_title.add_theme_font_size_override("font_size", 14)
	title_row.add_child(top_title)

	top_row = HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_theme_constant_override("separation", 3)
	panel.add_child(top_row)


func _build_own_panel() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(300, 668)
	panel.size = Vector2(680, 225)
	panel.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(panel)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 8)
	panel.add_child(title_row)

	turn_dots[POS_BOTTOM] = _make_turn_dot()
	title_row.add_child(turn_dots[POS_BOTTOM])

	own_title = Label.new()
	own_title.text = "Tu mano"
	own_title.add_theme_font_size_override("font_size", 16)
	title_row.add_child(own_title)

	own_hand_row = HBoxContainer.new()
	own_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	own_hand_row.add_theme_constant_override("separation", 8)
	panel.add_child(own_hand_row)

	# Solo informa el estado del turno (el pase es automático), así que es una
	# etiqueta y no un botón deshabilitado.
	pass_status = Label.new()
	pass_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pass_status.add_theme_font_size_override("font_size", 14)
	pass_status.add_theme_color_override("font_color", Color(0.85, 0.88, 0.85))
	panel.add_child(pass_status)


# En los laterales la etiqueta va DEBAJO de la pila de fichas, siguiendo la columna,
# para que se lea junto a las fichas de ese jugador y no arriba, despegada de ellas.
func _build_left_panel() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(10, 204)
	panel.size = Vector2(160, 456)
	panel.alignment = BoxContainer.ALIGNMENT_BEGIN
	panel.add_theme_constant_override("separation", 8)
	add_child(panel)

	var center := CenterContainer.new()
	panel.add_child(center)

	left_stack = VBoxContainer.new()
	left_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	left_stack.add_theme_constant_override("separation", 6)
	center.add_child(left_stack)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 6)
	panel.add_child(title_row)

	turn_dots[POS_LEFT] = _make_turn_dot()
	title_row.add_child(turn_dots[POS_LEFT])

	left_title = Label.new()
	left_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	left_title.custom_minimum_size = Vector2(110, 0)
	left_title.add_theme_font_size_override("font_size", 14)
	title_row.add_child(left_title)


func _build_right_panel() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(1110, 204)
	panel.size = Vector2(160, 456)
	panel.alignment = BoxContainer.ALIGNMENT_BEGIN
	panel.add_theme_constant_override("separation", 8)
	add_child(panel)

	var center := CenterContainer.new()
	panel.add_child(center)

	right_stack = VBoxContainer.new()
	right_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	right_stack.add_theme_constant_override("separation", 6)
	center.add_child(right_stack)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 6)
	panel.add_child(title_row)

	turn_dots[POS_RIGHT] = _make_turn_dot()
	title_row.add_child(turn_dots[POS_RIGHT])

	right_title = Label.new()
	right_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	right_title.custom_minimum_size = Vector2(110, 0)
	right_title.add_theme_font_size_override("font_size", 14)
	title_row.add_child(right_title)


func _build_board_area() -> void:
	board_viewport = Control.new()
	board_viewport.position = Vector2(180, 204)
	board_viewport.size = Vector2(920, 456)
	board_viewport.clip_contents = true
	add_child(board_viewport)


func _build_log_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(10, 668)
	panel.size = Vector2(280, 222)
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "Registro de la mesa"
	title.add_theme_font_size_override("font_size", 14)
	vb.add_child(title)

	log_rt = RichTextLabel.new()
	log_rt.bbcode_enabled = true
	log_rt.scroll_following = true
	log_rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_rt.add_theme_font_size_override("normal_font_size", 13)
	vb.add_child(log_rt)


func _build_end_choice_popup() -> void:
	end_choice_popup = PanelContainer.new()
	end_choice_popup.position = Vector2(390, 214)
	# Más alto que antes para que el contenido quepa dentro de los márgenes del
	# fondo. El margen es menor que en los diálogos grandes: es un aviso chico.
	end_choice_popup.size = Vector2(500, 100)
	end_choice_popup.visible = false
	_apply_dialog_style(end_choice_popup, 14.0)
	add_child(end_choice_popup)

	var vb := VBoxContainer.new()
	end_choice_popup.add_child(vb)

	var lbl := Label.new()
	lbl.text = "¿En qué punta deseas jugar?"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)

	var left_btn := Button.new()
	left_btn.name = "LeftBtn"
	left_btn.text = "Izquierda"
	left_btn.pressed.connect(func(): _on_end_choice("L"))
	row.add_child(left_btn)

	var right_btn := Button.new()
	right_btn.name = "RightBtn"
	right_btn.text = "Derecha"
	right_btn.pressed.connect(func(): _on_end_choice("R"))
	row.add_child(right_btn)

	# Salida sin jugar. Hace falta porque mientras la elección está abierta la mano
	# queda bloqueada: sin este botón, elegir una ficha de dos puntas te obligaba a
	# jugarla.
	var cancel_btn := Button.new()
	cancel_btn.name = "CancelBtn"
	cancel_btn.text = "No jugar"
	cancel_btn.pressed.connect(_cancel_end_choice)
	row.add_child(cancel_btn)


func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.position = Vector2(390, 596)
	toast_panel.size = Vector2(500, 44)
	toast_panel.visible = false
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Fondo propio y opaco: se dibuja sobre las fichas del tablero, y con el estilo
	# por defecto se transparentaría y no se leería. El desvanecido usa "modulate",
	# que afecta también a este fondo, así que sigue funcionando.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.13, 0.09)
	sb.border_color = Color(1, 0.85, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	toast_panel.add_theme_stylebox_override("panel", sb)
	add_child(toast_panel)

	toast_label = Label.new()
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 17)
	toast_panel.add_child(toast_label)


# Aparece, se queda un momento y se desvanece. Si llega otro aviso antes de que
# termine, se corta el anterior para que no se solapen los desvanecidos.
func _show_toast(text: String) -> void:
	toast_label.text = text
	if toast_tween != null and toast_tween.is_valid():
		toast_tween.kill()
	toast_panel.modulate = Color(1, 1, 1, 1)
	toast_panel.visible = true
	toast_tween = create_tween()
	toast_tween.tween_interval(1.1)
	toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.7)
	toast_tween.tween_callback(func(): toast_panel.visible = false)


# El estilo por defecto de PanelContainer no es opaco, así que en un diálogo se
# transparenta el tablero y las manos de atrás y no se lee nada. Los diálogos llevan
# fondo propio, opaco.
func _apply_dialog_style(panel: PanelContainer, margin: float = 22.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.13, 0.09)
	sb.border_color = Color(0.55, 0.62, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(margin)
	panel.add_theme_stylebox_override("panel", sb)


func _make_turn_dot() -> Panel:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(16, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.32, 0.26)
	sb.set_corner_radius_all(8)
	dot.add_theme_stylebox_override("panel", sb)
	return dot


# Prende la bolita del puesto en turno y apaga las demás.
# Las bolitas están indexadas por LUGAR EN LA PANTALLA, no por puesto: hay que
# traducir de quién es el turno a dónde se dibuja ese jugador.
func _update_turn_dots() -> void:
	var active_pos: int = _screen_pos(pub.current_player)
	for pos in range(SEAT_COUNT):
		var dot: Panel = turn_dots[pos]
		if dot == null:
			continue
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		if phase == Phase.PLAYING and pos == active_pos:
			sb.bg_color = Color(1, 0.85, 0.25)
		else:
			sb.bg_color = Color(0.25, 0.32, 0.26)
		dot.add_theme_stylebox_override("panel", sb)


# Puesto local desde la línea de comandos, para poder probar la perspectiva sin
# tocar código:  godot -- --seat=2
# Es el puesto que se PIDE, no el que queda: el definitivo llega en seat_assigned.
# En red lo reemplazará el asiento que asigne la sala al entrar.
func _resolve_local_seat() -> int:
	for arg in OS.get_cmdline_user_args():
		var text: String = str(arg)
		if text.begins_with("--seat="):
			var value: String = text.substr(7)
			if value.is_valid_int():
				var seat: int = int(value)
				if seat >= 0 and seat < SEAT_COUNT:
					return seat
			push_warning("--seat=%s no es un puesto válido (0 a 3); se usa el 0." % value)
	return 0


# ===========================================================================
# Perspectiva: de puesto a lugar en la pantalla
# ===========================================================================
# El jugador local se ve siempre abajo. Como el orden de turno es 0->1->2->3, la
# posición de la derecha es siempre quien juega después de uno, y la de arriba es
# el compañero (los compañeros se sientan enfrentados).
func _screen_pos(seat: int) -> int:
	return posmod(seat - local_seat, SEAT_COUNT)


func _seat_at(pos: int) -> int:
	return posmod(local_seat + pos, SEAT_COUNT)


func _is_partner(seat: int) -> bool:
	return seat == _seat_at(POS_TOP)


# Etiqueta de un puesto ajeno: su nombre, que es IA, cuántas fichas le quedan y si
# es el compañero o salió en esta mano.
func _rival_label(seat: int, line_break: bool) -> String:
	var partner: String = " — tu compañero" if _is_partner(seat) else ""
	var separator: String = "\n" if line_break else " — "
	return "%s %s%s%s%d fichas%s" % [
		SEAT_NAMES[seat], _owner_label(seat), partner, separator, pub.hand_counts[seat], _lead_mark(seat),
	]


# Marca del jugador que salió en la mano, para tener siempre la referencia de quién
# jugó primero en esa ronda.
func _lead_mark(seat: int) -> String:
	if seat == pub.lead_player:
		return "  ·  salió"
	return ""


func _build_hand_result_overlay() -> void:
	hand_result_overlay = ColorRect.new()
	hand_result_overlay.color = Color(0, 0, 0, 0.7)
	hand_result_overlay.position = Vector2.ZERO
	hand_result_overlay.size = Vector2(1280, 900)
	hand_result_overlay.visible = false
	add_child(hand_result_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hand_result_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	_apply_dialog_style(panel)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)

	# El contenido se arma de nuevo en cada mano (las fichas cambian); el botón se
	# queda fijo, así su señal se conecta una sola vez.
	hand_result_content = VBoxContainer.new()
	hand_result_content.add_theme_constant_override("separation", 10)
	vb.add_child(hand_result_content)

	var continue_btn := Button.new()
	continue_btn.text = "Continuar"
	continue_btn.custom_minimum_size = Vector2(200, 42)
	continue_btn.pressed.connect(_on_hand_result_continue)
	var btn_center := CenterContainer.new()
	btn_center.add_child(continue_btn)
	vb.add_child(btn_center)


func _build_game_over_overlay() -> void:
	game_over_overlay = ColorRect.new()
	game_over_overlay.color = Color(0, 0, 0, 0.75)
	game_over_overlay.position = Vector2.ZERO
	game_over_overlay.size = Vector2(1280, 900)
	game_over_overlay.visible = false
	add_child(game_over_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_overlay.add_child(center)

	var panel := PanelContainer.new()
	_apply_dialog_style(panel)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)

	game_over_label = Label.new()
	game_over_label.add_theme_font_size_override("font_size", 26)
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(game_over_label)

	# Dos botones en fila. Jugando en local el segundo no tiene sentido —no hay sala que
	# cerrar ni de la que salir— así que se esconde.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)

	again_button = Button.new()
	again_button.text = "Jugar de nuevo"
	again_button.custom_minimum_size = Vector2(200, 40)
	again_button.pressed.connect(_on_play_again_pressed)
	row.add_child(again_button)

	leave_button = Button.new()
	leave_button.custom_minimum_size = Vector2(200, 40)
	leave_button.visible = false
	leave_button.pressed.connect(_on_leave_pressed)
	row.add_child(leave_button)


func _build_start_overlay() -> void:
	start_overlay = ColorRect.new()
	start_overlay.color = Color(0, 0, 0, 0.85)
	start_overlay.position = Vector2.ZERO
	start_overlay.size = Vector2(1280, 900)
	add_child(start_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	start_overlay.add_child(center)

	var panel := PanelContainer.new()
	_apply_dialog_style(panel)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.custom_minimum_size = Vector2(480, 340)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "Dominó Dominicano"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vb.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "4 jugadores, 2 parejas (Sur-Norte contra Este-Oeste). Tú juegas en el Sur; Norte es tu compañero."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	subtitle.custom_minimum_size = Vector2(430, 0)
	vb.add_child(subtitle)

	var goal_lbl := Label.new()
	goal_lbl.text = "Elige la meta de puntos de la mesa:"
	goal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(goal_lbl)

	var goal_row := HBoxContainer.new()
	goal_row.alignment = BoxContainer.ALIGNMENT_CENTER
	goal_row.add_theme_constant_override("separation", 10)
	vb.add_child(goal_row)

	target_option_buttons.clear()
	for goal in [100, 150, 200]:
		var b := Button.new()
		b.text = str(goal)
		b.toggle_mode = true
		b.button_pressed = (goal == selected_target)
		b.custom_minimum_size = Vector2(70, 36)
		b.pressed.connect(func(): _on_goal_selected(goal))
		goal_row.add_child(b)
		target_option_buttons.append(b)

	var bonus_lbl := Label.new()
	bonus_lbl.text = "Valor de las bonificaciones:"
	bonus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(bonus_lbl)

	# Los valores por defecto salen del protocolo y no de las reglas: es esta
	# pantalla la que los propone, y después viajan en start_match().
	var defaults: Dictionary = Transport.default_config()
	spin_pase_seguido = _add_bonus_field(vb, "Valor del Pase seguido", int(defaults.bonus_pase_seguido))
	spin_capicua = _add_bonus_field(vb, "Valor de la Capicúa", int(defaults.bonus_capicua))
	spin_pase_salida = _add_bonus_field(vb, "Valor del Pase de Salida", int(defaults.bonus_pase_salida))

	var rules_lbl := Label.new()
	rules_lbl.text = "Reglas: dominó doble-seis (28 fichas), 7 fichas por jugador, no existe pozo. Si tienes ficha jugable, debes jugarla: no se puede pasar voluntariamente. En la primera mano sale el 6-6 (el burro)."
	rules_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	rules_lbl.custom_minimum_size = Vector2(430, 0)
	rules_lbl.add_theme_font_size_override("font_size", 12)
	vb.add_child(rules_lbl)

	var start_btn := Button.new()
	start_btn.text = "Comenzar partida"
	start_btn.custom_minimum_size = Vector2(220, 44)
	start_btn.pressed.connect(_on_start_pressed)
	var start_center := CenterContainer.new()
	start_center.add_child(start_btn)
	vb.add_child(start_center)

	# La partida en red se arma en otra pantalla, con su propio transporte y su propio
	# ciclo. Mezclarla acá dejaría dos autoridades vivas a la vez.
	var online_btn := Button.new()
	online_btn.text = "Jugar en línea con amigos"
	online_btn.custom_minimum_size = Vector2(220, 36)
	online_btn.pressed.connect(_on_play_online_pressed)
	var online_center := CenterContainer.new()
	online_center.add_child(online_btn)
	vb.add_child(online_center)


func _add_bonus_field(parent: VBoxContainer, label_text: String, default_value: int) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(280, 0)
	lbl.add_theme_font_size_override("font_size", 14)
	row.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 500
	spin.step = 5
	spin.value = default_value
	spin.custom_minimum_size = Vector2(110, 0)
	row.add_child(spin)

	return spin


func _make_tile_back(w: int, h: int) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(w, h)
	p.size = Vector2(w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.1, 0.1)
	sb.border_color = Color(0.9, 0.85, 0.7)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	return p


# ===========================================================================
# Pantalla de inicio / fin de partida
# ===========================================================================
func _on_goal_selected(goal: int) -> void:
	selected_target = goal
	for b in target_option_buttons:
		b.button_pressed = (int(b.text) == goal)


func _on_start_pressed() -> void:
	# La configuración se MANDA; no se escribe en las reglas desde acá. En red este
	# mismo diccionario es el mensaje que sube el anfitrión.
	var config: Dictionary = {
		"target_score": selected_target,
		"bonus_pase_seguido": int(spin_pase_seguido.value),
		"bonus_capicua": int(spin_capicua.value),
		"bonus_pase_salida": int(spin_pase_salida.value),
	}
	start_overlay.visible = false
	log_rt.clear()
	_log("Partida nueva. Meta: %d puntos." % config.target_score)
	_log("Bonificaciones — pase seguido: %d, capicúa: %d, pase de salida: %d." % [config.bonus_pase_seguido, config.bonus_capicua, config.bonus_pase_salida])
	transport.start_match(config)


func _on_play_online_pressed() -> void:
	get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)


## Qué ofrece la pantalla de fin de partida. En red la sala NO se cierra sola: sigue
## viva con la misma gente, y cada uno decide si sigue. Cerrarla es potestad del
## anfitrión, que es quien la creó.
func _configure_end_buttons() -> void:
	if connection_lost:
		again_button.text = "Volver al inicio"
		leave_button.visible = false
		return
	if not online_mode:
		again_button.text = "Jugar de nuevo"
		leave_button.visible = false
		return
	again_button.text = "Volver a jugar"
	leave_button.visible = true
	if _is_room_host():
		leave_button.text = "Cerrar sala"
	else:
		leave_button.text = "Salir de la sala"


func _is_room_host() -> bool:
	var ws := transport as WsClientTransport
	return ws != null and ws.is_host()


func _on_play_again_pressed() -> void:
	if phase != Phase.GAME_OVER:
		return
	game_over_overlay.visible = false
	if not online_mode:
		start_overlay.visible = true
		return
	# La sala se mantiene: la misma gente en las mismas sillas. El servidor la devuelve
	# al lobby, y allá se espera a los demás.
	var ws := transport as WsClientTransport
	if ws != null and ws.is_open():
		ws.play_again()
	_return_to_lobby()


func _on_leave_pressed() -> void:
	if phase != Phase.GAME_OVER:
		return
	game_over_overlay.visible = false
	var ws := transport as WsClientTransport
	if ws != null and ws.is_open():
		if ws.is_host():
			ws.close_room()
		else:
			ws.leave_room()
	_return_to_lobby()


## Devuelve el socket al lobby por el mismo buzón por el que vino. Hay que sacarlo del
## árbol antes de cambiar de escena, igual que en la ida: si siguiera colgando de esta
## pantalla se destruiría con ella y habría que reconectar desde cero.
##
## Un socket ya cerrado no se traspasa: el lobby arranca de nuevo desde la entrada.
func _return_to_lobby() -> void:
	var ws := transport as WsClientTransport
	if ws != null and ws.is_open():
		transport = null
		remove_child(ws)
		TransportHandoff.put(ws)
	get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)


# ===========================================================================
# Lo que llega del transporte
# ===========================================================================
# Estos seis manejadores son la única entrada de información al cliente. Ninguno
# decide nada: guardan lo que llegó, lo dibujan y lo redactan.
func _on_seat_assigned(seat: int) -> void:
	local_seat = seat


# El estado nuevo. Se guarda y se redibuja todo: el dibujado es idempotente, así que
# no importa cuántos snapshots lleguen ni en qué momento.
func _on_snapshot(new_pub: Dictionary, new_mine: Dictionary) -> void:
	pub = new_pub
	mine = new_mine
	awaiting_play = false
	_render_all()


## Cambió quién está sentado. Se redibuja solo si ya hay algo que dibujar: en red este
## aviso llega antes del primer snapshot.
func _on_seats_changed(names: Array) -> void:
	seat_owners = names
	if not pub.is_empty():
		_render_all()


func _on_events(list: Array) -> void:
	for e in list:
		_handle_event(e)


func _on_hand_started() -> void:
	phase = Phase.PLAYING
	if pub.must_open_with_double_six:
		_log("Se reparten las fichas (7 por jugador, sin pozo). [b]%s[/b] tiene el 6-6 (el burro) y sale." % SEAT_NAMES[pub.current_player])
	else:
		_log("Nueva mano. Sale %s." % SEAT_NAMES[pub.current_player])
	# El snapshot del reparto ya llegó, pero con la fase todavía en SETUP o en
	# HAND_OVER: se redibuja para que la mano propia quede interactiva.
	_render_all()


func _on_hand_ended(closing: Dictionary, hand_reveal: Dictionary) -> void:
	# La fase se marca antes de redibujar: así la mano propia no queda dibujada como
	# interactiva en el mismo cuadro en que la mano ya terminó.
	phase = Phase.HAND_OVER
	reveal = hand_reveal
	_render_all()
	_show_hand_result_for(closing)


## Un rechazo del servidor. Se le dice al jugador en vez de dejar el clic sin efecto, y
## se desbloquea la mano: un rechazo no trae estado nuevo, así que nadie más lo haría.
func _on_server_error(reason: String) -> void:
	_show_toast(_rejection_text(reason))
	awaiting_play = false
	_render_own_hand()


## Se cayó la conexión. Hay que decirlo con claridad: sin esto la mesa se queda quieta y
## parece que el juego se colgó, que es lo peor que puede pasarle a alguien jugando.
func _on_disconnected() -> void:
	phase = Phase.GAME_OVER
	_cancel_end_choice()
	hand_result_overlay.visible = false
	connection_lost = true
	game_over_label.text = "Se perdió la conexión con el servidor."
	_configure_end_buttons()
	game_over_overlay.visible = true
	_log("[b]Se perdió la conexión con el servidor.[/b]")


func _on_match_ended(winner_team: int) -> void:
	phase = Phase.GAME_OVER
	game_over_label.text = "¡Equipo %s gana la partida!\nPuntaje final: %d - %d" % [TEAM_NAMES[winner_team], pub.team_score[0], pub.team_score[1]]
	_configure_end_buttons()
	game_over_overlay.visible = true
	_log("[b]Fin de la partida. Gana el equipo %s (%d - %d).[/b]" % [TEAM_NAMES[winner_team], pub.team_score[0], pub.team_score[1]])


# Traduce un evento a lo que se lee en pantalla. Acá vive el idioma; las reglas ya
# quedaron resueltas del otro lado.
func _handle_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"played":
			_log("%s jugó [b]%s[/b]." % [SEAT_NAMES[e.seat], str(e.tile)])
		"passed":
			_log("%s pasa (no tiene fichas con %d ni %d)." % [SEAT_NAMES[e.seat], e.left_end, e.right_end])
			_show_toast("%s pasó" % SEAT_NAMES[e.seat])
		"bonus":
			var text: String = _bonus_text(e)
			_log("[b]+%d[/b] al equipo %s — %s." % [e.pts, TEAM_NAMES[e.team], text])
			_show_toast("+%d  %s" % [e.pts, text])
		"opening_pass_cancelled":
			_log("Pase de salida anulado: %s (pareja de %s) tampoco pudo jugar." % [SEAT_NAMES[e.partner_seat], SEAT_NAMES[e.lead_seat]])
		"hand_won":
			_log("[b]%s[/b] colocó su última ficha. ¡Equipo %s gana la mano! (+%d puntos)" % [SEAT_NAMES[e.winner_seat], TEAM_NAMES[e.winner_team], e.pts])
		"tranque":
			_log("¡Tranque! %s (%d) contra %s (%d): gana el equipo %s. (+%d puntos)" % [SEAT_NAMES[e.closer], e.closer_pips, SEAT_NAMES[e.challenger], e.challenger_pips, TEAM_NAMES[e.winner_team], e.pts])
		"rejected":
			# El aviso al desarrollador se queda: jugando en local un rechazo solo puede
			# venir de un error de la interfaz. En red va a ser normal con latencia,
			# porque la mesa puede avanzar mientras el clic viaja.
			push_warning("Jugada rechazada de %s: %s" % [SEAT_NAMES[e.seat], e.reason])
			# Y al jugador se le dice: si no, el clic no hace nada y parece que el juego
			# se colgó.
			if e.seat == local_seat:
				_show_toast(_rejection_text(str(e.reason)))
				# Un rechazo no trae snapshot, así que hay que desbloquear y redibujar
				# acá: de lo contrario la mano se quedaría apagada para siempre.
				awaiting_play = false
				_render_own_hand()


# El evento trae el tipo de bonificación y quién la provocó; el texto se redacta
# acá, que es donde vive el idioma.
func _bonus_text(e: Dictionary) -> String:
	match str(e.get("kind", "")):
		"pase_seguido":
			return "Pase seguido (%s hizo pasar a los otros tres)" % SEAT_NAMES[e.seat]
		"capicua":
			return "Capicúa (%s cerró con ficha que iba en las dos puntas)" % SEAT_NAMES[e.seat]
		"pase_salida":
			return "Pase de salida (%s hizo pasar a %s)" % [SEAT_NAMES[e.seat], SEAT_NAMES[e.other_seat]]
	return "Bonificación"


# ===========================================================================
# Fin de mano y puntuación
# ===========================================================================
# Arma la pantalla de fin de mano a partir del evento de cierre. Las reglas y los
# puntos ya los resolvió la autoridad; acá solo se redacta lo que se lee en pantalla.
func _show_hand_result_for(e: Dictionary) -> void:
	# "reveal" ya viene puesto por _on_hand_ended: el destape llega junto con el
	# cierre de la mano, que es el único momento en que corresponde verlo.
	if str(e.get("type", "")) == "hand_won":
		var subtitle: String = "%s colocó su última ficha. Se cuentan todas las fichas que quedaron en la mesa, de las dos parejas." % SEAT_NAMES[e.winner_seat]
		if e.capicua:
			subtitle += " Cerró de capicúa: la ficha calzaba en las dos puntas."
		_show_hand_result(
			"¡Equipo %s gana la mano!" % TEAM_NAMES[e.winner_team],
			subtitle,
			{},
			e.winner_team,
			e.totals,
			e.pts
		)
		return

	var tranque_subtitle: String
	if e.tie:
		tranque_subtitle = "%s trancó el juego. Empate con %s (%d - %d): gana la pareja que tiene la mano." % [SEAT_NAMES[e.closer], SEAT_NAMES[e.challenger], e.closer_pips, e.challenger_pips]
	else:
		tranque_subtitle = "%s trancó el juego. Se comparan sus fichas con las de %s, que seguía en el turno: %d contra %d, gana %s." % [SEAT_NAMES[e.closer], SEAT_NAMES[e.challenger], e.closer_pips, e.challenger_pips, SEAT_NAMES[e.winner_seat]]

	# Se llena a mano en vez de con un literal: en un literal de diccionario una
	# clave sin comillas se toma como el nombre literal, no como el valor de la
	# variable, y las marcas nunca calzarían con el número de puesto.
	var notes := {}
	notes[e.closer] = "trancó"
	notes[e.challenger] = "seguía"

	_show_hand_result("¡Tranque!", tranque_subtitle, notes, e.winner_team, e.totals, e.pts)


# ===========================================================================
# Pantalla de fin de mano
# ===========================================================================
# Siempre se muestran las cuatro manos, porque todas las fichas que quedaron suman.
# "notes" marca jugadores concretos (en el tranque, quién trancó y quién seguía).
func _show_hand_result(title: String, subtitle: String, notes: Dictionary, winner_team: int, team_pips: Array, pts: int) -> void:
	pending_winner_team = winner_team

	for c in hand_result_content.get_children():
		hand_result_content.remove_child(c)
		c.queue_free()

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 26)
	hand_result_content.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = subtitle
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub_lbl.custom_minimum_size = Vector2(520, 0)
	sub_lbl.add_theme_font_size_override("font_size", 14)
	hand_result_content.add_child(sub_lbl)

	var count_head := Label.new()
	count_head.text = "Fichas que quedaron en la mesa (todas se cuentan)"
	count_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_head.add_theme_font_size_override("font_size", 14)
	hand_result_content.add_child(count_head)

	for team in [0, 1]:
		hand_result_content.add_child(_make_team_summary(team, team_pips[team], "Equipo %s" % TEAM_NAMES[team], notes))

	if not pub.hand_bonuses.is_empty():
		var bonus_head := Label.new()
		bonus_head.text = "Bonificaciones de la mano"
		bonus_head.add_theme_font_size_override("font_size", 15)
		bonus_head.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
		hand_result_content.add_child(bonus_head)

		for b in pub.hand_bonuses:
			var b_lbl := Label.new()
			b_lbl.text = "+%d  %s  →  %s" % [b.pts, _bonus_text(b), TEAM_NAMES[b.team]]
			b_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			b_lbl.custom_minimum_size = Vector2(520, 0)
			b_lbl.add_theme_font_size_override("font_size", 13)
			hand_result_content.add_child(b_lbl)

	var pts_lbl := Label.new()
	pts_lbl.text = "Equipo %s suma %d puntos de la mesa  (%d + %d)" % [TEAM_NAMES[winner_team], pts, team_pips[0], team_pips[1]]
	pts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pts_lbl.add_theme_font_size_override("font_size", 20)
	pts_lbl.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	hand_result_content.add_child(pts_lbl)

	var score_lbl := Label.new()
	score_lbl.text = "Marcador: %s %d  —  %s %d      (meta: %d)" % [TEAM_NAMES[0], pub.team_score[0], TEAM_NAMES[1], pub.team_score[1], pub.target_score]
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.add_theme_font_size_override("font_size", 15)
	hand_result_content.add_child(score_lbl)

	hand_result_overlay.visible = true


func _make_team_summary(team: int, total: int, header: String, notes: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var head := Label.new()
	head.text = header
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	box.add_child(head)

	for s in range(4):
		if _team_of(s) == team:
			box.add_child(_make_seat_summary_row(s, notes.get(s, "")))

	var total_lbl := Label.new()
	total_lbl.text = "Total del equipo: %d" % total
	total_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total_lbl.add_theme_font_size_override("font_size", 15)
	box.add_child(total_lbl)

	return box


func _make_seat_summary_row(seat: int, note: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_lbl := Label.new()
	if note.is_empty():
		name_lbl.text = "%s:" % SEAT_NAMES[seat]
	else:
		name_lbl.text = "%s (%s):" % [SEAT_NAMES[seat], note]
	name_lbl.custom_minimum_size = Vector2(112, 0)
	name_lbl.add_theme_font_size_override("font_size", 14)
	if not note.is_empty():
		name_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	row.add_child(name_lbl)

	var tiles_box := HBoxContainer.new()
	tiles_box.add_theme_constant_override("separation", 4)
	tiles_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tiles_box)

	var total := 0
	for t in reveal.hands[seat]:
		var tex := TextureRect.new()
		tex.texture = load(t.texture())
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(30, 60)
		tiles_box.add_child(tex)
		total += t.pips()

	if reveal.hands[seat].is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "se pegó (sin fichas)"
		none_lbl.add_theme_font_size_override("font_size", 13)
		tiles_box.add_child(none_lbl)

	var total_lbl := Label.new()
	total_lbl.text = "= %d" % total
	total_lbl.custom_minimum_size = Vector2(48, 0)
	total_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total_lbl.add_theme_font_size_override("font_size", 14)
	row.add_child(total_lbl)

	return row


func _on_hand_result_continue() -> void:
	if pending_winner_team < 0:
		return
	pending_winner_team = -1
	hand_result_overlay.visible = false
	# Si alguna pareja llegó a la meta lo decide la autoridad, no la pantalla: acá
	# solo se pide seguir, y lo que vuelve es una mano nueva o el fin de la partida.
	transport.request_continue()


# ===========================================================================
# Interacción del jugador humano
# ===========================================================================
func _on_hand_tile_pressed(idx: int) -> void:
	if phase != Phase.PLAYING or pub.current_player != local_seat:
		return

	# Con la elección de punta abierta no se toca otra ficha: hay que contestarla o
	# cancelarla. El popup está más arriba en la pantalla y NO tapa la mano, así que sin
	# esto se podía jugar otra ficha por debajo y dejar la elección vieja viva — y
	# contestarla después llegaba como una jugada fuera de turno.
	if pending_hand_idx >= 0:
		return
	# Con una jugada en vuelo tampoco: mandar otra sería una jugada duplicada.
	if awaiting_play:
		return

	var moves: Array = mine.legal_moves
	var chosen: Variant = null
	for m in moves:
		if m.idx == idx:
			chosen = m
			break
	if chosen == null:
		return
	if pub.board.is_empty() or chosen.ends.size() == 1:
		var e: String = chosen.ends[0]
		_send_play(idx, e)
	else:
		_show_end_choice_popup(idx)


func _show_end_choice_popup(idx: int) -> void:
	pending_hand_idx = idx
	var left_btn: Button = end_choice_popup.find_child("LeftBtn", true, false)
	var right_btn: Button = end_choice_popup.find_child("RightBtn", true, false)
	left_btn.text = "Izquierda (%d)" % pub.left_end
	right_btn.text = "Derecha (%d)" % pub.right_end
	end_choice_popup.visible = true
	# Se redibuja la mano para que las fichas queden apagadas: así el bloqueo se ve, en
	# vez de que el clic simplemente no haga nada.
	_render_own_hand()


func _on_end_choice(end: String) -> void:
	if pending_hand_idx < 0:
		_cancel_end_choice()
		return
	var idx: int = pending_hand_idx
	_cancel_end_choice()
	_send_play(idx, end)


## Cierra la elección de punta y olvida la ficha pendiente.
func _cancel_end_choice() -> void:
	pending_hand_idx = -1
	end_choice_popup.visible = false
	_render_own_hand()


## El popup solo tiene sentido mientras sea tu turno, así que se cierra solo en cuanto
## deja de serlo. Sin esto quedaba abierto encima de la mesa (no la tapa: tu mano está
## más abajo y se puede tocar igual), y contestarlo después mandaba una jugada fuera de
## turno. En red va a pasar más seguido, porque la mesa puede avanzar mientras lo estás
## mirando.
func _sync_end_choice() -> void:
	if pending_hand_idx < 0:
		return
	if phase != Phase.PLAYING or pub.current_player != local_seat:
		_cancel_end_choice()


# ===========================================================================
# Renderizado
# ===========================================================================
# Las parejas son los puestos enfrentados. No hace falta importar las reglas para
# saberlo: es lo mismo que ya dicen TEAM_NAMES ("Sur-Norte" son los pares,
# "Este-Oeste" los impares) y lo mismo que se ve en la mesa, donde tu pareja queda
# siempre al frente.
func _team_of(seat: int) -> int:
	return seat % 2


func _render_all() -> void:
	_sync_end_choice()
	_render_board()
	_render_own_hand()
	_render_side_stacks()
	_render_top_backs()
	_update_top_bar()
	_update_pass_status()
	_update_turn_dots()
	own_title.text = "Tu mano (%s)%s" % [SEAT_NAMES[local_seat], _lead_mark(local_seat)]


# La ficha inicial (el burro) queda siempre exactamente en el centro del tablero y
# nunca se mueve. Cada lado de la hilera crece desde ahí en fila; al llegar a
# ROW_LENGTH fichas seguidas, dobla 90° UNA sola vez y desde ahí sigue derecho en el
# sentido contrario el resto de la mano (como en una mesa real cuando se acerca al
# borde). Primero se calcula todo el trazado a tamaño natural y, si no cabe, se
# encoge por igual alrededor del mismo centro — la hilera nunca se desplaza, solo
# se hace más chica.
func _render_board() -> void:
	for c in board_viewport.get_children():
		c.queue_free()

	if pub.board.is_empty() or pub.opening_tile_index < 0:
		return

	var anchor_tile: Domino = pub.board[pub.opening_tile_index]
	var right_chain: Array = pub.board.slice(pub.opening_tile_index + 1, pub.board.size())
	var left_chain: Array = []
	for i in range(pub.opening_tile_index - 1, -1, -1):
		left_chain.append(pub.board[i])

	# Solo en la primera mano sale forzosamente el 6-6; de la segunda en adelante la
	# ficha inicial puede ser cualquiera. Si es un doble va cruzada (angosta y alta);
	# si no, se acuesta como cualquier ficha de la fila, con su valor "a" mirando a la
	# izquierda y "b" a la derecha (así se fijan las puntas al abrir la mano).
	var anchor_is_double: bool = anchor_tile.is_double()
	var anchor_size: Vector2 = Vector2(64, 128) if anchor_is_double else Vector2(128, 64)
	var anchor_rot: float = 0.0 if anchor_is_double else _dir_angle(Vector2(-1, 0))
	var chain_start_x: float = anchor_size.x / 2.0

	var placements: Array = []
	placements.append({"domino": anchor_tile, "offset": Vector2.ZERO, "size": anchor_size, "rotation": anchor_rot})

	# Cada lado arranca calzando con la punta que la ficha inicial le expone: la
	# derecha con "b" y la izquierda con "a". El lado derecho dobla hacia arriba
	# (-Y); el izquierdo hacia abajo (+Y).
	for p in _layout_chain(right_chain, chain_start_x, 1.0, -1.0, anchor_tile.b):
		placements.append(p)
	for p in _layout_chain(left_chain, -chain_start_x, -1.0, 1.0, anchor_tile.a):
		placements.append(p)

	var min_x := 0.0
	var max_x := 0.0
	var min_y := 0.0
	var max_y := 0.0
	for p in placements:
		var half: Vector2 = p.size / 2.0
		var lo_x: float = p.offset.x - half.x
		var hi_x: float = p.offset.x + half.x
		var lo_y: float = p.offset.y - half.y
		var hi_y: float = p.offset.y + half.y
		if lo_x < min_x:
			min_x = lo_x
		if hi_x > max_x:
			max_x = hi_x
		if lo_y < min_y:
			min_y = lo_y
		if hi_y > max_y:
			max_y = hi_y

	var half_w: float = board_viewport.size.x / 2.0
	var half_h: float = board_viewport.size.y / 2.0
	var fit_scale := 1.0
	if max_x > 1.0 and half_w / max_x < fit_scale:
		fit_scale = half_w / max_x
	if -min_x > 1.0 and half_w / (-min_x) < fit_scale:
		fit_scale = half_w / (-min_x)
	if max_y > 1.0 and half_h / max_y < fit_scale:
		fit_scale = half_h / max_y
	if -min_y > 1.0 and half_h / (-min_y) < fit_scale:
		fit_scale = half_h / (-min_y)
	if fit_scale < 0.28:
		fit_scale = 0.28

	var anchor_screen: Vector2 = board_viewport.size / 2.0
	for p in placements:
		var rot: float = p.get("rotation", 0.0)
		_place_board_tile(p.domino, anchor_screen + p.offset * fit_scale, fit_scale, rot)


# Calcula toda la fila de un lado de la hilera (derecho o izquierdo). Avanza en línea
# recta hasta ROW_LENGTH fichas; luego dobla en "turn_dir_y" (fija para ese lado).
# Si justo después de doblar sigue un doble, ese doble también se queda en la misma
# columna vertical (se sigue derecho); la fila horizontal solo se retoma con la
# primera ficha normal que aparezca.
#
# Los dobles SIEMPRE se dibujan en su orientación natural (angosta y alta, sin
# girar): eso los hace cruzar una fila horizontal (como cualquier doble en la
# mesa), y en el tramo vertical del giro los deja alineados con él en vez de
# acostados — que es justo lo que se ve en una mesa real.
#
# La esquina queda en "L" limpia: la ficha que dobla cae exactamente sobre la última
# mitad de la ficha anterior (mismo ancho, borde compartido completo), y la fila que
# se retoma arranca con su mitad conectora justo debajo de esa ficha que dobló.
func _layout_chain(chain: Array, start_x: float, x_sign_init: float, turn_dir_y: float, connect_init: int) -> Array:
	var result: Array = []
	var x_pos: float = start_x
	var y_level: float = 0.0
	var row_y: float = 0.0
	var x_sign: float = x_sign_init
	var count_in_row: int = 0
	var connect_value: int = connect_init
	var turning: bool = false
	var has_turned: bool = false
	var turn_col_x: float = 0.0
	var pending_row_start: bool = false

	for t in chain:
		var outward_value: int = t.other(connect_value)

		# Cada lado dobla como máximo UNA vez en toda la partida; después sigue
		# derecho el resto de la hilera, no importa cuánto crezca.
		var entering_turn: bool = not turning and not has_turned and count_in_row >= ROW_LENGTH
		if entering_turn:
			turning = true

		var direction: Vector2 = Vector2(x_sign, 0.0) if not turning else Vector2(0.0, turn_dir_y)

		var along: float
		var perp: float
		if t.is_double():
			along = 64.0 if direction.x != 0.0 else 128.0
			perp = 128.0 if direction.x != 0.0 else 64.0
		else:
			along = 128.0
			perp = 64.0

		# La ficha que dobla se coloca justo DEBAJO (o encima) de la última mitad de
		# la ficha anterior: se corre media ficha hacia ATRÁS respecto al borde donde
		# iba la fila, de modo que su ancho completo calce con esa mitad y compartan
		# un borde entero. Al retomar la fila pasa lo mismo, un cuarto de vuelta más
		# allá: la mitad que conecta queda pegada al ancho de la ficha que dobló.
		if entering_turn:
			turn_col_x = x_pos - x_sign * (perp / 2.0)
		if pending_row_start:
			row_y = y_level + turn_dir_y * (perp / 2.0)
			pending_row_start = false

		var center: Vector2
		var slot_size: Vector2
		if not turning:
			center = Vector2(x_pos + x_sign * (along / 2.0), row_y)
			slot_size = Vector2(along, perp)
			x_pos += x_sign * along
			count_in_row += 1
			# Guarda el borde real de ESTA ficha (no la línea central de la fila) para
			# que, si la siguiente ficha dobla, arranque pegada aquí y no se solape ni
			# deje un hueco — el grosor cambia si esta ficha es un doble.
			y_level = row_y + turn_dir_y * (perp / 2.0)
		else:
			center = Vector2(turn_col_x, y_level + turn_dir_y * (along / 2.0))
			slot_size = Vector2(perp, along)
			y_level += turn_dir_y * along
			if not t.is_double():
				x_sign = -x_sign
				count_in_row = 0
				turning = false
				has_turned = true
				pending_row_start = true

		# La textura siempre trae el valor mayor en la mitad de "arriba" (ángulo 0°) y
		# el menor en la de "abajo". Se gira la ficha (si no es doble) para que la
		# mitad con el valor que debe quedar hacia afuera apunte en "direction".
		var angle: float
		if t.is_double():
			angle = 0.0
		elif outward_value == t.b:
			angle = _dir_angle(-direction)
		else:
			angle = _dir_angle(direction)

		result.append({"domino": t, "offset": center, "size": slot_size, "rotation": angle})
		connect_value = outward_value

	return result


# Ángulo (0/90/180/270) que hay que girar la ficha para que su mitad "de arriba"
# (la del valor mayor, en su textura sin girar) termine apuntando hacia "dir".
func _dir_angle(dir: Vector2) -> float:
	if dir.x > 0.0:
		return 90.0
	if dir.x < 0.0:
		return 270.0
	if dir.y > 0.0:
		return 180.0
	return 0.0


func _place_board_tile(t: Domino, center: Vector2, tile_scale: float, rotation_deg: float) -> void:
	var natural: Vector2 = Vector2(64, 128) * tile_scale
	var tex := TextureRect.new()
	tex.texture = load(t.texture())
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.size = natural
	tex.pivot_offset = natural / 2.0
	tex.position = center - natural / 2.0
	tex.rotation_degrees = rotation_deg
	board_viewport.add_child(tex)


func _render_own_hand() -> void:
	for c in own_hand_row.get_children():
		c.queue_free()

	var legal_by_idx := {}
	# Con la elección de punta abierta la mano queda apagada: la decisión pendiente es
	# esa, y se ve que no se puede tocar otra ficha en vez de que el clic no haga nada.
	if phase == Phase.PLAYING and pub.current_player == local_seat and pending_hand_idx < 0 and not awaiting_play:
		for m in mine.legal_moves:
			legal_by_idx[m.idx] = true

	for i in range(mine.tiles.size()):
		var t: Domino = mine.tiles[i]
		var btn := TextureButton.new()
		btn.texture_normal = load(t.texture())
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = Vector2(64, 128)
		var is_legal: bool = legal_by_idx.has(i)
		btn.disabled = not is_legal
		btn.modulate = Color(1, 1, 1, 1) if is_legal else Color(0.5, 0.5, 0.5, 1)
		var idx_capture := i
		btn.pressed.connect(func(): _on_hand_tile_pressed(idx_capture))
		own_hand_row.add_child(btn)


# Las tres manos de la IA usan fichas del mismo tamaño (44x88, la misma proporción
# 1:2 de una ficha real): de pie para Norte, acostadas para los laterales, según
# cómo las sostendría cada jugador desde su puesto.
func _render_top_backs() -> void:
	var seat: int = _seat_at(POS_TOP)
	top_title.text = _rival_label(seat, false)
	for c in top_row.get_children():
		c.queue_free()
	for i in range(pub.hand_counts[seat]):
		top_row.add_child(_make_tile_back(44, 88))


func _render_side_stacks() -> void:
	var left_seat: int = _seat_at(POS_LEFT)
	left_title.text = _rival_label(left_seat, true)
	for c in left_stack.get_children():
		c.queue_free()
	for i in range(pub.hand_counts[left_seat]):
		left_stack.add_child(_make_tile_back(88, 44))

	var right_seat: int = _seat_at(POS_RIGHT)
	right_title.text = _rival_label(right_seat, true)
	for c in right_stack.get_children():
		c.queue_free()
	for i in range(pub.hand_counts[right_seat]):
		right_stack.add_child(_make_tile_back(88, 44))


func _update_top_bar() -> void:
	lbl_target.text = "Meta: %d" % pub.target_score
	lbl_score0.text = "Sur-Norte: %d" % pub.team_score[0]
	lbl_score1.text = "Este-Oeste: %d" % pub.team_score[1]
	if phase == Phase.PLAYING:
		var who: String = "Tú"
		if pub.current_player != local_seat:
			who = _owner_name(pub.current_player)
		lbl_turn.text = "Turno: %s (%s)" % [SEAT_NAMES[pub.current_player], who]
	else:
		lbl_turn.text = ""

	if pub.board.is_empty():
		lbl_ends.text = "Mesa vacía — se espera la ficha inicial"
	else:
		lbl_ends.text = "Puntas abiertas: %d  —  %d" % [pub.left_end, pub.right_end]


# El pase es automático (lo aplica la autoridad) para que el juego nunca se quede
# esperando un clic que no llega; esto solo informa el estado del turno.
func _update_pass_status() -> void:
	if phase != Phase.PLAYING or pub.current_player != local_seat:
		pass_status.text = ""
	elif mine.legal_moves.is_empty():
		pass_status.text = "Sin fichas jugables: pasando…"
	else:
		pass_status.text = "Tienes ficha jugable: debes jugarla"


func _log(msg: String) -> void:
	log_rt.append_text(msg + "\n")


# Los motivos de rechazo vienen como clave, no como texto: el idioma se resuelve acá,
# igual que con el resto de los eventos.
func _rejection_text(reason: String) -> String:
	match reason:
		"no_es_su_turno":
			return "Ya no es tu turno"
		"ficha_no_jugable":
			return "Esa ficha no calza en la mesa"
		"punta_invalida":
			return "Esa ficha no va en esa punta"
		"mano_terminada":
			return "La mano ya terminó"
		"tiene_jugada":
			return "Tienes ficha jugable: debes jugarla"
	return "Esa jugada no se pudo aplicar"


## Manda la jugada y apaga la mano hasta que el servidor conteste. El bloqueo se pone
## ANTES de mandar y no después, porque jugando en local la respuesta llega dentro de la
## misma llamada: puesto después, quedaría encendido para siempre.
func _send_play(idx: int, end: String) -> void:
	awaiting_play = true
	_render_own_hand()
	transport.request_play(idx, end)


## Quién ocupa un puesto ajeno: su nombre, o "IA" si la silla la juega la máquina.
## Jugando en local son todas de la máquina; en red hay que decir el nombre, porque
## etiquetar de "IA" al amigo que tienes enfrente es mentirle al jugador.
func _owner_name(seat: int) -> String:
	if seat < 0 or seat >= seat_owners.size():
		return "IA"
	var owner: String = str(seat_owners[seat])
	if owner.is_empty():
		return "IA"
	return owner


## Lo mismo, con la marca que lleva junto al nombre del puesto en los paneles.
func _owner_label(seat: int) -> String:
	if seat < 0 or seat >= seat_owners.size():
		return "(IA)"
	if str(seat_owners[seat]).is_empty():
		return "(IA)"
	return "· %s" % str(seat_owners[seat])
