class_name IslandRenderer
extends Node2D

const TILE_EDGE_ALPHA := 26
const LABEL_FONT_SIZE := 30
const RESOURCE_FONT_SIZE := 20

var world: WorldData
var selected: int = -1
var _multimesh: MultiMesh
var _name_labels: Array[Label] = []
var _resource_labels: Array[Label] = []
var _tile_count: int = 0

func setup(p_world: WorldData) -> void:
	world = p_world
	_build()
	refresh_colors()

func _tile_texture() -> ImageTexture:
	var ts := GameDefs.TILE_SIZE
	var img := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	img.fill(GameDefs.WHITE)
	var edge := Color8(0, 0, 0, TILE_EDGE_ALPHA)
	for i in range(1):
		for x in range(ts):
			img.set_pixel(x, i, edge)
			img.set_pixel(x, ts - 1 - i, edge)
			img.set_pixel(i, x, edge)
			img.set_pixel(ts - 1 - i, x, edge)
	return ImageTexture.create_from_image(img)

func _build() -> void:
	_tile_count = 0
	for isl in world.islands:
		_tile_count += isl.tile_count

	var quad := QuadMesh.new()
	quad.size = Vector2(GameDefs.TILE_SIZE, GameDefs.TILE_SIZE)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _tile_texture()
	mat.vertex_color_use_as_albedo = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	quad.material = mat

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.use_colors = true
	_multimesh.mesh = quad
	_multimesh.instance_count = _tile_count

	var half := GameDefs.TILE_SIZE / 2.0
	var idx := 0
	for isl in world.islands:
		for t in range(isl.tile_count):
			var xform := Transform2D(0.0, Vector2(
				float(isl.tile_gx(t)) * GameDefs.TILE_SIZE + half,
				float(isl.tile_gy(t)) * GameDefs.TILE_SIZE + half
			))
			_multimesh.set_instance_transform_2d(idx, xform)
			_multimesh.set_instance_color(idx, GameDefs.FOG)
			idx += 1

	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = _multimesh
	add_child(mmi)

	_build_labels()

func _build_labels() -> void:
	for l in _name_labels:
		l.queue_free()
	for l in _resource_labels:
		l.queue_free()
	_name_labels = []
	_resource_labels = []

	for i in range(world.island_count):
		var isl := world.islands[i]
		if isl.tile_count == 0:
			continue

		var res_label := _make_label(String(GameDefs.RESOURCE_NAMES[isl.production]), RESOURCE_FONT_SIZE)
		res_label.position = isl.pos + Vector2(-200, -40)
		add_child(res_label)
		_resource_labels.append(res_label)

		var name_label := _make_label(isl.name, LABEL_FONT_SIZE)
		name_label.position = isl.pos + Vector2(-200, isl.radius + 14)
		add_child(name_label)
		_name_labels.append(name_label)

func _make_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", GameDefs.WHITE)
	l.add_theme_color_override("font_shadow_color", GameDefs.SHADOW)
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(400, 0)
	l.z_index = 1
	return l

func refresh_colors() -> void:
	if _multimesh == null:
		return
	var idx := 0
	for i in range(world.island_count):
		var isl := world.islands[i]
		var discovered: bool = world.discovered_islands[i]
		var base: Color = GameDefs.FOG
		if discovered:
			base = GameDefs.RESOURCE_COLORS[isl.production]

		for t in range(isl.tile_count):
			var gx := isl.tile_gx(t)
			var gy := isl.tile_gy(t)
			var c := base

			if discovered:
				if isl.tile_is_port(t):
					c = GameDefs.PORT_COLOR
				elif world.is_coast(gx, gy):
					c = base.lerp(GameDefs.SAND, GameDefs.COAST_BLEND)
				c = GameDefs.vary_color(c, gx, gy)
			else:
				c = GameDefs.vary_color(c, gx, gy)

			if selected == i:
				c = c.lerp(GameDefs.SELECT_TINT, GameDefs.SELECT_TINT.a)

			_multimesh.set_instance_color(idx, c)
			idx += 1

	for i in range(_name_labels.size()):
		var fogged: bool = not world.discovered_islands[i]
		_name_labels[i].modulate = GameDefs.FOG if fogged else GameDefs.WHITE
		_resource_labels[i].modulate = GameDefs.FOG if fogged else GameDefs.WHITE

func set_selected(idx: int) -> void:
	if selected == idx:
		return
	selected = idx
	refresh_colors()

func island_at(world_pos: Vector2) -> int:
	var ts := float(GameDefs.TILE_SIZE)
	var gx := int(world_pos.x / ts)
	var gy := int(world_pos.y / ts)
	for i in range(world.island_count):
		var isl := world.islands[i]
		if isl.tile_count == 0:
			continue
		if isl.pos.distance_to(world_pos) > isl.radius + ts:
			continue
		for t in range(isl.tile_count):
			if isl.tile_gx(t) == gx and isl.tile_gy(t) == gy:
				return i
	return -1
