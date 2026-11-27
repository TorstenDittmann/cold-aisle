extends CharacterBody3D
## First-person technician: walk, jog, crouch, torch. No jump.

const WALK_SPEED := 1.9
const JOG_SPEED := 3.7
const CROUCH_SPEED := 1.0
const EYE_STAND := 1.64
const EYE_CROUCH := 0.92
const MOUSE_SENS := 0.0022

var camera: Camera3D
var torch: SpotLight3D
var _shape: CapsuleShape3D
var _col: CollisionShape3D
var _pitch := 0.0
var _eye := EYE_STAND
var _bob := 0.0


func _ready() -> void:
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
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.45, 1.45)
		camera.rotation.x = _pitch
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("torch"):
		torch.visible = not torch.visible


func _physics_process(delta: float) -> void:
	var crouching := Input.is_action_pressed("crouch")
	var jogging := Input.is_action_pressed("jog") and not crouching
	var speed := CROUCH_SPEED if crouching else (JOG_SPEED if jogging else WALK_SPEED)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (global_transform.basis * Vector3(input.x, 0.0, input.y))
	dir.y = 0.0
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, 14.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 14.0 * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 9.8 * delta
	move_and_slide()

	# crouch: lower the eye and shrink the capsule
	_eye = lerpf(_eye, EYE_CROUCH if crouching else EYE_STAND, 1.0 - exp(-10.0 * delta))
	_shape.height = lerpf(_shape.height, 1.05 if crouching else 1.8, 1.0 - exp(-10.0 * delta))
	_col.position.y = _shape.height * 0.5

	# a small head bob tied to ground speed
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	_bob += delta * ground_speed * 3.4
	var bob_amt := clampf(ground_speed / JOG_SPEED, 0.0, 1.0) * 0.022
	camera.position.y = _eye + sin(_bob * 2.0) * bob_amt
	camera.position.x = cos(_bob) * bob_amt * 0.6
