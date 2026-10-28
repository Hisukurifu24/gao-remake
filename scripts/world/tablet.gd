class_name Tablet
extends Interactable
## A stone with words cut into it: a puzzle's rule, read with [b]interact[/b].

@export_multiline var lines: PackedStringArray = PackedStringArray()


func interact(by: Node) -> void:
	super.interact(by)
	Audio.play(&"read")
	EventBus.message_requested.emit("", lines)
