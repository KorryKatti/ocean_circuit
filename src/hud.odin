package main

// hud — ImGui panels for game info and selections.

import rlimgui "../lib/imgui_impl_raylib"
import imgui "../lib/odin-imgui"

draw_hud :: proc(app: ^App) {
	// Info panel
	imgui.SetNextWindowSize({260, 0}, .FirstUseEver)
	imgui.SetNextWindowPos({10, 10}, .FirstUseEver)
	if imgui.Begin("Info") {
		imgui.Text("Map: %dx%d", MAP_WIDTH, MAP_HEIGHT)
		imgui.Text("Islands: %d", app.island_count)
		imgui.TextColored({0.2, 1, 0.2, 1}, "Money: $%d", i32(app.money))
		imgui.Text("Day: %.1f", app.time_day)
		imgui.Text("Zoom: %.0f%%", app.camera.zoom * 100)
		imgui.Separator()
		imgui.TextDisabled("WASD: move character")
		imgui.TextDisabled("Scroll: zoom")
		imgui.TextDisabled("Click: select island or ship")
		imgui.TextDisabled("Scroll: zoom")
	}
	imgui.End()

	// Sailing ships panel
	imgui.SetNextWindowSize({260, 0}, .FirstUseEver)
	imgui.SetNextWindowPos({10, 200}, .FirstUseEver)
	if imgui.Begin("Sailing Ships") {
		imgui.Text("En route: %d", app.sailing_count)
		if app.sailing_count > 0 {
			imgui.Separator()
			for i in 0 ..< app.sailing_count {
				imgui.Text("#%d  grid(%d, %d)", i, app.sailing_grid_xs[i], app.sailing_grid_ys[i])
			}
		}
	}
	imgui.End()

	// Selected-island detail panel
	if app.selected >= 0 && app.selected < app.island_count {
		island := &app.islands[app.selected]
		name := get_name(island^)

		imgui.SetNextWindowSize({280, 0}, .FirstUseEver)
		imgui.SetNextWindowPos({10, 120}, .FirstUseEver)
		if imgui.Begin("Island") {
			imgui.Text("ID: %d | %s", island.id, name)
			imgui.Separator()
			imgui.Text("Produces: %s", resource_names[island.production])
			imgui.Text("Rate: %.1f/day", island.rate)
			imgui.Text("Storage: %.0f / %.0f", island.warehouse, island.max_ware)
			imgui.Text("Dock Level: %d", island.dock_level)
			imgui.Text("Tiles: %d", island.tile_count)

			if island.port_count > 0 {
				imgui.Separator()
				imgui.TextColored({0, 0.9, 0.8, 1}, "Port Tiles: %d", island.port_count)
				imgui.TextDisabled("Docks along the coast")
			}
		}
		imgui.End()
	}

	// Selected-ship detail panel
	if app.selected == -2 {
		imgui.SetNextWindowSize({280, 0}, .FirstUseEver)
		imgui.SetNextWindowPos({10, 120}, .FirstUseEver)
		if imgui.Begin("Ship") {
			stats := ship_stats[app.ships[0].type]
			imgui.TextColored({1, 0.4, 0.6, 1}, "%v", app.ships[0].type)
			imgui.Separator()
			imgui.Text("Health: %.0f / %.0f", app.ships[0].health, stats.health)
			imgui.Text("Speed: %.0f", app.ships[0].speed)
			imgui.Text("Value: $%d", i32(stats.value))
		}
		imgui.End()
	}
}
