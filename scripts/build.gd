extends RefCounted
## The building: every room, wall, rack and prop of Halden DC-3, assembled in code from a
## small kit of parts. Nothing here knows about the story; it only builds and names things.
##
## Plan (x runs east, z runs south):
##   north row   dock | mantrap | security | meet-me room | UPS
##   corridor    one long corridor, a badge door to every room
##   south row   the data hall, Zone A | Zone B (with Cage 7 in its far corner) | chillers
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
const SOUTH_PAD := 6.0         # the open floor along the far wall
const HALL_Z1 := AISLE_LEN + SOUTH_PAD
const GAP0 := 38               # racks left out of every row, to make the cross aisle
const GAP1 := 42
const GAP_Z0 := GAP0 * RACK_W
const GAP_Z1 := (GAP1 + 1) * RACK_W
const HALL_B_X := HALL_HALF_W + HALL_WEST   # Zone B starts where Zone A stops: it is one hall
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

## '#' wall, '.' crawl space, H/M/C hatches (Zone B, meet-me room, Cage 7), D damper, N the last note.
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
	_room("hall_a", "DATA HALL · ZONE A", -HALL_WEST, HALL_HALF_W, -END_PAD, HALL_Z1, 3, "bed_hall_a")
	_room("hall_b", "DATA HALL · ZONE B", HALL_B_X - HALL_WEST, HALL_B_X + HALL_HALF_W, -END_PAD, HALL_Z1, 7, "bed_hall_b")
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
	_dress_corridor()
	_build_hall("a", 0.0, 0, false)
	_build_hall("b", HALL_B_X, 4, true)
	_build_chillers()
	_build_plenum()
	_build_cameras()
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


func floor_piece(r: Room, x0: float, x1: float, z0: float, z1: float, layers: int, aisle_cx := 1000.0, mirror := 0.6, lines: Array = [], blue := 10000.0) -> void:
	var m := ShaderMaterial.new()
	m.shader = _floor_shader
	var lz := [10000.0, 10000.0, 10000.0, 10000.0]
	for i in mini(4, lines.size()):
		lz[i] = lines[i]
	m.set_shader_parameter("line_z", Vector4(lz[0], lz[1], lz[2], lz[3]))
	m.set_shader_parameter("line_b", blue)
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
	_door("hall_a1", "ZONE A-1", Vector3(-AISLE_PITCH, 0, -END_PAD - 0.1), true, "corridor", "hall_a")
	_door("hall_a2", "ZONE A-2", Vector3(AISLE_PITCH, 0, -END_PAD - 0.1), true, "corridor", "hall_a")
	_door("hall_b1", "ZONE B-1", Vector3(HALL_B_X - AISLE_PITCH, 0, -END_PAD - 0.1), true, "corridor", "hall_b")
	_door("hall_b2", "ZONE B-2", Vector3(HALL_B_X + AISLE_PITCH, 0, -END_PAD - 0.1), true, "corridor", "hall_b")
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
	# the camera wall: six monitors on a frame, each showing a feed, and the desk that runs them
	var bezel := mat(Color(0.03, 0.03, 0.035), 0.4, 0.3)
	var mon_shader: Shader = load("res://shaders/monitor.gdshader")
	for i in 6:
		var sx := 4.2 + (i % 3) * 0.8
		var sy := 1.55 + int(i / 3) * 0.55
		prop(sec, Vector3(sx, sy, -11.9), Vector3(0.76, 0.5, 0.07), bezel)
		var sm := ShaderMaterial.new()
		sm.shader = mon_shader
		sm.set_shader_parameter("seed", float(i) * 1.37 + 0.5)
		var sq := QuadMesh.new()
		sq.size = Vector2(0.69, 0.43)
		var smi := MeshInstance3D.new()
		smi.mesh = sq
		smi.material_override = sm
		smi.position = Vector3(sx, sy, -11.862)
		smi.layers = sec.layers
		sec.extra.add_child(smi)
		prop(sec, Vector3(sx + 0.3, sy - 0.232, -11.86), Vector3(0.02, 0.012, 0.01), glow_mat(Color(0.1, 1.0, 0.35), 2.0))
	for sx: float in [3.8, 4.6, 5.4, 6.2]:
		prop(sec, Vector3(sx, 1.55, -11.95), Vector3(0.06, 1.5, 0.06), steel)
	prop(sec, Vector3(5.0, 1.27, -11.95), Vector3(2.5, 0.05, 0.05), steel)
	prop(sec, Vector3(5.0, 2.37, -11.95), Vector3(2.5, 0.05, 0.05), steel)
	omni(sec, Vector3(5.0, 1.7, -11.3), Color(0.55, 1.0, 0.8), 0.7, 3.5, sec.layers)
	prop(sec, Vector3(5.0, 0.815, -11.0), Vector3(0.46, 0.025, 0.16), bezel)
	prop(sec, Vector3(5.5, 0.83, -11.0), Vector3(0.2, 0.06, 0.2), bezel)
	prop(sec, Vector3(5.5, 0.92, -11.0), Vector3(0.03, 0.14, 0.03), steel)
	prop(sec, Vector3(6.2, 0.87, -11.3), Vector3(0.5, 0.13, 0.36), bezel)
	for k in 4:
		prop(sec, Vector3(6.02 + k * 0.05, 0.87, -11.115), Vector3(0.015, 0.015, 0.01), glow_mat(Color(0.1, 1.0, 0.35) if k != 2 else AMBER, 2.5))
	prop(sec, Vector3(4.35, 0.85, -11.05), Vector3(0.08, 0.1, 0.08), mat(Color(0.6, 0.6, 0.58), 0.6))
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
		floor_piece(r, x0, x1, CORR_Z0 - 0.1, CORR_Z1 + 0.1, r.layers, 1000.0, 0.4, [cz + 1.08], cz + 0.9)
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
		floor_piece(r, x0, x1, -END_PAD, 0.0, all, 1000.0, 0.6, [-0.32])
		floor_piece(r, x0, x1, AISLE_LEN, HALL_Z1, all, 1000.0, 0.6, [AISLE_LEN + 0.32, AISLE_LEN + 2.4, HALL_Z1 - 1.9])
	# the roof is a long way up and nothing lights it
	box(r, Vector3((x_w + x_e) * 0.5, HALL_CEIL + 0.1, (HALL_Z1 - END_PAD) * 0.5), Vector3(x_e - x_w + 0.4, 0.2, HALL_Z1 + END_PAD + 0.4), _void_mat, shell)
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
		sign_text(r, "EPO · ZONE B", Vector3(ox, 1.62, -END_PAD + 0.07), Basis(), 0.0011)
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
	# a spool of fibre slack above every rack: yellow in Zone A, teal in Zone B
	var cable := mat(Color(0.05, 0.5, 0.45) if is_b else Color(0.85, 0.58, 0.04), 0.5)
	var spout := BoxMesh.new()
	var race := mat(Color(0.03, 0.3, 0.27) if is_b else Color(0.5, 0.35, 0.03), 0.6)
	spout.size = Vector3(0.07, 0.24, 0.1)
	spout.material = race
	var upright := Basis(Vector3.FORWARD, PI * 0.5)
	var tray := mat(Color(0.1, 0.1, 0.11), 0.5, 0.5)

	var x_w := ox - HALL_WEST if a == 0 else cx - AISLE_PITCH * 0.5
	var x_e := ox + HALL_HALF_W if a == AISLES - 1 else cx + AISLE_PITCH * 0.5
	var bays: Array = []
	h["bays"].append(bays)
	var jig := RandomNumberGenerator.new()
	jig.seed = hash("jig %s %d" % [h["id"], a])
	var i0 := 0
	while i0 < RACKS:
		var i1 := mini(count, i0 + BAY)
		var bz0 := i0 * RACK_W
		var bay := {"v": Node3D.new(), "e": Node3D.new(), "d": Node3D.new(), "m": null, "z0": bz0}
		r.visual.add_child(bay["v"])
		r.extra.add_child(bay["e"])
		bay["e"].add_child(bay["d"])
		bays.append(bay)
		_into_v = bay["v"]
		_into_e = bay["e"]
		floor_piece(r, x_w, x_e, bz0, bz0 + BAY * RACK_W, layers, cx, 0.6, [GAP_Z0 + 0.32, GAP_Z1 - 0.32])
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
				if i >= GAP0 and i <= GAP1:
					continue
				var z := (i + 0.5) * RACK_W
				# nobody ever lines a row up exactly: racks sit a little back, a little askew
				var back := 0.0
				var skew := 0.0
				if not (story_aisle and i < 13):
					back = jig.randf() * 0.025
					skew = jig.randf_range(-0.014, 0.014)
				var turn := Basis(Vector3.UP, skew)
				bodies.append(Transform3D(turn, Vector3(cx + side * (ROW_X + back), RACK_H * 0.5, z)))
				fronts.append(Transform3D(turn * facing, Vector3(cx + side * (FRONT_X - 0.008 + back), RACK_H * 0.5, z)))
				if i % 4 == 1:
					spools.append(Transform3D(Basis(), Vector3(cx + side * 1.25, 2.26, z)))
				if (story_aisle and i % 4 == 2) or (not story_aisle and i % 10 == 2) or (story_aisle and not is_b and i == 7):
					var letter := row_letter(a, side)
					var text := ("ZONE B · ROW %s · %02d" % [letter, i + 1]) if is_b else ("ZONE A · ROW %s · %d" % [letter, 140 + i])
					_rack_label(r, cx, side, z, text, layers)
			var s0 := bz0
			var s1 := bz0 + blen
			if i0 <= GAP1 and i1 > GAP0:
				if i0 < GAP0:
					s1 = GAP_Z0
				else:
					s0 = minf(GAP_Z1, s1)
			if s1 - s0 > 0.05:
				box(r, Vector3(cx + side * 1.27, 2.42, (s0 + s1) * 0.5), Vector3(0.16, 0.11, s1 - s0), race, layers)
				box(r, Vector3(cx + side * 2.05, 2.72, (s0 + s1) * 0.5), Vector3(1.4, 1.14, s1 - s0), _dark_mat, layers)
		_mm(r, body_mesh, bodies, layers)
		_mm(r, front_mesh, fronts, layers)
		_mm(r, spout, spools, layers)
		# cable tray down the middle, two runs of fibre on top of it
		box(r, Vector3(cx, 2.86, bmid), Vector3(0.6, 0.04, blen), tray, layers)
		box(r, Vector3(cx, 2.93, bmid), Vector3(0.3, 0.1, blen), cable, layers)
		_dress_bay(r, h, a, bay, i0, i1, x_w, x_e)
		i0 += BAY
	_into_v = null
	_into_e = null
	for side: float in [-1.0, 1.0]:
		solid(Vector3(cx + side * ROW_X, RACK_H * 0.5, GAP_Z0 * 0.5), Vector3(RACK_D, RACK_H, GAP_Z0))
		solid(Vector3(cx + side * ROW_X, RACK_H * 0.5, (GAP_Z1 + length) * 0.5), Vector3(RACK_D, RACK_H, length - GAP_Z1))

	# a dimmer fitting in each cross corridor, at the mouth of the aisle, and the row
	# letters hung over it where they can be read from the far side of the hall
	for z: float in [-END_PAD * 0.5, AISLE_LEN + END_PAD * 0.5, AISLE_LEN + 4.2]:
		if is_b and a == AISLES - 1 and z > 0.0:
			continue   # Cage 7 stands here
		var cl := omni(r, Vector3(cx, 2.9, z), TEAL if is_b else COOL, 1.0 if is_b else 1.6, 6.0, layers | int(h["shell"]))
		h["cross"].append(cl)
		if z > AISLE_LEN + 2.0:
			cl.omni_range = 7.5
			cl.light_energy *= 1.5
			continue
		var north := z < 0.0
		var sz := -0.1 if north else length + 0.1
		var out := -1.0 if north else 1.0
		var colour := Color(1.0, 0.75, 0.4) if is_b else Color(0.8, 0.88, 1.0)
		# a header over the mouth of the aisle, read from in front
		var words := "%s        %s" % [row_letter(a, 1.0), row_letter(a, -1.0)] if north else "%s        %s" % [row_letter(a, -1.0), row_letter(a, 1.0)]
		var sign := sign_text(r, words, Vector3(cx, 2.5, sz + out * 0.02), Basis(Vector3.UP, PI) if north else Basis(), 0.0058, colour)
		sign.layers = int(h["shell"])
		var board := box(r, Vector3(cx, 2.5, sz), Vector3(2.2, 0.42, 0.03), _void_mat, int(h["shell"]))
		if jig.randf() < 0.3:
			# hung a little off level
			var off := jig.randf_range(-0.05, 0.05)
			sign.rotate_object_local(Vector3.BACK, off)
			board.rotation.z = off if not north else -off
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
		var strip := {"light": light, "mesh": mesh, "haze": haze, "z": z, "on": true, "full": (1.3 if is_b else 3.4) * (0.7 + 0.3 * jig.randf())}
		# tubes fail and nobody has got to them yet; one or two hang from a single chain
		if jig.randf() < 0.09 and not (story_aisle and z < 12.0):
			strip["dead"] = true
			strip["on"] = false
			mesh.material_override = _lamp_off
			haze.visible = false
		if jig.randf() < 0.05:
			mesh.rotation.z = jig.randf_range(-0.16, 0.16)
			mesh.position.y -= 0.07
		h["strips"][a].append(strip)
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
	var eye2 := Vector2(eye.x, eye.z)
	var inside: bool = (rooms["hall_a"] as Room).rect.has_point(eye2) or (rooms["hall_b"] as Room).rect.has_point(eye2)
	# standing in the spine or against an outer wall, the nearest rows are still drawn
	var reach := 100.0
	for id: String in halls:
		for a in AISLES:
			reach = minf(reach, absf(eye.x - aisle_x(id, a)))
	reach = 2.75 if reach < 2.75 else reach + 0.4
	for id: String in halls:
		var h: Dictionary = halls[id]
		var r: Room = rooms["hall_" + id]
		if not r.visual.visible:
			continue
		var above := eye.y > 3.4
		var near_gap := absf(eye.z - (GAP_Z0 + GAP_Z1) * 0.5) < 4.0
		var at_end := eye.z < 1.5 or eye.z > AISLE_LEN - 1.5 or near_gap
		var deep := inside and eye.z > 2.2 and eye.z < AISLE_LEN - 2.2 and not above and not near_gap
		var near_bay := 0 if eye.z < AISLE_LEN * 0.5 else int(ceil(float(RACKS) / BAY)) - 1
		for a in AISLES:
			var dx := absf(eye.x - aisle_x(id, a))
			var bays: Array = h["bays"][a]
			for b in bays.size():
				var see := above or dx < reach or (whole_mid and a == MID)
				if not see and near_gap and not above:
					see = b == 1 or b == 2   # from the cross aisle, the rows either side of it
				elif not see and not deep:
					see = b == near_bay   # from a cross corridor only the mouth of each aisle shows
				var bay: Dictionary = bays[b]
				(bay["d"] as Node3D).visible = dx < reach or (above and dx < 9.0)
				if (bay["v"] as Node3D).visible != see:
					bay["v"].visible = see
					bay["e"].visible = see
					if bay["m"]:
						bay["m"].visible = see
			for s: Dictionary in h["strips"][a]:
				var k := 0.0
				if s["on"]:
					var dz := absf(eye.z - float(s["z"]))
					if dx < reach + 0.05:
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
	if s["on"] == on or s.has("dead"):
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
	quad.size = Vector2(0.27, 0.046)
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


## Cage 7: a wire cage in the far corner of Zone B, with no door on the hall side.
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
	for x: float in [28.25, 28.7]:
		box(r, Vector3(x + dx, 2.8, 3.7), Vector3(0.22, 0.22, 12.4), pipe)
	box(r, Vector3(31.6 + dx, 2.8, 8.9), Vector3(6.8, 0.22, 0.22), pipe)
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
	# it can also be let go from here, so the lit fibre never ends at a shut door
	props["damper_pull"] = prop(r, dp + Vector3(-0.09, 0.0, 0.5), Vector3(0.06, 0.22, 0.1), glow_mat(AMBER, 2.5))
	props["damper_glow"] = omni(r, dp + Vector3(-0.5, 0.0, 0.3), AMBER, 0.7, 3.0, r.layers)
	usable("damper_pull", dp + Vector3(-0.15, -0.05, 0.0), Vector3(0.4, 1.0, CELL - 0.2))
	# where the last technician stopped
	var nc: Vector2i = marks["N"]
	var np := cell_pos(nc.x, nc.y)
	props["note3"] = prop(r, np + Vector3(0.3, 0.02, 0.1), Vector3(0.09, 0.01, 0.06), mat(Color(0.75, 0.75, 0.72), 0.5))
	prop(r, np + Vector3(0.1, 0.03, -0.2), Vector3(0.16, 0.05, 0.05), mat(Color(0.12, 0.12, 0.13), 0.4, 0.5))
	usable("note3", np + Vector3(0.2, 0.2, 0), Vector3(0.9, 0.5, 0.9))


func set_damper(open: bool) -> void:
	(props["damper"] as Node3D).visible = not open
	(props["damper_pull"] as Node3D).visible = not open
	(props["damper_glow"] as Node3D).visible = not open
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
	if current.begins_with("hall_"):
		seen["hall_a"] = true
		seen["hall_b"] = true
	if not everything:
		for pass_i in 2:
			for id: String in doors:
				var d: Node = doors[id]
				if d.open > 0.01:
					if seen.has(d.room_a):
						seen[d.room_b] = true
					elif seen.has(d.room_b):
						seen[d.room_a] = true
			if seen.has("hall_a") or seen.has("hall_b"):
				seen["hall_a"] = true
				seen["hall_b"] = true
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


# ---------------------------------------------------------------- set dressing

## Everything below is furniture: the things a working building collects. Boxes of one
## material in one place are drawn together, so a bay of clutter costs a handful of draws.
var _dm := {}


func _m(id: String) -> Material:
	if _dm.is_empty():
		_dm = {
			"steel": mat(Color(0.3, 0.31, 0.33), 0.45, 0.6),
			"duct": mat(Color(0.34, 0.35, 0.36), 0.5, 0.55),
			"panel": mat(Color(0.15, 0.155, 0.165), 0.5, 0.4),
			"dark": mat(Color(0.05, 0.05, 0.055), 0.7, 0.2),
			"concrete": mat(Color(0.2, 0.2, 0.2), 0.95),
			"card": mat(Color(0.42, 0.31, 0.18), 0.95),
			"wood": mat(Color(0.36, 0.27, 0.16), 0.9),
			"yellow": mat(Color(0.75, 0.58, 0.06), 0.7),
			"line": mat(Color(0.5, 0.4, 0.06), 0.8),
			"orange": mat(Color(0.85, 0.3, 0.05), 0.7),
			"red": mat(Color(0.6, 0.06, 0.04), 0.5, 0.2),
			"blue": mat(Color(0.08, 0.2, 0.42), 0.5, 0.3),
			"pipe_r": mat(Color(0.42, 0.14, 0.08), 0.5, 0.3),
			"green": mat(Color(0.06, 0.38, 0.16), 0.6),
			"white": mat(Color(0.62, 0.62, 0.6), 0.8),
			"alu": mat(Color(0.5, 0.51, 0.52), 0.35, 0.8),
			"tote": mat(Color(0.1, 0.24, 0.4), 0.6),
			"cable": mat(Color(0.85, 0.58, 0.04), 0.5),
			"wrap": mat(Color(0.26, 0.27, 0.28), 0.25, 0.1),
			"screen": glow_mat(Color(0.12, 0.42, 0.5), 1.3),
			"led_g": glow_mat(Color(0.1, 1.0, 0.35), 3.0),
			"led_a": glow_mat(AMBER, 3.0),
			"vend": glow_mat(Color(0.55, 0.78, 1.0), 1.5),
			"void": _void_mat,
		}
	return _dm[id]


func _q(batch: Dictionary, id: String, pos: Vector3, size: Vector3, turn := Basis()) -> void:
	var m := _m(id)
	if not batch.has(m):
		batch[m] = []
	(batch[m] as Array).append(Transform3D(turn * Basis.from_scale(size), pos))


func _flush(batch: Dictionary, parent: Node3D, layers: int, round := false) -> void:
	for m: Material in batch:
		var mesh: Mesh
		if round:
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			c.radial_segments = 10
			c.rings = 1
			c.material = m
			mesh = c
		else:
			var bx := BoxMesh.new()
			bx.material = m
			mesh = bx
		var ts: Array = batch[m]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = ts.size()
		for i in ts.size():
			mm.set_instance_transform(i, ts[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.layers = layers
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
	batch.clear()


func _dress_bay(r: Room, h: Dictionary, a: int, bay: Dictionary, i0: int, i1: int, x_w: float, x_e: float) -> void:
	var is_b: bool = h["b"]
	var ox: float = h["ox"]
	var zone := "B" if is_b else "A"
	var cx := ox + (a - MID) * AISLE_PITCH
	var layers := 1 << (int(h["bit0"]) + a % 3)
	var shell := int(h["shell"])
	var count: int = h["racks"][a]
	var bz0 := i0 * RACK_W
	var bz1 := i1 * RACK_W
	var bmid := (bz0 + bz1) * 0.5
	var b := i0 / BAY
	var story_aisle := absi(a - MID) <= 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s %d %d" % [zone, a, b])
	var e := {}      # seen with the bay
	var d := {}      # small things, seen only from this aisle
	var round := {}
	var west_wall := a == 0 and not is_b
	var east_wall := a == AISLES - 1 and is_b
	var hot_door := a < AISLES - 1   # the hot aisle east of this row is shut in behind doors

	# services overhead: a duct across the hall, chilled water along the aisle
	_q(e, "duct", Vector3((x_w + x_e) * 0.5, 4.3, bz0 + 4.0), Vector3(x_e - x_w, 0.5, 0.8))
	_q(e, "yellow", Vector3((x_w + x_e) * 0.5, 3.74, bz0 + 9.6), Vector3(x_e - x_w, 0.16, 0.32))
	_q(e, "blue", Vector3(cx - 0.74, 3.6, bmid), Vector3(0.2, 0.2, bz1 - bz0))
	_q(e, "pipe_r", Vector3(cx + 0.74, 3.6, bmid), Vector3(0.2, 0.2, bz1 - bz0))

	# the ends of the rows: a power panel on each, and a door across each hot aisle
	var ends: Array = []
	if i0 == 0:
		ends.append([-0.03, -1.0])
	if i1 == count:
		ends.append([bz1 + 0.03, 1.0])
	if i0 < GAP0 and i1 > GAP0:
		ends.append([GAP_Z0 + 0.03, 1.0])
	if i0 <= GAP1 and i1 > GAP1 + 1 and i0 > GAP0 - BAY:
		ends.append([GAP_Z1 - 0.03, -1.0])
	for end: Array in ends:
		var ez: float = end[0]
		var out: float = end[1]
		for side: float in [-1.0, 1.0]:
			var rx := cx + side * ROW_X
			_q(e, "panel", Vector3(rx, RACK_H * 0.5, ez), Vector3(RACK_D - 0.03, RACK_H - 0.02, 0.04))
			_q(e, "steel", Vector3(rx - 0.18, 1.3, ez + out * 0.05), Vector3(0.42, 0.62, 0.07))
			_q(e, "led_g" if rng.randf() < 0.85 else "led_a", Vector3(rx - 0.18, 1.52, ez + out * 0.09), Vector3(0.03, 0.03, 0.01))
			_q(e, "red", Vector3(rx + 0.3, 0.42, ez + out * 0.1), Vector3(0.12, 0.42, 0.12))
		if hot_door:
			var hx := cx + AISLE_PITCH * 0.5
			_q(e, "steel", Vector3(hx, 1.2, ez - out * 0.2), Vector3(1.0, 2.4, 0.05))
			_q(e, "line", Vector3(hx, 1.45, ez - out * 0.17), Vector3(0.96, 0.1, 0.02))
			_q(e, "dark", Vector3(hx, 1.75, ez - out * 0.17), Vector3(0.3, 0.3, 0.02))
			solid(Vector3(hx, 1.2, ez - out * 0.2), Vector3(1.0, 2.4, 0.1))
		# a painted line where the aisle meets the cross corridor

	# cooling units along the outer walls
	if west_wall or east_wall:
		var wx := x_w + 0.42 if west_wall else x_e - 0.42
		var face := 1.0 if west_wall else -1.0
		h["cross"].append(omni(r, Vector3(wx + face * 0.6, 2.6, bmid), TEAL if is_b else COOL, 1.0, 6.5, layers | shell))
		for k in 2:
			var uz := bz0 + 3.1 + k * 6.2
			if uz > bz1 - 1.3:
				continue
			_q(e, "steel", Vector3(wx, 1.05, uz), Vector3(0.8, 2.1, 2.3))
			_q(e, "dark", Vector3(wx + face * 0.405, 0.6, uz), Vector3(0.02, 0.8, 1.9))
			_q(e, "screen", Vector3(wx + face * 0.405, 1.6, uz - 0.7), Vector3(0.02, 0.12, 0.2))
			_q(e, "led_g", Vector3(wx + face * 0.405, 1.6, uz - 0.45), Vector3(0.02, 0.03, 0.03))
			_q(e, "blue", Vector3(wx, 3.2, uz + 0.6), Vector3(0.16, 2.2, 0.16))
			_q(e, "pipe_r", Vector3(wx, 3.2, uz + 0.9), Vector3(0.16, 2.2, 0.16))
			solid(Vector3(wx, 1.05, uz), Vector3(0.8, 2.1, 2.3))
			sign_text(r, "CRAH %s-%02d" % [zone, b * 2 + k + 1], Vector3(wx + face * 0.41, 1.85, uz), Basis(Vector3.UP, face * PI * 0.5), 0.0016)
	# columns down the spine between the two zones
	if a == AISLES - 1 and not is_b:
		var col := {}
		_q(col, "concrete", Vector3(x_e, HALL_CEIL * 0.5, bmid), Vector3(0.55, HALL_CEIL, 0.55))
		_q(col, "yellow", Vector3(x_e, 0.5, bmid), Vector3(0.6, 1.0, 0.6))
		_q(col, "dark", Vector3(x_e, 0.5, bmid), Vector3(0.61, 0.18, 0.61))
		_q(col, "red", Vector3(x_e - 0.34, 1.35, bmid), Vector3(0.12, 0.42, 0.12))
		solid(Vector3(x_e, 1.5, bmid), Vector3(0.6, 3.0, 0.6))
		_flush(col, bay["e"], layers | (1 << 4) | shell)
		h["cross"].append(omni(r, Vector3(x_e, 2.7, bmid + 1.2), COOL, 1.3, 6.5, layers | (1 << 4) | shell))

	# the corridor wall at the near end
	if i0 == 0:
		var wz := -END_PAD + 0.02
		var px := cx + AISLE_PITCH * 0.5
		if hot_door:
			_q(e, "concrete", Vector3(px, HALL_CEIL * 0.5, wz + 0.12), Vector3(0.42, HALL_CEIL, 0.24))
			_q(e, "line", Vector3(px, 0.6, wz + 0.25), Vector3(0.44, 1.2, 0.02))
		var ix := cx + AISLE_PITCH * 0.5 - 0.75
		match a % 4:
			0:
				_q(e, "red", Vector3(ix, 0.95, wz + 0.1), Vector3(0.15, 0.5, 0.15))
				_q(e, "red", Vector3(ix, 1.6, wz + 0.02), Vector3(0.22, 0.22, 0.02))
			1:
				_q(e, "green", Vector3(ix, 1.45, wz + 0.06), Vector3(0.34, 0.34, 0.12))
				_q(e, "white", Vector3(ix, 1.45, wz + 0.125), Vector3(0.2, 0.06, 0.01))
				_q(e, "white", Vector3(ix, 1.45, wz + 0.125), Vector3(0.06, 0.2, 0.01))
			2:
				_q(e, "white", Vector3(ix, 1.55, wz + 0.02), Vector3(0.9, 0.5, 0.02))
				sign_text(r, "NO FOOD OR DRINK\nNO LONE WORKING", Vector3(ix, 1.55, wz + 0.06), Basis(), 0.0015, Color(0.08, 0.08, 0.09))
			3:
				_q(e, "dark", Vector3(ix, 1.4, wz + 0.05), Vector3(0.2, 0.32, 0.1))
				_q(e, "steel", Vector3(ix, 1.75, wz + 0.02), Vector3(0.3, 0.12, 0.02))
				sign_text(r, "OPS 2001", Vector3(ix, 1.75, wz + 0.06), Basis(), 0.0011, Color(0.05, 0.05, 0.05))
		if a == MID:
			var big := sign_text(r, "ZONE %s" % zone, Vector3(ox - 2.2, 2.6, wz + 0.02), Basis(), 0.006, Color(0.3, 0.32, 0.35))
			big.layers = shell

	# the open floor along the far wall: stores, spares, the gas for the fire system
	if i0 + BAY >= RACKS:
		var sz := HALL_Z1
		if hot_door:
			_q(e, "concrete", Vector3(cx + AISLE_PITCH * 0.5, HALL_CEIL * 0.5, sz - 0.15), Vector3(0.45, HALL_CEIL, 0.3))
		if a != MID and not east_wall:
			var kind := (a + (2 if is_b else 0)) % 5
			var fz := sz - 0.85
			# a bay marked out on the floor
			match kind:
				0:
					for k in 7:
						_q(round, "red", Vector3(cx + (k - 3.0) * 0.32, 0.8, sz - 0.3), Vector3(0.25, 1.6, 0.25))
						_q(round, "steel", Vector3(cx + (k - 3.0) * 0.32, 1.66, sz - 0.3), Vector3(0.07, 0.14, 0.07))
					_q(e, "steel", Vector3(cx, 1.78, sz - 0.3), Vector3(2.3, 0.06, 0.06))
					_q(e, "steel", Vector3(cx, 1.1, sz - 0.46), Vector3(2.4, 0.05, 0.04))
					_q(e, "steel", Vector3(cx + 1.15, 2.6, sz - 0.3), Vector3(0.06, 1.7, 0.06))
					sign_text(r, "IG-541 · DO NOT ISOLATE", Vector3(cx, 2.1, sz - 0.02), Basis(Vector3.UP, PI), 0.0016)
					solid(Vector3(cx, 0.9, sz - 0.3), Vector3(2.4, 1.8, 0.5))
				1:
					for k in 2:
						var px2 := cx - 0.75 + k * 1.5
						_q(e, "wood", Vector3(px2, 0.07, fz), Vector3(1.2, 0.14, 1.0))
						for j in 4:
							_q(e, "card", Vector3(px2 - 0.29 + (j % 2) * 0.58, 0.4 + (j / 2) * 0.5, fz), Vector3(0.55, 0.48, 0.8))
						if k == 0:
							_q(e, "wrap", Vector3(px2, 0.66, fz), Vector3(1.18, 1.02, 0.84))
					solid(Vector3(cx, 0.6, fz), Vector3(2.7, 1.2, 1.0))
				2:
					for k in 3:
						_q(e, "wrap", Vector3(cx - 0.9 + k * 0.66, RACK_H * 0.5, sz - 0.6), Vector3(0.62, RACK_H, 1.0))
					_q(round, "wood", Vector3(cx + 1.15, 0.45, sz - 0.5), Vector3(0.9, 0.5, 0.9), Basis(Vector3.RIGHT, PI * 0.5))
					_q(round, "cable", Vector3(cx + 1.15, 0.45, sz - 0.5), Vector3(0.6, 0.42, 0.6), Basis(Vector3.RIGHT, PI * 0.5))
					solid(Vector3(cx, 1.0, sz - 0.6), Vector3(2.9, 2.0, 1.0))
				3:
					_q(e, "wood", Vector3(cx, 0.9, sz - 0.42), Vector3(2.0, 0.05, 0.75))
					for sx: float in [-1.0, 1.0]:
						_q(e, "steel", Vector3(cx + sx * 0.92, 0.44, sz - 0.42), Vector3(0.05, 0.88, 0.7))
					_q(e, "dark", Vector3(cx - 0.4, 1.2, sz - 0.2), Vector3(0.55, 0.36, 0.05))
					_q(e, "screen", Vector3(cx - 0.4, 1.2, sz - 0.23), Vector3(0.5, 0.31, 0.01))
					_q(e, "red", Vector3(cx + 0.55, 1.03, sz - 0.4), Vector3(0.5, 0.22, 0.26))
					_q(e, "dark", Vector3(cx + 0.1, 0.3, sz - 1.15), Vector3(0.36, 0.6, 0.36))
					_q(e, "white", Vector3(cx + 0.2, 2.0, sz - 0.03), Vector3(1.5, 0.9, 0.02))
					solid(Vector3(cx, 0.6, sz - 0.42), Vector3(2.0, 1.2, 0.75))
				4:
					for k in 6:
						_q(e, "panel", Vector3(cx - 0.8, 0.02 + k * 0.045, fz), Vector3(0.6, 0.04, 0.6), Basis(Vector3.UP, (k % 3) * 0.05))
					_q(e, "tote", Vector3(cx + 0.1, 0.2, fz), Vector3(0.45, 0.4, 0.65))
					_q(e, "tote", Vector3(cx + 0.1, 0.61, fz), Vector3(0.45, 0.4, 0.65), Basis(Vector3.UP, 0.12))
					_q(e, "alu", Vector3(cx + 1.0, 1.6, sz - 0.4), Vector3(0.45, 3.3, 0.05), Basis(Vector3.RIGHT, -0.2))
					_q(e, "alu", Vector3(cx + 0.9, 1.3, sz - 0.5), Vector3(0.4, 2.7, 0.05), Basis(Vector3.RIGHT, -0.24))
					solid(Vector3(cx + 0.1, 0.5, fz), Vector3(2.4, 1.0, 0.9))

	# what gets left in an aisle on a night shift
	var n := 2 + rng.randi() % 2
	for k in n:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var i := rng.randi_range(i0 + 1, maxi(i0 + 1, i1 - 2))
		var kind := rng.randi() % 8
		if i >= GAP0 - 2 and i <= GAP1 + 2:
			continue
		if story_aisle and i < 13:
			continue
		var z := (i + 0.5) * RACK_W
		var fx := cx + side * FRONT_X
		match kind:
			0:
				_q(d, "steel", Vector3(fx - side * 0.3, 0.48, z), Vector3(0.5, 0.86, 0.7))
				_q(d, "dark", Vector3(fx - side * 0.3, 0.93, z), Vector3(0.54, 0.04, 0.74))
				_q(d, "dark", Vector3(fx - side * 0.16, 1.14, z), Vector3(0.05, 0.3, 0.42))
				_q(d, "screen", Vector3(fx - side * 0.19, 1.14, z), Vector3(0.01, 0.25, 0.37))
				solid(Vector3(fx - side * 0.3, 0.6, z), Vector3(0.52, 1.2, 0.72))
			1:
				_q(d, "card", Vector3(fx - side * 0.27, 0.2, z), Vector3(0.46, 0.4, 0.52))
				_q(d, "card", Vector3(fx - side * 0.25, 0.55, z + 0.03), Vector3(0.36, 0.3, 0.4), Basis(Vector3.UP, 0.35))
				_q(d, "white", Vector3(fx - side * 0.25, 0.701, z + 0.03), Vector3(0.2, 0.004, 0.12), Basis(Vector3.UP, 0.35))
				solid(Vector3(fx - side * 0.27, 0.36, z), Vector3(0.48, 0.72, 0.54))
			2:
				for t: float in [-1.0, 1.0]:
					_q(d, "alu", Vector3(fx - side * 0.3 + t * 0.16, 0.8, z), Vector3(0.05, 1.64, 0.44), Basis(Vector3.BACK, t * 0.19))
				_q(d, "yellow", Vector3(fx - side * 0.3, 1.6, z), Vector3(0.2, 0.06, 0.46))
				solid(Vector3(fx - side * 0.3, 0.8, z), Vector3(0.5, 1.6, 0.46))
			3:
				var tx: float = (floor((cx + side * 0.6) / 0.6) + 0.5) * 0.6
				var tz: float = (floor(z / 0.6) + 0.5) * 0.6
				_q(d, "void", Vector3(tx, 0.005, tz), Vector3(0.58, 0.01, 0.58))
				_q(d, "panel", Vector3(fx - side * 0.1, 0.3, tz + 0.75), Vector3(0.04, 0.6, 0.6), Basis(Vector3.BACK, side * 0.2))
				for c: Vector2 in [Vector2(-0.38, -0.38), Vector2(0.38, 0.38)]:
					_q(d, "orange", Vector3(tx + c.x, 0.17, tz + c.y), Vector3(0.11, 0.34, 0.11))
					_q(d, "white", Vector3(tx + c.x, 0.22, tz + c.y), Vector3(0.115, 0.06, 0.115))
			4:
				var sy := 0.5 + rng.randf() * 1.0
				_q(d, "alu", Vector3(fx - side * 0.18, sy, z), Vector3(0.5, 0.085, 0.46))
				_q(d, "dark", Vector3(fx - side * 0.435, sy, z), Vector3(0.012, 0.07, 0.44))
				_q(d, "led_a", Vector3(fx - side * 0.445, sy, z - 0.17), Vector3(0.012, 0.02, 0.02))
			5:
				_q(d, "cable", Vector3(fx - side * 0.05, 2.3, z), Vector3(0.06, 0.5, 0.06))
				_q(d, "cable", Vector3(fx - side * 0.05, 1.86, z), Vector3(0.08, 0.4, 0.12))
			6:
				for t: float in [-1.0, 1.0]:
					_q(d, "yellow", Vector3(cx + side * 0.62 + t * 0.075, 0.3, z), Vector3(0.02, 0.62, 0.3), Basis(Vector3.BACK, t * 0.24))
			7:
				_q(d, "tote", Vector3(fx - side * 0.24, 0.17, z), Vector3(0.42, 0.34, 0.62))
				_q(d, "tote", Vector3(fx - side * 0.24, 0.52, z), Vector3(0.42, 0.34, 0.62), Basis(Vector3.UP, 0.1))
				_q(d, "white", Vector3(fx - side * 0.24, 0.7, z), Vector3(0.3, 0.02, 0.4))
				solid(Vector3(fx - side * 0.24, 0.36, z), Vector3(0.44, 0.72, 0.64))

	# and the small mess: a door left open, a panel leaning, paper, a cup, an offcut of cable
	for k in 5:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var i := rng.randi_range(i0 + 1, maxi(i0 + 1, i1 - 2))
		if (i >= GAP0 - 1 and i <= GAP1 + 1) or (story_aisle and i < 13):
			continue
		var z := (i + 0.5) * RACK_W + rng.randf_range(-0.2, 0.2)
		var fx := cx + side * FRONT_X
		var spin := Basis(Vector3.UP, rng.randf() * TAU)
		match rng.randi() % 7:
			0:
				# a rack door standing open into the aisle
				var swing := rng.randf_range(0.9, 1.4) * side
				var hinge := Vector3(fx - side * 0.01, RACK_H * 0.5, (i + 1.0) * RACK_W)
				var dturn := Basis(Vector3.UP, swing)
				_q(d, "panel", hinge + dturn * Vector3(0, 0, -0.3), Vector3(0.025, RACK_H - 0.06, 0.6), dturn)
			1:
				_q(d, "panel", Vector3(fx - side * 0.12, 0.5, z), Vector3(0.025, 1.0, 0.56), Basis(Vector3.BACK, side * 0.2))
			2:
				_q(d, "white", Vector3(cx + side * rng.randf_range(0.5, 0.95), 0.012, z), Vector3(0.21, 0.004, 0.3), spin)
				_q(d, "white", Vector3(cx + side * rng.randf_range(0.6, 0.9), 0.014, z + 0.25), Vector3(0.21, 0.004, 0.3), Basis(Vector3.UP, rng.randf() * TAU))
			3:
				_q(round, "white", Vector3(fx - side * 0.12, 0.06, z), Vector3(0.08, 0.11, 0.08), Basis(Vector3.BACK, (PI * 0.5) if rng.randf() < 0.5 else 0.0))
			4:
				_q(d, "cable", Vector3(cx + side * 0.85, 0.03, z), Vector3(0.05, 0.05, rng.randf_range(0.5, 1.3)), Basis(Vector3.UP, rng.randf_range(-0.5, 0.5)))
			5:
				_q(d, "card", Vector3(cx + side * 0.8, 0.008, z), Vector3(0.5, 0.012, 0.36), spin)
			6:
				_q(d, "dark", Vector3(fx - side * 0.2, 0.09, z), Vector3(0.3, 0.18, 0.2), Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)))
	_flush(e, bay["e"], layers | shell)
	_flush(round, bay["e"], layers | shell, true)
	_flush(d, bay["d"], layers)


## True when x is within `clear` metres of a door that opens onto the corridor.
func _by_door(x: float, clear: float) -> bool:
	for id: String in doors:
		var d: Node3D = doors[id]
		if absf(d.position.z - ROOM_Z1) < 0.5 or absf(d.position.z + END_PAD) < 0.5:
			if absf(d.position.x - x) < clear:
				return true
	return false


func _dress_corridor() -> void:
	var r: Room = rooms["corridor"]
	var cz := (CORR_Z0 + CORR_Z1) * 0.5
	var zn := CORR_Z0     # north wall
	var zs := CORR_Z1     # the wall the hall is behind
	# things with a place: [x, kind]
	var items := [
		[-28.6, "lockers"], [-22.4, "bench"], [-18.4, "vending"], [-16.9, "water"], [-14.0, "board"],
		[-11.4, "mop"], [-3.2, "ext"], [2.4, "reel"], [9.3, "ext"], [17.8, "ext"],
		[28.4, "cabinets"], [34.0, "crate"], [37.2, "chairs"], [40.6, "trolley"], [44.2, "boxes"], [47.6, "bins"],
	]
	var south := [[0.0, "plan"], [12.5, "ext"], [20.0, "board2"], [27.0, "ext"], [39.76, "plan"]]
	var x0 := CORR_X0
	while x0 < CORR_X1:
		var x1 := minf(CORR_X1, x0 + 14.0)
		var mid := (x0 + x1) * 0.5
		var len := x1 - x0
		var e := {}
		var round := {}
		# services on the ceiling, a guide line on the floor
		_q(e, "blue", Vector3(mid, 3.17, zs - 0.3), Vector3(len, 0.18, 0.18))
		_q(e, "pipe_r", Vector3(mid, 3.17, zs - 0.52), Vector3(len, 0.18, 0.18))
		_q(e, "steel", Vector3(mid, 2.96, zn + 0.42), Vector3(len, 0.05, 0.5))
		_q(e, "cable", Vector3(mid, 3.03, zn + 0.34), Vector3(len, 0.1, 0.14))
		_q(e, "dark", Vector3(mid, 3.03, zn + 0.54), Vector3(len, 0.1, 0.18))
		var bx := x0 + 3.5
		while bx < x1:
			_q(e, "dark", Vector3(bx, 3.1, cz), Vector3(0.1, 0.3, 2.9))
			if not _by_door(bx, 1.4):
				_q(e, "steel", Vector3(bx, 1.64, zs - 0.05), Vector3(0.09, 3.28, 0.09))
			bx += 7.0
		# wear: scuffs at trolley height, damp on the ceiling, a tile gone and its cables hanging
		var wear := RandomNumberGenerator.new()
		wear.seed = hash("wear %d" % int(x0))
		for k in 5:
			var wx := wear.randf_range(x0 + 0.5, x1 - 0.5)
			var south_side := wear.randf() < 0.5
			if _by_door(wx, 1.7):
				continue
			_q(e, "dark", Vector3(wx, wear.randf_range(0.25, 0.95), (zs - 0.004) if south_side else (zn + 0.004)), Vector3(wear.randf_range(0.5, 1.8), wear.randf_range(0.03, 0.09), 0.012))
		var cx2 := wear.randf_range(x0 + 2.0, x1 - 2.0)
		_q(e, "wood", Vector3(cx2, CEIL_Y - 0.004, cz + wear.randf_range(-0.6, 0.6)), Vector3(wear.randf_range(0.6, 1.3), 0.012, wear.randf_range(0.5, 1.0)), Basis(Vector3.UP, wear.randf()))
		while _by_door(cx2, 1.5):
			cx2 += 0.8
		if int(x0 - CORR_X0) % 28 < 14:
			var gx := wear.randf_range(x0 + 3.0, x1 - 3.0)
			while _by_door(gx, 2.0):
				gx += 0.8
			_q(e, "void", Vector3(gx, CEIL_Y - 0.005, cz - 0.5), Vector3(0.6, 0.02, 0.6))
			_q(e, "cable", Vector3(gx + 0.1, CEIL_Y - 0.3, cz - 0.4), Vector3(0.05, 0.6, 0.05), Basis(Vector3.BACK, 0.12))
			_q(e, "dark", Vector3(gx - 0.12, CEIL_Y - 0.22, cz - 0.6), Vector3(0.05, 0.45, 0.05), Basis(Vector3.RIGHT, 0.2))
			_q(e, "white", Vector3(gx + 0.4, 0.3, zs - 0.2), Vector3(0.03, 0.6, 0.6), Basis(Vector3.BACK, 0.18))
		else:
			_q(round, "tote", Vector3(cx2, 0.14, cz - 0.9), Vector3(0.3, 0.28, 0.3))
		for it: Array in items:
			var x: float = it[0]
			if x < x0 or x >= x1:
				continue
			match it[1]:
				"lockers":
					for k in 8:
						_q(e, "panel" if k % 3 else "steel", Vector3(x + k * 0.5, 0.95, zn + 0.27), Vector3(0.48, 1.9, 0.5))
						_q(e, "dark", Vector3(x + k * 0.5 + 0.16, 1.1, zn + 0.525), Vector3(0.04, 0.1, 0.01))
					solid(Vector3(x + 1.75, 0.95, zn + 0.27), Vector3(4.0, 1.9, 0.5))
				"bench":
					_q(e, "wood", Vector3(x, 0.45, zn + 0.24), Vector3(1.7, 0.06, 0.42))
					for sx: float in [-1.0, 1.0]:
						_q(e, "steel", Vector3(x + sx * 0.7, 0.21, zn + 0.24), Vector3(0.05, 0.42, 0.38))
					_q(e, "yellow", Vector3(x + 0.4, 0.57, zn + 0.24), Vector3(0.28, 0.17, 0.24))
					solid(Vector3(x, 0.24, zn + 0.24), Vector3(1.7, 0.48, 0.42))
				"vending":
					_q(e, "dark", Vector3(x, 0.95, zn + 0.38), Vector3(0.95, 1.9, 0.75))
					_q(e, "vend", Vector3(x - 0.12, 1.15, zn + 0.76), Vector3(0.62, 1.2, 0.01))
					_q(e, "panel", Vector3(x + 0.33, 1.2, zn + 0.76), Vector3(0.2, 0.5, 0.012))
					solid(Vector3(x, 0.95, zn + 0.38), Vector3(0.95, 1.9, 0.75))
					omni(r, Vector3(x - 0.1, 1.2, zn + 1.2), Color(0.55, 0.78, 1.0), 0.9, 4.5, r.layers)
				"water":
					_q(e, "white", Vector3(x, 0.5, zn + 0.2), Vector3(0.34, 1.0, 0.36))
					_q(round, "blue", Vector3(x, 1.2, zn + 0.2), Vector3(0.28, 0.4, 0.28))
					solid(Vector3(x, 0.6, zn + 0.2), Vector3(0.34, 1.2, 0.36))
				"board":
					_q(e, "wood", Vector3(x, 1.5, zn + 0.02), Vector3(1.7, 1.0, 0.03))
					for k in 6:
						_q(e, "white" if k != 2 else "yellow", Vector3(x - 0.62 + (k % 3) * 0.6, 1.72 - (k / 3) * 0.44, zn + 0.05), Vector3(0.22 + (k % 2) * 0.12, 0.3, 0.02), Basis(Vector3.BACK, (k - 2) * 0.03))
					sign_text(r, "DAYS SINCE LAST INCIDENT   1123", Vector3(x, 2.12, zn + 0.02), Basis(), 0.0013)
				"mop":
					_q(e, "yellow", Vector3(x, 0.22, zn + 0.3), Vector3(0.4, 0.44, 0.55))
					_q(e, "wood", Vector3(x + 0.05, 0.9, zn + 0.14), Vector3(0.03, 1.5, 0.03), Basis(Vector3.RIGHT, -0.12))
					for t: float in [-1.0, 1.0]:
						_q(e, "yellow", Vector3(x + 1.1 + t * 0.075, 0.3, zn + 0.5), Vector3(0.02, 0.62, 0.3), Basis(Vector3.BACK, t * 0.24))
				"ext":
					_q(e, "red", Vector3(x, 0.95, zn + 0.1), Vector3(0.15, 0.5, 0.15))
					_q(e, "red", Vector3(x, 1.6, zn + 0.02), Vector3(0.22, 0.22, 0.02))
				"reel":
					_q(round, "red", Vector3(x, 1.3, zn + 0.1), Vector3(0.62, 0.16, 0.62), Basis(Vector3.RIGHT, PI * 0.5))
					_q(round, "dark", Vector3(x, 1.3, zn + 0.19), Vector3(0.2, 0.03, 0.2), Basis(Vector3.RIGHT, PI * 0.5))
				"cabinets":
					for k in 3:
						_q(e, "steel", Vector3(x + k * 1.1, 1.0, zn + 0.24), Vector3(1.0, 2.0, 0.46))
						_q(e, "led_g" if k != 1 else "led_a", Vector3(x + k * 1.1 - 0.3, 1.7, zn + 0.475), Vector3(0.04, 0.04, 0.01))
						_q(e, "yellow", Vector3(x + k * 1.1 + 0.25, 1.45, zn + 0.475), Vector3(0.16, 0.14, 0.006))
					solid(Vector3(x + 1.1, 1.0, zn + 0.24), Vector3(3.2, 2.0, 0.46))
				"crate":
					_q(e, "wood", Vector3(x, 0.07, zn + 0.42), Vector3(1.2, 0.14, 0.8))
					_q(e, "wood", Vector3(x, 0.6, zn + 0.42), Vector3(1.1, 0.92, 0.7))
					_q(e, "dark", Vector3(x, 0.6, zn + 0.775), Vector3(0.5, 0.3, 0.005))
					solid(Vector3(x, 0.55, zn + 0.42), Vector3(1.2, 1.1, 0.8))
				"chairs":
					for k in 5:
						_q(e, "dark", Vector3(x, 0.45 + k * 0.1, zn + 0.3 + k * 0.012), Vector3(0.46, 0.05, 0.46))
					_q(e, "dark", Vector3(x, 1.0, zn + 0.1), Vector3(0.44, 0.7, 0.05))
					for c: Vector2 in [Vector2(-0.2, 0.1), Vector2(0.2, 0.1), Vector2(-0.2, 0.5), Vector2(0.2, 0.5)]:
						_q(e, "alu", Vector3(x + c.x, 0.22, zn + c.y), Vector3(0.03, 0.44, 0.03))
					solid(Vector3(x, 0.5, zn + 0.3), Vector3(0.5, 1.0, 0.5))
				"trolley":
					_q(e, "steel", Vector3(x, 0.5, zn + 0.36), Vector3(1.0, 0.04, 0.6))
					_q(e, "steel", Vector3(x, 0.14, zn + 0.36), Vector3(1.0, 0.04, 0.6))
					_q(e, "alu", Vector3(x - 0.1, 0.57, zn + 0.36), Vector3(0.7, 0.09, 0.46))
					_q(e, "alu", Vector3(x - 0.05, 0.67, zn + 0.36), Vector3(0.7, 0.09, 0.46), Basis(Vector3.UP, 0.06))
					_q(e, "steel", Vector3(x + 0.5, 0.75, zn + 0.36), Vector3(0.03, 0.6, 0.56))
					solid(Vector3(x, 0.4, zn + 0.36), Vector3(1.0, 0.8, 0.6))
				"boxes":
					_q(e, "card", Vector3(x, 0.25, zn + 0.32), Vector3(0.6, 0.5, 0.6))
					_q(e, "card", Vector3(x + 0.68, 0.2, zn + 0.28), Vector3(0.55, 0.4, 0.5), Basis(Vector3.UP, 0.1))
					_q(e, "card", Vector3(x + 0.1, 0.68, zn + 0.3), Vector3(0.45, 0.36, 0.45), Basis(Vector3.UP, -0.2))
					solid(Vector3(x + 0.3, 0.4, zn + 0.3), Vector3(1.3, 0.8, 0.6))
				"bins":
					for k in 3:
						_q(e, ["green", "tote", "panel"][k], Vector3(x + k * 0.52, 0.42, zn + 0.26), Vector3(0.46, 0.84, 0.46))
						_q(e, "dark", Vector3(x + k * 0.52, 0.86, zn + 0.26), Vector3(0.48, 0.04, 0.48))
					solid(Vector3(x + 0.52, 0.44, zn + 0.26), Vector3(1.5, 0.88, 0.46))
		for it: Array in south:
			var x: float = it[0]
			if x < x0 or x >= x1:
				continue
			match it[1]:
				"plan":
					_q(e, "white", Vector3(x, 1.55, zs - 0.02), Vector3(1.1, 0.75, 0.02))
					_q(e, "panel", Vector3(x, 1.55, zs - 0.04), Vector3(0.9, 0.5, 0.02))
					_q(e, "led_g", Vector3(x - 0.3, 1.42, zs - 0.055), Vector3(0.04, 0.04, 0.01))
					var zone := sign_text(r, "DATA HALL · ZONE %s" % ("A" if x < 20.0 else "B"), Vector3(x, 2.5, zs - 0.02), Basis(Vector3.UP, PI), 0.0046, Color(0.36, 0.38, 0.42))
					zone.layers = r.layers
				"ext":
					_q(e, "red", Vector3(x, 0.95, zs - 0.1), Vector3(0.15, 0.5, 0.15))
					_q(e, "red", Vector3(x, 1.6, zs - 0.02), Vector3(0.22, 0.22, 0.02))
				"board2":
					_q(e, "white", Vector3(x, 1.55, zs - 0.02), Vector3(1.8, 1.0, 0.02))
					sign_text(r, "NIGHTS: one technician on site.\nCall the operations desk before every task.", Vector3(x, 1.6, zs - 0.06), Basis(Vector3.UP, PI), 0.0012, Color(0.08, 0.08, 0.09))
		_flush(e, r.extra, r.layers)
		_flush(round, r.extra, r.layers, true)
		x0 = x1
	# hung across the corridor, read from either direction
	var hung := [
		[-13.0, "DATA HALL · WAY OUT", "STAFF LOCKERS"],
		[9.1, "ZONE B · UPS · PLANT", "ZONE A · WAY OUT"],
		[28.0, "ZONE B · PLANT", "UPS · SECURITY · WAY OUT"],
	]
	for hsign: Array in hung:
		var x: float = hsign[0]
		prop(r, Vector3(x, 2.62, cz), Vector3(0.04, 0.34, 2.5), _void_mat)
		var east := sign_text(r, hsign[1], Vector3(x - 0.025, 2.62, cz), Basis(Vector3.UP, -PI * 0.5), minf(0.003, 2.3 / (String(hsign[1]).length() * 28.8)), Color(0.8, 0.88, 1.0))
		var west := sign_text(r, hsign[2], Vector3(x + 0.025, 2.62, cz), Basis(Vector3.UP, PI * 0.5), minf(0.003, 2.3 / (String(hsign[2]).length() * 28.8)), Color(0.8, 0.88, 1.0))
		east.double_sided = false
		west.double_sided = false
	# one fitting has dropped at one end and nobody has put it back
	var hang := prop(r, Vector3(-24.6, CEIL_Y - 0.28, cz + 0.3), Vector3(1.2, 0.06, 0.14), _lamp_off)
	hang.rotation = Vector3(0.0, 0.5, 0.36)
	prop(r, Vector3(-24.1, CEIL_Y - 0.25, cz + 0.05), Vector3(0.04, 0.5, 0.04), _m("dark"))


## Security cameras: the six that feed the desk, and more that watch the hall. Each is a
## white housing with a hood, a dark lens, a status light and a bracket to the wall above.
func _build_cameras() -> void:
	var cams := [
		[Vector3(-8.7, 3.0, -11.7), Vector3(-4.5, 0.6, -8.0)],
		[Vector3(-8.7, 3.0, -4.3), Vector3(8.0, 0.4, -4.3)],
		[Vector3(0.0, 3.1, -2.3), Vector3(0.0, 0.4, 11.0)],
		[Vector3(HALL_B_X, 3.1, -2.3), Vector3(HALL_B_X, 0.4, 11.0)],
		[Vector3(18.5, 3.0, -11.7), Vector3(23.0, 0.6, -8.5)],
		[Vector3(17.7, 3.0, -6.3), Vector3(12.5, 0.6, -10.5)],
	]
	# and ones that are not on the desk's wall: someone else is watching those
	for hall: String in ["a", "b"]:
		var ox: float = halls[hall]["ox"]
		for a: int in [1, 3]:
			cams.append([Vector3(aisle_x(hall, a), 3.1, -2.3), Vector3(aisle_x(hall, a), 0.4, 11.0)])
		cams.append([Vector3(ox - 2.5 * AISLE_PITCH, 3.3, HALL_Z1 - 0.35), Vector3(ox, 0.3, AISLE_LEN)])
		cams.append([Vector3(ox + 0.5 * AISLE_PITCH, 3.3, HALL_Z1 - 0.35), Vector3(ox - AISLE_PITCH, 0.3, AISLE_LEN)])
	cams.append([Vector3(CORR_X1 - 0.4, 3.0, -4.3), Vector3(30.0, 0.4, -4.3)])
	var white := mat(Color(0.62, 0.63, 0.62), 0.5, 0.1)
	var dark := mat(Color(0.02, 0.02, 0.025), 0.15, 0.6)
	var red := glow_mat(Color(1.0, 0.1, 0.06), 3.0)
	var lens_mesh := CylinderMesh.new()
	lens_mesh.top_radius = 0.042
	lens_mesh.bottom_radius = 0.042
	lens_mesh.height = 0.05
	lens_mesh.radial_segments = 10
	lens_mesh.rings = 1
	lens_mesh.material = dark
	for c: Array in cams:
		var eye: Vector3 = c[0]
		var look: Vector3 = c[1]
		var id := room_at(eye)
		if id == "":
			continue
		var r: Room = rooms[id]
		var layers := r.layers
		if id.begins_with("hall_"):
			layers |= int(halls[id.trim_prefix("hall_")]["all"])
		var n := Node3D.new()
		r.extra.add_child(n)
		# sits just above the point the feed is taken from, so it never sees itself
		n.position = eye + Vector3(0, 0.2, 0)
		n.look_at_from_position(n.position, look + Vector3(0, 0.2, 0))
		box_in(n, Vector3(0, 0, 0.04), Vector3(0.12, 0.11, 0.3), white, layers)
		box_in(n, Vector3(0, 0.065, -0.03), Vector3(0.15, 0.02, 0.4), white, layers)
		box_in(n, Vector3(0, -0.01, -0.112), Vector3(0.1, 0.08, 0.01), dark, layers)
		var lens := MeshInstance3D.new()
		lens.mesh = lens_mesh
		lens.rotation.x = PI * 0.5
		lens.position = Vector3(0, -0.005, -0.13)
		lens.layers = layers
		n.add_child(lens)
		box_in(n, Vector3(0.04, -0.035, -0.118), Vector3(0.014, 0.014, 0.01), red, layers)
		box_in(n, Vector3(0, 0.0, 0.2), Vector3(0.03, 0.03, 0.12), dark, layers)
		# the bracket: an arm back and a plate, kept upright whatever way the camera points
		var arm := Node3D.new()
		r.extra.add_child(arm)
		var back := -(look - eye)
		back.y = 0.0
		back = back.normalized()
		arm.position = n.position
		box_in(arm, back * 0.2 + Vector3(0, 0.07, 0), Vector3(0.05, 0.05, 0.05) + Vector3(absf(back.x), 0, absf(back.z)) * 0.3, white, layers)
		box_in(arm, back * 0.36 + Vector3(0, 0.07, 0), Vector3(0.16, 0.16, 0.16) - Vector3(absf(back.x), 0, absf(back.z)) * 0.13, white, layers)
