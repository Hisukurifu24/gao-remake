class_name Player
extends CharacterBody2D
## Top-down 8-direction player controller.
##
## The sprite sheet is 4 columns (walk cycle) by 4 rows (down, up, left, right),
## driven by [member Sprite2D.frame] rather than an AnimationPlayer -- placeholder
## art, placeholder animation.

const DIR_ROWS := {
	Vector2i(0, 1): 0,   # down
	Vector2i(0, -1): 1,  # up
	Vector2i(-1, 0): 2,  # left
	Vector2i(1, 0): 3,   # right
}
const WALK_FPS := 8.0

@export var speed := 90.0
@export var acceleration := 1200.0
@export var friction := 1600.0

## Facing is snapped to 4 directions for sprite/interaction purposes even
## though movement itself is free 8-direction.
var facing := Vector2.DOWN

var _walk_time := 0.0
var _target: Interactable = null

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _sensor: Area2D = $InteractSensor


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if not GameState.is_input_locked():
		input = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")

	if input != Vector2.ZERO:
		velocity = velocity.move_toward(input * speed, acceleration * delta)
		facing = _snap_to_4(input)
		_walk_time += delta
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		_walk_time = 0.0

	move_and_slide()
	_update_sprite()
	_update_sensor()
	_refresh_target()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"interact"):
		return
	if GameState.is_input_locked() or _target == null:
		return
	get_viewport().set_input_as_handled()
	_target.interact(self)


func _snap_to_4(dir: Vector2) -> Vector2:
	# Ties go to the vertical axis, which reads better for a top-down sprite.
	if absf(dir.x) > absf(dir.y):
		return Vector2(signf(dir.x), 0.0)
	return Vector2(0.0, signf(dir.y))


func _update_sprite() -> void:
	var row: int = DIR_ROWS[Vector2i(facing)]
	var column := 0
	if _walk_time > 0.0:
		column = int(_walk_time * WALK_FPS) % 4
	_sprite.frame = row * _sprite.hframes + column


func _update_sensor() -> void:
	_sensor.position = facing * 10.0


## Picks the interactable the player is most plainly facing: in front, then closest.
func _refresh_target() -> void:
	var best: Interactable = null
	var best_score := -INF
	for area in _sensor.get_overlapping_areas():
		var candidate := area as Interactable
		if candidate == null or not candidate.is_available():
			continue
		var offset := candidate.global_position - global_position
		if offset.length() > 0.001 and offset.normalized().dot(facing) < 0.0:
			continue  # behind us
		var score := -offset.length()
		if score > best_score:
			best_score = score
			best = candidate

	if best == _target:
		return
	_target = best
	EventBus.interact_target_changed.emit(_target)
