class_name ShipTypes
extends RefCounted

enum Type {
	EXPLORER_SHIP,
	SMALL_CARGO_SHIP,
	MEDIUM_CARGO_SHIP,
	LARGE_CARGO_SHIP,
	ASSIST_SMALL_WAR_SHIP,
	ASSIST_MEDIUM_WAR_SHIP,
	ASSIST_LARGE_WAR_SHIP,
	EXPLORER_MEDIUM_SHIP,
	FISHING_SHIP,
	OIL_SHIP_SMALL,
	OIL_SHIP_MEDIUM,
	OIL_SHIP_LARGE,
	SUPPLIES_SMALL_SHIP,
	SUPPLIES_MEDIUM_SHIP,
	SUPPLIES_LARGE_SHIP,
	PATROL_BOARD,
	FRIGATE,
	DESTROYER,
	CRUISER,
	BATTLESHIP,
	PIRATE_SHIP_SMALL,
	PIRATE_SHIP_MEDIUM,
	PIRATE_SHIP_LARGE,
}

enum State { IDLE, SAILING, DOCKED }

# Columns: health, value, speed, cargo_space, fuel_capacity, sensor_range
const STATS := {
	Type.EXPLORER_SHIP: [100, 0, 180, 50, 100, 1000],
	Type.SMALL_CARGO_SHIP: [140, 5_000, 120, 500, 900, 300],
	Type.MEDIUM_CARGO_SHIP: [180, 18_000, 100, 1500, 1500, 400],
	Type.LARGE_CARGO_SHIP: [240, 60_000, 70, 5000, 3000, 500],
	Type.ASSIST_SMALL_WAR_SHIP: [300, 10_000, 140, 150, 10, 700],
	Type.ASSIST_MEDIUM_WAR_SHIP: [600, 35_000, 120, 300, 200, 800],
	Type.ASSIST_LARGE_WAR_SHIP: [1000, 120_000, 100, 600, 300, 1000],
	Type.EXPLORER_MEDIUM_SHIP: [170, 15_000, 160, 300, 200, 1200],
	Type.FISHING_SHIP: [120, 0, 120, 800, 800, 250],
	Type.OIL_SHIP_SMALL: [180, 50_000, 100, 2000, 1500, 300],
	Type.OIL_SHIP_MEDIUM: [220, 150_000, 85, 6000, 3000, 350],
	Type.OIL_SHIP_LARGE: [280, 500_000, 70, 15000, 6000, 400],
	Type.SUPPLIES_SMALL_SHIP: [130, 8_000, 130, 700, 1000, 300],
	Type.SUPPLIES_MEDIUM_SHIP: [170, 30_000, 110, 2500, 2000, 350],
	Type.SUPPLIES_LARGE_SHIP: [220, 100_000, 90, 7000, 4000, 400],
	Type.PATROL_BOARD: [220, 7_500, 150, 100, 90, 600],
	Type.FRIGATE: [500, 80_000, 160, 250, 150, 900],
	Type.DESTROYER: [900, 220_000, 140, 400, 250, 1000],
	Type.CRUISER: [1500, 450_000, 120, 800, 400, 1200],
	Type.BATTLESHIP: [2500, 1_000_000, 60, 1000, 800, 1500],
	Type.PIRATE_SHIP_SMALL: [150, 0, 130, 300, 700, 400],
	Type.PIRATE_SHIP_MEDIUM: [350, 0, 110, 800, 1500, 500],
	Type.PIRATE_SHIP_LARGE: [700, 0, 90, 2000, 2500, 600],
}

const HEALTH := 0
const VALUE := 1
const SPEED := 2
const CARGO_SPACE := 3
const FUEL_CAPACITY := 4
const SENSOR_RANGE := 5

static func stat(type: int, which: int) -> float:
	return float(STATS[type][which])

static func health_of(type: int) -> float:
	return stat(type, HEALTH)

static func value_of(type: int) -> float:
	return stat(type, VALUE)

static func speed_of(type: int) -> float:
	return stat(type, SPEED)

static func fuel_capacity_of(type: int) -> float:
	return stat(type, FUEL_CAPACITY)

static func sensor_range_of(type: int) -> float:
	return stat(type, SENSOR_RANGE)

static func type_name(type: int) -> String:
	return Type.keys()[type]
