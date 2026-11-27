extends Node3D
## Milestone 0, the look test: one walkable aisle of Data Hall A, assembled in code.
## Dimensions follow the reference: 0.62 m racks, 2.2 m aisle, strip lights every 3.1 m.

const RACKS := 32
const RACK_W := 0.62
const RACK_H := 2.12
const RACK_D := 1.12
const ROW_X := 1.66            # centre of each rack row
const FRONT_X := 1.1           # rack fronts face the aisle here
const CEIL_Y := 3.28
const STRIP_GAP := 3.1
const END_PAD := 2.4
const STRIP_COLOUR := Color(0.82, 0.92, 1.0)

var aisle_len: float
var player: CharacterBody3D
var visual: Node3D    # everything that should also appear reflected in the floor
var post_mat: ShaderMaterial
var hud_clock: Label
var hud_hint: Label
var hud_fps: Label
var _clock_s := 22.0 * 3600.0
var _scale_steps: Array[float] = [1.0, 0.85, 0.7, 0.58, 0.5]
var _scale_i := 0
var _slow_t := 0.0
var _fast_t := 0.0


func _ready() -> void:
	aisle_len = RACKS * RACK_W
	_setup_input()
	_build_environment()
	visual = Node3D.new()
	add_child(visual)
	_build_shell()
	_build_racks()
	_build_overhead()
	_build_strips()
	_build_mirror()
	_build_player()
	_build_lens_and_hud()
	_apply_shot_args()


func _process(delta: float) -> void:
	_clock_s += delta * 4.0   # the night runs four times faster than real time
	var h := int(_clock_s / 3600.0) % 24
	var m := int(_clock_s / 60.0) % 60
	hud_clock.text = "%02d:%02d" % [h, m]
	hud_hint.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if hud_fps.visible:
		hud_fps.text = "%d fps · %d%% res · %d draws" % [
			Engine.get_frames_per_second(),
			int(_scale_steps[_scale_i] * 100.0),
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))]
	_adapt_resolution(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_stats"):
		hud_fps.visible = not hud_fps.visible


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
	add_child(we)


func _mat(albedo: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m


func _box(pos: Vector3, size: Vector3, mat: Material, solid := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	visual.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		body.position = pos
		add_child(body)
	return mi


func _build_shell() -> void:
	var z_mid := aisle_len * 0.5
	var z_len := aisle_len + END_PAD * 2.0

	# floor: a glossy plane you can see the mirrored hall through (see _build_mirror)
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = load("res://shaders/floor.gdshader")
	var segs := 6
	var seg_len := z_len / segs
	for i in segs:
		var plane := PlaneMesh.new()
		plane.size = Vector2(8.0, seg_len)
		var fmi := MeshInstance3D.new()
		fmi.mesh = plane
		fmi.material_override = floor_mat
		fmi.position = Vector3(0, 0, -END_PAD + seg_len * (i + 0.5))
		add_child(fmi)
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fshape := BoxShape3D.new()
	fshape.size = Vector3(8.0, 0.2, z_len)
	fcs.shape = fshape
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, -0.1, z_mid)
	add_child(floor_body)

	var dark := _mat(Color(0.07, 0.072, 0.08), 0.8)
	var wall := _mat(Color(0.05, 0.052, 0.058), 0.85)
	# ceiling and the bulkheads over each rack row
	_box(Vector3(0, CEIL_Y + 0.1, z_mid), Vector3(8.0, 0.2, z_len), dark)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 2.05, 2.72, z_mid), Vector3(1.4, 1.14, aisle_len), dark)
		_box(Vector3(side * 4.0, CEIL_Y * 0.5, z_mid), Vector3(0.2, CEIL_Y, z_len), wall, true)
		# one long collider per rack row
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(RACK_D, RACK_H, aisle_len)
		cs.shape = shape
		body.add_child(cs)
		body.position = Vector3(side * ROW_X, RACK_H * 0.5, z_mid)
		add_child(body)
	# end walls
	_box(Vector3(0, CEIL_Y * 0.5, -END_PAD - 0.1), Vector3(8.0, CEIL_Y, 0.2), wall, true)
	_box(Vector3(0, CEIL_Y * 0.5, aisle_len + END_PAD + 0.1), Vector3(8.0, CEIL_Y, 0.2), wall, true)

	# the far door, and the green exit sign over it
	var door := _mat(Color(0.09, 0.095, 0.105), 0.5, 0.6)
	_box(Vector3(0, 1.05, aisle_len + END_PAD - 0.02), Vector3(1.0, 2.1, 0.06), door)
	var sign_mat := StandardMaterial3D.new()
	sign_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sign_mat.albedo_color = Color(0.1, 1.0, 0.3)
	sign_mat.emission_enabled = true
	sign_mat.emission = Color(0.1, 1.0, 0.3)
	sign_mat.emission_energy_multiplier = 3.0
	_box(Vector3(0, 2.45, aisle_len + END_PAD - 0.03), Vector3(0.48, 0.15, 0.04), sign_mat)
	var sign_light := OmniLight3D.new()
	sign_light.light_color = Color(0.1, 1.0, 0.3)
	sign_light.light_energy = 0.35
	sign_light.omni_range = 4.0
	sign_light.position = Vector3(0, 2.4, aisle_len + END_PAD - 0.4)
	add_child(sign_light)


func _build_racks() -> void:
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
	var front_mesh := QuadMesh.new()
	front_mesh.size = Vector2(RACK_W, RACK_H)
	front_mesh.material = front_mat
	var fronts := MultiMesh.new()
	fronts.transform_format = MultiMesh.TRANSFORM_3D
	fronts.mesh = front_mesh
	fronts.instance_count = RACKS * 2

	var n := 0
	for side in [-1.0, 1.0]:
		for i in RACKS:
			var z := (i + 0.5) * RACK_W
			bodies.set_instance_transform(n, Transform3D(Basis(), Vector3(side * ROW_X, RACK_H * 0.5, z)))
			var facing := Basis(Vector3.UP, -side * PI * 0.5)   # quad normal points into the aisle
			fronts.set_instance_transform(n, Transform3D(facing, Vector3(side * (FRONT_X - 0.004), RACK_H * 0.5, z)))
			n += 1
			if i % 4 == 1:
				_rack_label(side, z, "HALL A · ROW %s · %d" % ["C" if side < 0 else "D", 140 + i])

	for mm in [bodies, fronts]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		visual.add_child(mmi)


func _rack_label(side: float, z: float, text: String) -> void:
	var facing := Basis(Vector3.UP, -side * PI * 0.5)
	var sticker := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.042)
	sticker.mesh = quad
	sticker.material_override = _mat(Color(0.62, 0.62, 0.58), 0.9)
	sticker.transform = Transform3D(facing, Vector3(side * (FRONT_X - 0.008), 2.085, z))
	visual.add_child(sticker)
	var label := Label3D.new()
	label.text = text
	label.font = load("res://fonts/IBMPlexMono-Medium.ttf")
	label.font_size = 48
	label.pixel_size = 0.00042
	label.modulate = Color(0.05, 0.05, 0.05)
	label.outline_size = 0
	label.shaded = true
	label.transform = Transform3D(facing, Vector3(side * (FRONT_X - 0.011), 2.085, z))
	visual.add_child(label)


func _build_overhead() -> void:
	var z_mid := aisle_len * 0.5
	# cable tray down the middle, two runs of yellow fibre on top of it
	_box(Vector3(0, 2.86, z_mid), Vector3(0.6, 0.04, aisle_len), _mat(Color(0.1, 0.1, 0.11), 0.5, 0.5))
	var yellow := _mat(Color(0.85, 0.58, 0.04), 0.5)
	for side in [-1.0, 1.0]:
		var tube := CylinderMesh.new()
		tube.top_radius = 0.05
		tube.bottom_radius = 0.05
		tube.height = aisle_len
		tube.radial_segments = 10
		tube.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = tube
		mi.material_override = yellow
		mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(side * 0.13, 2.925, z_mid))
		visual.add_child(mi)

	# a spool of fibre slack above every rack, so every customer gets the same length
	var torus := TorusMesh.new()
	torus.inner_radius = 0.154
	torus.outer_radius = 0.226
	torus.rings = 20
	torus.ring_segments = 8
	torus.material = yellow
	var spools := MultiMesh.new()
	spools.transform_format = MultiMesh.TRANSFORM_3D
	spools.mesh = torus
	spools.instance_count = RACKS * 2
	var n := 0
	var upright := Basis(Vector3.FORWARD, PI * 0.5)
	for side in [-1.0, 1.0]:
		for i in RACKS:
			spools.set_instance_transform(n, Transform3D(upright, Vector3(side * 1.305, 2.62, (i + 0.5) * RACK_W)))
			n += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = spools
	visual.add_child(mmi)


func _build_strips() -> void:
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
		_box(Vector3(0, 3.23, z), Vector3(1.6, 0.06, 0.14), strip_mat)
		var light := OmniLight3D.new()
		light.light_color = STRIP_COLOUR
		light.light_energy = 3.4
		light.omni_range = 7.5
		light.omni_attenuation = 1.3
		light.light_specular = 0.6
		light.position = Vector3(0, 3.0, z)
		add_child(light)
		# lit air under the fitting
		var haze := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(2.6, 3.2)
		haze.mesh = quad
		haze.material_override = haze_mat
		haze.position = Vector3(0, 1.62, z)
		haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(haze)


## The Compatibility renderer has no screen-space reflections, so the floor is a real mirror:
## the hall is drawn a second time upside down beneath a partly transparent floor.
func _build_mirror() -> void:
	var mirror := visual.duplicate()
	mirror.scale = Vector3(1, -1, 1)
	add_child(mirror)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(load("res://scripts/player.gd"))
	player.position = Vector3(0, 0.02, -0.6)
	player.rotation.y = PI   # face down the aisle (+z)
	add_child(player)


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
	hud_hint.text = "CLICK TO START\n\nWASD move  ·  Shift jog  ·  Ctrl crouch  ·  F torch  ·  F3 stats  ·  Esc release mouse"
	hud_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hud_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud_hint.position.y -= 48

	# reticle: one quiet dot
	var dot := ColorRect.new()
	dot.color = Color(0.93, 0.95, 0.97, 0.55)
	dot.size = Vector2(3, 3)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position -= Vector2(1.5, 1.5)
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


# ---------------------------------------------------------------- performance

## Keep the frame rate: drop the 3D resolution a step when frames run long,
## raise it again after a sustained stretch of headroom.
func _adapt_resolution(delta: float) -> void:
	if delta > 0.4:
		return
	if delta > 1.0 / 45.0:
		_slow_t += delta
		_fast_t = 0.0
	elif delta < 1.0 / 58.0:
		_fast_t += delta
		_slow_t = maxf(0.0, _slow_t - delta)
	if _slow_t > 1.0 and _scale_i < _scale_steps.size() - 1:
		_scale_i += 1
		_slow_t = 0.0
		get_viewport().scaling_3d_scale = _scale_steps[_scale_i]
	elif _fast_t > 8.0 and _scale_i > 0:
		_scale_i -= 1
		_fast_t = 0.0
		get_viewport().scaling_3d_scale = _scale_steps[_scale_i]


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
			player.position = Vector3(0.0, 0.02, 0.4)
		"low":
			player.position = Vector3(-0.1, 0.02, 3.0)
			player.set_physics_process(false)
			player.camera.position.y = 0.45
			player.camera.rotation.x = 0.08
		"rack":
			player.position = Vector3(0.35, 0.02, 8.0)
			player.rotation.y = PI + 1.15
		"torch":
			player.position = Vector3(0.0, 0.02, 0.4)
			player.torch.visible = true
			for n in get_children():
				if n is OmniLight3D and n.light_color == STRIP_COLOUR:
					n.visible = false
	await get_tree().create_timer(1.5).timeout
	print("draw calls: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), "  primitives: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	get_tree().quit()
