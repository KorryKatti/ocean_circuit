class_name HUD
extends CanvasLayer

signal camera_toggled
signal explore_requested(k: int)
signal stop_requested
signal recall_requested
signal buy_ship_requested(ship_type: int)
signal time_scale_requested(index: int)
signal next_ship_requested(step: int)

const PANEL_WIDTH := 280.0
const LEFT_MARGIN := 10.0
const RIGHT_MARGIN := 310.0
const PANEL_GAP := 10.0

var explore_k: int = 0

var _info_labels: Dictionary = {}
var _camera_button: Button
var _speed_buttons: Array[Button] = []
var _buy_button: Button
var _fleet_label: Label
var _win_banner: PanelContainer
var _sailing_count_label: Label
var _sailing_list: VBoxContainer
var _island_panel: PanelContainer
var _island_labels: VBoxContainer
var _ship_panel: PanelContainer
var _ship_labels: VBoxContainer
var _explore_slider: HSlider
var _send_button: Button
var _stop_button: Button
var _recall_button: Button
var _discovered_count_label: Label
var _discovered_list: VBoxContainer
var _log_list: VBoxContainer

func _ready() -> void:
	layer = 10
	var left := _column(LEFT_MARGIN)
	var right := _column(RIGHT_MARGIN)
	_build_info(left)
	_build_sailing(left)
	_build_island(left)
	_build_ship(left)
	_build_discovered(right)
	_build_log(right)
	_build_win_banner()

func _build_win_banner() -> void:
	_win_banner = PanelContainer.new()
	_win_banner.position = Vector2(360, 520)
	_win_banner.visible = false
	add_child(_win_banner)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_win_banner.add_child(margin)

	var box := VBoxContainer.new()
	margin.add_child(box)

	var title := Label.new()
	title.text = "YOU WIN"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", GameDefs.TEXT_GOLD)
	box.add_child(title)

	var sub := Label.new()
	sub.name = "Sub"
	box.add_child(sub)

func _column(x: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.position = Vector2(x, LEFT_MARGIN)
	col.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", int(PANEL_GAP))
	add_child(col)
	return col

func _panel(parent: Node, title: String) -> Array:
	var panel := PanelContainer.new()
	parent.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	margin.add_child(box)

	if title != "":
		var header := Label.new()
		header.text = title
		header.add_theme_font_size_override("font_size", 15)
		header.add_theme_color_override("font_color", GameDefs.TEXT_HEADER)
		box.add_child(header)
		box.add_child(HSeparator.new())

	return [panel, box]

func _label(box: Node, key: String, color: Color = GameDefs.TEXT) -> Label:
	var l := Label.new()
	l.name = key
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l

func _clear(box: Node) -> void:
	for child in box.get_children():
		child.queue_free()

func _add_line(box: Node, text: String, color: Color = GameDefs.TEXT) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	box.add_child(l)

func _build_info(column: VBoxContainer) -> void:
	var res := _panel(column, "Ocean Circuit")
	var box: VBoxContainer = res[1]

	_info_labels["map"] = _label(box, "map")
	_info_labels["islands"] = _label(box, "islands")
	_info_labels["money"] = _label(box, "money", GameDefs.TEXT_GOOD)
	_info_labels["day"] = _label(box, "day")
	_info_labels["zoom"] = _label(box, "zoom")
	box.add_child(HSeparator.new())

	_camera_button = Button.new()
	_camera_button.custom_minimum_size = Vector2(PANEL_WIDTH - 34, 25)
	box.add_child(_camera_button)
	_camera_button.pressed.connect(func() -> void: camera_toggled.emit())

	var speed_row := HBoxContainer.new()
	box.add_child(speed_row)
	for i in range(GameRules.TIME_SCALES.size()):
		var b := Button.new()
		b.text = GameRules.time_scale_name(i)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var index := i
		b.pressed.connect(func() -> void: time_scale_requested.emit(index))
		speed_row.add_child(b)
		_speed_buttons.append(b)

	box.add_child(HSeparator.new())

	_fleet_label = _label(box, "fleet")
	_buy_button = Button.new()
	_buy_button.custom_minimum_size = Vector2(PANEL_WIDTH - 34, 26)
	_buy_button.pressed.connect(func() -> void:
		buy_ship_requested.emit(ShipTypes.Type.SMALL_CARGO_SHIP)
	)
	box.add_child(_buy_button)

	box.add_child(HSeparator.new())
	for line in [
		"WASD: move character",
		"Scroll: zoom, drag: pan",
		"Click: island or ship",
		"C: camera   TAB: next ship",
		"SPACE: pause   B: buy ship",
	]:
		var l := Label.new()
		l.text = line
		l.add_theme_color_override("font_color", GameDefs.TEXT_DIM)
		box.add_child(l)

func _build_sailing(column: VBoxContainer) -> void:
	var res := _panel(column, "Sailing Ships")
	var box: VBoxContainer = res[1]
	_sailing_count_label = _label(box, "count")
	box.add_child(HSeparator.new())
	_sailing_list = VBoxContainer.new()
	box.add_child(_sailing_list)

func _build_island(column: VBoxContainer) -> void:
	var res := _panel(column, "Island")
	_island_panel = res[0]
	_island_labels = res[1]
	_island_panel.visible = false

func _build_ship(column: VBoxContainer) -> void:
	var res := _panel(column, "Ship")
	_ship_panel = res[0]
	var box: VBoxContainer = res[1]

	_ship_labels = VBoxContainer.new()
	box.add_child(_ship_labels)
	box.add_child(HSeparator.new())

	var k_label := Label.new()
	k_label.text = "Islands to visit (0 = all):"
	k_label.add_theme_color_override("font_color", GameDefs.TEXT)
	box.add_child(k_label)

	_explore_slider = HSlider.new()
	_explore_slider.min_value = 0
	_explore_slider.max_value = 1
	_explore_slider.step = 1
	_explore_slider.custom_minimum_size = Vector2(PANEL_WIDTH - 34, 16)
	box.add_child(_explore_slider)

	var row := HBoxContainer.new()
	box.add_child(row)

	_send_button = Button.new()
	_send_button.text = "Send to Explore"
	_send_button.custom_minimum_size = Vector2(200, 30)
	row.add_child(_send_button)
	_send_button.pressed.connect(func() -> void: explore_requested.emit(explore_k))

	_stop_button = Button.new()
	_stop_button.text = "Stop"
	_stop_button.custom_minimum_size = Vector2(90, 30)
	row.add_child(_stop_button)
	_stop_button.pressed.connect(func() -> void: stop_requested.emit())

	_recall_button = Button.new()
	_recall_button.text = "Recall"
	_recall_button.custom_minimum_size = Vector2(90, 30)
	row.add_child(_recall_button)
	_recall_button.pressed.connect(func() -> void: recall_requested.emit())

func _build_discovered(column: VBoxContainer) -> void:
	var res := _panel(column, "Discovered Islands")
	var box: VBoxContainer = res[1]
	_discovered_count_label = _label(box, "count")
	box.add_child(HSeparator.new())
	_discovered_list = VBoxContainer.new()
	box.add_child(_discovered_list)

func _build_log(column: VBoxContainer) -> void:
	var res := _panel(column, "Discovery Log")
	var box: VBoxContainer = res[1]
	_log_list = VBoxContainer.new()
	box.add_child(_log_list)

# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func refresh(main: Node) -> void:
	var world: WorldData = main.world
	if world == null:
		return

	_info_labels["map"].text = "Map: %dx%d" % [GameDefs.MAP_WIDTH, GameDefs.MAP_HEIGHT]
	_info_labels["islands"].text = "Islands: %d" % world.island_count
	_info_labels["money"].text = "Money: $%d / $%d" % [int(world.money), int(GameRules.WIN_MONEY)]
	_info_labels["day"].text = "Day: %.1f" % main.time_day
	_info_labels["zoom"].text = "Zoom: %.0f%%" % (main.camera.zoom.x * 100.0)
	_camera_button.text = "Camera: Ship" if main.cam_mode == 0 else "Camera: Player"

	for i in range(_speed_buttons.size()):
		_speed_buttons[i].disabled = i == main.time_scale_index

	var ships: Array = main.ships
	_fleet_label.text = "Fleet: %d ship(s)" % ships.size()
	var buy_price := GameRules.ship_price(ShipTypes.Type.SMALL_CARGO_SHIP)
	_buy_button.text = "Buy Cargo Ship  $%d" % int(buy_price)
	_buy_button.disabled = world.money < buy_price

	_win_banner.visible = world.game_won
	if world.game_won:
		var sub := _win_banner.find_child("Sub", true, false) as Label
		if sub != null:
			sub.text = "Net worth $%d with %d ships" % [int(world.money), ships.size()]

	_refresh_sailing(main)
	_refresh_island(main, world)
	_refresh_ship(main, world)
	_refresh_discovered(world)
	_refresh_log(world)

func _refresh_sailing(main: Node) -> void:
	var grid: Array = main.sailing_grid
	_sailing_count_label.text = "En route: %d" % grid.size()
	_clear(_sailing_list)
	for i in range(grid.size()):
		_add_line(_sailing_list, "#%d  grid(%d, %d)" % [i, grid[i].x, grid[i].y])

func _refresh_island(main: Node, world: WorldData) -> void:
	var idx: int = main.selected
	var show := idx >= 0 and idx < world.island_count
	_island_panel.visible = show
	_clear(_island_labels)
	if not show:
		return

	var isl := world.islands[idx]
	_add_line(_island_labels, "ID: %d | %s" % [isl.id, isl.name], GameDefs.WHITE)
	_island_labels.add_child(HSeparator.new())
	_add_line(_island_labels, "Produces: %s" % GameDefs.RESOURCE_NAMES[isl.production])
	_add_line(_island_labels, "Rate: %.1f/day" % isl.rate)
	_add_line(_island_labels, "Storage: %.0f / %.0f" % [isl.warehouse, isl.max_ware])
	_add_line(_island_labels, "Sells for: $%d / unit" % int(GameRules.price_of(isl.production)))
	_add_line(_island_labels, "Dock Level: %d" % isl.dock_level)
	_add_line(_island_labels, "Tiles: %d" % isl.tile_count)

	if isl.port_count > 0:
		_island_labels.add_child(HSeparator.new())
		_add_line(_island_labels, "Port Tiles: %d" % isl.port_count, GameDefs.TEXT_TEAL)
		_add_line(_island_labels, "Docks along the coast", GameDefs.TEXT_DIM)

func _refresh_ship(main: Node, world: WorldData) -> void:
	var ship: Ship = main.ships[main.selected_ship]
	var show: bool = main.selected == -2
	_ship_panel.visible = show
	if not show:
		return

	_clear(_ship_labels)

	var undiscovered := world.undiscovered_non_port_island_count()
	_explore_slider.max_value = maxi(undiscovered, 1)
	explore_k = clampi(explore_k, 0, undiscovered)
	_explore_slider.set_value_no_signal(explore_k)

	var busy := ship.waypoint_count > 0
	_send_button.visible = not busy
	_stop_button.visible = busy
	_recall_button.visible = busy

	_add_line(_ship_labels, "Ship %d/%d  %s" % [
		main.selected_ship + 1, main.ships.size(), ShipTypes.type_name(ship.type)
	], GameDefs.TEXT_PINK)
	_ship_labels.add_child(HSeparator.new())
	_add_line(_ship_labels, "Cargo: %s / %.0f" % [ship.cargo_label(), ship.cargo_space()])
	_add_line(_ship_labels, "Deliveries: %d" % ship.deliveries)
	_add_line(_ship_labels, "Speed: %.0f" % ship.speed)
	_add_line(_ship_labels, "Worth: $%d" % int(ShipTypes.value_of(ship.type)))
	_ship_labels.add_child(HSeparator.new())

	if busy:
		_add_line(_ship_labels, "Sailing leg %d / %d" % [ship.waypoint_idx + 1, ship.waypoint_count])
		if ship.waypoint_idx < ship.waypoint_count:
			var iid: int = ship.waypoints[ship.waypoint_idx].island_idx
			if iid >= 0 and iid < world.island_count:
				var isl := world.islands[iid]
				var text := "-> %s (%s)" % [isl.name, GameDefs.RESOURCE_NAMES[isl.production]]
				_add_line(_ship_labels, text, GameDefs.TEXT_DIM)
	else:
		_add_line(_ship_labels, "Status: Idle")

	_add_line(_ship_labels, "Islands: %d / %d" % [world.discovered_island_count, world.island_count])

	var fleet_row := HBoxContainer.new()
	_ship_labels.add_child(fleet_row)
	var prev := Button.new()
	prev.text = "<"
	prev.pressed.connect(func() -> void: next_ship_requested.emit(-1))
	fleet_row.add_child(prev)
	var next := Button.new()
	next.text = ">"
	next.pressed.connect(func() -> void: next_ship_requested.emit(1))
	fleet_row.add_child(next)

func _refresh_discovered(world: WorldData) -> void:
	var total := 0
	for i in range(world.island_count):
		if world.islands[i].production != GameDefs.ResourceType.PORT:
			total += 1
	_discovered_count_label.text = "%d / %d found" % [world.discovered_island_count, total]

	_clear(_discovered_list)
	for i in range(world.island_count):
		if not world.discovered_islands[i]:
			continue
		var isl := world.islands[i]
		if isl.production == GameDefs.ResourceType.PORT:
			continue
		_add_line(_discovered_list, isl.name, GameDefs.TEXT_TEAL)
		var detail := "  %s — rate %.1f" % [GameDefs.RESOURCE_NAMES[isl.production], isl.rate]
		_add_line(_discovered_list, detail, GameDefs.TEXT_DIM)

func _refresh_log(world: WorldData) -> void:
	_clear(_log_list)
	var entries := world.recent_log(10)
	if entries.is_empty():
		_add_line(_log_list, "No discoveries yet...", GameDefs.TEXT_DIM)
		return
	for e in entries:
		_add_line(_log_list, "Day %.1f" % e["time"], GameDefs.TEXT_GOLD)
		_add_line(_log_list, "  " + e["msg"], GameDefs.TEXT_DIM)
