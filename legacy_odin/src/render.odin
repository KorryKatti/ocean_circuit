package main

// render — Viewport utilities and water rendering.

import "core:math"
import rl "vendor:raylib"

// ---------------------------------------------------------------------------
// Viewport
// ---------------------------------------------------------------------------

get_viewport :: proc(app: ^App) -> (min_x, min_y, max_x, max_y: f32) {
	screen_w := f32(rl.GetScreenWidth())
	screen_h := f32(rl.GetScreenHeight())
	half_w := (screen_w / 2) / app.camera.zoom
	half_h := (screen_h / 2) / app.camera.zoom
	min_x = app.camera.target.x - half_w
	min_y = app.camera.target.y - half_h
	max_x = app.camera.target.x + half_w
	max_y = app.camera.target.y + half_h
	return
}

// ---------------------------------------------------------------------------
// Water rendering
// ---------------------------------------------------------------------------

draw_water :: proc(app: ^App) {
	tex_w := f32(app.scroll_tex.width)
	tex_h := f32(app.scroll_tex.height)

	app.scroll_x += 15 * rl.GetFrameTime()
	app.scroll_y += 10 * rl.GetFrameTime()
	if app.scroll_x >= tex_w {app.scroll_x -= tex_w}
	if app.scroll_y >= tex_h {app.scroll_y -= tex_h}

	vp_min_x, vp_min_y, vp_max_x, vp_max_y := get_viewport(app)
	start_ix := i32(math.floor(vp_min_x / tex_w)) - 1
	start_iy := i32(math.floor(vp_min_y / tex_h)) - 1
	end_ix := i32(math.ceil(vp_max_x / tex_w)) + 1
	end_iy := i32(math.ceil(vp_max_y / tex_h)) + 1

	for ix := start_ix; ix <= end_ix; ix += 1 {
		for iy := start_iy; iy <= end_iy; iy += 1 {
			pos_x := f32(ix) * tex_w - app.scroll_x
			pos_y := f32(iy) * tex_h - app.scroll_y
			rl.DrawTexture(app.scroll_tex, i32(pos_x), i32(pos_y), rl.WHITE)
		}
	}
}

// ---------------------------------------------------------------------------
// Player rendering
// ---------------------------------------------------------------------------

draw_player :: proc(app: ^App) {
	s := app.player.size
	rl.DrawRectangleV({app.player.x - s / 2, app.player.y - s / 2}, {s, s}, {220, 30, 30, 255})
}
