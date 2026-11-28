extends Node3D
## A sliding badge door. The reader on each face shows the zone state:
## green when your badge is granted, red when it has been revoked, dark when it has no power.

const GREEN := Color(0.1, 1.0, 0.35)
const RED := Color(1.0, 0.12, 0.08)

var id := ""
var title := ""
var room_a := ""
var room_b := ""
var open := 0.0
var game: Node

var _target := 0.0
var _hold := 0.0
var _slide := Vector3.RIGHT
var _panel: StaticBody3D
var _reader: StandardMaterial3D
var _flash := 0.0
var _state := "red"


func build(kit: RefCounted, door_id: String, door_title: String, pos: Vector3, along_x: bool, a: String, b: String, layers: int) -> void:
	id = door_id
	title = door_title
	room_a = a
	room_b = b
	game = kit.g
	position = pos
	_slide = Vector3.RIGHT if along_x else Vector3.BACK
	var normal := Vector3.BACK if along_x else Vector3.RIGHT

	_panel = StaticBody3D.new()
	_panel.collision_layer = 3
	_panel.set_meta("door", self)
	var size := Vector3(DOOR_W(), 2.1, 0.07) if along_x else Vector3(0.07, 2.1, DOOR_W())
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = kit.mat(Color(0.1, 0.105, 0.115), 0.45, 0.6)
	mi.layers = layers
	_panel.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	_panel.add_child(cs)
	_panel.position = Vector3(0, 1.05, 0)
	add_child(_panel)

	_reader = kit.glow_mat(RED, 1.0)
	var font: Font = load("res://fonts/IBMPlexMono-Medium.ttf")
	for s: float in [-1.0, 1.0]:
		var at := _slide * 0.82 + normal * s * 0.12 + Vector3(0, 1.2, 0)
		var rm := BoxMesh.new()
		rm.size = Vector3(0.09, 0.15, 0.05) if along_x else Vector3(0.05, 0.15, 0.09)
		var r := MeshInstance3D.new()
		r.mesh = rm
		r.material_override = _reader
		r.position = at
		r.layers = layers
		add_child(r)
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.36, 0.5, 0.3)
		var bc := CollisionShape3D.new()
		bc.shape = bs
		body.add_child(bc)
		body.position = at + normal * s * 0.08
		body.set_meta("door", self)
		add_child(body)
		var label := Label3D.new()
		label.text = title
		label.font = font
		label.font_size = 48
		label.pixel_size = minf(0.0029, 0.94 / (maxi(title.length(), 1) * 28.8))
		label.modulate = Color(0.92, 0.94, 0.97)
		label.outline_size = 0
		label.shaded = false
		label.layers = layers
		var facing := Basis()
		if along_x:
			facing = Basis() if s > 0 else Basis(Vector3.UP, PI)
		else:
			facing = Basis(Vector3.UP, PI * 0.5 * s)
		label.transform = Transform3D(facing, normal * s * 0.128 + Vector3(0, 2.36, 0))
		add_child(label)
		# the plate it is printed on: dark blue with a pale edge, the same on every door
		for plate: Array in [[Vector3(1.12, 0.3, 0.012), Color(0.55, 0.58, 0.62), 0.104], [Vector3(1.07, 0.25, 0.012), Color(0.03, 0.07, 0.17), 0.112]]:
			var pm := BoxMesh.new()
			var ps: Vector3 = plate[0]
			pm.size = ps if along_x else Vector3(ps.z, ps.y, ps.x)
			var pi := MeshInstance3D.new()
			pi.mesh = pm
			pi.material_override = kit.glow_mat(plate[1], 0.9)
			pi.position = normal * s * float(plate[2]) + Vector3(0, 2.36, 0)
			pi.layers = layers
			add_child(pi)


func DOOR_W() -> float:
	return 1.16


func _process(delta: float) -> void:
	if _target > open:
		open = minf(1.0, open + delta * 1.7)
	elif _target < open:
		open = maxf(0.0, open - delta * 1.3)
	_panel.position = Vector3(0, 1.05, 0) - _slide * open * 1.14
	if open >= 1.0 and _target >= 1.0:
		_hold -= delta
		if _hold <= 0.0 and game.player.global_position.distance_to(global_position) > 1.5:
			_target = 0.0
			game.sound.play("door_close", -9.0)
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_show(_state, 1.0)


## Set the steady colour of the readers: "green", "red" or "dead".
func set_state(state: String) -> void:
	_state = state
	if _flash <= 0.0:
		_show(state, 1.0)


func _show(state: String, energy: float) -> void:
	var c := GREEN if state == "green" else RED
	if state == "dead":
		c = Color(0.02, 0.02, 0.02)
	_reader.albedo_color = c
	_reader.emission = c
	_reader.emission_energy_multiplier = energy


func badge() -> void:
	if _target >= 1.0:
		_hold = 3.0
		return
	var ok: bool = game.story.on_badge(self)
	_flash = 0.6
	if ok:
		_show("green", 5.0)
		game.sound.play("beep")
		open_now()
	else:
		_show("red" if _state != "dead" else "dead", 5.0)
		game.sound.play("deny")


func open_now(hold := 3.5) -> void:
	if _target < 1.0:
		game.sound.play("door", -7.0)
	_target = 1.0
	_hold = hold


func shut() -> void:
	_target = 0.0
	open = 0.0
