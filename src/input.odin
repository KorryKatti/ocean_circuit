package main

// input — Player movement and click handling.

import rl "vendor:raylib"

// ---------------------------------------------------------------------------
// Water check
// ---------------------------------------------------------------------------

is_water :: proc(grid: ^MapGrid, world_x, world_y: f32) -> bool {
	gx := int(world_x / f32(TILE_SIZE))
	gy := int(world_y / f32(TILE_SIZE))
	if gx < 0 || gx >= grid.width || gy < 0 || gy >= grid.height {
		return true
	}
	return grid.cells[gy][gx] == '.'
}

// ---------------------------------------------------------------------------
// Player movement
// ---------------------------------------------------------------------------

update_player :: proc(app: ^App) {
	dt := rl.GetFrameTime()
	speed := app.player.speed * dt
	dx: f32 = 0
	dy: f32 = 0

	if rl.IsKeyDown(.W) {dy -= speed}
	if rl.IsKeyDown(.S) {dy += speed}
	if rl.IsKeyDown(.A) {dx -= speed}
	if rl.IsKeyDown(.D) {dx += speed}

	new_x := app.player.x + dx
	if !is_water(&app.grid, new_x, app.player.y) {
		app.player.x = new_x
	}

	new_y := app.player.y + dy
	if !is_water(&app.grid, app.player.x, new_y) {
		app.player.y = new_y
	}
}

// ---------------------------------------------------------------------------
// Click handling
// ---------------------------------------------------------------------------

handle_click :: proc(app: ^App) {
	mouse := rl.GetScreenToWorld2D(rl.GetMousePosition(), app.camera)
	app.selected = -1
	tile_f := f32(TILE_SIZE)

	// Check ship hit
	ship_w := tile_f
	ship_h := tile_f * 3
	if mouse.x >= app.ships[0].x - ship_w / 2 &&
	   mouse.x <= app.ships[0].x + ship_w / 2 &&
	   mouse.y >= app.ships[0].y - ship_h / 2 &&
	   mouse.y <= app.ships[0].y + ship_h / 2 {
		app.selected = -2
		return
	}

	for i in 0 ..< app.island_count {
		island := &app.islands[i]
		for t in 0 ..< island.tile_count {
			tile := &island.tiles[t]
			tx := f32(tile.gx) * tile_f
			ty := f32(tile.gy) * tile_f
			if mouse.x >= tx && mouse.x <= tx + tile_f && mouse.y >= ty && mouse.y <= ty + tile_f {
				app.selected = i
				return
			}
		}
	}
}
