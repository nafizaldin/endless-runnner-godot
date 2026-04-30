extends CharacterBody3D

@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var animation_player: AnimationPlayer = $Character/AnimationPlayer
@onready var camera: Camera3D = $Camera3D
@onready var gui: Control = $gui
@onready var death_overlay: ColorRect = $gui/death_overlay
@onready var died_label: Label = $gui/died_label
@onready var countdown_label: Label = $gui/countdown_label
@onready var coin_label: Label = gui.get_node("label") as Label

const MOVE_SPEED: float = 8.0
const JUMP_VELOCITY: float = 8.0  # Jump strength
const GRAVITY: float = 24.0  # Gravity strength
const LANES: Array = [-2, 0, 2]  # Lane positions on x-axis
const FOV_LANDSCAPE: float = 70.0
const FOV_PORTRAIT: float = 86.0

## Min swipe length as a fraction of min(viewport width, height)
const SWIPE_MIN_FRACTION: float = 0.06

var starting_point: Vector3 = Vector3.ZERO
var current_lane: int = 1  # Start at lane index 1 (x = 0)
var target_lane: int = 1

var is_jumping: bool = false
var is_dead: bool = false
var _swipe_start: Vector2 = Vector2.ZERO
var _swipe_index: int = 0
var _mouse_swipe_down: bool = false
var _swipe_cooldown_ms: int = 0
const SWIPE_DEBOUNCE_MS: int = 120
var _jump_requested: bool = false

func _ready() -> void:
	coin_label.text = "Coins: "
	starting_point = global_transform.origin
	_on_viewport_size_changed()
	var vp: Viewport = get_viewport()
# warning-ignore:return_value_discarded
	vp.size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
	var s: Vector2 = get_viewport().get_visible_rect().size
	if s.x < 1.0 or s.y < 1.0:
		return
	var aspect: float = s.x / s.y
	if aspect < 1.0:
		camera.fov = lerp(FOV_PORTRAIT, FOV_LANDSCAPE, clamp(aspect, 0.0, 1.0))
	else:
		camera.fov = FOV_LANDSCAPE
	_apply_ui_scale(s)

func _apply_ui_scale(s: Vector2) -> void:
	var f: float = clamp(s.y / 720.0, 0.45, 2.2)
	coin_label.add_theme_font_size_override("font_size", int(20.0 * f))
	died_label.add_theme_font_size_override("font_size", int(48.0 * f))
	countdown_label.add_theme_font_size_override("font_size", int(36.0 * f))

func _input(event: InputEvent) -> void:
	# Web often sends left-button mouse for touch; mobile sends ScreenTouch.
	# Swallow duplicate touch+emulated mouse with debounce in _apply_swipe().
	if is_dead:
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			_swipe_start = t.position
			_swipe_index = t.index
		else:
			if t.index == _swipe_index:
				_apply_swipe_safe(_swipe_start, t.position)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_swipe_start = mb.position
				_mouse_swipe_down = true
			else:
				if _mouse_swipe_down:
					_apply_swipe_safe(_swipe_start, mb.position)
				_mouse_swipe_down = false
			get_viewport().set_input_as_handled()
		return

func _min_swipe_pixels() -> float:
	var s: Vector2 = get_viewport().get_visible_rect().size
	return min(s.x, s.y) * SWIPE_MIN_FRACTION

func _apply_swipe_safe(start: Vector2, end: Vector2) -> void:
	var now: int = int(Time.get_ticks_msec())
	if now - _swipe_cooldown_ms < SWIPE_DEBOUNCE_MS:
		return
	if not _apply_swipe(start, end):
		return
	_swipe_cooldown_ms = now

func _apply_swipe(start: Vector2, end: Vector2) -> bool:
	var d: Vector2 = end - start
	if d.length() < _min_swipe_pixels():
		return false
	if abs(d.x) > abs(d.y):
		if d.x < 0.0 and target_lane > 0:
			target_lane -= 1
			return true
		elif d.x > 0.0 and target_lane < LANES.size() - 1:
			target_lane += 1
			return true
	else:
		if d.y < 0.0:
			_jump_requested = true
			return true
	return false

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector3.ZERO
		animation_player.play("Idle")
		return

	var direction: Vector3 = Vector3.ZERO
	
	# Handle lane switching
	if Input.is_action_just_pressed("ui_left") and target_lane > 0:
		target_lane -= 1
	if Input.is_action_just_pressed("ui_right") and target_lane < LANES.size() - 1:
		target_lane += 1
	
	# Move towards the target lane
	var target_x: float = LANES[target_lane]
	var current_x: float = global_transform.origin.x
	global_transform.origin.x = lerp(current_x, target_x, MOVE_SPEED * delta)

	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0  # Reset vertical velocity when on the floor

	# Jumping logic (keyboard / gamepad + swipe)
	if is_on_floor() and (Input.is_action_just_pressed("ui_up") or _jump_requested):
		velocity.y = JUMP_VELOCITY
		_jump_requested = false
	elif not is_on_floor():
		_jump_requested = false

	# Apply the velocity and move the character
	move_and_slide()

	# Play animations based on movement
	if not is_on_floor():
		animation_player.play("Jump")
	else:
		animation_player.play("Run")

var coin_count: int = 0
func _on_collision_area_entered(area):
	var parent = area.get_parent()
	if parent.is_in_group("coins"):
		audio_player.play()
		coin_count += 1
		coin_label.text = "Coins: " + str(coin_count)
		parent.queue_free()

func show_death_ui(show_died: bool, countdown_text: String = "") -> void:
	death_overlay.visible = show_died
	died_label.visible = show_died
	countdown_label.visible = countdown_text != ""
	if countdown_text != "":
		countdown_label.text = countdown_text
