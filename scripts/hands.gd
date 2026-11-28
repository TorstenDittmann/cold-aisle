extends Node3D
## Your hands. They come up into view whenever you work on something: the eye turns to
## the thing, leans in, and a hand reaches, presses, pulls or lifts. They hang off the
## camera, so they are always exactly where you are looking.

const REST := Vector3(0.3, -0.62, -0.3)
const KINDS := {
	"rack_a147": "swap", "rack_b07": "plug", "panel7": "plug",
	"abort_a": "press", "epo_b": "press", "fire_panel_a": "press", "chiller2": "press",
	"damper": "press", "damper_pull": "pull", "breaker_b2": "press", "cage_gate": "pull",
	"console7": "press", "dock_shutter": "pull",
	"handheld": "take", "desk_bin": "drop", "note1": "take", "note2": "take", "note3": "take",
	"handover": "take", "ups_log": "take",
	"hatch_b": "lift", "hatch_mmr": "lift", "hatch_cage": "lift",
	"hatch_m": "climb", "hatch_h_up": "climb", "hatch_c": "climb",
}

var game: Node
var hold := false     # the player is kept still until the hand has reached
var busy := false

var _right: Node3D
var _left: Node3D
var _item: MeshInstance3D
var _items := {}

## The handheld is a real thing: a rugged tablet held up in the right hand. Its screen is
## drawn sharp on top by handheld.gd, which asks where the corners are.
const DEV_D := 0.30                       # metres from the eye when raised
const SCREEN := Vector2(0.194, 0.291)
var device: Node3D


func build(g: Node) -> void:
	game = g
	_right = _arm(1.0)
	_left = _arm(-1.0)
	_item = MeshInstance3D.new()
	_item.layers = 0xFFFFF
	_item.visible = false
	_right.add_child(_item)
	_items = {
		"drive": [Vector3(0.11, 0.028, 0.16), _mat(Color(0.5, 0.51, 0.53), 0.5)],
		"cable": [Vector3(0.022, 0.022, 0.5), _mat(Color(0.85, 0.58, 0.04), 0.0)],
		"paper": [Vector3(0.15, 0.004, 0.2), _mat(Color(0.72, 0.7, 0.62), 0.0)],
		"slab": [Vector3(0.075, 0.012, 0.15), _mat(Color(0.05, 0.05, 0.06), 0.4)],
	}
	visible = false
	_build_device()


func _build_device() -> void:
	device = Node3D.new()
	get_parent().add_child(device)
	var rubber := _mat(Color(0.11, 0.115, 0.125), 0.0)
	var edge := _mat(Color(0.75, 0.3, 0.05), 0.0)
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color(0.035, 0.04, 0.046)
	_part(device, Vector3(0, -0.006, -0.011), Vector3(SCREEN.x + 0.04, SCREEN.y + 0.056, 0.018), rubber)
	_part(device, Vector3(0, 0, -0.001), Vector3(SCREEN.x, SCREEN.y, 0.004), glass)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			_part(device, Vector3(sx * (SCREEN.x * 0.5 + 0.012), sy * (SCREEN.y * 0.5 + 0.012) - 0.006, -0.011), Vector3(0.024, 0.04, 0.024), edge)
	_part(device, Vector3(0, -SCREEN.y * 0.5 - 0.02, 0.0), Vector3(0.05, 0.008, 0.004), _mat(Color(0.25, 0.26, 0.28), 0.0))
	# the hand that holds it: thumb on the bezel, fingers behind, the forearm running down
	var arm := _arm(1.0)
	remove_child(arm)
	device.add_child(arm)
	arm.position = Vector3(SCREEN.x * 0.5 + 0.022, -SCREEN.y * 0.5 + 0.035, -0.046)
	arm.rotation = Vector3(1.3, 0.0, 0.42)
	var glove := _mat(Color(0.5, 0.42, 0.36), 0.0)
	_part(device, Vector3(SCREEN.x * 0.5 + 0.012, -SCREEN.y * 0.5 + 0.045, 0.008), Vector3(0.03, 0.07, 0.022), glove)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.7, 0.85, 1.0)
	glow.light_energy = 0.25
	glow.omni_range = 1.6
	glow.position = Vector3(0, 0, 0.1)
	device.add_child(glow)
	device.visible = false


## Hold the handheld `k` of the way up (0 put away, 1 raised), leaving `edge` of the
## view's width free on the right for touch buttons.
func hold_device(k: float, edge: float) -> void:
	device.visible = k > 0.0
	if not device.visible:
		return
	var cam: Camera3D = get_parent()
	var vp := cam.get_viewport().get_visible_rect().size
	var half_h := DEV_D * tan(deg_to_rad(cam.fov * 0.5))
	var half_w := half_h * vp.x / maxf(vp.y, 1.0)
	var x := half_w * (1.0 - 2.0 * edge) - SCREEN.x * 0.5
	device.position = Vector3(x + 0.03 * (1.0 - k), 0.012 - (half_h * 2.0 + 0.1) * (1.0 - k), -DEV_D)
	device.rotation = Vector3(0, 0, -0.012 + (1.0 - k) * 0.14)


## Top left and top right of the screen, in the world.
func screen_top() -> Array[Vector3]:
	return [device.to_global(Vector3(-SCREEN.x * 0.5, SCREEN.y * 0.5, 0)), device.to_global(Vector3(SCREEN.x * 0.5, SCREEN.y * 0.5, 0))]


func _mat(c: Color, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	m.metallic = metal
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.1   # a hand is never quite lost in the dark
	return m


func _part(parent: Node3D, pos: Vector3, size: Vector3, m: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.layers = 0xFFFFF
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## A forearm in a grey fleece and a work glove, pointing away from the eye.
func _arm(side: float) -> Node3D:
	var n := Node3D.new()
	var sleeve := _mat(Color(0.2, 0.22, 0.25), 0.0)
	var cuff := _mat(Color(0.85, 0.32, 0.06), 0.0)
	var glove := _mat(Color(0.5, 0.42, 0.36), 0.0)
	_part(n, Vector3(0, 0, 0.3), Vector3(0.095, 0.085, 0.46), sleeve)
	_part(n, Vector3(0, 0, 0.065), Vector3(0.1, 0.09, 0.03), cuff)
	_part(n, Vector3(0, 0, -0.01), Vector3(0.09, 0.04, 0.12), glove)
	_part(n, Vector3(0, -0.012, -0.1), Vector3(0.085, 0.03, 0.07), glove)
	_part(n, Vector3(-side * 0.055, -0.005, 0.0), Vector3(0.03, 0.03, 0.08), glove)
	n.position = Vector3(side * REST.x, REST.y, REST.z)
	add_child(n)
	return n


func wants(id: String) -> bool:
	return KINDS.has(id) and not busy and not (id == "damper_pull" and not game.story.flags.has("fibre"))


func _hold_item(id: String) -> void:
	if id == "":
		_item.visible = false
		return
	var mesh := BoxMesh.new()
	mesh.size = _items[id][0]
	_item.mesh = mesh
	_item.material_override = _items[id][1]
	_item.position = Vector3(0, 0.03, -0.12 - mesh.size.z * 0.3)
	_item.visible = true


func _move(arm: Node3D, to: Vector3, secs: float, tilt := Vector3.ZERO) -> Tween:
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(arm, "position", to, secs)
	t.tween_property(arm, "rotation", tilt, secs)
	return t


## Turn to the thing, reach for it, then let the story do what happens, then finish.
func act(id: String, at: Vector3) -> void:
	var kind: String = KINDS[id]
	var pl: CharacterBody3D = game.player
	busy = true
	hold = true
	if game.handheld.raised:
		game.handheld.toggle()   # it goes back on the belt: this takes both hands
	visible = true
	var side := Vector3(-1, 1, 1)
	_right.position = REST
	_left.position = REST * side
	_right.rotation = Vector3.ZERO
	_left.rotation = Vector3.ZERO
	_hold_item({"plug": "cable", "drop": "drive"}.get(kind, ""))
	pl.face(at, 0.4, 0.0 if kind in ["lift", "climb"] else 0.22)
	game.sound.play("cloth%d" % (randi() % 2), -16.0, randf_range(0.9, 1.1))
	var reach := Vector3(0.13, -0.17, -0.5)
	var tilt := Vector3(0.12, 0.2, 0.0)
	match kind:
		"lift":
			reach = Vector3(0.2, -0.3, -0.46)
			tilt = Vector3(-0.5, 0.15, 0.0)
		"climb":
			reach = Vector3(0.2, 0.12, -0.46)
			tilt = Vector3(0.7, 0.1, 0.0)
	_move(_right, reach, 0.42, tilt)
	if kind in ["lift", "climb", "swap"]:
		_move(_left, reach * side + Vector3(0, 0, 0.04), 0.46, tilt * Vector3(1, -1, 1))
	await get_tree().create_timer(0.45).timeout
	hold = false
	var snd: Array = {"press": ["switch", -6.0], "plug": ["click_m", -4.0], "pull": ["latch", -8.0], "take": ["paper", -10.0], "drop": ["click_m", -8.0], "swap": ["click_m", -6.0], "lift": ["hatch", -5.0], "climb": ["cloth0", -10.0]}[kind]
	if not (kind == "take" and id == "handheld"):
		game.sound.play(snd[0], snd[1], randf_range(0.95, 1.05))
	game.story.on_use(id)
	match kind:
		"press":
			await _move(_right, reach + Vector3(0, 0.01, -0.09), 0.09, tilt).finished
			await _move(_right, reach, 0.14, tilt).finished
		"plug":
			await _move(_right, reach + Vector3(0, 0, -0.12), 0.16, tilt).finished
			_item.reparent(self)
			await _move(_right, reach + Vector3(0, -0.02, 0.05), 0.2, tilt).finished
		"pull":
			await _move(_right, reach + Vector3(0, -0.14, 0.12), 0.3, tilt + Vector3(-0.3, 0, 0)).finished
		"take":
			_hold_item("slab" if id == "handheld" else "paper")
			await _move(_right, Vector3(0.1, -0.2, -0.36), 0.3, Vector3(0.5, 0.25, 0.0)).finished
		"drop":
			await _move(_right, reach + Vector3(0, -0.1, -0.05), 0.2, tilt).finished
			_hold_item("")
		"swap":
			# the dead drive comes out, the spare goes in
			_hold_item("drive")
			await _move(_right, reach + Vector3(0, 0, 0.2), 0.45, tilt).finished
			await _move(_right, Vector3(0.34, -0.3, -0.34), 0.3, tilt).finished
			await _move(_right, reach + Vector3(0, 0, 0.2), 0.3, tilt).finished
			await _move(_right, reach + Vector3(0, 0, -0.04), 0.4, tilt).finished
			_hold_item("")
			await _move(_right, reach + Vector3(0, 0, -0.08), 0.1, tilt).finished
		"lift":
			_move(_left, reach * side + Vector3(0, 0.16, 0.06), 0.4, Vector3(-0.2, -0.15, 0.0))
			await _move(_right, reach + Vector3(0, 0.16, 0.06), 0.4, Vector3(-0.2, 0.15, 0.0)).finished
		"climb":
			_move(_left, reach * side + Vector3(0, -0.2, 0.1), 0.35, tilt * Vector3(1, -1, 1))
			await _move(_right, reach + Vector3(0, 0.08, -0.05), 0.35, tilt).finished
	pl.lean_to(0.0, 0.35)
	_move(_left, REST * side, 0.3)
	await _move(_right, REST, 0.3).finished
	if _item.get_parent() != _right:
		_item.reparent(_right)
	_hold_item("")
	visible = false
	busy = false
