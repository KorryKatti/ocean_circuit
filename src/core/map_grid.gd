class_name MapGrid
extends RefCounted

var rows: PackedStringArray = PackedStringArray()
var width: int = 0
var height: int = 0

func char_at(gx: int, gy: int) -> int:
	if gx < 0 or gx >= width or gy < 0 or gy >= height:
		return GameDefs.WATER_CHAR
	return rows[gy].unicode_at(gx)

func is_water(gx: int, gy: int) -> bool:
	return char_at(gx, gy) == GameDefs.WATER_CHAR

func is_water_world(wx: float, wy: float) -> bool:
	var gx := int(wx / GameDefs.TILE_SIZE)
	var gy := int(wy / GameDefs.TILE_SIZE)
	return is_water(gx, gy)

func find_water_near(wx: float, wy: float) -> Vector2:
	var gx := int(wx / GameDefs.TILE_SIZE)
	var gy := int(wy / GameDefs.TILE_SIZE)
	for radius in range(30):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx != -radius and dx != radius and dy != -radius and dy != radius:
					continue
				var cx := gx + dx
				var cy := gy + dy
				if is_water(cx, cy):
					return Vector2(
						float(cx) * GameDefs.TILE_SIZE + GameDefs.TILE_SIZE / 2.0,
						float(cy) * GameDefs.TILE_SIZE + GameDefs.TILE_SIZE / 2.0
					)
	return Vector2(wx, wy)
