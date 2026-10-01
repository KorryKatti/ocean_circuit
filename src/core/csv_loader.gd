class_name CsvLoader
extends RefCounted

static func data_dir() -> String:
	return ProjectSettings.globalize_path("res://data")

static func _open(file_name: String) -> FileAccess:
	var path := data_dir().path_join(file_name)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Could not open %s (err %d)" % [path, FileAccess.get_open_error()])
	return f

static func _lines_without_header(f: FileAccess) -> PackedStringArray:
	var out := PackedStringArray()
	var first := true
	while not f.eof_reached():
		var line := f.get_line()
		if first:
			first = false
			continue
		if not line.is_empty():
			out.append(line)
	return out

static func load_map(file_name: String) -> MapGrid:
	var grid := MapGrid.new()
	var f := _open(file_name)
	if f == null:
		return grid

	var raw := f.get_as_text()
	var lines := raw.split("\n", false)
	f = null

	grid.rows.resize(lines.size())
	for i in range(lines.size()):
		grid.rows[i] = lines[i].replace(",", "").replace("\r", "")

	grid.width = GameDefs.MAP_WIDTH
	grid.height = mini(grid.rows.size(), GameDefs.MAP_HEIGHT)
	if grid.rows.size() < grid.height:
		grid.rows.resize(grid.height)
		for i in range(grid.rows.size(), grid.height):
			grid.rows[i] = ""
	return grid

static func load_islands(file_name: String, grid: MapGrid) -> Array[IslandData]:
	var islands: Array[IslandData] = []
	var f := _open(file_name)
	if f == null:
		return islands

	var max_id := -1
	var lines := _lines_without_header(f)
	f = null

	for line in lines:
		var parts := line.split(",", false, 3)
		if parts.size() < 3:
			continue
		var island_id := int(parts[0])
		var px := int(parts[1])
		var gy := int(parts[2])
		if island_id < 0 or island_id >= GameDefs.MAX_ISLANDS:
			continue
		if px < 0 or px >= grid.width or gy < 0 or gy >= grid.height:
			continue

		if island_id > max_id:
			for i in range(islands.size(), island_id + 1):
				islands.append(IslandData.new())
			max_id = island_id

		var isl := islands[island_id]
		if isl.tile_count == 0:
			isl.id = island_id
			isl.production = GameDefs.resource_from_char(grid.char_at(px, gy))
		if isl.tile_count < GameDefs.MAX_TILES:
			isl.add_tile(px, gy)

	for isl in islands:
		isl.compute_bounds()
	return islands

static func load_metadata(file_name: String) -> Array[IslandMeta]:
	var metas: Array[IslandMeta] = []
	var f := _open(file_name)
	if f == null:
		return metas

	var lines := _lines_without_header(f)
	f = null

	for line in lines:
		var parts := line.split(",", false, 9)
		if parts.size() < 8:
			continue
		var m := IslandMeta.new()
		m.id = int(parts[0])
		m.name = parts[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
		if parts[2].length() > 0:
			m.production = GameDefs.resource_from_char(parts[2].unicode_at(0))
		m.rate = parts[4].to_float()
		m.max_ware = parts[5].to_float()
		m.dock_level = int(parts[6])
		m.tile_count = int(parts[7])
		if parts.size() >= 9:
			m.port_count = int(parts[8])
		metas.append(m)
	return metas

static func apply_metadata(islands: Array[IslandData], metas: Array[IslandMeta]) -> void:
	for m in metas:
		if m.id < 0 or m.id >= islands.size():
			continue
		var isl := islands[m.id]
		isl.production = m.production
		isl.rate = m.rate
		isl.max_ware = m.max_ware
		isl.dock_level = m.dock_level
		isl.name = m.name

static func load_ports(file_name: String, islands: Array[IslandData]) -> void:
	var f := _open(file_name)
	if f == null:
		return

	var lines := _lines_without_header(f)
	f = null

	var wanted := {}
	for line in lines:
		var parts := line.split(",", false, 3)
		if parts.size() < 3:
			continue
		var island_id := int(parts[0])
		var px := int(parts[1])
		var gy := int(parts[2])
		if island_id < 0 or island_id >= islands.size():
			continue
		if px < 0 or px >= GameDefs.MAP_WIDTH or gy < 0 or gy >= GameDefs.MAP_HEIGHT:
			continue
		wanted[Vector3i(island_id, px, gy)] = true

	for island_id in range(islands.size()):
		var isl := islands[island_id]
		for t in range(isl.tile_count):
			if wanted.has(Vector3i(island_id, isl.tile_gx(t), isl.tile_gy(t))):
				isl.mark_port(t)
