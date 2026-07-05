package main

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import imgui "../lib/odin-imgui"
import rlimgui "../lib/imgui_impl_raylib"

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

DEFAULT_SEED :: 42
MAX_ISLANDS :: 24
MAX_TILES :: 800
TILE_SIZE :: 32

// ---------------------------------------------------------------------------
// Resource types — what each island produces
// ---------------------------------------------------------------------------

ResourceType :: enum {
    WOOD, FISH, ORE, METAL, OIL, LUXURY,
}

resource_names := [?]cstring {
    "Wood", "Fish", "Ore", "Metal", "Oil", "Luxury",
}

resource_colors := [?]rl.Color {
    {139, 90, 43, 255},    // WOOD
    {70, 130, 180, 255},   // FISH
    {128, 128, 128, 255},  // ORE
    {192, 192, 192, 255},  // METAL
    {30, 30, 30, 255},     // OIL
    {255, 215, 0, 255},    // LUXURY
}

// ---------------------------------------------------------------------------
// Core data structures
// ---------------------------------------------------------------------------

// Tile — a single grid-aligned square that makes up an island's shape.
Tile :: struct {
    gx: i32,  // grid X coordinate
    gy: i32,  // grid Y coordinate
}

// Island — a landmass with a unique id, procedural tile shape, and economic data.
Island :: struct {
    id:         int,
    pos:        rl.Vector2,
    name:       [32]u8,
    name_len:   int,
    production: ResourceType,
    rate:       f32,        // units produced per day
    warehouse:  f32,        // current cargo stored
    max_ware:   f32,        // warehouse capacity
    dock_level: int,        // affects loading speed
    radius:     f32,        // bounding radius for spacing/collision
    tiles:      [MAX_TILES]Tile,
    tile_count: int,
}

// Rng — simple LCG-based pseudorandom number generator.
Rng :: struct {
    state: u32,
}

// ---------------------------------------------------------------------------
// RNG utilities
// ---------------------------------------------------------------------------

seed_rng :: proc(seed: u32) -> Rng {
    return {state = seed | 1}
}

lcg_next :: proc(rng: ^Rng) -> u32 {
    rng.state = (rng.state * 1103515245) + 12345
    return rng.state
}

next_f32 :: proc(rng: ^Rng, min_val, max_val: f32) -> f32 {
    return min_val + f32(lcg_next(rng) % 10000) / 10000.0 * (max_val - min_val)
}

next_int :: proc(rng: ^Rng, min_val, max_val: int) -> int {
    return min_val + int(lcg_next(rng) % u32(max_val - min_val))
}

// ---------------------------------------------------------------------------
// Island generation — procedural tile shapes via BFS flood fill
// ---------------------------------------------------------------------------

// generate_tiles creates an organic blob of tiles around a center point
// using randomized BFS expansion. Stops at `count` or MAX_TILES.
generate_tiles :: proc(rng: ^Rng, center: rl.Vector2, count: int, tiles: ^[MAX_TILES]Tile, out_count: ^int) {
    cx := i32(center.x / TILE_SIZE)
    cy := i32(center.y / TILE_SIZE)

    placed: [MAX_TILES]bool
    grid: [256][256]i32
    for i in 0..<256 {
        for j in 0..<256 {
            grid[i][j] = -1
        }
    }

    ox := cx - 128
    oy := cy - 128

    grid[128][128] = 0
    tiles[0] = {cx, cy}
    placed[0] = true
    total := 1

    dirs := [4][2]i32 {
        {1, 0}, {-1, 0}, {0, 1}, {0, -1},
    }

    for total < count && total < MAX_TILES {
        idx := int(lcg_next(rng) % u32(total))
        base := tiles[idx]

        shuffled := [4]int { 0, 1, 2, 3 }
        for k in 0..<3 {
            s := 3 - k
            j2 := int(lcg_next(rng) % u32(s + 1))
            shuffled[s], shuffled[j2] = shuffled[j2], shuffled[s]
        }

        expanded := false
        for s in 0..<4 {
            d := dirs[shuffled[s]]
            nx := base.gx + d[0]
            ny := base.gy + d[1]
            gx_idx := nx - ox
            gy_idx := ny - oy

            if gx_idx < 0 || gx_idx >= 256 || gy_idx < 0 || gy_idx >= 256 { continue }
            if grid[gy_idx][gx_idx] >= 0 { continue }

            grid[gy_idx][gx_idx] = i32(total)
            tiles[total] = {nx, ny}
            placed[total] = true
            total += 1
            expanded = true
            break
        }

        if !expanded {
            for k in 0..<total {
                if !placed[k] { continue }
                for s in 0..<4 {
                    d := dirs[s]
                    nx := tiles[k].gx + d[0]
                    ny := tiles[k].gy + d[1]
                    gx_idx := nx - ox
                    gy_idx := ny - oy

                    if gx_idx < 0 || gx_idx >= 256 || gy_idx < 0 || gy_idx >= 256 { continue }
                    if grid[gy_idx][gx_idx] >= 0 { continue }

                    grid[gy_idx][gx_idx] = i32(total)
                    tiles[total] = {nx, ny}
                    placed[total] = true
                    total += 1
                    expanded = true
                    break
                }
                if expanded { break }
            }
        }

        if !expanded { break }
    }

    out_count^ = total
}

// ---------------------------------------------------------------------------
// Island name data
// ---------------------------------------------------------------------------

island_names := [?]cstring {
    "Port Haven", "Iron Bay", "Coral Reef", "Storm Point",
    "Gold Coast", "Fog Harbor", "Tide Watch", "Ember Isle",
    "Salt Marsh", "Driftwood", "Pearl Bay", "Rust Dock",
    "Copper Peak", "Silver Shore", "Kelp Forest", "Turtle Rock",
    "Moon Harbor", "Anvil Port", "Flint Isle", "Cedar Landing",
    "Stone Gate", "Coral Spire", "Wave Crest", "Amber Dock",
}

// generate_islands creates `count` islands with procedural positions and
// tile shapes. Uses rejection sampling for spacing, falls back to ring layout.
generate_islands :: proc(seed: u32, count: int) -> [MAX_ISLANDS]Island {
    rng := seed_rng(seed)
    islands: [MAX_ISLANDS]Island

    MAP_MIN_X :: f32(-2000)
    MAP_MAX_X :: f32(15000)
    MAP_MIN_Y :: f32(-2000)
    MAP_MAX_Y :: f32(10000)
    MIN_SPACING :: f32(1500)

    for i in 0..<min(count, MAX_ISLANDS) {
        pos: rl.Vector2
        radius := next_f32(&rng, 80, 150)
        tile_count := int(next_f32(&rng, 300, 600))

        placed := false
        for attempt in 0..<300 {
            candidate := rl.Vector2{
                next_f32(&rng, MAP_MIN_X + 200, MAP_MAX_X - 200),
                next_f32(&rng, MAP_MIN_Y + 200, MAP_MAX_Y - 200),
            }

            valid := true
            for j in 0..<i {
                dx := candidate.x - islands[j].pos.x
                dy := candidate.y - islands[j].pos.y
                dist_sq := dx * dx + dy * dy
                min_dist := MIN_SPACING + radius + islands[j].radius
                if dist_sq < min_dist * min_dist {
                    valid = false
                    break
                }
            }

            if valid {
                pos = candidate
                placed = true
                break
            }
        }

        if !placed {
            angle := f32(i) * (2.0 * 3.14159 / f32(count))
            center_x := (MAP_MIN_X + MAP_MAX_X) / 2
            center_y := (MAP_MIN_Y + MAP_MAX_Y) / 2
            ring := f32(1500 + (i / 4) * 1500)
            pos = {center_x + ring * math.cos(angle), center_y + ring * math.sin(angle)}
        }

        islands[i].id = i
        islands[i].pos = pos
        islands[i].radius = radius
        islands[i].production = ResourceType(lcg_next(&rng) % 6)
        islands[i].rate = next_f32(&rng, 1, 5)
        islands[i].warehouse = 0
        islands[i].max_ware = next_f32(&rng, 50, 200)
        islands[i].dock_level = next_int(&rng, 1, 4)

        generate_tiles(&rng, pos, tile_count, &islands[i].tiles, &islands[i].tile_count)

        src := transmute([^]u8)island_names[i]
        n := 0
        for j in 0..<32 {
            if src[j] == 0 { break }
            islands[i].name[j] = src[j]
            n += 1
        }
        islands[i].name_len = n
    }
    return islands
}

// get_name returns the island's name as a cstring for raylib text rendering.
get_name :: proc(island: Island) -> cstring {
    buf: [33]u8
    for j in 0..<island.name_len {
        buf[j] = island.name[j]
    }
    buf[island.name_len] = 0
    return cstring(&buf[0])
}

// ---------------------------------------------------------------------------
// Application state
// ---------------------------------------------------------------------------

App :: struct {
    islands:      [MAX_ISLANDS]Island,
    island_count: int,
    seed:         u32,
    camera:       rl.Camera2D,
    selected:     int,
    money:        f32,
    time_day:     f32,
    scroll_tex:   rl.Texture2D,
    bg_color:     rl.Color,
    scroll_x:     f32,
    scroll_y:     f32,
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

    app: App
    app.seed = DEFAULT_SEED
    app.islands = generate_islands(app.seed, MAX_ISLANDS)
    app.island_count = MAX_ISLANDS
    app.money = 1000
    app.selected = -1
    app.camera.offset = {640, 360}
    app.camera.target = {6500, 4000}
    app.camera.rotation = 0
    app.camera.zoom = 0.12

    app.scroll_tex = rl.LoadTexture("assets/img/sea_texture.jpg")
    defer rl.UnloadTexture(app.scroll_tex)

    img := rl.LoadImage("assets/img/sea_texture.jpg")
    defer rl.UnloadImage(img)
    colors := rl.LoadImageColors(img)
    center_pixel := colors[(img.height / 2) * img.width + img.width / 2]
    app.bg_color = {center_pixel.r, center_pixel.g, center_pixel.b, 255}

    for !rl.WindowShouldClose() {
        update_camera(&app)
        app.time_day += rl.GetFrameTime() / 60.0

        rl.BeginDrawing()
        rl.ClearBackground(app.bg_color)

        rl.BeginMode2D(app.camera)
        draw_water(&app)
        draw_islands(&app)
        rl.EndMode2D()

        rlimgui.begin()
        draw_hud(&app)
        rlimgui.end()

        if rl.IsMouseButtonPressed(.LEFT) && !imgui.GetIO().WantCaptureMouse {
            handle_click(&app)
        }

        rl.EndDrawing()
    }
}

// ---------------------------------------------------------------------------
// Camera — right-drag to pan, scroll to zoom
// ---------------------------------------------------------------------------

update_camera :: proc(app: ^App) {
    if rl.IsMouseButtonDown(.RIGHT) {
        delta := rl.GetMouseDelta()
        app.camera.target.x -= delta.x / app.camera.zoom
        app.camera.target.y -= delta.y / app.camera.zoom
    }

    wheel := rl.GetMouseWheelMove()
    if wheel != 0 {
        app.camera.zoom += wheel * 0.1
        if app.camera.zoom < 0.03 { app.camera.zoom = 0.03 }
        if app.camera.zoom > 3.0 { app.camera.zoom = 3.0 }
    }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

// draw_water tiles the sea texture across the visible world in a scrolling grid.
draw_water :: proc(app: ^App) {
    tex_w := f32(app.scroll_tex.width)
    tex_h := f32(app.scroll_tex.height)

    app.scroll_x += 15 * rl.GetFrameTime()
    app.scroll_y += 10 * rl.GetFrameTime()
    if app.scroll_x >= tex_w { app.scroll_x -= tex_w }
    if app.scroll_y >= tex_h { app.scroll_y -= tex_h }

    for ix := -10; ix <= 60; ix += 1 {
        for iy := -10; iy <= 40; iy += 1 {
            pos := rl.Vector2{
                f32(ix) * tex_w - app.scroll_x,
                f32(iy) * tex_h - app.scroll_y,
            }
            rl.DrawTexture(app.scroll_tex, i32(pos.x), i32(pos.y), rl.WHITE)
        }
    }
}

// draw_islands renders each island as a collection of colored tiles with
// dark outlines, name labels, and resource indicators.
draw_islands :: proc(app: ^App) {
    for i in 0..<app.island_count {
        island := &app.islands[i]
        color := resource_colors[island.production]
        tile_pixel := f32(TILE_SIZE)

        for t in 0..<island.tile_count {
            tile := &island.tiles[t]
            x := f32(tile.gx) * tile_pixel
            y := f32(tile.gy) * tile_pixel

            if app.selected == i {
                rl.DrawRectangle(i32(x) - 1, i32(y) - 1, i32(tile_pixel) + 2, i32(tile_pixel) + 2, {255, 255, 100, 60})
            }

            rl.DrawRectangleV({x, y}, {tile_pixel, tile_pixel}, color)
            rl.DrawRectangleLinesEx({x, y, tile_pixel, tile_pixel}, 2, {20, 20, 20, 200})
        }

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

// draw_hud renders the info panel and selected island details using ImGui.
draw_hud :: proc(app: ^App) {
    imgui.SetNextWindowSize({260, 0}, .FirstUseEver)
    imgui.SetNextWindowPos({10, 10}, .FirstUseEver)
    if imgui.Begin("Info") {
        imgui.Text("Seed: %d", app.seed)
        imgui.TextColored({0.2, 1, 0.2, 1}, "Money: $%d", i32(app.money))
        imgui.Text("Day: %.1f", app.time_day)
        imgui.Separator()
        imgui.TextDisabled("Right-drag: pan")
        imgui.TextDisabled("Scroll: zoom")
    }
    imgui.End()

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
        }
        imgui.End()
    }
}

// ---------------------------------------------------------------------------
// Input handling
// ---------------------------------------------------------------------------

// handle_click checks if the mouse world position hits any island tile
// and sets app.selected to the matching island index.
handle_click :: proc(app: ^App) {
    mouse := rl.GetScreenToWorld2D(rl.GetMousePosition(), app.camera)
    app.selected = -1
    tile_f := f32(TILE_SIZE)

    for i in 0..<app.island_count {
        island := &app.islands[i]
        for t in 0..<island.tile_count {
            tile := &island.tiles[t]
            tx := f32(tile.gx) * tile_f
            ty := f32(tile.gy) * tile_f
            if mouse.x >= tx && mouse.x <= tx + tile_f &&
               mouse.y >= ty && mouse.y <= ty + tile_f {
                app.selected = i
                return
            }
        }
    }
}
