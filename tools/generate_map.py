#!/usr/bin/env python3
"""Generate a grid-based map CSV for Ocean Circuit.

Each cell is one tile. '.' = water, letter = resource type.
Adjacent non-water cells form an island (flood-fill grouped).

Usage:
    python3 generate_map.py                     # defaults: 100x75, 8 islands
    python3 generate_map.py --width 120 --height 90 --islands 12
    python3 generate_map.py --seed 42           # deterministic output
"""

import argparse
import csv
import random
import sys
from collections import deque
from pathlib import Path

# Resource types: single char -> full name
RESOURCES = {
    "W": "Wood",
    "F": "Fish",
    "O": "Ore",
    "M": "Metal",
    "L": "Luxury",
    "P": "Port",
}

RESOURCE_CHARS = list(RESOURCES.keys())
RESOURCE_CHARS_NO_PORT = ["W", "F", "O", "M", "L"]

# Island metadata defaults
DEFAULT_RATES = {"W": 2.5, "F": 1.8, "O": 3.0, "M": 2.0, "L": 1.2, "P": 0.0}
DEFAULT_MAX_WARE = {"W": 120, "F": 80, "O": 150, "M": 100, "L": 60, "P": 0}
DEFAULT_DOCK_LEVELS = [1, 2, 2, 3]

ISLAND_NAMES = [
    "Port Haven", "Iron Bay", "Coral Reef", "Storm Point",
    "Gold Coast", "Fog Harbor", "Tide Watch", "Ember Isle",
    "Salt Marsh", "Driftwood", "Pearl Bay", "Rust Dock",
    "Copper Peak", "Silver Shore", "Kelp Forest", "Turtle Rock",
    "Moon Harbor", "Anvil Port", "Flint Isle", "Cedar Landing",
    "Stone Gate", "Coral Spire", "Wave Crest", "Amber Dock",
]


def make_grid(width, height):
    return [["." for _ in range(width)] for _ in range(height)]


def neighbors(x, y):
    for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
        nx, ny = x + dx, y + dy
        yield nx, ny


def flood_fill_islands(grid, width, height):
    """Group adjacent non-water cells into islands. Returns list of (cells, resource_char)."""
    visited = set()
    islands = []

    for y in range(height):
        for x in range(width):
            if (x, y) in visited or grid[y][x] == ".":
                continue

            resource = grid[y][x]
            cells = []
            queue = deque([(x, y)])
            visited.add((x, y))

            while queue:
                cx, cy = queue.popleft()
                cells.append((cx, cy))
                for nx, ny in neighbors(cx, cy):
                    if 0 <= nx < width and 0 <= ny < height:
                        if (nx, ny) not in visited and grid[ny][nx] == resource:
                            visited.add((nx, ny))
                            queue.append((nx, ny))

            islands.append((cells, resource))

    return islands


def generate_blob(grid, width, height, cx, cy, resource, size, rng):
    """Grow an organic blob around (cx, cy) using random walk."""
    grid[cy][cx] = resource
    placed = [(cx, cy)]
    attempts = 0
    max_attempts = size * 20

    while len(placed) < size and attempts < max_attempts:
        attempts += 1
        # Pick a random existing cell
        bx, by = placed[rng.randint(0, len(placed) - 1)]
        # Pick a random neighbor direction
        dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        rng.shuffle(dirs)
        dx, dy = dirs[0]
        nx, ny = bx + dx, by + dy

        if 0 <= nx < width and 0 <= ny < height and grid[ny][nx] == ".":
            # Check spacing: don't touch other non-water cells
            too_close = False
            for nnx, nny in neighbors(nx, ny):
                if (nnx, nny) != (bx, by) and 0 <= nnx < width and 0 <= nny < height:
                    if grid[nny][nnx] != "." and grid[nny][nnx] != resource:
                        too_close = True
                        break
            if not too_close:
                grid[ny][nx] = resource
                placed.append((nx, ny))

    return placed


def generate_map(width, height, num_islands, seed):
    rng = random.Random(seed)
    grid = make_grid(width, height)

    # Margins — keep islands away from edges
    margin = 3
    min_spacing = 50

    placed_centers = []

    for i in range(num_islands):
        # First island is always PORT (spawn point)
        resource = "P" if i == 0 else RESOURCE_CHARS_NO_PORT[(i - 1) % len(RESOURCE_CHARS_NO_PORT)]
        island_size = rng.randint(4400, 15000)

        # Try to find a valid center
        success = False
        for _ in range(200):
            cx = rng.randint(margin, width - margin - 1)
            cy = rng.randint(margin, height - margin - 1)

            # Check spacing from other islands
            valid = True
            for px, py in placed_centers:
                if abs(cx - px) < min_spacing and abs(cy - py) < min_spacing:
                    valid = False
                    break

            if valid and grid[cy][cx] == ".":
                generate_blob(grid, width, height, cx, cy, resource, island_size, rng)
                placed_centers.append((cx, cy))
                success = True
                break

        if not success:
            print(f"Warning: could not place island {i} after 200 attempts", file=sys.stderr)

    return grid


def write_map_csv(grid, width, height, path):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        for row in grid:
            writer.writerow(row)
    print(f"Wrote map: {path} ({width}x{height})")


def write_metadata_csv(grid, width, height, seed, path):
    islands = flood_fill_islands(grid, width, height)
    rng = random.Random(seed + 1000)

    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "island_id", "name", "production", "production_name",
            "rate", "max_warehouse", "dock_level", "tile_count",
        ])

        for idx, (cells, resource) in enumerate(islands):
            name = ISLAND_NAMES[idx % len(ISLAND_NAMES)]
            if idx >= len(ISLAND_NAMES):
                name += f" {idx // len(ISLAND_NAMES) + 1}"

            writer.writerow([
                idx,
                name,
                resource,
                RESOURCES[resource],
                DEFAULT_RATES.get(resource, 2.0),
                DEFAULT_MAX_WARE.get(resource, 100),
                rng.choice(DEFAULT_DOCK_LEVELS),
                len(cells),
            ])

    print(f"Wrote metadata: {path} ({len(islands)} islands)")


def main():
    parser = argparse.ArgumentParser(description="Generate Ocean Circuit map CSV")
    parser.add_argument("--width", type=int, default=4000, help="Grid width (default: 4000)")
    parser.add_argument("--height", type=int, default=3250, help="Grid height (default: 3250)")
    parser.add_argument("--islands", type=int, default=24, help="Number of islands (default: 24)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed (default: 42)")
    parser.add_argument("--output", type=str, default="map.csv", help="Output map CSV path")
    parser.add_argument("--meta", type=str, default="metadata.csv", help="Output metadata CSV path")
    args = parser.parse_args()

    grid = generate_map(args.width, args.height, args.islands, args.seed)

    # Preview
    islands = flood_fill_islands(grid, args.width, args.height)
    print(f"Generated {len(islands)} islands:")
    for idx, (cells, resource) in enumerate(islands):
        xs = [c[0] for c in cells]
        ys = [c[1] for c in cells]
        print(f"  {idx}: {RESOURCES[resource]:>6} | {len(cells):>3} tiles | "
              f"pos=({min(xs)}-{max(xs)}, {min(ys)}-{max(ys)})")

    write_map_csv(grid, args.width, args.height, args.output)
    write_metadata_csv(grid, args.width, args.height, args.seed, args.meta)


if __name__ == "__main__":
    main()
