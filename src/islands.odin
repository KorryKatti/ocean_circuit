package main

// islands — Island types, resource definitions, and island rendering.

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

MAX_ISLANDS :: 48
MAX_TILES :: 16000
TILE_SIZE :: 32
MAP_WIDTH :: 4000
MAP_HEIGHT :: 3250
MAX_PORTS :: 4096
MAX_LOG   :: 32

LogEntry :: struct {
	msg:  [128]u8,
	len:  int,
	time: f32,
}

// ---------------------------------------------------------------------------
// Resource types
// ---------------------------------------------------------------------------

ResourceType :: enum {
	WOOD,
	FISH,
	ORE,
	METAL,
	OIL,
	LUXURY,
	PORT,
}

PortRef :: struct {
	island_idx: int,
	tile_idx:   int, // index into islands[island_idx].tiles
	x, y:       f32, // world coords (pixels) for routing/rendering
}

resource_names := [?]cstring{"Wood", "Fish", "Ore", "Metal", "Oil", "Luxury", "Port"}

resource_colors := [?]rl.Color {
	{139, 90, 43, 255}, // WOOD
	{70, 130, 180, 255}, // FISH
	{128, 128, 128, 255}, // ORE
	{192, 192, 192, 255}, // METAL
	{30, 30, 30, 255}, // OIL
	{255, 215, 0, 255}, // LUXURY
	{0, 220, 200, 255}, // PORT
}

PORT_COLOR :: rl.Color{0, 180, 160, 255}
PORT_HIGHLIGHT :: rl.Color{0, 220, 200, 255}

resource_from_char :: proc(c: byte) -> ResourceType {
	switch c {
	case 'W':
		return .WOOD
	case 'F':
		return .FISH
	case 'O':
		return .ORE
	case 'M':
		return .METAL
	case 'L':
		return .LUXURY
	case 'P':
		return .PORT
	case:
		return .ORE
	}
}

// ---------------------------------------------------------------------------
// Core data structures
// ---------------------------------------------------------------------------

Tile :: struct {
	gx:      i32,
	gy:      i32,
	is_port: bool,
}

Island :: struct {
	id:         int,
	pos:        rl.Vector2,
	name:       [32]u8,
	name_len:   int,
	production: ResourceType,
	rate:       f32,
	warehouse:  f32,
	max_ware:   f32,
	dock_level: int,
	radius:     f32,
	tiles:      [MAX_TILES]Tile,
	tile_count: int,
	port_count: int,
}

MapCell :: struct {
	ch: byte,
}

MapGrid :: struct {
	cells:  [MAP_HEIGHT][MAP_WIDTH]byte,
	width:  int,
	height: int,
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

get_name :: proc(island: Island) -> cstring {
	buf: [33]u8
	for j in 0 ..< island.name_len {
		buf[j] = island.name[j]
	}
	buf[island.name_len] = 0
	return cstring(&buf[0])
}

push_log :: proc(app: ^App, msg: string, day: f32) {
	entry := &app.log_entries[app.log_next]
	n := min(len(msg), 127)
	for j in 0 ..< n {
		entry.msg[j] = msg[j]
	}
	entry.len = n
	entry.time = day
	app.log_next = (app.log_next + 1) % MAX_LOG
	if app.log_count < MAX_LOG {
		app.log_count += 1
	}
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

draw_islands :: proc(app: ^App) {
	vp_min_x, vp_min_y, vp_max_x, vp_max_y := get_viewport(app)
	tile_f := f32(TILE_SIZE)

	for i in 0 ..< app.island_count {
		island := &app.islands[i]
		color := resource_colors[island.production]

		// Bounding-box cull entire island if off-screen (with buffer)
		buffer := tile_f * 2
		island_min_x := island.pos.x - island.radius - buffer
		island_max_x := island.pos.x + island.radius + buffer
		island_min_y := island.pos.y - island.radius - buffer
		island_max_y := island.pos.y + island.radius + buffer
		if island_max_x < vp_min_x ||
		   island_min_x > vp_max_x ||
		   island_max_y < vp_min_y ||
		   island_min_y > vp_max_y {
			continue
		}

		// Draw tiles
		for t in 0 ..< island.tile_count {
			tile := &island.tiles[t]
			x := f32(tile.gx) * tile_f
			y := f32(tile.gy) * tile_f

			if app.selected == i {
				rl.DrawRectangle(
					i32(x) - 1,
					i32(y) - 1,
					i32(tile_f) + 2,
					i32(tile_f) + 2,
					{255, 255, 100, 60},
				)
			}

			tile_color := color
			if tile.is_port {
				tile_color = PORT_COLOR
			}
			if app.discovered_islands[i] {
				// Brighten discovered islands
				tile_color.r = min(tile_color.r + 40, 255)
				tile_color.g = min(tile_color.g + 40, 255)
				tile_color.b = min(tile_color.b + 40, 255)
			}

			rl.DrawRectangleV({x, y}, {tile_f, tile_f}, tile_color)
			rl.DrawRectangleLinesEx({x, y, tile_f, tile_f}, 2, {20, 20, 20, 200})
		}

		// Labels
		if island.pos.x >= vp_min_x - 200 &&
		   island.pos.x <= vp_max_x + 200 &&
		   island.pos.y >= vp_min_y - 100 &&
		   island.pos.y <= vp_max_y + 100 {

			name := get_name(island^)
			text_w := rl.MeasureText(name, 32)
			name_x := i32(island.pos.x) - text_w / 2
			name_y := i32(island.pos.y + island.radius + 16)
			rl.DrawText(name, name_x + 2, name_y + 2, 32, {0, 0, 0, 200})
			rl.DrawText(name, name_x, name_y, 32, {255, 255, 255, 255})

			res_name := resource_names[island.production]
			res_w := rl.MeasureText(res_name, 24)
			res_x := i32(island.pos.x) - res_w / 2
			res_y := i32(island.pos.y - 20)
			rl.DrawText(res_name, res_x + 2, res_y + 2, 24, {0, 0, 0, 200})
			rl.DrawText(res_name, res_x, res_y, 24, {255, 255, 255, 255})
		}
	}
}
