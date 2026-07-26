extends Interactable
## A one-shot container.
##
## Opened state is stored as a world flag in [GameState], not on the node, so a
## chest stays open after leaving and re-entering the map. In M3 the reward
## becomes an Item resource handed to the Inventory autoload.

@export var contents := "Small Health Potion"
## Must be unique per chest, e.g. &"chest_town_well".
@export var opened_flag: StringName = &""

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	if is_opened():
		_show_opened()


func interact(by: Node) -> void:
	super.interact(by)
	if is_opened():
		EventBus.message_requested.emit("", PackedStringArray(["The chest is empty."]))
		return

	if opened_flag != &"":
		GameState.set_flag(opened_flag)
	_show_opened()
	# M3: Inventory.add_item(item, 1) -- until then, just announce it.
	EventBus.message_requested.emit("", PackedStringArray(["You found %s." % contents]))


func is_opened() -> bool:
	return opened_flag != &"" and GameState.has_flag(opened_flag)


func is_available() -> bool:
	return not is_opened()


func _show_opened() -> void:
	_sprite.modulate = Color(0.55, 0.55, 0.6)
