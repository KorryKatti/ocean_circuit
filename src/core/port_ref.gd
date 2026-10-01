class_name PortRef
extends RefCounted

var island_idx: int = -1
var tile_idx: int = -1
var x: float = 0.0
var y: float = 0.0

func pos() -> Vector2:
	return Vector2(x, y)
