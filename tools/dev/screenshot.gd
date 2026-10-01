extends SceneTree

var scene: Node
var frame := 0


func _initialize() -> void:
	scene = load("res://src/world/main.tscn").instantiate()
	root.add_child(scene)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 20:
		scene.selected_ship = 0
		scene.selected = -2
	if frame < 400:
		return false

	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("/tmp/opencode/shot.png")
	print("[shot] %dx%d money=$%d found=%d" % [
		img.get_width(), img.get_height(),
		int(scene.world.money),
		scene.world.discovered_island_count
	])
	return true
