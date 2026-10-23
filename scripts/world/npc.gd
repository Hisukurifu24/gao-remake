class_name Npc
extends Interactable
## A talkable villager.
##
## Real characters get a [Dialogue] resource. [member lines] stays as the quick
## path for throwaway extras -- a one-line "the fields are dangerous at night"
## villager should not need a .tres.

## Wins over [member lines] when set.
@export var dialogue: Dialogue
## A shopkeeper: talking to them opens the counter instead of a conversation.
## Wins over both of the above -- what they say is the shop's greeting.
@export var shop: Shop
## A smith: talking to them opens the forge, the same way. A smith with things to
## say as well (Nezha) has a [member dialogue] whose menu opens it instead, with
## a [code]OPEN_FORGE[/code] effect.
@export var smith: Smith

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
## Not there -- not drawn, not solid, not offered -- until this flag is set, and
## then fades in where they stand: a settled floor's lost player, who is only in
## the labyrinth once somebody has asked you to go and find them.
@export var hidden_until: StringName = &""

## How long a hidden NPC takes to appear once their flag is set.
const APPEAR_TIME := 0.6


func _ready() -> void:
	if sprite_sheet != null:
		($Sprite2D as Sprite2D).texture = sprite_sheet
	if is_hidden():
		_set_present(false)
		EventBus.flag_changed.connect(_on_flag_changed)


func is_available() -> bool:
	return not is_hidden()


func is_hidden() -> bool:
	return hidden_until != &"" and not GameState.has_flag(hidden_until)


func interact(by: Node) -> void:
	super.interact(by)
	if shop != null:
		EventBus.shop_requested.emit(shop)
	elif smith != null:
		EventBus.forge_requested.emit(smith)
	elif dialogue != null:
		await DialogueRunner.start(dialogue)
	elif not lines.is_empty():
		await DialogueRunner.say(speaker, lines)
	if met_flag != &"":
		GameState.set_flag(met_flag)


func _on_flag_changed(flag: StringName, _value: Variant) -> void:
	if flag != hidden_until or is_hidden():
		return
	EventBus.flag_changed.disconnect(_on_flag_changed)
	# Drawn at once, solid once the player isn't standing where it appeared.
	visible = true
	SolidWhenClear.attach($Solid)
	modulate.a = 0.0
	create_tween().tween_property(self, ^"modulate:a", 1.0, APPEAR_TIME)


## Drawn and solid, or neither.
func _set_present(present: bool) -> void:
	visible = present
	for shape in $Solid.get_children():
		(shape as CollisionShape2D).set_deferred(&"disabled", not present)
