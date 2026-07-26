class_name StatusEffect
extends Resource
## A timed condition riding on a combatant: poison, a sharpened blade, a daze.
##
## Effects are pure data. [Combatant] is the only thing that knows how to carry
## one and [CombatManager] the only thing that ticks it, so adding "burning" is a
## .tres file, not code.
##
## One effect per [member id] at a time: re-applying refreshes the duration
## rather than stacking, which keeps a two-enemy poison from doubling into an
## unsurvivable bleed.

enum Kind {
	DAMAGE_OVER_TIME,  ## HP lost at the start of each turn.
	HEAL_OVER_TIME,    ## HP restored at the start of each turn.
	ATTACK_MOD,        ## [member magnitude] percent, may be negative.
	DEFENSE_MOD,       ## as above.
	SPEED_MOD,         ## as above; changes turn order from the next round.
	STUN,              ## The carrier loses its turn entirely.
}

@export var id: StringName = &""
@export var display_name := ""
@export var kind: Kind = Kind.DAMAGE_OVER_TIME
## Always a percentage, never flat points, and may be negative for the *_MOD
## kinds. Over-time effects read it as a percent of the carrier's *max HP*,
## which is what keeps poison worth applying on floor 90 and survivable on
## floor 2 -- a flat 4 damage a turn is either everything or nothing depending
## on where you are in the tower. Ignored by STUN.
@export var magnitude := 0
## Turns it lasts, counted at the start of the carrier's own turn.
@export var duration := 3
## Purely presentational: the tag colour in the combat screen.
@export var color := Color(0.85, 0.45, 0.45)
## Debuffs are worth telling the player about in red; buffs in green.
@export var is_debuff := true


## True for the kinds that change a stat rather than move HP around.
func is_modifier() -> bool:
	return kind in [Kind.ATTACK_MOD, Kind.DEFENSE_MOD, Kind.SPEED_MOD]


## A multiplier for the stat this effect modifies, 1.0 for everything else.
## Floored at 0.1 so a stack of debuffs can never zero a stat out.
func multiplier() -> float:
	if not is_modifier():
		return 1.0
	return maxf(0.1, 1.0 + magnitude / 100.0)


## Points of HP one tick of this effect is worth on a carrier with
## [param max_hp]. Always at least 1, so a status is never a no-op.
func tick_amount(max_hp: int) -> int:
	return maxi(1, roundi(max_hp * absi(magnitude) / 100.0))


func label() -> String:
	return display_name if not display_name.is_empty() else String(id)
