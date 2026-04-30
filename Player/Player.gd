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
const SWIPE_MIN_FRACTION: float = 0.04

## Set false to disable verbose swipe / pointer logging in the console.
const SWIPE_DEBUG_LOG: bool = true
## 0 = log every InputEventMouseMotion (very noisy). 100 = at most one line per 100ms while moving.
const SWIPE_DEBUG_MOTION_LOG_INTERVAL_MS: int = 0
var _swipe_debug_last_motion_log_ms: int = 0

var starting_point: Vector3 = Vector3.ZERO
var current_lane: int = 1  # Start at lane index 1 (x = 0)
var target_lane: int = 1

var is_jumping: bool = false
var is_dead: bool = false
var _swipe_start: Vector2 = Vector2.ZERO
## Updated every frame while dragging; web often gives same pos on up as down if we do not track motion
var _swipe_end: Vector2 = Vector2.ZERO
var _swipe_index: int = 0
var _mouse_swipe_down: bool = false
var _touch_pointer_down: bool = false
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
	if SWIPE_DEBUG_LOG:
# warning-ignore:return_value_discarded
		gui.gui_input.connect(_on_swipe_debug_gui_input)
		print("[SWIPE_DEBUG] logging ON | Player node + $gui.gui_input | set SWIPE_DEBUG_LOG=false in Player.gd to disable")

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

func _swipe_debug_is_pointer_event(e: InputEvent) -> bool:
	return (
		e is InputEventScreenTouch
		or e is InputEventScreenDrag
		or e is InputEventMouseButton
		or e is InputEventMouseMotion
		or e is InputEventMagnifyGesture
		or e is InputEventPanGesture
	)

func _on_swipe_debug_gui_input(e: InputEvent) -> void:
	# With mouse_filter=IGNORE, this may never fire; if it does, you will see it here.
	_swipe_debug_log_line("Player.$gui.gui_input", e)

func _unhandled_input(event: InputEvent) -> void:
	if not SWIPE_DEBUG_LOG or not _swipe_debug_is_pointer_event(event):
		return
	# If you see the same event here and in _input, that event was not marked "handled" earlier.
	_swipe_debug_log_line("Player._unhandled_input (still unhandled)", event)

## Console lines all start with [SWIPE_DEBUG] for easy copy-paste to the dev.
func _swipe_debug_log_line(context: String, e: InputEvent) -> void:
	if not SWIPE_DEBUG_LOG:
		return
	if e is InputEventMouseMotion and SWIPE_DEBUG_MOTION_LOG_INTERVAL_MS > 0:
		var t2: int = int(Time.get_ticks_msec())
		if t2 - _swipe_debug_last_motion_log_ms < SWIPE_DEBUG_MOTION_LOG_INTERVAL_MS:
			return
		_swipe_debug_last_motion_log_ms = t2
	var line: String = "[SWIPE_DEBUG] " + context
	line += " | dead=" + str(is_dead)
	line += " | vp=" + str(get_viewport().get_visible_rect().size)
	line += " | " + e.get_class() + " | " + e.as_text()
	if e is InputEventScreenTouch:
		var st: InputEventScreenTouch = e
		line += " | index=" + str(st.index) + " pos=" + str(st.position) + " pressed=" + str(st.pressed)
	if e is InputEventScreenDrag:
		var sd: InputEventScreenDrag = e
		line += " | index=" + str(sd.index) + " pos=" + str(sd.position) + " rel=" + str(sd.relative)
	if e is InputEventMouseButton:
		var mb: InputEventMouseButton = e
		line += " | btn=" + str(mb.button_index) + " pos=" + str(mb.position) + " pressed=" + str(mb.pressed) + " 2x=" + str(mb.doubleclick)
	if e is InputEventMouseMotion:
		var mm: InputEventMouseMotion = e
		line += " | pos=" + str(mm.position) + " rel=" + str(mm.relative) + " mask=" + str(mm.button_mask)
	if e is InputEventMagnifyGesture:
		var mg: InputEventMagnifyGesture = e
		line += " | pos=" + str(mg.position) + " factor=" + str(mg.factor)
	if e is InputEventPanGesture:
		var pg: InputEventPanGesture = e
		line += " | pos=" + str(pg.position) + " delta=" + str(pg.delta)
	print(line)

func _input(event: InputEvent) -> void:
	# Web: touch is often emulated as mouse. Release position can match press unless we
	# update _swipe_end during InputEventMouseMotion and InputEventScreenDrag.
	if SWIPE_DEBUG_LOG and _swipe_debug_is_pointer_event(event):
		_swipe_debug_log_line("Player._input", event)
	if is_dead:
		return
	if event is InputEventScreenDrag:
		var sdrag: InputEventScreenDrag = event
		if _touch_pointer_down and sdrag.index == _swipe_index:
			_swipe_end = sdrag.position
		return
	if event is InputEventMouseMotion:
		if _mouse_swipe_down and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
			_swipe_end = (event as InputEventMouseMotion).position
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			_swipe_start = t.position
			_swipe_end = t.position
			_swipe_index = t.index
			_touch_pointer_down = true
		else:
			if t.index == _swipe_index and _touch_pointer_down:
				_swipe_end = t.position
				_apply_swipe_safe(_swipe_start, _swipe_end)
			_touch_pointer_down = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_swipe_start = mb.position
				_swipe_end = mb.position
				_mouse_swipe_down = true
			else:
				if _mouse_swipe_down:
					_swipe_end = mb.position
					_apply_swipe_safe(_swipe_start, _swipe_end)
				_mouse_swipe_down = false
			get_viewport().set_input_as_handled()
		return

func _min_swipe_pixels() -> float:
	var s: Vector2 = get_viewport().get_visible_rect().size
	return min(s.x, s.y) * SWIPE_MIN_FRACTION

func _apply_swipe_safe(start: Vector2, end: Vector2) -> void:
	if SWIPE_DEBUG_LOG:
		var dist: float = start.distance_to(end)
		var min_px: float = _min_swipe_pixels()
		print(
			"[SWIPE_DEBUG] _apply_swipe_safe | start=",
			start, " end=", end, " dist=", snappedf(dist, 0.1), " min_px=", snappedf(min_px, 0.1),
			" | touch_down=", _touch_pointer_down, " mouse_down=", _mouse_swipe_down
		)
	var now: int = int(Time.get_ticks_msec())
	if now - _swipe_cooldown_ms < SWIPE_DEBOUNCE_MS:
		if SWIPE_DEBUG_LOG:
			print("[SWIPE_DEBUG] _apply_swipe_safe SKIPPED (debounce ", SWIPE_DEBOUNCE_MS, "ms)")
		return
	if not _apply_swipe(start, end):
		return
	_swipe_cooldown_ms = now

func _apply_swipe(start: Vector2, end: Vector2) -> bool:
	var d: Vector2 = end - start
	if d.length() < _min_swipe_pixels():
		if SWIPE_DEBUG_LOG:
			print(
				"[SWIPE_DEBUG] _apply_swipe | REJECT: too short | |d|=",
				snappedf(d.length(), 0.1), " < min=", snappedf(_min_swipe_pixels(), 0.1)
			)
		return false
	if abs(d.x) > abs(d.y):
		if d.x < 0.0 and target_lane > 0:
			if SWIPE_DEBUG_LOG:
				print("[SWIPE_DEBUG] _apply_swipe | LANE left (swipe left)")
			target_lane -= 1
			return true
		elif d.x > 0.0 and target_lane < LANES.size() - 1:
			if SWIPE_DEBUG_LOG:
				print("[SWIPE_DEBUG] _apply_swipe | LANE right (swipe right)")
			target_lane += 1
			return true
		if SWIPE_DEBUG_LOG:
			print("[SWIPE_DEBUG] _apply_swipe | horizontal swipe but no lane change | d=", d, " lane=", target_lane)
	else:
		if d.y < 0.0:
			if SWIPE_DEBUG_LOG:
				print("[SWIPE_DEBUG] _apply_swipe | JUMP (swipe up)")
			_jump_requested = true
			return true
		if SWIPE_DEBUG_LOG:
			print("[SWIPE_DEBUG] _apply_swipe | vertical swipe not up (no jump) | d=", d)
	if SWIPE_DEBUG_LOG:
		print("[SWIPE_DEBUG] _apply_swipe | no action matched | d=", d, " target_lane=", target_lane)
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
