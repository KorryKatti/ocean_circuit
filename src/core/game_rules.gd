class_name GameRules
extends RefCounted

const START_MONEY := 1000.0
const WIN_MONEY := 20000.0

const DAYS_PER_SECOND := 0.5
const MIN_STOCK_TO_SAIL := 10.0
const SPAWN_STARTING_STOCK := 25.0

const PRICE := [12.0, 15.0, 20.0, 26.0, 40.0, 70.0, 0.0]

const TIME_SCALES := [0.0, 1.0, 2.0, 4.0]
const TIME_SCALE_NAMES := ["Paused", "1x", "2x", "4x"]

static func price_of(resource_type: int) -> float:
	return PRICE[resource_type]

static func ship_price(ship_type: int) -> float:
	return ShipTypes.value_of(ship_type)

static func time_scale_name(index: int) -> String:
	return TIME_SCALE_NAMES[index]
