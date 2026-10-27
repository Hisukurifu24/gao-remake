class_name CombatResult
extends RefCounted
## The answer [method CombatManager.start] hands back to whoever started the fight.
##
## A caller should only ever need this object: [BossGate] clears the floor on
## [member victory], a wandering monster (M6) shrugs off a [member fled]. XP, Col
## and loot are already granted by the time this arrives -- they are listed here
## for the summary, not as a to-do list.

var victory := false
var fled := false
var xp := 0
var col := 0
var loot: Array[StringName] = []
var rounds := 0
## Filled in when the fight ended without either side winning (see
## [constant CombatManager.MAX_ROUNDS]).
var stalemate := false
## A first-strike duel ([member Encounter.first_strike]): [member victory] is the
## other side yielding, [member yielded] you doing so -- neither a death. And
## [member betrayed] if it stopped being a duel halfway.
var duel := false
var yielded := false
var betrayed := false


func defeated() -> bool:
	return not victory and not fled and not stalemate and not yielded


func summary() -> String:
	if fled:
		return "You broke away."
	if yielded:
		return "You yield. The duel is lost."
	if stalemate:
		return "Neither side could finish it."
	if not victory:
		return "You were struck down."
	if duel and not betrayed:
		return "The duel is yours."
	if xp > 0 and col > 0:
		return "Victory! %d XP, %d col." % [xp, col]
	if xp > 0:
		return "Victory! %d XP." % xp
	return "Victory!"
