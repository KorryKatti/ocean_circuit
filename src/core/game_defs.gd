class_name GameDefs
extends RefCounted

const MAX_ISLANDS := 48
const MAX_TILES := 16000
const TILE_SIZE := 32
const MAP_WIDTH := 4000
const MAP_HEIGHT := 3250
const MAX_PORTS := 4096
const MAX_LOG := 32

const WATER_CHAR := 46
const TILE_VARIATION := 0.032
const COAST_BLEND := 0.5

enum ResourceType { WOOD, FISH, ORE, METAL, OIL, LUXURY, PORT }

const RESOURCE_NAMES := ["Wood", "Fish", "Ore", "Metal", "Oil", "Luxury", "Port"]

const RESOURCE_COLORS := [
	Color8(58, 110, 62),
	Color8(104, 142, 118),
	Color8(122, 110, 98),
	Color8(120, 132, 148),
	Color8(48, 44, 42),
	Color8(206, 168, 74),
	Color8(72, 150, 150),
]

const SAND := Color8(196, 178, 132)
const FOG := Color8(38, 44, 56)
const PORT_COLOR := Color8(64, 196, 176)
const SELECT_TINT := Color8(255, 255, 100, 60)

const WHITE := Color8(255, 255, 255)
const SHADOW := Color8(0, 0, 0, 200)
const PLAYER_COLOR := Color8(220, 30, 30)

const TEXT := Color8(217, 217, 217)
const TEXT_DIM := Color8(140, 140, 140)
const TEXT_HEADER := Color8(217, 230, 255)
const TEXT_GOOD := Color8(51, 255, 51)
const TEXT_TEAL := Color8(0, 230, 204)
const TEXT_GOLD := Color8(255, 217, 51)
const TEXT_PINK := Color8(255, 102, 153)

static func resource_from_char(c: int) -> ResourceType:
	match char(c):
		"W": return ResourceType.WOOD
		"F": return ResourceType.FISH
		"O": return ResourceType.ORE
		"M": return ResourceType.METAL
		"L": return ResourceType.LUXURY
		"P": return ResourceType.PORT
		_: return ResourceType.ORE

static func vary_color(c: Color, gx: int, gy: int) -> Color:
	var h := (gx * 73856093) ^ (gy * 19349663)
	var amount := TILE_VARIATION * (float(h % 1000) / 500.0 - 1.0)
	return Color(
		clampf(c.r + amount, 0.0, 1.0),
		clampf(c.g + amount, 0.0, 1.0),
		clampf(c.b + amount, 0.0, 1.0),
		c.a
	)
