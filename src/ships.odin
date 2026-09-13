#+feature dynamic-literals
package main

// ships — Ship types, stats, movement, and rendering.

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

Ship :: struct {
	x:      f32,
	y:      f32,
	speed:  f32,
	angle:  f32,
	type:   ShipTypes,
	health: f32,
	value:  f32,
	state:  ShipState,
	dest_x: f32,
	dest_y: f32,
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

update_ship :: proc(app: ^App) {
	dt := rl.GetFrameTime()
	for i in 0 ..< MAX_SHIPS {
		ship := &app.ships[i]
		if ship.state != .SAILING {continue}

		dx := ship.dest_x - ship.x
		dy := ship.dest_y - ship.y
		dist := math.sqrt(dx * dx + dy * dy)

		if dist < 2.0 {
			ship.x = ship.dest_x
			ship.y = ship.dest_y
			ship.state = .DOCKED
			continue
		}

		nx := dx / dist
		ny := dy / dist
		step := ship.speed * dt
		if step > dist {step = dist}
		ship.x += nx * step
		ship.y += ny * step

		ship.angle = math.atan2(ny, nx) * (180.0 / math.PI)
	}
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

draw_ship :: proc(app: ^App) {
	tile_f := f32(TILE_SIZE)
	ship_w := tile_f
	ship_h := tile_f * 3

	origin := rl.Vector2{ship_w / 2, ship_h / 2}
	rect := rl.Rectangle{app.ships[0].x - origin.x, app.ships[0].y - origin.y, ship_w, ship_h}

	rl.DrawRectanglePro(rect, origin, app.ships[0].angle, {255, 100, 150, 255})
	rl.DrawRectangleLinesEx(rect, 2, {200, 60, 100, 255})
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
