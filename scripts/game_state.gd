extends Node
# ============================================================================
#  GameState — глобальное состояние: деньги, апгрейды, сохранения.
#  Автолоад: доступен из любого скрипта как `GameState`.
# ============================================================================

signal money_changed(v: float)
signal carried_changed(v: float)
signal straws_changed(v: float)
signal needles_changed(found: int, total: int)
signal toast(text: String)
signal stats_changed()
signal pile_finished()

const SAVE_PATH := "user://hay_hunter_save.json"

var money := 0.0
var price_per_straw := 0.022

const UPGRADES := {
	"hands":      {"name": "Руки",             "kind": "stat", "max": 9, "costs": [2, 6, 18, 45, 120, 300, 750, 1800],
				   "info": "Сколько соломы хватаете за раз"},
	"shovel":     {"name": "Лопата",           "kind": "tool", "max": 9, "costs": [25, 60, 150, 340, 780, 1800, 4000, 9000],
				   "info": "Загребает много соломы, тратит силы"},
	"bucket":     {"name": "Ведро",            "kind": "tool", "max": 7, "costs": [12, 30, 70, 160, 360, 800, 1700],
				   "info": "+2 соломы к переноске за уровень"},
	"wheelbarrow": {"name": "Тачка",           "kind": "tool", "max": 7, "costs": [2, 6, 14, 30, 70, 160, 360],
				   "info": "Переносит целые охапки: ×6 за уровень"},
	"pitchfork":  {"name": "Вилы",             "kind": "tool", "max": 5, "costs": [50, 140, 320, 700, 1500],
				   "info": "Швыряет сено прочь — быстро, но без денег"},
	"vacuum":     {"name": "Пылесос",          "kind": "tool", "max": 5, "costs": [400, 900, 2000, 4500, 9000],
				   "info": "Всасывает сено с огромной силой"},
	"stamina":    {"name": "Выносливость",     "kind": "stat", "max": 9, "costs": [8, 20, 45, 100, 220, 480, 1000, 2100],
				   "info": "+25 к запасу сил за уровень"},
	"boots":      {"name": "Кроссовки",        "kind": "stat", "max": 9, "costs": [6, 15, 35, 80, 170, 360, 760, 1600],
				   "info": "+4% скорости за уровень"},
	"detector":   {"name": "Металлоискатель",  "kind": "stat", "max": 7, "costs": [20, 55, 130, 300, 650, 1400],
				   "info": "+2 м дальности сигнала за уровень"},
}

var up := {
	"hands": 1, "shovel": 0, "bucket": 0, "wheelbarrow": 0, "pitchfork": 0, "vacuum": 0,
	"stamina": 1, "boots": 1, "detector": 1,
}

var stamina := 100.0
var carried := 0.0
var needles_found := 0
var needles_total := 5
var tool := "hands"
var detector_on := true

func dig_power() -> float:
	var base: float = [3.0, 4.0, 6.0, 9.0, 13.0, 18.0, 24.0, 32.0, 42.0][int(up.hands) - 1]
	var mult := 1.0
	if int(up.shovel) > 0 and tool != "pitchfork" and tool != "vacuum":
		mult = 4.0 + 2.0 * (int(up.shovel) - 1)
	elif int(up.pitchfork) > 0 and tool == "pitchfork":
		mult = 5.0 + 3.0 * (int(up.pitchfork) - 1)
	elif int(up.vacuum) > 0 and tool == "vacuum":
		mult = 10.0 + 6.0 * (int(up.vacuum) - 1)
	return base * mult

func dig_stamina_cost() -> float:
	var c := 5.0
	if tool == "shovel":
		c = 7.0
	elif tool == "pitchfork":
		c = 9.0
	elif tool == "vacuum":
		c = 11.0
	return c * (1.0 - 0.02 * (int(up.stamina) - 1))

func stamina_max() -> float:
	return 100.0 + 25.0 * (int(up.stamina) - 1)

func capacity() -> float:
	var cap := 1.0 + 2.0 * int(up.bucket)
	cap *= 1.0 + 6.0 * int(up.wheelbarrow)
	cap *= 1.0 + 10.0 * int(up.vacuum)
	return cap

func walk_speed() -> float:
	return 4.4 * (1.0 + 0.04 * (int(up.boots) - 1))

func detector_range() -> float:
	return 3.0 + 2.0 * (int(up.detector) - 1)

func upgrade_cost(id: String) -> float:
	var u: Dictionary = UPGRADES[id]
	var lvl := int(up[id])
	if lvl >= int(u.max):
		return -1.0
	var idx := lvl - 1 if u.kind == "stat" else lvl
	return float(u.costs[idx])

func buy(id: String) -> bool:
	var c := upgrade_cost(id)
	if c < 0.0 or money < c - 0.001:
		return false
	money -= c
	up[id] = int(up[id]) + 1
	stamina = minf(stamina, stamina_max())
	money_changed.emit(money)
	stats_changed.emit()
	save()
	return true

func add_money(v: float) -> void:
	money = maxf(0.0, money + v)
	money_changed.emit(money)
	stats_changed.emit()

func sell_all() -> float:
	var earned := carried * price_per_straw
	if earned <= 0.0:
		return 0.0
	carried = 0.0
	money += earned
	money_changed.emit(money)
	carried_changed.emit(carried)
	stats_changed.emit()
	save()
	return earned

func hold(v: float, capacity_limit := true) -> float:
	var space := capacity() - carried
	var take := v
	if capacity_limit and space < take:
		take = maxf(0.0, space)
	if take <= 0.0:
		return 0.0
	carried += take
	carried_changed.emit(carried)
	stats_changed.emit()
	return take

func full() -> bool:
	return carried >= capacity() - 0.01

func save() -> void:
	var d := {"money": money, "up": up, "needles_found": needles_found, "tool": tool, "detector_on": detector_on}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return
	money = float(d.get("money", 0.0))
	needles_found = int(d.get("needles_found", 0))
	tool = str(d.get("tool", "hands"))
	detector_on = bool(d.get("detector_on", true))
	var u = d.get("up", {})
	if typeof(u) == TYPE_DICTIONARY:
		for k in up.keys():
			if u.has(k):
				up[k] = int(u[k])

func _ready() -> void:
	load_save()
	stamina = stamina_max()
