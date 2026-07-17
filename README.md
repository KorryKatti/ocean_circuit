# Ocean Circuit

- a spreadsheet simulator

The world map is a CSV spreadsheet — each cell is a tile, `.` is water, letters are land. Edit it in LibreOffice, the game reads it at runtime. Odin + Raylib + Dear ImGui.

## Build

```bash
./build.sh
```

## Generate Map

```bash
python3 tools/generate_map.py
```

## Controls

WASD to move, scroll to zoom, click to select island.
