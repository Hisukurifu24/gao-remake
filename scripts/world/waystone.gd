class_name Waystone
extends Interactable
## One of the stones that seal an open field's arena ([enum FloorDefinition.Shape]).
## [b]Interact[/b] wakes it for good; wake all of them and the arena's seal -- a
## [SealedDoor] with one hollow per stone, which [member SealedDoor.opens_itself] --
## breaks wherever you are.
##
## Woken is a flag ([member flag]), so it stays woken across visits and saves, and
## the seal lights a hollow the moment it is set. The stone only knows its own.

const DIM := Rect2(64, 32, 16, 16)
const LIT := Rect2(80, 32, 16, 16)
## How fast a woken stone breathes, and how far.
const PULSE := 2.2
const PULSE_DEPTH := 0.18

@export var flag: StringName = &""
## Every stone's flag, this one's included: what "two of three" counts.
@export var all_flags: Array[StringName] = []

var _time := 0.0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_show()


func _process(delta: float) -> void:
	if not is_woken():
		return
	_time += delta
	var glow := 1.0 + PULSE_DEPTH * (0.5 + 0.5 * sin(_time * PULSE))
	_sprite.self_modulate = Color(glow, glow, glow, 1.0)


func is_woken() -> bool:
	return flag != &"" and GameState.has_flag(flag)


func is_available() -> bool:
	return not is_woken()


func interact(by: Node) -> void:
	super.interact(by)
	if is_woken():
		return
	var woken := 1
	for other in all_flags:
		if other != flag and GameState.has_flag(other):
			woken += 1
	var lines := PackedStringArray(["The waystone wakes under your hand, and a light comes up in it."])
	if woken < all_flags.size():
		lines.append("%s of %s. Somewhere across the field the arena's seal hums." % [
				_count_word(woken).capitalize(), _count_word(all_flags.size())])
	# Said before the flag is set: the last stone's flag breaks the seal, and what
	# the seal says has to come after this, not before it.
	EventBus.message_requested.emit("", lines)
	GameState.set_flag(flag)
	_show()


func _show() -> void:
	(_sprite.texture as AtlasTexture).region = LIT if is_woken() else DIM
	_sprite.self_modulate = Color.WHITE


static func _count_word(count: int) -> String:
	return ["none", "one", "two", "three", "four", "five"][clampi(count, 0, 5)]
