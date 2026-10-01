class_name Main
extends Node2D

const SHIP_POS_INTERVAL := 5.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 1.5

enum CamMode { PLAYER, SHIP, FREE }
const PAN_SPEED := 900.0
const DRAG_THRESHOLD := 6.0
const HUD_REFRESH_INTERVAL := 0.1

var world: WorldData
var player: Player
var ships: Array[Ship] = []
var selected_ship: int = 0
var camera: Camera2D
var water: Water
var renderer: IslandRenderer
var hud: HUD

var cam_mode: int = CamMode.PLAYER
var selected: int = -1
var time_day: float = 0.0
var time_scale_index: int = 1
var ship_timer: float = 0.0
var hud_timer: float = 0.0

var ship_pos_timer: float = 0.0
var sailing_grid: Array[Vector2i] = []
var _last_discovered_island_count: int = -1

var _dragging: bool = false
var _drag_moved: float = 0.0

func _ready() -> void:
	world = WorldData.new()
	world.load_all()

	_setup_world_nodes()
	_spawn_actors()
	_setup_camera()
	_setup_hud()

func _setup_world_nodes() -> void:
	water = Water.new()
	water.z_index = -10
	water.setup(load("res://assets/img/sea_texture.png"))
	add_child(water)

	renderer = IslandRenderer.new()
	add_child(renderer)
	renderer.setup(world)

func _spawn_actors() -> void:
	var spawn_island := world.spawn_island

	player = Player.new()
	player.setup(world)
	add_child(player)

	add_ship(ShipTypes.Type.SMALL_CARGO_SHIP)
	if world.buy_ship(ShipTypes.Type.SMALL_CARGO_SHIP):
		add_ship(ShipTypes.Type.SMALL_CARGO_SHIP)

	if spawn_island < 0:
		return

	var isl := world.islands[spawn_island]
	if isl.tile_count > 0:
		player.position = Vector2(
			float(isl.tile_gx(0)) * GameDefs.TILE_SIZE + GameDefs.TILE_SIZE / 2.0,
			float(isl.tile_gy(0)) * GameDefs.TILE_SIZE + GameDefs.TILE_SIZE / 2.0
		)

	var spawn_point := _first_water_next_to_port(isl)
	if spawn_point != Vector2.ZERO:
		ships[0].position = spawn_point
		ships[0].state = ShipTypes.State.DOCKED

func _first_water_next_to_port(isl: IslandData) -> Vector2:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for t in range(isl.tile_count):
		if not isl.tile_is_port(t):
			continue
		for d in dirs:
			var wgx := isl.tile_gx(t) + d.x
			var wgy := isl.tile_gy(t) + d.y
			if world.grid.is_water(wgx, wgy):
				return Vector2(
					float(wgx) * GameDefs.TILE_SIZE + GameDefs.TILE_SIZE / 2.0,
					float(wgy) * GameDefs.TILE_SIZE + GameDefs.TILE_SIZE / 2.0
				)
	return Vector2.ZERO

func add_ship(ship_type: int) -> Ship:
	var s := Ship.new()
	s.setup(world, ship_type)
	s.configure_sprite(load("res://assets/img/ship.png"))
	s.z_index = 5
	if ships.size() > 0:
		s.position = ships[0].position + Vector2(24.0 * ships.size(), 0.0)
		s.state = ShipTypes.State.IDLE
	add_child(s)
	ships.append(s)
	return s

func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(0.5, 0.5)
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()

func _setup_hud() -> void:
	hud = HUD.new()
	add_child(hud)
	hud.camera_toggled.connect(_on_camera_toggled)
	hud.explore_requested.connect(_on_explore_requested)
	hud.stop_requested.connect(_on_stop_requested)
	hud.recall_requested.connect(_on_recall_requested)
	hud.buy_ship_requested.connect(_on_buy_ship_requested)
	hud.time_scale_requested.connect(_on_time_scale_requested)
	hud.next_ship_requested.connect(_on_next_ship_requested)
	hud.refresh(self)

# ---------------------------------------------------------------------------
# Frame loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var scale: float = GameRules.TIME_SCALES[time_scale_index]
	if world.game_won:
		scale = 0.0

	var days := delta * GameRules.DAYS_PER_SECOND * scale
	time_day += days
	world.produce(days)

	if scale > 0.0:
		player.tick(delta)

	for s in ships:
		s.tick(delta * scale, time_day)
		if not s.is_sailing():
			s.assign_trade_route()

	_pan_with_keys(delta)
	_update_camera()
	water.view_rect = _visible_world_rect()
	water.tick(delta)

	ship_timer += delta
	if ship_timer >= SHIP_POS_INTERVAL:
		ship_timer = 0.0
		_recompute_sailing_grid()

	if world.discovered_island_count != _last_discovered_island_count:
		_last_discovered_island_count = world.discovered_island_count
		renderer.refresh_colors()

	if not world.game_won and world.money >= GameRules.WIN_MONEY:
		world.game_won = true
		world.push_log("You reached $%d. You win!" % int(GameRules.WIN_MONEY), time_day)

	hud_timer += delta
	if hud_timer >= HUD_REFRESH_INTERVAL:
		hud_timer = 0.0
		hud.refresh(self)

func _visible_world_rect() -> Rect2:
	var view := get_viewport_rect().size
	var z := camera.zoom.x
	return Rect2(camera.position - view / (2.0 * z), view / z)

func _update_camera() -> void:
	match cam_mode:
		CamMode.PLAYER:
			camera.position = player.position
		CamMode.SHIP:
			camera.position = ships[selected_ship].position

func _pan_with_keys(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("ui_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("ui_right"):
		dir.x += 1.0
	if Input.is_action_pressed("ui_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("ui_down"):
		dir.y += 1.0
	if dir == Vector2.ZERO:
		return
	cam_mode = CamMode.FREE
	camera.position += dir.normalized() * PAN_SPEED * delta / camera.zoom.x

func _recompute_sailing_grid() -> void:
	sailing_grid.clear()
	var ts := float(GameDefs.TILE_SIZE)
	for s in ships:
		if s.is_sailing():
			sailing_grid.append(Vector2i(int(s.position.x / ts), int(s.position.y / ts)))

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _dragging:
		_handle_drag(event as InputEventMouseMotion)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.keycode)

func _handle_key(key: int) -> void:
	match key:
		KEY_C:
			_on_camera_toggled()
		KEY_SPACE:
			_on_time_scale_requested(0 if time_scale_index != 0 else 1)
		KEY_1:
			_on_time_scale_requested(1)
		KEY_2:
			_on_time_scale_requested(2)
		KEY_3:
			_on_time_scale_requested(3)
		KEY_TAB:
			_on_next_ship_requested(1)
		KEY_B:
			_on_buy_ship_requested(ShipTypes.Type.SMALL_CARGO_SHIP)

func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		_set_zoom(camera.zoom.x + 0.05)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		_set_zoom(camera.zoom.x - 0.05)
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_dragging = true
			_drag_moved = 0.0
		else:
			_dragging = false
			if _drag_moved < DRAG_THRESHOLD:
				_handle_click(get_global_mouse_position())

func _handle_drag(mm: InputEventMouseMotion) -> void:
	_drag_moved += mm.relative.length()
	cam_mode = CamMode.FREE
	camera.position -= mm.relative / camera.zoom.x

func _set_zoom(z: float) -> void:
	camera.zoom = Vector2.ONE * clampf(z, ZOOM_MIN, ZOOM_MAX)

func _handle_click(world_pos: Vector2) -> void:
	var ship_idx := _ship_at(world_pos)
	if ship_idx >= 0:
		selected_ship = ship_idx
		selected = -2
		renderer.set_selected(-1)
		hud.refresh(self)
		return

	selected = renderer.island_at(world_pos)
	renderer.set_selected(selected)
	if selected >= 0:
		for s in ships:
			s.preferred_island = -1
		ships[selected_ship].preferred_island = selected
	hud.refresh(self)

func _ship_at(world_pos: Vector2) -> int:
	for i in range(ships.size()):
		var s := ships[i]
		if s.texture == null:
			continue
		var hit_size := s.texture.get_size() * s.scale
		if Rect2(s.position - hit_size / 2.0, hit_size).has_point(world_pos):
			return i
	return -1

# ---------------------------------------------------------------------------
# HUD callbacks
# ---------------------------------------------------------------------------

func _on_camera_toggled() -> void:
	cam_mode = CamMode.SHIP if cam_mode == CamMode.PLAYER else CamMode.PLAYER
	_update_camera()
	hud.refresh(self)

func _on_explore_requested(k: int) -> void:
	ships[selected_ship].build_explore_route(k)
	hud.refresh(self)

func _on_stop_requested() -> void:
	var s := ships[selected_ship]
	s.reset_waypoints()
	s.state = ShipTypes.State.IDLE
	hud.refresh(self)

func _on_recall_requested() -> void:
	ships[selected_ship].recall_home()
	hud.refresh(self)

func _on_buy_ship_requested(ship_type: int) -> void:
	if world.buy_ship(ship_type):
		add_ship(ship_type)
	hud.refresh(self)

func _on_time_scale_requested(index: int) -> void:
	time_scale_index = clampi(index, 0, GameRules.TIME_SCALES.size() - 1)
	hud.refresh(self)

func _on_next_ship_requested(step: int) -> void:
	selected_ship = posmod(selected_ship + step, ships.size())
	selected = -2
	hud.refresh(self)
