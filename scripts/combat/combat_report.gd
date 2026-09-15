class_name CombatReport
extends RefCounted
## What just happened, in a form a view can draw.
##
## [CombatManager] emits one of these per resolved action (and per status tick)
## instead of reaching into the combat screen. [member text] is the log line;
## [member hits] is what to float over which sprite. A headless test can assert
## on both without a single node existing.

enum Kind {
	SKILL,    ## Someone acted.
	DEFEND,
	FLEE,     ## Attempted; [member success] says whether it worked.
	STATUS,   ## A damage- or heal-over-time tick.
	SKIPPED,  ## Staggered or stunned: the turn was lost.
	DEFEAT,   ## A combatant went down.
	ITEM,     ## Something was spent out of the bag.
	OPENING,  ## One side struck first; the other sits out round 1.
}

## One number over one sprite.
class Hit extends RefCounted:
	var target: Combatant
	## Negative for damage, positive for healing, 0 for a miss.
	var amount := 0
	var crit := false
	var missed := false
	var staggered := false

	func _init(on: Combatant) -> void:
		target = on

var kind: Kind = Kind.SKILL
var actor: Combatant = null
var skill: Skill = null
## Set on [constant Kind.ITEM] reports, for a view that wants to show the icon.
var item: Item = null
var text := ""
var hits: Array[Hit] = []
var success := true


static func make(of_kind: Kind, by: Combatant, message: String) -> CombatReport:
	var report := CombatReport.new()
	report.kind = of_kind
	report.actor = by
	report.text = message
	return report


func add_hit(hit: Hit) -> void:
	hits.append(hit)


## Every combatant this report touched, for a view that wants to refresh bars.
func touched() -> Array[Combatant]:
	var result: Array[Combatant] = []
	if actor != null:
		result.append(actor)
	for hit in hits:
		if hit.target != null and hit.target not in result:
			result.append(hit.target)
	return result
