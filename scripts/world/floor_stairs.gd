extends Interactable
## Stairs back down to a floor you've already cleared.

@export var target_floor := 1


func interact(by: Node) -> void:
	super.interact(by)
	if target_floor < 1:
		return
	SceneRouter.enter_floor(target_floor, &"from_above")


func get_prompt() -> String:
	return "Descend to Floor %d" % target_floor
