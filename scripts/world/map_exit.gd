extends Interactable
## Sends the player to another map, arriving at a named spawn point there.
##
## [member auto_trigger] distinguishes the two flavours: a doorway you press
## interact on, versus the edge of a field you simply walk into.

@export_file("*.tscn") var target_map := ""
@export var target_spawn: StringName = &"default"
@export var auto_trigger := false


func _ready() -> void:
	if auto_trigger:
		monitoring = true
		body_entered.connect(_on_body_entered)


func interact(by: Node) -> void:
	super.interact(by)
	_travel()


func is_available() -> bool:
	return not auto_trigger  # walk-in exits shouldn't show a prompt


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_travel()


func _travel() -> void:
	if target_map.is_empty():
		push_warning("MapExit '%s' has no target_map." % name)
		return
	SceneRouter.change_map(target_map, target_spawn)
