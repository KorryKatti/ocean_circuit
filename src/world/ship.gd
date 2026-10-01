class_name Ship
extends Sprite2D

const ARRIVE_EPSILON := 8.0
const SHIP_DRAW_HEIGHT := 256.0

var world: WorldData
var type: int = ShipTypes.Type.EXPLORER_SHIP
var state: int = ShipTypes.State.IDLE
var health: float = 0.0
var value: float = 0.0
var speed: float = 0.0

var dest: Vector2 = Vector2.ZERO
var waypoints: Array[Waypoint] = []
var waypoint_count: int = 0
var waypoint_idx: int = 0
var dock_wait: float = 0.0

var cargo_type: int = -1
var cargo: float = 0.0
var deliveries: int = 0
var preferred_island: int = -1

func cargo_space() -> float:
	return ShipTypes.stat(type, ShipTypes.CARGO_SPACE)

func is_empty() -> bool:
	return cargo <= 0.0

func cargo_label() -> String:
	if is_empty():
		return "empty"
	return "%.0f %s" % [cargo, GameDefs.RESOURCE_NAMES[cargo_type]]

func setup(p_world: WorldData, p_type: int) -> void:
	world = p_world
	type = p_type
	health = ShipTypes.health_of(type)
	value = ShipTypes.value_of(type)
	speed = ShipTypes.speed_of(type)

func configure_sprite(tex: Texture2D) -> void:
	texture = tex
	centered = true
	var h := float(tex.get_height())
	var w := float(tex.get_width())
	if h > 0.0:
		var s := SHIP_DRAW_HEIGHT / h
		scale = Vector2(s, s)

func reset_waypoints() -> void:
	waypoints.clear()
	waypoint_count = 0
	waypoint_idx = 0
	dock_wait = 0.0

func is_sailing() -> bool:
	return state == ShipTypes.State.SAILING

# ---------------------------------------------------------------------------
# Route generation
# ---------------------------------------------------------------------------

func build_explore_route(k: int) -> void:
	reset_waypoints()
	if world == null:
		return

	var candidate_island: Array[int] = []
	var candidate_port: Array[int] = []
	var island_seen := {}

	for i in range(world.all_port_count):
		if world.is_port_discovered(i):
			continue
		var iid := world.all_ports[i].island_idx
		if iid < 0 or iid >= world.island_count:
			continue
		if world.discovered_islands[iid]:
			continue
		if world.islands[iid].production == GameDefs.ResourceType.PORT:
			continue
		if island_seen.has(iid):
			continue
		island_seen[iid] = true
		candidate_island.append(iid)
		candidate_port.append(i)

	if candidate_island.is_empty():
		return

	for c in range(candidate_island.size()):
		var iid := candidate_island[c]
		var best_port_idx := candidate_port[c]
		var best := world.all_ports[best_port_idx].pos().distance_squared_to(position)
		for i in range(world.all_port_count):
			if world.is_port_discovered(i):
				continue
			if world.all_ports[i].island_idx != iid:
				continue
			var d := world.all_ports[i].pos().distance_squared_to(position)
			if d < best:
				best = d
				best_port_idx = i
		candidate_port[c] = best_port_idx

	if k > 0 and k < candidate_island.size():
		var order := range(candidate_island.size())
		order.sort_custom(func(a: int, b: int) -> bool:
			var pa := world.all_ports[candidate_port[a]].pos()
			var pb := world.all_ports[candidate_port[b]].pos()
			return pa.distance_squared_to(position) < pb.distance_squared_to(position)
		)
		var kept_islands: Array[int] = []
		var kept_ports: Array[int] = []
		for c in order.slice(0, k):
			kept_islands.append(candidate_island[c])
			kept_ports.append(candidate_port[c])
		candidate_island = kept_islands
		candidate_port = kept_ports

	var used := {}
	var visited := 0
	var cursor := position
	while visited < candidate_island.size():
		var best_c := -1
		var best_d := INF
		for c in range(candidate_island.size()):
			if used.has(c):
				continue
			var d := world.all_ports[candidate_port[c]].pos().distance_squared_to(cursor)
			if d < best_d:
				best_d = d
				best_c = c
		if best_c < 0:
			break

		used[best_c] = true
		var port_pos := world.all_ports[candidate_port[best_c]].pos()
		var wp_pos := world.grid.find_water_near(port_pos.x, port_pos.y)

		waypoints.append(Waypoint.new(wp_pos.x, wp_pos.y, candidate_port[best_c], candidate_island[best_c]))
		waypoint_count += 1
		cursor = wp_pos
		visited += 1

	if waypoint_count > 0:
		waypoint_idx = 0
		dest = waypoints[0].pos()
		state = ShipTypes.State.SAILING

func recall_home() -> void:
	reset_waypoints()
	if world == null:
		return
	for i in range(world.all_port_count):
		if world.all_ports[i].island_idx == 0:
			dest = world.all_ports[i].pos()
			state = ShipTypes.State.SAILING
			return

# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func tick(delta: float, day: float) -> void:
	if state != ShipTypes.State.SAILING:
		return

	if dock_wait > 0.0:
		dock_wait -= delta
		return

	var delta_v := dest - position
	var dist := delta_v.length()

	if dist < ARRIVE_EPSILON:
		position = dest
		_on_arrival(day)
		return

	var step := minf(speed * delta, dist)
	position += delta_v / dist * step
	rotation = delta_v.angle() + PI / 2.0
	check_sensor_discovery(day)

func assign_trade_route() -> void:
	reset_waypoints()
	if world == null:
		return

	var source := -1
	if preferred_island >= 0 and preferred_island < world.island_count:
		source = preferred_island
	else:
		source = world.nearest_supplier(position, -1)
	preferred_island = -1

	if source < 0:
		return

	var load_port := _dock_port(world, source)
	if load_port < 0:
		return

	var resource: int = world.islands[source].production
	var target := world.nearest_consumer(world.islands[source].pos, resource)
	if target < 0:
		return

	var drop_port := _dock_port(world, target)
	if drop_port < 0:
		return

	var load_pos := world.grid.find_water_near(world.all_ports[load_port].x, world.all_ports[load_port].y)
	var drop_pos := world.grid.find_water_near(world.all_ports[drop_port].x, world.all_ports[drop_port].y)

	waypoints.append(Waypoint.new(load_pos.x, load_pos.y, -1, source))
	waypoints.append(Waypoint.new(drop_pos.x, drop_pos.y, -1, target))
	waypoint_count = 2
	waypoint_idx = 0
	dest = load_pos
	state = ShipTypes.State.SAILING

func _dock_port(w: WorldData, island_idx: int) -> int:
	for i in range(w.all_port_count):
		if w.all_ports[i].island_idx != island_idx:
			continue
		var p := w.all_ports[i]
		var water := w.grid.find_water_near(p.x, p.y)
		if water.distance_to(Vector2(p.x, p.y)) < float(GameDefs.TILE_SIZE) * 2.0:
			return i
	return -1

func _service_dock(day: float) -> void:
	var island_idx := -1
	if waypoint_idx < waypoint_count:
		island_idx = waypoints[waypoint_idx].island_idx
	if island_idx < 0 or island_idx >= world.island_count:
		return

	var isl := world.islands[island_idx]

	if is_empty():
		if isl.production == GameDefs.ResourceType.PORT:
			return
		var take := minf(cargo_space(), isl.warehouse)
		if take <= 0.0:
			return
		isl.warehouse -= take
		cargo = take
		cargo_type = isl.production
		return

	var sold_type := cargo_type
	var earned := world.sell(cargo_type, cargo)
	deliveries += 1
	cargo = 0.0
	cargo_type = -1
	world.push_log("Delivered %s to %s for $%d" % [
		GameDefs.RESOURCE_NAMES[sold_type], isl.name, int(earned)
	], day)

func _on_arrival(day: float) -> void:
	if waypoint_idx < waypoint_count:
		var wp := waypoints[waypoint_idx]
		_service_dock(day)
		if wp.all_port_idx >= 0:
			world.discover_port(wp.all_port_idx, day)
		waypoint_idx += 1

	if waypoint_idx < waypoint_count:
		dest = waypoints[waypoint_idx].pos()
		dock_wait = 1.5
	else:
		reset_waypoints()
		state = ShipTypes.State.IDLE

func check_sensor_discovery(day: float) -> void:
	if world == null or state != ShipTypes.State.SAILING:
		return
	var sq_range := ShipTypes.sensor_range_of(type) * ShipTypes.sensor_range_of(type)
	for i in range(world.all_port_count):
		if world.is_port_discovered(i):
			continue
		var port := world.all_ports[i]
		if port.island_idx >= 0 and port.island_idx < world.island_count:
			if world.islands[port.island_idx].production == GameDefs.ResourceType.PORT:
				continue
		if port.pos().distance_squared_to(position) <= sq_range:
			world.discover_port(i, day)

# ---------------------------------------------------------------------------
# Travel validation
# ---------------------------------------------------------------------------

func ship_travel(target: Vector2) -> TravelResult:
	var result := TravelResult.new()

	if state == ShipTypes.State.SAILING:
		result.reason = "ship is already sailing"
		return result

	var dist := target.distance_to(position)
	result.distance = dist

	if dist < 1.0:
		result.reason = "destination too close"
		return result

	if speed > 0.0:
		result.travel_time = dist / speed
	else:
		result.reason = "ship has zero speed"
		return result

	result.fuel_needed = dist / 10.0
	if result.fuel_needed > ShipTypes.fuel_capacity_of(type):
		result.reason = "not enough fuel capacity"
		return result

	result.can_reach = true
	return result

func ship_travel_go(target: Vector2) -> bool:
	var result := ship_travel(target)
	if not result.can_reach:
		return false
	dest = target
	state = ShipTypes.State.SAILING
	return true

# ---------------------------------------------------------------------------
# Radar
# ---------------------------------------------------------------------------

func _radar_from(src: Vector2, radius: float, k: int) -> Array[RadarHit]:
	var hits: Array[RadarHit] = []
	if world == null:
		return hits
	for i in range(world.island_count):
		var isl := world.islands[i]
		if isl.tile_count == 0:
			continue
		var dist := isl.pos.distance_to(src)
		if dist <= radius:
			hits.append(RadarHit.new())
			hits[hits.size() - 1].island_id = i
			hits[hits.size() - 1].distance = dist
			hits[hits.size() - 1].pos = isl.pos
	hits.sort_custom(func(a: RadarHit, b: RadarHit) -> bool: return a.distance < b.distance)
	if k > 0 and k < hits.size():
		hits.resize(k)
	return hits

func radar_from_ship(k: int) -> Array[RadarHit]:
	return _radar_from(position, ShipTypes.sensor_range_of(type), k)

func radar_from_player(player_pos: Vector2, range_px: float, k: int) -> Array[RadarHit]:
	return _radar_from(player_pos, range_px, k)
