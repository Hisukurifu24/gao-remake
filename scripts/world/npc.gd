extends Interactable
## A talkable villager.
##
## Real characters get a [Dialogue] resource. [member lines] stays as the quick
## path for throwaway extras -- a one-line "the fields are dangerous at night"
## villager should not need a .tres.

## Wins over [member lines] when set.
@export var dialogue: Dialogue

@export_group("Simple text")
@export var speaker := "Villager"
@export_multiline var lines: PackedStringArray = PackedStringArray()

@export_group("State")
## Set once the player has finished a conversation with this NPC. Deliberately
## set *after* the talk, not before: a dialogue whose first line is gated on
## "have we met?" must still see the answer the player would expect.
@export var met_flag: StringName = &""


func interact(by: Node) -> void:
	super.interact(by)
	if dialogue != null:
		await DialogueRunner.start(dialogue)
	elif not lines.is_empty():
		await DialogueRunner.say(speaker, lines)
	if met_flag != &"":
		GameState.set_flag(met_flag)
