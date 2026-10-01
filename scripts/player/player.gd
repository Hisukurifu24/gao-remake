class_name Player
extends CharacterBody2D
## Top-down 8-direction player controller.
##
## The sprite sheet is the Ninja Adventure layout: 4 columns (down, up, left,
## right) by 7 rows, the first 4 of them the walk cycle. Driven by
## [member Sprite2D.frame] rather than an AnimationPlayer.

const DIR_COLUMNS := {
	Vector2i(0, 1): 0,   # down
	Vector2i(0, -1): 1,  # up
	Vector2i(-1, 0): 2,  # left
	Vector2i(1, 0): 3,   # right
}
## Who you are, drawn: the map walks this sheet and the battle screen stands it
## on the field, so the two can't drift onto different characters.
const SHEET := preload("res://assets/ninja_adventure/Actor/Character/SamuraiBlue/SpriteSheet.png")
## The sheet's row of attack poses, one per facing column.
const ATTACK_ROW := 4
const WALK_FPS := 8.0
const WALK_FRAMES := 4
## A conversation ends on the same press that closed it, and a player mashing
## through text is still pressing interact a few frames later -- straight back
## into the NPC they just finished with. Interaction goes deaf for a moment
## after any box closes, chests and signs included.
const INTERACT_GRACE := 0.25

@export var speed := 90.0
@export var acceleration := 1200.0
@export var friction := 1600.0

## Facing is snapped to 4 directions for sprite/interaction purposes even
## though movement itself is free 8-direction.
var facing := Vector2.DOWN

var _walk_time := 0.0
var _target: Interactable = null
var _deaf_until := 0.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _sensor: Area2D = $InteractSensor


func _ready() -> void:
	_sprite.texture = SHEET
	EventBus.dialogue_finished.connect(_on_dialogue_finished)


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


## A map swap frees the player with a target still set, and the next map's player
## starts with none -- so nothing would ever announce the change, and the HUD would
## keep offering to talk to someone two maps away.
func _exit_tree() -> void:
	if _target != null:
		_target = null
		EventBus.interact_target_changed.emit(null)


func _on_dialogue_finished(_dialogue_id: StringName) -> void:
	_deaf_until = _seconds() + INTERACT_GRACE


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"interact"):
		return
	if GameState.is_input_locked() or _target == null:
		return
	if _seconds() < _deaf_until:
		return
	get_viewport().set_input_as_handled()
	_target.interact(self)


func _seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func _snap_to_4(dir: Vector2) -> Vector2:
	# Ties go to the vertical axis, which reads better for a top-down sprite.
	if absf(dir.x) > absf(dir.y):
		return Vector2(signf(dir.x), 0.0)
	return Vector2(0.0, signf(dir.y))


func _update_sprite() -> void:
	var column: int = DIR_COLUMNS[Vector2i(facing)]
	var row := 0
	if _walk_time > 0.0:
		row = int(_walk_time * WALK_FPS) % WALK_FRAMES
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
