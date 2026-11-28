extends Node
## A test player. `playtest=comply|defy|stay` plays the whole night the way a person
## does: it holds the walk key, turns the view, badges readers, presses E on things and
## types at consoles. Nothing is teleported and no story function is called directly, so
## a wall in the wrong place, a prompt out of reach or a door that will not open stops it.

const Kit := preload("res://scripts/build.gd")

var game: Node
var story: Node
var kit: RefCounted
var pl: CharacterBody3D

var _nodes := {}     # name -> Vector2(x, z)
var _edges: Array = []   # [a, b, door]
var _stand := {}     # usable id -> Vector2 to stand on
var _dead := false
var _skip_t := 0.0


func run(g: Node, ending: String) -> void:
	game = g
	story = g.story
	kit = g.kit
	pl = g.player
	_build_map()
	var plan := _plan(ending)
	for i in plan.size():
		var s: Array = plan[i]
		print("  bot  act %d  %-10s %s" % [story.act, s[0], str(s.slice(1))])
		var ok: bool = await callv("_do_" + String(s[0]), s.slice(1))
		if not ok or _dead:
			if not _dead:
				_fail("step failed: " + str(s))
			return
	_release()
	print("PLAYTEST OK  ending=%s  defy=%d  caught=%d  clock=%s" % [ending, story.defy, story.caught_n, game.clock_text()])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.coldAisleTest = 'OK %s'" % ending, true)
	else:
		get_tree().quit()


func _fail(what: String) -> void:
	_dead = true
	_release()
	var p := pl.global_position
	print("PLAYTEST FAILED  %s  (act %d, step %s, room %s, at %.1f %.1f %.1f)" % [what, story.act, story.step, game.room, p.x, p.y, p.z])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.coldAisleTest = 'FAILED %s'" % what.replace("'", ""), true)
	else:
		get_tree().quit(1)


# ---------------------------------------------------------------- the night, as a list

func _plan(ending: String) -> Array:
	var defiant := ending != "comply"
	var bx := Kit.HALL_B_X
	var x := KEY_X   # any key finishes the typing on a console; X does nothing else
	var p: Array = [
		["start"],
		["travel", "c_trap"], ["step", "to_security"],
		["travel", "sec_d"],
		["use", "handover"], ["close"],
		["use", "handheld"], ["step", "swap"],
		["pages"],
		["travel", "a0_n", ["hall_a2"]],
		["use", "rack_a147"], ["until", "step", "return", 6.0],
		["travel", "sec_d"],
		["use", "desk_bin"], ["until", "act", 2, 30.0],
		["until", "flag", "hot", 60.0],
		["travel", "b0_n", ["hall_b2"]],
		["walk", Vector2(bx + 0.1, 4.03)], ["until", "step", "console", 25.0],
		["use", "rack_b07"], ["keys", [x, KEY_1, x, KEY_2, x, KEY_3, x, KEY_4, x, KEY_E]], ["step", "ups"],
		["travel", "ups_d", ["hall_b2" if defiant else "hall_b1"]],
		["use", "ups_log"], ["close"],
		["use", "breaker_b2"], ["step", "to_desk2"],
		["travel", "sec_d"],
		["use", "cctv"], ["until", "act", 3, 30.0], ["until", "flag", "cams_done", 40.0], ["keys", [KEY_E]], ["step", "fire_panel"],
		["travel", "a0_s", ["hall_a1" if defiant else "hall_a2"]],
		["use", "fire_panel_a"], ["step", "abort"], ["torch", true], ["jog", true],
		["travel", "a0_n"], ["jog", false],
		["use", "abort_a"], ["step", "chiller"],
		["travel", "ch_m", ["hall_a2" if defiant else "hall_a1"]],
		["use", "chiller2"], ["until", "act", 4, 40.0],
		["use", "note1"], ["close"], ["torch", false],
		["travel", "b1_s", ["hall_b1"]],
		["use", "hatch_b"], ["until", "room", "plenum", 8.0], ["torch", true],
		["crawl", "H", "M"], ["use", "hatch_m"], ["until", "room", "mmr", 8.0],
		["use", "note2"], ["close"], ["use", "panel7"], ["use", "damper"],
		["use", "hatch_mmr"], ["until", "room", "plenum", 8.0],
		["crawl", "M", "C"], ["crawl", "C", "N"], ["use", "note3"], ["close"],
		["crawl", "N", "C"], ["use", "hatch_c"], ["until", "act", 5, 40.0],
		["travel", "cage_c"], ["use", "console7"], ["keys", [x, KEY_1, x, KEY_2]],
	]
	if ending == "stay":
		p.append(["keys", [x, KEY_3]])
	else:
		p.append_array([["keys", [x, KEY_E]], ["travel", "cage_n"], ["use", "cage_gate"], ["torch", false]])
		if ending == "defy":
			p.append_array([["travel", "b0_n"], ["use", "epo_b"], ["torch", true], ["travel", "dock"], ["use", "dock_shutter"]])
		else:
			p.append(["travel", "trap"])
	p.append(["ending"])
	return p


func _build_map() -> void:
	var bx := Kit.HALL_B_X
	var ap := Kit.AISLE_PITCH
	var cz := -4.3
	var corridor := [["c_dock", -6.0], ["c_a1", -ap], ["c_trap", -0.5], ["c_sec", 5.0], ["c_a2", ap], ["c_b1", bx - ap],
		["c_mmr", 13.5], ["c_ups", 22.0], ["c_b2", bx + ap], ["c_ch", 30.0]]
	corridor.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	for i in corridor.size():
		_nodes[corridor[i][0]] = Vector2(corridor[i][1], cz)
		if i > 0:
			_edges.append([corridor[i - 1][0], corridor[i][0], ""])
	var more := {
		"dock_n": Vector2(-6.0, -7.4), "dock": Vector2(-6.0, -9.2), "dock_e": Vector2(-3.5, -9.0),
		"trap": Vector2(-0.5, -9.0), "trap_n": Vector2(-0.5, -7.4),
		"sec_d": Vector2(5.0, -7.4), "mmr_d": Vector2(13.5, -7.4), "ups_d": Vector2(22.0, -7.4),
		"ch": Vector2(30.0, -1.3), "ch_m": Vector2(31.6, 3.3),
		"cage_n": Vector2(bx + ap, 14.2), "cage_m": Vector2(bx + 6.5, 15.4), "cage_c": Vector2(bx + 6.5, 17.2),
		"cage_s": Vector2(bx + 6.5, 20.6), "cage": Vector2(bx + 4.4, 20.6),
	}
	for k: String in more:
		_nodes[k] = more[k]
	for h: Array in [["a", 0.0], ["b", bx]]:
		for a in 3:
			var n: String = h[0] + ["1", "0", "2"][a]
			var ax: float = h[1] + [-ap, 0.0, ap][a]
			_nodes[n + "_n"] = Vector2(ax, -1.3)
			if not (h[0] == "b" and a == 2):
				_nodes[n + "_s"] = Vector2(ax, Kit.AISLE_LEN + 1.3)
				_edges.append([n + "_n", n + "_s", ""])
		_edges.append([h[0] + "1_n", h[0] + "0_n", ""])
		_edges.append([h[0] + "0_n", h[0] + "2_n", ""])
		_edges.append([h[0] + "1_s", h[0] + "0_s", ""])
		_edges.append(["c_" + h[0] + "1", h[0] + "1_n", "hall_" + h[0] + "1"])
		_edges.append(["c_" + h[0] + "2", h[0] + "2_n", "hall_" + h[0] + "2"])
	_edges.append(["a0_s", "a2_s", ""])
	_edges.append_array([
		["c_dock", "dock_n", "dock_corr"], ["dock_n", "dock", ""], ["dock", "dock_e", ""], ["dock_e", "trap", "dock_mantrap"],
		["trap", "trap_n", ""], ["trap_n", "c_trap", "mantrap_corr"],
		["c_sec", "sec_d", "security"], ["c_mmr", "mmr_d", "mmr"], ["c_ups", "ups_d", "ups"],
		["c_ch", "ch", "chillers"], ["ch", "ch_m", ""],
		["b2_n", "cage_n", "#gate"], ["cage_n", "cage_m", ""], ["cage_m", "cage_c", ""], ["cage_c", "cage_s", ""], ["cage_s", "cage", ""],
	])
	_stand = {
		"handover": Vector2(6.2, -9.9), "handheld": Vector2(3.8, -9.9), "desk_bin": Vector2(7.9, -10.0), "cctv": Vector2(5.0, -10.0),
		"rack_a147": Vector2(0.1, 7.5 * Kit.RACK_W), "rack_b07": Vector2(bx + 0.1, 6.5 * Kit.RACK_W),
		"ups_log": Vector2(19.4, -8.0), "breaker_b2": Vector2(24.6, -9.0),
		"fire_panel_a": Vector2(2.0, Kit.HALL_Z1 - 1.3), "chiller2": Vector2(31.9, 2.8), "note1": Vector2(31.9, 4.4),
		"note2": Vector2(11.0 + 5 * Kit.RACK_W, -9.5), "panel7": Vector2(11.0 + 4 * Kit.RACK_W, -9.5),
		"damper": Vector2(16.8, -9.0), "hatch_mmr": Vector2(16.5, -8.4),
		"console7": Vector2(bx + 6.5, 17.2), "cage_gate": Vector2(bx + ap, 14.4), "dock_shutter": Vector2(-5.6, -10.3),
	}


# ---------------------------------------------------------------- hands

func _release() -> void:
	for a: String in ["move_forward", "jog", "crouch"]:
		Input.action_release(a)


func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _process(delta: float) -> void:
	# a person would watch a little of each cutscene and then skip it
	if game != null and game.cine.playing:
		_skip_t += delta
		if _skip_t > 2.5:
			_skip_t = 2.0
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_SPACE
			ev.pressed = true
			Input.parse_input_event(ev)
	else:
		_skip_t = 0.0


## Wait until the player can move again (a cutscene, a blink, waking on the floor).
func _ready_to_move() -> bool:
	var t := 0.0
	while pl.frozen or story._busy or game.cine.playing:
		_release()
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > 90.0:
			_fail("the player never got control back")
			return false
	return true


func _turn(yaw_err: float, pitch_err: float) -> void:
	var k: float = pl.MOUSE_SENS * pl.sens
	pl.look(Vector2(-clampf(yaw_err, -0.14, 0.14) / k, -clampf(pitch_err, -0.1, 0.1) / k))


## Walk to a point on the floor. False means something moved you (you were caught).
func _walk_to(goal: Vector2, tol := 0.18) -> bool:
	if not await _ready_to_move():
		return false
	var last := pl.global_position
	var t := 0.0
	var limit := 8.0 + Vector2(last.x - goal.x, last.z - goal.y).length() * 1.6
	while true:
		var p := pl.global_position
		if p.distance_to(last) > 2.5:
			_release()
			return false
		last = p
		var d := Vector2(goal.x - p.x, goal.y - p.z)
		if d.length() < tol:
			break
		if pl.frozen or story._busy:
			_release()
			if not await _ready_to_move():
				return false
			continue
		var err := wrapf(atan2(-d.x, -d.y) - pl.rotation.y, -PI, PI)
		_turn(err, -pl._pitch)
		if absf(err) < 0.3:
			Input.action_press("move_forward")
		else:
			Input.action_release("move_forward")
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > limit:
			_fail("could not walk to %.1f, %.1f" % [goal.x, goal.y])
			return false
	Input.action_release("move_forward")
	return true


func _aim(at: Vector3) -> void:
	for i in 90:
		var from: Vector3 = pl.camera.global_position
		var d: Vector3 = at - from
		var yaw_err := wrapf(atan2(-d.x, -d.z) - pl.rotation.y, -PI, PI)
		var pitch_err: float = atan2(d.y, Vector2(d.x, d.z).length()) - pl._pitch
		if absf(yaw_err) < 0.006 and absf(pitch_err) < 0.006:
			break
		_turn(yaw_err, pitch_err)
		await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func _badge(id: String) -> bool:
	var d: Node3D = kit.doors[id]
	if d.open > 0.6 and d._target >= 1.0:
		return true
	await _aim(d.global_position + Vector3(0, 1.2, 0))
	for attempt in 3:
		if pl.target == null or not pl.target.has_meta("door"):
			_fail("standing at door %s but the dot is not on it" % id)
			return false
		await _key(KEY_E)
		await _secs(0.5)
		if d._target >= 1.0:
			break   # a door the log did not expect refuses once
	if d._target < 1.0:
		_fail("door would not open: " + id)
		return false
	while d.open < 0.9:
		await get_tree().process_frame
	return true


func _room_of(v: Vector2) -> String:
	return kit.room_at(Vector3(v.x, 0.0, v.y))


func _nearest() -> String:
	var p := pl.global_position
	var here: String = kit.room_at(p)
	var best := ""
	var best_d := 1e9
	for n: String in _nodes:
		var v: Vector2 = _nodes[n]
		var d := Vector2(v.x - p.x, v.y - p.z).length()
		if _room_of(v) == here and d < best_d:
			best = n
			best_d = d
	return best


func _route(from: String, to: String, avoid: Array) -> Array:
	var prev := {from: ""}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == to:
			break
		for e: Array in _edges:
			if e[2] in avoid or not _passable(e[2]):
				continue
			var nb := ""
			if e[0] == cur:
				nb = e[1]
			elif e[1] == cur:
				nb = e[0]
			if nb != "" and not prev.has(nb):
				prev[nb] = cur
				queue.append(nb)
	if not prev.has(to):
		return []
	var path: Array = [to]
	while prev[path[0]] != "":
		path.push_front(prev[path[0]])
	return path


## Like a person, the bot only tries doors whose reader is green.
func _passable(door: String) -> bool:
	if door == "":
		return true
	if door == "#gate":
		return story.flags.has("gate")
	if story.flags.has("epo"):
		return not door in ["dock_mantrap", "mantrap_corr"]
	return story.granted.get(door, false)


func _door_between(a: String, b: String) -> String:
	for e: Array in _edges:
		if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
			return "" if String(e[2]).begins_with("#") else e[2]
	return ""


# ---------------------------------------------------------------- steps

func _do_start() -> bool:
	story.new_game()
	game.started = true
	story.on_play_begins()
	await _secs(1.0)
	return true


func _do_travel(to: String, avoid: Array = []) -> bool:
	for attempt in 8:
		if not await _ready_to_move():
			return false
		var from := _nearest()
		var path := _route(from, to, avoid)
		if path.is_empty():
			_fail("no route from %s to %s" % [from, to])
			return false
		var ok := true
		for i in path.size():
			if i > 0:
				var door := _door_between(path[i - 1], path[i])
				if door != "" and not await _badge(door):
					return false
			if not await _walk_to(_nodes[path[i]]):
				ok = false
				break
		if _dead:
			return false
		if ok:
			return true
		print("  bot  moved by the building; finding the way again")
		await _secs(1.0)
	_fail("never arrived at " + to)
	return false


func _do_walk(to: Vector2) -> bool:
	return await _walk_to(to)


func _do_use(id: String) -> bool:
	if _stand.has(id) and not await _walk_to(_stand[id]):
		if not _dead:
			_fail("moved away while walking to " + id)
		return false
	if not await _ready_to_move():
		return false
	var body: Node3D = kit.uses[id]
	await _aim(body.global_position)
	if pl.target != body:
		_fail("cannot reach %s: the dot is on %s" % [id, "nothing" if pl.target == null else str(pl.target.get_meta("use_id", "a door"))])
		return false
	if story.prompt_for(id) == "":
		_fail("nothing to do at " + id)
		return false
	await _key(KEY_E)
	await _secs(0.4)
	return true


func _do_close() -> bool:
	if not game.terminal.is_open:
		_fail("expected something to read")
		return false
	await _secs(0.6)
	await _key(KEY_X)
	await _key(KEY_E)
	return not game.terminal.is_open


func _do_keys(codes: Array) -> bool:
	for c: int in codes:
		await _key(c as Key)
		await _secs(0.25)
	return true


func _do_pages() -> bool:
	await _key(KEY_Q)
	if not game.handheld.raised:
		_fail("Q did not raise the handheld")
		return false
	for i in 5:
		await _secs(0.3)
		await _key(KEY_TAB)
	await _key(KEY_Q)
	return not game.handheld.raised


func _do_torch(on: bool) -> bool:
	if pl.torch.visible != on:
		await _ready_to_move()
		await _key(KEY_F)
	return pl.torch.visible == on


func _do_jog(on: bool) -> bool:
	if on:
		Input.action_press("jog")
	else:
		Input.action_release("jog")
	return true


func _do_step(want: String) -> bool:
	if story.step != want:
		_fail("expected step %s, got %s" % [want, story.step])
		return false
	return true


func _do_until(what: String, value: Variant, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		var ok := false
		match what:
			"step":
				ok = story.step == value
			"act":
				ok = story.act == value and not story._busy
			"flag":
				ok = story.flags.has(value)
			"room":
				ok = game.room == value and not story._busy
		if ok:
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	_fail("waited %d s for %s = %s" % [int(secs), what, str(value)])
	return false


func _do_crawl(from: String, to: String) -> bool:
	var marks := {}
	for row in Kit.PLENUM_MAP.size():
		for c in Kit.PLENUM_MAP[row].length():
			marks[Kit.PLENUM_MAP[row][c]] = Vector2i(c, row)
	var path: Array[Vector2i] = kit._plenum_path(marks[from], marks[to])
	for cell: Vector2i in path:
		var g: Vector3 = kit.cell_pos(cell.x, cell.y)
		if not await _walk_to(Vector2(g.x, g.z), 0.25):
			if not _dead:
				_fail("moved out of the crawl space")
			return false
	return true


func _do_ending() -> bool:
	var t := 0.0
	while not (story.ended and game._ending_ready):
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > 90.0:
			_fail("no ending reached")
			return false
	return true
