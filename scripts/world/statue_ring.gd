class_name StatueRing
extends Node
## Four statues round an altar, and the rule for turning them: [b]interact[/b] on
## one turns it a quarter clockwise, and the two beside it round the ring turn
## with it. Solved is every statue facing the altar, which sets
## [member solved_flag]; the altar's orb and the sealed chest in the room are
## waiting on it. Solved stays solved, so the statues face in whenever the floor is
## entered again.
##
## It is Lights Out with four states a piece. On a ring of four the turns are
## independent -- any arrangement has exactly one set of turns that solves it --
## so a ring scrambled by turning it backwards is solvable by construction, and
## [method turns_to_solve] can say how far from solved it is.

## The statues, by index round the ring. Set by whoever builds it, before it
## enters the tree.
var statues: Array[Statue] = []
## The way each statue faces when the ring is solved: at the altar.
var targets: Array[int] = []
@export var solved_flag: StringName = &""


func _ready() -> void:
	for statue in statues:
		statue.interacted.connect(_on_turned.bind(statue))
	if is_solved():
		# The statues come after the ring among the map's children, so they are
		# not ready yet.
		_face_in.call_deferred()


func is_solved() -> bool:
	return solved_flag != &"" and GameState.has_flag(solved_flag)


## Whether every statue now faces the altar.
func all_facing() -> bool:
	for i in statues.size():
		if statues[i].facing != targets[i]:
			return false
	return true


## The statues one turn of [param index] moves: itself and its two neighbours.
static func turned_by(index: int, count: int) -> Array[int]:
	return [posmod(index - 1, count), index, posmod(index + 1, count)]


## How many times each statue has to be turned from [param facings] to reach
## [param goal] -- the one answer, found by trying every one of the 4^n -- or an
## empty array if there is none.
static func turns_to_solve(facings: Array[int], goal: Array[int]) -> Array[int]:
	var count := facings.size()
	for code in int(pow(4, count)):
		var turns: Array[int] = []
		for i in count:
			turns.append((code >> (2 * i)) & 3)
		var solves := true
		for i in count:
			var moved := 0
			for j in turned_by(i, count):
				moved += turns[j]
			if posmod(facings[i] + moved, 4) != goal[i]:
				solves = false
				break
		if solves:
			return turns
	return []


func _on_turned(_by: Node, statue: Statue) -> void:
	if is_solved():
		return
	for i in turned_by(statue.index, statues.size()):
		statues[i].face(statues[i].facing + 1)
	if all_facing():
		GameState.set_flag(solved_flag)
		EventBus.message_requested.emit("", PackedStringArray([
			"The last statue grinds round to face the altar, and the orb on it wakes.",
		]))


func _face_in() -> void:
	for i in statues.size():
		statues[i].face(targets[i], false)
