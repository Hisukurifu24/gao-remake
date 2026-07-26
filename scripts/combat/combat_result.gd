class_name CombatResult
extends RefCounted
## The answer [method CombatManager.start] hands back to whoever started the fight.
##
## A caller should only ever need this object: [BossGate] clears the floor on
## [member victory], a wandering monster (M6) shrugs off a [member fled]. XP and
## loot are already granted by the time this arrives -- they are listed here for
## the summary screen, not as a to-do list.

var victory := false
var fled := false
var xp := 0
var loot: Array[StringName] = []
var rounds := 0
## Filled in when the fight ended without either side winning (see
## [constant CombatManager.MAX_ROUNDS]).
var stalemate := false


func defeated() -> bool:
	return not victory and not fled and not stalemate


func summary() -> String:
	if fled:
		return "You broke away."
	if stalemate:
		return "Neither side could finish it."
	if not victory:
		return "You were struck down."
	if xp > 0:
		return "Victory! %d XP." % xp
	return "Victory!"
