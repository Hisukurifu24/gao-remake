class_name Escortee
extends Npc
## A player stranded out in the field ([FloorEvents]), cornered by the floor's
## monsters and waiting for someone to get them back to the camp.
##
## Talk to them and take the job, and they follow you: along your own trail, a
## few steps behind, so they go where you went and never through a wall. The
## floor's monsters go for them as they would for you ([method Monster._touching_escort])
## -- a fight that catches them is yours. Walk them into the camp's plot and they
## say their thanks, which is the conversation the job's TALK objective waits on
## ([method FloorEvents.escort_talk]): the quest pays out on the spot.
##
## Following is not saved, by design: leave the floor, or get knocked flat on the
## way, and they bolt back to where you found them, the job still yours. They are
## not solid, on the map or behind you -- someone you are escorting must never be
## what boxes you into a corridor.

const GROUP := &"escort"
## How far behind your trail they keep, and how fast they can close it.
const FOLLOW_GAP := 18.0
const FOLLOW_SPEED := 100.0
## Further than this from you -- a teleport trap, a slide into a fight's formation
## -- and they catch up at once rather than walk the trail you left.
const SNAP_DISTANCE := 96.0
const WALK_FPS := 8.0
## Drawn faint while a fight is on, out of the formation's way.
const FIGHT_ALPHA := 0.35

@export var floor_number := 0
## The camp, in cells: walking them into it is the end of the job.
@export var home := Rect2i()

var following := false

var _trail: Array[Vector2] = []
var _spot := Vector2.ZERO
var _walk_time := 0.0
var _column := 0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	_spot = position
	# They step on ticks under a camera that moves every drawn frame.
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_ON
	# Never solid: see the class note.
	for shape in $Solid.get_children():
		(shape as CollisionShape2D).disabled = true
	CombatManager.combat_began.connect(_on_combat_began)
	CombatManager.combat_finished.connect(_on_combat_finished)


func is_available() -> bool:
	return super.is_available() and not following


func interact(by: Node) -> void:
	await super.interact(by)
	if _on_the_job():
		follow()


## Starts them after the player, from wherever they are.
func follow() -> void:
	if following:
		return
	following = true
	_trail.clear()


func _on_the_job() -> bool:
	var quest := FloorEvents.escort_quest(floor_number)
	return GameState.has_flag(QuestLog.flag_for(quest, "started")) \
			and not GameState.has_flag(QuestLog.flag_for(quest, "done"))


func _physics_process(delta: float) -> void:
	if not following or GameState.is_input_locked():
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return
	var start := position
	var target := (get_parent() as Node2D).to_local(player.global_position)
	if position.distance_to(target) > SNAP_DISTANCE:
		_trail.clear()
		position = target
		reset_physics_interpolation()
	elif _trail.is_empty() or (_trail.back() as Vector2).distance_to(target) >= 4.0:
		_trail.append(target)
	# Walk the trail, keeping the gap: the points nearer than it to you wait.
	var budget := FOLLOW_SPEED * delta
	while budget > 0.0 and not _trail.is_empty() and position.distance_to(target) > FOLLOW_GAP:
		var next: Vector2 = _trail[0]
		var gap := position.distance_to(next)
		if gap <= budget:
			position = next
			_trail.pop_front()
			budget -= gap
		else:
			position = position.move_toward(next, budget)
			budget = 0.0
	_animate(position - start, delta)
	if home.has_point(Vector2i((position / 16.0).floor())):
		_arrive()


## In the camp: they stop and say so, and the job is done.
func _arrive() -> void:
	following = false
	_trail.clear()
	_sprite.frame = 0
	await DialogueRunner.start(FloorEvents.home_dialogue(floor_number))


func _animate(motion: Vector2, delta: float) -> void:
	var moving := motion.length() > 0.01
	_walk_time = _walk_time + delta if moving else 0.0
	if moving:
		if absf(motion.x) > absf(motion.y):
			_column = 2 if motion.x < 0.0 else 3
		else:
			_column = 1 if motion.y < 0.0 else 0
	var row := int(_walk_time * WALK_FPS) % 4 if moving else 0
	_sprite.frame = row * 4 + _column


func _on_combat_began(_encounter: Encounter, _party: Array, _enemies: Array) -> void:
	if following:
		modulate.a = FIGHT_ALPHA


## Knocked flat with them behind you: they run back to where you found them, and
## the job waits there. A fight won or fled, they are still with you.
func _on_combat_finished(result: CombatResult) -> void:
	modulate.a = 1.0
	if not following or result == null or result.victory or result.fled:
		return
	following = false
	_trail.clear()
	position = _spot
	_sprite.frame = 0
	EventBus.message_requested.emit("", PackedStringArray([
		"%s bolts while you're down -- back to where you found them." % display_name,
	]))
