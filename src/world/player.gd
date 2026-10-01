class_name Player
extends Node2D

const SIZE := 20.0
const SPEED := 200.0

var world: WorldData

func setup(p_world: WorldData) -> void:
	world = p_world

func tick(delta: float) -> void:
	if world == null:
		return
	var step := SPEED * delta
	var dx := 0.0
	var dy := 0.0

	if Input.is_action_pressed("move_up"):
		dy -= step
	if Input.is_action_pressed("move_down"):
		dy += step
	if Input.is_action_pressed("move_left"):
		dx -= step
	if Input.is_action_pressed("move_right"):
		dx += step

	if dx != 0.0 and not world.grid.is_water_world(position.x + dx, position.y):
		position.x += dx
	if dy != 0.0 and not world.grid.is_water_world(position.x, position.y + dy):
		position.y += dy

func _draw() -> void:
	var h := SIZE / 2.0
	draw_rect(Rect2(-h, -h, SIZE, SIZE), GameDefs.PLAYER_COLOR)
