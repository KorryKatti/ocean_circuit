#+feature dynamic-literals
package main

// ships — Ship types, stats, movement, and rendering.

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

// ---------------------------------------------------------------------------
// Ship types and stats
// ---------------------------------------------------------------------------

ShipTypes :: enum {
	EXPLORER_SHIP,
	SMALL_CARGO_SHIP,
	MEDIUM_CARGO_SHIP,
	LARGE_CARGO_SHIP,
	ASSIST_SMALL_WAR_SHIP,
	ASSIST_MEDIUM_WAR_SHIP,
	ASSIST_LARGE_WAR_SHIP,
	EXPLORER_MEDIUM_SHIP,
	FISHING_SHIP,
	OIL_SHIP_SMALL,
	OIL_SHIP_MEDIUM,
	OIL_SHIP_LARGE,
	SUPPLIES_SMALL_SHIP,
	SUPPLIES_MEDIUM_SHIP,
	SUPPLIES_LARGE_SHIP,
	PATROL_BOARD,
	FRIGATE,
	DESTROYER,
	CRUISER,
	BATTLESHIP,
	PIRATE_SHIP_SMALL,   // cannot be owned by player
	PIRATE_SHIP_MEDIUM,  // cannot be owned by player
	PIRATE_SHIP_LARGE,   // cannot be owned by player
}

ShipStats :: struct {
	health:        f32,
	value:         f32,
	speed:         f32,
	cargo_space:   f32,
	fuel_capacity: f32,
	sensor_range:  f32,
}

ship_stats := map[ShipTypes]ShipStats {
	.EXPLORER_SHIP          = {100, 0, 180, 50, 100, 1000},
	.SMALL_CARGO_SHIP       = {140, 5_000, 120, 500, 900, 300},
	.MEDIUM_CARGO_SHIP      = {180, 18_000, 100, 1500, 1500, 400},
	.LARGE_CARGO_SHIP       = {240, 60_000, 70, 5000, 3000, 500},
	.ASSIST_SMALL_WAR_SHIP  = {300, 10_000, 140, 150, 10, 700},
	.ASSIST_MEDIUM_WAR_SHIP = {600, 35_000, 120, 300, 200, 800},
	.ASSIST_LARGE_WAR_SHIP  = {1000, 120_000, 100, 600, 300, 1000},
	.EXPLORER_MEDIUM_SHIP   = {170, 15_000, 160, 300, 200, 1200},
	.FISHING_SHIP           = {120, 0, 120, 800, 800, 250},
	.OIL_SHIP_SMALL         = {180, 50_000, 100, 2000, 1500, 300},
	.OIL_SHIP_MEDIUM        = {220, 150_000, 85, 6000, 3000, 350},
	.OIL_SHIP_LARGE         = {280, 500_000, 70, 15000, 6000, 400},
	.SUPPLIES_SMALL_SHIP    = {130, 8_000, 130, 700, 1000, 300},
	.SUPPLIES_MEDIUM_SHIP   = {170, 30_000, 110, 2500, 2000, 350},
	.SUPPLIES_LARGE_SHIP    = {220, 100_000, 90, 7000, 4000, 400},
	.PATROL_BOARD           = {220, 7_500, 150, 100, 90, 600},
	.FRIGATE                = {500, 80_000, 160, 250, 150, 900},
	.DESTROYER              = {900, 220_000, 140, 400, 250, 1000},
	.CRUISER                = {1500, 450_000, 120, 800, 400, 1200},
	.BATTLESHIP             = {2500, 1_000_000, 60, 1000, 800, 1500},
	.PIRATE_SHIP_SMALL      = {150, 0, 130, 300, 700, 400},
	.PIRATE_SHIP_MEDIUM     = {350, 0, 110, 800, 1500, 500},
	.PIRATE_SHIP_LARGE      = {700, 0, 90, 2000, 2500, 600},
}

// ---------------------------------------------------------------------------
// Ship state
// ---------------------------------------------------------------------------

ShipState :: enum {
	IDLE,
	SAILING,
	DOCKED,
}

MAX_SHIPS :: 64

Waypoint::struct {
	x:f32,
	y:f32,
	all_port_idx:int,
	island_idx:int,
}

Ship :: struct {
	x, y:            f32,
	speed:           f32,
	angle:           f32,
	type:            ShipTypes,
	health, value:   f32,
	state:           ShipState,
	dest_x, dest_y:  f32,
	waypoints:       [MAX_PORTS]Waypoint,
	waypoint_count:  int,
	waypoint_idx:    int,
	dock_wait:       f32,
}

// used to reset a ship's waypoints when it docks or is destroyed
reset_waypoints :: proc(ship: ^Ship) {
	ship.waypoint_count = 0
	ship.waypoint_idx = 0
	ship.dock_wait=0
}
// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------


// find_water_near finds the closest water tile to a world position.
// Used to set waypoints on water next to ports instead of on the port itself.
find_water_near :: proc(grid: ^MapGrid, wx, wy: f32) -> (rx, ry: f32) {
	gx := int(wx / f32(TILE_SIZE))
	gy := int(wy / f32(TILE_SIZE))

	// Spiral outward from the port tile to find nearest water
	for radius := 0; radius < 30; radius += 1 {
		for dy := -radius; dy <= radius; dy += 1 {
			for dx := -radius; dx <= radius; dx += 1 {
				// Only check tiles on the edge of the current radius
				if dx != -radius && dx != radius && dy != -radius && dy != radius {continue}
				cx := gx + dx
				cy := gy + dy
				if cx < 0 || cx >= grid.width || cy < 0 || cy >= grid.height {continue}
				if grid.cells[cy][cx] == '.' {
					return f32(cx) * f32(TILE_SIZE) + f32(TILE_SIZE) / 2,
					       f32(cy) * f32(TILE_SIZE) + f32(TILE_SIZE) / 2
				}
			}
		}
	}
	// Fallback: return original position
	return wx, wy
}

build_explore_route :: proc(app: ^App, ship: ^Ship, k: int) {
	reset_waypoints(ship)

	// 1. Collect unique islands that have at least one undiscovered port.
	//    For each such island, store the index of its nearest port to the ship.
	candidate_island: [MAX_ISLANDS]int   // island index
	candidate_port:   [MAX_ISLANDS]int   // best port index for that island
	candidate_count := 0
	island_seen: [MAX_ISLANDS]bool

	for i in 0 ..< app.all_port_count {
		if app.discovered_ports[i] {continue}
		port := app.all_ports[i]
		iid := port.island_idx
		if iid < 0 || iid >= app.island_count {continue}
		if app.discovered_islands[iid] {continue}
		if app.islands[iid].production == .PORT {continue}
		if island_seen[iid] {continue}
		island_seen[iid] = true

		candidate_island[candidate_count] = iid
		candidate_port[candidate_count] = i
		candidate_count += 1
	}
	if candidate_count == 0 {return}

	// For each candidate island, find the single closest port to the ship
	for c in 0 ..< candidate_count {
		iid := candidate_island[c]
		best_port_idx := candidate_port[c]
		best_dx := app.all_ports[best_port_idx].x - ship.x
		best_dy := app.all_ports[best_port_idx].y - ship.y
		best_dist := best_dx * best_dx + best_dy * best_dy

		for i in 0 ..< app.all_port_count {
			if app.discovered_ports[i] {continue}
			if app.all_ports[i].island_idx != iid {continue}
			dx := app.all_ports[i].x - ship.x
			dy := app.all_ports[i].y - ship.y
			d := dx * dx + dy * dy
			if d < best_dist {
				best_dist = d
				best_port_idx = i
			}
		}
		candidate_port[c] = best_port_idx
	}

	// 2. If k > 0, sort candidates by distance and keep first k
	if k > 0 && k < candidate_count {
		for i in 1 ..< candidate_count {
			key_pi := candidate_port[i]
			kdx := app.all_ports[key_pi].x - ship.x
			kdy := app.all_ports[key_pi].y - ship.y
			key_dist := kdx * kdx + kdy * kdy
			j := i - 1
			for j >= 0 {
				j_pi := candidate_port[j]
				jdx := app.all_ports[j_pi].x - ship.x
				jdy := app.all_ports[j_pi].y - ship.y
				j_dist := jdx * jdx + jdy * jdy
				if j_dist <= key_dist {break}
				candidate_port[j + 1] = candidate_port[j]
				candidate_island[j + 1] = candidate_island[j]
				j -= 1
			}
			candidate_port[j + 1] = key_pi
			candidate_island[j + 1] = candidate_island[i]
		}
		candidate_count = k
	}

	// 3. Nearest-neighbor ordering (greedy TSP)
	used: [MAX_ISLANDS]bool
	visited := 0
	cx, cy := ship.x, ship.y

	for visited < candidate_count {
		best_c := -1
		best_d: f32 = 1e30
		for c in 0 ..< candidate_count {
			if used[c] {continue}
			port := app.all_ports[candidate_port[c]]
			dx := port.x - cx
			dy := port.y - cy
			d := dx * dx + dy * dy
			if d < best_d {
				best_d = d
				best_c = c
			}
		}
		if best_c < 0 {break}

		used[best_c] = true
		port := app.all_ports[candidate_port[best_c]]

		// Snap waypoint to water tile next to port, not the port itself
		wp_x, wp_y := find_water_near(&app.grid, port.x, port.y)

		wp := &ship.waypoints[ship.waypoint_count]
		wp.x = wp_x
		wp.y = wp_y
		wp.all_port_idx = candidate_port[best_c]
		wp.island_idx = candidate_island[best_c]
		ship.waypoint_count += 1

		cx = wp_x
		cy = wp_y
		visited += 1
	}

	if ship.waypoint_count > 0 {
		ship.waypoint_idx = 0
		ship.dest_x = ship.waypoints[0].x
		ship.dest_y = ship.waypoints[0].y
		ship.state = .SAILING
	}
}



update_ship :: proc(app: ^App) {
	dt := rl.GetFrameTime()
	for i in 0 ..< MAX_SHIPS {
		ship := &app.ships[i]
		if ship.state != .SAILING {continue}

		if ship.dock_wait > 0 {
			ship.dock_wait -= dt
			continue
		}

		dx := ship.dest_x - ship.x
		dy := ship.dest_y - ship.y
		dist := math.sqrt(dx * dx + dy * dy)

		if dist < f32(TILE_SIZE) {
			ship.x = ship.dest_x
			ship.y = ship.dest_y

		if ship.waypoint_idx < ship.waypoint_count {
			wp := &ship.waypoints[ship.waypoint_idx]
			if wp.all_port_idx >= 0 && wp.all_port_idx < app.all_port_count {
				if !app.discovered_ports[wp.all_port_idx] {
					app.discovered_ports[wp.all_port_idx] = true
					app.discovered_count += 1
					if wp.island_idx >= 0 && wp.island_idx < app.island_count {
						if !app.discovered_islands[wp.island_idx] {
							app.discovered_islands[wp.island_idx] = true
							app.discovered_island_count += 1
						}
						island := &app.islands[wp.island_idx]
						msg := fmt.aprintf("Arrived at %s (%s)", get_name(island^), resource_names[island.production])
						push_log(app, msg, app.time_day)
						delete(msg, context.allocator)
					}
				}
			}
				ship.waypoint_idx += 1
			}

			if ship.waypoint_idx < ship.waypoint_count {
				ship.dest_x = ship.waypoints[ship.waypoint_idx].x
				ship.dest_y = ship.waypoints[ship.waypoint_idx].y
				ship.dock_wait = 1.5
			} else {
				reset_waypoints(ship)
				ship.state = .IDLE
			}
			continue
		}

		nx := dx / dist
		ny := dy / dist
		step := ship.speed * dt
		if step > dist {step = dist}
		ship.x += nx * step
		ship.y += ny * step
		ship.angle = math.atan2(ny, nx) * (180.0 / math.PI) + 90
		check_sensor_discovery(app, ship)
	}
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

draw_ship :: proc(app: ^App) {
	ship := &app.ships[0]
	tile_f := f32(TILE_SIZE)
	ship_w := tile_f * 3
	ship_h := tile_f * 8

	// Source rect: full texture
	src := rl.Rectangle{0, 0, f32(app.ship_tex.width), f32(app.ship_tex.height)}
	// Dest rect: offset to center the actual ship pixels within the texture
	ox := f32(8)   // nudge right
	oy := f32(20)  // nudge down (texture has more padding above ship)
	dest := rl.Rectangle{ship.x - ship_w / 2 + ox, ship.y - ship_h / 2 + oy, ship_w, ship_h}
	origin := rl.Vector2{ship_w / 2, ship_h / 2}

	rl.DrawTexturePro(app.ship_tex, src, dest, origin, ship.angle, rl.WHITE)
}

// ---------------------------------------------------------------------------
// Ship travel
// ---------------------------------------------------------------------------

TravelResult :: struct {
	distance:     f32,
	travel_time:  f32, // seconds at ship's current speed
	fuel_needed:  f32, // estimated fuel cost (distance / 10)
	can_reach:    bool,
	reason:       [64]u8,
	reason_len:   int,
}

// ship_travel calculates travel info for sending a ship to a destination.
// Pass world-space coordinates for dest_x/dest_y. The ship must be IDLE or DOCKED.
// Returns a TravelResult with distance, time, fuel estimate, and validity.
ship_travel :: proc(ship_id: int, dest_x, dest_y: f32, app: ^App) -> TravelResult {
	result: TravelResult

	if ship_id < 0 || ship_id >= MAX_SHIPS {
		set_reason(&result, "invalid ship id")
		return result
	}

	ship := &app.ships[ship_id]

	switch ship.state {
	case .SAILING:
		set_reason(&result, "ship is already sailing")
		return result
	case .DOCKED:
		// ok — can depart from dock
	case .IDLE:
		// ok — can depart from idle position
	case:
		set_reason(&result, "ship in unknown state")
		return result
	}

	stats := ship_stats[ship.type]

	dx := dest_x - ship.x
	dy := dest_y - ship.y
	dist := math.sqrt(dx * dx + dy * dy)

	result.distance = dist

	if dist < 1.0 {
		set_reason(&result, "destination too close")
		return result
	}

	// Travel time at current speed (seconds)
	if ship.speed > 0 {
		result.travel_time = dist / ship.speed
	} else {
		set_reason(&result, "ship has zero speed")
		return result
	}

	// Fuel estimate: distance / 10 as a simple heuristic
	// TODO: refine when fuel consumption mechanics are finalized
	result.fuel_needed = dist / 10.0
	if result.fuel_needed > stats.fuel_capacity {
		set_reason(&result, "not enough fuel capacity")
		return result
	}

	result.can_reach = true
	return result
}

// ship_travel_go is a convenience wrapper that also sets the ship's destination
// and changes its state to SAILING. Returns false if the ship cannot travel.
ship_travel_go :: proc(ship_id: int, dest_x, dest_y: f32, app: ^App) -> bool {
	result := ship_travel(ship_id, dest_x, dest_y, app)
	if !result.can_reach {return false}

	ship := &app.ships[ship_id]
	ship.dest_x = dest_x
	ship.dest_y = dest_y
	ship.state = .SAILING
	return true
}

set_reason :: proc(r: ^TravelResult, msg: string) {
	n := min(len(msg), 63)
	for j in 0 ..< n {
		r.reason[j] = msg[j]
	}
	r.reason_len = n
}

// ---------------------------------------------------------------------------
// Radar — detect nearby islands
// ---------------------------------------------------------------------------

RadarHit :: struct {
	island_id: int,
	distance:  f32,
	x:         f32,
	y:         f32,
}

MAX_RADAR_HITS :: 64

// radar finds islands within range of a world-space position.
// Pass ship_id >= 0 to use that ship's sensor_range as the radius,
// or pass ship_id = -1 to use your own range_f32 value.
// k limits the number of results (0 or negative = no limit).
// Returns the number of hits written to out_hits.
radar :: proc(
	src_x, src_y: f32,
	ship_id: int,
	range_f32: f32,
	k: int,
	app: ^App,
	out_hits: []RadarHit,
) -> int {
	// Determine search radius
	radius := range_f32
	if ship_id >= 0 && ship_id < MAX_SHIPS {
		stats := ship_stats[app.ships[ship_id].type]
		radius = stats.sensor_range
	}

	hit_count := 0
	for i in 0 ..< app.island_count {
		island := &app.islands[i]
		if island.tile_count == 0 {continue}

		dx := island.pos.x - src_x
		dy := island.pos.y - src_y
		dist := math.sqrt(dx * dx + dy * dy)

		if dist <= radius {
			if hit_count < len(out_hits) {
				out_hits[hit_count] = {i, dist, island.pos.x, island.pos.y}
				hit_count += 1
			}
		}
	}

	// Sort by distance (insertion sort — small N, fine for this use case)
	for i in 1 ..< hit_count {
		key := out_hits[i]
		j := i - 1
		for j >= 0 && out_hits[j].distance > key.distance {
			out_hits[j + 1] = out_hits[j]
			j -= 1
		}
		out_hits[j + 1] = key
	}

	// Apply k limit
	if k > 0 && k < hit_count {
		hit_count = k
	}

	return hit_count
}

// radar_from_ship is a convenience for radar originating from a ship's position.
radar_from_ship :: proc(
	ship_id: int,
	k: int,
	app: ^App,
	out_hits: []RadarHit,
) -> int {
	if ship_id < 0 || ship_id >= MAX_SHIPS {return 0}
	ship := &app.ships[ship_id]
	return radar(ship.x, ship.y, ship_id, 0, k, app, out_hits)
}

// radar_from_player is a convenience for radar originating from the player's position.
// Uses the player's own detection range (passed as range_f32).
radar_from_player :: proc(
	range_f32: f32,
	k: int,
	app: ^App,
	out_hits: []RadarHit,
) -> int {
	return radar(app.player.x, app.player.y, -1, range_f32, k, app, out_hits)
}

// ---------------------------------------------------------------------------
// Proximity-based discovery
// ---------------------------------------------------------------------------

check_sensor_discovery :: proc(app: ^App, ship: ^Ship) {
	if ship.state != .SAILING {return}
	sensor := ship_stats[ship.type].sensor_range
	sq_range := sensor * sensor

	for i in 0 ..< app.all_port_count {
		if app.discovered_ports[i] {continue}
		port := &app.all_ports[i]
		if port.island_idx >= 0 && port.island_idx < app.island_count {
			if app.islands[port.island_idx].production == .PORT {continue}
		}
		dx := port.x - ship.x
		dy := port.y - ship.y
		if dx * dx + dy * dy <= sq_range {
			app.discovered_ports[i] = true
			app.discovered_count += 1
			if port.island_idx >= 0 && port.island_idx < app.island_count {
				if !app.discovered_islands[port.island_idx] {
					app.discovered_islands[port.island_idx] = true
					app.discovered_island_count += 1
				}
				island := &app.islands[port.island_idx]
				msg := fmt.aprintf("Discovered %s (%s)", get_name(island^), resource_names[island.production])
				push_log(app, msg, app.time_day)
				delete(msg, context.allocator)
			}
		}
	}
}