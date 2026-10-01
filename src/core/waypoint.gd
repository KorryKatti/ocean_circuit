class_name Waypoint
extends RefCounted

var x: float = 0.0
var y: float = 0.0
var all_port_idx: int = -1
var island_idx: int = -1

func _init(p_x: float = 0.0, p_y: float = 0.0, p_port: int = -1, p_island: int = -1) -> void:
	x = p_x
	y = p_y
	all_port_idx = p_port
	island_idx = p_island

func pos() -> Vector2:
	return Vector2(x, y)
