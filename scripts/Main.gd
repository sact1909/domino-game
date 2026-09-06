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


# ---------------------------------------------------------------------------
# Reparto de la pantalla
# ---------------------------------------------------------------------------
# Todo el juego se dibuja sobre un lienzo fijo de 1920x1080 y Godot lo escala a la
# ventana, así que estas medidas son las mismas en cualquier monitor.
const SCREEN_SIZE := Vector2(1920, 1080)

## Ficha en mano. Es la MISMA para los cuatro puestos: antes la propia era de 128 y las de
## los demás de 88, y la mesa se veía desigual sin motivo — las cuatro manos son lo mismo
## vistas desde sitios distintos.
##
## Cuánto ocupa depende del puesto: la propia y la de enfrente van de pie (64 de ancho por
## 128 de alto) y las de los lados acostadas (128 por 64).
const HAND_TILE_LONG := 128.0
const HAND_TILE_SHORT := 64.0
const HAND_TILE_GAP := 8

## La franja de datos de arriba se quitó: se llevaba 48 px de alto a lo ancho de toda la
## ventana para cinco datos cortos, y ese alto es justo lo que decide si la ficha de la
## mesa cabe. Ahora cada dato está donde se necesita — el marcador junto a la mano de cada
## jugador, y la meta y las puntas en la esquina, fuera del paso.
const TOP_PANEL_POS := Vector2(610, 10)
const TOP_PANEL_SIZE := Vector2(700, 154)
const BOARD_POS := Vector2(178, 170)
const BOARD_SIZE := Vector2(1564, 712)
const OWN_PANEL_POS := Vector2(460, 886)
const OWN_PANEL_SIZE := Vector2(1000, 194)
const LOG_PANEL_POS := Vector2(14, 886)
const LOG_PANEL_SIZE := Vector2(300, 186)
const TOAST_POS := Vector2(710, 826)
const TOAST_SIZE := Vector2(500, 44)

## Meta y puntas abiertas, arrinconadas arriba a la derecha. Van sobre el fondo y no en
## una franja porque no compiten con nada: esa esquina queda encima del tablero pero por
## fuera de él, así que no le quita sitio a la hilera ni a ninguna mano.
const INFO_SIZE := Vector2(232, 76)
const INFO_POS := Vector2(SCREEN_SIZE.x - INFO_SIZE.x - 16.0, 12.0)

## Marcador de cada pareja, pegado a la mano de cada jugador: el mismo número aparece
## junto a los dos que forman la pareja, que es como se lleva la cuenta en una mesa de
## verdad. Va enganchado a la fila de fichas, no al panel, para que quede siempre junto a
## la ficha del extremo aunque la mano se vaya acortando.
const SCORE_BADGE_SIZE := Vector2(66, 42)
const SCORE_BADGE_GAP := 14

# Medidas de los dos puestos laterales. El canal donde va el nombre girado sale de
# restarle a la ventana el panel y las fichas, así que todo se calcula de acá.
const SIDE_PANEL_SIZE := Vector2(140, 712)
const SIDE_TILE_SIZE := Vector2(HAND_TILE_LONG, HAND_TILE_SHORT)
const SIDE_LEFT_POS := Vector2(34, 170)
const SIDE_RIGHT_POS := Vector2(1746, 170)
const SIDE_TITLE_GAP := 7.0
const SIDE_DOT_SIZE := 16.0

## Largo fijo de una ficha en la mesa. Es LO QUE NO CAMBIA: la hilera crece, se pliega, y
## la ficha se queda igual en vez de encogerse conforme avanza la mano.
##
## El número sale de medir cuánto encoge DE VERDAD, no de elegirlo a ojo. Con el tablero
## de 1564x712 —el de ahora, sin la franja de datos arriba— en 400 manos:
##
##   largo pedido    lo que se ve
##       105         105 siempre
##       110         110 siempre
##       115         115 en el 98.1 %, 110 en el resto
##       120         120 en el 94.2 %, 119 o 110 en el resto
##
## 110 es el más grande que nunca encoge, y se confirmó en otras 1500 manos con distinta
## semilla. Con el tablero anterior, 38 px más bajo, 110 se recortaba en el 2.5 % de los
## estados; los 38 px que dejó libres la franja de datos son justo los que lo permiten.
##
## La red de seguridad se queda puesta igual: 1900 manos son muchas pero no son todas, y
## si algún día apareciera un trazado más largo es mejor verlo un poco más chico un
## momento que perder de vista media mesa y no poder tocar una punta.
const BOARD_TILE_LENGTH := 110.0

## Cuánto dura y cuánto recorre la entrada de una ficha. Corta y bien por debajo de la
## pausa entre turnos (0.9 s en local, 0.6 s en el servidor) para que siempre termine
## antes de que la mesa se vuelva a dibujar.
const PLAY_ANIM_TIME := 0.28
const PLAY_ANIM_TRAVEL := 150.0
const BOARD_TILE_SCALE := BOARD_TILE_LENGTH / 128.0

## Hasta dónde puede llegar la hilera a cada lado antes de doblar, en unidades naturales.
## La ficha inicial está clavada en el centro, así que a cada lado le toca media mesa.
const BOARD_REACH_X := (BOARD_SIZE.x / 2.0) / BOARD_TILE_SCALE

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
var lbl_ends: Label

# Marcador de cada pareja y nombre de cada puesto, indexados por LUGAR EN LA PANTALLA
# igual que las bolitas de turno: en la pantalla de cada quien su propia mano va abajo,
# así que el puesto no dice dónde se dibuja.
var score_labels: Array = [null, null, null, null]
var score_badges: Array = [null, null, null, null]
var seat_titles: Array = [null, null, null, null]

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

# Elección de punta: la ficha elegida, las puntas donde puede ir, las marcas encendidas
# sobre la mesa y dónde quedó en pantalla la ficha de cada punta.
var pending_ends: Array = []
var end_highlights: Array = []
var end_slots: Dictionary = {}

# Ficha recién jugada, para animar su llegada. El evento dice QUIÉN jugó; de qué lado
# entró se deduce comparando la mesa con la que se dibujó la vez anterior.
var pending_arrival: Dictionary = {}
var last_board_count: int = 0
var last_opening_index: int = -1
var cancel_choice_button: Button
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
	_build_info_corner()
	_build_top_panel()
	_build_own_panel()
	_build_left_panel()
	_build_right_panel()
	_build_board_area()
	_build_log_panel()
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
	bg.size = SCREEN_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


## Meta y puntas abiertas, en la esquina de arriba a la derecha.
##
## Son los dos datos que no pertenecen a ningún jugador: la meta no cambia en toda la
## partida y las puntas son de la mesa. Por eso van juntos y apartados, en el único sitio
## de la ventana donde no le quitan espacio a nadie — encima del tablero, sí, pero fuera
## del rectángulo por donde puede crecer la hilera.
func _build_info_corner() -> void:
	var box := VBoxContainer.new()
	box.position = INFO_POS
	box.size = INFO_SIZE
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	lbl_target = Label.new()
	lbl_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_target.add_theme_font_size_override("font_size", 15)
	lbl_target.add_theme_color_override("font_color", Color(0.72, 0.82, 0.72))
	box.add_child(lbl_target)

	# Las puntas se leen a cada jugada y deciden qué ficha se puede poner, así que van
	# más grandes y más claras que la meta, que se mira una vez y ya.
	lbl_ends = Label.new()
	lbl_ends.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_ends.add_theme_font_size_override("font_size", 22)
	lbl_ends.add_theme_color_override("font_color", Color(1, 0.95, 0.82))
	box.add_child(lbl_ends)


func _build_top_panel() -> void:
	var panel := VBoxContainer.new()
	panel.position = TOP_PANEL_POS
	panel.size = TOP_PANEL_SIZE
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
	seat_titles[POS_TOP] = top_title

	# El marcador va en la MISMA fila que las fichas, y no suelto en el panel, para que
	# quede pegado a la ficha del extremo aunque la mano se acorte. La fila de fichas se
	# vacía y se rehace en cada dibujado, así que el marcador cuelga de esta envoltura,
	# que no se toca.
	var row_wrap := HBoxContainer.new()
	row_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	row_wrap.add_theme_constant_override("separation", SCORE_BADGE_GAP)
	panel.add_child(row_wrap)

	row_wrap.add_child(_make_score_badge(POS_TOP))

	top_row = HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_theme_constant_override("separation", HAND_TILE_GAP)
	row_wrap.add_child(top_row)
	row_wrap.add_child(_make_badge_spacer())


func _build_own_panel() -> void:
	var panel := VBoxContainer.new()
	panel.position = OWN_PANEL_POS
	panel.size = OWN_PANEL_SIZE
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
	seat_titles[POS_BOTTOM] = own_title

	# Igual que en Norte, pero el marcador va DESPUÉS de las fichas: en el puesto de abajo
	# el extremo libre queda a la derecha.
	var row_wrap := HBoxContainer.new()
	row_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	row_wrap.add_theme_constant_override("separation", SCORE_BADGE_GAP)
	panel.add_child(row_wrap)

	row_wrap.add_child(_make_badge_spacer())

	own_hand_row = HBoxContainer.new()
	own_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	own_hand_row.add_theme_constant_override("separation", HAND_TILE_GAP)
	row_wrap.add_child(own_hand_row)

	row_wrap.add_child(_make_score_badge(POS_BOTTOM))

	var status_row := HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 12)
	panel.add_child(status_row)

	# Solo informa el estado del turno (el pase es automático), así que es una
	# etiqueta y no un botón deshabilitado.
	pass_status = Label.new()
	pass_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pass_status.add_theme_font_size_override("font_size", 14)
	pass_status.add_theme_color_override("font_color", Color(0.85, 0.88, 0.85))
	status_row.add_child(pass_status)

	# Salida sin jugar, al lado del estado y no en un cartel aparte: solo aparece cuando
	# hay una ficha elegida, y hace falta porque mientras tanto la mano queda bloqueada.
	cancel_choice_button = Button.new()
	cancel_choice_button.text = "No jugar"
	cancel_choice_button.visible = false
	cancel_choice_button.pressed.connect(_cancel_end_choice)
	status_row.add_child(cancel_choice_button)


# En los laterales la etiqueta va DEBAJO de la pila de fichas, siguiendo la columna,
# para que se lea junto a las fichas de ese jugador y no arriba, despegada de ellas.
# Los dos puestos de los lados se arman igual: la columna de fichas centrada en el panel,
# y el nombre GIRADO 90° en el canal que queda entre las fichas y el borde de la ventana.
#
# El nombre va girado para acompañar a las fichas, que también lo están, y va en el canal
# porque es el hueco libre que le corresponde a ese puesto — el equivalente de la franja
# que usa Norte encima de las suyas. Debajo de la columna quedaba a media pantalla, lejos
# de las fichas que nombra.
#
# Un control girado no se lleva bien con los contenedores: el contenedor lo coloca por su
# rectángulo SIN girar y el resultado no tiene nada que ver con lo que se ve. Por eso el
# nombre y su bolita van colocados a mano, y solo las fichas quedan en el contenedor.
func _build_left_panel() -> void:
	left_stack = _build_side_panel(SIDE_LEFT_POS, POS_LEFT, true, func(lbl: Label): left_title = lbl)


func _build_right_panel() -> void:
	right_stack = _build_side_panel(SIDE_RIGHT_POS, POS_RIGHT, false, func(lbl: Label): right_title = lbl)


func _build_side_panel(at: Vector2, screen_pos: int, toward_left_edge: bool, keep_title: Callable) -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.position = at
	panel.size = SIDE_PANEL_SIZE
	panel.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(panel)

	# El centrador se queda con TODO el alto del panel, y dentro la columna queda en el
	# medio sin importar cuántas fichas le falten. Sin esto colgaban del borde de arriba y
	# se acortaban hacia abajo, mientras la columna de enfrente sí se mantenía centrada.
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(center)

	# La columna y su marcador viajan juntos, y el conjunto es lo que queda centrado. El
	# marcador va en el extremo CONTRARIO a la bolita de turno de ese lado: arriba en el
	# izquierdo, abajo en el derecho, así no se amontonan en la misma esquina.
	var column_wrap := VBoxContainer.new()
	column_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	column_wrap.add_theme_constant_override("separation", SCORE_BADGE_GAP)
	center.add_child(column_wrap)

	# El marcador se compensa con un hueco del mismo tamaño en el extremo contrario, para
	# que la fila de fichas siga centrada donde estaba: sin el hueco, la mano entera se
	# corre hacia un lado y las cuatro dejan de estar enfrentadas.
	if toward_left_edge:
		column_wrap.add_child(_make_score_badge(screen_pos))
	else:
		column_wrap.add_child(_make_badge_spacer())

	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", HAND_TILE_GAP)
	column_wrap.add_child(stack)

	if toward_left_edge:
		column_wrap.add_child(_make_badge_spacer())
	else:
		column_wrap.add_child(_make_score_badge(screen_pos))

	_build_side_title(screen_pos, toward_left_edge, keep_title)
	return stack


## Crea el nombre girado y su bolita. Colocarlos es otra cosa: depende de lo que mida el
## texto, y eso solo se sabe cuando hay texto. Lo hace _layout_side_title() en cada
## dibujado.
func _build_side_title(screen_pos: int, toward_left_edge: bool, keep_title: Callable) -> void:
	var dot: Panel = _make_turn_dot()
	add_child(dot)
	turn_dots[screen_pos] = dot

	var title := Label.new()
	# Sin envoltorio de línea: al girar, el ANCHO de la etiqueta pasa a ocupar alto —donde
	# sobra sitio— y su ALTO pasa a ocupar el canal, que es lo escaso. Una segunda línea se
	# comería el canal; un texto largo, en cambio, solo crece hacia donde hay espacio.
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.rotation_degrees = -90.0 if toward_left_edge else 90.0
	add_child(title)
	seat_titles[screen_pos] = title
	keep_title.call(title)


## El marcador de la pareja de un puesto: el número grande y, al pasar el ratón, de qué
## pareja es. Los dos jugadores de una misma pareja enseñan el MISMO número, uno a cada
## lado de la mesa, que es como se canta la puntuación jugando en vivo.
##
## El color separa a las dos parejas de un vistazo: cálido el equipo de quien mira esta
## pantalla, frío el contrario. Así se ve quién va con quién sin leer ningún nombre.
func _make_score_badge(screen_pos: int) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = SCORE_BADGE_SIZE
	# Dentro de una fila o una columna, un contenedor se estira a lo ancho de la caja que
	# le toca; encogido y centrado se queda del tamaño pedido, junto a las fichas.
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	badge.add_child(label)

	score_badges[screen_pos] = badge
	score_labels[screen_pos] = label
	return badge


## Un hueco del tamaño del marcador para el otro extremo de la mano. Es lo que mantiene
## las fichas centradas donde estaban antes de que el marcador existiera.
func _make_badge_spacer() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = SCORE_BADGE_SIZE
	gap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	gap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


## Coloca el nombre girado y su bolita, con la caja ajustada a lo que mide el texto.
##
## Ajustarla importa: con una caja fija más ancha que el texto, pegar el texto a un borde
## dejaba un nombre arriba y el otro abajo —porque los lados leen en sentidos opuestos— y
## centrarlo lo alejaba de la bolita. Con la caja a medida se puede centrar el NOMBRE en
## los dos lados y dejar la bolita pegada a él.
func _layout_side_title(title: Label, dot: Panel, at: Vector2, toward_left_edge: bool) -> void:
	# La caja se ajusta al texto en las dos dimensiones. Un alto fijo dejaba aire arriba y
	# abajo que, al girar, se convertía en hueco contra el borde y contra las fichas.
	var natural: Vector2 = title.get_minimum_size()
	var text_length: float = natural.x
	title.size = natural
	# Se gira alrededor de su propio centro: así basta con colocar ese centro donde se
	# quiere y el giro no lo desplaza.
	title.pivot_offset = title.size / 2.0

	var tiles_left: float = at.x + (SIDE_PANEL_SIZE.x - SIDE_TILE_SIZE.x) / 2.0
	var lane_x: float = tiles_left / 2.0
	if not toward_left_edge:
		lane_x = (tiles_left + SIDE_TILE_SIZE.x + SCREEN_SIZE.x) / 2.0

	# El nombre va centrado en el alto del panel en los dos lados, para que se vean a la
	# misma altura. La bolita se pega justo antes de donde EMPIEZA el texto según el
	# sentido de lectura de ese lado: abajo en el izquierdo, arriba en el derecho.
	var middle_y: float = at.y + SIDE_PANEL_SIZE.y / 2.0
	var dot_offset: float = text_length / 2.0 + SIDE_TITLE_GAP + SIDE_DOT_SIZE / 2.0
	var dot_y: float = middle_y + dot_offset if toward_left_edge else middle_y - dot_offset

	title.position = Vector2(lane_x, middle_y) - title.size / 2.0
	dot.position = Vector2(lane_x - SIDE_DOT_SIZE / 2.0, dot_y - SIDE_DOT_SIZE / 2.0)


func _build_board_area() -> void:
	board_viewport = Control.new()
	board_viewport.position = BOARD_POS
	board_viewport.size = BOARD_SIZE
	board_viewport.clip_contents = true
	add_child(board_viewport)


func _build_log_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = LOG_PANEL_POS
	panel.size = LOG_PANEL_SIZE
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


## Enciende o apaga las sombras de las dos puntas de la mesa.
##
## Antes esto era un cartel preguntando "¿izquierda o derecha?". La sombra es más directa:
## enseña EL HUECO donde va a caer la ficha, con su tamaño y su orientación de verdad, así
## que no hay nada que traducir de una palabra a un sitio.
##
## Van sin la imagen de la ficha a propósito: lo que se está eligiendo es un sitio, no una
## ficha, y dibujar una que todavía no está jugada confundiría con las que sí lo están.
func _sync_end_highlights() -> void:
	for node in end_highlights:
		if is_instance_valid(node):
			# Se saca del árbol antes de liberarlo: queue_free() tarda hasta el final del
			# cuadro y mientras tanto la sombra vieja se seguiría viendo.
			board_viewport.remove_child(node)
			node.queue_free()
	end_highlights = []

	if pending_hand_idx < 0 or pending_hand_idx >= mine.tiles.size():
		return

	# El hueco depende de la ficha elegida: un doble se acuesta cruzado y ocupa otro sitio
	# y otro tamaño. Enseñar el de una ficha normal cuando vas a jugar un doble sería
	# mentirle al jugador sobre dónde va a caer.
	var chosen: Domino = mine.tiles[pending_hand_idx]
	var shape: String = "double" if chosen.is_double() else "plain"

	for end in pending_ends:
		var key: String = str(end)
		if not end_slots.has(key):
			continue
		var rect: Rect2 = (end_slots[key] as Dictionary)[shape]
		var shadow := Button.new()
		shadow.position = rect.position
		shadow.size = rect.size
		shadow.tooltip_text = "Jugar por la izquierda" if key == "L" else "Jugar por la derecha"
		shadow.pressed.connect(func(): _on_end_choice(key))
		_apply_shadow_style(shadow)
		board_viewport.add_child(shadow)
		end_highlights.append(shadow)


## La sombra: oscura y translúcida, con un borde claro que la separa del fondo de la mesa.
## Al pasar por encima se aclara, para que se note que es lo que hay que tocar.
func _apply_shadow_style(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		var lit: bool = state == "hover" or state == "pressed"
		sb.bg_color = Color(0.05, 0.10, 0.06, 0.62 if lit else 0.42)
		sb.border_color = Color(1, 0.94, 0.55, 0.95 if lit else 0.6)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(6)
		button.add_theme_stylebox_override(state, sb)


func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.position = TOAST_POS
	toast_panel.size = TOAST_SIZE
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


## Bolita de turno. Tiene que quedar CUADRADA para que el redondeo la haga un círculo:
## dentro de un HBoxContainer los hijos se estiran al alto de la fila, y con una etiqueta
## de dos líneas quedaba de 16x36 — una pastilla, no un círculo. SHRINK_CENTER la deja en
## su tamaño y la centra verticalmente junto al texto.
func _make_turn_dot() -> Panel:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(SIDE_DOT_SIZE, SIDE_DOT_SIZE)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
		var lit: bool = phase == Phase.PLAYING and pos == active_pos

		var dot: Panel = turn_dots[pos]
		if dot != null:
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(8)
			sb.bg_color = Color(1, 0.85, 0.25) if lit else Color(0.25, 0.32, 0.26)
			dot.add_theme_stylebox_override("panel", sb)

		# El nombre del que juega se enciende con la bolita. Antes el turno se leía en la
		# franja de arriba; sin ella, hace falta que se vea desde el puesto mismo, y con
		# dos señales juntas —bolita y nombre— se ve desde donde se está mirando de quién es
		# el turno sin tener que ir a buscar un punto de 16 px.
		var title: Label = seat_titles[pos]
		if title != null:
			if lit:
				title.add_theme_color_override("font_color", Color(1, 0.85, 0.25))
			else:
				title.remove_theme_color_override("font_color")


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
	return "%s%s%s%d fichas%s" % [
		_seat_title(seat), partner, separator, pub.hand_counts[seat], _lead_mark(seat),
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
	hand_result_overlay.size = SCREEN_SIZE
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
	game_over_overlay.size = SCREEN_SIZE
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
	start_overlay.size = SCREEN_SIZE
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
		_log("Se reparten las fichas (7 por jugador, sin pozo). [b]%s[/b] tiene el 6-6 (el burro) y sale." % _seat_label(pub.current_player))
	else:
		_log("Nueva mano. Sale %s." % _seat_label(pub.current_player))
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
	game_over_label.text = "¡Equipo %s gana la partida!\nPuntaje final: %d - %d" % [_team_label(winner_team), pub.team_score[0], pub.team_score[1]]
	_configure_end_buttons()
	game_over_overlay.visible = true
	_log("[b]Fin de la partida. Gana el equipo %s (%d - %d).[/b]" % [_team_label(winner_team), pub.team_score[0], pub.team_score[1]])


# Traduce un evento a lo que se lee en pantalla. Acá vive el idioma; las reglas ya
# quedaron resueltas del otro lado.
func _handle_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"played":
			_log("%s jugó [b]%s[/b]." % [_seat_label(e.seat), str(e.tile)])
			# El evento llega ANTES del estado nuevo, así que cuando se dibuje la mesa ya
			# se sabe de quién es la ficha que acaba de aparecer.
			pending_arrival = {"seat": int(e.seat)}
		"passed":
			_log("%s pasa (no tiene fichas con %d ni %d)." % [_seat_label(e.seat), e.left_end, e.right_end])
			_show_toast("%s pasó" % _seat_label(e.seat))
		"bonus":
			var text: String = _bonus_text(e)
			_log("[b]+%d[/b] al equipo %s — %s." % [e.pts, _team_label(e.team), text])
			_show_toast("+%d  %s" % [e.pts, text])
		"opening_pass_cancelled":
			_log("Pase de salida anulado: %s (pareja de %s) tampoco pudo jugar." % [_seat_label(e.partner_seat), _seat_label(e.lead_seat)])
		"hand_won":
			_log("[b]%s[/b] colocó su última ficha. ¡Equipo %s gana la mano! (+%d puntos)" % [_seat_label(e.winner_seat), _team_label(e.winner_team), e.pts])
		"tranque":
			_log("¡Tranque! %s (%d) contra %s (%d): gana el equipo %s. (+%d puntos)" % [_seat_label(e.closer), e.closer_pips, _seat_label(e.challenger), e.challenger_pips, _team_label(e.winner_team), e.pts])
		"rejected":
			# El aviso al desarrollador se queda: jugando en local un rechazo solo puede
			# venir de un error de la interfaz. En red va a ser normal con latencia,
			# porque la mesa puede avanzar mientras el clic viaja.
			push_warning("Jugada rechazada de %s: %s" % [_seat_label(e.seat), e.reason])
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
			return "Pase seguido (%s hizo pasar a los otros tres)" % _seat_label(e.seat)
		"capicua":
			return "Capicúa (%s cerró con ficha que iba en las dos puntas)" % _seat_label(e.seat)
		"pase_salida":
			return "Pase de salida (%s hizo pasar a %s)" % [_seat_label(e.seat), _seat_label(e.other_seat)]
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
		var subtitle: String = "%s colocó su última ficha. Se cuentan todas las fichas que quedaron en la mesa, de las dos parejas." % _seat_label(e.winner_seat)
		if e.capicua:
			subtitle += " Cerró de capicúa: la ficha calzaba en las dos puntas."
		_show_hand_result(
			"¡Equipo %s gana la mano!" % _team_label(e.winner_team),
			subtitle,
			{},
			e.winner_team,
			e.totals,
			e.pts
		)
		return

	var tranque_subtitle: String
	if e.tie:
		tranque_subtitle = "%s trancó el juego. Empate con %s (%d - %d): gana la pareja que tiene la mano." % [_seat_label(e.closer), _seat_label(e.challenger), e.closer_pips, e.challenger_pips]
	else:
		tranque_subtitle = "%s trancó el juego. Se comparan sus fichas con las de %s, que seguía en el turno: %d contra %d, gana %s." % [_seat_label(e.closer), _seat_label(e.challenger), e.closer_pips, e.challenger_pips, _seat_label(e.winner_seat)]

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
		hand_result_content.add_child(_make_team_summary(team, team_pips[team], "Equipo %s" % _team_label(team), notes))

	if not pub.hand_bonuses.is_empty():
		var bonus_head := Label.new()
		bonus_head.text = "Bonificaciones de la mano"
		bonus_head.add_theme_font_size_override("font_size", 15)
		bonus_head.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
		hand_result_content.add_child(bonus_head)

		for b in pub.hand_bonuses:
			var b_lbl := Label.new()
			b_lbl.text = "+%d  %s  →  %s" % [b.pts, _bonus_text(b), _team_label(b.team)]
			b_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			b_lbl.custom_minimum_size = Vector2(520, 0)
			b_lbl.add_theme_font_size_override("font_size", 13)
			hand_result_content.add_child(b_lbl)

	var pts_lbl := Label.new()
	pts_lbl.text = "Equipo %s suma %d puntos de la mesa  (%d + %d)" % [_team_label(winner_team), pts, team_pips[0], team_pips[1]]
	pts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pts_lbl.add_theme_font_size_override("font_size", 20)
	pts_lbl.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	hand_result_content.add_child(pts_lbl)

	var score_lbl := Label.new()
	score_lbl.text = "Marcador: %s %d  —  %s %d      (meta: %d)" % [_team_label(0), pub.team_score[0], _team_label(1), pub.team_score[1], pub.target_score]
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
		name_lbl.text = "%s:" % _seat_label(seat)
	else:
		name_lbl.text = "%s (%s):" % [_seat_label(seat), note]
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
		_begin_end_choice(idx, chosen.ends)


## Deja la ficha elegida y enciende las marcas de las puntas donde puede ir. Todavía no se
## juega nada: se juega al tocar una de las dos.
func _begin_end_choice(idx: int, ends: Array) -> void:
	pending_hand_idx = idx
	pending_ends = ends
	_sync_end_highlights()
	cancel_choice_button.visible = true
	_update_pass_status()
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


## Apaga las marcas y olvida la ficha elegida.
func _cancel_end_choice() -> void:
	pending_hand_idx = -1
	pending_ends = []
	_sync_end_highlights()
	cancel_choice_button.visible = false
	_update_pass_status()
	_render_own_hand()


## La elección solo tiene sentido mientras sea tu turno, así que se cierra sola en cuanto
## deja de serlo. Sin esto quedarían las marcas encendidas sobre una mesa que ya avanzó, y
## tocarlas mandaría una jugada fuera de turno. En red va a pasar más seguido, porque la
## mesa puede avanzar mientras las estás mirando.
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
	_update_scoreboard()
	_update_pass_status()
	_update_turn_dots()
	own_title.text = "Tu mano (%s)%s" % [_seat_label(local_seat), _lead_mark(local_seat)]


# La ficha inicial (el burro) queda siempre exactamente en el centro del tablero y nunca
# se mueve. Cada lado de la hilera crece desde ahí en fila y, cuando a la siguiente ficha
# ya no le queda sitio, esa misma ficha dobla 90° y la fila sigue en sentido contrario —
# como en una mesa real cuando la cadena llega al borde. Puede doblar tantas veces como
# haga falta: la hilera se pliega en filas, igual que un texto que salta de renglón.
#
# Las fichas mantienen SIEMPRE el mismo tamaño (ver BOARD_TILE_LENGTH). Antes se calculaba
# el trazado a tamaño natural y se encogía para que cupiera, y eso las dejaba cada vez más
# chicas conforme avanzaba la mano; ahora es la hilera la que se pliega para caber.
func _render_board() -> void:
	# Las sombras cuelgan del mismo nodo que las fichas, así que se van con ellas. Se
	# olvida la lista para no intentar liberarlas dos veces al volver a encenderlas.
	end_highlights = []
	end_slots = {}
	for c in board_viewport.get_children():
		c.queue_free()

	if pub.board.is_empty() or pub.opening_tile_index < 0:
		# Mano nueva: se olvida lo anterior para no animar una ficha que no acaba de caer.
		pending_arrival = {}
		last_board_count = 0
		last_opening_index = -1
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

	var anchor_placement := {"domino": anchor_tile, "offset": Vector2.ZERO, "size": anchor_size, "rotation": anchor_rot}

	# Cada lado arranca calzando con la punta que la ficha inicial le expone: la
	# derecha con "b" y la izquierda con "a". El lado derecho dobla hacia arriba
	# (-Y); el izquierdo hacia abajo (+Y).
	var right_placed: Array = _layout_chain(right_chain, chain_start_x, 1.0, -1.0, anchor_tile.b)
	var left_placed: Array = _layout_chain(left_chain, -chain_start_x, -1.0, 1.0, anchor_tile.a)

	var placements: Array = [anchor_placement]
	placements.append_array(right_placed)
	placements.append_array(left_placed)

	# Cuál de todas es la que acaba de caer, para animar solo esa. Se deduce comparando
	# con la mesa anterior: si la ficha inicial se corrió un puesto en la lista es que la
	# nueva entró por la izquierda; si no, por la derecha.
	var arrival_index: int = -1
	var arrival_seat: int = -1
	if not pending_arrival.is_empty() and pub.board.size() == last_board_count + 1:
		arrival_seat = int(pending_arrival.seat)
		if right_placed.is_empty() and left_placed.is_empty():
			arrival_index = 0
		elif pub.opening_tile_index > last_opening_index:
			arrival_index = placements.size() - 1
		else:
			arrival_index = right_placed.size()
	pending_arrival = {}
	last_board_count = pub.board.size()
	last_opening_index = pub.opening_tile_index

	# Dónde caería la SIGUIENTE ficha en cada punta: es lo que se dibuja como sombra.
	#
	# Se calculan las dos variantes, normal y doble, porque un doble se acuesta cruzado y
	# ocupa un hueco distinto — otro tamaño y otro sitio. Cuál se enseña depende de la
	# ficha que se haya elegido; las dos se tienen en cuenta al medir para que la sombra
	# quepa sea cual sea.
	#
	# Se calculan con el mismo _layout_chain que las demás en vez de estimarlo aparte, así
	# la sombra hereda gratis toda la lógica de la esquina: si a la siguiente le toca
	# doblar, la sombra ya aparece doblada.
	var slots := {
		"R": _slots_after(right_chain, chain_start_x, 1.0, -1.0, anchor_tile.b, pub.right_end),
		"L": _slots_after(left_chain, -chain_start_x, -1.0, 1.0, anchor_tile.a, pub.left_end),
	}

	# La medición incluye SIEMPRE las sombras, se esté eligiendo o no. Si no, la mesa se
	# reajustaría al tocar una ficha; midiendo siempre igual, la sombra tiene su sitio
	# reservado y nada se mueve. Cuesta poco: en 300 manos medidas, la escala más chica
	# pasó de 0.55 a 0.53.
	var measured: Array = placements.duplicate()
	for side in slots.values():
		measured.append(side.plain)
		measured.append(side.double)

	# La ficha tiene un tamaño FIJO: la hilera crece y las fichas se quedan igual. El
	# tamaño está elegido para que el trazado más largo posible quepa entero (ver
	# BOARD_TILE_LENGTH), así que en la práctica no hace falta encoger nunca.
	#
	# Aun así se comprueba y se encoge si hiciera falta. El tamaño salió de medir 400
	# manos, que es mucho pero no son todas las manos posibles: si alguna vez apareciera
	# un trazado más largo que el peor medido, es mejor que se vea más chico un momento
	# que perder de vista media mesa y no poder tocar una punta.
	var fit_scale := BOARD_TILE_SCALE
	var min_x := 0.0
	var max_x := 0.0
	var min_y := 0.0
	var max_y := 0.0
	for p in measured:
		var half: Vector2 = p.size / 2.0
		min_x = min(min_x, p.offset.x - half.x)
		max_x = max(max_x, p.offset.x + half.x)
		min_y = min(min_y, p.offset.y - half.y)
		max_y = max(max_y, p.offset.y + half.y)

	# Con la ficha inicial clavada en el centro hay que caber a los dos lados por igual.
	var half_w: float = board_viewport.size.x / 2.0
	var half_h: float = board_viewport.size.y / 2.0
	var spread_x: float = max(max_x, -min_x)
	var spread_y: float = max(max_y, -min_y)
	if spread_x > 1.0:
		fit_scale = min(fit_scale, half_w / spread_x)
	if spread_y > 1.0:
		fit_scale = min(fit_scale, half_h / spread_y)

	var anchor_screen: Vector2 = board_viewport.size / 2.0
	for i in range(placements.size()):
		var p: Dictionary = placements[i]
		var rot: float = p.get("rotation", 0.0)
		var from_seat: int = arrival_seat if i == arrival_index else -1
		_place_board_tile(p.domino, anchor_screen + p.offset * fit_scale, fit_scale, rot, from_seat)

	end_slots = {}
	for key in slots:
		end_slots[key] = {
			"plain": _screen_rect(slots[key].plain, anchor_screen, fit_scale),
			"double": _screen_rect(slots[key].double, anchor_screen, fit_scale),
		}
	_sync_end_highlights()


## Los dos huecos posibles para la siguiente ficha de una punta: el de una ficha normal y
## el de un doble. Se obtienen dejando que _layout_chain coloque una ficha de más al final
## de la cadena, que es exactamente lo que haría con la ficha de verdad.
func _slots_after(chain: Array, start_x: float, x_sign: float, turn_dir_y: float, connect_init: int, end_value: int) -> Dictionary:
	return {
		"plain": _slot_for(chain, start_x, x_sign, turn_dir_y, connect_init, Domino.new(end_value, 0 if end_value != 0 else 1)),
		"double": _slot_for(chain, start_x, x_sign, turn_dir_y, connect_init, Domino.new(end_value, end_value)),
	}


func _slot_for(chain: Array, start_x: float, x_sign: float, turn_dir_y: float, connect_init: int, tile: Domino) -> Dictionary:
	var placed: Array = _layout_chain(chain + [tile], start_x, x_sign, turn_dir_y, connect_init)
	return placed[placed.size() - 1]


func _screen_rect(placement: Dictionary, anchor_screen: Vector2, fit_scale: float) -> Rect2:
	var size: Vector2 = (placement.size as Vector2) * fit_scale
	var center: Vector2 = anchor_screen + (placement.offset as Vector2) * fit_scale
	return Rect2(center - size / 2.0, size)


## "reach_x" es hasta dónde puede llegar la fila antes de doblar. Va como parámetro y no
## como constante para poder medir con distintos tamaños de ficha sin tocar el código.
func _layout_chain(chain: Array, start_x: float, x_sign_init: float, turn_dir_y: float, connect_init: int, reach_x: float = BOARD_REACH_X) -> Array:
	var result: Array = []
	var x_pos: float = start_x
	var y_level: float = 0.0
	var row_y: float = 0.0
	var x_sign: float = x_sign_init
	var connect_value: int = connect_init
	var turning: bool = false
	var turn_col_x: float = 0.0
	var pending_row_start: bool = false

	for t in chain:
		var outward_value: int = t.other(connect_value)
		# Lo que ocuparía la ficha a lo largo si siguiera en la fila. Se calcula antes de
		# decidir el giro porque es justo lo que decide si cabe.
		var flat_along: float = 64.0 if t.is_double() else 128.0

		# La fila dobla cuando la ficha YA NO CABE, no a las tantas fichas. Con un número
		# fijo, la fila terminaba donde tocara y sobraba mesa a los lados, lo que obligaba
		# a dibujar las fichas pequeñas; midiendo el sitio de verdad, la hilera se pliega
		# sola contra el borde y las fichas pueden ser mucho más grandes.
		#
		# Y puede doblar tantas veces como haga falta: la hilera se va plegando en filas,
		# como un texto que salta de renglón. Con un solo giro permitido, una mano larga se
		# salía del tablero por el otro lado.
		var entering_turn: bool = not turning and absf(x_pos + x_sign * flat_along) > reach_x
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
				turning = false
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


func _dir_angle(dir: Vector2) -> float:
	if dir.x > 0.0:
		return 90.0
	if dir.x < 0.0:
		return 270.0
	if dir.y > 0.0:
		return 180.0
	return 0.0


## Coloca una ficha en la mesa. Si "from_seat" es un puesto, la ficha entra deslizándose
## desde ese lado en vez de aparecer de golpe.
func _place_board_tile(t: Domino, center: Vector2, tile_scale: float, rotation_deg: float, from_seat: int = -1) -> void:
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
	if from_seat >= 0:
		_animate_arrival(tex, from_seat)


## La ficha recién jugada entra desde el lado de QUIEN LA JUGÓ. Además de llenar la pausa
## entre turnos, que hasta ahora era tiempo muerto, dice quién jugó sin tener que leer el
## registro: con tres rivales, ver de dónde viene la ficha es más rápido que buscar el
## nombre.
##
## El tween se crea desde la propia ficha para que muera con ella: la mesa se vuelve a
## dibujar entera en cada jugada, y una animación apuntando a una ficha ya liberada es un
## error en tiempo de ejecución.
func _animate_arrival(tex: TextureRect, from_seat: int) -> void:
	var landing: Vector2 = tex.position
	var offset := Vector2.ZERO
	match _screen_pos(from_seat):
		POS_BOTTOM:
			offset = Vector2(0, PLAY_ANIM_TRAVEL)
		POS_TOP:
			offset = Vector2(0, -PLAY_ANIM_TRAVEL)
		POS_LEFT:
			offset = Vector2(-PLAY_ANIM_TRAVEL, 0)
		POS_RIGHT:
			offset = Vector2(PLAY_ANIM_TRAVEL, 0)

	tex.position = landing + offset
	tex.modulate = Color(1, 1, 1, 0)

	var tween: Tween = tex.create_tween()
	tween.set_parallel(true)
	tween.tween_property(tex, "position", landing, PLAY_ANIM_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(tex, "modulate:a", 1.0, PLAY_ANIM_TIME)


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
		btn.custom_minimum_size = Vector2(HAND_TILE_SHORT, HAND_TILE_LONG)
		var is_legal: bool = legal_by_idx.has(i)
		btn.disabled = not is_legal
		btn.modulate = Color(1, 1, 1, 1) if is_legal else Color(0.5, 0.5, 0.5, 1)
		var idx_capture := i
		btn.pressed.connect(func(): _on_hand_tile_pressed(idx_capture))
		own_hand_row.add_child(btn)


# Las tres manos de enfrente usan la misma ficha que la propia: de pie para Norte,
# acostadas para los laterales, según cómo las sostendría cada jugador desde su puesto.
func _render_top_backs() -> void:
	var seat: int = _seat_at(POS_TOP)
	top_title.text = _rival_label(seat, false)
	for c in top_row.get_children():
		c.queue_free()
	for i in range(pub.hand_counts[seat]):
		top_row.add_child(_make_tile_back(HAND_TILE_SHORT, HAND_TILE_LONG))


func _render_side_stacks() -> void:
	var left_seat: int = _seat_at(POS_LEFT)
	left_title.text = _rival_label(left_seat, false)
	_layout_side_title(left_title, turn_dots[POS_LEFT], SIDE_LEFT_POS, true)
	for c in left_stack.get_children():
		c.queue_free()
	for i in range(pub.hand_counts[left_seat]):
		left_stack.add_child(_make_tile_back(HAND_TILE_LONG, HAND_TILE_SHORT))

	var right_seat: int = _seat_at(POS_RIGHT)
	right_title.text = _rival_label(right_seat, false)
	_layout_side_title(right_title, turn_dots[POS_RIGHT], SIDE_RIGHT_POS, false)
	for c in right_stack.get_children():
		c.queue_free()
	for i in range(pub.hand_counts[right_seat]):
		right_stack.add_child(_make_tile_back(HAND_TILE_LONG, HAND_TILE_SHORT))


## Los datos de la mesa, ya sin franja: la meta y las puntas en su esquina, y el tanteo
## de cada pareja pegado a la mano de sus dos jugadores.
func _update_scoreboard() -> void:
	lbl_target.text = "Meta  %d" % pub.target_score
	if pub.board.is_empty():
		lbl_ends.text = "Puntas  —"
	else:
		lbl_ends.text = "Puntas  %d  ·  %d" % [pub.left_end, pub.right_end]

	var own_team: int = _team_of(local_seat)
	for pos in range(SEAT_COUNT):
		var badge: PanelContainer = score_badges[pos]
		var label: Label = score_labels[pos]
		if badge == null or label == null:
			continue
		var team: int = _team_of(_seat_at(pos))
		label.text = str(pub.team_score[team])
		# El nombre de la pareja no cabe en el marcador y tampoco hace falta a cada
		# momento; se deja a mano por si se quiere confirmar de quién es el número.
		badge.tooltip_text = "%s: %d" % [_team_label(team), pub.team_score[team]]
		_style_score_badge(badge, label, team == own_team)


func _style_score_badge(badge: PanelContainer, label: Label, own_team: bool) -> void:
	var accent: Color = Color(1, 0.85, 0.35) if own_team else Color(0.55, 0.74, 0.92)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.16, 0.08, 0.92)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = accent
	sb.set_content_margin_all(4)
	badge.add_theme_stylebox_override("panel", sb)
	label.add_theme_color_override("font_color", accent)


# El pase es automático (lo aplica la autoridad) para que el juego nunca se quede
# esperando un clic que no llega; esto solo informa el estado del turno.
func _update_pass_status() -> void:
	if pending_hand_idx >= 0:
		# Con una ficha elegida, lo único que falta es decir dónde ponerla. Se dice acá
		# porque las marcas por sí solas no explican que hay que tocarlas.
		pass_status.text = "Toca la punta resaltada donde quieres jugarla"
	elif phase != Phase.PLAYING or pub.current_player != local_seat:
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


## Cómo se nombra un puesto en los textos: registro, avisos, resumen de la mano.
##
## Jugando solo son los nombres de brújula, que es lo único que hay. En red se usa el
## nombre que cada quien puso: decirle "Norte" a alguien que se llama Beto no le dice nada
## a los demás en la mesa, y el registro se vuelve ilegible.
func _seat_label(seat: int) -> String:
	if not online_mode:
		return SEAT_NAMES[seat]
	if seat < 0 or seat >= seat_owners.size():
		return "AI Player 1"
	var owner: String = str(seat_owners[seat])
	if not owner.is_empty():
		return owner
	return "AI Player %d" % _ai_number(seat)


## Número de la máquina en esa silla, contando SOLO las sillas vacías y en orden. Así
## salen "AI Player 1, 2, 3" seguidos, en vez de números con huecos que no significarían
## nada para quien los lee.
func _ai_number(seat: int) -> int:
	var found: int = 0
	for s in range(SEAT_COUNT):
		if s >= seat_owners.size() or str(seat_owners[s]).is_empty():
			found += 1
			if s == seat:
				return found
	return 1


## Igual, pero dejando claro que la mueve la máquina. Hace falta jugando solo, donde
## "Norte" no lo dice; en red "AI Player 1" ya se explica solo.
func _seat_title(seat: int) -> String:
	if not online_mode:
		return "%s (IA)" % SEAT_NAMES[seat]
	return _seat_label(seat)


## Cómo se nombra una pareja. En red son los dos nombres unidos: dejar "Sur-Norte" mientras
## los puestos se llaman por su nombre haría que el marcador y la mesa hablaran idiomas
## distintos.
func _team_label(team: int) -> String:
	if not online_mode:
		return TEAM_NAMES[team]
	var members: Array = []
	for seat in range(SEAT_COUNT):
		if _team_of(seat) == team:
			members.append(_seat_label(seat))
	return " y ".join(members)
