extends SceneTree

var scene: Node
var frame := 0


func _initialize() -> void:
	scene = load("res://src/world/main.tscn").instantiate()
	root.add_child(scene)


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	_run()
	return true


func _run() -> void:
	var world: WorldData = scene.world
	print("[eco] starting money=$%d  fleet=%d  win target=$%d" % [
		int(world.money), scene.ships.size(), int(GameRules.WIN_MONEY)
	])
	print("[eco] spawn stock=%.0f" % world.islands[world.spawn_island].warehouse)

	scene.time_scale_index = 3
	var step := 1.0 / 60.0
	var report_every := 60 * 20
	var total_frames := 60 * 60 * 4

	for f in range(total_frames):
		scene._process(step)
		if f % report_every == 0 and f > 0:
			var busy := 0
			var loaded := 0
			var deliveries := 0
			for s in scene.ships:
				if s.is_sailing():
					busy += 1
				if not s.is_empty():
					loaded += 1
				deliveries += s.deliveries
			print("  t=%4ds day=%5.1f  money=$%-7d earned=$%-7d sailing=%d loaded=%d deliveries=%d found=%d" % [
				f / 60, scene.time_day, int(world.money), int(world.total_earned),
				busy, loaded, deliveries, world.discovered_island_count
			])

	print("[eco] --- final ---")
	print("[eco] money=$%d  earned=$%d  won=%s" % [
		int(world.money), int(world.total_earned), world.game_won
	])
	var deliveries := 0
	for s in scene.ships:
		print("[eco]   %-20s cargo=%-14s deliveries=%d state=%d" % [
			ShipTypes.type_name(s.type), s.cargo_label(), s.deliveries, s.state
		])
		deliveries += s.deliveries

	var stocks := 0.0
	for i in range(world.island_count):
		stocks += world.islands[i].warehouse
	print("[eco] total island stock=%.0f" % stocks)

	print("[eco] --- log tail ---")
	for e in world.recent_log(8):
		print("   day %6.2f  %s" % [e["time"], e["msg"]])

	if world.total_earned <= 0.0:
		print("[eco] FAIL: nothing was ever delivered")
	elif deliveries <= 0:
		print("[eco] FAIL: no deliveries recorded")
	else:
		print("[eco] OK")
