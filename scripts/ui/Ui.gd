class_name Ui
extends RefCounted

## El aspecto de los carteles del juego, en un solo sitio.
##
## Existe porque el mismo cartel se arma en dos pantallas que no se conocen entre sí —la
## mesa y el lobby— y los valores estaban copiados a mano en las dos. Se desincronizaron:
## el cartel del lobby tenía otro fondo, otro borde y otro grosor, y al pasar de una
## pantalla a la otra parecían dos aplicaciones distintas.
##
## Acá no hay nada que dependa del juego: ni reglas, ni red, ni estado. Solo colores,
## cajas y unos iconos dibujados a mano.


# ---------------------------------------------------------------------------
# Paleta
# ---------------------------------------------------------------------------
## Fondo del cartel y su borde dorado. El dorado es el único color cálido de la pantalla
## y por eso funciona como marco: separa el cartel del paño verde sin competir con él.
const PANEL_BG := Color(0.055, 0.125, 0.09)
const PANEL_BORDER := Color(0.79, 0.65, 0.26)

## Verde de acento: lo que está elegido, lo que se puede pulsar, lo afirmativo.
const ACCENT := Color(0.24, 0.78, 0.45)
const ACCENT_FILL := Color(0.11, 0.33, 0.21)
const ACCENT_SOFT := Color(0.10, 0.24, 0.17)

## Dorado de las bonificaciones: lo que suma puntos se marca con el mismo color que el
## borde, para que "premio" tenga un color propio y no otro verde más.
const GOLD := Color(0.93, 0.76, 0.28)

## Texto: el título, el cuerpo y lo secundario.
const TEXT := Color(0.94, 0.97, 0.94)
const TEXT_BODY := Color(0.82, 0.88, 0.83)
const TEXT_MUTED := Color(0.60, 0.71, 0.64)

## Campos y botones secundarios, más oscuros que el cartel para que se vean hundidos.
const FIELD_BG := Color(0.075, 0.15, 0.115)
const FIELD_BORDER := Color(0.20, 0.30, 0.24)

## Velo sobre el paño. Es el mismo en las dos pantallas de arranque a propósito: son el
## mismo momento del juego, antes de repartir, y con valores distintos el salto de una a
## otra se notaba.
const VEIL := Color(0, 0, 0, 0.5)

const RADIUS := 16
const FIELD_RADIUS := 10


# ---------------------------------------------------------------------------
# Cajas
# ---------------------------------------------------------------------------
## El cartel: fondo oscuro, borde dorado y sombra. La sombra es lo que lo despega del
## paño; sin ella, sobre un fondo con dibujo, el borde solo no alcanza.
static func panel_style(margin: float = 26.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(RADIUS)
	sb.set_content_margin_all(margin)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	return sb


## Una caja hundida: los campos de texto, los números, los botones apagados.
static func field_style(bg: Color = FIELD_BG, border: Color = FIELD_BORDER, width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(FIELD_RADIUS)
	sb.set_content_margin_all(8)
	return sb


## La caja de las reglas: verde apagado, sin borde fuerte. No es algo que se pulse, así
## que no debe parecerlo.
static func note_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT_SOFT
	sb.border_color = Color(0.16, 0.36, 0.25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(FIELD_RADIUS)
	sb.set_content_margin_all(12)
	return sb


# ---------------------------------------------------------------------------
# Textos
# ---------------------------------------------------------------------------
static func title(text: String, size: int = 30) -> Label:
	return _label(text, size, TEXT, HORIZONTAL_ALIGNMENT_CENTER)


static func body(text: String, width: float = 0.0) -> Label:
	var lbl := _label(text, 15, TEXT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	if width > 0.0:
		# Con ancho fijo el texto envuelve solo. Sin él, un párrafo largo estira el
		# cartel hasta donde haga falta y descuadra todo lo demás.
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.custom_minimum_size = Vector2(width, 0)
	return lbl


static func muted(text: String, width: float = 0.0, size: int = 13) -> Label:
	var lbl := _label(text, size, TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	if width > 0.0:
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.custom_minimum_size = Vector2(width, 0)
	return lbl


## Un encabezado de sección: el icono y el texto en una fila. El icono lleva el color de
## lo que encabeza —verde lo que se elige, dorado lo que da puntos— así que se distinguen
## las secciones de un vistazo, sin leerlas.
static func section(text: String, kind: int, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(icon(kind, color, 20.0))
	row.add_child(_label(text, 17, TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	return row


## Una línea de separación. Va como un Panel de un píxel de alto y no como HSeparator
## para que el color no dependa del tema por defecto.
static func rule(width: float) -> Panel:
	var line := Panel.new()
	line.custom_minimum_size = Vector2(width, 1)
	var sb := StyleBoxFlat.new()
	sb.bg_color = FIELD_BORDER
	line.add_theme_stylebox_override("panel", sb)
	return line


static func _label(text: String, size: int, color: Color, align: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = align
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


# ---------------------------------------------------------------------------
# Iconos
# ---------------------------------------------------------------------------
## Los iconos van DIBUJADOS, no como imágenes ni como texto.
##
## No es capricho: la fuente por defecto de Godot no trae ninguno de estos glifos (lo
## comprobé uno por uno: ni ✓, ni ★, ni ⚙, ni ℹ), así que como texto saldrían cuadritos.
## Y como imágenes habría que añadir archivos, revisar su licencia y decidir tamaños.
## Dibujados no pesan nada, se ven nítidos a cualquier escala y toman el color que se les
## pida, que es justo lo que hace falta acá: el mismo icono en verde o en dorado.
enum { GEAR, STAR, INFO, CHECK, PLAY, PEOPLE }


static func icon(kind: int, color: Color, size: float = 20.0) -> Control:
	var node := IconDraw.new()
	node.kind = kind
	node.tint = color
	node.custom_minimum_size = Vector2(size, size)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


class IconDraw extends Control:
	var kind: int = Ui.GEAR
	var tint: Color = Ui.ACCENT

	func _draw() -> void:
		var s: float = minf(size.x, size.y)
		var c := Vector2(s, s) / 2.0
		var r: float = s / 2.0
		match kind:
			Ui.CHECK:
				# Dos trazos con las esquinas redondeadas, del grosor de un séptimo del
				# icono: más fino se pierde a 16 px, más grueso parece una V.
				var w: float = s * 0.15
				var a := Vector2(s * 0.20, s * 0.52)
				var b := Vector2(s * 0.42, s * 0.74)
				var d := Vector2(s * 0.80, s * 0.28)
				draw_line(a, b, tint, w, true)
				draw_line(b, d, tint, w, true)
				draw_circle(b, w / 2.0, tint)
			Ui.STAR:
				draw_colored_polygon(_star(c, r * 0.98, r * 0.45), tint)
			Ui.GEAR:
				# Los dientes son trazos gruesos que salen del centro, encima va el cuerpo
				# y al final se tapa el agujero con el color del cartel. Seis dientes y no
				# ocho: a 20 px, ocho se emborronan y parece una flor.
				for i in range(6):
					var ang: float = TAU * float(i) / 6.0
					var dir := Vector2(cos(ang), sin(ang))
					draw_line(c + dir * (r * 0.40), c + dir * (r * 0.94), tint, s * 0.26, true)
				draw_circle(c, r * 0.66, tint)
				draw_circle(c, r * 0.30, Ui.PANEL_BG)
			Ui.INFO:
				draw_circle(c, r * 0.96, tint)
				draw_circle(Vector2(c.x, c.y - r * 0.42), r * 0.13, Ui.PANEL_BG)
				draw_line(Vector2(c.x, c.y - r * 0.10), Vector2(c.x, c.y + r * 0.52), Ui.PANEL_BG, s * 0.13, true)
			Ui.PLAY:
				draw_colored_polygon(PackedVector2Array([
					Vector2(s * 0.28, s * 0.20), Vector2(s * 0.28, s * 0.80), Vector2(s * 0.82, s * 0.50),
				]), tint)
			Ui.PEOPLE:
				# Dos personas: la de atrás más pequeña y corrida, que es lo que hace que
				# se lea "varios" y no "uno".
				_person(Vector2(s * 0.66, s * 0.42), r * 0.62, tint)
				_person(Vector2(s * 0.36, s * 0.38), r * 0.78, tint)

	## Una persona: la cabeza y los hombros. Los hombros son media rueda, que a este
	## tamaño se lee mejor que una silueta con detalle.
	func _person(at: Vector2, scale: float, color: Color) -> void:
		draw_circle(Vector2(at.x, at.y - scale * 0.45), scale * 0.42, color)
		draw_colored_polygon(_slice(Vector2(at.x, at.y + scale * 0.55), scale * 0.80, 180.0, 360.0), color)

	func _star(at: Vector2, outer: float, inner: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		for i in range(10):
			var ang: float = -PI / 2.0 + TAU * float(i) / 10.0
			var rad: float = outer if i % 2 == 0 else inner
			points.append(at + Vector2(cos(ang), sin(ang)) * rad)
		return points

	func _slice(at: Vector2, radius: float, from_deg: float, to_deg: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		for i in range(17):
			var t: float = float(i) / 16.0
			var ang: float = deg_to_rad(lerpf(from_deg, to_deg, t))
			points.append(at + Vector2(cos(ang), sin(ang)) * radius)
		return points


# ---------------------------------------------------------------------------
# Botones y campos
# ---------------------------------------------------------------------------
## Botón principal: borde y texto verdes, con su icono. Es el que se pulsa por defecto,
## así que se distingue por el color y no por el tamaño.
static func primary_button(text: String, kind: int = PLAY) -> Button:
	var btn := _button(text, ACCENT)
	_apply_button_style(btn, ACCENT_FILL, ACCENT, 2)
	btn.add_child(icon(kind, ACCENT, BUTTON_ICON))
	_pin_icon(btn, ACCENT_FILL, ACCENT, 2)
	return btn


## Botón secundario: la misma forma, sin color. Lo que hace es igual de válido, pero no
## es lo que se espera que se pulse.
static func secondary_button(text: String, kind: int = PEOPLE) -> Button:
	var btn := _button(text, TEXT_BODY)
	_apply_button_style(btn, FIELD_BG, FIELD_BORDER, 1)
	btn.add_child(icon(kind, TEXT_MUTED, BUTTON_ICON))
	_pin_icon(btn, FIELD_BG, FIELD_BORDER, 1)
	return btn


## Una de las opciones de meta. La elegida se llena de verde y le sale un visto en la
## esquina: con solo el color, en una captura o con poca luz, no se sabe cuál está puesta.
static func choice_button(text: String, chosen: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.button_pressed = chosen
	btn.custom_minimum_size = Vector2(112, 52)
	btn.add_theme_font_size_override("font_size", 19)
	style_choice(btn, chosen)
	return btn


## Se llama al construir y en cada cambio de elección: el estado vive en el botón, no en
## una copia aparte que pueda quedar desfasada.
static func style_choice(btn: Button, chosen: bool) -> void:
	var fill: Color = ACCENT_FILL if chosen else FIELD_BG
	var border: Color = ACCENT if chosen else FIELD_BORDER
	_apply_button_style(btn, fill, border, 2 if chosen else 1)
	btn.add_theme_color_override("font_color", TEXT if chosen else TEXT_BODY)
	btn.add_theme_color_override("font_pressed_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)

	for child in btn.get_children():
		if child is Control and child.name == "visto":
			child.queue_free()
	if not chosen:
		return

	# El visto va colocado a mano y no en un contenedor: tiene que salirse un poco del
	# botón por la esquina, y un contenedor lo metería dentro.
	var mark := icon(CHECK, TEXT, 16.0)
	mark.name = "visto"
	var badge := Panel.new()
	badge.name = "visto"
	badge.custom_minimum_size = Vector2(22, 22)
	badge.size = Vector2(22, 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT
	sb.set_corner_radius_all(11)
	badge.add_theme_stylebox_override("panel", sb)
	badge.add_child(mark)
	mark.position = Vector2(3, 3)
	mark.size = Vector2(16, 16)
	btn.add_child(badge)
	badge.position = Vector2(btn.custom_minimum_size.x - 14, -8)


static func _button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 48)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", TEXT)
	btn.add_theme_color_override("font_pressed_color", TEXT)
	return btn


## El icono de un botón se coloca a mano y el texto se corre a la derecha con un margen.
##
## Godot deja poner un icono con "btn.icon", pero eso pide una Texture2D y estos iconos
## son dibujados. Y con el texto centrado, el icono le caía encima: por eso el texto se
## alinea a la izquierda y el margen le reserva el sitio.
const BUTTON_ICON := 18.0
const BUTTON_PAD := 46.0


static func _pin_icon(btn: Button, fill: Color, border: Color, width: int) -> void:
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBoxFlat = btn.get_theme_stylebox(state)
		sb.content_margin_left = BUTTON_PAD

	# Anclado al centro del lado izquierdo, con los desplazamientos puestos a mano: así
	# queda centrado a lo alto sea cual sea la altura del botón.
	var mark: Control = btn.get_child(btn.get_child_count() - 1)
	mark.anchor_left = 0.0
	mark.anchor_right = 0.0
	mark.anchor_top = 0.5
	mark.anchor_bottom = 0.5
	mark.offset_left = 18.0
	mark.offset_right = 18.0 + BUTTON_ICON
	mark.offset_top = -BUTTON_ICON / 2.0
	mark.offset_bottom = BUTTON_ICON / 2.0
	# El estilo se vuelve a pedir para que el margen nuevo entre en las cinco cajas.
	_apply_button_style(btn, fill, border, width)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBoxFlat = btn.get_theme_stylebox(state)
		sb.content_margin_left = BUTTON_PAD


static func _apply_button_style(btn: Button, fill: Color, border: Color, width: int) -> void:
	btn.add_theme_stylebox_override("normal", field_style(fill, border, width))
	btn.add_theme_stylebox_override("hover", field_style(fill.lightened(0.10), border.lightened(0.15), width))
	btn.add_theme_stylebox_override("pressed", field_style(fill.darkened(0.10), border, width))
	btn.add_theme_stylebox_override("focus", field_style(fill, border, width))
	btn.add_theme_stylebox_override("disabled", field_style(fill.darkened(0.30), border.darkened(0.30), width))


## Un campo de número. Se le da estilo al LineEdit de dentro y no al SpinBox: el
## SpinBox es un envoltorio y el fondo que se ve es el del campo de texto.
##
## Las flechitas de subir y bajar se dejan como vienen. Son una textura del tema por
## defecto de Godot, así que no se pueden redibujar como los demás iconos, y sustituirlas
## por dos botones propios cambiaría cómo se usa el campo para ganar muy poco.
static func style_spin(spin: SpinBox, width: float = 190.0) -> SpinBox:
	spin.custom_minimum_size = Vector2(width, 44)
	spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var field: LineEdit = spin.get_line_edit()
	field.add_theme_stylebox_override("normal", field_style())
	field.add_theme_stylebox_override("focus", field_style(FIELD_BG, ACCENT, 1))
	field.add_theme_stylebox_override("read_only", field_style())
	field.add_theme_font_size_override("font_size", 18)
	field.add_theme_color_override("font_color", TEXT)
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return spin


static func style_line_edit(field: LineEdit) -> LineEdit:
	field.custom_minimum_size = Vector2(0, 42)
	field.add_theme_stylebox_override("normal", field_style())
	field.add_theme_stylebox_override("focus", field_style(FIELD_BG, ACCENT, 1))
	field.add_theme_font_size_override("font_size", 16)
	field.add_theme_color_override("font_color", TEXT)
	field.add_theme_color_override("font_placeholder_color", TEXT_MUTED)
	return field


## Las dos fichas del encabezado. Van con las imágenes de verdad del juego —no un dibujo
## de una ficha— porque ya están en el proyecto y porque es literalmente lo que se va a
## ver en la mesa un segundo después.
##
## Las rutas llegan de fuera: acá no se sabe qué es un dominó, y así este archivo no
## depende de las reglas.
static func tiles_header(paths: Array, height: float = 58.0) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(height * 2.0, height)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Las fichas van casi acostadas y solapadas, como quedan sobre la mesa. La textura es
	# una ficha DE PIE, así que el giro parte de 90°: con giros pequeños salían dos fichas
	# verticales cruzadas en V, que no se parece a nada de una mesa de dominó.
	var turn: Array = [90.0 - 22.0, 90.0 + 16.0]
	var at: Array = [Vector2(height * 0.78, height * 0.52), Vector2(height * 1.30, height * 0.46)]
	var tile := Vector2(height * 0.46, height * 0.92)
	for i in range(mini(paths.size(), 2)):
		var tex := TextureRect.new()
		tex.texture = load(str(paths[i]))
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.size = tile
		tex.pivot_offset = tile / 2.0
		tex.rotation_degrees = float(turn[i])
		tex.position = (at[i] as Vector2) - tile / 2.0
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tex)
	return box


## Una fila de silla en la sala. Es una caja hundida y no un botón con relieve: la lista
## de quién está sentado dónde se lee, y solo el anfitrión la toca. La resaltada es la
## que él eligió primero para intercambiar.
static func style_seat_row(btn: Button, picked: bool) -> void:
	var fill: Color = ACCENT_FILL if picked else FIELD_BG
	var border: Color = ACCENT if picked else FIELD_BORDER
	_apply_button_style(btn, fill, border, 2 if picked else 1)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBoxFlat = btn.get_theme_stylebox(state)
		sb.content_margin_left = 16.0
