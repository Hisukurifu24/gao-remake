class_name Interactable
extends Area2D
## Base class for anything the player can face and press [b]interact[/b] on:
## NPCs, chests, doors, signs.
##
## Subclasses override [method interact]. The player finds these by overlap, so
## they must sit on the "interactable" physics layer (4).

signal interacted(by: Node)

## Verb shown in the on-screen prompt, e.g. "Talk to Argo".
@export var prompt_verb := "Examine"
@export var display_name := ""


func interact(by: Node) -> void:
	interacted.emit(by)


## Lets a subclass hide itself from the prompt without leaving the tree
## (an opened chest, an NPC busy elsewhere).
func is_available() -> bool:
	return true


func get_prompt() -> String:
	if display_name.is_empty():
		return prompt_verb
	return "%s %s" % [prompt_verb, display_name]
