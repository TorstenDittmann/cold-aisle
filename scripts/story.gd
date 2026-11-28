extends Node
## The night shift, in five acts. This file owns everything that changes: tickets, the
## door log and its predictions, which doors your badge opens, what the building does to
## you, and the three ways out.
##
## The door log runs ahead of you. Each prediction names a door and a time a few minutes
## in the future. When you open that door the clock snaps to the logged time, so the log
## is always right. Where a second door would do, using it instead is defiance: the hidden
## counter that decides how hard the building pushes back and which endings are clean.

const Kit := preload("res://scripts/build.gd")
const SAVE_PATH := "user://cold_aisle.cfg"
const ACT_CLOCK := [0.0, 1320.0, 1390.0, 1470.0, 1520.0, 1570.0]   # 22:00 23:10 00:30 01:20 02:10
const ACT_CAP := [0.0, 1385.0, 1465.0, 1516.0, 1566.0, 1620.0]
const ACT_NAME := ["", "HANDOVER", "TICKETS", "OUT OF SYNC", "UNDER THE FLOOR", "CAGE 7"]
const NOTE_ORDER := ["label", "note1", "note2", "note3"]
const NOTES := {
	"label": "[b]ASSET LABEL[/b]  from the failed drive, Zone A K-147\nHALDEN DC-3 · ZONE B · ROW P · 07\nZone B has rows A to N.",
	"note1": "[b]NOTE[/b]  taped inside the CH-2 panel\nIt writes the door log before the doors open. I checked three nights running.\nIt only holds while you go where it says. Use the other door and watch what it does.\nThe tile at the far end of Zone B, between rows I and J, is loose. I left the lifter here.\nDo not jog in there. It hears the tiles.\n  D. Marsh, nights",
	"note2": "[b]NOTE[/b]  meet-me room, behind panel 7\nPort 12 is on no patch schedule. Yellow, unlabelled, straight down through the floor.\nClip the fault locator on and it glows the whole way. Open damper P-7 or you will not get past.\nIt ends under a cage that is not on the plan.\n  D. M.",
	"note3": "[b]BADGE[/b]  on the plenum floor\n0388 · D. MARSH · NIGHTS\nLast entry, three weeks ago: MANTRAP IN. There is no exit entry.\nOn the back, in pen: It does not want you gone. It wants you certain. There is a chair.",
}
const READS := {
	"handover": "[b]HANDOVER SHEET[/b]  nights, security desk\n\n  Mon   0388 MARSH    nothing to report\n  Tue   0388 MARSH    nothing to report\n  Wed   0388 MARSH    B2 tripped 23:44. reset.\n  Thu   0388 MARSH    B2 tripped 23:44. reset. same minute?\n  Fri   0388 MARSH    it knew I would check\n  Sat   0388 MARSH\n\nThree weeks of empty lines follow. The agency sent nobody.\n\n  Tonight   0417   ______________",
	"ups_log": "[b]BREAKER LOG[/b]  UPS room, panel B\n\n  B2   tripped 23:44   reset 23:45\n  B2   tripped 23:44   reset 23:45\n  B2   tripped 23:44   reset 23:45\n\nThe same line, every night, for three weeks. Nobody was on nights for three weeks.\n\nIn the margin, in pen: there is nothing wrong with B2. It trips so that somebody walks here.  D.M.",
}
const DOOR_IDS := ["dock_mantrap", "mantrap_corr", "dock_corr", "security", "mmr", "ups", "hall_a1", "hall_a2", "hall_b1", "hall_b2", "chillers"]

var game: Node
var kit: RefCounted
var act := 0
var step := ""
var defy := 0
var caught_n := 0
var notes: Array[String] = []
var have_handheld := false
var have_lifter := false
var granted := {}
var log: Array = []          # {t, text, kind}: kind is real, pred, true, void or ghost
var tickets: Array = []      # {id, title, body, open}
var messages: Array = []     # {who, text, t}
var flags := {}
var ended := false
var countdown := -1.0

var _queue: Array = []       # pending predictions {door, t, alts, entry, warned}
var _gen := 0                # bumped whenever the act changes, so stale timers stop
var _busy := false
var _strip_t := 0.0
var _relay_t := 3.0
var _pulse_gain := 0.0
var _pulse_z := 0.0


func setup(g: Node) -> void:
	game = g
	kit = g.kit


# ---------------------------------------------------------------- helpers

## Wait `secs` of play. Time spent in a cutscene does not count.
func _wait(secs: float) -> bool:
	var mine := _gen
	while game.cine.playing and mine == _gen:
		await get_tree().process_frame
	await get_tree().create_timer(secs).timeout
	while game.cine.playing and mine == _gen:
		await get_tree().process_frame
	return mine == _gen and not ended


func _ops_at(text: String, t: float) -> void:
	messages.append({"who": "ops", "text": text, "t": t})
	game.handheld.mark(3)
	game.notify("MESSAGE")


func ops(text: String) -> void:
	messages.append({"who": "ops", "text": text, "t": game.clock})
	game.handheld.mark(3)
	if have_handheld:
		game.notify("MESSAGE")


func you(text: String) -> void:
	messages.append({"who": "you", "text": text, "t": game.clock})
	game.handheld.mark(3)


func ticket(id: String, title: String, body: String) -> void:
	tickets.append({"id": id, "title": title, "body": body, "open": true})
	game.handheld.mark(0)
	if have_handheld:
		game.notify("TICKET #" + id)


func close_ticket(id: String) -> void:
	for t: Dictionary in tickets:
		if t["id"] == id:
			t["open"] = false
	game.handheld.mark(0)


func add_note(id: String) -> void:
	if not notes.has(id):
		notes.append(id)
		game.handheld.mark(4)


func _log(text: String, kind := "real", t := -1.0) -> Dictionary:
	var e := {"t": game.clock if t < 0.0 else t, "text": text, "kind": kind}
	log.append(e)
	game.handheld.mark(2)
	return e


func _line(title: String, result := "GRANTED") -> String:
	return "%-15s %s" % [title, result]


## Write a door into the log, `ahead` minutes in the future.
func predict(door: String, ahead: float, alts: Array = [], title := "") -> void:
	var base: float = game.clock
	if not _queue.is_empty():
		base = maxf(base, _queue[-1]["t"])
	var t := floorf(base + ahead)
	var name: String = title if title != "" else String(kit.doors[door].title)
	var e := _log(_line(name), "pred", t)
	_queue.append({"door": door, "t": t, "alts": alts, "entry": e, "warned": false})


func _void_queue() -> void:
	for p: Dictionary in _queue:
		p["entry"]["kind"] = "void"
	_queue.clear()


func grant(ids: Array, on := true) -> void:
	for id: String in ids:
		granted[id] = on
	_refresh_doors()


func _refresh_doors() -> void:
	for id: String in DOOR_IDS:
		var state := "green" if granted.get(id, false) else "red"
		if flags.has("epo"):
			state = "dead"
		kit.doors[id].set_state(state)


func _beacon(on: bool) -> void:
	(kit.props["b07_led"] as Node3D).visible = on
	(kit.props["b07_light"] as Node3D).visible = on


## What you are meant to be doing, in one line, and where. Shown on screen and marked
## on the handheld's plan, because the building is too big to search.
func _goal() -> Array:
	var u: Dictionary = kit.uses
	var room: String = game.room
	match act:
		1:
			match step:
				"badge_in":
					return ["Badge in through the mantrap", kit.doors["dock_mantrap"].position]
				"to_security":
					return ["Security desk: pick up the handheld", u["handheld"].position]
				"swap":
					return ["#4471   Zone A · Row K · rack 147", u["rack_a147"].position]
				"return":
					return ["#4471   Security desk: the RETURNS bin", u["desk_bin"].position]
		2:
			match step:
				"to_hall_b", "pulse", "console":
					if flags.has("hot"):
						return ["#4473   Zone B · Row K · rack 07", u["rack_b07"].position]
					if not tickets.is_empty() and tickets[-1]["id"] == "4472":
						return ["#4472   Zone B · Row P · rack 07", null]
				"ups":
					return ["#4474   UPS room: breaker B2", u["breaker_b2"].position]
				"to_desk2":
					return ["Security desk: the cameras", u["cctv"].position]
		3:
			match step:
				"fire_panel":
					return ["#4475   Zone A, far end: fire panel FP-A", u["fire_panel_a"].position]
				"abort":
					return ["GAS ABORT   Zone A, corridor end, between the doors", u["abort_a"].position]
				"chiller":
					if not tickets.is_empty() and tickets[-1]["id"] == "4476":
						return ["#4476   Chiller plant: restart CH-2", u["chiller2"].position]
		4:
			if not notes.has("note1"):
				return ["The CH-2 panel: something is taped inside", u["note1"].position]
			if room == "plenum":
				return ["Follow the lit fibre" if flags.has("fibre") else "Under the floor: find the way up", null]
			if not flags.has("fibre"):
				if room == "mmr":
					return ["Meet-me room: panel 7, port 12", u["panel7"].position]
				return ["Zone B, far end, rows I and J: the loose tile", u["hatch_b"].position]
			if not flags.has("damper"):
				return ["Meet-me room: damper P-7", u["damper"].position]
			return ["Under the floor: follow the lit fibre", u["hatch_mmr"].position]
		5:
			if not flags.has("console7"):
				return ["Cage 7: the console", u["console7"].position]
			if not flags.has("epo"):
				return ["02:31   MANTRAP OUT   is already in the log", null]
	return ["", null]


func objective() -> String:
	return "" if ended or act == 0 else String(_goal()[0])


func goal_pos() -> Variant:
	return null if ended or act == 0 else _goal()[1]


func _teleport(spot: String) -> void:
	var s: Array = kit.spots[spot]
	game.player.place(s[0], s[1])


func _all_notes() -> bool:
	return notes.has("note1") and notes.has("note2") and notes.has("note3")


# ---------------------------------------------------------------- doors

## Called by a door when you badge it. Returns whether it opens.
func on_badge(door: Node) -> bool:
	var id: String = door.id
	if flags.has("epo"):
		# no power: inner doors fail open, the mantrap fails shut
		return not id in ["dock_mantrap", "mantrap_corr"]
	if not granted.get(id, false):
		if act >= 4 and not flags.has("denied_hint"):
			flags["denied_hint"] = true
			game.toast("Revoked. Your badge opened this an hour ago.")
		return false
	if not _queue.is_empty():
		var p: Dictionary = _queue[0]
		if id == p["door"]:
			# the log was right; if you were early, the clock agrees with the log anyway
			game.clock = maxf(game.clock, p["t"])
			p["entry"]["kind"] = "true"
			_queue.pop_front()
			game.handheld.mark(2)
			_after_door(id, true)
			return true
		if id in p["alts"]:
			if not p["warned"]:
				p["warned"] = true   # the building objects, once
				return false
			defy += 1
			p["entry"]["kind"] = "void"
			_queue.pop_front()
			_log(_line(door.title, "GRANTED  UNPREDICTED"))
			_on_defied()
			_after_door(id, false)
			return true
	_log(_line(door.title))
	_after_door(id, false)
	return true


func _on_defied() -> void:
	game.sound.play("stall", -6.0)
	_flicker_everything()
	if defy == 1:
		_say_later(4.0, "Your badge just took a door the system did not expect. It has flagged it. I have never seen that flag before.")
	elif defy == 2:
		_say_later(4.0, "It flagged you again. Whatever you are doing, it does not like it.")


func _say_later(secs: float, text: String) -> void:
	if await _wait(secs):
		ops(text)


func _flicker_everything() -> void:
	var mine := _gen
	for i in 3:
		game.dim(0.25)
		await get_tree().create_timer(0.07).timeout
		game.dim(1.0)
		await get_tree().create_timer(0.09).timeout
		if mine != _gen:
			return


func _after_door(id: String, _predicted: bool) -> void:
	if act == 2 and flags.has("console_b") and id in ["hall_b1", "hall_b2"] and not flags.has("left_b"):
		flags["left_b"] = true
	if act == 5 and id == "mantrap_corr" and flags.has("console7"):
		flags["comply"] = true


# ---------------------------------------------------------------- using things

## The words under the reticle. An empty string means there is nothing to do here.
func prompt_for(id: String) -> String:
	match id:
		"handheld":
			return "" if have_handheld else "Pick up the handheld and the spare drive"
		"rack_a147":
			return "Swap the failed drive" if step == "swap" else ""
		"desk_bin":
			return "Drop the dead drive in returns" if step == "return" else ""
		"handover":
			return "Read the handover sheet"
		"ups_log":
			return "Read the breaker log"
		"cctv":
			return "Watch the cameras" if have_handheld else ""
		"rack_b07":
			return "Plug in the console cable" if act >= 2 and not flags.has("epo") else ""
		"breaker_b2":
			return "Reset breaker B2" if step == "ups" else ""
		"fire_panel_a":
			return "Acknowledge fire panel FP-A" if step == "fire_panel" else ""
		"abort_a":
			return "Hold the gas abort" if step == "abort" else ""
		"chiller2":
			return "Restart CH-2" if step == "chiller" else ""
		"note1":
			return "Take what is taped inside the panel" if act >= 4 and not notes.has("note1") else ""
		"note2":
			return "Read the note" if not notes.has("note2") else ""
		"note3":
			return "Pick up the badge" if not notes.has("note3") else ""
		"hatch_b":
			return "Lift the loose floor tile" if act >= 4 else ""
		"hatch_h_up":
			return "Climb up into Zone B"
		"hatch_m":
			return "Climb up into the meet-me room"
		"hatch_c":
			return "Climb up"
		"hatch_mmr", "hatch_cage":
			return "Climb down under the floor"
		"panel7":
			return "" if flags.has("fibre") else "Clip the fault locator on port 12"
		"damper":
			return "Close damper P-7" if flags.has("damper") else "Open damper P-7"
		"console7":
			return "Use the console" if act >= 5 else ""
		"cage_gate":
			return "Unbolt the mesh panel" if act >= 5 and not flags.has("gate") and kit.in_cage(game.player.global_position) else ""
		"epo_b":
			return "" if flags.has("epo") else "Emergency power off · Zone B"
		"dock_shutter":
			return "Raise the shutter"
	return ""


func on_use(id: String) -> void:
	if ended or _busy or prompt_for(id) == "":
		return
	match id:
		"handheld":
			have_handheld = true
			(kit.props["handheld"] as Node3D).visible = false
			game.sound.play("tone")
			_handheld_hints()
			_say_later(16.0, "Housekeeping. Zone A-2 is the door straight across the corridor from the security office. Row K is one aisle to your right once you are inside. The row letters hang over every aisle. You should not need Zone B tonight.")
			ops("Evening, 0417. Operations desk here, remote as always. You are the only one on site tonight. One ticket in the queue, should be a quiet shift.")
			ticket("4471", "Failed drive, Zone A", "Zone A · Row K · rack 147, drive bay 3. Swap it for the spare and bring the dead one back to RETURNS at the security desk. Row K is in the aisle between the two doors, near the corridor end. It is showing an amber fault light.")
			step = "swap"
		"rack_a147":
			_swap_drive()
		"desk_bin":
			close_ticket("4471")
			game.sound.play("relay")
			_change_act(2)
		"cctv":
			_use_cctv()
		"handover":
			game.sound.play("tick", -8.0)
			game.terminal.show_screen("HANDOVER SHEET · nights", READS["handover"])
		"ups_log":
			game.sound.play("tick", -8.0)
			game.terminal.show_screen("BREAKER LOG · panel B", READS["ups_log"])
		"rack_b07":
			_console_b()
		"breaker_b2":
			_reset_breaker()
		"fire_panel_a":
			_fire_panel()
		"abort_a":
			_abort_gas(false)
		"chiller2":
			_restart_chiller()
		"note1":
			add_note("note1")
			have_lifter = true
			(kit.props["note1"] as Node3D).visible = false
			_read_note("note1", "A note, and a floor-tile lifter.")
		"note2":
			add_note("note2")
			(kit.props["note2"] as Node3D).visible = false
			_read_note("note2", "")
		"note3":
			add_note("note3")
			(kit.props["note3"] as Node3D).visible = false
			_read_note("note3", "")
		"hatch_b":
			if not have_lifter:
				game.toast("The tile rocks under your boot, but you cannot get a grip on it without a lifter.")
			else:
				game.sound.play("tile")
				_hatch("plenum_h")
		"hatch_h_up":
			_hatch("hall_b_hatch")
		"hatch_m":
			_hatch("mmr_hatch")
		"hatch_mmr":
			_hatch("plenum_m")
		"hatch_cage":
			_hatch("plenum_c")
		"hatch_c":
			if act < 5:
				_change_act(5)
			else:
				_hatch("cage")
		"panel7":
			flags["fibre"] = true
			kit.set_fibre_lit(true)
			game.sound.play("beep")
			game.toast("Port 12 lights up red. Under the floor, one fibre is glowing.")
		"damper":
			if flags.has("damper"):
				flags.erase("damper")
			else:
				flags["damper"] = true
			kit.set_damper(flags.has("damper"))
			game.sound.play("breaker", -6.0, 1.3)
			game.toast("Something heavy moves under the floor." if flags.has("damper") else "The damper closes.")
		"console7":
			_console_7()
		"cage_gate":
			flags["gate"] = true
			kit.open_cage_gate()
			game.sound.play("tile", -3.0, 0.8)
		"epo_b":
			_epo()
		"dock_shutter":
			if flags.has("epo"):
				_ending("defy" if defy >= 2 else "defy_logged")
			else:
				game.toast("The shutter is interlocked with the door log. It does not move.")


func _read_note(id: String, lead: String) -> void:
	game.sound.play("tick", -8.0)
	var text: String = NOTES[id]
	if lead != "":
		text = lead + "\n\n" + text
	game.terminal.show_screen("NOTE · saved to the handheld", text)


func _hatch(spot: String) -> void:
	_busy = true
	await game.blink(func() -> void: _teleport(spot), 0.25)
	_busy = false


# ---------------------------------------------------------------- acts

func new_game() -> void:
	defy = 0
	caught_n = 0
	notes.clear()
	begin_act(1, true)


func has_save() -> int:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return 0
	return int(cf.get_value("save", "act", 0))


func continue_game() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		new_game()
		return
	defy = int(cf.get_value("save", "defy", 0))
	caught_n = int(cf.get_value("save", "caught", 0))
	notes.clear()
	for n: String in cf.get_value("save", "notes", []):
		notes.append(n)
	begin_act(int(cf.get_value("save", "act", 1)), true)


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("save", "act", act)
	cf.set_value("save", "defy", defy)
	cf.set_value("save", "caught", caught_n)
	cf.set_value("save", "notes", Array(notes))
	cf.save(SAVE_PATH)


## Move to the next act where you stand: the frame closes, a short scene plays, the clock
## moves on.
func _change_act(n: int) -> void:
	_busy = true
	game.sound.play("swell", -2.0)
	await game.fade(1.0, 0.5)
	begin_act(n, false)
	var shots := act_shots(n)
	if shots.is_empty():
		await get_tree().create_timer(1.2).timeout
	else:
		await game.cine.play(shots)
		_world_for_act(n)
	game.act_card(n, ACT_NAME[n])
	await game.fade(0.0, 0.8)
	_busy = false


## Start an act. With `fresh` the whole building is put into the state that act begins in
## (used for a new game and for Continue); without it only what changes is touched.
func begin_act(n: int, fresh: bool) -> void:
	_gen += 1
	act = n
	ended = false
	countdown = -1.0
	_void_queue()
	game.clock = ACT_CLOCK[n]
	game.banner("")
	game.sound.alarm(false)
	game.sound.silenced = false
	_save()
	if fresh:
		_restore(n)
	match n:
		1:
			step = "badge_in"
			grant(DOOR_IDS, false)
			grant(["dock_mantrap", "mantrap_corr", "security", "hall_a1", "hall_a2"])
			_log(_line("STAFF GATE"), "real", 1318.0)
			game.toast("22:00. Badge in through the mantrap.", 8.0)
		2:
			step = "to_hall_b"
			_act2()
		3:
			step = "cctv"
			_act3()
		4:
			step = "note1"
			_act4()
		5:
			step = "cage"
			_act5()
	_world_for_act(n)
	game.act_card(n, ACT_NAME[n])


## What the building looks like when act `n` begins.
func _world_for_act(n: int) -> void:
	kit.set_hall_lit("a", n <= 3)
	kit.set_hall_lit("b", n <= 3)
	kit.set_hall_power("a", 1.0)
	kit.set_hall_power("b", 1.0)
	(kit.props["cage_light"] as Node3D).visible = true
	for id: String in ["corridor", "dock", "mantrap", "mmr", "ups", "chillers"]:
		kit.set_room_lit(id, n <= 3)
	kit.set_room_lit("security", true)
	(kit.props["fault_led"] as Node3D).visible = n == 1
	(kit.props["fault_light"] as Node3D).visible = n == 1
	(kit.props["breaker_led"] as Node3D).visible = n <= 2
	_beacon(n == 2 and flags.has("hot") and not flags.has("b_cleared"))
	(kit.props["handheld"] as Node3D).visible = not have_handheld
	(kit.props["note1"] as Node3D).visible = not notes.has("note1")
	(kit.props["note2"] as Node3D).visible = not notes.has("note2")
	(kit.props["note3"] as Node3D).visible = not notes.has("note3")
	kit.set_damper(flags.has("damper"))
	kit.set_fibre_lit(flags.has("fibre"))
	kit.set_pulse(-100.0, 0.0)
	if flags.has("gate"):
		kit.open_cage_gate()
	else:
		kit.close_cage_gate()
	game.figure.active = n >= 4
	game.figure.reset()
	game.player.torch_flicker = 0.0
	_refresh_doors()


## Rebuild the handheld's history for a game that starts at act `n`.
func _restore(n: int) -> void:
	flags.clear()
	log.clear()
	tickets.clear()
	messages.clear()
	have_handheld = n >= 2
	have_lifter = notes.has("note1")
	if n == 1:
		notes.clear()
	elif not notes.has("label"):
		notes.insert(0, "label")
	for d: String in DOOR_IDS:
		kit.doors[d].shut()
	var past := [
		[1318.0, "STAFF GATE"], [1321.0, "MANTRAP"], [1323.0, "SECURITY DESK"], [1331.0, "ZONE A-1"], [1352.0, "SECURITY DESK"],
		[1396.0, "ZONE B-1"], [1421.0, "ZONE B-2"], [1425.0, "UPS ROOM"], [1440.0, "SECURITY DESK"],
		[1481.0, "ZONE A-1"], [1498.0, "ZONE A-2"], [1502.0, "CHILLER PLANT"],
	]
	var upto: int = [0, 0, 5, 9, 12, 12][n]
	for i in upto:
		_log(_line(past[i][1]), "real" if i < 6 else "true", past[i][0])
	var old := [["4471", "Failed drive, Zone A"], ["4472", "Link down, Zone B P-07"], ["4473", "High temperature, Zone B"],
		["4474", "Breaker B2, UPS room"], ["4475", "Fire panel FP-A"], ["4476", "Chiller CH-2 tripped"]]
	var closed: int = [0, 0, 1, 4, 6, 6][n]
	for i in closed:
		tickets.append({"id": old[i][0], "title": old[i][1], "body": "", "open": false})
	if n >= 3:
		flags["log"] = true
		flags["console_b"] = true
	if n >= 5:
		flags["fibre"] = true
		flags["damper"] = true
	game.handheld.unread.clear()
	_teleport(["", "dock", "desk", "desk", "chillers", "cage"][n])


func _act2() -> void:
	grant(["hall_b1", "hall_b2"])
	if not await _wait(3.0):
		return
	ticket("4472", "Link down, Zone B P-07", "Zone B · Row P · rack 07: link down on port 47. Reseat the fibre.")
	if not await _wait(7.0):
		return
	ops("Row P? Zone B stops at row N on my plan. Do not go looking for it. Same row as the label on that dead drive, though. Leave it with me.")
	if not await _wait(9.0):
		return
	game.sound.play("chime", -6.0)
	flags["hot"] = true
	_beacon(true)
	ticket("4473", "High temperature, Zone B", "HIGH TEMP alarm, Zone B. Plug your console cable into Row K · rack 07 and read what it says. Row K is in the aisle between the two doors, a few racks in from the corridor end. The rack is showing an amber fault light.")


func _act3() -> void:
	flags["log"] = true
	grant(["ups"], false)
	_watch_cameras()


func _act4() -> void:
	grant(DOOR_IDS, false)
	grant(["security", "hall_b1", "hall_b2", "chillers"])
	(kit.doors["chillers"] as Node).shut()
	game.sound.play("breaker", -3.0, 0.7)
	if not await _wait(4.0):
		return
	ops("Your badge just dropped off every zone except Zone B. I did not do that. And I have lost you on the cameras.")
	predict("hall_b2", 6.0, ["hall_b1"])
	if not await _wait(10.0):
		return
	ops("There is a line in your log for Zone B, east door. Six minutes from now. I would like to know who is writing those.")
	if not await _wait(28.0):
		return
	_ops_at("Good shift, 0417. Badge logged out at the mantrap. Get some sleep.", 1591.0)
	if not await _wait(7.0):
		return
	ops("I did not send that. Look at the time on it. I am going to stop typing for a while.")


func _act5() -> void:
	grant(DOOR_IDS, false)
	grant(["security", "hall_b1", "hall_b2", "chillers"])
	flags["fibre"] = true
	flags["damper"] = true
	_teleport("cage")
	game.toast("NO SERVICE", 5.0)
	messages.append({"who": "ops", "text": "0417, are you still there? Your badge has stopped moving.", "t": game.clock})


# ---------------------------------------------------------------- act 1

func _swap_drive() -> void:
	_busy = true
	game.player.frozen = true
	game.sound.play("swap")
	await get_tree().create_timer(1.7).timeout
	game.player.frozen = false
	_busy = false
	(kit.props["fault_led"] as Node3D).visible = false
	(kit.props["fault_light"] as Node3D).visible = false
	add_note("label")
	step = "return"
	game.toast("The new drive spins up. The dead one has an asset label for Zone B, row P. It is in your notes.", 8.0)
	_say_later(13.0, "Marsh had your shift until three weeks ago. Stopped coming in, never handed the badge back. The agency took a while to find you.")
	if await _wait(6.0):
		ops("Rebuild has started. Drop the dead drive in RETURNS at the security desk and I will close the ticket.")


# ---------------------------------------------------------------- act 2

func _pulse_event() -> void:
	var mine := _gen
	step = "pulse"
	game.sound.play("stall", -3.0)
	var t := 0.0
	var z := Kit.AISLE_LEN
	while t < 9.0 and mine == _gen:
		var pz: float = game.player.global_position.z
		if t < 2.6:
			# it runs down the row toward you
			z = lerpf(Kit.AISLE_LEN, pz, smoothstep(0.0, 1.0, t / 2.6))
			_pulse_gain = 1.0
		elif t < 7.5:
			# and stops level with you. Move, and it moves.
			z = lerpf(z, pz, 0.06)
			_pulse_gain = 1.0
		else:
			_pulse_gain = 1.0 - (t - 7.5) / 1.5
		_pulse_z = z
		kit.set_pulse(z, _pulse_gain)
		game.sound.duck = 0.6 * _pulse_gain
		await get_tree().process_frame
		t += get_process_delta_time()
	kit.set_pulse(-100.0, 0.0)
	game.sound.duck = 0.0
	if mine == _gen and step == "pulse":
		step = "console"
		you("Every status light in the aisle went out and came back, one rack at a time. It stopped next to me.")
		_say_later(5.0, "Nothing in my logs. Nothing ran. Plug in at K-07 and read me what the console says.")


func _console_b() -> void:
	var title := "CONSOLE · hb-k07 · Zone B row K rack 07"
	if act != 2 or flags.has("b_cleared"):
		game.terminal.show_screen(title, "hb-k07-con> show status\n  inlet temp     21.3 C\n  fans           6/6\n  alarms         none\n  port 47        hb-p07   up   [CAGE 7]")
		return
	game.sound.play("beep", -6.0)
	_console_b_menu("hb-k07-con>\n  console cable connected. 9600 8N1.")


func _console_b_menu(text: String) -> void:
	var choices := [
		["show status", _console_b_status],
		["show link partners", _console_b_links],
		["show door log, badge 0417", _console_b_log],
	]
	if flags.has("console_b"):
		choices.append(["clear the temperature alarm", _console_b_clear])
	game.terminal.show_screen("CONSOLE · hb-k07 · Zone B row K rack 07", text, choices)


func _console_b_status() -> void:
	_console_b_menu("hb-k07-con> show status\n  inlet temp     21.4 C     alarm threshold 32.0 C\n  fans           6/6\n  HIGH TEMP raised by    hb-p07\n  hb-p07                 no such rack in inventory")


func _console_b_links() -> void:
	_console_b_menu("hb-k07-con> show link partners\n  port 1    hb-k06     up    211 d\n  port 2    hb-k08     up    211 d\n  port 47   hb-p07     up   1123 d    [CAGE 7]\n  CAGE 7                no such location in inventory")


func _console_b_log() -> void:
	if not flags.has("console_b"):
		flags["console_b"] = true
		flags["log"] = true
		predict("hall_b2", 6.0, ["hall_b1"])
		predict("ups", 4.0)
		_say_later(9.0, "I have pushed the door log to your handheld. Two of those lines have not happened yet. Tell me that is a clock fault.")
	var t := "hb-k07-con> show door log badge 0417\n"
	var lines: Array = log.duplicate()
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
	for e: Dictionary in lines.slice(maxi(0, lines.size() - 8)):
		var l := "  %s  %s" % [game.clock_text(e["t"]), e["text"]]
		t += ("[color=#ffb347]%s[/color]\n" % l) if e["kind"] == "pred" else (l + "\n")
	t += "\n  system time    %s" % game.clock_text()
	_console_b_menu(t)


func _console_b_clear() -> void:
	flags["b_cleared"] = true
	_beacon(false)
	close_ticket("4473")
	close_ticket("4472")
	grant(["ups"])
	step = "ups"
	game.terminal.show_screen("CONSOLE · hb-k07 · Zone B row K rack 07", "hb-k07-con> clear alarm\n  HIGH TEMP cleared.\n  note: alarm source hb-p07 is not in inventory. Nothing was hot.")
	ticket("4474", "Breaker B2, UPS room", "UPS room, panel B: breaker B2 has tripped. Reset it by hand. Your badge has the UPS room for tonight.")


func _reset_breaker() -> void:
	game.sound.play("breaker")
	(kit.props["breaker_led"] as Node3D).visible = false
	close_ticket("4474")
	_flicker_everything()
	step = "to_desk2"
	predict("security", 5.0)
	if await _wait(4.0):
		ops("B2 is back. Come to the security desk and look at the cameras for me. I want a second pair of eyes on something.")


# ---------------------------------------------------------------- act 3

func _use_cctv() -> void:
	if step == "to_desk2":
		_change_act(3)
		return
	game.cctv.open()
	game.show_all_rooms(true)


func _watch_cameras() -> void:
	# camera 4 shows a technician with a torch in Zone B. The badge on the overlay is yours.
	var mine := _gen
	game.cctv.open()
	game.show_all_rooms(true)
	var twin: Node3D = game.double
	twin.visible = true
	twin.position = Vector3(Kit.HALL_B_X, 0, 13.0)
	twin.rotation.y = 0.0
	game.cctv.set_tag(3, "BADGE 0417 · IN ROOM")
	var t := 0.0
	while t < 7.0 and mine == _gen and game.cctv.is_open:
		twin.position.z -= get_process_delta_time() * 0.7
		await get_tree().process_frame
		t += get_process_delta_time()
	if mine != _gen:
		return
	# it stops, and looks up at the camera
	twin.rotation.x = 0.5
	await get_tree().create_timer(1.6).timeout
	if mine != _gen:
		return
	game.cctv.set_static(3, 1.0)
	game.cctv.set_tag(3, "SIGNAL LOST")
	if game.cctv.is_open:
		game.sound.static_noise(true)
	twin.visible = false
	ops("No. There is nobody else badged in tonight. Why do you ask?")
	await get_tree().create_timer(2.5).timeout
	if mine != _gen:
		return
	you("Is anyone else on site?")
	flags["cams_done"] = true
	if not game.cctv.is_open:
		on_cctv_closed()


func on_cctv_closed() -> void:
	game.show_all_rooms(false)
	(game.double as Node3D).visible = false
	if act == 3 and step == "cctv" and flags.has("cams_done"):
		step = "fire_panel"
		game.sound.play("chime", -6.0)
		ticket("4475", "Fire panel FP-A", "Fire panel FP-A reports a fault. It is on the south wall at the far end of Zone A. Acknowledge it at the panel.")
		predict("hall_a1", 5.0, ["hall_a2"])


func _fire_panel() -> void:
	step = "abort"
	countdown = 56.0 - 4.0 * defy
	kit.set_hall_lit("a", false)
	game.sound.play("breaker", -4.0)
	game.sound.alarm(true)
	game.toast("FP-A: NO FAULT. PRE-DISCHARGE STARTED. The abort station is on the north wall, between the doors.", 9.0)


func _abort_gas(by_itself: bool) -> void:
	countdown = -1.0
	game.banner("")
	game.sound.alarm(false)
	close_ticket("4475")
	step = "chiller"
	grant(["chillers"])
	if not by_itself:
		game.sound.play("beep")
		predict("hall_a2", 4.0, ["hall_a1"])
	predict("chillers", 4.0)
	if not await _wait(2.5):
		return
	ops("That was not me. I have not touched suppression." if not by_itself else "Suppression aborted itself at zero. Then the cameras came back and you were on the floor of the security office.")
	if not await _wait(2.5):
		return
	you("Did you trigger that?" if not by_itself else "What happened?")
	if not await _wait(5.0):
		return
	ticket("4476", "Chiller CH-2 tripped", "CH-2 tripped on the suppression signal. Restart it at its local panel in the chiller plant, east end of the corridor.")


func _restart_chiller() -> void:
	game.sound.play("breaker", 0.0, 0.8)
	var m: StandardMaterial3D = (kit.props["chiller_led"] as MeshInstance3D).material_override
	m.albedo_color = Color(0.1, 1.0, 0.35)
	m.emission = Color(0.1, 1.0, 0.35)
	close_ticket("4476")
	_change_act(4)


# ---------------------------------------------------------------- act 5 and the endings

func _console_7() -> void:
	if not flags.has("console7"):
		flags["console7"] = true
		game.clock = maxf(game.clock, 1573.0)
		grant(DOOR_IDS)
		grant(["dock_corr", "mmr"], false)
		kit.set_room_lit("corridor", true)
		kit.set_room_lit("mantrap", true)
		predict("mantrap_corr", 18.0, [], "MANTRAP OUT")
		_queue[0]["entry"]["text"] = _line("MANTRAP OUT", "NO RECORD")
	var t := "c7-con> tail door log badge 0417\n"
	var lines: Array = log.duplicate()
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
	for e: Dictionary in lines.slice(maxi(0, lines.size() - 7)):
		var l := "  %s  %s" % [game.clock_text(e["t"]), e["text"]]
		t += ("[color=#ffb347]%s[/color]\n" % l) if e["kind"] in ["pred", "true", "ghost"] else (l + "\n")
	t += "  -- end of log --\n\n  system time    %s" % game.clock_text()
	_console_7_menu(t)


func _console_7_menu(text: String) -> void:
	var choices := [["show model", _console_7_model], ["show subjects", _console_7_subjects]]
	if _all_notes():
		choices.append(["take the chair", func() -> void:
			game.terminal.close()
			_ending("stay")])
	game.terminal.show_screen("CONSOLE · c7 · CAGE 7", text, choices)


func _error_text() -> String:
	return "%.1f %%" % (defy * 3.1 + caught_n * 0.4)


func _console_7_model() -> void:
	_console_7_menu("c7-con> show model\n  tenant       [withheld]\n  inputs       door log, cameras, power, cooling, suppression\n  target       next door, next minute, per badge\n  controls     lighting, access zones, cooling, suppression, clocks\n  objective    minimise prediction error\n  method       predict. where a prediction fails, act until it holds.\n\n  error, badge 0417, tonight      %s" % _error_text())


func _console_7_subjects() -> void:
	_console_7_menu("c7-con> show subjects\n  0388  MARSH D    21 nights   error 0.0 %%    status RESIDENT\n  0417  (you)       1 night    error %s    status OPEN\n\n  final entry for 0417      02:31  MANTRAP OUT  NO RECORD\n  final entry for 0388      [edited at this console]" % _error_text())


func _epo() -> void:
	if not flags.has("console7"):
		game.toast("The cover is sealed with a numbered tag. You have no reason to break it. Yet.")
		return
	flags["epo"] = true
	_void_queue()
	game.sound.play("powerdown")
	game.sound.silenced = true
	kit.set_hall_power("b", 0.0)
	kit.set_hall_lit("b", false)
	(kit.props["cage_light"] as Node3D).visible = false
	for id: String in ["corridor", "mantrap", "dock", "mmr", "ups", "chillers"]:
		kit.set_room_lit(id, false)
	game.figure.active = false
	_refresh_doors()
	if await _wait(6.0):
		game.toast("Zone B is dark. For the first time tonight, the building is quiet. The mantrap has no power. The loading dock has a hand chain.", 10.0)


func _ending(kind: String) -> void:
	if ended:
		return
	ended = true
	_gen += 1
	var lines: Array = []
	match kind:
		"comply":
			game.clock = 1591.0
			lines = [
				"[color=#ffb347]02:31  MANTRAP OUT[/color]",
				"You leave at the logged time. Nothing is recorded. You drive home and you sleep.",
				"",
				"[color=#ffb347]21:58  STAFF GATE      GRANTED\n22:01  MANTRAP         GRANTED\n22:03  SECURITY DESK   GRANTED\n22:11  ZONE A-1        GRANTED[/color]",
				"",
				"Tomorrow night is already written.",
				"ENDING 1 OF 3 · COMPLY",
			]
		"defy":
			lines = [
				"02:31",
				"Outside it is getting light. The car park is empty except for your car.",
				"",
				"No entry is written.",
				"",
				"ENDING 2 OF 3 · DEFY",
			]
		"defy_logged":
			lines = [
				"Outside it is getting light. The handheld buzzes once in your pocket.",
				"",
				"[color=#ffb347]02:31  LOADING DOCK    GRANTED[/color]",
				"",
				"You went everywhere it said tonight. It had this door too.",
				"ENDING 2 OF 3 · DEFY, AS LOGGED",
			]
		"stay":
			lines = [
				"[color=#ffb347]22:00  0431  STAFF GATE      GRANTED\n22:02  0431  MANTRAP         GRANTED[/color]",
				"",
				"Somebody starts the night shift tomorrow. You already know which doors they will open.",
				"",
				"ENDING 3 OF 3 · STAY",
			]
	var cf := ConfigFile.new()
	cf.save(SAVE_PATH)   # the night is over: clear the checkpoint
	game.sound.alarm(false)
	game.handheld.raised = false
	game.terminal.close()
	await game.fade(1.0, 0.7)
	await game.cine.play(ending_shots(kind))
	game.show_ending(lines)


# ---------------------------------------------------------------- being caught

## Not a game over: the frame closes, you wake at the security desk, the clock has moved
## on, and the log has gained an entry you did not make.
func caught(reason: String) -> void:
	if _busy or ended:
		return
	_busy = true
	caught_n += 1
	countdown = -1.0
	game.banner("")
	game.sound.alarm(false)
	game.sound.play("thump")
	game.set_noise(1.0)
	game.terminal.close()
	var wake := func() -> void:
		_teleport("desk")
		game.set_noise(0.0)
		game.figure.reset()
		var cap := ACT_CAP[act] as float
		if not _queue.is_empty():
			cap = minf(cap, _queue[0]["t"])
		game.clock = minf(game.clock + 11.0, cap)
		_log(_line("SECURITY DESK"), "ghost")
		game.player.wake()
		game.hold = true
	await game.blink(wake, 2.2, 1.4)
	await get_tree().create_timer(2.6).timeout
	game.hold = false
	_busy = false
	game.toast("You are on the floor of the security office. The door log says you walked here.", 8.0)
	if reason == "gas":
		_abort_gas(true)


# ---------------------------------------------------------------- every frame

func on_room(now: String, _before: String) -> void:
	if ended:
		return
	if act == 1 and step == "badge_in" and now == "corridor":
		step = "to_security"
		game.toast("Pick up the handheld at the security desk.", 7.0)
	if now == "hall_b" and act >= 4:
		game.figure.back_off()
		if not flags.has("epo"):
			game.hint("crouch", "CTRL   crouch.  Walk, do not jog.", "DUCK   crouch.  Walk, do not jog.", func() -> bool: return game.player.crouching, 12.0)
	if now in ["hall_a", "hall_b"] and have_handheld:
		game.hint("jog", "SHIFT   jog", "JOG   jog", func() -> bool: return game.player.jogging, 12.0)
	if act == 5 and flags.has("comply") and now == "mantrap":
		_ending("comply")


func _process(delta: float) -> void:
	if act == 0 or ended or game.paused:
		return
	# the clock: four times real speed, and never past the next line the log has written
	var cap := ACT_CAP[act] as float
	if not _queue.is_empty():
		cap = minf(cap, _queue[0]["t"])
	if game.clock < cap:
		game.clock = minf(cap, game.clock + delta * 4.0 / 60.0)

	var p: Vector3 = game.player.global_position
	var room: String = game.room
	if room != "" and game.started and not game.player.torch.visible and (room == "plenum" or not kit.rooms[room].lit):
		game.hint("torch", "F   torch", "TORCH   switch on the torch", func() -> bool: return game.player.torch.visible, 25.0)

	if act == 2 and step == "to_hall_b" and room == "hall_b" and absf(p.x - Kit.HALL_B_X) < 1.2 and p.z > 1.5 and flags.has("hot"):
		_pulse_event()

	if act == 3 and step == "fire_panel" and room == "hall_a":
		# the strip lights go out one bay at a time behind you
		_strip_t -= delta
		if _strip_t <= 0.0:
			for a in Kit.AISLES:
				var strips: Array = kit.halls["a"]["strips"][a]
				var mine := absf(p.x - kit.aisle_x("a", a)) < 1.4
				for i in strips.size():
					if strips[i]["on"] and ((mine and strips[i]["z"] < p.z - 3.4) or (not mine and p.z > 9.0 and strips[i]["z"] < p.z)):
						kit.set_strip("a", a, i, false)
						game.sound.play("tick", -2.0, randf_range(0.8, 1.0))
						_strip_t = 0.4
						break
				if _strip_t > 0.0:
					break

	if countdown > 0.0:
		countdown -= delta
		game.banner("GAS DISCHARGE IN  %02d" % int(ceil(countdown)))
		if countdown <= 0.0:
			caught("gas")

	if room == "ups":
		_relay_t -= delta
		if _relay_t <= 0.0:
			_relay_t = randf_range(1.5, 6.0)
			game.sound.play("relay", -14.0, randf_range(0.9, 1.2))

	# the torch does not like Cage 7 equipment
	var near_cage := 0.0
	if room == "hall_b" and not flags.has("epo"):
		var d := Vector2(p.x - (Kit.HALL_B_X + 6.0), p.z - (Kit.CONSOLE_Z + 0.3)).length()
		near_cage = clampf(1.0 - (d - 4.0) / 7.0, 0.0, 1.0)
	game.player.torch_flicker = near_cage * 0.8


# ---------------------------------------------------------------- teaching the controls

## Called once the opening is over and you can move. Nothing about the controls is shown
## before this; each one appears the first time it is useful.
func on_play_begins() -> void:
	game.hint("look", "MOUSE   look around", "DRAG the right side of the screen to look around", func() -> bool: return game.turned() > 1.2)
	game.hint("walk", "W  A  S  D   walk", "DRAG the left side of the screen to walk", func() -> bool: return game.walked() > 2.5)
	if act == 1 and step == "badge_in":
		game.hint("use", "E   use what the dot is on.  Badge the reader beside the door.", "USE   badge the reader beside the door", func() -> bool: return step != "badge_in")
	if have_handheld:
		_handheld_hints()


func _handheld_hints() -> void:
	game.hint("pda", "Q   raise the handheld", "PDA   raise the handheld", func() -> bool: return game.handheld.raised)
	game.hint("page", "TAB   next page   ·   Q   put it away", "NEXT turns the page   ·   PDA puts it away", func() -> bool: return not game.handheld.raised, 25.0)
	game.hint("pause", "ESC   pause and settings", "II   pause and settings", func() -> bool: return game.paused, 7.0)


# ---------------------------------------------------------------- cutscenes

var _shot := {}


func opening_shots() -> Array:
	var bx := Kit.HALL_B_X
	return [
		{"from": Vector3(-24.0, 7.2, 1.0), "to": Vector3(-17.0, 6.2, 6.0), "look": Vector3(-2.0, 1.5, 46.0), "secs": 8.0,
			"text": "Halden DC-3. One data hall, forty thousand machines and, after ten at night, one person."},
		{"from": Vector3(0, 1.5, 0.6), "to": Vector3(0, 1.5, 7.5), "look": Vector3(0, 1.25, 40), "secs": 6.0,
			"text": "It takes a minute to walk one aisle end to end. There are fourteen aisles."},
		{"from": Vector3(bx, 1.6, 27.5), "to": Vector3(bx, 1.6, 22.0), "look": Vector3(bx, 1.2, -2.0), "secs": 7.0,
			"text": "For three weeks that person was Marsh. Marsh stopped coming in. Nobody on days can say why."},
		{"from": Vector3(7.9, 2.0, -6.9), "to": Vector3(6.9, 1.8, -8.3), "look": Vector3(4.6, 1.2, -11.5), "secs": 6.5,
			"text": "The work is simple. A ticket arrives on the handheld. You walk to where it says."},
		{"from": Vector3(-7.9, 1.7, -7.2), "to": Vector3(-6.6, 1.64, -8.7), "look": Vector3(-2.1, 1.3, -9.0), "secs": 5.0,
			"text": "Tonight it is you. Badge 0417.", "start": _shot_first_reader},
	]


func act_shots(n: Variant) -> Array:
	var bx := Kit.HALL_B_X
	var cz := Kit.CONSOLE_Z
	_shot = {}
	match int(n):
		2:
			return [
				{"from": Vector3(bx - 9.8, 1.6, -5.2), "to": Vector3(bx - 7.0, 1.55, -5.0), "look": Vector3(bx + 1.0, 1.25, -2.8), "secs": 7.0,
					"text": "23:10. One ticket closed. Along the corridor, two readers that were red all evening turn green.",
					"start": _shot_readers_red, "tick": _shot_readers},
			]
		4:
			return [
				{"from": Vector3(Kit.CORR_X1 - 1.4, 1.6, -4.3), "to": Vector3(Kit.CORR_X1 - 3.2, 1.6, -4.3), "look": Vector3(-9, 1.3, -4.3), "secs": 7.5,
					"text": "01:20. CH-2 restarts. Then, from the far end of the corridor, the lights go out one at a time.",
					"start": _shot_corridor_on, "tick": _shot_corridor},
				{"from": Vector3(bx, 1.5, -1.6), "to": Vector3(bx, 1.5, 2.6), "look": Vector3(bx, 1.2, 20), "secs": 6.5,
					"text": "Your badge is down to four doors. Every one of them is on the way to Zone B."},
			]
		5:
			return [
				{"from": Vector3(bx + 5.44, 1.75, cz - 12.7), "to": Vector3(bx + 5.44, 1.6, cz - 7.4), "look": Vector3(bx + 5.3, 1.1, cz), "secs": 7.0,
					"text": "02:10. Zone B, row P. A cage that is on no plan, running for one thousand one hundred and twenty-three days."},
				{"from": Vector3(bx + 7.3, 1.6, cz + 2.4), "to": Vector3(bx + 6.9, 1.45, cz + 1.4), "look": Vector3(bx + 5.2, 1.0, cz), "secs": 6.0,
					"text": "One console. One chair. Somebody has been sitting in it."},
			]
	return []


func ending_shots(kind: String) -> Array:
	var bx := Kit.HALL_B_X
	var cz := Kit.CONSOLE_Z
	_shot = {}
	match kind:
		"comply":
			return [
				{"from": Vector3(0, 1.5, 8.0), "to": Vector3(0, 1.5, 3.0), "look": Vector3(0, 1.25, 40), "secs": 7.0,
					"text": "02:31. As the mantrap closes behind you, every light in Halden DC-3 comes back on.", "start": _shot_relight},
				{"from": Vector3(5.0, 1.8, -9.9), "to": Vector3(5.0, 1.75, -8.4), "look": Vector3(5.0, 1.8, -11.9), "secs": 6.5,
					"text": "The cameras come back too. They show a technician leaving, exactly on time."},
			]
		"defy", "defy_logged":
			return [
				{"from": Vector3(-5.6, 1.55, -7.2), "to": Vector3(-5.6, 1.4, -8.6), "look": Vector3(-5.6, 1.35, -11.9), "secs": 8.0,
					"text": "The hand chain is cold. The shutter goes up one arm's length at a time.", "tick": _shot_shutter},
				{"from": Vector3(bx, 1.5, 1.0), "to": Vector3(bx, 1.5, -1.2), "look": Vector3(bx, 1.2, 20), "secs": 6.0,
					"text": "Behind you, Zone B is dark. Nothing in it is predicting anything."},
			]
		"stay":
			return [
				{"from": Vector3(bx + 7.6, 1.75, cz + 2.2), "to": Vector3(bx + 6.7, 1.4, cz + 1.0), "look": Vector3(bx + 5.2, 1.0, cz), "secs": 7.0,
					"text": "You sit. The chair is still warm."},
				{"from": Vector3(bx, 3.0, -2.2), "to": Vector3(bx, 3.0, -1.6), "look": Vector3(bx, 0.4, 11.0), "secs": 6.5,
					"text": "The log scrolls under your hands. You change one line, then another."},
			]
	return []


func _shot_first_reader() -> void:
	kit.doors["dock_mantrap"].set_state("green")


func _shot_readers_red() -> void:
	for id: String in ["hall_b1", "hall_b2"]:
		kit.doors[id].set_state("red")


func _shot_readers(k: float) -> void:
	if k > 0.5 and not _shot.has("b1"):
		_shot["b1"] = true
		kit.doors["hall_b1"].set_state("green")
		game.sound.play("beep", -8.0)
	if k > 0.62 and not _shot.has("b2"):
		_shot["b2"] = true
		kit.doors["hall_b2"].set_state("green")
		game.sound.play("beep", -12.0)


func _shot_corridor_on() -> void:
	kit.set_room_lit("corridor", true)
	_shot["out"] = 0


func _shot_corridor(k: float) -> void:
	# the corridor is long; only the last eight fittings are near enough to watch
	var n: int = kit.rooms["corridor"].lamps.size()
	var out := clampi(int(k * 10.5), 0, 8)
	for i in n:
		kit.set_lamp("corridor", i, i >= n - 8 + out)
	if out != int(_shot.get("out", 0)):
		_shot["out"] = out
		game.sound.play("tick", -3.0, randf_range(0.75, 0.9))


func _shot_relight() -> void:
	kit.set_hall_lit("a", true)
	kit.set_hall_lit("b", true)
	for id: String in ["corridor", "dock", "mantrap", "mmr", "ups", "chillers", "security"]:
		kit.set_room_lit(id, true)
	game.sound.play("breaker", -4.0, 1.2)


func _shot_shutter(k: float) -> void:
	# five pulls on the chain
	var pulls := k * 5.0
	var done := floorf(pulls) + smoothstep(0.0, 0.55, pulls - floorf(pulls))
	kit.set_shutter(minf(1.0, done / 5.0))
	if int(pulls) != int(_shot.get("pull", -1)) and k < 1.0:
		_shot["pull"] = int(pulls)
		game.sound.play("door", -4.0, 0.7)


# ---------------------------------------------------------------- self-test

func _check(ok: bool, what: String) -> void:
	if ok:
		return
	print("AUTOTEST FAILED  ", what, "  (act %d, step %s, room %s)" % [act, step, game.room])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.coldAisleTest = 'FAILED %s'" % what.replace("'", ""), true)
	get_tree().quit(1)


## `autotest=comply|defy|stay` plays the whole night through the same calls the player
## makes, and fails loudly if any act cannot be completed. `playtest=` does the same with
## simulated keys and real walking: see bot.gd.
func autotest(ending: String, walk := false) -> void:
	if walk:
		var bot := Node.new()
		bot.set_script(load("res://scripts/bot.gd"))
		add_child(bot)
		bot.run(game, ending)
		return
	var pl: CharacterBody3D = game.player
	var use := func(id: String, at: Vector3) -> void:
		pl.global_position = at
		await get_tree().create_timer(0.3).timeout
		_check(prompt_for(id) != "", "nothing to do at " + id + " in step " + step)
		on_use(id)
		await get_tree().create_timer(0.3).timeout
		if game.terminal.is_open:
			game.terminal.close()
	var badge := func(id: String) -> void:
		var d: Node3D = kit.doors[id]
		d.badge()
		await get_tree().create_timer(0.2).timeout
		if d.open <= 0.0:
			d.badge()   # a defied door refuses once
		_check(d.open > 0.0 or d._target > 0.0, "door did not open: " + id)
		await get_tree().create_timer(0.2).timeout
	var want := func(s: String) -> void:
		_check(step == s, "expected step %s, got %s (act %d)" % [s, step, act])
		print("  ok  act %d  %s  %s" % [act, step, game.clock_text()])
	var defiant := ending != "comply"
	new_game()
	game.started = true
	await get_tree().create_timer(0.5).timeout
	await badge.call("dock_mantrap")
	await badge.call("mantrap_corr")
	pl.global_position = Vector3(0, 0.02, -4.3)
	await get_tree().create_timer(0.5).timeout
	want.call("to_security")
	await badge.call("security")
	await use.call("handheld", Vector3(4, 0.02, -10))
	want.call("swap")
	await badge.call("hall_a1")
	await use.call("rack_a147", Vector3(0, 0.02, 4.6))
	await get_tree().create_timer(2.0).timeout
	want.call("return")
	await use.call("desk_bin", Vector3(7.5, 0.02, -10))
	await get_tree().create_timer(4.0).timeout
	_check(act == 2, "act 2 did not start")
	await get_tree().create_timer(21.0).timeout
	await badge.call("hall_b1")
	pl.global_position = Vector3(Kit.HALL_B_X, 0.02, 3.0)
	await get_tree().create_timer(10.5).timeout
	want.call("console")
	pl.global_position = Vector3(Kit.HALL_B_X, 0.02, 4.0)
	_console_b()
	_console_b_log()
	_console_b_clear()
	game.terminal.close()
	want.call("ups")
	await badge.call("hall_b1" if defiant else "hall_b2")
	await badge.call("ups")
	await use.call("breaker_b2", Vector3(24, 0.02, -9))
	want.call("to_desk2")
	await badge.call("security")
	await use.call("cctv", Vector3(5, 0.02, -10))
	await get_tree().create_timer(4.0).timeout
	_check(act == 3 and game.cctv.is_open, "act 3 did not open the cameras")
	await get_tree().create_timer(13.0).timeout
	game.cctv.close()
	want.call("fire_panel")
	await badge.call("hall_a2" if defiant else "hall_a1")
	pl.global_position = Vector3(0, 0.02, 12.0)
	await get_tree().create_timer(3.0).timeout
	await use.call("fire_panel_a", Vector3(2, 0.02, Kit.HALL_Z1 - 1.44))
	want.call("abort")
	await use.call("abort_a", Vector3(0, 0.02, -1.5))
	want.call("chiller")
	await badge.call("hall_a2")
	await badge.call("chillers")
	await use.call("chiller2", Vector3(31.8 + Kit.CH_DX, 0.02, 2.8))
	await get_tree().create_timer(4.0).timeout
	_check(act == 4, "act 4 did not start")
	await use.call("note1", Vector3(31.8 + Kit.CH_DX, 0.02, 4.4))
	await get_tree().create_timer(5.0).timeout
	await badge.call("hall_b2")
	await use.call("hatch_b", Vector3(Kit.HALL_B_X - Kit.AISLE_PITCH, 0.02, Kit.AISLE_LEN + 0.5))
	await get_tree().create_timer(1.5).timeout
	_check(game.room == "plenum", "not in the plenum: " + game.room)
	await use.call("hatch_m", kit.spots["plenum_m"][0])
	await get_tree().create_timer(1.5).timeout
	_check(game.room == "mmr", "not in the meet-me room")
	await use.call("note2", Vector3(13.9, 0.02, -9.8))
	await use.call("panel7", Vector3(13.4, 0.02, -9.8))
	await use.call("damper", Vector3(17.0, 0.02, -9.0))
	await use.call("hatch_mmr", Vector3(16.5, 0.02, -8.0))
	await get_tree().create_timer(1.5).timeout
	await use.call("note3", kit.cell_pos(15, 1))
	await use.call("hatch_c", kit.spots["plenum_c"][0])
	await get_tree().create_timer(4.0).timeout
	_check(act == 5 and kit.in_cage(pl.global_position), "act 5 did not start in the cage")
	_console_7()
	_console_7_model()
	_console_7_subjects()
	if ending == "stay":
		_check(_all_notes(), "notes missing")
		game.terminal.close()
		_ending("stay")
	else:
		game.terminal.close()
		on_use("cage_gate")
		pl.global_position = Vector3(Kit.HALL_B_X, 0.02, -1.6)
		await get_tree().create_timer(0.4).timeout
		if ending == "defy":
			on_use("epo_b")
			await get_tree().create_timer(0.5).timeout
			await badge.call("dock_corr")
			await use.call("dock_shutter", Vector3(-5.6, 0.02, -10.5))
		else:
			await badge.call("hall_b2")
			await badge.call("mantrap_corr")
			pl.global_position = Vector3(-0.5, 0.02, -9.0)
	await get_tree().create_timer(3.0).timeout
	_check(ended, "no ending reached")
	print("AUTOTEST OK  ending=%s  defy=%d  clock=%s" % [ending, defy, game.clock_text()])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.coldAisleTest = 'OK %s'" % ending, true)
	get_tree().quit()


## `-- --walktest` pushes the player through every doorway and along the whole crawl
## space with real collision, to catch a wall or a ceiling in the wrong place.
func walktest() -> void:
	var pl: CharacterBody3D = game.player
	game.started = true
	begin_act(5, true)
	flags["console7"] = true
	grant(DOOR_IDS)
	var bad := 0
	for id: String in DOOR_IDS:
		var d: Node3D = kit.doors[id]
		var n := Vector3.BACK if d._slide == Vector3.RIGHT else Vector3.RIGHT
		d.open_now(99.0)
		pl.place(d.position - n * 1.3 + Vector3(0, 0.02, 0), 0.0)
		await get_tree().create_timer(0.8).timeout
		pl.auto_dir = n
		await get_tree().create_timer(2.0).timeout
		pl.auto_dir = Vector3.ZERO
		var through := (pl.global_position - d.position).dot(n)
		print("  door %-14s %s  (%.2f m past)" % [id, "ok" if through > 1.0 else "BLOCKED", through])
		if through <= 1.0:
			bad += 1
	# the crawl: Zone B hatch to the meet-me room, then on through the damper to Cage 7
	kit.set_damper(true)
	var marks := {}
	for row in Kit.PLENUM_MAP.size():
		for c in Kit.PLENUM_MAP[row].length():
			if Kit.PLENUM_MAP[row][c] in ["H", "M", "C", "N"]:
				marks[Kit.PLENUM_MAP[row][c]] = Vector2i(c, row)
	for leg: Array in [["H", "M"], ["M", "C"], ["C", "N"]]:
		var path: Array[Vector2i] = kit._plenum_path(marks[leg[0]], marks[leg[1]])
		pl.place(kit.cell_pos(path[0].x, path[0].y) + Vector3(0, 0.02, 0), 0.0)
		await get_tree().create_timer(0.3).timeout
		var stuck := false
		for cell: Vector2i in path:
			var goal: Vector3 = kit.cell_pos(cell.x, cell.y)
			var t := 0.0
			while Vector2(pl.global_position.x - goal.x, pl.global_position.z - goal.z).length() > 0.15 and t < 6.0:
				pl.auto_dir = Vector3(goal.x - pl.global_position.x, 0, goal.z - pl.global_position.z)
				await get_tree().physics_frame
				t += get_physics_process_delta_time()
			if t >= 6.0:
				stuck = true
				break
		pl.auto_dir = Vector3.ZERO
		print("  crawl %s to %s   %s   crouching=%s  y=%.2f" % [leg[0], leg[1], "STUCK" if stuck else "ok", pl.crouching, pl.global_position.y])
		if stuck or not pl.crouching:
			bad += 1
	print("WALKTEST %s" % ("OK" if bad == 0 else "FAILED: %d" % bad))
	get_tree().quit()
