class_name BossGate
extends Interactable
## The labyrinth door at the end of a floor.
##
## The gate is the whole shape of the game in one node: beat what is behind it,
## and the floor above opens. Losing costs the walk back and nothing else --
## Aincrad is a death game in the fiction, not in the save file.
##
## On a generated floor the door is not there until you find it. It stands in a
## boss room at the heart of the labyrinth, invisible and solid to nothing, and
## shows itself when the player walks into that room. Finding it sets
## [code]boss_found_<n>[/code], and found stays found: losing the fight sends you
## back to the entrance, and making you hunt for the door again on top of that
## would be punishment, not difficulty.

## What you are left standing with after losing a boss fight: enough to walk
## back to the door, not enough to walk straight through it.
const DEFEAT_HP_RATIO := 0.35
## The door fading aside and the boss fading in on its threshold, before it
## walks out to its spot. Locked, and before the fight starts, so it has its own
## beat rather than racing the runner's opening pause.
const STEP_OUT_TIME := 0.5
## What the door fades to while its boss is out of it.
const ASIDE_ALPHA := 0.0

@export var floor_number := 1
@export var boss_name := ""
## The room the door hides in, in the map's coordinates. Empty -- the default, and
## every authored floor so far -- leaves it in plain view.
@export var reveal_area := Rect2()

## Whether the door can be seen and challenged. Views read it; only the gate
## sets it.
var revealed := true
var _trigger: Area2D = null
## The boss and its escort while they are out of the door.
var _figures: Array[FoeFigure] = []

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _solid_shape: CollisionShape2D = $Solid/CollisionShape2D


static func found_flag(number: int) -> StringName:
	return StringName("boss_found_%d" % number)


func _ready() -> void:
	if not reveal_area.has_area() or _is_found():
		return
	revealed = false
	_sprite.visible = false
	_solid_shape.disabled = true
	# A few pixels inside the room, so brushing the doorway does not count as
	# having walked in.
	var inside := reveal_area.grow(-4.0)
	_trigger = Area2D.new()
	_trigger.name = "RevealTrigger"
	_trigger.collision_layer = 0
	_trigger.collision_mask = 2  # the player
	_trigger.monitorable = false
	_trigger.position = inside.get_center() - position
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = inside.size
	shape.shape = rect
	_trigger.add_child(shape)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)


func is_available() -> bool:
	return revealed


func _is_found() -> bool:
	return GameState.has_flag(found_flag(floor_number)) or GameState.is_floor_cleared(floor_number)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		reveal()


## Shows the door. Public so a test or a future Argo, selling the location, can
## call it; walking into the room is the ordinary way.
func reveal() -> void:
	if revealed:
		return
	revealed = true
	GameState.set_flag(found_flag(floor_number))
	_sprite.visible = true
	_sprite.modulate.a = 0.0
	create_tween().tween_property(_sprite, "modulate:a", 1.0, 0.6)
	_solid_shape.set_deferred(&"disabled", false)
	if _trigger:
		_trigger.queue_free()
		_trigger = null
	EventBus.boss_room_found.emit(floor_number)
	EventBus.message_requested.emit("", PackedStringArray([
		"The air goes still. This is the boss chamber.",
		"The labyrinth door stands before you.",
	]))


func interact(by: Node) -> void:
	super.interact(by)
	if GameState.is_floor_cleared(floor_number):
		_ascend()
	else:
		await _fight()


func get_prompt() -> String:
	if GameState.is_floor_cleared(floor_number):
		return "Ascend to Floor %d" % (floor_number + 1)
	return "Challenge %s" % _boss_label()


func _fight() -> void:
	var encounter := Bestiary.boss_encounter(floor_number)
	if encounter == null:
		push_error("BossGate: floor %d has no boss encounter." % floor_number)
		return

	await DialogueRunner.say("", PackedStringArray([
		"%s is waiting beyond the door." % _boss_label(),
	]))

	await _step_out(encounter)
	var result: CombatResult = await CombatManager.start(encounter)
	_step_back(result)
	if result == null:
		return

	if result.victory:
		GameState.clear_floor(floor_number)
		EventBus.message_requested.emit("", PackedStringArray([
			"%s falls." % _boss_label(),
			"Floor %d cleared. The way up is open." % floor_number,
		]))
	elif result.fled:
		EventBus.message_requested.emit("", PackedStringArray([
			"You back out of the boss chamber. The door has not moved.",
		]))
	else:
		_revive()


## The boss -- and its escort -- step out of the door to fight where you stand:
## a figure for each enemy fades in on the threshold as the door fades aside,
## the map finds them a formation, and they walk out to it. Nowhere to stand
## leaves the fight unstaged, the door where it was and nobody out of it -- which
## the floor test proves never happens.
func _step_out(encounter: Encounter) -> void:
	var map := get_parent() as GameMap
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if map == null or player == null:
		return
	var bodies: Array[Vector2] = []
	for i in encounter.enemies.size():
		bodies.append(FoeFigure.body_of(encounter.enemies[i], i == 0))
	var field := map.stage_boss(map.to_local(player.global_position), position, bodies)
	if field == null:
		return
	for i in encounter.enemies.size():
		var figure := FoeFigure.new(encounter.enemies[i], i == 0)
		figure.position = position
		figure.face(Vector2(-field.axis))
		map.add_child(figure)
		_figures.append(figure)
		field.enemy_nodes.append(figure)

	var paced := CombatManager.step_delay > 0.0
	if not paced:
		_sprite.modulate.a = ASIDE_ALPHA
		for i in _figures.size():
			_figures[i].position = field.enemy_spots[i]
		EventBus.battle_staged.emit(field)
		return
	GameState.push_input_lock()
	for figure in _figures:
		figure.modulate.a = 0.0
	var out := create_tween().set_parallel()
	out.tween_property(_sprite, "modulate:a", ASIDE_ALPHA, STEP_OUT_TIME)
	for i in _figures.size():
		var figure := _figures[i]
		out.tween_property(figure, "modulate:a", 1.0, STEP_OUT_TIME * 0.5)
		out.tween_property(figure, "position", field.enemy_spots[i], STEP_OUT_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await out.finished
	GameState.pop_input_lock()
	EventBus.battle_staged.emit(field)


## The fight is over: the figures go -- a beaten boss has already gone up in
## smoke on the stage -- and the door comes back. A defeat reloads the floor, which
## takes them with it, but they are freed here all the same.
func _step_back(_result: CombatResult) -> void:
	for figure in _figures:
		if is_instance_valid(figure):
			figure.queue_free()
	_figures.clear()
	if _sprite.modulate.a >= 1.0:
		return
	if CombatManager.step_delay <= 0.0:
		_sprite.modulate.a = 1.0
		return
	create_tween().tween_property(_sprite, "modulate:a", 1.0, STEP_OUT_TIME)


## A defeat drops the player at the floor entrance on their last legs. Rebuilding
## the floor also puts its monsters back, which is the point: the way through a
## wall you can't clear is levels.
func _revive() -> void:
	# total_max_hp(), not the base stat: a coat with +HP has to count towards
	# what "on your last legs" means.
	GameState.set_hp(maxi(1, roundi(GameState.total_max_hp() * DEFEAT_HP_RATIO)))
	EventBus.message_requested.emit("", PackedStringArray([
		"%s stands over you." % _boss_label(),
		"You come to at the entrance to the floor, barely.",
	]))
	SceneRouter.enter_floor(floor_number, &"default")


func _ascend() -> void:
	if floor_number >= FloorTuning.TOP_FLOOR:
		EventBus.message_requested.emit("", PackedStringArray([
			"Floor 100. There is nothing above this.",
			"The game is cleared -- or it would be, once the final fight exists.",
		]))
		return
	SceneRouter.enter_floor(floor_number + 1, &"from_below")


func _boss_label() -> String:
	if boss_name.is_empty():
		return FloorTuning.boss_name(floor_number)
	return boss_name
