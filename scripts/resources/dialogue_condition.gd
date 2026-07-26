class_name DialogueCondition
extends Resource
## One requirement a dialogue line or choice checks against [GameState].
##
## Conditions are deliberately small and readable in the inspector rather than
## an expression language: dialogue asks questions the rest of the game already
## answers ("is this flag set?", "is floor 25 cleared?", "am I level 10 yet?").
## Combine them by putting several in a line's [code]conditions[/code] array --
## they are ANDed. For OR, write two lines; the first whose conditions pass wins.

enum Test {
	FLAG_SET,       ## GameState.has_flag(flag)
	FLOOR_CLEARED,  ## GameState.is_floor_cleared(number)
	MIN_LEVEL,      ## GameState.level >= number
}

@export var test: Test = Test.FLAG_SET
## Inverts the whole test: "flag NOT set", "floor NOT cleared".
@export var negate := false

@export var flag: StringName = &""
## Floor number for FLOOR_CLEARED, level for MIN_LEVEL.
@export var number := 0


func is_met() -> bool:
	var result := false
	match test:
		Test.FLAG_SET:
			result = flag != &"" and GameState.has_flag(flag)
		Test.FLOOR_CLEARED:
			result = GameState.is_floor_cleared(number)
		Test.MIN_LEVEL:
			result = GameState.level >= number
	return result != negate


## True when every condition in [param conditions] passes. An empty array is
## "no requirements", so unconditional content needs no boilerplate.
static func all_met(conditions: Array[DialogueCondition]) -> bool:
	for condition in conditions:
		if condition != null and not condition.is_met():
			return false
	return true
