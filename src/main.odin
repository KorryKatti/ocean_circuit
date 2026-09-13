#+feature dynamic-literals
package main

// Ocean Circuit — A naval shipping economy game.
// Entry point: window setup, data loading, main loop.

import rlimgui "../lib/imgui_impl_raylib"
import imgui "../lib/odin-imgui"
import "core:fmt"
import rl "vendor:raylib"

// ---------------------------------------------------------------------------
// Application state
// ---------------------------------------------------------------------------

Player :: struct {
	x:     f32,
	y:     f32,
	speed: f32,
	size:  f32,
}

App :: struct {
	islands:         [MAX_ISLANDS]Island,
	island_count:    int,
	grid:            MapGrid,
	camera:          rl.Camera2D,
	selected:        int,
	money:           f32,
	time_day:        f32,
	scroll_tex:      rl.Texture2D,
	bg_color:        rl.Color,
	scroll_x:        f32,
	scroll_y:        f32,
	player:          Player,
	ships:           [MAX_SHIPS]Ship,
	world_economy:   f32,
	ship_pos_timer:  f32,
	sailing_count:   int,
	sailing_grid_xs: [MAX_SHIPS]int,
	sailing_grid_ys: [MAX_SHIPS]int,
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .WINDOW_ALWAYS_RUN})
	rl.InitWindow(1280, 720, "Ocean Circuit")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	imgui.CreateContext(nil)
	defer imgui.DestroyContext(nil)
	io := imgui.GetIO()
	io.ConfigFlags |= {.NavEnableKeyboard}
	rlimgui.init()
	defer rlimgui.shutdown()

	// Load map from CSV
	app := new(App)
	defer free(app)
	if !load_map_csv("assets/data/map.csv", &app.grid) {
		fmt.println("ERROR: Could not load map.csv")
		return
	}

	// Load island tiles from CSV (no flood fill needed)
	app.island_count = load_islands_csv("assets/data/islands.csv", &app.grid, &app.islands)

	// Load metadata (names, rates, dock levels)
	metas: [MAX_ISLANDS]IslandMeta
	meta_count: int
	load_metadata_csv("assets/data/metadata.csv", &metas, &meta_count)

	// Apply metadata to islands
	for i in 0 ..< app.island_count {
		island := &app.islands[i]
		for m in 0 ..< meta_count {
			if metas[m].id == island.id {
				island.production = metas[m].production
				island.rate = metas[m].rate
				island.max_ware = metas[m].max_ware
				island.dock_level = metas[m].dock_level
				for j in 0 ..< metas[m].name_len {
					island.name[j] = metas[m].name[j]
				}
				island.name_len = metas[m].name_len
				break
			}
		}
	}

	// Load port positions and mark tiles
	load_ports_csv("assets/data/ports.csv", &app.islands, app.island_count)

	app.money = 1000
	app.selected = -1

	// Spawn the player on the PORT island (fallback: first island)
	app.player.size = 20
	app.player.speed = 200
	spawn_island := -1
	for i in 0 ..< app.island_count {
		if app.islands[i].production == .PORT {
			spawn_island = i
			break
		}
	}
	if spawn_island < 0 && app.island_count > 0 {
		spawn_island = 0
	}

	if spawn_island >= 0 {
		spawn_name := "spawn"
		n := min(len(spawn_name), 31)
		for j in 0 ..< n {
			app.islands[spawn_island].name[j] = spawn_name[j]
		}
		app.islands[spawn_island].name_len = n
	}

	if spawn_island >= 0 && app.islands[spawn_island].tile_count > 0 {
		t := app.islands[spawn_island].tiles[0]
		app.player.x = f32(t.gx) * f32(TILE_SIZE) + f32(TILE_SIZE) / 2
		app.player.y = f32(t.gy) * f32(TILE_SIZE) + f32(TILE_SIZE) / 2

		ship := &app.ships[0]
		ship.type = .EXPLORER_SHIP
		ship.health = ship_stats[.EXPLORER_SHIP].health
		ship.value = ship_stats[.EXPLORER_SHIP].value
		ship.speed = ship_stats[.EXPLORER_SHIP].speed * 15

		dirs := [4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
		for ti in 0 ..< app.islands[spawn_island].tile_count {
			if !app.islands[spawn_island].tiles[ti].is_port {continue}
			port_gx := app.islands[spawn_island].tiles[ti].gx
			port_gy := app.islands[spawn_island].tiles[ti].gy
			for d in dirs {
				water_gx := port_gx + i32(d[0])
				water_gy := port_gy + i32(d[1])
				if water_gx >= 0 &&
				   water_gx < i32(app.grid.width) &&
				   water_gy >= 0 &&
				   water_gy < i32(app.grid.height) &&
				   app.grid.cells[water_gy][water_gx] == '.' {
					ship.x = f32(water_gx) * f32(TILE_SIZE) + f32(TILE_SIZE) / 2
					ship.y = f32(water_gy) * f32(TILE_SIZE) + f32(TILE_SIZE) / 2
					ship.state = .DOCKED
					break
				}
			}
			if ship.state == .DOCKED {break}
		}
	}

	// Camera
	app.camera.offset = {640, 360}
	app.camera.target = {app.player.x, app.player.y}
	app.camera.rotation = 0
	app.camera.zoom = 0.5

	// Tiled sea texture
	app.scroll_tex = rl.LoadTexture("assets/img/sea_texture.png")
	defer rl.UnloadTexture(app.scroll_tex)

	app.bg_color = {10, 20, 50, 255}

	fmt.printf("Loaded %d islands\n", app.island_count)

	// Main game loop
	for !rl.WindowShouldClose() {
		update_player(app)
		update_ship(app)
		update_camera(app)
		app.time_day += rl.GetFrameTime() / 60.0
		app.ship_pos_timer += rl.GetFrameTime()
		if app.ship_pos_timer >= 5.0 {
			app.ship_pos_timer = 0
			app.sailing_count = 0
			for i in 0 ..< MAX_SHIPS {
				if app.ships[i].state == .SAILING {
					app.sailing_grid_xs[app.sailing_count] = int(app.ships[i].x / f32(TILE_SIZE))
					app.sailing_grid_ys[app.sailing_count] = int(app.ships[i].y / f32(TILE_SIZE))
					app.sailing_count += 1
				}
			}
		}

		rl.BeginDrawing()
		rl.ClearBackground(app.bg_color)

		rl.BeginMode2D(app.camera)
		draw_water(app)
		draw_islands(app)
		draw_ship(app)
		draw_player(app)
		rl.EndMode2D()

		rlimgui.begin()
		draw_hud(app)
		rlimgui.end()

		if rl.IsMouseButtonPressed(.LEFT) && !imgui.GetIO().WantCaptureMouse {
			handle_click(app)
		}

		rl.EndDrawing()
	}
}

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------

update_camera :: proc(app: ^App) {
	app.camera.target = {app.player.x, app.player.y}

	wheel := rl.GetMouseWheelMove()
	if wheel != 0 {
		app.camera.zoom += wheel * 0.05
		if app.camera.zoom < 0.5 {app.camera.zoom = 0.5}
		if app.camera.zoom > 1.5 {app.camera.zoom = 1.5}
	}
}
