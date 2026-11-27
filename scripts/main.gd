extends Node3D
## Cold Aisle. This file is the frame around the game: the low-resolution 3D view and its
## lens, the HUD, input, the title and pause screens, and the per-frame bookkeeping of
## which room you are in. The building is built by build.gd; the night is run by story.gd.
##
## The 3D world is drawn into a small SubViewport and scaled up with hard pixels.
## Text (handheld, consoles, prompts) is drawn at full resolution on top.

const Kit := preload("res://scripts/build.gd")
const PIXEL_ROWS: Array[int] = [180, 240, 300, 360, 540]
const SETTINGS_PATH := "user://settings.cfg"
const AMBER := Color(1.0, 0.7, 0.28)
const INK := Color(0.93, 0.95, 0.97)

var view: SubViewport
var world: Node3D
var kit: RefCounted
var player: CharacterBody3D
var story: Node
var sound: Node
var figure: Node3D
var double: Node3D          # the technician the cameras show in Act 3
var handheld: Control
var terminal: Control
var cctv: Control
var post_mat: ShaderMaterial
var env: Environment

var clock := 1320.0         # minutes since midnight of the day the shift began
var room := ""
var started := false
var paused := false
var hold := false           # a scripted moment is keeping the player still
var test_mode := false

var _rows_i := 1
var _show_all := false
var _lid := 0.0
var _mono: Font
var _mono_light: Font
var _hud: CanvasLayer
var _reticle: ColorRect
var _prompt: Label
var _toast: Label
var _toast_t := 0.0
var _notify: Label
var _notify_t := 0.0
var _banner: Label
var _card: Label
var _card_t := 0.0
var _fps: Label
var _title: Control
var _title_info: Label
var _pause: Label
var _ending: Control
var _ending_text: RichTextLabel
var _ending_ready := false


func _ready() -> void:
	_mono = load("res://fonts/IBMPlexMono-Medium.ttf")
	_mono_light = load("res://fonts/IBMPlexMono-Regular.ttf")
	_setup_input()
	_build_view()
	_build_environment()
	sound = Node.new()
	sound.set_script(load("res://scripts/sound.gd"))
	add_child(sound)
	kit = Kit.new()
	kit.build(self, world)
	_build_player()
	_build_lens_and_hud()
	story = Node.new()
	story.set_script(load("res://scripts/story.gd"))
	story.setup(self)
	add_child(story)
	_load_settings()
	get_viewport().size_changed.connect(_fit_view)
	_fit_view()
	if not _apply_test_args():
		_warm_up()


func clock_text(t := -1.0) -> String:
	var m := int(clock if t < 0.0 else t)
	return "%02d:%02d" % [int(m / 60) % 24, m % 60]


# ---------------------------------------------------------------- every frame

func _process(delta: float) -> void:
	paused = started and not test_mode and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	player.frozen = paused or hold or terminal.is_open or cctv.is_open or not started
	_pause.visible = paused and not _ending.visible
	if _pause.visible:
		_pause.text = "PAUSED\nclick to go back in\n\n[  ]   look speed   %.1f\n-  =   volume       %d%%\n1 to 5 pixel size   %d\nF3     frame stats" % [
			player.sens, int(round(sound.volume * 100.0)), _rows_i + 1]

	# which room, what can be seen from it, what it sounds like
	var now: String = kit.room_at(player.global_position)
	if now != "" and now != room:
		var before := room
		room = now
		sound.set_bed(kit.rooms[now].bed)
		if started:
			story.on_room(now, before)
	kit.show_rooms(room, _show_all)

	# reticle and the words under it
	var target: Object = player.target
	var words := ""
	if target != null and not player.frozen:
		if target.has_meta("door"):
			words = "E   badge reader · " + String((target.get_meta("door") as Node).title)
		else:
			words = "E   " + String(story.prompt_for(String(target.get_meta("use_id"))))
	_prompt.text = words
	var want := 10.0 if words != "" else 4.0
	_reticle.size = _reticle.size.lerp(Vector2(want, want), 1.0 - exp(-18.0 * delta))
	_reticle.position = get_viewport().get_visible_rect().size * 0.5 - _reticle.size * 0.5
	_reticle.visible = started and not player.frozen

	_toast_t -= delta
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_notify_t -= delta
	_notify.modulate.a = clampf(_notify_t, 0.0, 1.0) * (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.01))
	_card_t -= delta
	_card.modulate.a = clampf(_card_t * 0.7, 0.0, 1.0)
	if _fps.visible:
		_fps.text = "%d fps · %d x %d · %d draws · %s" % [
			Engine.get_frames_per_second(), view.size.x, view.size.y,
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)), room]


func footstep(jogging: bool, crouching: bool) -> void:
	var perforated := false
	if room == "hall_a" or room == "hall_b":
		var hall := "a" if room == "hall_a" else "b"
		for a in 3:
			if absf(player.global_position.x - kit.aisle_x(hall, a)) < 0.66:
				perforated = true
	sound.step(perforated, jogging, crouching)


func show_all_rooms(on: bool) -> void:
	_show_all = on


# ---------------------------------------------------------------- input

func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jog": [KEY_SHIFT], "crouch": [KEY_CTRL, KEY_C], "torch": [KEY_F],
		"interact": [KEY_E], "handheld": [KEY_Q], "page": [KEY_TAB, KEY_R],
		"toggle_stats": [KEY_F3],
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code: int in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code as Key
			InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var pressed := key != null and key.pressed and not key.echo
	var click: bool = event is InputEventMouseButton and event.pressed

	if _ending.visible:
		if _ending_ready and (click or (pressed and key.physical_keycode in [KEY_ENTER, KEY_SPACE])):
			get_tree().reload_current_scene()
		return
	if not started:
		if click or (pressed and key.physical_keycode in [KEY_ENTER, KEY_SPACE]):
			_begin(false)
		elif pressed and key.physical_keycode == KEY_C and story.has_save() > 0:
			_begin(true)
		return
	if pressed and terminal.is_open:
		terminal.key(key)
		return
	if pressed and cctv.is_open:
		if key.physical_keycode in [KEY_E, KEY_Q, KEY_ESCAPE]:
			cctv.close()
		return
	if pressed:
		var code := key.physical_keycode
		if event.is_action_pressed("toggle_stats"):
			_fps.visible = not _fps.visible
		elif code >= KEY_1 and code < KEY_1 + PIXEL_ROWS.size():
			# number keys pick the pixel size: 1 is the chunkiest
			_rows_i = code - KEY_1
			_fit_view()
			_save_settings()
		elif event.is_action_pressed("handheld") and story.have_handheld:
			handheld.toggle()
			sound.play("tick", -10.0, 1.2)
		elif event.is_action_pressed("page") and handheld.raised:
			handheld.next_page()
			sound.play("tick", -12.0, 1.5)
		elif code == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif paused and code in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
			player.sens = clampf(player.sens + (0.1 if code == KEY_BRACKETRIGHT else -0.1), 0.3, 3.0)
			_save_settings()
		elif paused and code in [KEY_MINUS, KEY_EQUAL]:
			sound.set_volume(sound.volume + (0.1 if code == KEY_EQUAL else -0.1))
			_save_settings()
		elif not paused:
			player.handle_input(event)
		return
	if click and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not paused:
		player.handle_input(event)


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	player.sens = float(cf.get_value("s", "sens", 1.0))
	sound.set_volume(float(cf.get_value("s", "volume", 0.8)))
	_rows_i = clampi(int(cf.get_value("s", "rows", 1)), 0, PIXEL_ROWS.size() - 1)


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("s", "sens", player.sens)
	cf.set_value("s", "volume", sound.volume)
	cf.set_value("s", "rows", _rows_i)
	cf.save(SETTINGS_PATH)


# ---------------------------------------------------------------- title

## Draw every room once behind a closed eyelid, so that shaders compile before play
## starts and not the first time you open a door. Then show the title over Hall A.
func _warm_up() -> void:
	_set_lid(1.0)
	_show_all = true
	player.camera.far = 160.0
	player.global_position = Vector3(44.0, 14.0, -26.0)
	player.camera.look_at(Vector3(12.0, -6.0, 28.0))
	player.torch.visible = true
	await get_tree().create_timer(0.35).timeout
	player.torch.visible = false
	player.camera.far = 80.0
	player.camera.rotation = Vector3.ZERO
	_show_all = false
	player.place(Vector3(0.0, 0.02, 0.4), PI)
	var n: int = story.has_save()
	_title_info.text = "CLICK   begin the night shift" + ("\nC       continue from Act %d · %s" % [n, story.ACT_NAME[n]] if n > 0 else "")
	_title.visible = true
	var tw := create_tween()
	tw.tween_method(_set_lid, 1.0, 0.0, 1.2)


func _begin(resume: bool) -> void:
	started = true
	_title.visible = false
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_lid(1.0)
	if resume:
		story.continue_game()
	else:
		story.new_game()
	var tw := create_tween()
	tw.tween_method(_set_lid, 1.0, 0.0, 1.6)


# ---------------------------------------------------------------- things the story asks for

func toast(text: String, secs := 6.0) -> void:
	_toast.text = text
	_toast_t = secs


func notify(text: String) -> void:
	_notify.text = "●  %s   ·   Q" % text
	_notify_t = 7.0
	sound.play("tone", -4.0)


func banner(text: String) -> void:
	_banner.text = text


func act_card(n: int, title: String) -> void:
	_card.text = "ACT %d\n%s\n%s" % [n, title, clock_text()]
	_card_t = 6.0


func dim(exposure: float) -> void:
	env.tonemap_exposure = exposure


func set_noise(amount: float) -> void:
	post_mat.set_shader_parameter("noise", amount)


func _set_lid(v: float) -> void:
	_lid = v
	post_mat.set_shader_parameter("lid", v)


## The frame closes like an eyelid, `mid` happens in the dark, and it opens again.
func blink(mid: Callable, dark := 0.3) -> void:
	var tw := create_tween()
	tw.tween_method(_set_lid, _lid, 1.0, 0.35)
	await tw.finished
	mid.call()
	await get_tree().create_timer(dark).timeout
	tw = create_tween()
	tw.tween_method(_set_lid, 1.0, 0.0, 0.6)
	await tw.finished


func show_ending(lines: Array) -> void:
	handheld.raised = false
	terminal.close()
	sound.play("chord")
	var tw := create_tween()
	tw.tween_method(_set_lid, _lid, 1.0, 2.2)
	await tw.finished
	sound.silenced = true
	_ending.visible = true
	var text := ""
	for l: String in lines:
		text += l + "\n\n"
		_ending_text.text = text
		await get_tree().create_timer(2.4 if l != "" else 0.6).timeout
	_ending_text.text = text + "[color=#7f8791]click to return to the title[/color]"
	_ending_ready = true


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


func _build_environment() -> void:
	env = Environment.new()
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


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(load("res://scripts/player.gd"))
	player.game = self
	world.add_child(player)
	player.place(Vector3(0.0, 0.02, 0.4), PI)

	figure = Node3D.new()
	figure.set_script(load("res://scripts/figure.gd"))
	figure.game = self
	world.add_child(figure)

	# the technician on camera 4: lit, carrying a torch, wearing your badge number
	double = Node3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.2
	body.height = 1.75
	var b := MeshInstance3D.new()
	b.mesh = body
	b.material_override = kit.mat(Color(0.12, 0.13, 0.15), 0.8)
	b.position.y = 0.88
	b.layers = 1 << 5
	double.add_child(b)
	var beam := SpotLight3D.new()
	beam.light_color = Color(0.86, 0.93, 1.0)
	beam.light_energy = 30.0
	beam.spot_range = 14.0
	beam.spot_angle = 30.0
	beam.position = Vector3(0.18, 1.45, -0.2)
	double.add_child(beam)
	double.visible = false
	world.add_child(double)


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

	_hud = CanvasLayer.new()
	_hud.layer = 2
	add_child(_hud)

	_reticle = ColorRect.new()
	_reticle.color = Color(0.93, 0.95, 0.97, 0.55)
	_reticle.size = Vector2(4, 4)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_reticle)

	_prompt = _label(13, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_prompt, Control.PRESET_CENTER, Vector2(0, 34))
	_toast = _label(15, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.custom_minimum_size = Vector2(760, 0)
	_anchor(_toast, Control.PRESET_CENTER_BOTTOM, Vector2(0, -70))
	_notify = _label(13, AMBER, HORIZONTAL_ALIGNMENT_RIGHT)
	_anchor(_notify, Control.PRESET_BOTTOM_RIGHT, Vector2(-36, -30))
	_banner = _label(22, AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_banner, Control.PRESET_CENTER_TOP, Vector2(0, 40))
	_card = _label(15, INK, HORIZONTAL_ALIGNMENT_LEFT)
	_card.position = Vector2(36, 30)
	_fps = _label(12, AMBER, HORIZONTAL_ALIGNMENT_LEFT)
	_anchor(_fps, Control.PRESET_BOTTOM_LEFT, Vector2(36, -30))
	_fps.visible = false

	handheld = Control.new()
	handheld.set_script(load("res://scripts/handheld.gd"))
	_hud.add_child(handheld)
	handheld.build(self, _mono, _mono_light)
	terminal = Control.new()
	terminal.set_script(load("res://scripts/terminal.gd"))
	_hud.add_child(terminal)
	terminal.build(self, _mono, _mono_light)
	cctv = Control.new()
	cctv.set_script(load("res://scripts/cctv.gd"))
	_hud.add_child(cctv)
	cctv.build(self, _mono)

	_pause = _label(15, INK, HORIZONTAL_ALIGNMENT_LEFT)
	_anchor(_pause, Control.PRESET_CENTER, Vector2(0, 0))
	_pause.visible = false

	# title
	_title = Control.new()
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.visible = false
	_hud.add_child(_title)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(shade)
	var name_l := _label(64, INK, HORIZONTAL_ALIGNMENT_LEFT, _title)
	name_l.text = "COLD AISLE"
	name_l.position = Vector2(80, 150)
	var sub := _label(14, Color(0.6, 0.63, 0.69), HORIZONTAL_ALIGNMENT_LEFT, _title)
	sub.text = "HALDEN DC-3  ·  NIGHT SHIFT  ·  22:00"
	sub.position = Vector2(84, 240)
	_title_info = _label(18, AMBER, HORIZONTAL_ALIGNMENT_LEFT, _title)
	_title_info.position = Vector2(84, 320)
	var keys := _label(13, Color(0.6, 0.63, 0.69), HORIZONTAL_ALIGNMENT_LEFT, _title)
	keys.text = "WASD   move            E     use, badge\nSHIFT  jog             Q     handheld\nCTRL   crouch          TAB   handheld page (or R)\nF      torch           ESC   pause, settings\n\nAbout twenty minutes. Sound on. Progress is kept at the start of each act."
	keys.position = Vector2(84, 440)

	# ending
	_ending = Control.new()
	_ending.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ending.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ending.visible = false
	_hud.add_child(_ending)
	var black := ColorRect.new()
	black.color = Color(0.012, 0.016, 0.02)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ending.add_child(black)
	_ending_text = RichTextLabel.new()
	_ending_text.bbcode_enabled = true
	_ending_text.scroll_active = false
	_ending_text.add_theme_font_override("normal_font", _mono_light)
	_ending_text.add_theme_font_size_override("normal_font_size", 17)
	_ending_text.add_theme_color_override("default_color", INK)
	_ending_text.position = Vector2(120, 110)
	_ending_text.size = Vector2(900, 560)
	_ending_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ending.add_child(_ending_text)


func _label(size: int, colour: Color, align: HorizontalAlignment, parent: Node = null) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _mono)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else _hud).add_child(l)
	return l


func _anchor(l: Label, preset: Control.LayoutPreset, offset: Vector2) -> void:
	l.set_anchors_and_offsets_preset(preset)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	if preset in [Control.PRESET_BOTTOM_RIGHT, Control.PRESET_TOP_RIGHT]:
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_TOP_LEFT]:
		l.grow_horizontal = Control.GROW_DIRECTION_END
	if preset in [Control.PRESET_BOTTOM_RIGHT, Control.PRESET_BOTTOM_LEFT, Control.PRESET_CENTER_BOTTOM]:
		l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if preset == Control.PRESET_CENTER_TOP:
		l.grow_vertical = Control.GROW_DIRECTION_END
	l.position += offset


# ---------------------------------------------------------------- tests

## Command-line helpers, after `--`:
##   --autotest=comply|defy|stay     play the whole night and check it can be finished
##   --act=N --at=x,y,z,yaw --out=f.png [--torch] [--handheld=PAGE] [--all]   render one still
func _apply_test_args() -> bool:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("walktest"):
		test_mode = true
		story.walktest()
		return true
	if args.has("autotest"):
		test_mode = true
		story.autotest(args["autotest"])
		return true
	if not args.has("out"):
		return false
	_shot(args)
	return true


func _shot(args: Dictionary) -> void:
	test_mode = true
	if args.has("title"):
		_warm_up()
		await get_tree().create_timer(3.0).timeout
		get_viewport().get_texture().get_image().save_png(args["out"])
		get_tree().quit()
		return
	started = true
	story.begin_act(int(args.get("act", "1")), true)
	_card_t = 0.0
	_toast_t = 0.0
	if args.has("at"):
		var v: PackedStringArray = args["at"].split(",")
		player.place(Vector3(float(v[0]), float(v[1]), float(v[2])), float(v[3]) if v.size() > 3 else 0.0)
		if v.size() > 4:
			player.camera.rotation.x = float(v[4])
	player.torch.visible = args.has("torch")
	if args.has("all"):
		_show_all = true
	if args.has("handheld"):
		story.have_handheld = true
		handheld.page = int(args["handheld"])
		handheld.toggle()
		handheld.page = int(args["handheld"])
		handheld.refresh()
	if args.has("figure"):
		var v2: PackedStringArray = args["figure"].split(",")
		figure.active = true
		figure.set_physics_process(false)
		figure.visible = true
		figure.position = Vector3(float(v2[0]), 0, float(v2[1]))
	if args.has("use"):
		await get_tree().create_timer(0.5).timeout
		story.on_use(args["use"])
	if args.has("ending"):
		story._ending(args["ending"])
	await get_tree().create_timer(float(args.get("wait", "1.5"))).timeout
	print("draw calls: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"  primitives: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"  view: ", view.size, "  room: ", room)
	get_viewport().get_texture().get_image().save_png(args["out"])
	get_tree().quit()
