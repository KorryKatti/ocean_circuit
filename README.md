# Ocean Circuit

A naval shipping economy game — top-down 2D, pan/zoom camera, ship exploration and
port discovery.

![](https://i.ibb.co/HTnhdNHC/image.png)

## Requirements

- Godot 4.4+ (developed against 4.7.2)
- The generated map CSVs in `data/` — already present, regenerate with
  `python3 tools/generate_map.py`

## Run

```bash
./run.sh
```

Or `godot --path .`, or open the folder in the Godot editor and press F5.

If `godot` is not on your PATH (Steam installs it outside it):

```bash
ln -sf "$HOME/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64" ~/.local/bin/godot
```

## Generate Map

The world is generated, not committed. `tools/generate_map.py` writes the four CSVs
that the game loads from `data/`:

```bash
python3 tools/generate_map.py
cp assets/data/*.csv data/
```

| File | Contents |
|---|---|
| `map.csv` | 4000x3250 grid of resource chars, `.` is water |
| `islands.csv` | 182k rows of `island_id,x,y` — one row per land tile |
| `ports.csv` | 2519 rows of `island_id,x,y` — dock tiles |
| `metadata.csv` | 24 rows: island name, production, rate, dock level |

`data/` contains a `.gdignore`, so Godot does not import these as resources. They are
read at runtime from an absolute path via `ProjectSettings.globalize_path`.

## How to play

You run a shipping company. Islands produce a resource into their warehouse over
time, warehouses cap out, and your ships move the excess somewhere that pays for
it. **Reach $20,000 to win.**

- Ships find their own work. An empty ship sails to the nearest island with stock,
  loads up to its cargo hold, then sails to the nearest island that does *not*
  produce that resource and sells it.
- Click an island to send the selected ship there instead.
- Spend earnings on **Buy Cargo Ship** ($5000). More ships means more income.
- `TAB` or the `<` `>` buttons cycle which ship the panel is showing.

Resource prices are fixed: Wood $12, Fish $15, Ore $20, Metal $26, Oil $40,
Luxury $70. A full hold of Luxury pays for the whole game on its own, so the late
game is about reaching one.

## Controls

| Input | Action |
|---|---|
| `WASD` | move the player |
| Scroll | zoom |
| Drag / arrow keys | pan camera |
| Click island | send selected ship there |
| Click ship | select that ship |
| `C` | toggle camera between player and selected ship |
| `TAB` | next ship |
| `SPACE` | pause / resume |
| `1` `2` `3` | speed 1x / 2x / 4x |
| `B` | buy a cargo ship |

Selecting a ship also gives the older **Ship Orders** panel: set *k* and press
**Send to Explore** to route it to the *k* nearest undiscovered islands (0 = all).

Undiscovered islands are drawn as dark silhouettes until a port on them is visited.
Fog is visual only — production and trade work everywhere from the start.

## Layout

```
project.godot
data/                 generated map CSVs (gitignored)
assets/img/           sea and ship textures
src/core/             data + simulation, no rendering
  game_defs.gd        constants, resource types and colours
  csv_loader.gd       CSV parsing
  map_grid.gd         the water/land grid
  island_data.gd      one island: tiles, ports, bounds
  world_data.gd       all islands + discovery state
  ship_type.gd        23 ship types and their stat table
  game_rules.gd       prices, day length, win target
src/world/            nodes that draw the world
  main.gd             orchestrator, camera, input
  island_renderer.gd  182k tiles drawn as one MultiMesh
  water.gd            scrolling sea
  ship.gd             movement, waypoint routing, sensors
  player.gd           WASD movement with tile collision
src/ui/hud.gd         HUD panels
tools/generate_map.py world generator
tools/dev/            headless smoke test + screenshot helper
legacy_odin/          the original Odin/raylib/ImGui implementation
```

## Dev tools

```bash
# simulate 120s of exploration headlessly and assert it works
godot --headless --path . --script res://tools/dev/smoke_test.gd

# simulate the economy for 4 minutes and assert deliveries + income happen
godot --headless --path . --script res://tools/dev/economy_test.gd

# write a screenshot to /tmp/opencode/shot.png
godot --path . --script res://tools/dev/screenshot.gd
```

## Legacy

`legacy_odin/` is the original Odin + raylib + Dear ImGui version, kept for
reference. Build it with `legacy_odin/build.sh`. It is no longer maintained.
