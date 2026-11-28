extends Node
## All sound. The building is never silent until you make it silent: every room has a bed of
## fan noise, and the beds cross-fade as you walk. Everything is in audio/, made by tools/gen_audio.py.

const BEDS := ["bed_room", "bed_hall_a", "bed_hall_b", "bed_plant", "bed_plenum"]
const BED_DB := {"bed_room": -14.0, "bed_hall_a": -5.0, "bed_hall_b": -4.0, "bed_plant": -2.0, "bed_plenum": -8.0}

var duck := 0.0          # 0..1: the fans stall as the figure comes close
var silenced := false    # true after the emergency power-off
var volume := 0.8        # the player's setting, 0..1

var _streams := {}
var _beds := {}          # name -> AudioStreamPlayer
var _level := {}         # name -> 0..1 current fade
var _bed := ""
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _alarm: AudioStreamPlayer
var _deep: AudioStreamPlayer   # a recorded room tone under the machine halls
var _deep_lv := 0.0
var _far_t := 12.0             # until the next sound from somewhere else in the building
var _static: AudioStreamPlayer


func _ready() -> void:
	var dir := DirAccess.open("res://audio")
	if dir:
		for f in dir.get_files():
			var n := f.trim_suffix(".import").trim_suffix(".remap")
			if n.ends_with(".ogg"):
				_streams[n.trim_suffix(".ogg")] = load("res://audio/" + n)
	for name: String in BEDS:
		_beds[name] = _looper(name)
		_level[name] = 0.0
	_alarm = _looper("alarm")
	_deep = _looper("bed_deep")
	_static = _looper("static")
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	set_volume(volume)


func _looper(name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if _streams.has(name):
		var s: AudioStreamOggVorbis = _streams[name]
		s.loop = true
		p.stream = s
	p.volume_db = -80.0
	add_child(p)
	return p


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))


func play(name: String, db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(name):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[name]
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func step(perforated: bool, jogging: bool, crouching: bool) -> void:
	var name := "step_p%d" % (randi() % 3) if perforated else "step_s%d" % (randi() % 5)
	play(name, -4.0 if jogging else (-22.0 if crouching else -12.0), randf_range(0.94, 1.06))


func set_bed(name: String) -> void:
	_bed = name


func alarm(on: bool) -> void:
	if on and not _alarm.playing:
		_alarm.volume_db = -9.0
		_alarm.play()
	elif not on:
		_alarm.stop()


func static_noise(on: bool) -> void:
	if on and not _static.playing:
		_static.volume_db = -14.0
		_static.play()
	elif not on:
		_static.stop()


func _process(delta: float) -> void:
	# under the fans, the building itself: a low recorded tone in the big rooms, and now
	# and then something metal moving a long way off
	var big := _bed != "bed_room" and _bed != "" and not silenced
	_deep_lv = move_toward(_deep_lv, 1.0 if big else 0.0, delta * 0.4)
	if _deep_lv > 0.001:
		if not _deep.playing:
			_deep.play()
		_deep.volume_db = -15.0 + linear_to_db(_deep_lv * (1.0 - duck * 0.5))
	elif _deep.playing:
		_deep.stop()
	if _bed != "":
		_far_t -= delta
		if _far_t <= 0.0:
			_far_t = randf_range(16.0, 44.0)
			play("far%d" % (randi() % 6), randf_range(-27.0, -19.0) + (6.0 if silenced else 0.0), randf_range(0.6, 0.95))
	for name: String in BEDS:
		var p: AudioStreamPlayer = _beds[name]
		var want := 1.0 if (name == _bed and not silenced) else 0.0
		_level[name] = move_toward(_level[name], want, delta * (0.5 if silenced else 1.2))
		var lv: float = _level[name] * (1.0 - duck)
		if lv <= 0.001:
			if p.playing:
				p.stop()
			continue
		if not p.playing:
			p.play()
		p.volume_db = float(BED_DB[name]) + linear_to_db(lv)
