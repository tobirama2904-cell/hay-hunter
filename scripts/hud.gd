extends CanvasLayer
# ============================================================================
#  HUD — деньги, статистика, силы, детектор, подсказки, виртуальный стик,
#  тач-обзор, кнопки и магазин/техдерево.
# ============================================================================

signal new_pile_requested()

var player: Node3D
var haystack: Node3D

var _money: Label
var _stats: Label
var _stamina: ProgressBar
var _det_bar: ProgressBar
var _prompt: Label
var _toast: Label
var _toast_t := 0.0
var _fps: Label
var _joystick: Control
var _joy_knob: Control
var _look: Control
var _shop: Control
var _shop_list: VBoxContainer
var _finish: Control
var _joy_center := Vector2.ZERO

const STICK_R := 92.0

func setup(p: Node3D, hs: Node3D) -> void:
	player = p
	haystack = hs

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_money = _label(root, "", 34, Color(0.95, 0.9, 0.6))
	_money.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_money.position = Vector2(-250, 12)
	_money.size = Vector2(238, 44)
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_stats = _label(root, "", 19, Color(0.92, 0.93, 0.95))
	_stats.position = Vector2(14, 12)
	_stats.size = Vector2(430, 120)

	var st_cap := _label(root, "СИЛЫ", 14, Color(0.8, 0.85, 0.9))
	st_cap.position = Vector2(14, 132)
	st_cap.size = Vector2(80, 22)
	_stamina = ProgressBar.new()
	_stamina.position = Vector2(70, 132)
	_stamina.size = Vector2(240, 20)
	_stamina.show_percentage = false
	_stamina.max_value = 100
	root.add_child(_stamina)

	_det_bar = ProgressBar.new()
	_det_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_det_bar.position = Vector2(-160, -118)
	_det_bar.size = Vector2(320, 14)
	_det_bar.show_percentage = false
	_det_bar.max_value = 100
	root.add_child(_det_bar)

	_label(root, "+", 22, Color(1, 1, 1, 0.75)).set_anchors_preset(Control.PRESET_CENTER)

	_prompt = _label(root, "", 22, Color(1, 1, 0.85))
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.position = Vector2(-260, 54)
	_prompt.size = Vector2(520, 34)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_toast = _label(root, "", 24, Color(1, 0.95, 0.7))
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-320, 96)
	_toast.size = Vector2(640, 40)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0

	_fps = _label(root, "", 14, Color(0.7, 0.8, 0.7, 0.7))
	_fps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps.position = Vector2(-120, 60)
	_fps.size = Vector2(110, 20)
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_build_look_pad(root)
	_build_joystick(root)
	_build_buttons(root)
	_build_shop(root)
	_build_finish(root)

	GameState.money_changed.connect(func(_v): _refresh())
	GameState.carried_changed.connect(func(_v): _refresh())
	GameState.straws_changed.connect(func(_v): _refresh())
	GameState.needles_changed.connect(func(_f, _t): _refresh())
	GameState.stats_changed.connect(_refresh)
	GameState.toast.connect(_show_toast)
	GameState.pile_finished.connect(_on_finished)
	if player:
		player.prompt_changed.connect(func(t): _prompt.text = t)
	_refresh()

func _label(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _build_look_pad(root: Control) -> void:
	_look = Control.new()
	_look.set_anchors_preset(Control.PRESET_FULL_RECT)
	_look.mouse_filter = Control.MOUSE_FILTER_PASS
	_look.gui_input.connect(_on_look_input)
	root.add_child(_look)

func _build_joystick(root: Control) -> void:
	_joystick = Control.new()
	_joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_joystick.position = Vector2(26, -220)
	_joystick.size = Vector2(STICK_R * 2.0, STICK_R * 2.0)
	_joystick.mouse_filter = Control.MOUSE_FILTER_PASS
	var base := Panel.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.14, 0.35)
	sb.set_corner_radius_all(200)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(2)
	base.add_theme_stylebox_override("panel", sb)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick.add_child(base)
	_joy_knob = Control.new()
	_joy_knob.size = Vector2(74, 74)
	_joy_knob.position = Vector2(STICK_R - 37, STICK_R - 37)
	var knob := Panel.new()
	knob.set_anchors_preset(Control.PRESET_FULL_RECT)
	var kb := StyleBoxFlat.new()
	kb.bg_color = Color(0.95, 0.85, 0.5, 0.5)
	kb.set_corner_radius_all(200)
	knob.add_theme_stylebox_override("panel", kb)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_knob.add_child(knob)
	_joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick.add_child(_joy_knob)
	_joystick.gui_input.connect(_on_joystick_input)
	root.add_child(_joystick)

func _on_joystick_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_joy_center = event.position + _joystick.position
		else:
			if player:
				player.move_input = Vector2.ZERO
			_joy_knob.position = Vector2(STICK_R - 37, STICK_R - 37)
	elif event is InputEventScreenDrag:
		_set_stick(event.position - _joy_center)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_set_stick(event.position + _joystick.position - _joy_center)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if player:
			player.move_input = Vector2.ZERO
		_joy_knob.position = Vector2(STICK_R - 37, STICK_R - 37)

func _set_stick(v: Vector2) -> void:
	var l := minf(v.length(), STICK_R)
	var d: Vector2 = v.normalized() * l if v.length() > 0.001 else Vector2.ZERO
	if player:
		player.move_input = Vector2(d.x, d.y) / STICK_R
	_joy_knob.position = Vector2(STICK_R, STICK_R) + d - Vector2(37, 37)

func _on_look_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		if player:
			player.look_delta += event.relative
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if player:
			player.look_delta += event.relative

func _btn(parent: Control, text: String, size: Vector2, pos: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size = size
	b.position = pos
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b

func _build_buttons(root: Control) -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	holder.position = Vector2(-330, -330)
	holder.size = Vector2(320, 320)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	_btn(holder, "КОПАТЬ", Vector2(150, 150), Vector2(160, 160), func(): if player: player.want_dig = true)
	_btn(holder, "ПРЫЖОК", Vector2(96, 74), Vector2(56, 160), func(): if player: player.want_jump = true)
	_btn(holder, "E", Vector2(96, 74), Vector2(160, 74), func(): if player: player.want_interact = true)
	_btn(holder, "ДЕТЕКТОР", Vector2(122, 56), Vector2(24, 246), func():
		GameState.detector_on = not GameState.detector_on
		if player: player._show_tool()
		_show_toast("Металлоискатель: " + ("вкл" if GameState.detector_on else "выкл")))
	_btn(holder, "ИНСТР.", Vector2(122, 56), Vector2(24, 184), func(): _cycle_tool())
	_btn(holder, "МЕНЮ", Vector2(96, 56), Vector2(160, 8), func(): _open_shop())
	_btn(holder, "БЕГ", Vector2(96, 56), Vector2(56, 98), func():
		if player: player._mobile_sprint = not player._mobile_sprint)

func _cycle_tool() -> void:
	var order := ["hands", "shovel", "pitchfork", "vacuum"]
	var have := []
	for t in order:
		if t == "hands" or int(GameState.up[t]) > 0:
			have.append(t)
	if have.is_empty():
		return
	var i := have.find(GameState.tool)
	i = (i + 1) % have.size()
	GameState.tool = have[i]
	if player:
		player._show_tool()
	_show_toast("Инструмент: " + str(GameState.UPGRADES[GameState.tool].name))

func _build_shop(root: Control) -> void:
	_shop = Control.new()
	_shop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shop.visible = false
	root.add_child(_shop)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shop.add_child(dim)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-390, -300)
	panel.size = Vector2(780, 600)
	_shop.add_child(panel)
	var title := _label(panel, "МАГАЗИН И ТЕХДЕРЕВО", 28, Color(0.95, 0.9, 0.6))
	title.position = Vector2(24, 14)
	title.size = Vector2(500, 36)
	_btn(panel, "ЗАКРЫТЬ", Vector2(140, 44), Vector2(620, 14), func(): _shop.visible = false)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 66)
	scroll.size = Vector2(740, 520)
	panel.add_child(scroll)
	_shop_list = VBoxContainer.new()
	_shop_list.custom_minimum_size = Vector2(720, 0)
	scroll.add_child(_shop_list)

func _open_shop() -> void:
	_shop.visible = true
	_refresh_shop()

func _refresh_shop() -> void:
	if _shop_list == null:
		return
	for c in _shop_list.get_children():
		c.queue_free()
	for id in GameState.UPGRADES:
		var u: Dictionary = GameState.UPGRADES[id]
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(700, 64)
		_shop_list.add_child(row)
		var lvl := int(GameState.up[id])
		var cost := GameState.upgrade_cost(id)
		var lab := Label.new()
		lab.text = "%s\n%s  ·  ур. %d/%d" % [str(u.name), str(u.info), lvl, int(u.max)]
		lab.add_theme_font_size_override("font_size", 17)
		lab.custom_minimum_size = Vector2(520, 60)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(lab)
		if cost < 0.0:
			var done := Label.new()
			done.text = "МАКС"
			done.add_theme_font_size_override("font_size", 18)
			done.custom_minimum_size = Vector2(160, 60)
			row.add_child(done)
			continue
		var b := Button.new()
		b.text = "%.2f $" % cost
		b.custom_minimum_size = Vector2(160, 56)
		b.disabled = GameState.money < cost
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(func():
			if GameState.buy(id):
				Sfx.play("buy", -4.0, 1.0)
				_show_toast("Куплено: %s (ур. %d)" % [str(u.name), int(GameState.up[id])])
				if id == "shovel" and GameState.tool == "hands":
					GameState.tool = "shovel"
					if player: player._show_tool()
				_refresh_shop()
			else:
				_show_toast("Не хватает денег"))
		row.add_child(b)

func _build_finish(root: Control) -> void:
	_finish = Control.new()
	_finish.set_anchors_preset(Control.PRESET_FULL_RECT)
	_finish.visible = false
	root.add_child(_finish)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_finish.add_child(dim)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-320, -160)
	panel.size = Vector2(640, 320)
	_finish.add_child(panel)
	var t := _label(panel, "ВСЕ ИГОЛКИ НАЙДЕНЫ!", 30, Color(1, 0.9, 0.6))
	t.position = Vector2(40, 30)
	t.size = Vector2(560, 40)
	var d := _label(panel, "Апгрейды и деньги сохраняются.\nСледующий стог — ещё больше сена и иголок.", 20, Color(0.9, 0.9, 0.95))
	d.position = Vector2(40, 86)
	d.size = Vector2(560, 80)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var b := _btn(panel, "НОВЫЙ СТОГ", Vector2(240, 64), Vector2(40, 220), func():
		_finish.visible = false
		new_pile_requested.emit())
	b.add_theme_font_size_override("font_size", 22)
	var b2 := _btn(panel, "ОСТАТЬСЯ", Vector2(200, 64), Vector2(320, 220), func(): _finish.visible = false)
	b2.add_theme_font_size_override("font_size", 22)

func _on_finished() -> void:
	_finish.visible = true

func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_t = 3.4
	_toast.modulate.a = 1.0

func _refresh() -> void:
	if _money:
		_money.text = "%.2f $" % GameState.money
	if _stats and haystack:
		_stats.text = "Соломы в стоге: %s\nВ руках: %d / %d\nИголки: %d / %d\nИнструмент: %s" % [
			_fmt(haystack.straws_left()), int(GameState.carried), int(GameState.capacity()),
			GameState.needles_found, GameState.needles_total,
			str(GameState.UPGRADES[GameState.tool].name),
		]

func _fmt(v: float) -> String:
	var s := str(int(v))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = " " + out
	return out

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t < 0.9:
			_toast.modulate.a = maxf(0.0, _toast_t / 0.9)
	if _stamina and player:
		_stamina.max_value = GameState.stamina_max()
		_stamina.value = GameState.stamina
	if _det_bar and player:
		_det_bar.value = player.detector_signal * 100.0
	if _fps:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
