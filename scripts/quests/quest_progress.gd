class_name QuestProgress
extends RefCounted
## How far the player has got with one [Quest].
##
## Runtime-only, like [Combatant]: it holds the counters while a quest is live and
## [QuestLog] is the only thing that writes them. Views read it and draw.
##
## The counters cover both kinds of objective the same way, which is the point of
## the class. A KILL tally is *accumulated* here because nothing else remembers a
## kill; a COLLECT count is *recomputed* into here from the bag whenever the bag
## changes. Either way a view asks [method of] and gets a number, and neither the
## journal nor the tracker has to know which sort it is looking at.

var quest: Quest

## Objective id to progress. Only ever holds ids that are actually in the quest --
## [QuestLog] seeds every objective at construction, so a lookup never has to
## guess whether a missing key means zero or means a renamed objective.
var _counts: Dictionary[StringName, int] = {}


func _init(for_quest: Quest) -> void:
	quest = for_quest
	if quest == null:
		return
	for objective in quest.listed_objectives():
		_counts[objective.id] = 0


func of(objective: QuestObjective) -> int:
	if objective == null:
		return 0
	return _counts.get(objective.id, 0)


## Sets one objective's progress, clamped to what the objective asks for, and
## reports whether the number actually moved. [QuestLog] emits on a true return,
## so a kill that lands on a finished objective does not announce anything.
func set_progress(objective: QuestObjective, value: int) -> bool:
	if objective == null or not _counts.has(objective.id):
		return false
	var clamped := clampi(value, 0, objective.required)
	if clamped == _counts[objective.id]:
		return false
	_counts[objective.id] = clamped
	return true


func advance(objective: QuestObjective, amount := 1) -> bool:
	return set_progress(objective, of(objective) + amount)


func is_objective_complete(objective: QuestObjective) -> bool:
	return objective != null and of(objective) >= objective.required


func is_complete() -> bool:
	if quest == null:
		return false
	for objective in quest.listed_objectives():
		if not is_objective_complete(objective):
			return false
	return true


func completed_count() -> int:
	var done := 0
	for objective in quest.listed_objectives():
		if is_objective_complete(objective):
			done += 1
	return done


## "1/3" over objectives, not over kills -- the journal's at-a-glance number.
func summary() -> String:
	return "%d/%d" % [completed_count(), quest.listed_objectives().size()]
