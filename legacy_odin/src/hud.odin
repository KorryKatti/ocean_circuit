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
		if app.cam_mode == .PLAYER {
			if imgui.Button("Camera: Player", {240, 25}) {
				app.cam_mode = .SHIP
			}
		} else {
			if imgui.Button("Camera: Ship", {240, 25}) {
				app.cam_mode = .PLAYER
			}
		}
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
		ship := &app.ships[0]

		imgui.SetNextWindowSize({300, 0}, .FirstUseEver)
		imgui.SetNextWindowPos({10, 120}, .FirstUseEver)
		if imgui.Begin("Ship") {
			stats := ship_stats[ship.type]
			imgui.TextColored({1, 0.4, 0.6, 1}, "%v", ship.type)
			imgui.Separator()
			imgui.Text("Health: %.0f / %.0f", ship.health, stats.health)
			imgui.Text("Speed: %.0f", ship.speed)
			imgui.Text("Value: $%d", i32(stats.value))
			imgui.Separator()

			if ship.waypoint_count > 0 {
				imgui.Text("Exploring: %d / %d ports", ship.waypoint_idx + 1, ship.waypoint_count)
				if ship.waypoint_idx < ship.waypoint_count {
					wp := &ship.waypoints[ship.waypoint_idx]
					if wp.island_idx >= 0 && wp.island_idx < app.island_count {
						island := &app.islands[wp.island_idx]
						imgui.TextDisabled("-> %s (%s)", get_name(island^), resource_names[island.production])
					}
				}
				imgui.Text("Islands: %d / %d", app.discovered_island_count, app.island_count)
			} else {
				imgui.Text("Status: Idle")
				imgui.Text("Islands: %d / %d", app.discovered_island_count, app.island_count)
			}

			imgui.Separator()

			if ship.waypoint_count == 0 {
				undiscovered := i32(app.island_count - app.discovered_island_count)
				imgui.Text("Islands to visit (0 = all):")
				imgui.SliderInt("##k", &app.explore_k, 0, undiscovered)
				if imgui.Button("Send to Explore", {200, 30}) {
					build_explore_route(app, ship, int(app.explore_k))
				}
			} else {
				if imgui.Button("Stop", {90, 30}) {
					reset_waypoints(ship)
					ship.state = .IDLE
				}
				imgui.SameLine()
				if imgui.Button("Recall", {90, 30}) {
					reset_waypoints(ship)
					for i in 0 ..< app.all_port_count {
						if app.all_ports[i].island_idx == 0 {
							ship.dest_x = app.all_ports[i].x
							ship.dest_y = app.all_ports[i].y
							ship.state = .SAILING
							break
						}
					}
				}
			}
		}
		imgui.End()
	}
		// Discovered ports panel
	imgui.SetNextWindowSize({260, 0}, .FirstUseEver)
	imgui.SetNextWindowPos({310, 10}, .FirstUseEver)
	if imgui.Begin("Discovered Islands") {
		// Count non-PORT discovered islands
		diplay_count := 0
		for i in 0 ..< app.island_count {
			if app.discovered_islands[i] && app.islands[i].production != .PORT {
				diplay_count += 1
			}
		}
		total_display := 0
		for i in 0 ..< app.island_count {
			if app.islands[i].production != .PORT {
				total_display += 1
			}
		}
		imgui.Text("%d / %d found", diplay_count, total_display)
		imgui.Separator()
		for i in 0 ..< app.island_count {
			if !app.discovered_islands[i] {continue}
			island := &app.islands[i]
			if island.production == .PORT {continue}
			name := get_name(island^)
			imgui.TextColored({0, 0.9, 0.8, 1}, "%s", name)
			imgui.TextDisabled("  %s — rate %.1f", resource_names[island.production], island.rate)
		}
	}
	imgui.End()

	// Discovery log panel
	imgui.SetNextWindowSize({260, 150}, .FirstUseEver)
	imgui.SetNextWindowPos({310, 400}, .FirstUseEver)
	if imgui.Begin("Discovery Log") {
		if app.log_count == 0 {
			imgui.TextDisabled("No discoveries yet...")
		} else {
			show := min(app.log_count, 10)
			idx := app.log_next
			for _ in 0 ..< show {
				idx = (idx - 1 + MAX_LOG) % MAX_LOG
				entry := &app.log_entries[idx]
				entry_msg := string(entry.msg[:entry.len])
				imgui.TextColored({1, 0.85, 0.2, 1}, "Day %.1f", entry.time)
				imgui.TextDisabled("  %s", entry_msg)
			}
		}
	}
	imgui.End()
}
