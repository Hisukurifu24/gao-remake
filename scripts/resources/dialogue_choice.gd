class_name DialogueChoice
extends Resource
## One branch offered at the bottom of a dialogue line.

## Shown in the choice menu.
@export var text := ""
## Id of the [DialogueLine] to jump to. Empty ends the conversation.
@export var next: StringName = &""

@export_group("Availability")
## All must pass for the choice to be offered. Empty means always available.
@export var conditions: Array[DialogueCondition] = []
## When false, a choice whose conditions fail is still listed but greyed out and
## unselectable -- the "you need a lockpick for this" reveal. When true it is
## simply absent.
@export var hide_when_locked := true
## Shown in place of nothing when a locked choice is visible, e.g. "(Requires 500 col)".
@export var locked_hint := ""

@export_group("Result")
## Applied when the player picks this choice, before the next line is shown.
@export var effects: Array[DialogueEffect] = []


func is_unlocked() -> bool:
	return DialogueCondition.all_met(conditions)


## Locked-and-hidden choices never reach the menu at all.
func is_listed() -> bool:
	return is_unlocked() or not hide_when_locked


func label() -> String:
	if is_unlocked() or locked_hint.is_empty():
		return text
	return "%s  %s" % [text, locked_hint]
