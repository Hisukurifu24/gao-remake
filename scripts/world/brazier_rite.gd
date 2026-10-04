class_name BrazierRite
extends Node
## A ring of braziers and the rule for lighting them: all of them before the first
## burns out ([constant Mode.TIMED]), or in the order the tablet beside them gives
## ([constant Mode.ORDERED]). Solved sets [member solved_flag], which the sealed
## chest in the room is waiting on; solved stays solved, so the fires are lit
## whenever the floor is entered again.
##
## A timed rite's clock stops while the input lock is held. A monster that runs
## you down mid-rite costs you the fight, not the fires -- and a message box, a
## map or a bag opened mid-rite costs nothing either.

enum Mode { TIMED, ORDERED }

## How long the wrong fire burns before they all go out, so you see which it was.
const WRONG_FLARE := 0.35

@export var mode := Mode.TIMED
## For an ordered rite, the brazier indices in the order they are to be lit.
@export var order: Array[int] = []
## For a timed rite, the seconds from the first fire to the last.
@export var burn := 8.0
@export var solved_flag: StringName = &""

## The rite's braziers, by index. Set by whoever builds it, before it enters the tree.
var braziers: Array[Brazier] = []

var _lit: Array[int] = []
## Seconds since the first fire was lit; below zero while none is.
var _clock := -1.0
var _failing := false


func _ready() -> void:
	for brazier in braziers:
		brazier.interacted.connect(_on_lit.bind(brazier))
	if is_solved():
		# The braziers come after the rite among the map's children, so they are
		# not ready yet.
		_light_all.call_deferred()


func is_solved() -> bool:
	return solved_flag != &"" and GameState.has_flag(solved_flag)


## How many fires are burning now -- for the tests and the map.
func lit_count() -> int:
	return _lit.size()


func _process(delta: float) -> void:
	if mode != Mode.TIMED or _clock < 0.0 or is_solved() or GameState.is_input_locked():
		return
	_clock += delta
	for i in _lit:
		braziers[i].set_fuel(1.0 - _clock / burn)
	if _clock > burn:
		_fail("The first fire gutters out, and the rest follow it.")


func _on_lit(_by: Node, brazier: Brazier) -> void:
	if is_solved() or brazier.lit or _failing:
		return
	brazier.set_lit(true)
	if mode == Mode.ORDERED and brazier.index != order[_lit.size()]:
		_failing = true
		await get_tree().create_timer(WRONG_FLARE).timeout
		_failing = false
		_fail("The flames gutter and die. That was not the order the stone gave.")
		return
	if _lit.is_empty():
		_clock = 0.0
	_lit.append(brazier.index)
	if _lit.size() == braziers.size():
		_clock = -1.0
		for each in braziers:
			each.set_fuel(1.0)
		GameState.set_flag(solved_flag)
		EventBus.message_requested.emit("", PackedStringArray([
			"The last fire catches. Somewhere close, stone grinds against stone.",
		]))


func _fail(text: String) -> void:
	for brazier in braziers:
		brazier.set_lit(false)
	_lit.clear()
	_clock = -1.0
	EventBus.message_requested.emit("", PackedStringArray([text]))


func _light_all() -> void:
	for brazier in braziers:
		brazier.set_lit(true)
		_lit.append(brazier.index)
