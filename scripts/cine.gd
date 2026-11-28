extends Node
## Cutscenes. A cutscene is a list of shots; each shot moves a second camera from one
## place to another while a line of text sits under the picture. Any key or a tap skips.
##
## A shot is a Dictionary:
##   from, to      camera position at the start and end (Vector3)
##   look, look_to what the camera looks at (look_to is optional)
##   secs          how long the shot lasts
##   text          the caption
##   all           true to draw every room, for shots that see through doorways
##   start         Callable run when the shot begins
##   tick          Callable(progress 0..1) run every frame

var game: Node
var cam: Camera3D
var playing := false
var show_all := false

var _skip := false
var _age := 0.0
var _bar := 0.0
var _top: ColorRect
var _bottom: ColorRect
var _caption: Label
var _hint: Label


func build(g: Node, hud: CanvasLayer, mono: Font) -> void:
	game = g
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 80.0
	g.world.add_child(cam)
	_top = ColorRect.new()
	_bottom = ColorRect.new()
	for r: ColorRect in [_top, _bottom]:
		r.color = Color(0.012, 0.016, 0.02)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(r)
	_caption = Label.new()
	_caption.add_theme_font_override("font", mono)
	_caption.add_theme_font_size_override("font_size", 17)
	_caption.add_theme_color_override("font_color", Color(0.93, 0.95, 0.97))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_caption)
	_hint = Label.new()
	_hint.add_theme_font_override("font", mono)
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Color(0.4, 0.42, 0.46))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_hint)


func _process(delta: float) -> void:
	_bar = move_toward(_bar, 1.0 if playing else 0.0, delta * 2.5)
	var size: Vector2 = get_viewport().get_visible_rect().size
	var h := size.y * 0.115 * _bar
	_top.visible = _bar > 0.0
	_bottom.visible = _bar > 0.0
	_top.position = Vector2.ZERO
	_top.size = Vector2(size.x, h)
	_bottom.position = Vector2(0, size.y - h)
	_bottom.size = Vector2(size.x, h)
	_caption.visible = playing
	_caption.position = Vector2(size.x * 0.12, size.y - size.y * 0.115)
	_caption.size = Vector2(size.x * 0.76, size.y * 0.115)
	_hint.visible = playing and _age > 2.0
	_hint.text = "TAP  skip" if game.touch.active else "SPACE  skip"
	_hint.position = Vector2(size.x - 130, 16)
	if playing:
		_age += delta


func skip() -> void:
	if playing and _age > 0.7:
		_skip = true


## Play a list of shots. The frame opens on the first shot and closes after the last.
func play(shots: Array) -> void:
	if shots.is_empty() or (game.test_mode and not game.playtest):
		return
	playing = true
	_skip = false
	_age = 0.0
	cam.make_current()
	var first := true
	for s: Dictionary in shots:
		if _skip:
			break
		show_all = s.get("all", false)
		cam.fov = s.get("fov", 50.0)
		if s.has("start"):
			(s["start"] as Callable).call()
		var from: Vector3 = s["from"]
		var to: Vector3 = s.get("to", from)
		var look: Vector3 = s["look"]
		var look_to: Vector3 = s.get("look_to", look)
		var secs: float = s.get("secs", 5.0)
		_caption.text = s.get("text", "")
		cam.position = from
		cam.look_at(look)
		if first:
			first = false
			game.fade(0.0, 0.9)
		else:
			game.sound.play("tick", -16.0, 0.6)
		var t := 0.0
		while t < secs and not _skip:
			var k := t / secs
			var e := k * k * (3.0 - 2.0 * k)
			cam.position = from.lerp(to, e)
			cam.look_at(look.lerp(look_to, e))
			if s.has("tick"):
				(s["tick"] as Callable).call(k)
			await get_tree().process_frame
			t += get_process_delta_time()
		if s.has("tick"):
			(s["tick"] as Callable).call(1.0)
	_caption.text = ""
	await game.fade(1.0, 0.45)
	show_all = false
	playing = false
	game.player.camera.make_current()
