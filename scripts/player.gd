extends CharacterBody3D
# ============================================================================
#  Player — вид от первого лица: ходьба, бег, силы, копание, детектор,
#  взаимодействие (продать сено / взять иголку), анимация инструмента.
# ============================================================================

signal prompt_changed(text: String)
signal swing(strength: float)

const HEAD := 1.62
const DIG_REACH := 2.7
const DIG_CD := 0.42

var haystack: Node3D
var world: Node3D
var camera: Camera3D
var viewmodel: Node3D
var _tool_nodes := {}

var move_input := Vector2.ZERO
var look_delta := Vector2.ZERO
var want_dig := false
var want_jump := false
var want_interact := false
var _mobile_sprint := false

var yaw := 0.0
var pitch := -0.15
var _dig_timer := 0.0
var _swing := 0.0
var _step_timer := 0.0
var _beep_timer := 0.0
var detector_signal := 0.0
var detector_dist := 999.0
var prompt := ""

func setup(hs: Node3D, w: Node3D) -> void:
	haystack = hs
	world = w

func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.72
	shape.shape = cap
	shape.position = Vector3(0, 0.86, 0)
	add_child(shape)
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.5

	camera = Camera3D.new()
	camera.position = Vector3(0, HEAD, 0)
	camera.fov = 78.0
	camera.near = 0.05
	add_child(camera)
	_build_viewmodel()

func _build_viewmodel() -> void:
	viewmodel = Node3D.new()
	viewmodel.position = Vector3(0.34, -0.32, -0.55)
	camera.add_child(viewmodel)

	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.86, 0.68, 0.55)
	skin.roughness = 0.8
	var hands := Node3D.new()
	for sx in [-1, 1]:
		var hand := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.09, 0.3)
		hand.mesh = bm
		hand.material_override = skin
		hand.position = Vector3(0.03 * sx, -0.02 * sx, -0.05)
		hand.rotation = Vector3(-0.5, 0.15 * sx, 0.1 * sx)
		hands.add_child(hand)
	viewmodel.add_child(hands)
	_tool_nodes["hands"] = hands

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.38, 0.2)
	wood.roughness = 0.85
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.62, 0.63, 0.66)
	metal.metallic = 0.9
	metal.roughness = 0.35

	var shovel := Node3D.new()
	var handle := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.height = 1.0
	cyl.top_radius = 0.022
	cyl.bottom_radius = 0.022
	handle.mesh = cyl
	handle.material_override = wood
	handle.rotation = Vector3(-1.15, 0.0, 0.25)
	handle.position = Vector3(0, -0.05, 0.1)
	shovel.add_child(handle)
	var blade := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.26, 0.03, 0.34)
	blade.mesh = bmesh
	blade.material_override = metal
	blade.position = Vector3(0.0, -0.34, -0.42)
	blade.rotation = Vector3(-0.35, 0.0, 0.0)
	shovel.add_child(blade)
	viewmodel.add_child(shovel)
	_tool_nodes["shovel"] = shovel

	var fork := Node3D.new()
	var fh := MeshInstance3D.new()
	var fcyl := CylinderMesh.new()
	fcyl.height = 0.95
	fcyl.top_radius = 0.02
	fcyl.bottom_radius = 0.02
	fh.mesh = fcyl
	fh.material_override = wood
	fh.rotation = Vector3(-1.1, 0, 0.22)
	fork.add_child(fh)
	for i in 3:
		var prong := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.02, 0.02, 0.36)
		prong.mesh = pm
		prong.material_override = metal
		prong.position = Vector3(-0.08 + 0.08 * i, -0.3, -0.36)
		fork.add_child(prong)
	viewmodel.add_child(fork)
	_tool_nodes["pitchfork"] = fork

	var vac := Node3D.new()
	var pipe := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.height = 0.9
	pcyl.top_radius = 0.05
	pcyl.bottom_radius = 0.07
	pipe.mesh = pcyl
	pipe.material_override = metal
	pipe.rotation = Vector3(-1.2, 0, 0.3)
	vac.add_child(pipe)
	viewmodel.add_child(vac)
	_tool_nodes["vacuum"] = vac

	var det := Node3D.new()
	var rod := MeshInstance3D.new()
	var rcyl := CylinderMesh.new()
	rcyl.height = 0.8
	rcyl.top_radius = 0.02
	rcyl.bottom_radius = 0.02
	rod.mesh = rcyl
	rod.material_override = metal
	rod.rotation = Vector3(-1.3, 0, 0.15)
	det.add_child(rod)
	var coil := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.07
	torus.outer_radius = 0.12
	coil.mesh = torus
	var coil_mat := StandardMaterial3D.new()
	coil_mat.albedo_color = Color(0.15, 0.16, 0.2)
	coil_mat.roughness = 0.5
	coil.material_override = coil_mat
	coil.position = Vector3(0.0, -0.5, -0.62)
	coil.rotation = Vector3(1.2, 0, 0)
	det.add_child(coil)
	viewmodel.add_child(det)
	_tool_nodes["detector"] = det
	_show_tool()

func _show_tool() -> void:
	var t: String = GameState.tool
	for key in _tool_nodes:
		_tool_nodes[key].visible = (key == t)
	_tool_nodes["detector"].visible = GameState.detector_on and t != "shovel"

func set_look(y: float, p: float) -> void:
	yaw = y
	pitch = clampf(p, -1.4, 1.4)
	rotation.y = yaw
	camera.rotation.x = pitch

func teleport(pos: Vector3, yaw_deg: float, pitch_deg: float) -> void:
	global_position = pos
	set_look(deg_to_rad(yaw_deg), deg_to_rad(pitch_deg))

# ------------------------------------------------------------------ физика
func _physics_process(delta: float) -> void:
	var sens := 0.0026
	if look_delta != Vector2.ZERO:
		set_look(yaw - look_delta.x * sens, pitch - look_delta.y * sens)
		look_delta = Vector2.ZERO

	var dir := Vector3(move_input.x, 0, move_input.y)
	var sprinting := Input.is_action_pressed("sprint") or (move_input.length() > 0.85 and _mobile_sprint)
	if dir.length() > 1.0:
		dir = dir.normalized()
	dir = dir.rotated(Vector3.UP, yaw)
	var speed: float = GameState.walk_speed() * (1.7 if sprinting else 1.0)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	if not is_on_floor():
		velocity.y -= 14.0 * delta
	else:
		velocity.y = -0.1
		if want_jump:
			velocity.y = 5.2
			want_jump = false

	move_and_slide()

	var regen := 9.0
	if sprinting and velocity.length() > 1.0:
		GameState.stamina = maxf(0.0, GameState.stamina - 6.0 * delta)
		regen = 0.0
	GameState.stamina = minf(GameState.stamina_max(), GameState.stamina + regen * delta)

	if is_on_floor() and velocity.length() > 1.2:
		_step_timer -= delta * velocity.length()
		if _step_timer <= 0.0:
			_step_timer = 3.4
			Sfx.play("rustle", -24.0, randf_range(0.85, 1.15))

	_dig_timer -= delta
	if want_dig and _dig_timer <= 0.0:
		_do_dig()
	want_dig = false

	if want_interact:
		_do_interact()
		want_interact = false

	_swing = maxf(0.0, _swing - delta * 4.5)
	viewmodel.rotation.x = -0.9 * _swing
	viewmodel.position.y = -0.32 + 0.12 * _swing

	_detector(delta)
	_update_prompt()

func _dig_dir() -> Vector3:
	return -camera.global_transform.basis.z

func _do_dig() -> void:
	var origin := camera.global_position
	var to := origin + _dig_dir() * DIG_REACH
	var q := PhysicsRayQueryParameters3D.create(origin, to)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_dig_timer = 0.2
		return
	var collider = hit.get("collider")
	if collider == null or not (collider is StaticBody3D):
		_dig_timer = 0.25
		return
	if not str(collider.name).contains("Hay"):
		_dig_timer = 0.3
		return

	var cost: float = GameState.dig_stamina_cost()
	if GameState.stamina < cost:
		GameState.toast.emit("Сил не хватает — отдохни секунду")
		_dig_timer = 0.5
		return
	GameState.stamina -= cost

	var power: float = GameState.dig_power()
	var collect := GameState.tool != "pitchfork"
	if collect:
		var space: float = GameState.capacity() - GameState.carried
		power = minf(power, maxf(space, 0.0))
		if power <= 0.0:
			GameState.toast.emit("Руки полны — продай сено на станции SELL HAY")
			_dig_timer = 0.4
			return
	var removed: float = haystack.dig(hit["position"], power, collect)
	if removed <= 0.0:
		_dig_timer = 0.2
		return
	if collect:
		GameState.hold(removed)
	_dig_timer = DIG_CD
	_swing = 1.0
	swing.emit(hit["position"].y - global_position.y)
	Sfx.play3d("scoop" if GameState.tool != "vacuum" else "rustle2", hit["position"], -6.0, randf_range(0.9, 1.1))
	Sfx.play3d("rustle", hit["position"], -9.0, randf_range(0.95, 1.2))
	haystack.straw_particles.emit(hit["position"], int(clampf(removed, 3.0, 24.0)))
	GameState.straws_changed.emit(haystack.straws_left())

func _do_interact() -> void:
	var n: Dictionary = haystack.nearest_unfound_needle(global_position)
	if not n.is_empty() and n.revealed and n.dist < 2.4:
		if haystack.take_needle(n.idx):
			GameState.needles_found += 1
			GameState.needles_changed.emit(GameState.needles_found, GameState.needles_total)
			GameState.save()
			Sfx.play("found", -3.0, 1.0)
			GameState.toast.emit("Иголка найдена! (%d/%d)" % [GameState.needles_found, GameState.needles_total])
			if GameState.needles_found >= GameState.needles_total:
				GameState.pile_finished.emit()
		return
	if world and world.has_method("sell_point"):
		var p: Vector3 = world.sell_point()
		if global_position.distance_to(p) < 3.2:
			if GameState.carried > 0.0:
				var earned: float = GameState.sell_all()
				Sfx.play("sell", -3.0, 1.0)
				GameState.toast.emit("Продано! +%.2f $" % earned)
			else:
				GameState.toast.emit("Нечего продавать — накопай сена")

func _detector(delta: float) -> void:
	if not GameState.detector_on:
		detector_signal = 0.0
		return
	var n: Dictionary = haystack.nearest_unfound_needle(global_position)
	if n.is_empty():
		detector_signal = 0.0
		return
	detector_dist = n.dist
	var rng: float = GameState.detector_range()
	detector_signal = clampf(1.0 - detector_dist / rng, 0.0, 1.0)
	_beep_timer -= delta
	if _beep_timer <= 0.0:
		var interval: float = lerpf(1.15, 0.12, detector_signal * detector_signal)
		_beep_timer = interval
		if detector_signal > 0.03:
			Sfx.play("beep", -26.0 + 18.0 * detector_signal, 1.0 + 0.4 * detector_signal)

func _update_prompt() -> void:
	var text := ""
	var n: Dictionary = haystack.nearest_unfound_needle(global_position)
	if not n.is_empty() and n.revealed and n.dist < 2.4:
		text = "E — взять иголку"
	elif world and world.has_method("sell_point"):
		if global_position.distance_to(world.sell_point()) < 3.2:
			text = "E — продать сено (%d шт)" % int(GameState.carried)
	if text != prompt:
		prompt = text
		prompt_changed.emit(text)
