extends Control

# ---------------------------------------------------------------------------
# Constantes de la mesa
# ---------------------------------------------------------------------------
# Orden de asientos = orden de turno en sentido contrario a las agujas del reloj:
# Sur (humano, abajo) -> Este (derecha) -> Norte (arriba) -> Oeste (izquierda) -> Sur...
const HUMAN_SEAT := 0
const SEAT_NAMES := ["Sur", "Este", "Norte", "Oeste"]
const TEAM_OF_SEAT := [0, 1, 0, 1]
const TEAM_NAMES := ["Sur-Norte", "Este-Oeste"]

# Cada lado de la hilera avanza en fila (máx. 5 fichas seguidas); al llegar a esa
# cantidad, dobla UNA sola vez en toda la partida (el lado derecho hacia arriba, el
# izquierdo hacia abajo) y desde ahí sigue derecho en el sentido contrario el resto
# de la mano, igual que en una mesa real cuando la cadena se acerca al borde.
const ROW_LENGTH := 5

enum Phase { SETUP, PLAYING, HAND_OVER, GAME_OVER }

# ---------------------------------------------------------------------------
# Estado de la partida
# ---------------------------------------------------------------------------
var phase: int = Phase.SETUP
var target_score: int = 200
var team_score: Array = [0, 0]

var hands: Array = [[], [], [], []]
var board: Array = []
var left_end: int = -1
var right_end: int = -1

var current_player: int = 0
var lead_player: int = 0
var consecutive_passes: int = 0
# Quién puso la última ficha: en un tranque, sus fichas se comparan con las del
# jugador que le seguía en el turno para decidir quién gana la mano.
var last_player_to_play: int = -1
var is_first_hand_of_game: bool = true
var must_open_with_double_six: bool = false
# Índice dentro de "board" de la ficha inicial (el ancla fija de la hilera). Todo lo
# que se juega hacia la izquierda le suma 1 a este índice (porque se inserta antes).
var opening_tile_index: int = -1

# ---------------------------------------------------------------------------
# Referencias a nodos de interfaz (creados en tiempo de ejecución)
# ---------------------------------------------------------------------------
var lbl_target: Label
var lbl_score0: Label
var lbl_score1: Label
var lbl_turn: Label
var lbl_ends: Label

var north_title: Label
var north_row: HBoxContainer
var south_hand_row: HBoxContainer
var pass_status: Label

var west_title: Label
var west_stack: VBoxContainer
var east_title: Label
var east_stack: VBoxContainer

var board_viewport: Control

var log_rt: RichTextLabel

var start_overlay: Control
var selected_target: int = 200
var target_option_buttons: Array = []

var end_choice_popup: PanelContainer
var pending_hand_idx: int = -1

# Pantalla de fin de mano: se queda esperando el botón "Continuar" en vez de seguir
# sola, para que se pueda revisar de dónde salieron los puntos.
var hand_result_overlay: Control
var hand_result_content: VBoxContainer
var pending_winner_team: int = -1

var game_over_overlay: Control
var game_over_label: Label


# ===========================================================================
# Construcción de la interfaz
# ===========================================================================
func _ready() -> void:
	_build_background()
	_build_top_bar()
	_build_ends_label()
	_build_north_panel()
	_build_south_panel()
	_build_west_panel()
	_build_east_panel()
	_build_board_area()
	_build_log_panel()
	_build_end_choice_popup()
	_build_hand_result_overlay()
	_build_game_over_overlay()
	_build_start_overlay()


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


func _build_north_panel() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(440, 54)
	panel.size = Vector2(400, 120)
	panel.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(panel)

	north_title = Label.new()
	north_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	north_title.add_theme_font_size_override("font_size", 14)
	panel.add_child(north_title)

	north_row = HBoxContainer.new()
	north_row.alignment = BoxContainer.ALIGNMENT_CENTER
	north_row.add_theme_constant_override("separation", 3)
	panel.add_child(north_row)


func _build_south_panel() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(300, 668)
	panel.size = Vector2(680, 225)
	panel.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(panel)

	var title := Label.new()
	title.text = "Tu mano (Sur)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	panel.add_child(title)

	south_hand_row = HBoxContainer.new()
	south_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	south_hand_row.add_theme_constant_override("separation", 8)
	panel.add_child(south_hand_row)

	# Solo informa el estado del turno (el pase es automático), así que es una
	# etiqueta y no un botón deshabilitado.
	pass_status = Label.new()
	pass_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pass_status.add_theme_font_size_override("font_size", 14)
	pass_status.add_theme_color_override("font_color", Color(0.85, 0.88, 0.85))
	panel.add_child(pass_status)


# En los laterales la etiqueta va DEBAJO de la pila de fichas, siguiendo la columna,
# para que se lea junto a las fichas de ese jugador y no arriba, despegada de ellas.
func _build_west_panel() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(10, 204)
	panel.size = Vector2(160, 456)
	panel.alignment = BoxContainer.ALIGNMENT_BEGIN
	panel.add_theme_constant_override("separation", 8)
	add_child(panel)

	var center := CenterContainer.new()
	panel.add_child(center)

	west_stack = VBoxContainer.new()
	west_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	west_stack.add_theme_constant_override("separation", 6)
	center.add_child(west_stack)

	west_title = Label.new()
	west_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	west_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	west_title.add_theme_font_size_override("font_size", 14)
	panel.add_child(west_title)


func _build_east_panel() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(1110, 204)
	panel.size = Vector2(160, 456)
	panel.alignment = BoxContainer.ALIGNMENT_BEGIN
	panel.add_theme_constant_override("separation", 8)
	add_child(panel)

	var center := CenterContainer.new()
	panel.add_child(center)

	east_stack = VBoxContainer.new()
	east_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	east_stack.add_theme_constant_override("separation", 6)
	center.add_child(east_stack)

	east_title = Label.new()
	east_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	east_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	east_title.add_theme_font_size_override("font_size", 14)
	panel.add_child(east_title)


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
	end_choice_popup.size = Vector2(500, 72)
	end_choice_popup.visible = false
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
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)

	game_over_label = Label.new()
	game_over_label.add_theme_font_size_override("font_size", 26)
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(game_over_label)

	var again_btn := Button.new()
	again_btn.text = "Jugar de nuevo"
	again_btn.custom_minimum_size = Vector2(200, 40)
	again_btn.pressed.connect(_on_play_again_pressed)
	var again_center := CenterContainer.new()
	again_center.add_child(again_btn)
	vb.add_child(again_center)


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
	target_score = selected_target
	start_overlay.visible = false
	team_score = [0, 0]
	is_first_hand_of_game = true
	log_rt.clear()
	_log("Partida nueva. Meta: %d puntos." % target_score)
	start_new_hand()


func _on_play_again_pressed() -> void:
	game_over_overlay.visible = false
	start_overlay.visible = true


# ===========================================================================
# Reparto y comienzo de mano
# ===========================================================================
func _build_deck() -> Array:
	var deck: Array = []
	for i in range(7):
		for j in range(i, 7):
			deck.append(Domino.new(i, j))
	return deck


func start_new_hand() -> void:
	var deck := _build_deck()
	deck.shuffle()
	hands = [[], [], [], []]
	for seat in range(4):
		for k in range(7):
			hands[seat].append(deck.pop_back())

	board.clear()
	left_end = -1
	right_end = -1
	opening_tile_index = -1
	consecutive_passes = 0
	last_player_to_play = -1
	phase = Phase.PLAYING

	if is_first_hand_of_game:
		for seat in range(4):
			for t in hands[seat]:
				if t.a == 6 and t.b == 6:
					current_player = seat
					lead_player = seat
		must_open_with_double_six = true
		is_first_hand_of_game = false
		_log("Se reparten las fichas (7 por jugador, sin pozo). [b]%s[/b] tiene el 6-6 (el burro) y sale." % SEAT_NAMES[current_player])
	else:
		current_player = lead_player
		must_open_with_double_six = false
		_log("Nueva mano. Sale %s." % SEAT_NAMES[current_player])

	_render_all()
	_proceed_turn()


# ===========================================================================
# Turnos
# ===========================================================================
func _legal_moves_for(seat: int) -> Array:
	var moves: Array = []
	var hand: Array = hands[seat]

	if board.is_empty():
		if must_open_with_double_six and seat == lead_player:
			for i in range(hand.size()):
				if hand[i].a == 6 and hand[i].b == 6:
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


func _proceed_turn() -> void:
	if phase != Phase.PLAYING:
		return
	_update_top_bar()
	_render_south_hand()
	_update_pass_status()

	# Si de verdad no hay ninguna ficha jugable (sea IA o el humano), se pasa solo:
	# nadie puede quedarse esperando un clic que no llega, y así el tranque (4 pases
	# seguidos) siempre se detecta y se resuelve.
	if _legal_moves_for(current_player).is_empty():
		await get_tree().create_timer(0.9).timeout
		if phase == Phase.PLAYING:
			_handle_pass(current_player)
		return

	if current_player != HUMAN_SEAT:
		await get_tree().create_timer(0.9).timeout
		if phase == Phase.PLAYING:
			_ai_take_turn(current_player)


func _ai_take_turn(seat: int) -> void:
	var moves := _legal_moves_for(seat)
	if moves.is_empty():
		_handle_pass(seat)
		return

	var hand: Array = hands[seat]
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
	_play_tile(seat, best.idx, chosen_end)


func _play_tile(seat: int, idx: int, end: String) -> void:
	var t: Domino = hands[seat][idx]
	hands[seat].remove_at(idx)

	if board.is_empty():
		board.push_back(t)
		left_end = t.a
		right_end = t.b
		opening_tile_index = 0
	elif end == "L":
		var other_v := t.other(left_end)
		board.push_front(t)
		left_end = other_v
		opening_tile_index += 1
	else:
		var other_v := t.other(right_end)
		board.push_back(t)
		right_end = other_v

	must_open_with_double_six = false
	consecutive_passes = 0
	last_player_to_play = seat
	_log("%s jugó [b]%s[/b]." % [SEAT_NAMES[seat], str(t)])
	_render_all()
	_check_hand_end(seat)


func _handle_pass(seat: int) -> void:
	consecutive_passes += 1
	_log("%s pasa (no tiene fichas con %d ni %d)." % [SEAT_NAMES[seat], left_end, right_end])
	if consecutive_passes >= 4:
		_resolve_tranque()
	else:
		_advance_turn()


func _advance_turn() -> void:
	current_player = (current_player + 1) % 4
	_proceed_turn()


func _check_hand_end(seat: int) -> void:
	if hands[seat].is_empty():
		_hand_won_by_domino(seat)
	else:
		_advance_turn()


# ===========================================================================
# Fin de mano y puntuación
# ===========================================================================
func _seat_pips(seat: int) -> int:
	var total := 0
	for t in hands[seat]:
		total += t.pips()
	return total


func _team_pip_totals() -> Array:
	var totals := [0, 0]
	for s in range(4):
		totals[TEAM_OF_SEAT[s]] += _seat_pips(s)
	return totals


# Regla de la mesa: la pareja ganadora suma los puntos de TODAS las fichas que
# quedaron sobre la mesa, las de la propia pareja incluidas — no solo las del rival.
func _hand_won_by_domino(winner_seat: int) -> void:
	phase = Phase.HAND_OVER
	var winner_team: int = TEAM_OF_SEAT[winner_seat]
	var totals: Array = _team_pip_totals()
	var pts: int = totals[0] + totals[1]
	team_score[winner_team] += pts
	_log("[b]%s[/b] colocó su última ficha. ¡Equipo %s gana la mano! (+%d puntos)" % [SEAT_NAMES[winner_seat], TEAM_NAMES[winner_team], pts])
	lead_player = winner_seat
	_render_all()
	_show_hand_result(
		"¡Equipo %s gana la mano!" % TEAM_NAMES[winner_team],
		"%s colocó su última ficha. Se cuentan todas las fichas que quedaron en la mesa, de las dos parejas." % SEAT_NAMES[winner_seat],
		{},
		winner_team,
		totals,
		pts
	)


# Regla de la mesa: el tranque se decide cara a cara entre quien puso la última
# ficha y el jugador que le seguía en el turno (siempre de la pareja contraria,
# porque los puestos se alternan). Gana la mano la pareja de quien tenga menos
# puntos, y los puntos que suma son los de TODAS las fichas de la mesa, incluidas
# las dos manos que se compararon.
func _resolve_tranque() -> void:
	phase = Phase.HAND_OVER
	var totals: Array = _team_pip_totals()
	var pts: int = totals[0] + totals[1]

	var closer: int = last_player_to_play if last_player_to_play >= 0 else lead_player
	var challenger: int = (closer + 1) % 4
	var closer_pips: int = _seat_pips(closer)
	var challenger_pips: int = _seat_pips(challenger)

	var winner_seat: int
	var subtitle: String
	if closer_pips < challenger_pips:
		winner_seat = closer
		subtitle = "%s trancó el juego. Se comparan sus fichas con las de %s, que seguía en el turno: %d contra %d, gana %s." % [SEAT_NAMES[closer], SEAT_NAMES[challenger], closer_pips, challenger_pips, SEAT_NAMES[closer]]
	elif challenger_pips < closer_pips:
		winner_seat = challenger
		subtitle = "%s trancó el juego. Se comparan sus fichas con las de %s, que seguía en el turno: %d contra %d, gana %s." % [SEAT_NAMES[closer], SEAT_NAMES[challenger], closer_pips, challenger_pips, SEAT_NAMES[challenger]]
	else:
		# Empate entre los dos: se resuelve a favor de la pareja que tiene la mano.
		winner_seat = closer if TEAM_OF_SEAT[closer] == TEAM_OF_SEAT[lead_player] else challenger
		subtitle = "%s trancó el juego. Empate con %s (%d - %d): gana la pareja que tiene la mano." % [SEAT_NAMES[closer], SEAT_NAMES[challenger], closer_pips, challenger_pips]

	var winner_team: int = TEAM_OF_SEAT[winner_seat]
	team_score[winner_team] += pts
	_log("¡Tranque! %s (%d) contra %s (%d): gana el equipo %s. (+%d puntos)" % [SEAT_NAMES[closer], closer_pips, SEAT_NAMES[challenger], challenger_pips, TEAM_NAMES[winner_team], pts])

	# Dentro del equipo ganador, sale en la próxima mano quien se quedó con menos puntos en la mano.
	var best_seat := -1
	var best_pips := 9999
	for s in range(4):
		if TEAM_OF_SEAT[s] == winner_team:
			var sp: int = _seat_pips(s)
			if sp < best_pips:
				best_pips = sp
				best_seat = s
	lead_player = best_seat

	_render_all()
	var notes := {
		closer: "trancó",
		challenger: "seguía",
	}
	_show_hand_result("¡Tranque!", subtitle, notes, winner_team, totals, pts)


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

	var pts_lbl := Label.new()
	pts_lbl.text = "Equipo %s suma %d puntos  (%d + %d)" % [TEAM_NAMES[winner_team], pts, team_pips[0], team_pips[1]]
	pts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pts_lbl.add_theme_font_size_override("font_size", 20)
	pts_lbl.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	hand_result_content.add_child(pts_lbl)

	var score_lbl := Label.new()
	score_lbl.text = "Marcador: %s %d  —  %s %d      (meta: %d)" % [TEAM_NAMES[0], team_score[0], TEAM_NAMES[1], team_score[1], target_score]
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
		if TEAM_OF_SEAT[s] == team:
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
	for t in hands[seat]:
		var tex := TextureRect.new()
		tex.texture = load(t.texture())
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(30, 60)
		tiles_box.add_child(tex)
		total += t.pips()

	if hands[seat].is_empty():
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
	var winner_team: int = pending_winner_team
	pending_winner_team = -1
	hand_result_overlay.visible = false
	_after_hand_scoring_check(winner_team)


func _after_hand_scoring_check(winner_team: int) -> void:
	if team_score[winner_team] >= target_score:
		_game_over(winner_team)
	else:
		start_new_hand()


func _game_over(winner_team: int) -> void:
	phase = Phase.GAME_OVER
	game_over_label.text = "¡Equipo %s gana la partida!\nPuntaje final: %d - %d" % [TEAM_NAMES[winner_team], team_score[0], team_score[1]]
	game_over_overlay.visible = true
	_log("[b]Fin de la partida. Gana el equipo %s (%d - %d).[/b]" % [TEAM_NAMES[winner_team], team_score[0], team_score[1]])


# ===========================================================================
# Interacción del jugador humano
# ===========================================================================
func _on_hand_tile_pressed(idx: int) -> void:
	if phase != Phase.PLAYING or current_player != HUMAN_SEAT:
		return
	var moves := _legal_moves_for(HUMAN_SEAT)
	var chosen: Variant = null
	for m in moves:
		if m.idx == idx:
			chosen = m
			break
	if chosen == null:
		return
	if board.is_empty() or chosen.ends.size() == 1:
		var e: String = chosen.ends[0]
		_play_tile(HUMAN_SEAT, idx, e)
	else:
		_show_end_choice_popup(idx)


func _show_end_choice_popup(idx: int) -> void:
	pending_hand_idx = idx
	var left_btn: Button = end_choice_popup.find_child("LeftBtn", true, false)
	var right_btn: Button = end_choice_popup.find_child("RightBtn", true, false)
	left_btn.text = "Izquierda (%d)" % left_end
	right_btn.text = "Derecha (%d)" % right_end
	end_choice_popup.visible = true


func _on_end_choice(end: String) -> void:
	end_choice_popup.visible = false
	if pending_hand_idx < 0:
		return
	var idx := pending_hand_idx
	pending_hand_idx = -1
	_play_tile(HUMAN_SEAT, idx, end)


# ===========================================================================
# Renderizado
# ===========================================================================
func _render_all() -> void:
	_render_board()
	_render_south_hand()
	_render_side_stacks()
	_render_north_hand_backs()
	_update_top_bar()
	_update_pass_status()


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

	if board.is_empty() or opening_tile_index < 0:
		return

	var anchor_tile: Domino = board[opening_tile_index]
	var right_chain: Array = board.slice(opening_tile_index + 1, board.size())
	var left_chain: Array = []
	for i in range(opening_tile_index - 1, -1, -1):
		left_chain.append(board[i])

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
	var scale := 1.0
	if max_x > 1.0 and half_w / max_x < scale:
		scale = half_w / max_x
	if -min_x > 1.0 and half_w / (-min_x) < scale:
		scale = half_w / (-min_x)
	if max_y > 1.0 and half_h / max_y < scale:
		scale = half_h / max_y
	if -min_y > 1.0 and half_h / (-min_y) < scale:
		scale = half_h / (-min_y)
	if scale < 0.28:
		scale = 0.28

	var anchor_screen: Vector2 = board_viewport.size / 2.0
	for p in placements:
		var rot: float = p.get("rotation", 0.0)
		_place_board_tile(p.domino, anchor_screen + p.offset * scale, scale, rot)


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
		var size: Vector2
		if not turning:
			center = Vector2(x_pos + x_sign * (along / 2.0), row_y)
			size = Vector2(along, perp)
			x_pos += x_sign * along
			count_in_row += 1
			# Guarda el borde real de ESTA ficha (no la línea central de la fila) para
			# que, si la siguiente ficha dobla, arranque pegada aquí y no se solape ni
			# deje un hueco — el grosor cambia si esta ficha es un doble.
			y_level = row_y + turn_dir_y * (perp / 2.0)
		else:
			center = Vector2(turn_col_x, y_level + turn_dir_y * (along / 2.0))
			size = Vector2(perp, along)
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

		result.append({"domino": t, "offset": center, "size": size, "rotation": angle})
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


func _place_board_tile(t: Domino, center: Vector2, scale: float, rotation_deg: float) -> void:
	var natural: Vector2 = Vector2(64, 128) * scale
	var tex := TextureRect.new()
	tex.texture = load(t.texture())
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.size = natural
	tex.pivot_offset = natural / 2.0
	tex.position = center - natural / 2.0
	tex.rotation_degrees = rotation_deg
	board_viewport.add_child(tex)


func _render_south_hand() -> void:
	for c in south_hand_row.get_children():
		c.queue_free()

	var legal_by_idx := {}
	if phase == Phase.PLAYING and current_player == HUMAN_SEAT:
		for m in _legal_moves_for(HUMAN_SEAT):
			legal_by_idx[m.idx] = true

	for i in range(hands[HUMAN_SEAT].size()):
		var t: Domino = hands[HUMAN_SEAT][i]
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
		south_hand_row.add_child(btn)


# Las tres manos de la IA usan fichas del mismo tamaño (44x88, la misma proporción
# 1:2 de una ficha real): de pie para Norte, acostadas para los laterales, según
# cómo las sostendría cada jugador desde su puesto.
func _render_north_hand_backs() -> void:
	north_title.text = "Norte (IA) — compañero de Sur — %d fichas" % hands[2].size()
	for c in north_row.get_children():
		c.queue_free()
	for i in range(hands[2].size()):
		north_row.add_child(_make_tile_back(44, 88))


func _render_side_stacks() -> void:
	west_title.text = "Oeste (IA)\n%d fichas" % hands[3].size()
	for c in west_stack.get_children():
		c.queue_free()
	for i in range(hands[3].size()):
		west_stack.add_child(_make_tile_back(88, 44))

	east_title.text = "Este (IA)\n%d fichas" % hands[1].size()
	for c in east_stack.get_children():
		c.queue_free()
	for i in range(hands[1].size()):
		east_stack.add_child(_make_tile_back(88, 44))


func _update_top_bar() -> void:
	lbl_target.text = "Meta: %d" % target_score
	lbl_score0.text = "Sur-Norte: %d" % team_score[0]
	lbl_score1.text = "Este-Oeste: %d" % team_score[1]
	if phase == Phase.PLAYING:
		var who: String = "Tú" if current_player == HUMAN_SEAT else "IA"
		lbl_turn.text = "Turno: %s (%s)" % [SEAT_NAMES[current_player], who]
	else:
		lbl_turn.text = ""

	if board.is_empty():
		lbl_ends.text = "Mesa vacía — se espera la ficha inicial"
	else:
		lbl_ends.text = "Puntas abiertas: %d  —  %d" % [left_end, right_end]


# El pase es automático (ver _proceed_turn) para que el juego nunca se quede
# esperando un clic que no llega; esto solo informa el estado del turno.
func _update_pass_status() -> void:
	if phase != Phase.PLAYING or current_player != HUMAN_SEAT:
		pass_status.text = ""
	elif _legal_moves_for(HUMAN_SEAT).is_empty():
		pass_status.text = "Sin fichas jugables: pasando…"
	else:
		pass_status.text = "Tienes ficha jugable: debes jugarla"


func _log(msg: String) -> void:
	log_rt.append_text(msg + "\n")
