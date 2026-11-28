extends RefCounted
## The building: every room, wall, rack and prop of Halden DC-3, assembled in code from a
## small kit of parts. Nothing here knows about the story; it only builds and names things.
##
## Plan (x runs east, z runs south):
##   north row   dock | mantrap | security | meet-me room | UPS
##   corridor    one long corridor, a badge door to every room
##   south row   Data Hall A | Data Hall B (with Cage 7 in its far corner) | chillers
## The raised-floor plenum is a separate crawl space far below, reached through floor hatches.

const DoorScript := preload("res://scripts/door.gd")

const RACK_W := 0.62
const RACK_H := 2.12
const RACK_D := 1.12
const AISLE_PITCH := 5.44      # cold aisle to cold aisle; leaves a 1 m hot aisle between row backs
const ROW_X := 1.66            # row centre, measured from the aisle centre
const FRONT_X := 1.1           # rack fronts face the aisle here
const CEIL_Y := 3.28
const STRIP_GAP := 3.1
const END_PAD := 2.6           # depth of the cross corridor at each end of a hall
const HALL_HALF_W := 9.0        # from a hall's reference aisle to its east wall
const AISLES := 7              # cold aisles in each hall
const MID := 5                 # the aisle between a hall's two doors; the halls run on west of it
const HALL_WEST := MID * AISLE_PITCH + 3.56   # from the reference aisle to the west wall
const HALL_CEIL := 9.0
const RACKS := 80
const BAY := 20                # racks drawn as one piece, so no piece sits under too many lights
const AISLE_LEN := RACKS * RACK_W
const HALL_Z1 := AISLE_LEN + END_PAD
const HALL_B_X := 9.4 + HALL_WEST
const CH_DX := HALL_B_X - 18.4   # how far east the chiller plant sits
const CAGE_Z0 := AISLE_LEN - 6.64
const CONSOLE_Z := CAGE_Z0 + 4.0
const DOOR_W := 1.1
const DOOR_H := 2.1
const ROOM_Z0 := -12.0
const ROOM_Z1 := -6.0
const CORR_Z0 := -5.8
const CORR_Z1 := -2.8
const CORR_X0 := -HALL_WEST
const CORR_X1 := 32.0 + CH_DX
const PLENUM_Y := -30.0
const PLENUM_Z := 60.0
const PLENUM_H := 1.2
const CELL := 1.8
const COOL := Color(0.82, 0.92, 1.0)
const WARM := Color(1.0, 0.8, 0.58)
const TEAL := Color(0.1, 0.9, 0.78)
const AMBER := Color(1.0, 0.7, 0.28)

## '#' wall, '.' crawl space, H/M/C hatches (Hall B, meet-me room, Cage 7), D damper, N the last note.
const PLENUM_MAP: Array[String] = [
	"#################",
	"#H..#.....#....N#",
	"#.#.#.###.#.#####",
	"#.#...#...#.....#",
	"#.#####.#####.#.#",
	"#.......#...D.#.#",
	"#.#####.#.###.#.#",
	"#.#...#.#.#...#.#",
	"#.#.#.#...#.###.#",
	"#...#.M####....C#",
	"#################",
]


class Room:
	var id := ""
	var title := ""
	var rect := Rect2()
	var layers := 0
	var bed := ""
	var visual: Node3D     # drawn, and drawn again mirrored in the floor
	var mirror: Node3D
	var extra: Node3D      # lights, floor, labels, small props: not mirrored
	var lamps: Array = []  # [{light, mesh}] the room's ordinary fittings
	var lit := true


var g: Node
var world: Node3D
var rooms := {}        # id -> Room
var doors := {}        # id -> door node
var uses := {}         # id -> StaticBody3D you can interact with
var props := {}        # id -> Node3D the story switches on and off
var halls := {}        # "a" / "b" -> Dictionary
var spots := {}        # name -> [Vector3, yaw]
var shared: Array = [] # walls between two rooms: {n, m, a, b}
var fibre_mat: StandardMaterial3D
var _shell: Node3D
var _font: Font
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _dark_mat: StandardMaterial3D
var _hall_wall_mat: StandardMaterial3D
var _ceil_mat: StandardMaterial3D
var _wall_now: StandardMaterial3D
var _wall_h := CEIL_Y
var _void_mat: StandardMaterial3D
var _lights_t := 0.0
var _into_v: Node3D     # while a bay of racks is being built, its parts go in here
var _into_e: Node3D
var _floor_shader: Shader
var _front_shader: Shader
var _haze_shader: Shader


func build(game: Node, world_node: Node3D) -> void:
	g = game
	world = world_node
	_font = load("res://fonts/IBMPlexMono-Medium.ttf")
	_floor_shader = load("res://shaders/floor.gdshader")
	_front_shader = load("res://shaders/rack_front.gdshader")
	_haze_shader = load("res://shaders/haze_cone.gdshader")
	_lamp_on = glow_mat(COOL, 4.0)
	_lamp_off = mat(Color(0.1, 0.105, 0.11), 0.6)
	_wall_mat = mat(Color(0.3, 0.31, 0.33), 0.9)
	_hall_wall_mat = mat(Color(0.05, 0.052, 0.058), 0.85)
	_ceil_mat = mat(Color(0.22, 0.225, 0.24), 0.9)
	_dark_mat = mat(Color(0.07, 0.072, 0.08), 0.8)
	_shell = Node3D.new()
	world.add_child(_shell)

	_room("dock", "LOADING DOCK", -9.0, -2.2, ROOM_Z0, ROOM_Z1, 9, "bed_room")
	_room("mantrap", "MANTRAP", -2.0, 1.0, ROOM_Z0, ROOM_Z1, 10, "bed_room")
	_room("security", "SECURITY DESK", 1.2, 9.0, ROOM_Z0, ROOM_Z1, 11, "bed_room")
	_room("mmr", "MEET-ME ROOM", 9.2, 18.0, ROOM_Z0, ROOM_Z1, 12, "bed_room")
	_room("ups", "UPS ROOM", 18.2, 26.0, ROOM_Z0, ROOM_Z1, 13, "bed_plant")
	_room("corridor", "CORRIDOR", CORR_X0, CORR_X1, CORR_Z0, CORR_Z1, 8, "bed_room")
	_room("hall_a", "DATA HALL A", -HALL_WEST, HALL_HALF_W, -END_PAD, HALL_Z1, 3, "bed_hall_a")
	_room("hall_b", "DATA HALL B", HALL_B_X - HALL_WEST, HALL_B_X + HALL_HALF_W, -END_PAD, HALL_Z1, 7, "bed_hall_b")
	_room("chillers", "CHILLER PLANT", 27.8 + CH_DX, 36.0 + CH_DX, -END_PAD, 10.0, 14, "bed_plant")
	_room("plenum", "PLENUM", -1.0, 17.0 * CELL, PLENUM_Z - 1.0, PLENUM_Z + 11.0 * CELL, 15, "bed_plenum")

	# one slab of collision under the whole ground floor
	solid(Vector3(13.5, -0.1, 20.5), Vector3(96.0, 0.2, 70.0))
	_void_mat = StandardMaterial3D.new()
	_void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_void_mat.albedo_color = Color(0.008, 0.01, 0.013)
	_build_walls()
	_build_doors()
	_build_small_rooms()
	_build_corridor()
	_build_hall("a", 0.0, 0, false)
	_build_hall("b", HALL_B_X, 4, true)
	_build_chillers()
	_build_plenum()
	_finish_mirrors()


# ---------------------------------------------------------------- kit of parts

func mat(albedo: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m


func glow_mat(colour: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = energy
	return m


func _room(id: String, title: String, x0: float, x1: float, z0: float, z1: float, bit: int, bed: String) -> Room:
	var r := Room.new()
	r.id = id
	r.title = title
	r.rect = Rect2(x0, z0, x1 - x0, z1 - z0)
	r.layers = 1 << bit
	r.bed = bed
	r.visual = Node3D.new()
	r.extra = Node3D.new()
	world.add_child(r.visual)
	world.add_child(r.extra)
	rooms[id] = r
	return r


func box_in(parent: Node3D, pos: Vector3, size: Vector3, m: Material, layers: int) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.layers = layers
	parent.add_child(mi)
	return mi


## A box that is part of the room and shows in the floor's reflection.
func box(r: Room, pos: Vector3, size: Vector3, m: Material, layers := -1) -> MeshInstance3D:
	return box_in(_into_v if _into_v else r.visual, pos, size, m, r.layers if layers < 0 else layers)


## A small prop: drawn once, not reflected.
func prop(r: Room, pos: Vector3, size: Vector3, m: Material, layers := -1) -> MeshInstance3D:
	return box_in(_into_e if _into_e else r.extra, pos, size, m, r.layers if layers < 0 else layers)


func solid(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	world.add_child(body)
	return body


func block(r: Room, pos: Vector3, size: Vector3, m: Material, layers := -1) -> MeshInstance3D:
	solid(pos, size)
	return box(r, pos, size, m, layers)


func usable(id: String, pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	body.set_meta("use_id", id)
	world.add_child(body)
	uses[id] = body
	return body


func omni(r: Room, pos: Vector3, colour: Color, energy: float, rng: float, mask: int) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = colour
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.light_specular = 0.6
	l.light_cull_mask = mask
	l.position = pos
	(_into_e if _into_e else r.extra).add_child(l)
	return l


## An ordinary ceiling fitting: a glowing bar and the light it casts.
func lamp(r: Room, x: float, z: float, energy := 5.0, rng := 8.0, along_x := true) -> void:
	var size := Vector3(1.2, 0.06, 0.14) if along_x else Vector3(0.14, 0.06, 1.2)
	var mesh := box(r, Vector3(x, CEIL_Y - 0.05, z), size, _lamp_on)
	var l := omni(r, Vector3(x, CEIL_Y - 0.3, z), COOL, energy, rng, r.layers)
	r.lamps.append({"light": l, "mesh": mesh})


func set_room_lit(id: String, on: bool) -> void:
	var r: Room = rooms[id]
	r.lit = on
	for f in r.lamps:
		f["light"].visible = on
		_swap(r, f["mesh"], _lamp_on if on else _lamp_off)


## One fitting of a room, counted from the west or north end.
func set_lamp(id: String, i: int, on: bool) -> void:
	var r: Room = rooms[id]
	var f: Dictionary = r.lamps[i]
	if (f["light"] as Node3D).visible == on:
		return
	f["light"].visible = on
	_swap(r, f["mesh"], _lamp_on if on else _lamp_off)


func _twin(r: Room, n: Node3D) -> Node3D:
	if r.mirror == null:
		return null
	var path: Array[int] = []
	var at: Node = n
	while at != null and at != r.visual:
		path.push_front(at.get_index())
		at = at.get_parent()
	if at == null:
		return null
	var m: Node = r.mirror
	for i: int in path:
		m = m.get_child(i)
	return m as Node3D


## Raise the loading dock shutter by hand: 0 is shut, 1 is open to the morning.
func set_shutter(k: float) -> void:
	var dock: Room = rooms["dock"]
	for id: String in ["shutter", "dawn"]:
		var n: Node3D = props[id]
		var both: Array = [n, _twin(dock, n)]
		for m: Variant in both:
			if m == null:
				continue
			if id == "shutter":
				(m as Node3D).position.y = k * 2.55
			else:
				(m as Node3D).visible = k > 0.01
	var l: OmniLight3D = props["dawn_light"]
	l.light_energy = k * 7.0


## Change a material on a mesh and on its reflection.
func _swap(r: Room, mesh: MeshInstance3D, m: Material) -> void:
	mesh.material_override = m
	var twin := _twin(r, mesh)
	if twin:
		(twin as MeshInstance3D).material_override = m


func floor_piece(r: Room, x0: float, x1: float, z0: float, z1: float, layers: int, aisle_cx := 1000.0, mirror := 0.6) -> void:
	var m := ShaderMaterial.new()
	m.shader = _floor_shader
	m.set_shader_parameter("aisle_x", aisle_cx)
	m.set_shader_parameter("mirror", mirror)
	var plane := PlaneMesh.new()
	plane.size = Vector2(x1 - x0, z1 - z0)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = m
	mi.position = Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	mi.layers = layers
	(_into_e if _into_e else r.extra).add_child(mi)


func sign_text(r: Room, text: String, pos: Vector3, facing: Basis, px := 0.0011, colour := Color(0.75, 0.78, 0.82)) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = _font
	label.font_size = 48
	label.pixel_size = px
	label.modulate = colour
	label.outline_size = 0
	label.shaded = false
	label.layers = r.layers
	label.transform = Transform3D(facing, pos)
	(_into_e if _into_e else r.extra).add_child(label)
	return label


## A group of wall pieces that stays visible while either of two rooms is.
func _shared(a: String, b: String) -> Node3D:
	var n := Node3D.new()
	_shell.add_child(n)
	shared.append({"n": n, "m": null, "a": a, "b": b})
	return n


func _wall_piece(parent: Node3D, pos: Vector3, size: Vector3, layers: int) -> void:
	if size.x <= 0.01 or size.z <= 0.01:
		return
	solid(pos, size)
	# a long wall is drawn in lengths, so that no one piece sits under too many lights
	var along_x := size.x > size.z
	var length := size.x if along_x else size.z
	var n := maxi(1, int(ceil(length / 11.0)))
	for i in n:
		var off := (i + 0.5) * length / n - length * 0.5
		var p := pos + (Vector3(off, 0, 0) if along_x else Vector3(0, 0, off))
		var sz := Vector3(length / n, size.y, size.z) if along_x else Vector3(size.x, size.y, length / n)
		box_in(parent, p, sz, _wall_now if _wall_now else _wall_mat, layers)


## A wall running east-west at depth z, with a door opening centred on each x in `holes`.
func wall_x(parent: Node3D, z: float, x0: float, x1: float, holes: Array, layers: int, thick := 0.2) -> void:
	var cuts := holes.duplicate()
	cuts.sort()
	var a := x0
	for hx: float in cuts:
		var e := hx - DOOR_W * 0.5
		_wall_piece(parent, Vector3((a + e) * 0.5, _wall_h * 0.5, z), Vector3(e - a, _wall_h, thick), layers)
		_wall_piece(parent, Vector3(hx, (DOOR_H + _wall_h) * 0.5, z), Vector3(DOOR_W, _wall_h - DOOR_H, thick), layers)
		a = hx + DOOR_W * 0.5
	_wall_piece(parent, Vector3((a + x1) * 0.5, _wall_h * 0.5, z), Vector3(x1 - a, _wall_h, thick), layers)


## A wall running north-south at x, with a door opening centred on each z in `holes`.
func wall_z(parent: Node3D, x: float, z0: float, z1: float, holes: Array, layers: int, thick := 0.2) -> void:
	var cuts := holes.duplicate()
	cuts.sort()
	var a := z0
	for hz: float in cuts:
		var e := hz - DOOR_W * 0.5
		_wall_piece(parent, Vector3(x, _wall_h * 0.5, (a + e) * 0.5), Vector3(thick, _wall_h, e - a), layers)
		_wall_piece(parent, Vector3(x, (DOOR_H + _wall_h) * 0.5, hz), Vector3(thick, _wall_h - DOOR_H, DOOR_W), layers)
		a = hz + DOOR_W * 0.5
	_wall_piece(parent, Vector3(x, _wall_h * 0.5, (a + z1) * 0.5), Vector3(thick, _wall_h, z1 - a), layers)


func _l(id: String) -> int:
	return (rooms[id] as Room).layers


func aisle_x(hall: String, a: int) -> float:
	return float(halls[hall]["ox"]) + (a - MID) * AISLE_PITCH


# ---------------------------------------------------------------- walls and doors

func _build_walls() -> void:
	var corr := _l("corridor")
	var north := ["dock", "mantrap", "security", "mmr", "ups"]
	var door_x := {"dock": -6.0, "mantrap": -0.5, "security": 5.0, "mmr": 13.5, "ups": 22.0}
	for id: String in north:
		var r: Room = rooms[id]
		var x0 := r.rect.position.x
		var x1 := r.rect.end.x
		# outer north wall, and the wall this room shares with the corridor
		wall_x(r.visual, ROOM_Z0 - 0.1, x0 - 0.2, x1 + 0.2, [], r.layers)
		wall_x(_shared(id, "corridor"), ROOM_Z1 + 0.1, x0 - 0.1, x1 + 0.1, [door_x[id]], r.layers | corr)
	wall_x((rooms["corridor"] as Room).visual, ROOM_Z1 + 0.1, 26.1, CORR_X1 + 0.2, [], corr)
	wall_x((rooms["corridor"] as Room).visual, ROOM_Z1 + 0.1, CORR_X0 - 0.2, -9.1, [], corr)
	wall_z((rooms["dock"] as Room).visual, -9.1, ROOM_Z0, ROOM_Z1, [], _l("dock"))
	wall_z(_shared("dock", "mantrap"), -2.1, ROOM_Z0, ROOM_Z1, [-9.0], _l("dock") | _l("mantrap"))
	wall_z(_shared("mantrap", "security"), 1.1, ROOM_Z0, ROOM_Z1, [], _l("mantrap") | _l("security"))
	wall_z(_shared("security", "mmr"), 9.1, ROOM_Z0, ROOM_Z1, [], _l("security") | _l("mmr"))
	wall_z(_shared("mmr", "ups"), 18.1, ROOM_Z0, ROOM_Z1, [], _l("mmr") | _l("ups"))
	wall_z((rooms["ups"] as Room).visual, 26.1, ROOM_Z0, ROOM_Z1, [], _l("ups"))
	# corridor ends
	wall_z((rooms["corridor"] as Room).visual, CORR_X0 - 0.1, CORR_Z0 - 0.2, CORR_Z1 + 0.2, [], corr)
	wall_z((rooms["corridor"] as Room).visual, CORR_X1 + 0.1, CORR_Z0 - 0.2, CORR_Z1 + 0.2, [], corr)
	# corridor to the halls and the plant
	var ax0 := -HALL_WEST
	var bx0 := HALL_B_X - HALL_WEST
	var bx1 := HALL_B_X + HALL_HALF_W
	var cx0 := 27.8 + CH_DX
	wall_x(_shared("corridor", "hall_a"), -END_PAD - 0.1, ax0 - 0.2, 9.0, [-AISLE_PITCH, AISLE_PITCH], corr | _l("hall_a") | 7)
	wall_x(_shared("corridor", "hall_b"), -END_PAD - 0.1, bx0, bx1, [HALL_B_X - AISLE_PITCH, HALL_B_X + AISLE_PITCH], corr | _l("hall_b") | (7 << 4))
	wall_x(_shared("corridor", "chillers"), -END_PAD - 0.1, cx0, cx0 + 8.4, [30.0 + CH_DX], corr | _l("chillers"))
	# hall shells: tall, dark, and a long way off
	var ha: Room = rooms["hall_a"]
	var hb: Room = rooms["hall_b"]
	var ch: Room = rooms["chillers"]
	_wall_now = _hall_wall_mat
	_wall_h = HALL_CEIL
	wall_z(ha.visual, ax0 - 0.1, -END_PAD, HALL_Z1, [], ha.layers)
	wall_z(_shared("hall_a", "hall_b"), 9.2, -END_PAD - 0.2, HALL_Z1 + 0.2, [], ha.layers | hb.layers, 0.4)
	wall_z(_shared("hall_b", "chillers"), bx1 + 0.2, -END_PAD - 0.2, HALL_Z1 + 0.2, [], hb.layers | ch.layers, 0.4)
	wall_x(ha.visual, HALL_Z1 + 0.1, ax0 - 0.2, 9.0, [], ha.layers)
	wall_x(hb.visual, HALL_Z1 + 0.1, bx0, bx1, [], hb.layers)
	# the halls rise above the corridor that feeds them
	var up := HALL_CEIL - CEIL_Y
	box_in(ha.visual, Vector3((ax0 + 9.0) * 0.5, CEIL_Y + up * 0.5, -END_PAD - 0.05), Vector3(9.0 - ax0, up, 0.1), _void_mat, ha.layers)
	box_in(hb.visual, Vector3((bx0 + bx1) * 0.5, CEIL_Y + up * 0.5, -END_PAD - 0.05), Vector3(bx1 - bx0, up, 0.1), _void_mat, hb.layers)
	_wall_now = null
	_wall_h = CEIL_Y
	wall_x(ch.visual, 10.1, cx0, cx0 + 8.4, [], ch.layers)
	wall_z(ch.visual, cx0 + 8.3, -END_PAD, 10.0, [], ch.layers)


func _door(id: String, title: String, pos: Vector3, along_x: bool, a: String, b: String) -> void:
	var d := Node3D.new()
	d.set_script(DoorScript)
	world.add_child(d)
	d.build(self, id, title, pos, along_x, a, b, _l(a) | _l(b) | (7 if "hall_a" in [a, b] else 0) | ((7 << 4) if "hall_b" in [a, b] else 0))
	doors[id] = d


func _build_doors() -> void:
	_door("dock_mantrap", "MANTRAP", Vector3(-2.1, 0, -9.0), false, "dock", "mantrap")
	_door("mantrap_corr", "MANTRAP", Vector3(-0.5, 0, ROOM_Z1 + 0.1), true, "mantrap", "corridor")
	_door("dock_corr", "GOODS IN", Vector3(-6.0, 0, ROOM_Z1 + 0.1), true, "dock", "corridor")
	_door("security", "SECURITY DESK", Vector3(5.0, 0, ROOM_Z1 + 0.1), true, "security", "corridor")
	_door("mmr", "MEET-ME ROOM", Vector3(13.5, 0, ROOM_Z1 + 0.1), true, "mmr", "corridor")
	_door("ups", "UPS ROOM", Vector3(22.0, 0, ROOM_Z1 + 0.1), true, "ups", "corridor")
	_door("hall_a1", "HALL A-1", Vector3(-AISLE_PITCH, 0, -END_PAD - 0.1), true, "corridor", "hall_a")
	_door("hall_a2", "HALL A-2", Vector3(AISLE_PITCH, 0, -END_PAD - 0.1), true, "corridor", "hall_a")
	_door("hall_b1", "HALL B-1", Vector3(HALL_B_X - AISLE_PITCH, 0, -END_PAD - 0.1), true, "corridor", "hall_b")
	_door("hall_b2", "HALL B-2", Vector3(HALL_B_X + AISLE_PITCH, 0, -END_PAD - 0.1), true, "corridor", "hall_b")
	_door("chillers", "CHILLER PLANT", Vector3(30.0 + CH_DX, 0, -END_PAD - 0.1), true, "corridor", "chillers")


# ---------------------------------------------------------------- small rooms

func _plain(r: Room, mirror := 0.35) -> void:
	var p := r.rect.position
	var e := r.rect.end
	floor_piece(r, p.x, e.x, p.y, e.y, r.layers, 1000.0, mirror)
	box(r, Vector3((p.x + e.x) * 0.5, CEIL_Y + 0.1, (p.y + e.y) * 0.5), Vector3(e.x - p.x + 0.4, 0.2, e.y - p.y + 0.4), _ceil_mat)


func _build_small_rooms() -> void:
	var steel := mat(Color(0.2, 0.21, 0.23), 0.5, 0.4)
	var crate := mat(Color(0.36, 0.28, 0.17), 0.9)
	var grey := mat(Color(0.24, 0.25, 0.26), 0.7)

	# loading dock: where the night starts, and one way it can end
	var dock: Room = rooms["dock"]
	_plain(dock, 0.2)
	lamp(dock, -5.6, -9.0, 4.0, 8.0)
	var shutter := Node3D.new()
	dock.visual.add_child(shutter)
	props["shutter"] = shutter
	for i in 9:
		box_in(shutter, Vector3(-5.6, 0.2 + i * 0.3, -11.93), Vector3(3.6, 0.26, 0.08), steel, dock.layers)
	# what is behind it, for the one ending that gets it open
	props["dawn"] = box(dock, Vector3(-5.6, 1.35, -11.96), Vector3(3.6, 2.7, 0.02), glow_mat(Color(0.5, 0.62, 0.8), 2.4))
	(props["dawn"] as Node3D).visible = false
	props["dawn_light"] = omni(dock, Vector3(-5.6, 1.2, -10.9), Color(0.6, 0.72, 0.95), 0.0, 9.0, dock.layers)
	solid(Vector3(-5.6, 1.4, -11.95), Vector3(3.6, 2.8, 0.1))
	usable("dock_shutter", Vector3(-5.6, 1.3, -11.8), Vector3(3.6, 2.4, 0.3))
	block(dock, Vector3(-8.2, 0.5, -10.9), Vector3(1.2, 1.0, 1.2), crate)
	block(dock, Vector3(-8.3, 0.4, -9.4), Vector3(1.0, 0.8, 1.0), crate)
	block(dock, Vector3(-8.2, 1.3, -10.9), Vector3(0.8, 0.6, 0.8), crate)
	block(dock, Vector3(-3.3, 0.08, -7.2), Vector3(1.2, 0.16, 1.0), crate)
	sign_text(dock, "HALDEN DC-3\nGOODS IN", Vector3(-5.6, 3.0, -11.88), Basis(), 0.002)
	spots["dock"] = [Vector3(-6.2, 0.02, -9.0), -PI * 0.5]

	var trap: Room = rooms["mantrap"]
	_plain(trap, 0.5)
	lamp(trap, -0.5, -9.0, 6.0, 6.0)
	sign_text(trap, "ONE PERSON\nONE BADGE", Vector3(0.98, 1.9, -9.0), Basis(Vector3.UP, -PI * 0.5), 0.0016)

	# security desk: the hub. CCTV wall, the handheld, the returns bin.
	var sec: Room = rooms["security"]
	_plain(sec)
	lamp(sec, 5.0, -8.6, 4.0, 8.0)
	block(sec, Vector3(5.0, 0.4, -11.2), Vector3(3.4, 0.8, 0.9), grey)
	var screen := glow_mat(Color(0.25, 0.4, 0.34), 1.2)
	for i in 6:
		var sx := 4.2 + (i % 3) * 0.8
		var sy := 1.55 + int(i / 3) * 0.55
		prop(sec, Vector3(sx, sy, -11.93), Vector3(0.7, 0.46, 0.05), screen)
	usable("cctv", Vector3(5.0, 1.75, -11.7), Vector3(2.6, 1.3, 0.5))
	props["handheld"] = prop(sec, Vector3(3.8, 0.83, -11.0), Vector3(0.1, 0.03, 0.18), glow_mat(Color(0.5, 0.6, 0.7), 1.5))
	usable("handheld", Vector3(3.8, 0.9, -11.0), Vector3(0.5, 0.3, 0.5))
	block(sec, Vector3(7.9, 0.35, -11.3), Vector3(0.6, 0.7, 0.6), steel)
	sign_text(sec, "RETURNS", Vector3(7.9, 0.5, -10.99), Basis(), 0.0011)
	usable("desk_bin", Vector3(7.9, 0.6, -11.2), Vector3(0.8, 1.0, 0.8))
	block(sec, Vector3(1.6, 1.0, -9.0), Vector3(0.6, 2.0, 1.6), steel)
	prop(sec, Vector3(6.2, 0.815, -11.0), Vector3(0.22, 0.015, 0.3), mat(Color(0.72, 0.7, 0.62), 0.9))
	usable("handover", Vector3(6.2, 0.9, -11.0), Vector3(0.5, 0.3, 0.5))
	spots["desk"] = [Vector3(5.0, 0.02, -9.6), 0.0]

	# meet-me room: where every carrier's fibre lands
	var mmr: Room = rooms["mmr"]
	_plain(mmr)
	lamp(mmr, 13.5, -8.8, 4.0, 8.0)
	_rack_row(mmr, 11.0, -11.4, 6, 311.0)
	solid(Vector3(11.0 + 2.5 * RACK_W, RACK_H * 0.5, -11.4), Vector3(6 * RACK_W, RACK_H, RACK_D))
	var yellow := mat(Color(0.85, 0.58, 0.04), 0.5)
	box(mmr, Vector3(12.55, 2.7, -11.3), Vector3(4.2, 0.04, 0.5), steel)
	for i in 6:
		box(mmr, Vector3(11.0 + i * RACK_W, 2.42, -11.25), Vector3(0.05, 0.56, 0.05), yellow)
	sign_text(mmr, "PANEL 7", Vector3(11.0 + 4 * RACK_W, 2.2, -10.82), Basis(), 0.0011)
	usable("panel7", Vector3(11.0 + 4 * RACK_W, 1.2, -10.8), Vector3(0.6, 1.6, 0.3))
	props["note2"] = prop(mmr, Vector3(11.0 + 5 * RACK_W, 1.45, -10.83), Vector3(0.16, 0.22, 0.01), mat(Color(0.7, 0.68, 0.6), 0.9))
	usable("note2", Vector3(11.0 + 5 * RACK_W, 1.45, -10.8), Vector3(0.4, 0.5, 0.25))
	prop(mmr, Vector3(17.93, 1.3, -9.0), Vector3(0.06, 0.3, 0.2), mat(Color(0.5, 0.42, 0.08), 0.6))
	sign_text(mmr, "PLENUM DAMPER P-7", Vector3(17.9, 1.62, -9.0), Basis(Vector3.UP, -PI * 0.5), 0.0009)
	usable("damper", Vector3(17.8, 1.3, -9.0), Vector3(0.4, 0.6, 0.5))
	prop(mmr, Vector3(16.5, 0.012, -7.4), Vector3(0.6, 0.02, 0.6), mat(Color(0.42, 0.34, 0.06), 0.7))
	usable("hatch_mmr", Vector3(16.5, 0.15, -7.4), Vector3(0.7, 0.3, 0.7))
	spots["mmr_hatch"] = [Vector3(16.5, 0.02, -8.3), 0.0]

	# UPS room: batteries, breakers and relays
	var ups: Room = rooms["ups"]
	_plain(ups, 0.2)
	lamp(ups, 22.0, -8.8, 3.2, 8.0)
	var led := glow_mat(Color(0.1, 1.0, 0.35), 2.5)
	for i in 5:
		var bx := 19.2 + i * 1.3
		block(ups, Vector3(bx, 1.0, -11.5), Vector3(1.2, 2.0, 0.9), steel)
		prop(ups, Vector3(bx - 0.4, 1.7, -11.04), Vector3(0.04, 0.04, 0.02), led)
	box(ups, Vector3(25.93, 1.4, -9.0), Vector3(0.1, 1.5, 2.0), grey)
	sign_text(ups, "PANEL B\nB1  B2  B3  B4  B5  B6", Vector3(25.86, 1.85, -9.0), Basis(Vector3.UP, -PI * 0.5), 0.0011)
	props["breaker_led"] = prop(ups, Vector3(25.86, 1.35, -9.3), Vector3(0.02, 0.05, 0.05), glow_mat(AMBER, 3.0))
	usable("breaker_b2", Vector3(25.8, 1.4, -9.0), Vector3(0.4, 1.4, 1.8))
	prop(ups, Vector3(18.23, 1.4, -8.0), Vector3(0.02, 0.3, 0.22), mat(Color(0.72, 0.7, 0.62), 0.9))
	sign_text(ups, "BREAKER LOG", Vector3(18.26, 1.7, -8.0), Basis(Vector3.UP, PI * 0.5), 0.0009)
	usable("ups_log", Vector3(18.35, 1.4, -8.0), Vector3(0.3, 0.5, 0.4))


func _build_corridor() -> void:
	var r: Room = rooms["corridor"]
	var cz := (CORR_Z0 + CORR_Z1) * 0.5
	# floor and ceiling in three lengths, so no single mesh sits under every light
	var x0 := CORR_X0
	while x0 < CORR_X1:
		var x1 := minf(CORR_X1, x0 + 14.0)
		floor_piece(r, x0, x1, CORR_Z0 - 0.1, CORR_Z1 + 0.1, r.layers, 1000.0, 0.4)
		box(r, Vector3((x0 + x1) * 0.5, CEIL_Y + 0.1, cz), Vector3(x1 - x0, 0.2, 3.4), _ceil_mat)
		x0 = x1
	var x := CORR_X0 + 2.6
	while x < CORR_X1:
		lamp(r, x, cz, 3.6, 6.0, false)
		x += 5.4


# ---------------------------------------------------------------- data halls

## A row of rack bodies with lit fronts facing south, used outside the halls.
func _rack_row(r: Room, x0: float, z: float, count: int, seed: float) -> void:
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(RACK_W - 0.012, RACK_H, RACK_D)
	body_mesh.material = mat(Color(0.06, 0.06, 0.065), 0.55, 0.3)
	var bodies := MultiMesh.new()
	bodies.transform_format = MultiMesh.TRANSFORM_3D
	bodies.mesh = body_mesh
	bodies.instance_count = count
	var fm := ShaderMaterial.new()
	fm.shader = _front_shader
	fm.set_shader_parameter("seed", seed)
	var front_mesh := QuadMesh.new()
	front_mesh.size = Vector2(RACK_W, RACK_H)
	front_mesh.material = fm
	var fronts := MultiMesh.new()
	fronts.transform_format = MultiMesh.TRANSFORM_3D
	fronts.mesh = front_mesh
	fronts.instance_count = count
	for i in count:
		bodies.set_instance_transform(i, Transform3D(Basis(), Vector3(x0 + i * RACK_W, RACK_H * 0.5, z)))
		fronts.set_instance_transform(i, Transform3D(Basis(), Vector3(x0 + i * RACK_W, RACK_H * 0.5, z + RACK_D * 0.5 + 0.004)))
	for mm: MultiMesh in [bodies, fronts]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.layers = r.layers
		r.visual.add_child(mmi)


func _build_hall(id: String, ox: float, bit0: int, is_b: bool) -> void:
	var r: Room = rooms["hall_" + id]
	var all := 7 << bit0
	var shell := r.layers
	var racks: Array = []
	var strips: Array = []
	for a in AISLES:
		racks.append(RACKS)
		strips.append([])
	if is_b:
		racks[AISLES - 1] = RACKS - 12   # Cage 7 stands at the end of the last aisle
	var h := {
		"id": id, "ox": ox, "bit0": bit0, "all": all, "shell": shell, "b": is_b,
		"racks": racks, "fronts": [], "strips": strips, "cross": [], "bays": [],
		"strip_on": glow_mat(WARM if is_b else COOL, 2.2 if is_b else 4.0),
	}
	halls[id] = h
	var x_w := ox - HALL_WEST
	var x_e := ox + HALL_HALF_W

	# floor: a strip per aisle, cut into bays, each lit only by that aisle's lights
	for a in AISLES:
		var cx := ox + (a - MID) * AISLE_PITCH
		var x0 := x_w if a == 0 else cx - AISLE_PITCH * 0.5
		var x1 := x_e if a == AISLES - 1 else cx + AISLE_PITCH * 0.5
		floor_piece(r, x0, x1, -END_PAD, 0.0, all)
		floor_piece(r, x0, x1, AISLE_LEN, HALL_Z1, all)
	# the roof is a long way up and nothing lights it
	box(r, Vector3((x_w + x_e) * 0.5, HALL_CEIL + 0.1, AISLE_LEN * 0.5), Vector3(x_e - x_w + 0.4, 0.2, AISLE_LEN + END_PAD * 2.0 + 0.4), _void_mat, shell)
	# high-bay fittings on standby: pinpricks that show how far the roof goes
	var dot := QuadMesh.new()
	dot.size = Vector2(0.5, 0.12)
	dot.material = glow_mat(Color(0.2, 0.17, 0.12) if is_b else Color(0.14, 0.17, 0.22), 0.35)
	var dots: Array[Transform3D] = []
	var down := Basis(Vector3.RIGHT, PI * 0.5)
	for a in AISLES + 1:
		var z := 3.0
		while z < AISLE_LEN:
			dots.append(Transform3D(down, Vector3(ox + (a - MID - 0.5) * AISLE_PITCH, HALL_CEIL - 0.06, z)))
			z += 12.4
	var dm := MultiMesh.new()
	dm.transform_format = MultiMesh.TRANSFORM_3D
	dm.mesh = dot
	dm.instance_count = dots.size()
	for i in dots.size():
		dm.set_instance_transform(i, dots[i])
	var dmi := MultiMeshInstance3D.new()
	dmi.multimesh = dm
	dmi.layers = shell
	r.extra.add_child(dmi)

	# the emergency exit at the far end, and the green sign over it
	box(r, Vector3(ox, 1.05, HALL_Z1 - 0.02), Vector3(1.0, 2.1, 0.06), mat(Color(0.09, 0.095, 0.105), 0.5, 0.6), shell)
	box(r, Vector3(ox, 2.45, HALL_Z1 - 0.03), Vector3(0.48, 0.15, 0.04), glow_mat(Color(0.1, 1.0, 0.3), 3.0), all)
	var sl := omni(r, Vector3(ox, 2.4, HALL_Z1 - 0.4), Color(0.1, 1.0, 0.3), 0.5, 5.0, shell | all)
	props["exit_light_" + id] = sl

	for a in AISLES:
		_build_aisle(r, h, a)
	if is_b:
		_build_cage(r, h)
		prop(r, Vector3(ox, 1.3, -END_PAD + 0.06), Vector3(0.22, 0.3, 0.08), glow_mat(Color(0.9, 0.08, 0.05), 1.6), all)
		sign_text(r, "EPO · HALL B", Vector3(ox, 1.62, -END_PAD + 0.07), Basis(), 0.0011)
		usable("epo_b", Vector3(ox, 1.3, -END_PAD + 0.15), Vector3(0.5, 0.6, 0.3))
		var hx := ox - AISLE_PITCH
		props["hatch_b"] = prop(r, Vector3(hx, 0.012, AISLE_LEN + 1.3), Vector3(0.6, 0.02, 0.6), mat(Color(0.42, 0.34, 0.06), 0.7), all)
		usable("hatch_b", Vector3(hx, 0.15, AISLE_LEN + 1.3), Vector3(0.7, 0.3, 0.7))
		spots["hall_b_hatch"] = [Vector3(hx, 0.02, AISLE_LEN + 0.4), 0.0]
		_rack_usable("rack_b07", ox, -1.0, 6)
		# the rack the ticket is about shows an amber fault light, like any other fault
		props["b07_led"] = prop(r, Vector3(ox - FRONT_X + 0.02, 1.25, 6.5 * RACK_W), Vector3(0.02, 0.05, 0.05), glow_mat(AMBER, 5.0), all)
		props["b07_light"] = omni(r, Vector3(ox - FRONT_X + 0.3, 1.25, 6.5 * RACK_W), AMBER, 0.6, 2.4, all)
	else:
		prop(r, Vector3(2.0, 1.4, HALL_Z1 - 0.06), Vector3(0.5, 0.6, 0.08), glow_mat(Color(0.8, 0.1, 0.06), 1.0), all)
		sign_text(r, "FP-A", Vector3(2.0, 1.85, HALL_Z1 - 0.07), Basis(Vector3.UP, PI), 0.0013)
		usable("fire_panel_a", Vector3(2.0, 1.4, HALL_Z1 - 0.2), Vector3(0.7, 0.8, 0.3))
		props["fp_light"] = omni(r, Vector3(2.0, 1.5, HALL_Z1 - 0.5), Color(1.0, 0.15, 0.08), 0.7, 4.5, all | shell)
		prop(r, Vector3(0.0, 1.3, -END_PAD + 0.06), Vector3(0.24, 0.3, 0.08), glow_mat(Color(0.9, 0.7, 0.05), 1.4), all)
		sign_text(r, "GAS ABORT", Vector3(0.0, 1.62, -END_PAD + 0.07), Basis(), 0.0011)
		usable("abort_a", Vector3(0.0, 1.3, -END_PAD + 0.15), Vector3(0.5, 0.6, 0.3))
		_rack_usable("rack_a147", 0.0, -1.0, 7)
		props["fault_led"] = prop(r, Vector3(-FRONT_X + 0.02, 1.25, 7.5 * RACK_W), Vector3(0.02, 0.05, 0.05), glow_mat(AMBER, 5.0), all)
		var fl := omni(r, Vector3(-FRONT_X + 0.3, 1.25, 7.5 * RACK_W), AMBER, 0.5, 2.2, all)
		props["fault_light"] = fl


func _rack_usable(id: String, cx: float, side: float, i: int) -> void:
	usable(id, Vector3(cx + side * (FRONT_X - 0.05), 1.1, (i + 0.5) * RACK_W), Vector3(0.24, 1.7, RACK_W))


## The letter of the row on the west (-1) or east (+1) side of aisle `a`. O is skipped.
func row_letter(a: int, side: float) -> String:
	var n := a * 2 + (0 if side < 0.0 else 1)
	return "ABCDEFGHIJKLMN"[n]


func _mm(r: Room, mesh: Mesh, ts: Array[Transform3D], layers: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = ts.size()
	for i in ts.size():
		mm.set_instance_transform(i, ts[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.layers = layers
	(_into_v if _into_v else r.visual).add_child(mmi)


## One cold aisle: two facing rows of racks, the fibre overhead, and its strip lights.
func _build_aisle(r: Room, h: Dictionary, a: int) -> void:
	var is_b: bool = h["b"]
	var ox: float = h["ox"]
	var cx := ox + (a - MID) * AISLE_PITCH
	var layers := 1 << (int(h["bit0"]) + a % 3)
	var count: int = h["racks"][a]
	var length := count * RACK_W
	var z_mid := length * 0.5
	var story_aisle := absi(a - MID) <= 1

	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(RACK_D, RACK_H, RACK_W - 0.012)
	body_mesh.material = mat(Color(0.06, 0.06, 0.065), 0.55, 0.3)
	# rack fronts: one quad each, every LED drawn by the shader
	var front_mat := ShaderMaterial.new()
	front_mat.shader = _front_shader
	front_mat.set_shader_parameter("seed", float(a) * 97.0 + (500.0 if is_b else 0.0))
	front_mat.set_shader_parameter("bar", 1.0 if is_b else 0.0)
	h["fronts"].append(front_mat)
	var front_mesh := QuadMesh.new()
	front_mesh.size = Vector2(RACK_W, RACK_H)
	front_mesh.material = front_mat
	# a spool of fibre slack above every rack: yellow in Hall A, teal in Hall B
	var cable := mat(Color(0.05, 0.5, 0.45) if is_b else Color(0.85, 0.58, 0.04), 0.5)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.154
	torus.outer_radius = 0.226
	torus.rings = 12
	torus.ring_segments = 5
	torus.material = cable
	var upright := Basis(Vector3.FORWARD, PI * 0.5)
	var tray := mat(Color(0.1, 0.1, 0.11), 0.5, 0.5)

	var x_w := ox - HALL_WEST if a == 0 else cx - AISLE_PITCH * 0.5
	var x_e := ox + HALL_HALF_W if a == AISLES - 1 else cx + AISLE_PITCH * 0.5
	var bays: Array = []
	h["bays"].append(bays)
	var i0 := 0
	while i0 < RACKS:
		var i1 := mini(count, i0 + BAY)
		var bz0 := i0 * RACK_W
		var bay := {"v": Node3D.new(), "e": Node3D.new(), "m": null, "z0": bz0}
		r.visual.add_child(bay["v"])
		r.extra.add_child(bay["e"])
		bays.append(bay)
		_into_v = bay["v"]
		_into_e = bay["e"]
		floor_piece(r, x_w, x_e, bz0, bz0 + BAY * RACK_W, layers, cx)
		if i1 <= i0:
			i0 += BAY
			continue   # floor only: this is where Cage 7 stands
		var blen := (i1 - i0) * RACK_W
		var bmid := bz0 + blen * 0.5
		var bodies: Array[Transform3D] = []
		var fronts: Array[Transform3D] = []
		var spools: Array[Transform3D] = []
		for side: float in [-1.0, 1.0]:
			var facing := Basis(Vector3.UP, -side * PI * 0.5)   # quad normal points into the aisle
			for i in range(i0, i1):
				var z := (i + 0.5) * RACK_W
				bodies.append(Transform3D(Basis(), Vector3(cx + side * ROW_X, RACK_H * 0.5, z)))
				fronts.append(Transform3D(facing, Vector3(cx + side * (FRONT_X - 0.004), RACK_H * 0.5, z)))
				spools.append(Transform3D(upright, Vector3(cx + side * 1.305, 2.62, z)))
				if (story_aisle and i % 4 == 2) or (not story_aisle and i % 10 == 2) or (story_aisle and not is_b and i == 7):
					var letter := row_letter(a, side)
					var text := ("HALL B · ROW %s · %02d" % [letter, i + 1]) if is_b else ("HALL A · ROW %s · %d" % [letter, 140 + i])
					_rack_label(r, cx, side, z, text, layers)
			box(r, Vector3(cx + side * 2.05, 2.72, bmid), Vector3(1.4, 1.14, blen), _dark_mat, layers)
		_mm(r, body_mesh, bodies, layers)
		_mm(r, front_mesh, fronts, layers)
		_mm(r, torus, spools, layers)
		# cable tray down the middle, two runs of fibre on top of it
		box(r, Vector3(cx, 2.86, bmid), Vector3(0.6, 0.04, blen), tray, layers)
		for side: float in [-1.0, 1.0]:
			box(r, Vector3(cx + side * 0.13, 2.925, bmid), Vector3(0.09, 0.09, blen), cable, layers)
		i0 += BAY
	_into_v = null
	_into_e = null
	for side: float in [-1.0, 1.0]:
		solid(Vector3(cx + side * ROW_X, RACK_H * 0.5, z_mid), Vector3(RACK_D, RACK_H, length))

	# a dimmer fitting in each cross corridor, at the mouth of the aisle, and the row
	# letters hung over it where they can be read from the far side of the hall
	for z: float in [-END_PAD * 0.5, AISLE_LEN + END_PAD * 0.5]:
		if is_b and a == AISLES - 1 and z > 0.0:
			continue   # Cage 7 stands here
		var cl := omni(r, Vector3(cx, 2.9, z), TEAL if is_b else COOL, 0.7 if is_b else 1.6, 6.0, layers | int(h["shell"]))
		h["cross"].append(cl)
		var north := z < 0.0
		var sz := -0.1 if north else length + 0.1
		var out := -1.0 if north else 1.0
		var colour := Color(1.0, 0.75, 0.4) if is_b else Color(0.8, 0.88, 1.0)
		# a header over the mouth of the aisle, read from in front
		var words := "%s        %s" % [row_letter(a, 1.0), row_letter(a, -1.0)] if north else "%s        %s" % [row_letter(a, -1.0), row_letter(a, 1.0)]
		var sign := sign_text(r, words, Vector3(cx, 2.5, sz + out * 0.02), Basis(Vector3.UP, PI) if north else Basis(), 0.0058, colour)
		sign.layers = int(h["shell"])
		box(r, Vector3(cx, 2.5, sz), Vector3(2.2, 0.42, 0.03), _void_mat, int(h["shell"]))
		# and a blade on the end of each row, read from along the cross corridor
		for side: float in [-1.0, 1.0]:
			var bx := cx + side * ROW_X
			var bz := sz + out * 0.42
			box(r, Vector3(bx, 2.42, bz), Vector3(0.03, 0.5, 0.6), _void_mat, int(h["shell"]))
			for face: float in [-1.0, 1.0]:
				var blade := sign_text(r, row_letter(a, side), Vector3(bx + face * 0.02, 2.42, bz), Basis(Vector3.UP, face * PI * 0.5), 0.0075, colour)
				blade.layers = int(h["shell"])

	# strip lights. Only the ones near the eye cast real light: see light_strips().
	var haze_mat := ShaderMaterial.new()
	haze_mat.shader = _haze_shader
	if is_b:
		haze_mat.set_shader_parameter("colour", Vector3(1.0, 0.8, 0.58))
		haze_mat.set_shader_parameter("strength", 0.025)
	var strips := int(floor(length / STRIP_GAP)) + 1
	var z0 := (length - (strips - 1) * STRIP_GAP) * 0.5
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 3.2)
	for i in strips:
		var z := z0 + i * STRIP_GAP
		var sb: Dictionary = bays[clampi(int(z / (BAY * RACK_W)), 0, bays.size() - 1)]
		_into_v = sb["v"]
		_into_e = sb["e"]
		var mesh := box(r, Vector3(cx, 3.23, z), Vector3(1.6, 0.06, 0.14), h["strip_on"], layers)
		var light := omni(r, Vector3(cx, 3.0, z), WARM if is_b else COOL, 1.3 if is_b else 3.4, 7.5, layers)
		light.visible = false
		var haze := MeshInstance3D.new()
		haze.mesh = quad
		haze.material_override = haze_mat
		haze.position = Vector3(cx, 1.62, z)
		haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(_into_e if _into_e else r.extra).add_child(haze)
		h["strips"][a].append({"light": light, "mesh": mesh, "haze": haze, "z": z, "on": true, "full": 1.3 if is_b else 3.4})
	_into_v = null
	_into_e = null


## A hall has hundreds of strip lights and thousands of racks, and the renderer can
## afford a few dozen and a few hundred. So: rows that cannot be seen from where the eye
## is are not drawn (from inside an aisle, that is every other aisle), and real light is
## cast only by the strips near the eye, faded with distance so that none of them pops.
## `whole_mid` keeps the door-to-door aisles drawn for the security cameras.
func light_strips(eye: Vector3, delta: float, whole_mid := false) -> void:
	_lights_t -= delta
	if _lights_t > 0.0:
		return
	_lights_t = 0.1
	var bay_len := BAY * RACK_W
	for id: String in halls:
		var h: Dictionary = halls[id]
		var r: Room = rooms["hall_" + id]
		if not r.visual.visible:
			continue
		var inside := r.rect.has_point(Vector2(eye.x, eye.z))
		var above := eye.y > 3.4
		var at_end := eye.z < 1.5 or eye.z > AISLE_LEN - 1.5
		var deep := inside and eye.z > 2.2 and eye.z < AISLE_LEN - 2.2 and not above
		var near_bay := 0 if eye.z < AISLE_LEN * 0.5 else int(ceil(float(RACKS) / BAY)) - 1
		for a in AISLES:
			var dx := absf(eye.x - aisle_x(id, a))
			var bays: Array = h["bays"][a]
			for b in bays.size():
				var see := above or dx < 2.75 or (whole_mid and a == MID)
				if not see and not deep:
					see = b == near_bay   # from a cross corridor only the mouth of each aisle shows
				var bay: Dictionary = bays[b]
				if (bay["v"] as Node3D).visible != see:
					bay["v"].visible = see
					bay["e"].visible = see
					if bay["m"]:
						bay["m"].visible = see
			for s: Dictionary in h["strips"][a]:
				var k := 0.0
				if s["on"]:
					var dz := absf(eye.z - float(s["z"]))
					if dx < 2.8:
						k = clampf((36.0 - dz) / 6.0, 0.0, 1.0)
					k = maxf(k, clampf((16.0 - sqrt(dx * dx + dz * dz)) / 4.0, 0.0, 1.0))
					if at_end or above:
						k = maxf(k, clampf((9.5 - dz) / 2.0, 0.0, 1.0) * clampf((30.0 - dx) / 6.0, 0.0, 1.0))
				var l: OmniLight3D = s["light"]
				l.visible = k > 0.01
				l.light_energy = float(s["full"]) * k


func set_strip(hall: String, a: int, i: int, on: bool) -> void:
	var h: Dictionary = halls[hall]
	var s: Dictionary = h["strips"][a][i]
	if s["on"] == on:
		return
	s["on"] = on
	if not on:
		s["light"].visible = false
	s["haze"].visible = on
	_lights_t = 0.0
	_swap(rooms["hall_" + hall], s["mesh"], h["strip_on"] if on else _lamp_off)


func set_hall_lit(hall: String, on: bool) -> void:
	var h: Dictionary = halls[hall]
	for a in AISLES:
		for i in h["strips"][a].size():
			set_strip(hall, a, i, on)
	for l: OmniLight3D in h["cross"]:
		l.visible = on
	(rooms["hall_" + hall] as Room).lit = on


func set_hall_power(hall: String, power: float) -> void:
	for m: ShaderMaterial in halls[hall]["fronts"]:
		m.set_shader_parameter("power", power)
		m.set_shader_parameter("bar", power if halls[hall]["b"] else 0.0)
	(props["exit_light_" + hall] as Node3D).visible = power > 0.0


func set_pulse(z: float, gain: float) -> void:
	for m: ShaderMaterial in halls["b"]["fronts"]:
		m.set_shader_parameter("pulse_z", z)
		m.set_shader_parameter("pulse_gain", gain)


func _rack_label(r: Room, cx: float, side: float, z: float, text: String, layers: int) -> void:
	var facing := Basis(Vector3.UP, -side * PI * 0.5)
	var sticker := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.042)
	sticker.mesh = quad
	sticker.material_override = mat(Color(0.62, 0.62, 0.58), 0.9)
	sticker.layers = layers
	sticker.transform = Transform3D(facing, Vector3(cx + side * (FRONT_X - 0.008), 2.085, z))
	(_into_e if _into_e else r.extra).add_child(sticker)
	var label := Label3D.new()
	label.text = text
	label.font = _font
	label.font_size = 48
	label.pixel_size = 0.00042
	label.modulate = Color(0.05, 0.05, 0.05)
	label.outline_size = 0
	label.shaded = true
	label.layers = layers
	label.transform = Transform3D(facing, Vector3(cx + side * (FRONT_X - 0.011), 2.085, z))
	(_into_e if _into_e else r.extra).add_child(label)


## Cage 7: a wire cage in the far corner of Hall B, with no door on the hall side.
func _build_cage(r: Room, h: Dictionary) -> void:
	var ox: float = h["ox"]
	var x0 := ox + 3.2
	var x1 := ox + HALL_HALF_W
	var z0 := CAGE_Z0
	var z1 := HALL_Z1
	var gx := ox + AISLE_PITCH
	var layers := (1 << (int(h["bit0"]) + (AISLES - 1) % 3)) | int(h["shell"])
	var wire := ShaderMaterial.new()
	wire.shader = load("res://shaders/cage_mesh.gdshader")
	var post := mat(Color(0.09, 0.09, 0.1), 0.5, 0.6)
	# north face, either side of the panel that unbolts from inside
	var wl := gx - 0.55 - x0
	var wr := x1 - (gx + 0.55)
	prop(r, Vector3(x0 + wl * 0.5, CEIL_Y * 0.5, z0), Vector3(wl, CEIL_Y, 0.03), wire, layers)
	prop(r, Vector3(x1 - wr * 0.5, CEIL_Y * 0.5, z0), Vector3(wr, CEIL_Y, 0.03), wire, layers)
	prop(r, Vector3(gx, (2.1 + CEIL_Y) * 0.5, z0), Vector3(1.1, CEIL_Y - 2.1, 0.03), wire, layers)
	solid(Vector3(x0 + wl * 0.5, CEIL_Y * 0.5, z0), Vector3(wl, CEIL_Y, 0.1))
	solid(Vector3(x1 - wr * 0.5, CEIL_Y * 0.5, z0), Vector3(wr, CEIL_Y, 0.1))
	props["cage_gate"] = prop(r, Vector3(gx, 1.05, z0), Vector3(1.1, 2.1, 0.03), wire, layers)
	props["cage_gate_body"] = solid(Vector3(gx, 1.05, z0), Vector3(1.1, 2.1, 0.1))
	usable("cage_gate", Vector3(gx, 1.1, z0 + 0.25), Vector3(1.1, 1.8, 0.3))
	# west face
	prop(r, Vector3(x0, CEIL_Y * 0.5, (z0 + z1) * 0.5), Vector3(0.03, CEIL_Y, z1 - z0), wire, layers)
	solid(Vector3(x0, CEIL_Y * 0.5, (z0 + z1) * 0.5), Vector3(0.1, CEIL_Y, z1 - z0))
	for p: Vector3 in [Vector3(x0, 0, z0), Vector3(gx - 0.58, 0, z0), Vector3(gx + 0.58, 0, z0), Vector3(x0, 0, (z0 + z1) * 0.5)]:
		box(r, p + Vector3(0, CEIL_Y * 0.5, 0), Vector3(0.07, CEIL_Y, 0.07), post, layers)
	sign_text(r, "7", Vector3(gx - 1.4, 2.3, z0 - 0.03), Basis(Vector3.UP, PI), 0.003, Color(0.3, 0.32, 0.34))

	# six racks along the east wall, every light on them teal
	var fm := ShaderMaterial.new()
	fm.shader = _front_shader
	fm.set_shader_parameter("seed", 777.0)
	fm.set_shader_parameter("cage", 1.0)
	h["fronts"].append(fm)
	h["cage_front"] = fm
	var front_mesh := QuadMesh.new()
	front_mesh.size = Vector2(RACK_W, RACK_H)
	front_mesh.material = fm
	var fronts := MultiMesh.new()
	fronts.transform_format = MultiMesh.TRANSFORM_3D
	fronts.mesh = front_mesh
	fronts.instance_count = 8
	var facing := Basis(Vector3.UP, -PI * 0.5)
	for i in 8:
		fronts.set_instance_transform(i, Transform3D(facing, Vector3(x1 - RACK_D - 0.004, RACK_H * 0.5, z0 + 1.8 + i * RACK_W)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = fronts
	mmi.layers = layers
	r.visual.add_child(mmi)
	block(r, Vector3(x1 - RACK_D * 0.5, RACK_H * 0.5, z0 + 1.8 + 3.5 * RACK_W), Vector3(RACK_D, RACK_H, 8 * RACK_W), mat(Color(0.06, 0.06, 0.065), 0.55, 0.3), layers)
	# the console, and the chair in front of it
	var cz := CONSOLE_Z
	block(r, Vector3(x0 + 1.9, 0.45, cz), Vector3(0.7, 0.9, 1.3), mat(Color(0.1, 0.105, 0.115), 0.5, 0.5), layers)
	props["console_screen"] = prop(r, Vector3(x0 + 2.1, 1.2, cz), Vector3(0.05, 0.42, 0.62), glow_mat(TEAL * 0.5, 1.6), layers)
	box(r, Vector3(x0 + 2.9, 0.25, cz), Vector3(0.45, 0.5, 0.45), mat(Color(0.05, 0.05, 0.055), 0.8), layers)
	box(r, Vector3(x0 + 3.14, 0.75, cz), Vector3(0.06, 0.6, 0.42), mat(Color(0.05, 0.05, 0.055), 0.8), layers)
	usable("console7", Vector3(x0 + 2.2, 1.0, cz), Vector3(0.6, 1.2, 1.3))
	props["cage_light"] = omni(r, Vector3(x0 + 3.0, 2.6, cz + 0.3), TEAL, 2.6, 7.5, layers)
	prop(r, Vector3(x0 + 1.2, 0.012, z1 - 1.3), Vector3(0.6, 0.02, 0.6), mat(Color(0.42, 0.34, 0.06), 0.7), layers)
	usable("hatch_cage", Vector3(x0 + 1.2, 0.15, z1 - 1.3), Vector3(0.7, 0.3, 0.7))
	spots["cage"] = [Vector3(x0 + 1.2, 0.02, z1 - 2.2), 0.0]


func open_cage_gate() -> void:
	(props["cage_gate"] as Node3D).visible = false
	(props["cage_gate_body"] as StaticBody3D).process_mode = Node.PROCESS_MODE_DISABLED


func close_cage_gate() -> void:
	(props["cage_gate"] as Node3D).visible = true
	(props["cage_gate_body"] as StaticBody3D).process_mode = Node.PROCESS_MODE_INHERIT


func in_cage(p: Vector3) -> bool:
	return p.y > -5.0 and p.x > HALL_B_X + 3.2 and p.x < HALL_B_X + HALL_HALF_W and p.z > CAGE_Z0


# ---------------------------------------------------------------- plant

func _build_chillers() -> void:
	var r: Room = rooms["chillers"]
	var dx := CH_DX
	_plain(r, 0.15)
	lamp(r, 31.0 + dx, 0.5, 3.4, 8.5)
	lamp(r, 31.0 + dx, 6.5, 3.4, 8.5)
	var steel := mat(Color(0.22, 0.23, 0.25), 0.5, 0.4)
	var pipe := mat(Color(0.12, 0.24, 0.36), 0.5, 0.3)
	for i in 3:
		var z := 0.2 + i * 3.5
		block(r, Vector3(34.4 + dx, 1.2, z), Vector3(2.6, 2.4, 2.8), steel)
		prop(r, Vector3(33.08 + dx, 1.5, z - 0.9), Vector3(0.04, 0.3, 0.4), mat(Color(0.05, 0.05, 0.055), 0.5))
		var ok := i != 1
		var lm := prop(r, Vector3(33.06 + dx, 1.75, z - 0.9), Vector3(0.02, 0.05, 0.05), glow_mat(Color(0.1, 1.0, 0.35) if ok else AMBER, 3.0))
		if not ok:
			props["chiller_led"] = lm
		sign_text(r, "CH-%d" % (i + 1), Vector3(33.08 + dx, 2.1, z), Basis(Vector3.UP, -PI * 0.5), 0.002)
	for x: float in [29.0, 29.5]:
		box(r, Vector3(x + dx, 2.8, 3.7), Vector3(0.22, 0.22, 12.4), pipe)
	box(r, Vector3(32.0 + dx, 2.8, 8.9), Vector3(6.0, 0.22, 0.22), pipe)
	usable("chiller2", Vector3(33.0 + dx, 1.5, 2.8), Vector3(0.4, 0.9, 0.7))
	props["note1"] = prop(r, Vector3(33.08 + dx, 1.3, 4.4), Vector3(0.01, 0.22, 0.16), mat(Color(0.7, 0.68, 0.6), 0.9))
	usable("note1", Vector3(33.0 + dx, 1.3, 4.4), Vector3(0.3, 0.5, 0.4))
	spots["chillers"] = [Vector3(31.6 + dx, 0.02, 3.3), -PI * 0.5]


# ---------------------------------------------------------------- plenum

func cell_pos(c: int, row: int) -> Vector3:
	return Vector3(c * CELL, PLENUM_Y, PLENUM_Z + row * CELL)


func _cell(c: int, row: int) -> String:
	if row < 0 or row >= PLENUM_MAP.size() or c < 0 or c >= PLENUM_MAP[row].length():
		return "#"
	return PLENUM_MAP[row][c]


func _build_plenum() -> void:
	var r: Room = rooms["plenum"]
	var rows := PLENUM_MAP.size()
	var cols := PLENUM_MAP[0].length()
	var w := cols * CELL
	var d := rows * CELL
	var mid := Vector3((cols - 1) * CELL * 0.5, PLENUM_Y, PLENUM_Z + (rows - 1) * CELL * 0.5)
	var concrete := mat(Color(0.1, 0.1, 0.1), 0.95)
	box(r, mid + Vector3(0, -0.1, 0), Vector3(w, 0.2, d), concrete)
	solid(mid + Vector3(0, -0.1, 0), Vector3(w, 0.2, d))
	box(r, mid + Vector3(0, PLENUM_H + 0.1, 0), Vector3(w, 0.2, d), mat(Color(0.05, 0.05, 0.055), 0.7, 0.4))
	solid(mid + Vector3(0, PLENUM_H + 0.1, 0), Vector3(w, 0.2, d))

	var walls: Array[Vector3] = []
	var posts: Array[Vector3] = []
	var open: Array[Vector2i] = []
	var marks := {}
	for row in rows:
		for c in cols:
			var ch := _cell(c, row)
			var p := cell_pos(c, row)
			if ch == "#":
				walls.append(p)
				continue
			open.append(Vector2i(c, row))
			for dx: float in [-0.78, 0.78]:
				for dz: float in [-0.78, 0.78]:
					posts.append(p + Vector3(dx, 0, dz))
			if ch != ".":
				marks[ch] = Vector2i(c, row)
	# walls: one draw call, one collider per run of cells
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(CELL, PLENUM_H, CELL)
	wall_mesh.material = mat(Color(0.07, 0.07, 0.075), 0.9)
	_multi(r, wall_mesh, walls, Vector3(0, PLENUM_H * 0.5, 0))
	for row in rows:
		var c := 0
		while c < cols:
			if _cell(c, row) != "#":
				c += 1
				continue
			var c0 := c
			while c < cols and _cell(c, row) == "#":
				c += 1
			var p0 := cell_pos(c0, row)
			var p1 := cell_pos(c - 1, row)
			solid((p0 + p1) * 0.5 + Vector3(0, PLENUM_H * 0.5, 0), Vector3((c - c0) * CELL, PLENUM_H, CELL))
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.05, PLENUM_H, 0.05)
	post_mesh.material = mat(Color(0.2, 0.2, 0.21), 0.5, 0.7)
	_multi(r, post_mesh, posts, Vector3(0, PLENUM_H * 0.5, 0))

	# cable everywhere, and one fibre that is not on any schedule
	var runs: Array[Transform3D] = []
	for cell: Vector2i in open:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var nb: Vector2i = cell + step
			if _cell(nb.x, nb.y) == "#":
				continue
			var a := cell_pos(cell.x, cell.y)
			var b := cell_pos(nb.x, nb.y)
			var off := Vector3(0, 0.03, 0.45) if step.x == 1 else Vector3(-0.45, 0.03, 0)
			runs.append(Transform3D(Basis() if step.x == 1 else Basis(Vector3.UP, PI * 0.5), (a + b) * 0.5 + off))
	var run_mesh := BoxMesh.new()
	run_mesh.size = Vector3(CELL, 0.04, 0.04)
	run_mesh.material = mat(Color(0.5, 0.34, 0.03), 0.6)
	_multi_t(r, run_mesh, runs)
	fibre_mat = StandardMaterial3D.new()
	fibre_mat.albedo_color = Color(0.5, 0.34, 0.03)
	fibre_mat.roughness = 0.6
	fibre_mat.emission = Color(1.0, 0.25, 0.05)
	var path := _plenum_path(marks["M"], marks["C"])
	var fibre: Array[Transform3D] = []
	for i in path.size() - 1:
		var a := cell_pos(path[i].x, path[i].y)
		var b := cell_pos(path[i + 1].x, path[i + 1].y)
		fibre.append(Transform3D(Basis() if path[i].y == path[i + 1].y else Basis(Vector3.UP, PI * 0.5), (a + b) * 0.5 + Vector3(0, 0.035, 0)))
	var fibre_mesh := BoxMesh.new()
	fibre_mesh.size = Vector3(CELL + 0.04, 0.04, 0.04)
	fibre_mesh.material = fibre_mat
	_multi_t(r, fibre_mesh, fibre)

	# hatches: a square of light from the room above
	var ladder := mat(Color(0.3, 0.3, 0.32), 0.5, 0.6)
	for key: String in ["H", "M", "C"]:
		var mc: Vector2i = marks[key]
		var p := cell_pos(mc.x, mc.y)
		var colour: Color = {"H": WARM, "M": COOL, "C": TEAL}[key]
		box(r, p + Vector3(0, PLENUM_H - 0.01, 0), Vector3(0.6, 0.02, 0.6), glow_mat(colour * 0.5, 1.5))
		omni(r, p + Vector3(0, PLENUM_H - 0.25, 0), colour, 0.9, 3.5, r.layers)
		box(r, p + Vector3(0.36, PLENUM_H * 0.5, 0), Vector3(0.04, PLENUM_H, 0.4), ladder)
		var id: String = {"H": "hatch_h_up", "M": "hatch_m", "C": "hatch_c"}[key]
		usable(id, p + Vector3(0.36, 0.6, 0), Vector3(0.36, 1.2, 0.7))
		spots["plenum_" + key.to_lower()] = [p + Vector3(-0.2, 0.02, 0), -PI * 0.5]
	# the damper across the route to Cage 7
	var dc: Vector2i = marks["D"]
	var dp := cell_pos(dc.x, dc.y) + Vector3(0, PLENUM_H * 0.5, 0)
	props["damper"] = prop(r, dp, Vector3(0.12, PLENUM_H, CELL), mat(Color(0.16, 0.16, 0.17), 0.4, 0.8))
	props["damper_body"] = solid(dp, Vector3(0.12, PLENUM_H, CELL))
	# where the last technician stopped
	var nc: Vector2i = marks["N"]
	var np := cell_pos(nc.x, nc.y)
	props["note3"] = prop(r, np + Vector3(0.3, 0.02, 0.1), Vector3(0.09, 0.01, 0.06), mat(Color(0.75, 0.75, 0.72), 0.5))
	prop(r, np + Vector3(0.1, 0.03, -0.2), Vector3(0.16, 0.05, 0.05), mat(Color(0.12, 0.12, 0.13), 0.4, 0.5))
	usable("note3", np + Vector3(0.2, 0.2, 0), Vector3(0.9, 0.5, 0.9))


func set_damper(open: bool) -> void:
	(props["damper"] as Node3D).visible = not open
	(props["damper_body"] as StaticBody3D).process_mode = Node.PROCESS_MODE_DISABLED if open else Node.PROCESS_MODE_INHERIT


func set_fibre_lit(on: bool) -> void:
	fibre_mat.emission_enabled = on
	fibre_mat.emission_energy_multiplier = 3.0


func _plenum_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var prev := {from: from}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == to:
			break
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cur + step
			if _cell(nb.x, nb.y) != "#" and not prev.has(nb):
				prev[nb] = cur
				queue.append(nb)
	var path: Array[Vector2i] = [to]
	while path[0] != from:
		path.push_front(prev[path[0]])
	return path


func _multi(r: Room, mesh: Mesh, at: Array[Vector3], offset: Vector3) -> void:
	var ts: Array[Transform3D] = []
	for p in at:
		ts.append(Transform3D(Basis(), p + offset))
	_multi_t(r, mesh, ts)


func _multi_t(r: Room, mesh: Mesh, ts: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = ts.size()
	for i in ts.size():
		mm.set_instance_transform(i, ts[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.layers = r.layers
	r.visual.add_child(mmi)


# ---------------------------------------------------------------- reflections and visibility

## The Compatibility renderer has no screen-space reflections, so every floor is a real
## mirror: each room is drawn a second time upside down beneath a partly transparent floor.
func _finish_mirrors() -> void:
	for id: String in rooms:
		var r: Room = rooms[id]
		if id == "plenum":
			continue
		r.mirror = r.visual.duplicate()
		r.mirror.scale = Vector3(1, -1, 1)
		world.add_child(r.mirror)
	var shell_mirror := _shell.duplicate()
	shell_mirror.scale = Vector3(1, -1, 1)
	world.add_child(shell_mirror)
	for i in shared.size():
		shared[i]["m"] = shell_mirror.get_child(i)
	for id: String in halls:
		for bays: Array in halls[id]["bays"]:
			for bay: Dictionary in bays:
				bay["m"] = _twin(rooms["hall_" + id], bay["v"])


func room_at(p: Vector3) -> String:
	if p.y < -10.0:
		return "plenum"
	var q := Vector2(p.x, p.z)
	for id: String in rooms:
		if id != "plenum" and (rooms[id] as Room).rect.grow(0.12).has_point(q):
			return id
	return ""


## Show the room you are in, and whatever can be seen through open doors.
func show_rooms(current: String, everything := false) -> void:
	var seen := {current: true}
	if not everything:
		for pass_i in 2:
			for id: String in doors:
				var d: Node = doors[id]
				if d.open > 0.01:
					if seen.has(d.room_a):
						seen[d.room_b] = true
					elif seen.has(d.room_b):
						seen[d.room_a] = true
	for id: String in rooms:
		var r: Room = rooms[id]
		var on: bool = everything or seen.has(id)
		r.visual.visible = on
		r.extra.visible = on
		if r.mirror:
			r.mirror.visible = on
	for s: Dictionary in shared:
		var on: bool = everything or seen.has(s["a"]) or seen.has(s["b"])
		s["n"].visible = on
		s["m"].visible = on
	for id: String in doors:
		var d: Node = doors[id]
		d.visible = everything or seen.has(d.room_a) or seen.has(d.room_b)
