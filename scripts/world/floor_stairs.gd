extends Interactable
## Stairs: back down to a floor you've already cleared, or between a dungeon's
## levels ([DungeonGenerator]) -- up a ladder to the next, down a hole to the last.

@export var target_floor := 1
## Which of [member target_floor]'s levels; 0 is the floor itself, entered from
## above as any floor's stairs down are.
@export var target_level := 0
## The spawn point arrived at on a level.
@export var target_spawn: StringName = &"from_above"
@export var going_up := false


func interact(by: Node) -> void:
	super.interact(by)
	if target_floor < 1:
		return
	if target_level < 1:
		SceneRouter.enter_floor(target_floor, &"from_above")
	else:
		SceneRouter.enter_floor(target_floor, target_spawn, SceneRouter.FADE_TIME, target_level)


func get_prompt() -> String:
	if target_level < 1:
		return "Descend to Floor %d" % target_floor
	return "%s to Level %d" % ["Climb" if going_up else "Descend", target_level]
