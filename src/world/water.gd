class_name Water
extends Node2D

const SCROLL_X := 15.0
const SCROLL_Y := 10.0

var texture: Texture2D
var scroll: Vector2 = Vector2.ZERO
var view_rect: Rect2 = Rect2(0, 0, 1280, 720)

func setup(tex: Texture2D) -> void:
	texture = tex

func tick(delta: float) -> void:
	scroll.x += SCROLL_X * delta
	scroll.y += SCROLL_Y * delta
	var size := texture.get_size() if texture != null else Vector2.ONE
	if size.x > 0.0:
		scroll.x = fmod(scroll.x, size.x)
	if size.y > 0.0:
		scroll.y = fmod(scroll.y, size.y)
	queue_redraw()

func _draw() -> void:
	if texture == null:
		return

	var tile := texture.get_size()
	var start_x := int(floor(view_rect.position.x / tile.x)) - 1
	var start_y := int(floor(view_rect.position.y / tile.y)) - 1
	var end_x := int(ceil((view_rect.position.x + view_rect.size.x) / tile.x)) + 1
	var end_y := int(ceil((view_rect.position.y + view_rect.size.y) / tile.y)) + 1

	var tint := Color(0.62, 0.80, 0.98)
	for ix in range(start_x, end_x + 1):
		for iy in range(start_y, end_y + 1):
			var pos := Vector2(ix * tile.x, iy * tile.y) - scroll
			draw_texture(texture, pos, tint)
