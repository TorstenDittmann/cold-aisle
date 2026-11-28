extends Node3D
## The figure in Hall B. It is never lit: it is drawn in flat black, so all you see of it
## is the rack LEDs it blocks. It walks the cold aisles and the two cross corridors, and is
## drawn to torchlight and to jogging footsteps. It cannot follow you into a hot aisle.

const Kit := preload("res://scripts/build.gd")
const Z_N := -1.3
const Z_S := Kit.AISLE_LEN + 1.3
const N := Kit.AISLES
const LAST := Kit.AISLES - 1
const AISLE2_END := Kit.CAGE_Z0 - 1.6     # the east aisle stops short at Cage 7

var game: Node
var active := false
var hunting := 0.0
var _goal := Vector3.ZERO
var _patrol := Vector3.ZERO
var _last_seen := Vector3.ZERO
var _sway := 0.0


func _ready() -> void:
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color(0, 0, 0)
	black.disable_fog = true
	var body := CapsuleMesh.new()
	body.radius = 0.19
	body.height = 1.85
	var b := MeshInstance3D.new()
	b.mesh = body
	b.material_override = black
	b.position.y = 0.93
	add_child(b)
	var head := SphereMesh.new()
	head.radius = 0.13
	head.height = 0.3
	var hd := MeshInstance3D.new()
	hd.mesh = head
	hd.material_override = black
	hd.position.y = 2.0
	add_child(hd)
	for s: float in [-1.0, 1.0]:
		var arm := CapsuleMesh.new()
		arm.radius = 0.055
		arm.height = 1.0
		var am := MeshInstance3D.new()
		am.mesh = arm
		am.material_override = black
		am.position = Vector3(s * 0.26, 1.2, 0)
		add_child(am)
	visible = false
	reset()


func _ax(a: int) -> float:
	return Kit.HALL_B_X + (a - Kit.MID) * Kit.AISLE_PITCH


func reset() -> void:
	position = Vector3(_ax(Kit.MID), 0, Z_S)
	_patrol = position
	_goal = position
	hunting = 0.0


## Move away from the doors, so that walking in is never an instant catch.
func back_off() -> void:
	if position.z < 8.0:
		position = Vector3(_ax(Kit.MID - 1 + randi() % 2), 0, Kit.AISLE_LEN * 0.5 if position.z < 8.0 and randf() < 0.5 else Z_S)
		_patrol = position
		hunting = 0.0


func _nearest_aisle(x: float, limit := LAST) -> int:
	var best := 0
	for a in limit + 1:
		if absf(x - _ax(a)) < absf(x - _ax(best)):
			best = a
	return best


func _aisle_end(a: int) -> float:
	return AISLE2_END if a == LAST else Z_S


## The next straight leg toward `t`, keeping to aisles and cross corridors.
func _route(t: Vector3) -> Vector3:
	var p := position
	var ta := _nearest_aisle(t.x)
	var t_north := t.z <= 0.0
	var t_south := t.z >= Kit.AISLE_LEN and ta < LAST
	var on_n := absf(p.z - Z_N) < 0.06
	var on_s := absf(p.z - Z_S) < 0.06
	if on_n or on_s:
		var zc := Z_N if on_n else Z_S
		if (on_n and t_north) or (on_s and t_south):
			return Vector3(clampf(t.x, _ax(0), _ax(LAST if on_n else LAST - 1)), 0, zc)
		var via := ta
		if on_s and (ta == LAST or t_north):
			via = _nearest_aisle(p.x, LAST - 1)
		elif on_n and t_south:
			via = _nearest_aisle(p.x, LAST - 1)
		if absf(p.x - _ax(via)) > 0.06:
			return Vector3(_ax(via), 0, zc)
		if t_north:
			return Vector3(p.x, 0, Z_N)
		if t_south:
			return Vector3(p.x, 0, Z_S)
		return Vector3(p.x, 0, clampf(t.z, Z_N, _aisle_end(via)))
	# in an aisle
	var a := _nearest_aisle(p.x)
	if ta == a and not t_north and not t_south:
		return Vector3(_ax(a), 0, clampf(t.z, Z_N, _aisle_end(a)))
	if t_south and a < LAST:
		return Vector3(_ax(a), 0, Z_S)
	if t_north or a == LAST or ta == LAST:
		return Vector3(_ax(a), 0, Z_N)
	# another aisle: leave by whichever end is nearer to both of us
	var by_s := (Z_S - p.z) + (Z_S - t.z)
	var by_n := (p.z - Z_N) + (t.z - Z_N)
	return Vector3(_ax(a), 0, Z_S if by_s < by_n else Z_N)


func _physics_process(delta: float) -> void:
	visible = active and game.room == "hall_b"
	if not active:
		return
	var pl: CharacterBody3D = game.player
	var pp := pl.global_position
	var here: bool = game.room == "hall_b" and not game.kit.in_cage(pp)
	var k: float = 1.0 + 0.15 * game.story.defy
	var flat := Vector2(pp.x - position.x, pp.z - position.z)
	var dist := flat.length()
	if here:
		var same_lane := absf(pp.x - position.x) < 1.4 or (pp.z < 0.0 and position.z < 0.0) or (pp.z > Kit.AISLE_LEN and position.z > Kit.AISLE_LEN)
		var heard: bool = pl.jogging and dist < 16.0 * k
		var seen: bool = pl.torch.visible and (dist < 6.0 or (same_lane and dist < 14.0 * k))
		var close: bool = dist < (1.6 if pl.crouching else 2.7)
		if heard or seen or close:
			if hunting <= 0.0:
				game.sound.play("stall", -4.0)
			hunting = 5.0
			_last_seen = pp
		if dist < 1.0:
			game.story.caught("figure")
			return
	hunting = maxf(0.0, hunting - delta)
	var speed: float = (2.5 + 0.15 * game.story.defy) if hunting > 0.0 else 1.0
	var want := _last_seen if hunting > 0.0 else _patrol
	_goal = _route(want)
	var step := _goal - position
	step.y = 0.0
	if step.length() < 0.05:
		if hunting <= 0.0:
			# it keeps to the part of the hall you have business in
			var a := Kit.MID - 2 + randi() % 4
			_patrol = Vector3(_ax(a), 0, [Z_N, _aisle_end(a), Kit.AISLE_LEN * 0.5][randi() % 3])
	else:
		position += step.normalized() * minf(step.length(), speed * delta)
		rotation.y = lerp_angle(rotation.y, atan2(step.x, step.z), 1.0 - exp(-6.0 * delta))
	_sway += delta * speed * 2.2
	rotation.z = sin(_sway) * 0.03
	# the fans stall around it
	game.sound.duck = clampf(1.0 - dist / 9.0, 0.0, 0.85) if here else 0.0
