extends Interactable
## The labyrinth door at the end of a floor.
##
## The gate is the whole shape of the game in one node: beat what is behind it,
## and the floor above opens. Losing costs the walk back and nothing else --
## Aincrad is a death game in the fiction, not in the save file.

## What you are left standing with after losing a boss fight: enough to walk
## back to the door, not enough to walk straight through it.
const DEFEAT_HP_RATIO := 0.35

@export var floor_number := 1
@export var boss_name := ""


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

	var result: CombatResult = await CombatManager.start(encounter)
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
