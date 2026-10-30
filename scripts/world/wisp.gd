class_name Wisp
extends Node2D
## A small bright spirit that leads you somewhere -- Genshin's seelie, near enough.
##
## It idles where it was put until you walk up, then drifts ahead of you along
## [member path] to its [WispShrine], waiting whenever you fall behind. It leads
## you through rooms you haven't seen, so following it is filling in the map.
## When it reaches the shrine it sinks into it and sets [member solved_flag]; the
## shrine lights and the sealed chest beside it appears, both by listening for
## that flag. Nothing here knows the chest exists.
##
## No body: it floats over everything and blocks nothing, like a [Monster]'s
## absence of one. Monsters still chase you while you follow it.

## How close you come before it sets off.
const NOTICE := 30.0
## It stops and waits once you are this far behind, and sets off again once you
## are back within [constant RESUME].
const WAIT := 72.0
const RESUME := 48.0
## Slower than you walk (90), so keeping up is easy and losing it takes trying.
const SPEED := 58.0
## How high it floats over the cell it is on, and how far it bobs.
const HOVER := 12.0
const BOB := 2.0
const FPS := 6.0
## The spark sheet's frames it pulses through: the twinkle grown into an orb.
const FIRST_FRAME := 2
const FRAMES := 4

enum State { IDLE, LEADING, WAITING, ARRIVED }

## The way to the shrine, map-local, starting where it idles.
@export var path := PackedVector2Array()
@export var solved_flag: StringName = &""

var state := State.IDLE

var _next := 1
var _time := 0.0

@onready var _body: Node2D = $Body
@onready var _spark: Sprite2D = $Body/Spark


func _ready() -> void:
	if solved_flag != &"" and GameState.has_flag(solved_flag):
		queue_free()
		return
	# Over props and monsters, under the labyrinth's dark.
	z_index = 5
	# It steps on ticks under a camera that moves every drawn frame.
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_ON


func _process(delta: float) -> void:
	_time += delta
	var lift := HOVER + sin(_time * (5.0 if state == State.WAITING else 3.0)) * BOB
	_body.position.y = -roundf(lift)
	_spark.frame = FIRST_FRAME + int(_time * FPS) % FRAMES


func _physics_process(delta: float) -> void:
	if state == State.ARRIVED or GameState.is_input_locked():
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return
	var gap := player.global_position.distance_to(global_position)
	match state:
		State.IDLE:
			if gap <= NOTICE:
				state = State.LEADING
				Audio.play(&"wisp")
		State.LEADING:
			if gap > WAIT:
				state = State.WAITING
			else:
				_advance(delta)
		State.WAITING:
			if gap <= RESUME:
				state = State.LEADING


## Whether it has set off -- for the map, which marks it only while it waits to.
func is_idle() -> bool:
	return state == State.IDLE


func _advance(delta: float) -> void:
	var budget := SPEED * delta
	while budget > 0.0 and _next < path.size():
		var to := path[_next]
		var step := position.distance_to(to)
		if step > budget:
			position = position.move_toward(to, budget)
			return
		position = to
		budget -= step
		_next += 1
	if _next >= path.size():
		_arrive()


## Sinks into the shrine, then sets the flag everything else is waiting on.
func _arrive() -> void:
	state = State.ARRIVED
	var tween := create_tween()
	tween.tween_property(_body, ^"position:y", -2.0, 0.5)
	tween.parallel().tween_property(self, ^"modulate:a", 0.0, 0.6)
	await tween.finished
	if solved_flag != &"":
		GameState.set_flag(solved_flag)
	Audio.play(&"solved")
	EventBus.message_requested.emit("", PackedStringArray([
		"The wisp sinks into the stone lantern, and it lights from inside.",
	]))
	queue_free()
