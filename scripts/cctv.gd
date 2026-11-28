extends Control
## The camera wall at the security desk: six views, drawn small and slowly. That is both
## the look of a security monitor and the reason six extra views cost almost nothing.

const Kit := preload("res://scripts/build.gd")
const FEEDS := [
	["CAM 01  LOADING DOCK", Vector3(-8.7, 3.0, -11.7), Vector3(-4.5, 0.6, -8.0)],
	["CAM 02  CORRIDOR", Vector3(-8.7, 3.0, -4.3), Vector3(8.0, 0.4, -4.3)],
	["CAM 03  HALL A · AISLE 2", Vector3(0.0, 3.1, -2.3), Vector3(0.0, 0.4, 11.0)],
	["CAM 04  HALL B · AISLE 2", Vector3(Kit.HALL_B_X, 3.1, -2.3), Vector3(Kit.HALL_B_X, 0.4, 11.0)],
	["CAM 05  UPS ROOM", Vector3(18.5, 3.0, -11.7), Vector3(23.0, 0.6, -8.5)],
	["CAM 06  MEET-ME ROOM", Vector3(17.7, 3.0, -6.3), Vector3(12.5, 0.6, -10.5)],
]

var game: Node
var is_open := false
var _views: Array[SubViewport] = []
var _mats: Array[ShaderMaterial] = []
var _tags: Array[Label] = []
var _grid: Control
var _next := 0
var _tick := 0.0
var _stamp: Label


func build(g: Node, mono: Font) -> void:
	game = g
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.01, 0.012)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)
	var shader: Shader = load("res://shaders/cctv.gdshader")
	for i in FEEDS.size():
		var vp := SubViewport.new()
		vp.size = Vector2i(192, 144)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.msaa_3d = Viewport.MSAA_DISABLED
		game.view.add_child(vp)   # inside the 3D view, so it sees the same world
		var cam := Camera3D.new()
		cam.fov = 78.0
		cam.far = 45.0
		vp.add_child(cam)
		cam.look_at_from_position(FEEDS[i][1], FEEDS[i][2])
		_views.append(vp)
		var rect := TextureRect.new()
		rect.texture = vp.get_texture()
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.size = Vector2(384, 288)
		rect.position = Vector2((i % 3) * 400, int(i / 3) * 316)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = shader
		rect.material = m
		_mats.append(m)
		_grid.add_child(rect)
		var lab := Label.new()
		lab.add_theme_font_override("font", mono)
		lab.add_theme_font_size_override("font_size", 12)
		lab.text = FEEDS[i][0]
		lab.position = rect.position + Vector2(8, 6)
		_grid.add_child(lab)
		var tag := Label.new()
		tag.add_theme_font_override("font", mono)
		tag.add_theme_font_size_override("font_size", 12)
		tag.add_theme_color_override("font_color", Color(1.0, 0.7, 0.28))
		tag.position = rect.position + Vector2(8, 264)
		_grid.add_child(tag)
		_tags.append(tag)
	_stamp = Label.new()
	_stamp.add_theme_font_override("font", mono)
	_stamp.add_theme_font_size_override("font_size", 12)
	_stamp.add_theme_color_override("font_color", Color(0.5, 0.53, 0.57))
	_stamp.position = Vector2(0, 612)
	_grid.add_child(_stamp)
	visible = false


func open() -> void:
	is_open = true
	visible = true
	game.player.frozen = true
	for m in _mats:
		m.set_shader_parameter("static_amt", 0.0)
	for t in _tags:
		t.text = ""


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	game.player.frozen = false
	game.sound.static_noise(false)
	game.story.on_cctv_closed()


func set_static(feed: int, amount: float) -> void:
	_mats[feed].set_shader_parameter("static_amt", amount)


func set_tag(feed: int, text: String) -> void:
	_tags[feed].text = text


func _process(delta: float) -> void:
	if not is_open:
		return
	var room := size - Vector2(0, 84.0 if game.touch.active else 0.0)
	var k := minf(1.0, minf(room.x / 1208.0, room.y / 648.0))
	_grid.scale = Vector2(k, k)
	_grid.position = (room - Vector2(1184, 632) * k) * 0.5
	_stamp.text = "HALDEN DC-3 · SECURITY · %s%s" % [game.clock_text(), "" if game.touch.active else "          E  step away"]
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.11
		_views[_next].render_target_update_mode = SubViewport.UPDATE_ONCE
		_next = (_next + 1) % _views.size()
