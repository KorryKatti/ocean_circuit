#!/usr/bin/env python3
"""Generate a grid-based map CSV for Ocean Circuit.

Each cell is one tile. '.' = water, letter = resource type.
Adjacent non-water cells form an island (flood-fill grouped).

Port tiles are tracked separately in a ports CSV — they are NOT
written into the map grid. This keeps flood fill clean and avoids
island-merging bugs.

Usage:
    python3 generate_map.py                     # defaults: 4000x3250, 24 islands
    python3 generate_map.py --width 120 --height 90 --islands 12
    python3 generate_map.py --seed 42           # deterministic output
"""

from __future__ import annotations

import argparse
import csv
import random
import sys
from collections import deque
from typing import List, Tuple, Dict, Set

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

RESOURCES: Dict[str, str] = {
    "W": "Wood", "F": "Fish", "O": "Ore",
    "M": "Metal", "L": "Luxury", "P": "Port",
}

RESOURCE_CHARS_NO_PORT: List[str] = ["W", "F", "O", "M", "L"]

DEFAULT_RATES: Dict[str, float] = {
    "W": 2.5, "F": 1.8, "O": 3.0, "M": 2.0, "L": 1.2, "P": 0.0,
}
DEFAULT_MAX_WARE: Dict[str, float] = {
    "W": 120, "F": 80, "O": 150, "M": 100, "L": 60, "P": 0,
}
DEFAULT_DOCK_LEVELS: List[int] = [1, 2, 2, 3]

ISLAND_NAMES: List[str] = [
    "Port Haven", "Iron Bay", "Coral Reef", "Storm Point",
    "Gold Coast", "Fog Harbor", "Tide Watch", "Ember Isle",
    "Salt Marsh", "Driftwood", "Pearl Bay", "Rust Dock",
    "Copper Peak", "Silver Shore", "Kelp Forest", "Turtle Rock",
    "Moon Harbor", "Anvil Port", "Flint Isle", "Cedar Landing",
    "Stone Gate", "Coral Spire", "Wave Crest", "Amber Dock",
]

PORT_COVERAGE_MIN: float = 0.15
PORT_COVERAGE_MAX: float = 0.35
PORT_CLUSTER_SIZE: int = 3
PORT_CLUSTER_JITTER: int = 2

DIRS_4: List[Tuple[int, int]] = [(1, 0), (-1, 0), (0, 1), (0, -1)]


# ---------------------------------------------------------------------------
# Grid helpers
# ---------------------------------------------------------------------------

def make_grid(width: int, height: int) -> List[List[str]]:
    """Create a water-filled grid of the given dimensions."""
    grid: List[List[str]] = []
    for _ in range(height):
        row: List[str] = []
        for _ in range(width):
            row.append(".")
        grid.append(row)
    return grid


def get_neighbors(x: int, y: int) -> List[Tuple[int, int]]:
    """Return the 4 adjacent cells. Does NOT check bounds."""
    result: List[Tuple[int, int]] = []
    for dx, dy in DIRS_4:
        result.append((x + dx, y + dy))
    return result


# ---------------------------------------------------------------------------
# Flood fill — groups grid cells into islands
# ---------------------------------------------------------------------------

def flood_fill_islands(
    grid: List[List[str]],
    width: int,
    height: int,
) -> List[Tuple[List[Tuple[int, int]], str]]:
    """Group adjacent non-water cells into islands.

    'P' tiles are NEVER in the grid — ports are tracked separately.
    """
    visited: Set[Tuple[int, int]] = set()
    islands: List[Tuple[List[Tuple[int, int]], str]] = []

    for y in range(height):
        for x in range(width):
            if (x, y) in visited or grid[y][x] == ".":
                continue

            resource: str = grid[y][x]
            cells: List[Tuple[int, int]] = []
            queue: deque[Tuple[int, int]] = deque([(x, y)])
            visited.add((x, y))

            while len(queue) > 0:
                cx, cy = queue.popleft()
                cells.append((cx, cy))

                for nx, ny in get_neighbors(cx, cy):
                    if nx < 0 or nx >= width or ny < 0 or ny >= height:
                        continue
                    if (nx, ny) in visited:
                        continue
                    if grid[ny][nx] == resource:
                        visited.add((nx, ny))
                        queue.append((nx, ny))

            islands.append((cells, resource))

    return islands


# ---------------------------------------------------------------------------
# Blob generation — grows organic island shapes
# ---------------------------------------------------------------------------

def generate_blob(
    grid: List[List[str]],
    width: int,
    height: int,
    cx: int,
    cy: int,
    resource: str,
    size: int,
    rng: random.Random,
) -> List[Tuple[int, int]]:
    """Grow an organic blob around (cx, cy) using random walk."""
    grid[cy][cx] = resource
    placed: List[Tuple[int, int]] = [(cx, cy)]
    attempts: int = 0
    max_attempts: int = size * 20

    while len(placed) < size and attempts < max_attempts:
        attempts += 1
        bx, by = placed[random.randint(0, len(placed) - 1)]
        dirs_copy: List[Tuple[int, int]] = list(DIRS_4)
        rng.shuffle(dirs_copy)
        dx, dy = dirs_copy[0]
        nx, ny = bx + dx, by + dy

        if nx < 0 or nx >= width or ny < 0 or ny >= height:
            continue
        if grid[ny][nx] != ".":
            continue

        too_close: bool = False
        for nnx, nny in get_neighbors(nx, ny):
            if (nnx, nny) == (bx, by):
                continue
            if nnx < 0 or nnx >= width or nny < 0 or nny >= height:
                continue
            if grid[nny][nnx] != "." and grid[nny][nnx] != resource:
                too_close = True
                break

        if not too_close:
            grid[ny][nx] = resource
            placed.append((nx, ny))

    return placed


# ---------------------------------------------------------------------------
# Port detection — finds coastal tiles without modifying the grid
# ---------------------------------------------------------------------------

def find_sea_facing_tiles(
    cells: List[Tuple[int, int]],
    grid: List[List[str]],
    width: int,
    height: int,
    ocean_tiles: Set[Tuple[int, int]],
) -> List[Tuple[int, int]]:
    """Return island tiles that are adjacent to ocean-connected water."""
    sea_facing: List[Tuple[int, int]] = []

    for x, y in cells:
        for nx, ny in get_neighbors(x, y):
            if (nx, ny) in ocean_tiles:
                sea_facing.append((x, y))
                break

    return sea_facing


def find_ocean_tiles(
    grid: List[List[str]],
    width: int,
    height: int,
) -> Set[Tuple[int, int]]:
    """Find all water tiles connected to the map edge (ocean, not lakes)."""
    ocean: Set[Tuple[int, int]] = set()
    queue: deque[Tuple[int, int]] = deque()

    # Seed from all edge water tiles
    for x in range(width):
        if grid[0][x] == ".":
            queue.append((x, 0))
            ocean.add((x, 0))
        if grid[height - 1][x] == ".":
            queue.append((x, height - 1))
            ocean.add((x, height - 1))
    for y in range(height):
        if grid[y][0] == ".":
            queue.append((0, y))
            ocean.add((0, y))
        if grid[y][width - 1] == ".":
            queue.append((width - 1, y))
            ocean.add((width - 1, y))

    # BFS to find all connected water
    while len(queue) > 0:
        cx, cy = queue.popleft()
        for nx, ny in get_neighbors(cx, cy):
            if nx < 0 or nx >= width or ny < 0 or ny >= height:
                continue
            if (nx, ny) in ocean:
                continue
            if grid[ny][nx] == ".":
                ocean.add((nx, ny))
                queue.append((nx, ny))

    return ocean


def group_coast_segments(sea_facing: List[Tuple[int, int]]) -> List[List[Tuple[int, int]]]:
    """Group adjacent sea-facing tiles into contiguous coast segments."""
    remaining: Set[Tuple[int, int]] = set(sea_facing)
    segments: List[List[Tuple[int, int]]] = []

    while len(remaining) > 0:
        start: Tuple[int, int] = next(iter(remaining))
        segment: List[Tuple[int, int]] = []
        queue: deque[Tuple[int, int]] = deque([start])
        remaining.discard(start)

        while len(queue) > 0:
            cx, cy = queue.popleft()
            segment.append((cx, cy))
            for nx, ny in get_neighbors(cx, cy):
                if (nx, ny) in remaining:
                    remaining.discard((nx, ny))
                    queue.append((nx, ny))

        segments.append(segment)

    return segments


def pick_port_positions(
    cells: List[Tuple[int, int]],
    grid: List[List[str]],
    width: int,
    height: int,
    rng: random.Random,
    ocean_tiles: Set[Tuple[int, int]],
) -> List[Tuple[int, int]]:
    """Pick port tile positions on the coast WITHOUT modifying the grid.

    Returns a list of (x, y) positions that should be rendered as ports.
    Only places ports adjacent to ocean-connected water, not inland lakes.
    """
    sea_facing: List[Tuple[int, int]] = find_sea_facing_tiles(cells, grid, width, height, ocean_tiles)
    if len(sea_facing) == 0:
        return []

    target_count: int = int(len(sea_facing) * rng.uniform(PORT_COVERAGE_MIN, PORT_COVERAGE_MAX))
    if target_count < 1:
        target_count = 1

    segments: List[List[Tuple[int, int]]] = group_coast_segments(sea_facing)
    if len(segments) == 0:
        return []

    rng.shuffle(segments)
    ports: List[Tuple[int, int]] = []

    for segment in segments:
        if len(ports) >= target_count:
            break

        cluster_len: int = PORT_CLUSTER_SIZE + rng.randint(-PORT_CLUSTER_JITTER, PORT_CLUSTER_JITTER)
        cluster_len = max(1, min(cluster_len, len(segment)))

        start_idx: int = rng.randint(0, max(0, len(segment) - cluster_len))
        end_idx: int = min(start_idx + cluster_len, len(segment))

        for i in range(start_idx, end_idx):
            if len(ports) >= target_count:
                break
            ports.append(segment[i])

    return ports


# ---------------------------------------------------------------------------
# Map generation — main entry point
# ---------------------------------------------------------------------------

def generate_map(
    width: int,
    height: int,
    num_islands: int,
    seed: int,
) -> Tuple[List[List[str]], List[List[Tuple[int, int]]], List[List[Tuple[int, int]]]]:
    """Generate the full tile grid, cell lists, and port positions per island.

    Returns (grid, cell_lists, port_lists).
    """
    rng: random.Random = random.Random(seed)
    grid: List[List[str]] = make_grid(width, height)

    margin: int = 3
    min_spacing: int = 50
    placed_centers: List[Tuple[int, int]] = []
    all_cell_lists: List[List[Tuple[int, int]]] = []
    all_port_lists: List[List[Tuple[int, int]]] = []

    for i in range(num_islands):
        is_spawn: bool = (i == 0)
        resource: str = "W" if is_spawn else RESOURCE_CHARS_NO_PORT[(i - 1) % len(RESOURCE_CHARS_NO_PORT)]
        island_size: int = rng.randint(4400, 15000)

        success: bool = False
        for _ in range(200):
            cx: int = rng.randint(margin, width - margin - 1)
            cy: int = rng.randint(margin, height - margin - 1)

            valid: bool = True
            for px, py in placed_centers:
                if abs(cx - px) < min_spacing and abs(cy - py) < min_spacing:
                    valid = False
                    break

            if valid and grid[cy][cx] == ".":
                cells: List[Tuple[int, int]] = generate_blob(
                    grid, width, height, cx, cy, resource, island_size, rng,
                )
                placed_centers.append((cx, cy))
                all_cell_lists.append(cells)

                success = True
                break

        if not success:
            print(f"Warning: could not place island {i} after 200 attempts", file=sys.stderr)
            all_cell_lists.append([])
            all_port_lists.append([])

    # Compute ocean tiles once after all islands are placed
    print("Computing ocean connectivity...")
    ocean_tiles: Set[Tuple[int, int]] = find_ocean_tiles(grid, width, height)
    print(f"  Found {len(ocean_tiles)} ocean-connected water tiles")

    # Now pick port positions using ocean connectivity
    for idx, cells in enumerate(all_cell_lists):
        if len(cells) == 0:
            all_port_lists.append([])
            continue
        ports: List[Tuple[int, int]] = pick_port_positions(
            cells, grid, width, height, rng, ocean_tiles,
        )
        all_port_lists.append(ports)

    return grid, all_cell_lists, all_port_lists


# ---------------------------------------------------------------------------
# CSV output
# ---------------------------------------------------------------------------

def write_map_csv(grid: List[List[str]], width: int, height: int, path: str) -> None:
    """Write the tile grid to a CSV file."""
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        for row in grid:
            writer.writerow(row)
    print(f"Wrote map: {path} ({width}x{height})")


def write_ports_csv(
    all_port_lists: List[List[Tuple[int, int]]],
    path: str,
) -> None:
    """Write port positions to a CSV: island_id,x,y."""
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["island_id", "x", "y"])
        for island_id, ports in enumerate(all_port_lists):
            for x, y in ports:
                writer.writerow([island_id, x, y])
    total: int = sum(len(p) for p in all_port_lists)
    print(f"Wrote ports: {path} ({total} port tiles)")


def write_islands_csv(
    all_cell_lists: List[List[Tuple[int, int]]],
    path: str,
) -> None:
    """Write island tile assignments: island_id,x,y,resource.

    This lets Odin skip flood fill entirely and use exact Python island data.
    """
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["island_id", "x", "y"])
        for island_id, cells in enumerate(all_cell_lists):
            for x, y in cells:
                writer.writerow([island_id, x, y])
    total: int = sum(len(c) for c in all_cell_lists)
    print(f"Wrote islands: {path} ({total} tiles across {len(all_cell_lists)} islands)")


def write_metadata_csv(
    grid: List[List[str]],
    width: int,
    height: int,
    seed: int,
    all_port_lists: List[List[Tuple[int, int]]],
    path: str,
) -> None:
    """Write island metadata CSV."""
    islands: List[Tuple[List[Tuple[int, int]], str]] = flood_fill_islands(grid, width, height)
    rng: random.Random = random.Random(seed + 1000)

    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "island_id", "name", "production", "production_name",
            "rate", "max_warehouse", "dock_level", "tile_count", "port_count",
        ])

        for idx, (cells, resource) in enumerate(islands):
            name: str = "Spawn" if idx == 0 else ISLAND_NAMES[idx % len(ISLAND_NAMES)]
            if idx >= len(ISLAND_NAMES):
                name += f" {idx // len(ISLAND_NAMES) + 1}"

            production: str = "P" if idx == 0 else resource
            port_count: int = len(all_port_lists[idx]) if idx < len(all_port_lists) else 0

            writer.writerow([
                idx,
                name,
                production,
                RESOURCES.get(production, "Unknown"),
                DEFAULT_RATES.get(production, 2.0),
                DEFAULT_MAX_WARE.get(production, 100),
                rng.choice(DEFAULT_DOCK_LEVELS),
                len(cells),
                port_count,
            ])

    print(f"Wrote metadata: {path} ({len(islands)} islands)")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser: argparse.ArgumentParser = argparse.ArgumentParser(
        description="Generate Ocean Circuit map CSV"
    )
    parser.add_argument("--width", type=int, default=4000, help="Grid width (default: 4000)")
    parser.add_argument("--height", type=int, default=3250, help="Grid height (default: 3250)")
    parser.add_argument("--islands", type=int, default=24, help="Number of islands (default: 24)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed (default: 42)")
    parser.add_argument("--output", type=str, default="map.csv", help="Output map CSV path")
    parser.add_argument("--meta", type=str, default="metadata.csv", help="Output metadata CSV path")
    parser.add_argument("--ports", type=str, default="ports.csv", help="Output ports CSV path")
    parser.add_argument("--islands-csv", type=str, default="islands.csv", help="Output island tiles CSV path")
    args: argparse.Namespace = parser.parse_args()

    grid, all_cell_lists, all_port_lists = generate_map(args.width, args.height, args.islands, args.seed)

    # Preview
    print(f"Generated {len(all_cell_lists)} islands:")
    for idx, cells in enumerate(all_cell_lists):
        if len(cells) == 0:
            continue
        xs: List[int] = [c[0] for c in cells]
        ys: List[int] = [c[1] for c in cells]
        resource: str = grid[cells[0][1]][cells[0][0]]
        port_count: int = len(all_port_lists[idx]) if idx < len(all_port_lists) else 0
        port_str: str = f" | {port_count} port tiles" if port_count > 0 else ""
        print(f"  {idx}: {RESOURCES.get(resource, '?'):>6} | {len(cells):>3} tiles | "
              f"pos=({min(xs)}-{max(xs)}, {min(ys)}-{max(ys)}){port_str}")

    write_map_csv(grid, args.width, args.height, args.output)
    write_ports_csv(all_port_lists, args.ports)
    write_islands_csv(all_cell_lists, args.islands_csv)
    write_metadata_csv(grid, args.width, args.height, args.seed, all_port_lists, args.meta)


if __name__ == "__main__":
    main()
