class_name DroppedCol
extends Interactable
## The Col the player was carrying when they fell, lying where they fell.
##
## Its state is the purse's, not the node's: [GameState] keeps one dropped pile
## (map, position, amount), [GameMap] puts this down wherever that says, and the
## node frees itself the moment the purse says the pile is gone -- picked up, or
## lost to a second fall before anyone came back for it. Not solid: it can never
## wall off the corridor someone fell in.

var amount := 0


func _ready() -> void:
	display_name = "%d col" % amount
	EventBus.col_dropped.connect(_on_col_dropped)


func interact(by: Node) -> void:
	super.interact(by)
	var recovered := GameState.recover_col()
	if recovered > 0:
		EventBus.message_requested.emit("", PackedStringArray([
			"You gather up your %d col." % recovered,
		]))


## Any change to the pile retires this one: a new fall puts a new node down.
func _on_col_dropped(_map_id: StringName, _position: Vector2, _amount: int) -> void:
	queue_free()
