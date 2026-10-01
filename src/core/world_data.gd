class_name WorldData
extends RefCounted

var grid: MapGrid
var islands: Array[IslandData] = []
var island_count: int = 0

var all_ports: Array[PortRef] = []
var all_port_count: int = 0

var discovered_ports: PackedByteArray = PackedByteArray()
var discovered_count: int = 0
var discovered_islands: Array[bool] = []
var discovered_island_count: int = 0

var log_entries: Array = []
var log_count: int = 0

var spawn_island: int = -1

var money: float = GameRules.START_MONEY
var game_won: bool = false
var total_earned: float = 0.0

func load_all() -> void:
	var t0 := Time.get_ticks_msec()

	grid = CsvLoader.load_map("map.csv")
	print("[world] map.csv %dx%d in %d ms" % [grid.width, grid.height, Time.get_ticks_msec() - t0])

	t0 = Time.get_ticks_msec()
	islands = CsvLoader.load_islands("islands.csv", grid)
	island_count = islands.size()
	print("[world] islands.csv %d islands in %d ms" % [island_count, Time.get_ticks_msec() - t0])

	t0 = Time.get_ticks_msec()
	CsvLoader.apply_metadata(islands, CsvLoader.load_metadata("metadata.csv"))
	CsvLoader.load_ports("ports.csv", islands)
	print("[world] ports.csv in %d ms" % [Time.get_ticks_msec() - t0])

	_build_port_index()
	_init_discovery()

func _build_port_index() -> void:
	all_ports.clear()
	for i in range(island_count):
		var isl := islands[i]
		for t in range(isl.tile_count):
			if not isl.tile_is_port(t):
				continue
			if all_ports.size() >= GameDefs.MAX_PORTS:
				push_error("Too many ports, increase MAX_PORTS")
				return
			var p := PortRef.new()
			p.island_idx = i
			p.tile_idx = t
			p.x = float(isl.tile_gx(t)) * GameDefs.TILE_SIZE + GameDefs.TILE_SIZE / 2.0
			p.y = float(isl.tile_gy(t)) * GameDefs.TILE_SIZE + GameDefs.TILE_SIZE / 2.0
			all_ports.append(p)
	all_port_count = all_ports.size()

func _init_discovery() -> void:
	discovered_ports = PackedByteArray()
	discovered_ports.resize(all_port_count)
	discovered_islands = []
	discovered_islands.resize(island_count)
	for i in range(island_count):
		discovered_islands[i] = false

	spawn_island = -1
	for i in range(island_count):
		if islands[i].production == GameDefs.ResourceType.PORT:
			spawn_island = i
			break
	if spawn_island < 0 and island_count > 0:
		spawn_island = 0

	if spawn_island >= 0:
		discover_island(spawn_island)
		for i in range(all_port_count):
			if all_ports[i].island_idx == spawn_island:
				discovered_ports[i] = 1
				discovered_count += 1
		islands[spawn_island].warehouse = GameRules.SPAWN_STARTING_STOCK

func produce(days: float) -> void:
	for i in range(island_count):
		var isl := islands[i]
		if isl.production == GameDefs.ResourceType.PORT:
			continue
		isl.warehouse = minf(isl.warehouse + isl.rate * days, isl.max_ware)

func sell(resource_type: int, amount: float) -> float:
	var earned := amount * GameRules.price_of(resource_type)
	money += earned
	total_earned += earned
	return earned

func nearest_supplier(from: Vector2, exclude_island: int) -> int:
	var best := -1
	var best_dist := INF
	for i in range(island_count):
		var isl := islands[i]
		if i == exclude_island:
			continue
		if isl.production == GameDefs.ResourceType.PORT:
			continue
		if isl.warehouse < GameRules.MIN_STOCK_TO_SAIL:
			continue
		var dist := isl.pos.distance_squared_to(from)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best

func nearest_consumer(from: Vector2, resource_type: int) -> int:
	var best := -1
	var best_dist := INF
	for i in range(island_count):
		var isl := islands[i]
		if isl.production == GameDefs.ResourceType.PORT:
			continue
		if isl.production == resource_type:
			continue
		var dist := isl.pos.distance_squared_to(from)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best

func buy_ship(ship_type: int) -> bool:
	var price := GameRules.ship_price(ship_type)
	if price > money:
		return false
	money -= price
	return true

func is_coast(gx: int, gy: int) -> bool:
	return (
		grid.is_water(gx + 1, gy)
		or grid.is_water(gx - 1, gy)
		or grid.is_water(gx, gy + 1)
		or grid.is_water(gx, gy - 1)
	)

func is_port_discovered(idx: int) -> bool:
	if idx < 0 or idx >= all_port_count:
		return false
	return discovered_ports[idx] != 0

func discover_port(idx: int, day: float) -> bool:
	if idx < 0 or idx >= all_port_count:
		return false
	if discovered_ports[idx] != 0:
		return false
	discovered_ports[idx] = 1
	discovered_count += 1
	var island_idx := all_ports[idx].island_idx
	if island_idx >= 0 and island_idx < island_count:
		discover_island(island_idx)
		var isl := islands[island_idx]
		push_log("Discovered %s (%s)" % [isl.name, GameDefs.RESOURCE_NAMES[isl.production]], day)
	return true

func discover_island(idx: int) -> void:
	if idx < 0 or idx >= island_count:
		return
	if discovered_islands[idx]:
		return
	discovered_islands[idx] = true
	discovered_island_count += 1

func undiscovered_non_port_island_count() -> int:
	var n := 0
	for i in range(island_count):
		if not discovered_islands[i] and islands[i].production != GameDefs.ResourceType.PORT:
			n += 1
	return n

func push_log(msg: String, day: float) -> void:
	log_entries.append({"msg": msg, "time": day})
	if log_entries.size() > GameDefs.MAX_LOG:
		log_entries.pop_front()
	log_count = log_entries.size()

func recent_log(count: int) -> Array:
	var out := []
	var total := log_entries.size()
	if total == 0:
		return out
	var show := mini(total, count)
	for i in range(show):
		out.append(log_entries[total - 1 - i])
	return out
