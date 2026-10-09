class_name LocalQuests
## The jobs a generated floor's village hands out once it has settled (plan.md,
## M6 "Floor variety"): templates -- a hunt, a gathering, a player lost in the
## labyrinth -- filled in from the floor's biome and bestiary.
##
## Ninety generated floors cannot each get hand-written quests, and they cannot be
## .tres files either, so a local quest is [i]named[/i] rather than stored:
## [code]local_<floor>_<kind>[/code]. [QuestLibrary] hands any such id here, and
## the same id builds the same [Quest] every time, because everything about it --
## which two jobs the floor has, who gives them, how many, what they pay -- is drawn
## from the floor's own [code]hash("<seed>:settle")[/code] stream, never from the
## floor's rng and never from the map. That is what lets the journal draw a quest
## on floor 60 that was taken on floor 7, and what the M7 save gets for free: the
## id is the whole quest.
##
## Settling is keyed on progression, not on the seed: a floor's camp becomes a
## village once the floor [constant SETTLE_AFTER] above it is cleared, and that is
## also each quest's prerequisite -- the offer and the prerequisite gated on the
## same thing, as [Quest] asks.
##
## The conversations are built here too, so the offer, the wait, the turn-in and
## the thanks all read the quest's own [code]quest_<id>_*[/code] flags.

## How many floors above a floor must be cleared before its camp becomes a village.
const SETTLE_AFTER := 3
## How many jobs a village has: one per settler who stands outside a house.
const PER_FLOOR := 2
const KINDS: PackedStringArray = ["hunt", "gather", "lost"]

const ID_FORMAT := "local_%d_%s"
const LOST_TALK_FORMAT := "local_%d_lost_found"
const CHARACTERS := "res://assets/ninja_adventure/Actor/Character/%s/%s.png"

## Who settles a floor behind the front line: townsfolk, not fighters.
const SETTLER_SHEETS: PackedStringArray = [
	"Villager3", "Villager5", "Villager6", "OldMan2", "OldMan3", "OldWoman", "Boy",
	"Noble", "Cavegirl2",
]
## Settlers go by name rather than handle: these are the people who stopped climbing.
const SETTLERS: PackedStringArray = [
	"Hollis", "Breda", "Odo", "Maeve", "Tobin", "Sefa", "Ewan", "Linnet", "Corra",
	"Piet", "Aldis", "Runa", "Bastian", "Ivy", "Merrit", "Oona", "Fenwick", "Isolde",
]
## Whoever goes into a labyrinth to map it and doesn't come back.
const LOST_SHEETS: PackedStringArray = ["NinjaLeaf", "CamouflageRed", "Master", "Monk2", "Hunter"]

const HUNT_COUNT := Vector2i(4, 6)
const GATHER_COUNT := 3
## What each job pays in XP -- and in Col, by the same count -- in the floor's own
## monsters' worth: a little on top of the kills it takes, never a second climb.
## The floor is at least [constant SETTLE_AFTER] below the player by the time it
## is offered, so its monsters are worth less than the front line's.
const HUNT_XP := 2.0
const GATHER_XP := 3.0
const LOST_XP := 4.0
## The item part of each job's pay. The lost player's thanks is a piece of gear
## from what a floor cache holds.
const HUNT_ITEMS: Array = [[&"health_potion", 1], [&"small_potion", 3]]
const GATHER_ITEMS: Array = [[&"whetstone", 2], [&"health_potion", 1], [&"antidote", 2]]
const LOST_GEAR: Array[StringName] = [&"guard_ring", &"swift_charm", &"leather_coat", &"kobold_blade"]

## What each job's people say. {monster}, {item}, {count}, {giver}, {lost} and
## {floor} are filled in from the floor.
const TEXT := {
	"hunt": {
		"title": ["The {monster} Problem", "Clear the Doorstep"],
		"pitch": [
			"They come right up to the houses now, the {monster} do. Put {count} of them down and I'll make it worth your while.",
			"We moved up here because the front line had gone past. Nobody told the {monster}. {count} of them would teach the rest.",
		],
		"accepted": "{count}, then. They keep to the field rooms -- you won't have to look hard.",
		"waiting": "Every {monster} you put down is one less at my door. Keep going.",
		"ready": "It's gone quiet out there. That was you? Here -- you've earned it.",
		"done": "Not a single {monster} at the door since. I sleep through the night now.",
	},
	"gather": {
		"title": ["{giver}'s Order", "Short on {item}"],
		"pitch": [
			"I'm building, and I'm short of {item} -- {count} of them. The {monster} out in the field carry it, if you're not squeamish.",
			"Floor {floor}'s been good to us, but there's no trader comes this far down any more. I need {count} {item}. Every {monster} carries a little.",
		],
		"accepted": "Bring them all at once when you have them. I'm not going anywhere.",
		"waiting": "{count} {item}. No fewer -- I've measured twice.",
		"ready": "That's the lot? Let me see... yes. That'll do nicely. Take these.",
		"done": "See that roof? Your {item} is holding it up.",
	},
	"lost": {
		"title": ["Lost in the Labyrinth", "Where's {lost}?"],
		"pitch": [
			"{lost} went into the labyrinth to map it three days ago, and hasn't come back. None of us can get through it. You did, once.",
			"Have you seen {lost}? Went in after the dead ends with a pencil and a lantern. That was the day before yesterday.",
		],
		"accepted": "Try the dead ends. {lost} always said that's where everyone else's maps go wrong.",
		"waiting": "Nothing yet? {lost} wouldn't have gone back through the boss room. Try the dead ends.",
		"ready": "You found {lost}? Alive? Oh, thank you. It isn't much, but take it.",
		"done": "{lost}'s out mapping again already. Some people don't learn.",
	},
}
const LOST_LINES := {
	"found": "Someone! I've been going round in circles for days -- the walls move when you're not looking, I swear. {giver} sent you? Go on ahead. I'll follow your trail out.",
	"after": "I'm right behind you. Honestly.",
}

static var _plans: Dictionary[String, Dictionary] = {}


## Whether floor [param floor_number] ever settles: a generated floor with a
## floor [constant SETTLE_AFTER] above it to clear. Floor 1 is already a city and
## the authored floors grow their own way.
static func settles(floor_number: int) -> bool:
	return floor_number >= 2 and floor_number + SETTLE_AFTER <= FloorTuning.TOP_FLOOR \
			and not FloorRegistry.AUTHORED.has(floor_number)


## Whether floor [param floor_number]'s camp is a village yet.
static func is_settled(floor_number: int) -> bool:
	return settles(floor_number) and GameState.is_floor_cleared(floor_number + SETTLE_AFTER)


static func quest_id(floor_number: int, kind: String) -> StringName:
	return StringName(ID_FORMAT % [floor_number, kind])


## The jobs floor [param floor_number]'s village offers, in the order its settlers
## stand: empty for a floor that never settles.
static func ids_for(floor_number: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	if not settles(floor_number):
		return ids
	for job: Dictionary in _plan(floor_number)["jobs"]:
		ids.append(quest_id(floor_number, job["kind"]))
	return ids


## Whether [param id] names one of a settled floor's jobs.
static func owns(id: StringName) -> bool:
	return not _job(id).is_empty()


## The quest [param id] names, built from its floor; null if it names none.
static func build(id: StringName) -> Quest:
	var job := _job(id)
	if job.is_empty():
		return null
	var floor_number: int = job["floor"]
	var words: Dictionary = job["words"]
	var quest := Quest.new()
	quest.id = id
	quest.title = (job["title"] as String).format(words)
	quest.giver = job["giver"]
	quest.summary = (job["pitch"] as String).format(words)
	var prerequisites: Array[DialogueCondition] = [_cleared(floor_number + SETTLE_AFTER)]
	quest.prerequisites = prerequisites

	var objective := QuestObjective.new()
	objective.id = StringName(job["kind"])
	match job["kind"]:
		"hunt":
			objective.kind = QuestObjective.Kind.KILL
			objective.target = job["target"]
		"gather":
			objective.kind = QuestObjective.Kind.COLLECT
			objective.target = job["target"]
		"lost":
			objective.kind = QuestObjective.Kind.TALK
			objective.target = lost_talk_id(floor_number)
			objective.description = "Find %s in the labyrinth" % job["lost"]
	objective.required = job["count"]
	var objectives: Array[QuestObjective] = [objective]
	quest.objectives = objectives

	var xp := DialogueEffect.new()
	xp.kind = DialogueEffect.Kind.GRANT_XP
	xp.amount = job["xp"]
	var item := DialogueEffect.new()
	item.kind = DialogueEffect.Kind.GIVE_ITEM
	item.id = job["reward"]
	item.amount = job["reward_amount"]
	var col := DialogueEffect.new()
	col.kind = DialogueEffect.Kind.GIVE_COL
	col.amount = job["col"]
	var rewards: Array[DialogueEffect] = [xp, col, item]
	quest.rewards = rewards
	return quest


## Who gives job [param id]: [code]{name, sheet}[/code], or empty.
static func giver(id: StringName) -> Dictionary:
	var job := _job(id)
	if job.is_empty():
		return {}
	return {"name": job["giver"], "sheet": job["sheet"]}


## The giver's whole conversation about job [param id]: thanks once it is done,
## the turn-in once it is ready, a reminder while it runs, and the offer.
static func giver_dialogue(id: StringName) -> Dialogue:
	var job := _job(id)
	if job.is_empty():
		return null
	var words: Dictionary = job["words"]
	var text: Dictionary = TEXT[job["kind"]]
	var talk := Dialogue.new()
	talk.id = StringName("%s_giver" % id)
	talk.default_speaker = job["giver"]
	talk.default_portrait = load(CHARACTERS % [job["sheet"], "Faceset"])

	# Blocks first, most specific first; the two answers after them are only ever
	# reached by a choice, since the offer above them always opens.
	talk.lines.append(_line(text["done"], words, [_flag(id, "done")]))
	var ready := _line(text["ready"], words, [_flag(id, "ready")])
	var hand_in := DialogueChoice.new()
	hand_in.text = "Here."
	hand_in.next = DialogueLine.END
	var turn_in: Array[DialogueEffect] = [_effect(DialogueEffect.Kind.TURN_IN_QUEST, id)]
	hand_in.effects = turn_in
	var answers: Array[DialogueChoice] = [hand_in, _choice("Not just yet.")]
	ready.choices = answers
	talk.lines.append(ready)
	talk.lines.append(_line(text["waiting"], words, [_flag(id, "started")]))
	var offer := _line(job["pitch"], words, [])
	var take := DialogueChoice.new()
	take.text = "I'll do it."
	take.next = &"accepted"
	# The quest's prerequisite, and not already taken: the offer is gated on
	# exactly what QuestLog.start() will check.
	var untaken := _flag(id, "started")
	untaken.negate = true
	var gate: Array[DialogueCondition] = [_cleared(job["floor"] + SETTLE_AFTER), untaken]
	take.conditions = gate
	var start: Array[DialogueEffect] = [_effect(DialogueEffect.Kind.START_QUEST, id)]
	take.effects = start
	var offered: Array[DialogueChoice] = [take, _choice("Not now.")]
	offer.choices = offered
	talk.lines.append(offer)
	var accepted := _line(text["accepted"], words, [])
	accepted.id = &"accepted"
	talk.lines.append(accepted)
	return talk


## The conversation that finds floor [param floor_number]'s lost player, or null
## if its village has no one lost.
static func lost_dialogue(floor_number: int) -> Dialogue:
	var job := _job(quest_id(floor_number, "lost"))
	if job.is_empty():
		return null
	var words: Dictionary = job["words"]
	var talk := Dialogue.new()
	talk.id = lost_talk_id(floor_number)
	talk.default_speaker = job["lost"]
	talk.default_portrait = load(CHARACTERS % [job["lost_sheet"], "Faceset"])
	talk.lines.append(_line(LOST_LINES["after"], words, [_flag(talk_quest(floor_number), "ready")]))
	talk.lines.append(_line(LOST_LINES["after"], words, [_flag(talk_quest(floor_number), "done")]))
	talk.lines.append(_line(LOST_LINES["found"], words, []))
	return talk


## Who is lost on floor [param floor_number]: [code]{name, sheet}[/code], or empty.
static func lost_person(floor_number: int) -> Dictionary:
	var job := _job(quest_id(floor_number, "lost"))
	if job.is_empty():
		return {}
	return {"name": job["lost"], "sheet": job["lost_sheet"]}


static func lost_talk_id(floor_number: int) -> StringName:
	return StringName(LOST_TALK_FORMAT % floor_number)


static func talk_quest(floor_number: int) -> StringName:
	return quest_id(floor_number, "lost")


## Whether [param id] is the conversation a lost-player job asks for -- the one
## TALK target with no .tres behind it.
static func is_conversation(id: StringName) -> bool:
	var parts := String(id).split("_")
	if parts.size() != 4 or parts[0] != "local" or not parts[1].is_valid_int():
		return false
	return id == lost_talk_id(int(parts[1])) and owns(talk_quest(int(parts[1])))


# --- the stream -----------------------------------------------------------------

## The job [param id] names, from its floor's plan; empty if it names none.
static func _job(id: StringName) -> Dictionary:
	var parts := String(id).split("_")
	if parts.size() != 3 or parts[0] != "local" or not parts[1].is_valid_int():
		return {}
	var floor_number := int(parts[1])
	if not settles(floor_number):
		return {}
	for job: Dictionary in _plan(floor_number)["jobs"]:
		if job["kind"] == parts[2]:
			return job
	return {}


## Everything about floor [param floor_number]'s jobs, drawn in a fixed order from
## its settle stream. Cached by seed as well as floor, so a new game's floor 7 is
## not the last one's.
static func _plan(floor_number: int) -> Dictionary:
	var generation_seed := FloorRegistry.seed_for(floor_number)
	var key := "%d:%d" % [generation_seed, floor_number]
	if _plans.has(key):
		return _plans[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:settle" % generation_seed)

	var kinds := Array(KINDS)
	_shuffle(kinds, rng)
	var names := Array(SETTLERS)
	_shuffle(names, rng)
	var sheets := Array(SETTLER_SHEETS)
	_shuffle(sheets, rng)
	var pool := Bestiary.pool_for_floor(floor_number)
	var level := FloorTuning.enemy_level(floor_number)
	# Whoever the lost-player job's giver is missing: one name past the givers.
	var lost: String = names[PER_FLOOR]
	var lost_sheet: String = LOST_SHEETS[rng.randi() % LOST_SHEETS.size()]

	var jobs: Array[Dictionary] = []
	for i in PER_FLOOR:
		var kind: String = kinds[i]
		var text: Dictionary = TEXT[kind]
		var monster: EnemyType = pool[rng.randi() % pool.size()]
		var worth := monster.xp_at(level)
		var job := {
			"floor": floor_number,
			"kind": kind,
			"giver": names[i],
			"sheet": sheets[i % sheets.size()],
			"title": text["title"][rng.randi() % text["title"].size()],
			"pitch": text["pitch"][rng.randi() % text["pitch"].size()],
			"target": &"",
			"count": 1,
		}
		var item := ""
		match kind:
			"hunt":
				job["target"] = monster.id
				job["count"] = rng.randi_range(HUNT_COUNT.x, HUNT_COUNT.y)
				job["xp"] = roundi(worth * HUNT_XP)
				job["col"] = roundi(monster.col_at(level) * HUNT_XP)
				var pay: Array = HUNT_ITEMS[rng.randi() % HUNT_ITEMS.size()]
				job["reward"] = pay[0]
				job["reward_amount"] = pay[1]
			"gather":
				# Every monster in every pool drops a material; the floor test holds
				# the pools to that.
				job["target"] = monster.loot[0] if not monster.loot.is_empty() else &""
				job["count"] = GATHER_COUNT
				job["xp"] = roundi(worth * GATHER_XP)
				job["col"] = roundi(monster.col_at(level) * GATHER_XP)
				var pay: Array = GATHER_ITEMS[rng.randi() % GATHER_ITEMS.size()]
				job["reward"] = pay[0]
				job["reward_amount"] = pay[1]
				var material := ItemLibrary.get_item(job["target"]) if ItemLibrary.exists(job["target"]) else null
				item = material.label() if material != null else String(job["target"])
			"lost":
				job["xp"] = roundi(worth * LOST_XP)
				job["col"] = roundi(monster.col_at(level) * LOST_XP)
				job["reward"] = LOST_GEAR[rng.randi() % LOST_GEAR.size()]
				job["reward_amount"] = 1
		job["lost"] = lost
		job["lost_sheet"] = lost_sheet
		job["words"] = {
			"monster": monster.label(),
			"item": item,
			"count": job["count"],
			"giver": job["giver"],
			"lost": job["lost"],
			"floor": floor_number,
		}
		jobs.append(job)
	var plan := {"jobs": jobs}
	_plans[key] = plan
	return plan


static func _line(text: String, words: Dictionary, conditions: Array[DialogueCondition]) -> DialogueLine:
	var line := DialogueLine.new()
	line.text = text.format(words)
	line.conditions = conditions
	line.next = DialogueLine.END
	return line


static func _choice(text: String) -> DialogueChoice:
	var choice := DialogueChoice.new()
	choice.text = text
	choice.next = DialogueLine.END
	return choice


static func _flag(id: StringName, suffix: String) -> DialogueCondition:
	var condition := DialogueCondition.new()
	condition.test = DialogueCondition.Test.FLAG_SET
	condition.flag = QuestLog.flag_for(id, suffix)
	return condition


static func _cleared(floor_number: int) -> DialogueCondition:
	var condition := DialogueCondition.new()
	condition.test = DialogueCondition.Test.FLOOR_CLEARED
	condition.number = floor_number
	return condition


static func _effect(kind: DialogueEffect.Kind, id: StringName) -> DialogueEffect:
	var effect := DialogueEffect.new()
	effect.kind = kind
	effect.id = id
	return effect


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var held = items[i]
		items[i] = items[j]
		items[j] = held
