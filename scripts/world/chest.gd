extends Interactable
## A one-shot container.
##
## Opened state is stored as a world flag in [GameState], not on the node, so a
## chest stays open after leaving and re-entering the map.
##
## The reward is granted through [signal EventBus.item_granted] rather than by
## calling [Inventory] -- a chest announces what it gave up and does not need to
## know where it went. The one thing it does check is whether the bag can take
## it: opening is irreversible, so a chest that would overflow stays shut.

## What is inside, by [ItemLibrary] id.
@export var item_id: StringName = &"small_potion"
@export_range(1, 99) var amount := 1
## Must be unique per chest, e.g. &"chest_town_well".
@export var opened_flag: StringName = &""

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	if is_opened():
		_show_opened()


func interact(by: Node) -> void:
	super.interact(by)
	if is_opened():
		_say("The chest is empty.")
		return

	var item := ItemLibrary.get_item(item_id)
	if item == null:
		# A content bug, already shouted about by ItemLibrary. Open it anyway
		# rather than leaving the player prodding a chest that never responds.
		_open()
		_say("The chest is empty after all.")
		return

	if not Inventory.fits(item, amount):
		_say("Your bag is too full for %s." % item.label())
		return

	_open()
	EventBus.item_granted.emit(item_id, amount)
	_say("You found %s." % _found_text(item))


func is_opened() -> bool:
	return opened_flag != &"" and GameState.has_flag(opened_flag)


func is_available() -> bool:
	return not is_opened()


func _open() -> void:
	if opened_flag != &"":
		GameState.set_flag(opened_flag)
	_show_opened()


func _found_text(item: Item) -> String:
	return item.label() if amount <= 1 else "%s x%d" % [item.label(), amount]


func _say(text: String) -> void:
	EventBus.message_requested.emit("", PackedStringArray([text]))


func _show_opened() -> void:
	_sprite.modulate = Color(0.55, 0.55, 0.6)
