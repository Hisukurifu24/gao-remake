class_name Quest
extends Resource
## A job someone gives the player: objectives, what unlocks it, what it pays.
##
## Pure data, like [Item] and [Skill]. [QuestLog] knows how to track one and the
## journal knows how to draw one; neither knows what any *particular* quest is, so
## adding one is a .tres plus a line in [QuestLibrary].
##
## [b]Prerequisites are [DialogueCondition]s and rewards are [DialogueEffect]s --
## the same two classes dialogue uses.[/b] Not an accident and not laziness: a
## prerequisite asks [GameState] exactly the questions a dialogue line asks
## ("is this flag set?", "is floor 25 cleared?", "am I level 10 yet?"), and a
## reward does exactly what a dialogue effect does. Reusing them means a quest can
## pay out by starting another quest for free, and it means there is one condition
## language in the game rather than two that drift. They are misnamed for this
## second job; renaming them would rewrite every dialogue .tres for a word, which
## is the worse trade.
##
## Quest state reaches dialogue the same way everything else does: [QuestLog]
## writes [code]quest_<id>_started[/code], [code]_ready[/code] and [code]_done[/code]
## flags into [GameState], so an NPC gates a line on a quest with no new
## machinery. That is why [DialogueCondition] still only knows about GameState.

@export var id: StringName = &""
@export var title := ""
## Who hands it out. Shown in the journal; not checked against anything.
@export var giver := ""
## The pitch, in the giver's voice. Shown in the journal above the objectives.
@export_multiline var summary := ""

@export var objectives: Array[QuestObjective] = []

@export_group("Availability")
## All must pass before [method QuestLog.start] will accept this quest. Gate the
## dialogue choice that offers it on the same conditions -- otherwise the player
## picks "I'll take it" and nothing happens, which is the one failure mode this
## arrangement can produce.
@export var prerequisites: Array[DialogueCondition] = []

@export_group("Result")
## Paid out when the quest is turned in. GIVE_ITEM, GRANT_XP, SET_FLAG and
## START_QUEST all work here exactly as they do at the end of a conversation.
@export var rewards: Array[DialogueEffect] = []
## When true the quest sits at [constant QuestLog.State.READY] with every
## objective met until the player goes back and says so, which is what the
## [code]_ready[/code] flag and a turn-in dialogue branch are for. When false it
## pays out the moment the last objective lands -- right for "reach floor 10",
## wrong for anything with a person on the other end of it.
@export var needs_turn_in := true


func label() -> String:
	return title if not title.is_empty() else String(id)


## Whether the player may take this on right now. Says nothing about whether they
## already have -- [QuestLog] owns that.
func is_available() -> bool:
	return DialogueCondition.all_met(prerequisites)


func objective(objective_id: StringName) -> QuestObjective:
	for entry in objectives:
		if entry != null and entry.id == objective_id:
			return entry
	return null


## Objectives with a real target, in order. Everything that walks the list goes
## through here so one broken entry in a .tres cannot take a quest down with it.
func listed_objectives() -> Array[QuestObjective]:
	var listed: Array[QuestObjective] = []
	for entry in objectives:
		if entry != null and entry.id != &"":
			listed.append(entry)
	return listed


## "40 XP, Small Potion x2" -- the reward line in the journal, built from the
## effects themselves so a .tres cannot promise something it does not pay.
func reward_summary() -> String:
	var parts := PackedStringArray()
	for reward in rewards:
		if reward == null:
			continue
		var text := reward.summary()
		if not text.is_empty():
			parts.append(text)
	return ", ".join(parts)
