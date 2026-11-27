extends Control
## A console session: text on a screen and a short list of numbered commands.
## Used for rack consoles (through the console cable), wall panels and notes.

var game: Node
var is_open := false
var _panel: Panel
var _title: Label
var _body: RichTextLabel
var _choices: Array = []     # [[label, Callable], ...]
var _text := ""
var _shown := 0.0
var _on_close := Callable()


func build(g: Node, mono: Font, mono_light: Font) -> void:
	game = g
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.012, 0.016, 0.02, 0.98)
	sb.border_color = Color(0.25, 0.27, 0.3)
	sb.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.size = Vector2(820, 540)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_title = Label.new()
	_title.add_theme_font_override("font", mono)
	_title.add_theme_font_size_override("font_size", 13)
	_title.add_theme_color_override("font_color", Color(0.5, 0.53, 0.57))
	_title.position = Vector2(28, 18)
	_panel.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = false
	_body.add_theme_font_override("normal_font", mono_light)
	_body.add_theme_font_override("bold_font", mono)
	_body.add_theme_font_size_override("normal_font_size", 15)
	_body.add_theme_font_size_override("bold_font_size", 15)
	_body.add_theme_color_override("default_color", Color(0.86, 0.88, 0.9))
	_body.position = Vector2(28, 52)
	_body.size = Vector2(764, 470)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_body)
	visible = false


## Show a screen. `choices` is a list of [label, Callable]; the Callable may call show() again.
func show_screen(title: String, text: String, choices: Array = [], on_close := Callable()) -> void:
	_title.text = title
	_choices = choices
	_text = text
	_shown = 0.0
	if on_close.is_valid() or not is_open:
		_on_close = on_close
	is_open = true
	visible = true
	game.player.frozen = true
	_render()


func _render() -> void:
	var t := _text + "\n\n"
	for i in _choices.size():
		t += "[b]%d[/b]  %s\n" % [i + 1, _choices[i][0]]
	t += "[color=#7f8791]%s[/color]" % ("\nE  unplug" if not _choices.is_empty() else "\nE  close")
	_body.text = t
	_body.visible_characters = int(_shown)


func _process(delta: float) -> void:
	if not is_open:
		return
	_panel.position = (size - _panel.size) * 0.5
	var total := _body.get_total_character_count()
	if _shown < total:
		_shown = minf(total, _shown + delta * 420.0)
		_body.visible_characters = int(_shown)
	else:
		_body.visible_characters = -1


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	game.player.frozen = false
	var cb := _on_close
	_on_close = Callable()
	if cb.is_valid():
		cb.call()


## Returns true if the key was used.
func key(event: InputEventKey) -> bool:
	if not is_open:
		return false
	if _shown < _body.get_total_character_count():
		_shown = 1e9   # any key finishes the typing
		return true
	var n := event.physical_keycode - KEY_1
	if n >= 0 and n < _choices.size():
		game.sound.play("tick", -8.0, 1.3)
		(_choices[n][1] as Callable).call()
		return true
	if event.physical_keycode in [KEY_E, KEY_Q, KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
		close()
		return true
	return true
