extends Control
## Touch controls. Nothing is drawn until the screen is first touched. The left thumb is a
## floating stick, the right thumb looks around, and a few round buttons do the rest.
## Consoles, the cameras, the pause menu and the title get plain buttons to tap.

const RING := Color(0.93, 0.95, 0.97, 0.3)
const FILL := Color(0.93, 0.95, 0.97, 0.07)
const HOT := Color(1.0, 0.7, 0.28, 0.9)

var game: Node
var active := false
var paused := false
var title_choice := false     # the title is showing BEGIN and CONTINUE buttons

var _font: Font
var _buttons: Array = []      # {id, rect, label, round, hot}
var _move_i := -1
var _move_from := Vector2.ZERO
var _move_at := Vector2.ZERO
var _look_i := -1


func build(g: Node, mono: Font) -> void:
	game = g
	_font = mono
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if not active:
		return
	_layout()
	queue_redraw()
	var pl: CharacterBody3D = game.player
	if _move_i < 0:
		pl.touch_move = Vector2.ZERO
	else:
		var v := (_move_at - _move_from) / 70.0
		pl.touch_move = v.limit_length(1.0)


func _round(id: String, centre: Vector2, radius: float, label: String, hot := false) -> void:
	_buttons.append({"id": id, "rect": Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0), "label": label, "round": true, "hot": hot})


func _flat(id: String, rect: Rect2, label: String, hot := false) -> void:
	_buttons.append({"id": id, "rect": rect, "label": label, "round": false, "hot": hot})


func _layout() -> void:
	_buttons.clear()
	var s := size
	var pl: CharacterBody3D = game.player
	if game.ending_ready():
		return
	if not game.started:
		if title_choice and not game.loading:
			_flat("begin", Rect2(84, 320, 420, 64), "BEGIN THE NIGHT SHIFT", true)
			_flat("continue", Rect2(84, 400, 420, 64), "CONTINUE")
		return
	if game.cine.playing:
		return
	if game.terminal.is_open:
		var n: int = game.terminal.choice_count()
		var w := 96.0
		var x := (s.x - (n + 1) * (w + 12.0)) * 0.5
		for i in n:
			_flat("choice%d" % i, Rect2(x + i * (w + 12.0), s.y - 84, w, 60), str(i + 1), true)
		_flat("close", Rect2(x + n * (w + 12.0), s.y - 84, w, 60), "CLOSE")
		return
	if game.cctv.is_open:
		_flat("close", Rect2(s.x * 0.5 - 110, s.y - 78, 220, 56), "STEP AWAY")
		return
	if paused:
		var x := s.x * 0.5 - 190.0
		var y := s.y * 0.5 - 150.0
		_flat("resume", Rect2(x, y, 380, 60), "BACK TO THE SHIFT", true)
		var rows := [["sens", "LOOK SPEED  %.1f" % pl.sens], ["vol", "VOLUME  %d%%" % int(round(game.sound.volume * 100.0))], ["rows", "PIXEL SIZE  %d" % game.pixel_setting()]]
		for i in rows.size():
			var yy := y + 78.0 + i * 68.0
			_flat(rows[i][0] + "-", Rect2(x, yy, 60, 56), "-")
			_flat("", Rect2(x + 68, yy, 244, 56), rows[i][1])
			_flat(rows[i][0] + "+", Rect2(x + 320, yy, 60, 56), "+")
		return
	_round("pause", Vector2(s.x - 48, 48), 24, "II")
	if game.story.have_handheld:
		_round("handheld", Vector2(s.x - 62, 132), 34, "PDA", not game.handheld.unread.is_empty())
	if game.handheld.raised:
		_round("page", Vector2(s.x - 62, 220), 34, "NEXT", true)
		return
	_round("use", Vector2(s.x - 110, s.y - 150), 54, "USE", pl.target != null)
	_round("torch", Vector2(s.x - 228, s.y - 92), 36, "TORCH", pl.torch.visible)
	_round("jog", Vector2(s.x - 222, s.y - 208), 36, "JOG", pl.touch_jog)
	_round("crouch", Vector2(s.x - 100, s.y - 272), 36, "DUCK", pl.touch_crouch)


func _draw() -> void:
	if not active:
		return
	for b: Dictionary in _buttons:
		var r: Rect2 = b["rect"]
		var c: Color = HOT if b["hot"] else RING
		if b["round"]:
			var mid := r.get_center()
			draw_circle(mid, r.size.x * 0.5, FILL)
			draw_arc(mid, r.size.x * 0.5, 0.0, TAU, 40, c, 2.0)
		else:
			draw_rect(r, Color(0.02, 0.025, 0.03, 0.82), true)
			if b["id"] != "":
				draw_rect(r, c, false, 1.5)
		var text: String = b["label"]
		var fs := 13 if text.length() > 3 else 15
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, r.get_center() + Vector2(-tw * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.93, 0.95, 0.97, 0.9) if not b["hot"] else HOT)
	if _move_i >= 0:
		draw_arc(_move_from, 70.0, 0.0, TAU, 48, RING, 2.0)
		draw_circle(_move_from + (_move_at - _move_from).limit_length(70.0), 26.0, Color(0.93, 0.95, 0.97, 0.22))


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			if not active:
				active = true
				game.on_touch_mode()
				_layout()
			if _on_press(touch.index, touch.position):
				get_viewport().set_input_as_handled()
		else:
			if touch.index == _move_i:
				_move_i = -1
			if touch.index == _look_i:
				_look_i = -1
		return
	var drag := event as InputEventScreenDrag
	if drag != null and active:
		if drag.index == _move_i:
			_move_at = drag.position
		elif drag.index == _look_i:
			game.player.look(drag.relative * 2.6)


## Returns true when the touch was used here and should go no further.
func _on_press(index: int, at: Vector2) -> bool:
	if game.cine.playing:
		game.cine.skip()
		return true
	for b: Dictionary in _buttons:
		if b["id"] != "" and (b["rect"] as Rect2).grow(8.0).has_point(at):
			_tap(b["id"])
			return true
	if not game.started or game.ending_ready():
		return false   # the title and the endings take a tap anywhere
	if paused or game.terminal.is_open or game.cctv.is_open:
		if game.terminal.is_open:
			game.terminal.finish_typing()
		return true
	if at.x < size.x * 0.42:
		if _move_i < 0:
			_move_i = index
			_move_from = at
			_move_at = at
	elif _look_i < 0:
		_look_i = index
	return true


func _tap(id: String) -> void:
	var pl: CharacterBody3D = game.player
	game.sound.play("tick", -12.0, 1.4)
	match id:
		"begin":
			game.begin(false)
		"continue":
			game.begin(true)
		"use":
			if not pl.frozen:
				pl.use_target()
		"torch":
			if not pl.frozen:
				pl.toggle_torch()
		"jog":
			pl.touch_jog = not pl.touch_jog
			pl.touch_crouch = false
		"crouch":
			pl.touch_crouch = not pl.touch_crouch
			pl.touch_jog = false
		"handheld":
			game.toggle_handheld()
		"page":
			game.handheld.next_page()
		"pause":
			paused = true
		"resume":
			paused = false
		"close":
			if game.terminal.is_open:
				game.terminal.close()
			elif game.cctv.is_open:
				game.cctv.close()
		"sens-", "sens+":
			game.change_setting("sens", 1 if id.ends_with("+") else -1)
		"vol-", "vol+":
			game.change_setting("vol", 1 if id.ends_with("+") else -1)
		"rows-", "rows+":
			game.change_setting("rows", 1 if id.ends_with("+") else -1)
		_:
			if id.begins_with("choice"):
				game.terminal.choose(int(id.trim_prefix("choice")))
