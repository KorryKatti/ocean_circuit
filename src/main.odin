package main

// Ocean Circuit — A naval shipping economy game.
// Built with Odin + Raylib + ImGui. Islands are procedurally generated
// as clusters of colored square tiles (OpenTTD-style). The world scrolls
// over a tiled sea texture, and ImGui handles HUD/info panels.
//
// Architecture overview:
//   - RNG (LCG) drives all procedural generation from a single seed
//   - Islands are placed via rejection sampling with minimum spacing
//   - Each island's shape is a BFS flood-fill of grid-aligned tiles
//   - Camera uses Raylib's Camera2D for pan/zoom over world space
//   - ImGui overlays HUD panels in screen space on top of the 2D world

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import imgui "../lib/odin-imgui"
import rlimgui "../lib/imgui_impl_raylib"

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// DEFAULT_SEED — deterministic seed so islands are reproducible across runs.
// Changing this value produces an entirely different world layout.
DEFAULT_SEED :: 42

// MAX_ISLANDS — upper bound on the number of islands generated at startup.
// Stored as a fixed array in App, so this caps memory usage.
MAX_ISLANDS :: 24

// MAX_TILES — maximum tiles per island. The BFS flood-fill stops here.
// 800 tiles at 32px each gives islands up to ~25 tiles across.
MAX_TILES :: 800

// TILE_SIZE — pixel size of each square tile. Larger values = chunkier islands.
TILE_SIZE :: 32

// ---------------------------------------------------------------------------
// Resource types — what each island produces
// ---------------------------------------------------------------------------

// ResourceType enumerates the six cargo types in the game.
// Each island produces exactly one type, determined at generation time.
ResourceType :: enum {
    WOOD, FISH, ORE, METAL, OIL, LUXURY,
}

// resource_names — human-readable labels for display in HUD and world labels.
resource_names := [?]cstring {
    "Wood", "Fish", "Ore", "Metal", "Oil", "Luxury",
}

// resource_colors — tile fill colors, one per ResourceType.
// Indexed by ResourceType value, so resource_colors[WOOD] = brown.
resource_colors := [?]rl.Color {
    {139, 90, 43, 255},    // WOOD — warm brown
    {70, 130, 180, 255},   // FISH — steel blue
    {128, 128, 128, 255},  // ORE — neutral gray
    {192, 192, 192, 255},  // METAL — light silver
    {30, 30, 30, 255},     // OIL — near-black
    {255, 215, 0, 255},    // LUXURY — gold
}

// ---------------------------------------------------------------------------
// Core data structures
// ---------------------------------------------------------------------------

// Tile — a single grid-aligned square that makes up part of an island's shape.
// Coordinates are in tile-grid space; multiply by TILE_SIZE to get world pixels.
Tile :: struct {
    gx: i32,  // grid X coordinate (world_x = gx * TILE_SIZE)
    gy: i32,  // grid Y coordinate (world_y = gy * TILE_SIZE)
}

// Island — a landmass with a unique id, procedural tile shape, and economic data.
// Islands are stored in a fixed-size array and identified by index (0..MAX_ISLANDS-1).
// The `tiles` array holds the BFS-generated shape; `tile_count` is the actual count.
Island :: struct {
    id:         int,            // unique identifier, 0-based index
    pos:        rl.Vector2,     // center position in world space
    name:       [32]u8,         // fixed-buffer name (null-terminated)
    name_len:   int,            // length of name in bytes
    production: ResourceType,   // what this island produces
    rate:       f32,            // units produced per in-game day
    warehouse:  f32,            // current cargo stored (starts at 0)
    max_ware:   f32,            // warehouse capacity (set at generation)
    dock_level: int,            // affects loading speed (1-3, set at generation)
    radius:     f32,            // bounding radius for spacing checks
    tiles:      [MAX_TILES]Tile, // BFS-generated tile positions
    tile_count: int,            // actual number of tiles placed
}

// Rng — simple LCG-based pseudorandom number generator.
// State is seeded once; all subsequent values are deterministic.
// LCG formula: state = state * 1103515245 + 12345 (glibc constants).
Rng :: struct {
    state: u32,
}

// ---------------------------------------------------------------------------
// RNG utilities
// ---------------------------------------------------------------------------

// seed_rng initializes the RNG state. The `| 1` ensures the state is never
// zero, which would lock the LCG into an infinite zero-output loop.
seed_rng :: proc(seed: u32) -> Rng {
    return {state = seed | 1}
}

// lcg_next advances the LCG and returns the new state as a raw u32.
// The caller modulos this into the desired range.
lcg_next :: proc(rng: ^Rng) -> u32 {
    rng.state = (rng.state * 1103515245) + 12345
    return rng.state
}

// next_f32 returns a random float in [min_val, max_val).
// Uses modulo 10000 for ~0.01% resolution; sufficient for game values.
next_f32 :: proc(rng: ^Rng, min_val, max_val: f32) -> f32 {
    return min_val + f32(lcg_next(rng) % 10000) / 10000.0 * (max_val - min_val)
}

// next_int returns a random int in [min_val, max_val).
next_int :: proc(rng: ^Rng, min_val, max_val: int) -> int {
    return min_val + int(lcg_next(rng) % u32(max_val - min_val))
}

// ---------------------------------------------------------------------------
// Island generation — procedural tile shapes via BFS flood fill
// ---------------------------------------------------------------------------

// generate_tiles creates an organic blob of tiles around a center point
// using randomized BFS flood fill. The algorithm:
//   1. Place the first tile at the center grid cell
//   2. Pick a random existing tile, try to expand in a random direction
//   3. If expansion fails (blocked or full), scan all tiles for any opening
//   4. Repeat until `count` tiles are placed or no expansion is possible
//
// The result is an irregular, island-like shape. The `grid` array is a
// local coordinate system offset by (ox, oy) so the center sits at [128][128].
generate_tiles :: proc(rng: ^Rng, center: rl.Vector2, count: int, tiles: ^[MAX_TILES]Tile, out_count: ^int) {
    // Convert world position to grid coordinates
    cx := i32(center.x / TILE_SIZE)
    cy := i32(center.y / TILE_SIZE)

    // Track which tiles have been placed (for the random-selection pool)
    placed: [MAX_TILES]bool

    // Local grid: -1 = empty, >= 0 = tile index. 256x256 gives ±128 tiles range.
    grid: [256][256]i32
    for i in 0..<256 {
        for j in 0..<256 {
            grid[i][j] = -1
        }
    }

    // Offset so center maps to grid[128][128]
    ox := cx - 128
    oy := cy - 128

    // Place the seed tile at center
    grid[128][128] = 0
    tiles[0] = {cx, cy}
    placed[0] = true
    total := 1

    // Cardinal directions for neighbor expansion
    dirs := [4][2]i32 {
        {1, 0}, {-1, 0}, {0, 1}, {0, -1},
    }

    for total < count && total < MAX_TILES {
        // Pick a random already-placed tile as expansion base
        idx := int(lcg_next(rng) % u32(total))
        base := tiles[idx]

        // Fisher-Yates shuffle of direction indices for random expansion order
        shuffled := [4]int { 0, 1, 2, 3 }
        for k in 0..<3 {
            s := 3 - k
            j2 := int(lcg_next(rng) % u32(s + 1))
            shuffled[s], shuffled[j2] = shuffled[j2], shuffled[s]
        }

        // Try to expand from the randomly chosen base tile
        expanded := false
        for s in 0..<4 {
            d := dirs[shuffled[s]]
            nx := base.gx + d[0]
            ny := base.gy + d[1]
            gx_idx := nx - ox
            gy_idx := ny - oy

            // Bounds check and collision check
            if gx_idx < 0 || gx_idx >= 256 || gy_idx < 0 || gy_idx >= 256 { continue }
            if grid[gy_idx][gx_idx] >= 0 { continue }

            // Place the new tile
            grid[gy_idx][gx_idx] = i32(total)
            tiles[total] = {nx, ny}
            placed[total] = true
            total += 1
            expanded = true
            break
        }

        // Fallback: scan all placed tiles for any available neighbor
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

        // Island is fully surrounded — stop expanding
        if !expanded { break }
    }

    out_count^ = total
}

// ---------------------------------------------------------------------------
// Island name data
// ---------------------------------------------------------------------------

// island_names — pool of names assigned to islands in order.
// Must have at least MAX_ISLANDS entries.
island_names := [?]cstring {
    "Port Haven", "Iron Bay", "Coral Reef", "Storm Point",
    "Gold Coast", "Fog Harbor", "Tide Watch", "Ember Isle",
    "Salt Marsh", "Driftwood", "Pearl Bay", "Rust Dock",
    "Copper Peak", "Silver Shore", "Kelp Forest", "Turtle Rock",
    "Moon Harbor", "Anvil Port", "Flint Isle", "Cedar Landing",
    "Stone Gate", "Coral Spire", "Wave Crest", "Amber Dock",
}

// generate_islands creates `count` islands with procedural positions and
// tile shapes. Placement uses rejection sampling (random candidate + spacing
// check) with a fallback ring layout if random placement fails after 300 attempts.
//
// The map spans from (-2000, -2000) to (15000, 10000) in world units.
// Islands need MIN_SPACING + both radii of clearance to avoid overlap.
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

        // Rejection sampling: try random positions until one fits
        placed := false
        for attempt in 0..<300 {
            candidate := rl.Vector2{
                next_f32(&rng, MAP_MIN_X + 200, MAP_MAX_X - 200),
                next_f32(&rng, MAP_MIN_Y + 200, MAP_MAX_Y - 200),
            }

            // Check spacing against all previously placed islands
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

        // Fallback: place on concentric rings around map center
        if !placed {
            angle := f32(i) * (2.0 * 3.14159 / f32(count))
            center_x := (MAP_MIN_X + MAP_MAX_X) / 2
            center_y := (MAP_MIN_Y + MAP_MAX_Y) / 2
            ring := f32(1500 + (i / 4) * 1500)
            pos = {center_x + ring * math.cos(angle), center_y + ring * math.sin(angle)}
        }

        // Assign all island properties
        islands[i].id = i
        islands[i].pos = pos
        islands[i].radius = radius
        islands[i].production = ResourceType(lcg_next(&rng) % 6)
        islands[i].rate = next_f32(&rng, 1, 5)
        islands[i].warehouse = 0
        islands[i].max_ware = next_f32(&rng, 50, 200)
        islands[i].dock_level = next_int(&rng, 1, 4)

        // Generate the island's tile shape
        generate_tiles(&rng, pos, tile_count, &islands[i].tiles, &islands[i].tile_count)

        // Copy name from pool into the island's fixed buffer
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

// get_name returns the island's name as a null-terminated cstring.
// Uses a stack buffer since raylib text functions expect cstring.
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

// App — top-level game state. Holds all islands, camera, selection, economy,
// and rendering state. Passed by pointer to all update/draw functions.
App :: struct {
    islands:      [MAX_ISLANDS]Island,  // all generated islands
    island_count: int,                   // actual count (<= MAX_ISLANDS)
    seed:         u32,                   // current world seed
    camera:       rl.Camera2D,           // 2D camera for pan/zoom
    selected:     int,                   // index of selected island (-1 = none)
    money:        f32,                   // player's current cash
    time_day:     f32,                   // in-game day counter (incremented each frame)
    scroll_tex:   rl.Texture2D,          // sea texture for tiling background
    bg_color:     rl.Color,              // clear color sampled from sea texture center
    scroll_x:     f32,                   // horizontal scroll offset for sea animation
    scroll_y:     f32,                   // vertical scroll offset for sea animation
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

main :: proc() {
    // Window setup — resizable, runs in background
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .WINDOW_ALWAYS_RUN})
    rl.InitWindow(1280, 720, "Ocean Circuit")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    // ImGui setup — Dear ImGui context + Raylib backend
    imgui.CreateContext(nil)
    defer imgui.DestroyContext(nil)
    io := imgui.GetIO()
    io.ConfigFlags |= {.NavEnableKeyboard}
    rlimgui.init()
    defer rlimgui.shutdown()

    // Initialize game state
    app: App
    app.seed = DEFAULT_SEED
    app.islands = generate_islands(app.seed, MAX_ISLANDS)
    app.island_count = MAX_ISLANDS
    app.money = 1000
    app.selected = -1

    // Camera: offset anchors screen center, target is world-space focus point
    app.camera.offset = {640, 360}
    app.camera.target = {6500, 4000}
    app.camera.rotation = 0
    app.camera.zoom = 0.12

    // Load sea texture for tiling background
    app.scroll_tex = rl.LoadTexture("assets/img/sea_texture.jpg")
    defer rl.UnloadTexture(app.scroll_tex)

    // Sample the sea texture's center pixel for the background clear color.
    // This avoids dark blue gaps when the texture tiles don't perfectly cover edges.
    img := rl.LoadImage("assets/img/sea_texture.jpg")
    defer rl.UnloadImage(img)
    colors := rl.LoadImageColors(img)
    center_pixel := colors[(img.height / 2) * img.width + img.width / 2]
    app.bg_color = {center_pixel.r, center_pixel.g, center_pixel.b, 255}

    // Main game loop
    for !rl.WindowShouldClose() {
        update_camera(&app)
        app.time_day += rl.GetFrameTime() / 60.0

        rl.BeginDrawing()
        rl.ClearBackground(app.bg_color)

        // World-space rendering (transformed by camera)
        rl.BeginMode2D(app.camera)
        draw_water(&app)
        draw_islands(&app)
        rl.EndMode2D()

        // Screen-space ImGui overlay (HUD panels)
        rlimgui.begin()
        draw_hud(&app)
        rlimgui.end()

        // Left-click on the world selects an island, but only if ImGui
        // didn't capture the mouse (prevents deselecting when clicking panels)
        if rl.IsMouseButtonPressed(.LEFT) && !imgui.GetIO().WantCaptureMouse {
            handle_click(&app)
        }

        rl.EndDrawing()
    }
}

// ---------------------------------------------------------------------------
// Camera — right-drag to pan, scroll to zoom
// ---------------------------------------------------------------------------

// update_camera handles camera input each frame:
//   - Right mouse button drag: pans the camera by adjusting the target position.
//     Delta is divided by zoom so panning speed feels consistent at all zoom levels.
//   - Mouse wheel: zooms in/out. Clamped to [0.03, 3.0] to prevent extreme states.
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

// draw_water tiles the sea texture across a large grid in world space.
// The texture slowly scrolls (scroll_x, scroll_y) to create a moving ocean.
// Grid range is fixed at -10..60 x -10..40 tiles to cover the entire map
// at any zoom level. The camera transform (BeginMode2D) handles visibility.
draw_water :: proc(app: ^App) {
    tex_w := f32(app.scroll_tex.width)
    tex_h := f32(app.scroll_tex.height)

    // Advance scroll offsets each frame (wraps at texture boundary)
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

// draw_islands renders each island's tiles, outlines, name label, and
// resource indicator. Selected island gets a yellow highlight behind tiles.
// Text uses black drop-shadow for readability against the sea background.
draw_islands :: proc(app: ^App) {
    for i in 0..<app.island_count {
        island := &app.islands[i]
        color := resource_colors[island.production]
        tile_pixel := f32(TILE_SIZE)

        // Draw each tile: fill + dark outline
        for t in 0..<island.tile_count {
            tile := &island.tiles[t]
            x := f32(tile.gx) * tile_pixel
            y := f32(tile.gy) * tile_pixel

            // Selection highlight (drawn behind the tile)
            if app.selected == i {
                rl.DrawRectangle(i32(x) - 1, i32(y) - 1, i32(tile_pixel) + 2, i32(tile_pixel) + 2, {255, 255, 100, 60})
            }

            rl.DrawRectangleV({x, y}, {tile_pixel, tile_pixel}, color)
            rl.DrawRectangleLinesEx({x, y, tile_pixel, tile_pixel}, 2, {20, 20, 20, 200})
        }

        // Island name — centered below the island, white text with black shadow
        name := get_name(island^)
        text_w := rl.MeasureText(name, 32)
        name_x := i32(island.pos.x) - text_w / 2
        name_y := i32(island.pos.y + island.radius + 16)
        rl.DrawText(name, name_x + 2, name_y + 2, 32, {0, 0, 0, 200})
        rl.DrawText(name, name_x, name_y, 32, {255, 255, 255, 255})

        // Resource label — centered above the island
        res_name := resource_names[island.production]
        res_w := rl.MeasureText(res_name, 24)
        res_x := i32(island.pos.x) - res_w / 2
        res_y := i32(island.pos.y - 20)
        rl.DrawText(res_name, res_x + 2, res_y + 2, 24, {0, 0, 0, 200})
        rl.DrawText(res_name, res_x, res_y, 24, {255, 255, 255, 255})
    }
}

// draw_hud renders ImGui panels: a persistent info panel (top-left) showing
// seed/money/day, and a conditional island detail panel when an island is selected.
// ImGui windows are draggable and styled by default.
draw_hud :: proc(app: ^App) {
    // Info panel — always visible
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

    // Island detail panel — only shown when an island is selected
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

// handle_click converts the mouse screen position to world space and checks
// every tile of every island for a hit. Sets app.selected to the first
// matching island index, or -1 if nothing was clicked.
//
// This is per-tile AABB testing — efficient enough for ~24 islands x ~500 tiles.
// Called only when ImGui doesn't want the mouse (see WantCaptureMouse check).
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
