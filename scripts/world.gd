extends Node3D
# ============================================================================
#  World — ангар: пол, стены, крыша со щелями, станция SELL HAY, свет, пыль.
# ============================================================================

const SIZE := 50.0
const WALL_H := 15.0
var high_quality := true
var _sell_point := Vector3(15.0, 0.0, -7.5)

func sell_point() -> Vector3:
	return _sell_point

func _noise_tex(freq: float, seed_v: int, w := 256) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	n.seed = seed_v
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = w
	t.height = w
	t.seamless = true
	return t

func _slat(x: float, z: float, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = Vector3(x, size.y * 0.5, z)
	return mi

func build(quality: int = 1) -> void:
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	high_quality = quality > 1 and forward
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.55, 0.9)
	sky_mat.sky_horizon_color = Color(0.78, 0.82, 0.86)
	sky_mat.ground_bottom_color = Color(0.3, 0.28, 0.24)
	sky_mat.sun_angle_max = 12.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.ambient_light_color = Color(0.95, 0.88, 0.78)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 1.6
	env.ssao_enabled = high_quality   # только Forward+ (десктоп/скриншоты)
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.12
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.6, 0.5)
	env.fog_density = 0.002
	env.fog_sun_scatter = 0.35
	if high_quality:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.009
		env.volumetric_fog_gi_inject = 0.4
		env.volumetric_fog_length = 90.0
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, 22, 0)
	sun.light_color = Color(1.0, 0.9, 0.72)
	sun.light_energy = 1.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_bias = 0.03
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24, 150, 0)
	fill.light_color = Color(0.72, 0.7, 0.64)
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	add_child(fill)

	var concrete := StandardMaterial3D.new()
	concrete.albedo_texture = _noise_tex(0.06, 11)
	concrete.albedo_color = Color(0.5, 0.46, 0.4)
	concrete.metallic = 0.0
	concrete.roughness = 0.92
	var metal_wall := StandardMaterial3D.new()
	metal_wall.albedo_texture = _noise_tex(0.25, 21)
	metal_wall.albedo_color = Color(0.30, 0.33, 0.34)
	metal_wall.metallic = 0.55
	metal_wall.roughness = 0.55
	var metal_dark := StandardMaterial3D.new()
	metal_dark.albedo_color = Color(0.16, 0.17, 0.19)
	metal_dark.metallic = 0.7
	metal_dark.roughness = 0.45
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_texture = _noise_tex(0.5, 31)
	wood_mat.albedo_color = Color(0.5, 0.36, 0.22)
	wood_mat.roughness = 0.85

	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE, SIZE)
	floor_mi.mesh = pm
	floor_mi.material_override = concrete
	add_child(floor_mi)

	for i in 4:
		var wall := _slat(0, 0, Vector3(SIZE, WALL_H, 0.5), metal_wall)
		var a := deg_to_rad(90.0 * i)
		wall.position = Vector3(sin(a) * SIZE * 0.5, WALL_H * 0.5, cos(a) * SIZE * 0.5)
		wall.rotation.y = a
		add_child(wall)

	for z in range(-6, 7):
		var plate := _slat(0, z * 4.2, Vector3(SIZE, 0.22, 2.4), metal_dark)
		plate.position.y = WALL_H
		add_child(plate)
	for z in range(-7, 8):
		var beam := _slat(0, z * 4.0, Vector3(SIZE, 0.5, 0.35), metal_dark)
		beam.position.y = WALL_H - 0.5
		add_child(beam)
	for x in range(-3, 4):
		var beam2 := _slat(x * 9.0, 0, Vector3(0.35, 0.5, SIZE), metal_dark)
		beam2.position.y = WALL_H - 0.55
		add_child(beam2)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			for k in 2:
				var pillar := _slat(sx * (9.0 + k * 11.0), sz * (9.0 + k * 11.0), Vector3(0.6, WALL_H, 0.6), metal_wall)
				add_child(pillar)

	# ---------------------------------------------------------------- станция
	var station := Node3D.new()
	station.position = _sell_point
	add_child(station)
	var base := _slat(0, 0, Vector3(6.0, 3.4, 3.4), wood_mat)
	base.position = Vector3(0, 1.7, 0)
	station.add_child(base)
	var counter := MeshInstance3D.new()
	var cbm := BoxMesh.new()
	cbm.size = Vector3(6.4, 0.18, 1.4)
	counter.mesh = cbm
	var counter_mat := StandardMaterial3D.new()
	counter_mat.albedo_texture = _noise_tex(0.6, 41)
	counter_mat.albedo_color = Color(0.35, 0.24, 0.14)
	counter_mat.roughness = 0.6
	counter.material_override = counter_mat
	counter.position = Vector3(0, 1.15, -1.9)
	station.add_child(counter)
	station.add_child(_slat(-2.6, -1.9, Vector3(0.2, 1.1, 0.2), wood_mat))
	station.add_child(_slat(2.6, -1.9, Vector3(0.2, 1.1, 0.2), wood_mat))

	var font := load("res://assets/fonts/DejaVuSans-Bold.ttf")
	var sign := Label3D.new()
	if font: sign.font = font
	sign.text = "SELL HAY"
	sign.font_size = 220
	sign.pixel_size = 0.006
	sign.modulate = Color(0.95, 0.92, 0.85)
	sign.outline_size = 24
	sign.outline_modulate = Color(0.1, 0.08, 0.05)
	sign.position = Vector3(0, 3.9, -1.6)
	station.add_child(sign)
	var sign2 := Label3D.new()
	if font: sign2.font = font
	sign2.text = "SO,022 PER STRAW"
	sign2.font_size = 120
	sign2.pixel_size = 0.005
	sign2.modulate = Color(0.9, 0.88, 0.8)
	sign2.rotation_degrees = Vector3(-18, 0, 0)
	sign2.position = Vector3(3.6, 0.85, -2.6)
	station.add_child(sign2)

	var belt := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(1.1, 0.12, 8.0)
	belt.mesh = bmesh
	belt.material_override = metal_dark
	belt.position = Vector3(-0.4, 0.85, -5.6)
	belt.rotation_degrees = Vector3(-9, 0, 0)
	station.add_child(belt)
	for k in 5:
		station.add_child(_slat(-0.4, -3.0 - k * 1.6, Vector3(0.12, 0.85, 0.12), metal_dark))

	var title := Label3D.new()
	if font: title.font = font
	title.text = "FIND THE NEEDLE"
	title.font_size = 260
	title.pixel_size = 0.008
	title.modulate = Color(0.85, 0.8, 0.6)
	title.position = Vector3(0, 8.0, -SIZE * 0.5 + 0.6)
	add_child(title)
	var sub := Label3D.new()
	if font: sub.font = font
	sub.text = "6 000 000 соломинок · 5 иголок"
	sub.font_size = 120
	sub.pixel_size = 0.006
	sub.modulate = Color(0.7, 0.68, 0.6)
	sub.position = Vector3(0, 6.6, -SIZE * 0.5 + 0.6)
	add_child(sub)

	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	for i in 14:
		var pallet := _slat(rng.randf_range(-28, 28), rng.randf_range(-28, 28), Vector3(1.4, 0.16, 1.1), wood_mat)
		pallet.position.y = 0.08
		add_child(pallet)
	for i in 8:
		var barrel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.height = 0.95
		cyl.top_radius = 0.34
		cyl.bottom_radius = 0.34
		barrel.mesh = cyl
		barrel.material_override = metal_wall
		barrel.position = Vector3(rng.randf_range(-20, 20), 0.48, rng.randf_range(-20, 20))
		add_child(barrel)

	var hay_mat := StandardMaterial3D.new()
	hay_mat.albedo_texture = _noise_tex(1.4, 61)
	hay_mat.albedo_color = Color(0.75, 0.6, 0.28)
	hay_mat.roughness = 0.95
	for k in 4:
		var bale := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 1.0, 1.2)
		bale.mesh = bm
		bale.material_override = hay_mat
		bale.position = Vector3(-18 + k * 12.0, 0.5, 19.0)
		bale.rotation.y = rng.randf_range(0, TAU)
		add_child(bale)

	var dust := CPUParticles3D.new()
	dust.amount = 220
	dust.lifetime = 14.0
	dust.preprocess = 8.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(SIZE * 0.45, 6.0, SIZE * 0.45)
	dust.position = Vector3(0, 5.0, 0)
	dust.direction = Vector3(0.2, 0.1, 0.1)
	dust.spread = 30.0
	dust.initial_velocity_min = 0.05
	dust.initial_velocity_max = 0.35
	dust.gravity = Vector3(0, -0.02, 0)
	dust.scale_amount_min = 0.01
	dust.scale_amount_max = 0.05
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	dust.mesh = quad
	var dust_mat := StandardMaterial3D.new()
	dust_mat.albedo_color = Color(1.0, 0.95, 0.8, 0.35)
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust.material_override = dust_mat
	add_child(dust)
