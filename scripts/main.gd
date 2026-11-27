extends Node3D
## The look test: Data Hall A, three cold aisles joined by cross corridors, assembled in code.
## Dimensions follow the reference: 0.62 m racks, 2.2 m aisles, strip lights every 3.1 m.
##
## The 3D world is drawn into a small SubViewport and scaled up with hard pixels.

const AISLES := 3
const AISLE_PITCH := 5.44      # cold aisle to cold aisle; leaves a 1 m hot aisle between row backs
const RACKS := 32              # per row
const RACK_W := 0.62
const RACK_H := 2.12
const RACK_D := 1.12
const ROW_X := 1.66            # row centre, measured from the aisle centre
const FRONT_X := 1.1           # rack fronts face the aisle here
const CEIL_Y := 3.28
const STRIP_GAP := 3.1
const END_PAD := 2.6           # depth of the cross corridor at each end
const HALL_HALF_W := 9.0
const STRIP_COLOUR := Color(0.82, 0.92, 1.0)
const PIXEL_ROWS: Array[int] = [180, 240, 300, 360, 540]

var aisle_len: float
var view: SubViewport
var world: Node3D      # everything 3D lives under here, inside the SubViewport
var visual: Node3D     # the part of the world that is also drawn mirrored in the floor
var player: CharacterBody3D
var post_mat: ShaderMaterial
var hud_clock: Label
var hud_hint: Label
var hud_fps: Label
var _clock_s := 22.0 * 3600.0
var _rows_i := 1
var _strip_lights: Array[OmniLight3D] = []


func _ready() -> void:
	aisle_len = RACKS * RACK_W
	_setup_input()
	_build_view()
	_build_environment()
	visual = Node3D.new()
	world.add_child(visual)
	_build_shell()
	for a in AISLES:
		_build_aisle(a)
	_build_mirror()
	_build_player()
	_build_lens_and_hud()
	get_viewport().size_changed.connect(_fit_view)
	_fit_view()
	_apply_shot_args()


func _process(delta: float) -> void:
	_clock_s += delta * 4.0   # the night runs four times faster than real time
	var h := int(_clock_s / 3600.0) % 24
	var m := int(_clock_s / 60.0) % 60
	hud_clock.text = "%02d:%02d" % [h, m]
	hud_hint.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if hud_fps.visible:
		hud_fps.text = "%d fps · %d x %d · %d draws" % [
			Engine.get_frames_per_second(), view.size.x, view.size.y,
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_stats"):
		hud_fps.visible = not hud_fps.visible
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode >= KEY_1 and event.physical_keycode < KEY_1 + PIXEL_ROWS.size():
		# number keys pick the pixel size: 1 is the chunkiest
		_rows_i = event.physical_keycode - KEY_1
		_fit_view()
	else:
		player.handle_input(event)


func aisle_x(a: int) -> float:
	return (a - (AISLES - 1) * 0.5) * AISLE_PITCH


# ---------------------------------------------------------------- input

func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jog": [KEY_SHIFT], "crouch": [KEY_CTRL, KEY_C], "torch": [KEY_F],
		"release_mouse": [KEY_ESCAPE], "toggle_stats": [KEY_F3],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- low-resolution view

func _build_view() -> void:
	get_viewport().disable_3d = true
	view = SubViewport.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.handle_input_locally = false
	view.audio_listener_enable_3d = true
	view.msaa_3d = Viewport.MSAA_DISABLED
	add_child(view)
	world = Node3D.new()
	view.add_child(world)

	var screen := CanvasLayer.new()
	screen.layer = 0
	add_child(screen)
	var rect := TextureRect.new()
	rect.texture = view.get_texture()
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(rect)


## Size the 3D view to a fixed number of pixel rows, whatever the window size.
func _fit_view() -> void:
	var win := get_viewport().get_visible_rect().size
	var rows := PIXEL_ROWS[_rows_i]
	view.size = Vector2i(maxi(16, int(round(rows * win.x / maxf(win.y, 1.0)))), rows)
	if post_mat:
		post_mat.set_shader_parameter("pixel_rows", float(rows))


# ---------------------------------------------------------------- world

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.016, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.8)
	env.ambient_light_energy = 0.06
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_light_color = Color(0.045, 0.058, 0.07)
	env.fog_light_energy = 1.0
	env.fog_density = 0.03
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)


func _mat(albedo: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m


## Render layers decide which strip lights reach a mesh: aisle `a` uses layer bit `a`.
## That keeps every mesh under the renderer's limit of eight lights and stops light
## leaking through the rack rows.
func _layer(a: int) -> int:
	return 1 << a


const ALL_AISLES := (1 << AISLES) - 1
const SHELL := 1 << AISLES      # walls and ceiling: lit by the cross-corridor lights only


func _box(pos: Vector3, size: Vector3, mat: Material, layers := ALL_AISLES) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.layers = layers
	visual.add_child(mi)
	return mi


func _solid(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	world.add_child(body)


func _build_shell() -> void:
	var z_mid := aisle_len * 0.5
	var z_len := aisle_len + END_PAD * 2.0
	var hall_w := HALL_HALF_W * 2.0

	# floor: a glossy plane you can see the mirrored hall through (see _build_mirror).
	# One strip per aisle, lit only by that aisle's lights; the cross corridors see them all.
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = load("res://shaders/floor.gdshader")
	for a in AISLES:
		var x0 := -HALL_HALF_W if a == 0 else aisle_x(a) - AISLE_PITCH * 0.5
		var x1 := HALL_HALF_W if a == AISLES - 1 else aisle_x(a) + AISLE_PITCH * 0.5
		_floor_piece(floor_mat, (x0 + x1) * 0.5, z_mid, x1 - x0, aisle_len, _layer(a))
	_floor_piece(floor_mat, 0.0, -END_PAD * 0.5, hall_w, END_PAD, ALL_AISLES)
	_floor_piece(floor_mat, 0.0, aisle_len + END_PAD * 0.5, hall_w, END_PAD, ALL_AISLES)
	_solid(Vector3(0, -0.1, z_mid), Vector3(hall_w, 0.2, z_len))

	var dark := _mat(Color(0.07, 0.072, 0.08), 0.8)
	var wall := _mat(Color(0.05, 0.052, 0.058), 0.85)
	_box(Vector3(0, CEIL_Y + 0.1, z_mid), Vector3(hall_w, 0.2, z_len), dark, SHELL)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * (HALL_HALF_W + 0.1), CEIL_Y * 0.5, z_mid), Vector3(0.2, CEIL_Y, z_len), wall, SHELL)
		_solid(Vector3(side * (HALL_HALF_W + 0.1), CEIL_Y * 0.5, z_mid), Vector3(0.2, CEIL_Y, z_len))
	for z in [-END_PAD - 0.1, aisle_len + END_PAD + 0.1]:
		_box(Vector3(0, CEIL_Y * 0.5, z), Vector3(hall_w, CEIL_Y, 0.2), wall, SHELL)
		_solid(Vector3(0, CEIL_Y * 0.5, z), Vector3(hall_w, CEIL_Y, 0.2))

	# the far door, and the green exit sign over it
	var door := _mat(Color(0.09, 0.095, 0.105), 0.5, 0.6)
	_box(Vector3(0, 1.05, aisle_len + END_PAD - 0.02), Vector3(1.0, 2.1, 0.06), door, SHELL)
	var sign_mat := StandardMaterial3D.new()
	sign_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sign_mat.albedo_color = Color(0.1, 1.0, 0.3)
	sign_mat.emission_enabled = true
	sign_mat.emission = Color(0.1, 1.0, 0.3)
	sign_mat.emission_energy_multiplier = 3.0
	_box(Vector3(0, 2.45, aisle_len + END_PAD - 0.03), Vector3(0.48, 0.15, 0.04), sign_mat)
	var sign_light := OmniLight3D.new()
	sign_light.light_color = Color(0.1, 1.0, 0.3)
	sign_light.light_energy = 0.5
	sign_light.omni_range = 5.0
	sign_light.light_cull_mask = SHELL | ALL_AISLES
	sign_light.position = Vector3(0, 2.4, aisle_len + END_PAD - 0.4)
	world.add_child(sign_light)


func _floor_piece(mat: Material, x: float, z: float, w: float, d: float, layers: int) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, d)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(x, 0, z)
	mi.layers = layers
	world.add_child(mi)


## One cold aisle: two facing rows of racks, the fibre overhead, and its strip lights.
func _build_aisle(a: int) -> void:
	var cx := aisle_x(a)
	var layers := _layer(a)
	var z_mid := aisle_len * 0.5
	var row_letter := char(65 + a * 2)   # rows A/B, C/D, E/F

	# rack bodies
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(RACK_D, RACK_H, RACK_W - 0.012)
	body_mesh.material = _mat(Color(0.06, 0.06, 0.065), 0.55, 0.3)
	var bodies := MultiMesh.new()
	bodies.transform_format = MultiMesh.TRANSFORM_3D
	bodies.mesh = body_mesh
	bodies.instance_count = RACKS * 2

	# rack fronts: one quad each, every LED drawn by the shader
	var front_mat := ShaderMaterial.new()
	front_mat.shader = load("res://shaders/rack_front.gdshader")
	front_mat.set_shader_parameter("seed", float(a) * 97.0)
	var front_mesh := QuadMesh.new()
	front_mesh.size = Vector2(RACK_W, RACK_H)
	front_mesh.material = front_mat
	var fronts := MultiMesh.new()
	fronts.transform_format = MultiMesh.TRANSFORM_3D
	fronts.mesh = front_mesh
	fronts.instance_count = RACKS * 2

	# a spool of fibre slack above every rack, so every customer gets the same length
	var yellow := _mat(Color(0.85, 0.58, 0.04), 0.5)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.154
	torus.outer_radius = 0.226
	torus.rings = 16
	torus.ring_segments = 6
	torus.material = yellow
	var spools := MultiMesh.new()
	spools.transform_format = MultiMesh.TRANSFORM_3D
	spools.mesh = torus
	spools.instance_count = RACKS * 2
	var upright := Basis(Vector3.FORWARD, PI * 0.5)

	var n := 0
	for side in [-1.0, 1.0]:
		for i in RACKS:
			var z := (i + 0.5) * RACK_W
			bodies.set_instance_transform(n, Transform3D(Basis(), Vector3(cx + side * ROW_X, RACK_H * 0.5, z)))
			var facing := Basis(Vector3.UP, -side * PI * 0.5)   # quad normal points into the aisle
			fronts.set_instance_transform(n, Transform3D(facing, Vector3(cx + side * (FRONT_X - 0.004), RACK_H * 0.5, z)))
			spools.set_instance_transform(n, Transform3D(upright, Vector3(cx + side * 1.305, 2.62, z)))
			n += 1
			if i % 8 == 1:
				var letter := row_letter if side < 0 else char(row_letter.unicode_at(0) + 1)
				_rack_label(cx, side, z, "HALL A · ROW %s · %d" % [letter, 140 + i], layers)
		# bulkhead over the row, and one long collider for it
		_box(Vector3(cx + side * 2.05, 2.72, z_mid), Vector3(1.4, 1.14, aisle_len), _mat(Color(0.07, 0.072, 0.08), 0.8), layers)
		_solid(Vector3(cx + side * ROW_X, RACK_H * 0.5, z_mid), Vector3(RACK_D, RACK_H, aisle_len))

	for mm in [bodies, fronts, spools]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.layers = layers
		visual.add_child(mmi)

	# cable tray down the middle, two runs of yellow fibre on top of it
	_box(Vector3(cx, 2.86, z_mid), Vector3(0.6, 0.04, aisle_len), _mat(Color(0.1, 0.1, 0.11), 0.5, 0.5), layers)
	for side in [-1.0, 1.0]:
		var tube := CylinderMesh.new()
		tube.top_radius = 0.05
		tube.bottom_radius = 0.05
		tube.height = aisle_len
		tube.radial_segments = 8
		tube.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = tube
		mi.material_override = yellow
		mi.layers = layers
		mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(cx + side * 0.13, 2.925, z_mid))
		visual.add_child(mi)

	# a dimmer fitting in each cross corridor, at the mouth of the aisle
	for z in [-END_PAD * 0.5, aisle_len + END_PAD * 0.5]:
		var cl := OmniLight3D.new()
		cl.light_color = STRIP_COLOUR
		cl.light_energy = 1.6
		cl.omni_range = 6.0
		cl.omni_attenuation = 1.3
		cl.light_cull_mask = layers | SHELL
		cl.position = Vector3(cx, 2.9, z)
		world.add_child(cl)
		_strip_lights.append(cl)

	# strip lights
	var strip_mat := StandardMaterial3D.new()
	strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip_mat.albedo_color = STRIP_COLOUR
	strip_mat.emission_enabled = true
	strip_mat.emission = STRIP_COLOUR
	strip_mat.emission_energy_multiplier = 4.0
	var haze_mat := ShaderMaterial.new()
	haze_mat.shader = load("res://shaders/haze_cone.gdshader")
	var count := int(floor(aisle_len / STRIP_GAP)) + 1
	var z0 := (aisle_len - (count - 1) * STRIP_GAP) * 0.5
	for i in count:
		var z := z0 + i * STRIP_GAP
		_box(Vector3(cx, 3.23, z), Vector3(1.6, 0.06, 0.14), strip_mat, layers)
		var light := OmniLight3D.new()
		light.light_color = STRIP_COLOUR
		light.light_energy = 3.4
		light.omni_range = 7.5
		light.omni_attenuation = 1.3
		light.light_specular = 0.6
		light.light_cull_mask = layers
		light.position = Vector3(cx, 3.0, z)
		world.add_child(light)
		_strip_lights.append(light)
		var haze := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(2.6, 3.2)
		haze.mesh = quad
		haze.material_override = haze_mat
		haze.position = Vector3(cx, 1.62, z)
		haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(haze)


func _rack_label(cx: float, side: float, z: float, text: String, layers: int) -> void:
	var facing := Basis(Vector3.UP, -side * PI * 0.5)
	var sticker := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.042)
	sticker.mesh = quad
	sticker.material_override = _mat(Color(0.62, 0.62, 0.58), 0.9)
	sticker.layers = layers
	sticker.transform = Transform3D(facing, Vector3(cx + side * (FRONT_X - 0.008), 2.085, z))
	visual.add_child(sticker)
	var label := Label3D.new()
	label.text = text
	label.font = load("res://fonts/IBMPlexMono-Medium.ttf")
	label.font_size = 48
	label.pixel_size = 0.00042
	label.modulate = Color(0.05, 0.05, 0.05)
	label.outline_size = 0
	label.shaded = true
	label.layers = layers
	label.transform = Transform3D(facing, Vector3(cx + side * (FRONT_X - 0.011), 2.085, z))
	visual.add_child(label)


## The Compatibility renderer has no screen-space reflections, so the floor is a real mirror:
## the hall is drawn a second time upside down beneath a partly transparent floor.
func _build_mirror() -> void:
	var mirror := visual.duplicate()
	mirror.scale = Vector3(1, -1, 1)
	world.add_child(mirror)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(load("res://scripts/player.gd"))
	player.position = Vector3(aisle_x(1), 0.02, -1.2)
	player.rotation.y = PI   # face down the middle aisle (+z)
	world.add_child(player)


# ---------------------------------------------------------------- lens and HUD

func _build_lens_and_hud() -> void:
	var lens := CanvasLayer.new()
	lens.layer = 1
	add_child(lens)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/post.gdshader")
	rect.material = post_mat
	lens.add_child(rect)

	var hud := CanvasLayer.new()
	hud.layer = 2
	add_child(hud)
	var mono: Font = load("res://fonts/IBMPlexMono-Medium.ttf")
	var loc := _label(hud, mono, 13, Color(0.6, 0.63, 0.69), Vector2(32, 26))
	loc.text = "HALDEN DC-3  ·  DATA HALL A  ·  LOOK TEST"
	hud_clock = _label(hud, mono, 26, Color(0.93, 0.95, 0.97), Vector2(32, 46))
	hud_fps = _label(hud, mono, 12, Color(1.0, 0.7, 0.28), Vector2(32, 86))
	hud_fps.visible = false
	hud_hint = _label(hud, mono, 14, Color(0.93, 0.95, 0.97), Vector2.ZERO)
	hud_hint.text = "CLICK TO START\n\nWASD move  ·  Shift jog  ·  Ctrl crouch  ·  F torch\n1 to 5 pixel size  ·  F3 stats  ·  Esc release mouse"
	hud_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hud_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud_hint.position.y -= 48

	# reticle: one quiet dot
	var dot := ColorRect.new()
	dot.color = Color(0.93, 0.95, 0.97, 0.55)
	dot.size = Vector2(4, 4)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position -= Vector2(2, 2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(dot)


func _label(parent: Node, font: Font, size: int, colour: Color, pos: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


# ---------------------------------------------------------------- test shots

## `-- --shot=<name> --out=<file.png>` renders one still and quits. Used to check the look.
func _apply_shot_args() -> void:
	var shot := ""
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.trim_prefix("--shot=")
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	if shot == "":
		return
	hud_hint.modulate.a = 0.0
	set_process(false)
	match shot:
		"aisle":
			player.position = Vector3(aisle_x(1), 0.02, 0.4)
		"cross":
			# standing in the cross corridor, looking across the mouths of all three aisles
			player.position = Vector3(-8.4, 0.02, -1.9)
			player.rotation.y = -1.92
		"rack":
			player.position = Vector3(aisle_x(1) + 0.35, 0.02, 8.0)
			player.rotation.y = PI + 1.15
		"hot":
			# a hot aisle between two row backs: no strip lights, torch only
			player.position = Vector3((aisle_x(0) + aisle_x(1)) * 0.5, 0.02, 1.0)
			player.torch.visible = true
		"torch":
			player.position = Vector3(aisle_x(1), 0.02, 0.4)
			player.torch.visible = true
			for l in _strip_lights:
				l.visible = false
	await get_tree().create_timer(1.5).timeout
	print("draw calls: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"  primitives: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"  view: ", view.size)
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	get_tree().quit()
