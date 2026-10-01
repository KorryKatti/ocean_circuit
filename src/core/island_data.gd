class_name IslandData
extends RefCounted

var id: int = 0
var pos: Vector2 = Vector2.ZERO
var name: String = ""
var production: int = GameDefs.ResourceType.ORE
var rate: float = 0.0
var warehouse: float = 0.0
var max_ware: float = 0.0
var dock_level: int = 0
var radius: float = 0.0
var tiles: PackedInt32Array = PackedInt32Array()
var tile_count: int = 0
var port_count: int = 0
var is_port: PackedByteArray = PackedByteArray()

func tile_gx(t: int) -> int:
	return tiles[t * 2]

func tile_gy(t: int) -> int:
	return tiles[t * 2 + 1]

func tile_is_port(t: int) -> bool:
	return is_port[t] != 0

func mark_port(t: int) -> void:
	is_port[t] = 1
	port_count += 1

func add_tile(gx: int, gy: int) -> void:
	tiles.append(gx)
	tiles.append(gy)
	is_port.append(0)
	tile_count += 1

func compute_bounds() -> void:
	if tile_count == 0:
		return
	var min_x := tile_gx(0)
	var max_x := min_x
	var min_y := tile_gy(0)
	var max_y := min_y
	for t in range(1, tile_count):
		var tx := tile_gx(t)
		var ty := tile_gy(t)
		min_x = mini(min_x, tx)
		max_x = maxi(max_x, tx)
		min_y = mini(min_y, ty)
		max_y = maxi(max_y, ty)

	var ts := float(GameDefs.TILE_SIZE)
	pos = Vector2(
		float(min_x + max_x) / 2.0 * ts,
		float(min_y + max_y) / 2.0 * ts
	)
	radius = maxf(float(max_x - min_x), float(max_y - min_y)) / 2.0 * ts
