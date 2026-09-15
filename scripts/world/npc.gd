extends Interactable
## A talkable villager.
##
## Real characters get a [Dialogue] resource. [member lines] stays as the quick
## path for throwaway extras -- a one-line "the fields are dangerous at night"
## villager should not need a .tres.

## Wins over [member lines] when set.
@export var dialogue: Dialogue

## Their walk sheet, in the Ninja Adventure layout (4 columns by 7 rows). Empty
## keeps the scene's default villager.
@export var sprite_sheet: Texture2D

@export_group("Simple text")
@export var speaker := "Villager"
@export_multiline var lines: PackedStringArray = PackedStringArray()

@export_group("State")
## Set once the player has finished a conversation with this NPC. Deliberately
## set *after* the talk, not before: a dialogue whose first line is gated on
## "have we met?" must still see the answer the player would expect.
@export var met_flag: StringName = &""


func _ready() -> void:
	if sprite_sheet != null:
		($Sprite2D as Sprite2D).texture = sprite_sheet


func interact(by: Node) -> void:
	super.interact(by)
	if dialogue != null:
		await DialogueRunner.start(dialogue)
	elif not lines.is_empty():
		await DialogueRunner.say(speaker, lines)
	if met_flag != &"":
		GameState.set_flag(met_flag)
