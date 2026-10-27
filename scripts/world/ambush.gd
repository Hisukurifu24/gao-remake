class_name Ambush
extends Node2D
## Player killers lying in wait in a field room ([FloorEvents]): orange cursors,
## hidden until you walk into the room, who drop their hiding round you and give
## you a choice -- pay their toll, or fight the pair of them.
##
## Nothing is drawn until it springs: they are hiding, which is the point. It
## springs the first moment you stand in [member area] with nothing else going
## on, and only where the map can stage a fight for two round you
## ([method GameMap.stage_battle]) -- a cell it can't, it waits for the next.
## They step out of nowhere onto the formation, as a boss steps out of its door.
##
## Beaten or paid, they are done for good ([method FloorEvents.flag], "ambush"). Fled
## or beaten by, they melt away for the rest of the visit and are back on the next
## one, like any monster -- the floor is still theirs.

## How long they take to drop their hiding.
const APPEAR_TIME := 0.4
const SMOKE := preload("res://assets/ninja_adventure/FX/Smoke/Smoke/SpriteSheet.png")

@export var floor_number := 0
## The room they wait in, in cells.
@export var area := Rect2i()

var _spent := false
var _figures: Array[FoeFigure] = []


func _ready() -> void:
	if GameState.has_flag(FloorEvents.flag(floor_number, "ambush")):
		queue_free()


func _physics_process(_delta: float) -> void:
	if _spent or GameState.is_input_locked() or CombatManager.is_running():
		return
	var map := get_parent() as GameMap
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if map == null or player == null:
		return
	var at := map.to_local(player.global_position)
	if not area.has_point(Vector2i((at / FloorEvents.TILE).floor())) or map.is_safe(at):
		return
	_spring(map, player)


## Whether it has sprung on this visit.
func is_spent() -> bool:
	return _spent


func _spring(map: GameMap, player: Player) -> void:
	var encounter := Bestiary.ambush_encounter(floor_number)
	var at := map.to_local(player.global_position)
	var field := map.stage_battle(at, at + player.facing * FloorEvents.TILE, encounter.enemies.size())
	if field == null:
		return
	_spent = true
	for i in encounter.enemies.size():
		var figure := FoeFigure.new(encounter.enemies[i], false)
		figure.position = field.enemy_spots[i]
		figure.face(field.player_spot - field.enemy_spots[i])
		map.add_child(figure)
		_figures.append(figure)
		field.enemy_nodes.append(figure)
	await _appear()

	await DialogueRunner.start(FloorEvents.ambush_dialogue(floor_number))
	if GameState.has_flag(FloorEvents.flag(floor_number, "ambush_paid")):
		GameState.set_flag(FloorEvents.flag(floor_number, "ambush"))
		_vanish()
		EventBus.message_requested.emit("", PackedStringArray([
			"They count it, grin, and melt back into hiding. You won't see them again.",
		]))
		return

	EventBus.battle_staged.emit(field)
	var result: CombatResult = await CombatManager.start(encounter)
	_vanish()
	if result == null:
		return
	if result.victory:
		GameState.set_flag(FloorEvents.flag(floor_number, "ambush"))
		EventBus.message_requested.emit("", PackedStringArray([
			"The orange players break and run. They won't try this floor again.",
		]))
	elif result.fled:
		EventBus.message_requested.emit("", PackedStringArray([
			"You get clear. Behind you, they melt back into hiding -- they'll be waiting next time.",
		]))
	else:
		_robbed(map, result.defeated())


## Beaten by them: as a monster leaves you, but it was people who did it.
func _robbed(map: GameMap, defeated: bool) -> void:
	if defeated and SaveGame.end_if_fatal():
		return
	GameState.set_hp(maxi(1, roundi(GameState.total_max_hp() * 0.35)))
	var lines := PackedStringArray(["They leave you on the ground and melt back into hiding."])
	var spilled := map.player_fell() if defeated else 0
	if spilled > 0:
		lines.append("Your purse spills as you go down -- %d col lies where you fell." % spilled)
	EventBus.message_requested.emit("", lines)


func _appear() -> void:
	if CombatManager.step_delay <= 0.0:
		return
	GameState.push_input_lock()
	var tween := create_tween().set_parallel()
	for figure in _figures:
		figure.modulate.a = 0.0
		tween.tween_property(figure, ^"modulate:a", 1.0, APPEAR_TIME)
		_puff(figure.position)
	await tween.finished
	GameState.pop_input_lock()


## The figures go: a beaten one has already gone up in smoke on the stage.
func _vanish() -> void:
	for figure in _figures:
		if is_instance_valid(figure):
			_puff(figure.position)
			figure.queue_free()
	_figures.clear()


func _puff(at: Vector2) -> void:
	if CombatManager.step_delay <= 0.0 or get_parent() == null:
		return
	var smoke := Sprite2D.new()
	smoke.texture = SMOKE
	smoke.hframes = SMOKE.get_width() / SMOKE.get_height()
	smoke.position = at + Vector2(0, -8)
	get_parent().add_child(smoke)
	var tween := smoke.create_tween()
	tween.tween_property(smoke, ^"frame", smoke.hframes - 1, 0.5)
	tween.tween_callback(smoke.queue_free)
