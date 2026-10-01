extends SceneTree

var scene: Node
var frame := 0


func _initialize() -> void:
	scene = load("res://src/world/main.tscn").instantiate()
	root.add_child(scene)


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 2:
		return false
	_run()
	return true


func _run() -> void:
	var world: WorldData = scene.world
	var ship: Ship = scene.ships[0]
	var player: Player = scene.player

	print("[smoke] islands=%d ports=%d" % [world.island_count, world.all_port_count])
	print("[smoke] player at %s" % str(player.position))
	print("[smoke] ship at %s state=%d (DOCKED=%d)" % [
		str(ship.position), ship.state, ShipTypes.State.DOCKED
	])
	print("[smoke] discovered before: %d ports / %d islands" % [
		world.discovered_count, world.discovered_island_count
	])

	print("[smoke] --- build_explore_route(k=3) ---")
	ship.build_explore_route(3)
	print("[smoke] waypoints=%d state=%d (SAILING=%d)" % [
		ship.waypoint_count, ship.state, ShipTypes.State.SAILING
	])
	for i in range(ship.waypoint_count):
		var wp = ship.waypoints[i]
		print("   wp %d -> %s  port=%d island=%d" % [
			i, str(wp.pos()), wp.all_port_idx, wp.island_idx
		])

	print("[smoke] --- simulating 120 s at 60 fps ---")
	var dt := 1.0 / 60.0
	for f in range(60 * 120):
		ship.tick(dt, float(f) * dt / 60.0)
		if f % (60 * 20) == 0 and f > 0:
			print("   t=%3ds pos=%s wp=%d/%d discovered=%d/%d islands=%d" % [
				f / 60, str(ship.position), ship.waypoint_idx, ship.waypoint_count,
				world.discovered_count, world.all_port_count, world.discovered_island_count
			])

	print("[smoke] discovered after k=3 run: %d ports / %d islands" % [
		world.discovered_count, world.discovered_island_count
	])
	print("[smoke] ship state=%d (IDLE=%d) waypoints=%d" % [
		ship.state, ShipTypes.State.IDLE, ship.waypoint_count
	])

	print("[smoke] --- build_explore_route(k=0) = all remaining ---")
	ship.build_explore_route(0)
	print("[smoke] waypoints=%d" % ship.waypoint_count)

	print("[smoke] --- radar from ship ---")
	var hits := ship.radar_from_ship(5)
	print("[smoke] radar hits=%d" % hits.size())
	for h in hits:
		print("   island %d dist=%.0f" % [h.island_id, h.distance])

	print("[smoke] --- ship_travel to island 23 ---")
	var far: IslandData = world.islands[23]
	var res := ship.ship_travel(far.pos)
	print("[smoke] dist=%.0f time=%.1fs fuel=%.0f can_reach=%s reason='%s'" % [
		res.distance, res.travel_time, res.fuel_needed, res.can_reach, res.reason
	])

	print("[smoke] --- log tail ---")
	for e in world.recent_log(6):
		print("   day %6.2f  %s" % [e["time"], e["msg"]])

	print("[smoke] OK")
