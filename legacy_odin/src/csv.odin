package main

// csv — CSV file reading utilities for Ocean Circuit.
// Handles low-level file I/O, byte-level parsing, and loading of all
// game data CSVs (tile grid, island metadata, port positions, island tiles).
// All functions share the same package namespace as main.odin.

import "core:math"
import "core:os"

// ---------------------------------------------------------------------------
// Low-level file and parsing helpers
// ---------------------------------------------------------------------------

// read_file reads an entire file into a heap-allocated byte buffer.
// Returns nil on error or if the file cannot be opened.
read_file :: proc(path: string) -> (data: []byte) {
	handle, err := os.open(path)
	if err != nil {return nil}
	defer os.close(handle)

	buf := make([]byte, 64 * 1024 * 1024)
	total := 0
	for {
		n, read_err := os.read(handle, buf[total:])
		total += n
		if read_err != nil || n == 0 {break}
	}
	return buf[:total]
}

// parse_int parses a simple ASCII integer from a byte slice.
// Supports an optional leading '-' for negative values.
// Returns the parsed value and whether parsing succeeded.
parse_int :: proc(s: []byte) -> (v: int, ok: bool) {
	if len(s) == 0 {return 0, false}

	i := 0
	negative := false
	if s[0] == '-' {
		negative = true
		i = 1
	}

	result := 0
	found_digit := false
	for j := i; j < len(s); j += 1 {
		c := s[j]
		if c < '0' || c > '9' {break}
		result = result * 10 + int(c - '0')
		found_digit = true
	}

	if !found_digit {return 0, false}
	if negative {result = -result}
	return result, true
}

// parse_f32 parses a simple ASCII float (e.g. "2.5", "120") from a byte slice.
// Supports an optional leading '-' for negative values.
// Returns the parsed value and whether parsing succeeded.
parse_f32 :: proc(s: []byte) -> (v: f32, ok: bool) {
	if len(s) == 0 {return 0, false}

	str := string(s)
	negative := false
	i := 0
	if str[0] == '-' {
		negative = true
		i = 1
	}

	whole := 0
	decimal := 0
	divisor := f32(1)
	found_digit := false

	for j := i; j < len(str); j += 1 {
		c := str[j]
		if c == '.' {
			for k := j + 1; k < len(str); k += 1 {
				dc := str[k] // decimal character (digit after the '.' decimal point)
				if dc < '0' || dc > '9' {break}
				decimal = decimal * 10 + int(dc - '0')
				divisor *= 10
				found_digit = true
			}
			break
		} else if c >= '0' && c <= '9' {
			whole = whole * 10 + int(c - '0')
			found_digit = true
		} else {
			break
		}
	}

	if !found_digit {return 0, false}

	result := f32(whole) + f32(decimal) / divisor
	if negative {result = -result}
	return result, true
}

// ---------------------------------------------------------------------------
// CSV field splitting
// ---------------------------------------------------------------------------

// CsvField stores the start/end byte indices of a single CSV field
// within a line buffer. The field content is line[start..end).
CsvField :: struct {
	start: int,
	end:   int,
}

// split_csv_fields splits a line by commas and writes field boundaries
// into the provided slice. Returns the number of fields found.
// The last field extends to the end of the line (handles trailing fields).
split_csv_fields :: proc(line: []byte, fields: []CsvField) -> int {
	count := 0
	f_start := 0
	for i in 0 ..< len(line) {
		if line[i] == ',' {
			if count < len(fields) {
				fields[count] = {f_start, i}
				count += 1
			}
			f_start = i + 1
		}
	}
	if count < len(fields) {
		fields[count] = {f_start, len(line)}
		count += 1
	}
	return count
}

// ---------------------------------------------------------------------------
// Map grid CSV
// ---------------------------------------------------------------------------

// load_map_csv reads the tile grid CSV and populates the MapGrid.
// The CSV is a simple grid of single-character resource codes separated
// by commas, one row per line. Water cells are '.'.
// Returns true on success.
load_map_csv :: proc(path: string, grid: ^MapGrid) -> bool {
	content := read_file(path)
	if len(content) == 0 {return false}
	defer delete(content)

	row := 0
	col := 0
	for b in content {
		if b == '\n' {
			for c := col; c < MAP_WIDTH; c += 1 {
				grid.cells[row][c] = '.'
			}
			row += 1
			col = 0
			if row >= MAP_HEIGHT {break}
		} else if b == '\r' {
			// skip carriage return
		} else if b == ',' {
			col += 1
		} else {
			if row < MAP_HEIGHT && col < MAP_WIDTH {
				grid.cells[row][col] = b
			}
		}
	}

	// Pad final row if file doesn't end with newline
	if col > 0 && row < MAP_HEIGHT {
		for c := col; c < MAP_WIDTH; c += 1 {
			grid.cells[row][c] = '.'
		}
		row += 1
	}

	grid.width = MAP_WIDTH
	grid.height = row
	return true
}

// ---------------------------------------------------------------------------
// Island metadata CSV
// ---------------------------------------------------------------------------

// IslandMeta stores one row from metadata.csv — static island configuration
// including name, production type, rate, warehouse capacity, and dock level.
IslandMeta :: struct {
	id:         int,
	name:       [32]u8,
	name_len:   int,
	production: ResourceType,
	rate:       f32,
	max_ware:   f32,
	dock_level: int,
	tile_count: int,
}

// load_metadata_csv reads island metadata (names, production rates, etc.)
// and writes results into the metas array. Expects a CSV with columns:
// island_id, name, production_char, production_name, rate, max_warehouse,
// dock_level, tile_count, port_count.
load_metadata_csv :: proc(path: string, metas: ^[MAX_ISLANDS]IslandMeta, out_count: ^int) {
	content := read_file(path)
	if len(content) == 0 {return}
	defer delete(content)

	row := 0
	line_start := 0
	is_header := true

	for i := 0; i <= len(content); i += 1 {
		is_end := i == len(content)
		is_newline := false
		if !is_end {
			is_newline = content[i] == '\n' || content[i] == '\r'
		}

		if is_end || is_newline {
			if i > line_start && !is_header && row < MAX_ISLANDS {
				line := content[line_start:i]

				// Skip empty lines
				all_whitespace := true
				for b in line {
					if b != ' ' && b != '\t' {
						all_whitespace = false
						break
					}
				}

				if !all_whitespace {
					fields: [16]CsvField
					field_count := split_csv_fields(line, fields[:])

					if field_count >= 8 {
						meta := &metas[row]

						// Column 0: island_id
						if v, ok := parse_int(line[fields[0].start:fields[0].end]); ok {
							meta.id = v
						}

						// Column 1: name (trim surrounding quotes)
						ns := fields[1].start // name start index
						ne := fields[1].end // name end index
						if ne > ns && line[ns] == '"' {
							ns += 1
							if ne > ns && line[ne - 1] == '"' {
								ne -= 1
							}
						}
						n := min(ne - ns, 31)
						for j in 0 ..< n {
							meta.name[j] = line[ns + j]
						}
						meta.name_len = n

						// Column 2: production character
						if fields[2].end > fields[2].start {
							meta.production = resource_from_char(line[fields[2].start])
						}

						// Column 3: rate
						if v, ok := parse_f32(line[fields[3].start:fields[3].end]); ok {
							meta.rate = v
						}

						// Column 5: max_warehouse
						if v, ok := parse_f32(line[fields[5].start:fields[5].end]); ok {
							meta.max_ware = v
						}

						// Column 6: dock_level
						if v, ok := parse_int(line[fields[6].start:fields[6].end]); ok {
							meta.dock_level = v
						}

						// Column 7: tile_count
						if v, ok := parse_int(line[fields[7].start:fields[7].end]); ok {
							meta.tile_count = v
						}

						row += 1
					}
				}
			}

			if is_header {is_header = false}

			// Handle \r\n line endings
			if !is_end && content[i] == '\r' && i + 1 < len(content) && content[i + 1] == '\n' {
				line_start = i + 2
			} else {
				line_start = i + 1
			}
		}
	}

	out_count^ = row
}

// ---------------------------------------------------------------------------
// Port positions CSV
// ---------------------------------------------------------------------------

// load_ports_csv reads port positions (island_id, x, y) and marks
// matching tiles as is_port on the corresponding island. The CSV
// header row is skipped.
load_ports_csv :: proc(path: string, islands: ^[MAX_ISLANDS]Island, island_count: int) {
	content := read_file(path)
	if len(content) == 0 {return}
	defer delete(content)

	row := 0
	line_start := 0
	is_header := true

	for i := 0; i <= len(content); i += 1 {
		is_end := i == len(content)
		is_newline := false
		if !is_end {
			is_newline = content[i] == '\n' || content[i] == '\r'
		}

		if is_end || is_newline {
			if i > line_start && !is_header {
				line := content[line_start:i]

				all_whitespace := true
				for b in line {
					if b != ' ' && b != '\t' {
						all_whitespace = false
						break
					}
				}

				if !all_whitespace {
					fields: [16]CsvField
					field_count := split_csv_fields(line, fields[:])

					if field_count >= 3 {
						island_id := 0
						px := 0 // port tile x grid position
						py := 0 // port tile y grid position

						if v, ok := parse_int(line[fields[0].start:fields[0].end]); ok {
							island_id = v
						}
						if v, ok := parse_int(line[fields[1].start:fields[1].end]); ok {
							px = v
						}
						if v, ok := parse_int(line[fields[2].start:fields[2].end]); ok {
							py = v
						}

						// Mark the tile as port if island is in range
						if island_id >= 0 && island_id < island_count {
							island := &islands[island_id]
							for t in 0 ..< island.tile_count {
								if island.tiles[t].gx == i32(px) && island.tiles[t].gy == i32(py) {
									island.tiles[t].is_port = true
									island.port_count += 1
									break
								}
							}
						}
					}
				}
			}

			if is_header {is_header = false}

			if !is_end && content[i] == '\r' && i + 1 < len(content) && content[i + 1] == '\n' {
				line_start = i + 2
			} else {
				line_start = i + 1
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Island tiles CSV
// ---------------------------------------------------------------------------

// load_islands_csv reads island tile assignments (island_id, x, y)
// and populates the Island structs directly — no flood fill needed.
// The CSV header row is skipped. After loading all tiles, computes
// the bounding-box center and radius for each island.
// Returns the number of islands loaded.
load_islands_csv :: proc(path: string, grid: ^MapGrid, islands: ^[MAX_ISLANDS]Island) -> int {
	content := read_file(path)
	if len(content) == 0 {return 0}
	defer delete(content)

	island_count := 0
	row := 0
	line_start := 0
	is_header := true

	for i := 0; i <= len(content); i += 1 {
		is_end := i == len(content)
		is_newline := false
		if !is_end {
			is_newline = content[i] == '\n' || content[i] == '\r'
		}

		if is_end || is_newline {
			if i > line_start && !is_header {
				line := content[line_start:i]

				all_whitespace := true
				for b in line {
					if b != ' ' && b != '\t' {
						all_whitespace = false
						break
					}
				}

				if !all_whitespace {
					fields: [16]CsvField
					field_count := split_csv_fields(line, fields[:])

					if field_count >= 3 {
						island_id := 0
						px := 0 // tile x grid position
						py := 0 // tile y grid position

						if v, ok := parse_int(line[fields[0].start:fields[0].end]); ok {
							island_id = v
						}
						if v, ok := parse_int(line[fields[1].start:fields[1].end]); ok {
							px = v
						}
						if v, ok := parse_int(line[fields[2].start:fields[2].end]); ok {
							py = v
						}

						if island_id >= 0 && island_id < MAX_ISLANDS {
							island := &islands[island_id]

							// Initialize island on first tile
							if island.tile_count == 0 {
								island.id = island_id
								island.production = resource_from_char(grid.cells[py][px])
								island.warehouse = 0
								island.port_count = 0
								if island_id > island_count {
									island_count = island_id
								}
							}

							if island.tile_count < MAX_TILES {
								island.tiles[island.tile_count] = {i32(px), i32(py), false}
								island.tile_count += 1
							}
						}
					}
				}
			}

			if is_header {is_header = false}

			if !is_end && content[i] == '\r' && i + 1 < len(content) && content[i + 1] == '\n' {
				line_start = i + 2
			} else {
				line_start = i + 1
			}
		}
	}

	// Compute center, radius, and count for each island
	for i in 0 ..< island_count + 1 {
		island := &islands[i]
		if island.tile_count == 0 {continue}

		min_x := island.tiles[0].gx
		max_x := island.tiles[0].gx
		min_y := island.tiles[0].gy
		max_y := island.tiles[0].gy

		for t in 1 ..< island.tile_count {
			tx := island.tiles[t].gx // current tile x
			ty := island.tiles[t].gy // current tile y
			if tx < min_x {min_x = tx}
			if tx > max_x {max_x = tx}
			if ty < min_y {min_y = ty}
			if ty > max_y {max_y = ty}
		}

		center_x := f32(min_x + max_x) / 2.0 * f32(TILE_SIZE)
		center_y := f32(min_y + max_y) / 2.0 * f32(TILE_SIZE)
		island.pos = {center_x, center_y}

		half_w := f32(max_x - min_x) / 2.0 * f32(TILE_SIZE)
		half_h := f32(max_y - min_y) / 2.0 * f32(TILE_SIZE)
		island.radius = math.max(half_w, half_h)
	}

	return island_count + 1
}
