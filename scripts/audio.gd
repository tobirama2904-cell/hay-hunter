extends Node
# ============================================================================
#  Sfx — звуки (файлы генерирует tools/gen_sounds.py).
# ============================================================================

const FILES := {
	"rustle": "res://assets/sounds/rustle.wav",
	"rustle2": "res://assets/sounds/rustle2.wav",
	"scoop": "res://assets/sounds/scoop.wav",
	"dig_hit": "res://assets/sounds/dig_hit.wav",
	"beep": "res://assets/sounds/beep.wav",
	"sell": "res://assets/sounds/sell.wav",
	"buy": "res://assets/sounds/buy.wav",
	"found": "res://assets/sounds/found.wav",
	"step": "res://assets/sounds/step.wav",
	"ambient": "res://assets/sounds/ambient.wav",
}

var _streams := {}
var _ui_pool: Array[AudioStreamPlayer] = []
var _world_pool: Array[AudioStreamPlayer3D] = []
var _ui_idx := 0
var _world_idx := 0
var _ambient: AudioStreamPlayer

func _ready() -> void:
	for name in FILES:
		var p: String = FILES[name]
		if ResourceLoader.exists(p):
			_streams[name] = load(p)
	var amb = _streams.get("ambient")
	if amb is AudioStreamWAV:
		amb.loop_mode = AudioStreamWAV.LOOP_FORWARD
		amb.loop_end = int(amb.data.size() / 2)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_ui_pool.append(p)
	for i in 12:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 8.0
		p.max_distance = 40.0
		add_child(p)
		_world_pool.append(p)
	if _streams.has("ambient"):
		_ambient = AudioStreamPlayer.new()
		_ambient.stream = _streams["ambient"]
		_ambient.volume_db = -16.0
		add_child(_ambient)
		_ambient.play()

func play(name: String, volume_db := -6.0, pitch := 1.0) -> void:
	if not _streams.has(name):
		return
	var p := _ui_pool[_ui_idx]
	_ui_idx = (_ui_idx + 1) % _ui_pool.size()
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func play3d(name: String, pos: Vector3, volume_db := -6.0, pitch := 1.0) -> void:
	if not _streams.has(name):
		return
	var p := _world_pool[_world_idx]
	_world_idx = (_world_idx + 1) % _world_pool.size()
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.global_position = pos
	p.play()
