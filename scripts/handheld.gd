extends Control
## The technician's handheld: tickets, the floor plan, the door log, messages and notes.
## It rises from the corner of the view; the building keeps running while you read it.

const PAGES := ["TICKETS", "PLAN", "DOOR LOG", "MESSAGES", "NOTES"]
const W := 400.0
const H := 600.0
const AMBER := "#ffb347"
const DIM := "#7f8791"

var game: Node
var foot: Label
var raised := false
var page := 0
var unread := {}        # page index -> true

var _panel: Panel
var _head: Label
var _tabs: Label
var _body: RichTextLabel
var _plan: Control
var _rise := 0.0


func build(g: Node, mono: Font, mono_light: Font) -> void:
	game = g
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.04, 0.046, 0.97)
	sb.border_color = Color(0.2, 0.21, 0.23)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.size = Vector2(W, H)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_head = Label.new()
	_head.add_theme_font_override("font", mono)
	_head.add_theme_font_size_override("font_size", 22)
	_head.position = Vector2(24, 18)
	_panel.add_child(_head)
	_tabs = Label.new()
	_tabs.add_theme_font_override("font", mono)
	_tabs.add_theme_font_size_override("font_size", 11)
	_tabs.add_theme_color_override("font_color", Color(0.5, 0.53, 0.57))
	_tabs.position = Vector2(24, 52)
	_panel.add_child(_tabs)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = false
	_body.add_theme_font_override("normal_font", mono_light)
	_body.add_theme_font_override("bold_font", mono)
	_body.add_theme_font_size_override("normal_font_size", 13)
	_body.add_theme_font_size_override("bold_font_size", 13)
	_body.add_theme_color_override("default_color", Color(0.86, 0.88, 0.9))
	_body.position = Vector2(24, 84)
	_body.size = Vector2(W - 48, H - 130)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_body)

	_plan = Control.new()
	_plan.position = Vector2(24, 96)
	_plan.size = Vector2(W - 48, 330)
	_plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plan.draw.connect(_draw_plan)
	_panel.add_child(_plan)

	foot = Label.new()
	foot.add_theme_font_override("font", mono)
	foot.add_theme_font_size_override("font_size", 11)
	foot.add_theme_color_override("font_color", Color(0.4, 0.42, 0.46))
	foot.text = "TAB or R  next page   ·   Q  put away"
	foot.position = Vector2(24, H - 34)
	_panel.add_child(foot)
	visible = false


func toggle() -> void:
	raised = not raised
	if raised:
		foot.visible = not game.touch.active
		# open on whatever is new
		for i in PAGES.size():
			if unread.has(i):
				page = i
				break
		unread.erase(page)
		refresh()


func next_page() -> void:
	page = (page + 1) % PAGES.size()
	unread.erase(page)
	refresh()


func mark(p: int) -> void:
	if raised and page == p:
		refresh()
	else:
		unread[p] = true


func _process(delta: float) -> void:
	_rise = move_toward(_rise, 1.0 if raised else 0.0, delta * 5.0)
	visible = _rise > 0.0
	if not visible:
		return
	var ease_v := 1.0 - pow(1.0 - _rise, 3.0)
	var k := minf(1.0, (size.y - 16.0) / (H + 24.0))
	_panel.scale = Vector2(k, k)
	# on a touch screen the round buttons keep the right-hand edge
	var edge := 136.0 if game.touch.active else 36.0
	_panel.position = Vector2(size.x - W * k - edge, size.y - (H + 24.0) * k * ease_v + 30.0 * (1.0 - ease_v))
	_panel.rotation = (1.0 - ease_v) * 0.12 - 0.012
	_head.text = "%s   %s" % [game.clock_text(), PAGES[page]]
	if page == 1:
		_plan.queue_redraw()


func refresh() -> void:
	var st: Node = game.story
	var tabs := ""
	for i in PAGES.size():
		tabs += ("[%s]" if i == page else " %s ") % PAGES[i].substr(0, 4) + ("*" if unread.has(i) else " ")
	_tabs.text = tabs
	_plan.visible = page == 1
	var t := ""
	match page:
		0:
			if st.tickets.is_empty():
				t = "[color=%s]No tickets.[/color]" % DIM
			for i in range(st.tickets.size() - 1, -1, -1):
				var tk: Dictionary = st.tickets[i]
				if tk["open"]:
					t += "[b]#%s  OPEN[/b]\n[b]%s[/b]\n%s\n\n" % [tk["id"], tk["title"], tk["body"]]
				else:
					t += "[color=%s]#%s  closed   %s[/color]\n\n" % [DIM, tk["id"], tk["title"]]
		1:
			t = "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n[color=%s]HALDEN DC-3 · GROUND FLOOR\nHall A rows A to F · Hall B rows A to F[/color]" % DIM
		2:
			if not st.flags.has("log"):
				t = "[color=%s]DOOR LOG\nNo access. Ask the operations desk.[/color]" % DIM
			else:
				var lines: Array = st.log.duplicate()
				lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
				var from := maxi(0, lines.size() - 24)
				t = "[color=%s]BADGE 0417 · ALL DOORS[/color]\n" % DIM
				for i in range(from, lines.size()):
					var e: Dictionary = lines[i]
					var line := "%s  %s" % [game.clock_text(e["t"]), e["text"]]
					match e["kind"]:
						"pred", "true", "ghost":
							t += "[color=%s]%s[/color]\n" % [AMBER, line]
						"void":
							t += "[color=%s][s]%s[/s]  NO RECORD[/color]\n" % [DIM, line]
						_:
							t += line + "\n"
		3:
			if st.messages.is_empty():
				t = "[color=%s]No messages.[/color]" % DIM
			var from := maxi(0, st.messages.size() - 9)
			for i in range(from, st.messages.size()):
				var m: Dictionary = st.messages[i]
				if m["who"] == "you":
					t += "[right][color=%s]%s  you[/color]\n%s[/right]\n\n" % [DIM, game.clock_text(m["t"]), m["text"]]
				else:
					t += "[color=%s]OPS DESK  %s[/color]\n%s\n\n" % [DIM, game.clock_text(m["t"]), m["text"]]
		4:
			if st.notes.is_empty():
				t = "[color=%s]Nothing noted yet.[/color]" % DIM
			for id: String in st.notes:
				t += st.NOTES[id] + "\n\n"
	_body.text = t


func _draw_plan() -> void:
	var kit: RefCounted = game.kit
	var s := 7.6
	var off := Vector2(74, 96)
	var line := Color(0.5, 0.53, 0.57)
	var font: Font = _head.get_theme_font("font")
	for id: String in kit.rooms:
		if id == "plenum":
			continue
		var r: Rect2 = kit.rooms[id].rect
		var rr := Rect2(off + r.position * s, r.size * s)
		_plan.draw_rect(rr, line, false, 1.0)
		var name: String = {"dock": "DOCK", "mantrap": "TRAP", "security": "SECURITY", "mmr": "MEET-ME", "ups": "UPS",
			"corridor": "", "hall_a": "HALL A", "hall_b": "HALL B", "chillers": "CHILL"}[id]
		_plan.draw_string(font, rr.position + Vector2(4, 13), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, line)
	for id: String in kit.doors:
		var d: Node3D = kit.doors[id]
		_plan.draw_rect(Rect2(off + Vector2(d.position.x, d.position.z) * s - Vector2(3, 2), Vector2(6, 4)), Color(0.035, 0.04, 0.046), true)
	var p: Vector3 = game.player.global_position
	if p.y > -10.0:
		var blink := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)
		_plan.draw_circle(off + Vector2(p.x, p.z) * s, 3.5, Color(1, 1, 1, blink))
	else:
		_plan.draw_string(font, Vector2(0, 322), "NO POSITION FIX", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.7, 0.28))
