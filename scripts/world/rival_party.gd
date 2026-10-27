class_name RivalParty
extends Node2D
## Another party racing you to the boss ([FloorEvents]): three players in the camp
## who reckon they'll clear the floor today, and whose leader will race you for a
## stake.
##
## Take the bet and they set off down [member path] -- the way from the camp to the
## door, which they know and you don't -- at [constant FloorEvents.RIVAL_SPEED],
## a good deal slower than you can walk. They walk only while you can: through a
## fight, a conversation or a menu they wait, so the race is the walk, not the
## clock. Walk into the boss room before they reach its door and the race is yours
## -- the stake twice over and a prize; reach it after, and they have cleared the
## floor: the way up is open, and the boss and everything it carried are theirs.
##
## A race is not saved. Leave the floor with it running and it is lost: they
## didn't stop because you did.

const WALK_FPS := 8.0
## How far apart the three walk, along the path.
const SPACING := 14.0

@export var floor_number := 0
## Map-local points, the camp to the door.
@export var path := PackedVector2Array()
## Which point of [member path] is the labyrinth's mouth: they say so as they pass it.
@export var mouth_index := -1
## Their three walk sheets, leader first.
@export var sheets: Array[Texture2D] = []

var running := false

var _leader: Npc = null
var _walkers: Array[Sprite2D] = []
var _lengths := PackedFloat32Array()
var _distance := 0.0
var _walk_time := 0.0
var _told_mouth := false


func _ready() -> void:
	_leader = get_parent().get_node_or_null(^"RivalLeader") as Npc
	for i in sheets.size():
		var walker := Sprite2D.new()
		walker.name = "Rival%d" % i
		walker.texture = sheets[i]
		walker.hframes = 4
		walker.vframes = 7
		walker.offset = Vector2(0, -8)
		walker.visible = false
		add_child(walker)
		_walkers.append(walker)
	var total := 0.0
	_lengths.append(0.0)
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
		_lengths.append(total)
	if FloorEvents.race_over(floor_number):
		_retire()
		return
	if GameState.has_flag(FloorEvents.flag(floor_number, "race")):
		# Started, and you left: they kept going. Settled once the arrival is over.
		_lose.call_deferred(true)
		return
	EventBus.flag_changed.connect(_on_flag_changed)
	EventBus.boss_room_found.connect(_on_boss_room_found)
	# The other two wait either side of their leader until they set off.
	for i in range(1, _walkers.size()):
		_walkers[i].position = path[0] + Vector2((i * 2 - 3) * FloorEvents.TILE, 0)
		_walkers[i].visible = true


## How far along the way to the door they have walked, 0 to 1.
func progress() -> float:
	return clampf(_distance / maxf(1.0, _lengths[_lengths.size() - 1]), 0.0, 1.0)


## How long they take to reach the door, walking without a stop.
func walk_time() -> float:
	return _lengths[_lengths.size() - 1] / FloorEvents.RIVAL_SPEED


func _on_flag_changed(flag: StringName, _value: Variant) -> void:
	if flag == FloorEvents.flag(floor_number, "race") and not running:
		_start()


func _start() -> void:
	running = true
	if _leader != null:
		_leader.queue_free()
		_leader = null
	for walker in _walkers:
		walker.visible = true
	_place_walkers()
	EventBus.floor_announced.emit("Race",
			"%s set off for the boss room." % _guild())


func _physics_process(delta: float) -> void:
	if not running or GameState.is_input_locked():
		return
	_distance += FloorEvents.RIVAL_SPEED * delta
	_walk_time += delta
	_place_walkers()
	if not _told_mouth and mouth_index >= 0 and _distance >= _lengths[mouth_index]:
		_told_mouth = true
		EventBus.floor_announced.emit("Race",
				"%s reached the labyrinth." % _guild())
	if _distance >= _lengths[_lengths.size() - 1]:
		_lose(false)


## In the dark, they are as hidden as anything else in it.
func _process(_delta: float) -> void:
	var map := get_parent() as GameMap
	var dark := map.darkness() if map != null else null
	if dark == null:
		return
	for walker in _walkers:
		if walker.visible:
			walker.modulate.a = dark.light_at(Vector2i((walker.position / FloorEvents.TILE).floor()))


## Puts the three along the path, the leader in front, each facing the way it goes.
func _place_walkers() -> void:
	for i in _walkers.size():
		var along := _distance - i * SPACING
		var at := _point_at(along)
		var ahead := _point_at(along + 4.0)
		var walker := _walkers[i]
		var motion := ahead - at
		var column := 0
		if absf(motion.x) > absf(motion.y):
			column = 2 if motion.x < 0.0 else 3
		elif motion.y < 0.0:
			column = 1
		var row := int(_walk_time * WALK_FPS) % 4 if running and along > 0.0 else 0
		walker.position = at
		walker.frame = row * 4 + column


func _point_at(along: float) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	if along <= 0.0:
		return path[0]
	for i in range(1, path.size()):
		if along <= _lengths[i]:
			var span := _lengths[i] - _lengths[i - 1]
			return path[i - 1].lerp(path[i], (along - _lengths[i - 1]) / maxf(span, 0.001))
	return path[path.size() - 1]


## You walked into the boss room first.
func _on_boss_room_found(number: int) -> void:
	if number != floor_number or not running:
		return
	running = false
	GameState.set_flag(FloorEvents.flag(floor_number, "race_won"))
	var cast := FloorEvents.rivals(floor_number)
	var pot := FloorEvents.stake(floor_number) * 2
	EventBus.col_granted.emit(pot)
	EventBus.item_granted.emit(cast["prize"], 1)
	var prize := ItemLibrary.get_item(cast["prize"])
	EventBus.message_requested.emit("", PackedStringArray([
		"Boots pound up the passage behind you -- %s, out of breath." % cast["guild"],
		"%s: \"...You beat us here. Fair's fair.\" The stake is yours: %d col, and a %s on top." % [
				cast["leader"], pot, prize.label() if prize != null else String(cast["prize"])],
	]))
	_retire()


## They reached the door first -- or you left while they were on the way.
func _lose(away: bool) -> void:
	running = false
	GameState.set_flag(FloorEvents.flag(floor_number, "race_lost"))
	var guild: String = FloorEvents.rivals(floor_number)["guild"]
	if not GameState.is_floor_cleared(floor_number):
		GameState.clear_floor(floor_number)
	var lines := PackedStringArray()
	if away:
		lines.append("While you were away, %s cleared Floor %d. The race -- and the stake -- are theirs." % [
				guild, floor_number])
	else:
		lines.append("A chime rings out over the whole floor.")
		lines.append("%s have cleared Floor %d. The way up is open -- and the boss, and everything it carried, were theirs." % [
				_guild(), floor_number])
	EventBus.message_requested.emit("", lines)
	_retire()


## Their guild's name to start a sentence with: "The Dawnriders".
func _guild() -> String:
	var guild: String = FloorEvents.rivals(floor_number)["guild"]
	return guild.left(1).to_upper() + guild.substr(1)


## Off the map, theirs or yours, the race is over.
func _retire() -> void:
	running = false
	for walker in _walkers:
		walker.visible = false
	if _leader != null:
		_leader.queue_free()
		_leader = null
	set_physics_process(false)
	set_process(false)
