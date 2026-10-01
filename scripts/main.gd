extends Node3D
# ============================================================================
#  Main — сборка сцены: мир, стог, игрок, HUD; сохранения; режим скриншота.
# ============================================================================

var world: Node3D
var hay: Node3D
var player: Node3D
var hud: CanvasLayer
var _particles: CPUParticles3D
var _autosave := 0.0
var _shot_mode := false

const WorldScript = preload("res://scripts/world.gd")
const HayScript = preload("res://scripts/haystack.gd")
const PlayerScript = preload("res://scripts/player.gd")
const HudScript = preload("res://scripts/hud.gd")

func _ready() -> void:
	_setup_input()
	var env_shot: String = OS.get_environment("SHOT_PATH")
	_shot_mode = env_shot != ""
	var quality := 1
	if OS.get_environment("SHOT_QUALITY") == "high" or (not OS.has_feature("mobile") and not _shot_mode):
		quality = 2
	if OS.get_environment("SHOT_QUALITY") == "low":
		quality = 0

	world = Node3D.new()
	world.set_script(WorldScript)
	world.name = "World"
	add_child(world)
	world.build(quality)

	hay = Node3D.new()
	hay.set_script(HayScript)
	hay.name = "Haystack"
	add_child(hay)
	var per_col := 20
	if OS.get_environment("SHOT_PER_COL") != "":
		per_col = int(OS.get_environment("SHOT_PER_COL"))
	elif quality == 0:
		per_col = 12
	hay.max_per_col = per_col
	hay.build(20261001, GameState.needles_total)

	player = CharacterBody3D.new()
	player.set_script(PlayerScript)
	player.name = "Player"
	add_child(player)
	player.setup(hay, world)
	player.teleport(Vector3(2.0, 0.4, 25.0), PI, -0.12)

	hud = CanvasLayer.new()
	hud.set_script(HudScript)
	hud.name = "HUD"
	add_child(hud)
	hud.setup(player, hay)
	hud.new_pile_requested.connect(new_pile)

	_build_particles()
	hay.straw_particles.connect(_spawn_straw_particles)

	GameState.needles_changed.emit(GameState.needles_found, GameState.needles_total)
	GameState.money_changed.emit(GameState.money)

	if _shot_mode:
		_run_shot(env_shot)

func _setup_input() -> void:
	var defs := {
		"move_f": [KEY_W, KEY_UP],
		"move_b": [KEY_S, KEY_DOWN],
		"move_l": [KEY_A, KEY_LEFT],
		"move_r": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"dig": [KEY_F],
		"interact": [KEY_E],
		"menu": [KEY_TAB],
		"detector": [KEY_Q],
		"tool_next": [KEY_R],
	}
	for action in defs:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in defs[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("dig_mouse"):
		InputMap.add_action("dig_mouse")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("dig_mouse", mb)

func _build_particles() -> void:
	_particles = CPUParticles3D.new()
	_particles.amount = 28
	_particles.lifetime = 1.1
	_particles.one_shot = true
	_particles.explosiveness = 0.9
	_particles.direction = Vector3(0, 1, 0)
	_particles.spread = 60.0
	_particles.initial_velocity_min = 1.2
	_particles.initial_velocity_max = 3.2
	_particles.gravity = Vector3(0, -9.0, 0)
	_particles.scale_amount_min = 0.5
	_particles.scale_amount_max = 1.4
	_particles.emitting = false
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := 0.34
	var W := 0.012
	var q := [Vector3(-W, 0, 0), Vector3(W, 0, 0), Vector3(W, 0.01, -L), Vector3(-W, 0.01, -L)]
	st.add_vertex(q[0]); st.add_vertex(q[1]); st.add_vertex(q[2])
	st.add_vertex(q[0]); st.add_vertex(q[2]); st.add_vertex(q[3])
	st.generate_normals()
	_particles.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.8, 0.4)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_particles.material_override = m
	add_child(_particles)

func _spawn_straw_particles(pos: Vector3, amount: int) -> void:
	if _particles == null:
		return
	_particles.global_position = pos + Vector3(0, 0.2, 0)
	_particles.amount = int(clampf(amount * 2.0, 6.0, 40.0))
	_particles.restart()
	_particles.emitting = true

func _process(delta: float) -> void:
	if _shot_mode:
		return
	var mv := Vector2(
		Input.get_action_strength("move_r") - Input.get_action_strength("move_l"),
		Input.get_action_strength("move_b") - Input.get_action_strength("move_f")
	)
	if mv.length() > 0.01:
		player.move_input = mv
	if Input.is_action_just_pressed("jump"):
		player.want_jump = true
	if Input.is_action_just_pressed("dig") or (Input.is_action_pressed("dig_mouse") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		player.want_dig = true
	if Input.is_action_just_pressed("interact"):
		player.want_interact = true
	if Input.is_action_just_pressed("detector"):
		GameState.detector_on = not GameState.detector_on
		player._show_tool()
	if Input.is_action_just_pressed("tool_next"):
		hud._cycle_tool()
	if Input.is_action_just_pressed("menu"):
		if hud._shop.visible:
			hud._shop.visible = false
		else:
			hud._open_shop()
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_autosave += delta
	if _autosave > 12.0:
		_autosave = 0.0
		GameState.save()

func new_pile() -> void:
	GameState.needles_found = 0
	GameState.needles_total = mini(12, GameState.needles_total + 2)
	hay.build(randi(), GameState.needles_total)
	hay.force_rebuild()
	player.teleport(Vector3(2.0, 0.4, 25.0), PI, -0.12)
	GameState.needles_changed.emit(GameState.needles_found, GameState.needles_total)
	GameState.save()
	GameState.toast.emit("Новый стог: %d иголок" % GameState.needles_total)

# ------------------------------------------------------------------ скриншот
func _run_shot(path: String) -> void:
	var pos := Vector3(0, 3.0, 26.0)
	var sp: String = OS.get_environment("SHOT_POS")
	if sp != "":
		var parts := sp.split(",")
		if parts.size() == 3:
			pos = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	var yaw := float(OS.get_environment("SHOT_YAW")) if OS.get_environment("SHOT_YAW") != "" else 180.0
	var pitch := float(OS.get_environment("SHOT_PITCH")) if OS.get_environment("SHOT_PITCH") != "" else -12.0
	var frames := int(OS.get_environment("SHOT_FRAMES")) if OS.get_environment("SHOT_FRAMES") != "" else 30
	player.teleport(pos - Vector3(0, 1.62, 0), yaw, pitch)
	var tool_env := OS.get_environment("SHOT_TOOL")
	if tool_env != "":
		GameState.tool = tool_env
		if tool_env == "shovel" and int(GameState.up.shovel) == 0:
			GameState.up.shovel = 3
			GameState.up.hands = 4
	if OS.get_environment("SHOT_DIG") != "":
		hay.dig(Vector3(0, 8.4, 0), 400000.0, false)
		hay.force_rebuild()
	var hide := OS.get_environment("SHOT_HIDE")
	if hide == "hay":
		hay.visible = false
	elif hide == "world":
		world.visible = false
	elif hide == "straws":
		hay._mmi.visible = false
	elif hide == "core":
		hay._core.visible = false
	if OS.get_environment("SHOT_DEBUG") != "":
		var cam: Camera3D = player.camera
		var from: Vector3 = cam.global_position
		var to: Vector3 = from - cam.global_transform.basis.z * 60.0
		var q := PhysicsRayQueryParameters3D.create(from, to)
		var h := get_world_3d().direct_space_state.intersect_ray(q)
		if h.is_empty():
			print("RAY: ничего не задето за 60 м")
		else:
			print("RAY: ", h.collider.name, " на ", from.distance_to(h.position), " м, точка ", h.position)
		var faces: PackedVector3Array = (hay._shape.shape as ConcavePolygonShape3D).get_faces()
		var core_faces: PackedVector3Array = hay._core.mesh.get_faces() if hay._core.mesh else PackedVector3Array()
		print("FACES: коллизия=", faces.size(), " ядро=", core_faces.size(),
			" heights[центр]=", hay.heights[20 * 40 + 20], " трансформ=", hay.global_transform.origin)
		print("DEBUG hay children=", hay.get_child_count(),
			" mmi=", hay._mmi != null,
			" mm_count=", hay._mm.mesh.get_surface_count() if hay._mm and hay._mm.mesh else -1,
			" visible=", hay._mm.visible_instance_count if hay._mm else -1,
			" core_surfaces=", hay._core.mesh.get_surface_count() if hay._core and hay._core.mesh else -1,
			" cam=", player.camera.global_position, " yaw=", rad_to_deg(player.yaw))
	if OS.get_environment("SHOT_SHOP") != "":
		hud._open_shop()
	for i in frames:
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img:
		img.save_png(path)
		print("SHOT SAVED ", path)
	get_tree().quit()
