extends Node3D
# ============================================================================
#  Haystack — стог сена: миллионы логических соломинок, десятки тысяч
#  видимых, копание, ямки, столкновения, спрятанные иголки.
# ============================================================================

signal needle_revealed(index: int)
signal straw_particles(pos: Vector3, amount: int)

const GRID := 40
const CELL := 1.0
const BASE_H := 15.0
const BASE_R := 12.5
const LOGICAL_TARGET := 6_000_000.0

var max_per_col := 30        # видимых соломинок на колонку (качество)

var heights := PackedFloat32Array()
var h0 := PackedFloat32Array()
var density := 0.0
var _dug := 0.0
var _slot_hidden := PackedByteArray()
var _col_base := PackedInt32Array()   # смещение колонки в буфере инстансов
var _col_count := PackedInt32Array()  # сколько соломинок у колонки
var total_instances := 0
const PER_METER := 17.0               # видимых соломинок на метр высоты колонки

var needles: Array = []

var _mmi: MultiMeshInstance3D
var _mm: MultiMesh
var _core: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D
var _last_collision_rebuild := 0.0
var _rng := RandomNumberGenerator.new()

# ------------------------------------------------------------------ построение
func build(seed_value := 20261001, needle_count := 5) -> void:
	_rng.seed = seed_value
	heights.resize(GRID * GRID)
	h0.resize(GRID * GRID)
	_col_base.resize(GRID * GRID)
	_col_count.resize(GRID * GRID)
	var sum := 0.0
	for z in GRID:
		for x in GRID:
			var i := z * GRID + x
			var wx := (x - GRID * 0.5 + 0.5) * CELL
			var wz := (z - GRID * 0.5 + 0.5) * CELL
			var d := sqrt(wx * wx + wz * wz)
			var t: float = clampf(1.0 - d / BASE_R, 0.0, 1.0)
			var h := BASE_H * pow(t, 0.85)
			h *= 1.0 + 0.055 * sin(wx * 0.9) * cos(wz * 1.1) + 0.045 * sin(d * 2.3)
			if h < 0.12:
				h = 0.0
			heights[i] = h
			h0[i] = h
			sum += h
	density = LOGICAL_TARGET / maxf(sum, 1.0)
	_dug = 0.0
	total_instances = 0
	for i in GRID * GRID:
		_col_base[i] = total_instances
		_col_count[i] = int(clampf(round(h0[i] * PER_METER), 0.0, float(max_per_col)))
		total_instances += _col_count[i]
	_slot_hidden.resize(total_instances)
	_build_core()
	_build_instances()
	_build_collision()
	_place_needles(needle_count)

func _straw_texture(freq: float, seed_v: int, size := 512, as_norm := false, strength := 4.0) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	n.seed = seed_v
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = size
	t.height = size
	t.seamless = true
	if as_norm:
		t.as_normal_map = true
		t.bump_strength = strength
	return t

func _material_core() -> StandardMaterial3D:
	# ядро стога: у меша нет UV, поэтому включаем трипланар — текстура «ложится»
	# в мировых координатах и стог читается как сено уже с расстояния
	var m := StandardMaterial3D.new()
	var alb := _straw_texture(3.2, 7)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.72, 0.52, 0.20))
	ramp.set_color(1, Color(1.0, 0.88, 0.50))
	ramp.add_point(0.45, Color(0.88, 0.70, 0.32))
	ramp.add_point(0.8, Color(0.97, 0.82, 0.42))
	alb.color_ramp = ramp
	m.albedo_texture = alb
	m.albedo_color = Color(1, 1, 1)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.32, 0.32, 0.32)
	m.roughness = 0.88
	m.normal_enabled = true
	m.normal_texture = _straw_texture(9.0, 19, 512, true, 3.0)
	m.normal_scale = 0.9
	m.ao_enabled = true
	m.ao_texture = _straw_texture(14.0, 23, 256)
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.ao_light_affect = 0.12
	return m

func _straw_mesh() -> Mesh:
	# тонкая соломинка ~32 см: один квад (2 треугольника), лёгкий изгиб
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := 0.38
	var W := 0.012
	var bend := 0.035
	st.add_vertex(Vector3(-W, 0.0, 0))
	st.add_vertex(Vector3(W, 0.0, 0))
	st.add_vertex(Vector3(W, bend, -L))
	st.add_vertex(Vector3(-W, 0.0, 0))
	st.add_vertex(Vector3(W, bend, -L))
	st.add_vertex(Vector3(-W, bend, -L))
	st.generate_normals()
	return st.commit()

func _build_instances() -> void:
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Straws"
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = _straw_mesh()
	_mm.instance_count = total_instances
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.86, 0.45)
	mat.roughness = 0.85
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mmi.material_override = mat
	_mmi.multimesh = _mm
	add_child(_mmi)
	for z in GRID:
		for x in GRID:
			_update_column(z * GRID + x, true)

func _update_column(i: int, force := false) -> void:
	if _mm == null:
		return
	var x := i % GRID
	var z := i / GRID
	var cx := (x - GRID * 0.5 + 0.5) * CELL
	var cz := (z - GRID * 0.5 + 0.5) * CELL
	var hi: float = heights[i]
	var top: float = h0[i]
	var base := _col_base[i]
	var n := _col_count[i]
	for k in n:
		var idx := base + k
		# плотнее у поверхности стога (как настоящая кладка сена)
		var frac: float = pow((k + 0.5) / float(n), 0.72)
		var y := frac * top
		var hidden := y > hi + 0.06
		if not force and _slot_hidden[idx] == (1 if hidden else 0):
			continue
		_slot_hidden[idx] = 1 if hidden else 0
		if hidden:
			_mm.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0)))
			continue
		var jitter := Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.5, 0.5))
		var pos := Vector3(cx, y, cz) + jitter
		# солома лежит: тангаж/крен небольшие, поворот по кругу
		var yaw := _rng.randf_range(0.0, TAU)
		var b := Basis.from_euler(Vector3(_rng.randf_range(-0.32, 0.32), yaw, _rng.randf_range(-0.32, 0.32)))
		var s := _rng.randf_range(0.75, 1.35)
		b = b.scaled(Vector3(s, s, s))
		_mm.set_instance_transform(idx, Transform3D(b, pos))
		var t := _rng.randf()
		var c := Color(
			1.0,
			0.74 + 0.20 * t + _rng.randf_range(-0.05, 0.05),
			0.30 + 0.28 * t + _rng.randf_range(-0.06, 0.06))
		_mm.set_instance_color(idx, c)

func _surface_arrays(offset_y := 0.0) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vts := PackedVector3Array()
	vts.resize(GRID * GRID)
	for z in GRID:
		for x in GRID:
			var i := z * GRID + x
			vts[i] = Vector3((x - GRID * 0.5 + 0.5) * CELL, heights[i] + offset_y, (z - GRID * 0.5 + 0.5) * CELL)
	for z in GRID - 1:
		for x in GRID - 1:
			var i := z * GRID + x
			st.add_vertex(vts[i]); st.add_vertex(vts[i + GRID]); st.add_vertex(vts[i + 1])
			st.add_vertex(vts[i + 1]); st.add_vertex(vts[i + GRID]); st.add_vertex(vts[i + GRID + 1])
	st.generate_normals()
	return st

func _build_core() -> void:
	if _core == null:
		_core = MeshInstance3D.new()
		_core.name = "HayCore"
		_core.material_override = _material_core()
		add_child(_core)
	_core.mesh = _surface_arrays(-0.22).commit()

func _build_collision() -> void:
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = "HayBody"
		_shape = CollisionShape3D.new()
		_shape.shape = ConcavePolygonShape3D.new()
		_body.add_child(_shape)
		add_child(_body)
	var mesh := _surface_arrays(0.0).commit()
	(_shape.shape as ConcavePolygonShape3D).set_faces(mesh.get_faces())

# ------------------------------------------------------------------ копание
func straws_left() -> float:
	return maxf(0.0, LOGICAL_TARGET - _dug)

func dig(point: Vector3, power: float, collect := true) -> float:
	if power <= 0.0:
		return 0.0
	var cx := int(round(point.x / CELL + GRID * 0.5 - 0.5))
	var cz := int(round(point.z / CELL + GRID * 0.5 - 0.5))
	var R := 1.35
	var cand: Array = []
	var weight_sum := 0.0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var x := cx + dx
			var z := cz + dz
			if x < 0 or z < 0 or x >= GRID or z >= GRID:
				continue
			var i := z * GRID + x
			if heights[i] <= 0.02:
				continue
			var wx := (x - GRID * 0.5 + 0.5) * CELL
			var wz := (z - GRID * 0.5 + 0.5) * CELL
			var d := sqrt((wx - point.x) * (wx - point.x) + (wz - point.z) * (wz - point.z))
			if d > R:
				continue
			if absf(heights[i] - point.y) > 2.2:
				continue
			var w: float = pow(1.0 - d / R, 2.0) + 0.05
			cand.append({"i": i, "w": w})
			weight_sum += w
	if cand.is_empty():
		return 0.0
	var removed := 0.0
	for c in cand:
		var i: int = c["i"]
		var take: float = power * (float(c["w"]) / weight_sum)
		var avail: float = heights[i] * density
		take = minf(take, avail)
		if take <= 0.0:
			continue
		heights[i] = maxf(0.0, heights[i] - take / density)
		removed += take
		_update_column(i)
	_dug += removed
	_rebuild_soon()
	_check_needles(point)
	return removed

func _rebuild_soon() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_collision_rebuild < 0.25:
		return
	_last_collision_rebuild = now
	_build_core()
	_build_collision()

func force_rebuild() -> void:
	_build_core()
	_build_collision()
	for i in GRID * GRID:
		_update_column(i, true)

# ------------------------------------------------------------------ иголки
func _place_needles(count: int) -> void:
	for n in needles:
		if is_instance_valid(n.node):
			n.node.queue_free()
	needles.clear()
	for k in count:
		var tries := 0
		while tries < 200:
			tries += 1
			var x := _rng.randi_range(2, GRID - 3)
			var z := _rng.randi_range(2, GRID - 3)
			var i := z * GRID + x
			if h0[i] < 1.5:
				continue
			var frac := _rng.randf_range(0.12, 0.72)
			var y := h0[i] * frac
			var wx := (x - GRID * 0.5 + 0.5) * CELL + _rng.randf_range(-0.4, 0.4)
			var wz := (z - GRID * 0.5 + 0.5) * CELL + _rng.randf_range(-0.4, 0.4)
			var node := _needle_node()
			node.position = Vector3(wx, y, wz)
			node.rotation = Vector3(_rng.randf_range(-1.4, 1.4), _rng.randf_range(0, TAU), _rng.randf_range(-1.4, 1.4))
			node.visible = false
			add_child(node)
			needles.append({"pos": Vector3(wx, y, wz), "revealed": false, "node": node, "taken": false})
			break

func _needle_node() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.006
	cyl.bottom_radius = 0.006
	cyl.height = 0.34
	cyl.radial_segments = 6
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.87, 0.92)
	m.metallic = 1.0
	m.roughness = 0.12
	mi.material_override = m
	root.add_child(mi)
	var eye := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.008
	torus.outer_radius = 0.02
	eye.mesh = torus
	eye.position = Vector3(0, 0.18, 0)
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(0.85, 0.87, 0.92)
	em.metallic = 1.0
	em.roughness = 0.12
	eye.material_override = em
	root.add_child(eye)
	var light := OmniLight3D.new()
	light.light_color = Color(0.8, 0.95, 1.0)
	light.light_energy = 0.6
	light.omni_range = 1.2
	root.add_child(light)
	return root

func _check_needles(point: Vector3) -> void:
	for idx in needles.size():
		var n: Dictionary = needles[idx]
		if n.revealed or n.taken:
			continue
		var p: Vector3 = n.pos
		var gx := int(round(p.x / CELL + GRID * 0.5 - 0.5))
		var gz := int(round(p.z / CELL + GRID * 0.5 - 0.5))
		if gx < 0 or gz < 0 or gx >= GRID or gz >= GRID:
			continue
		var col := gz * GRID + gx
		var dxz := Vector2(p.x - point.x, p.z - point.z).length()
		if heights[col] < p.y + 0.12 and dxz < 1.6:
			n.revealed = true
			n.node.visible = true
			needle_revealed.emit(idx)
			Sfx.play3d("found", p, -4.0, 1.25)

func take_needle(idx: int) -> bool:
	var n: Dictionary = needles[idx]
	if n.taken or not n.revealed:
		return false
	n.taken = true
	if is_instance_valid(n.node):
		n.node.queue_free()
	return true

func nearest_unfound_needle(from: Vector3) -> Dictionary:
	var best := {}
	var best_d := 1e9
	for idx in needles.size():
		var n: Dictionary = needles[idx]
		if n.taken:
			continue
		var d := from.distance_to(n.pos)
		if d < best_d:
			best_d = d
			best = {"idx": idx, "dist": d, "pos": n.pos, "revealed": n.revealed}
	return best
