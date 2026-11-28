extends CharacterBody3D
## First-person technician: walk, jog, crouch, torch, and one key to use things. No jump.

const WALK_SPEED := 1.9
const JOG_SPEED := 3.7
const CROUCH_SPEED := 1.0
const EYE_STAND := 1.64
const EYE_CROUCH := 0.92
const MOUSE_SENS := 0.0022
const REACH := 2.3

var game: Node
var camera: Camera3D
var torch: SpotLight3D
var frozen := false          # true while a console or the cameras hold your attention
var sens := 1.0
var target: Object = null    # the usable thing under the reticle, if any
var jogging := false
var crouching := false
var torch_flicker := 0.0     # 0..1, set by the story near Cage 7 equipment
var touch_move := Vector2.ZERO  # the on-screen stick
var touch_jog := false
var touch_crouch := false
var auto_dir := Vector3.ZERO  # tests only: walk this way as if a key were held

var _shape: CapsuleShape3D
var _col: CollisionShape3D
var _pitch := 0.0
var _eye := EYE_STAND
var _bob := 0.0
var _stride := 0.0
var _wake := 0.0     # 1 = lying on the floor, 0 = up


func _ready() -> void:
	collision_mask = 1
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.28
	_shape.height = 1.8
	_col = CollisionShape3D.new()
	_col.shape = _shape
	_col.position.y = 0.9
	add_child(_col)

	camera = Camera3D.new()
	camera.fov = 66.0
	camera.near = 0.05
	camera.far = 80.0
	camera.position.y = EYE_STAND
	add_child(camera)
	camera.make_current()

	torch = SpotLight3D.new()
	torch.light_color = Color(0.86, 0.93, 1.0)
	torch.light_energy = 40.0
	torch.spot_range = 16.0
	torch.spot_angle = 34.0
	torch.spot_angle_attenuation = 1.6
	torch.spot_attenuation = 0.7
	torch.shadow_enabled = true
	torch.position = Vector3(0.18, -0.16, -0.1)
	torch.visible = false
	camera.add_child(torch)


## Called by main.gd: the player lives inside a SubViewport, which does not receive input itself.
func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative)
	elif event.is_action_pressed("torch") and not frozen:
		toggle_torch()
	elif event.is_action_pressed("interact") and not frozen:
		use_target()


func look(rel: Vector2) -> void:
	if frozen:
		return
	rotate_y(-rel.x * MOUSE_SENS * sens)
	_pitch = clampf(_pitch - rel.y * MOUSE_SENS * sens, -1.45, 1.45)


func toggle_torch() -> void:
	torch.visible = not torch.visible
	game.sound.play("tick", -6.0, 1.6)


## Come round on the floor and get up. Used after being caught.
func wake() -> void:
	_wake = 1.0


func use_target() -> void:
	if target == null:
		return
	if target.has_meta("door"):
		(target.get_meta("door") as Node).badge()
	elif target.has_meta("use_id"):
		game.story.on_use(String(target.get_meta("use_id")))


func place(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation.y = yaw
	velocity = Vector3.ZERO
	_pitch = 0.0
	if pos.y < -10.0:
		# arriving under the floor: already on hands and knees
		_shape.height = 1.05
		_col.position.y = 0.525
		_eye = EYE_CROUCH


func _physics_process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	# a low ceiling keeps you down
	var up := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.3, 0), global_position + Vector3(0, 1.9, 0), 1)
	up.exclude = [get_rid()]
	var low := not space.intersect_ray(up).is_empty()
	crouching = low or ((Input.is_action_pressed("crouch") or touch_crouch) and not frozen)
	jogging = (Input.is_action_pressed("jog") or touch_jog) and not crouching and not frozen
	var speed := CROUCH_SPEED if crouching else (JOG_SPEED if jogging else WALK_SPEED)

	var input := Vector2.ZERO if frozen else Input.get_vector("move_left", "move_right", "move_forward", "move_back") + touch_move
	var dir := (global_transform.basis * Vector3(input.x, 0.0, input.y))
	dir.y = 0.0
	if dir.length() > 1.0:
		dir = dir.normalized()
	if auto_dir != Vector3.ZERO:
		dir = auto_dir.normalized()
	var want := dir * speed
	velocity.x = move_toward(velocity.x, want.x, 14.0 * delta)
	velocity.z = move_toward(velocity.z, want.z, 14.0 * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 9.8 * delta
	move_and_slide()

	# crouch: lower the eye and shrink the capsule
	_eye = lerpf(_eye, EYE_CROUCH if crouching else EYE_STAND, 1.0 - exp(-10.0 * delta))
	_shape.height = lerpf(_shape.height, 1.05 if crouching else 1.8, 1.0 - exp(-10.0 * delta))
	_col.position.y = _shape.height * 0.5

	# a small head bob tied to ground speed, and a footstep every stride
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	_bob += delta * ground_speed * 3.4
	var bob_amt := clampf(ground_speed / JOG_SPEED, 0.0, 1.0) * 0.022
	_wake = maxf(0.0, _wake - delta / 4.5)
	var down := smoothstep(0.0, 1.0, clampf(_wake * 1.4, 0.0, 1.0))
	camera.position.y = lerpf(_eye + sin(_bob * 2.0) * bob_amt, 0.24, down)
	camera.position.x = cos(_bob) * bob_amt * 0.6
	camera.rotation = Vector3(_pitch + down * 0.5, down * 0.35, down * 1.25)
	_stride += delta * ground_speed
	if _stride > (0.62 if crouching else 0.78):
		_stride = 0.0
		game.footstep(jogging, crouching)
	jogging = jogging and ground_speed > 2.4

	# what is under the reticle
	var from := camera.global_position
	var ray := PhysicsRayQueryParameters3D.create(from, from - camera.global_transform.basis.z * REACH, 3)
	ray.exclude = [get_rid()]
	ray.hit_from_inside = true
	var hit := space.intersect_ray(ray)
	target = null
	if not hit.is_empty() and not frozen:
		var c: Object = hit["collider"]
		if c.has_meta("door") or (c.has_meta("use_id") and game.story.prompt_for(String(c.get_meta("use_id"))) != ""):
			target = c

	if torch.visible and torch_flicker > 0.0:
		var n := sin(Time.get_ticks_msec() * 0.031) * sin(Time.get_ticks_msec() * 0.0173)
		torch.light_energy = 40.0 * (1.0 - torch_flicker * (0.5 + 0.5 * n) * (1.0 if randf() > 0.08 else 1.6))
	else:
		torch.light_energy = 40.0
