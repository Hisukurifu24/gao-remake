class_name QuestLibrary
## Every [Quest] in the game, by id.
##
## The bridge between the quest ids that float around content -- a
## [DialogueEffect]'s START_QUEST, a reward that chains into the next job -- and
## the resources they name. Nothing outside this file should build a path to a
## .tres; ask here, and a renamed file breaks in one place.
##
## Listed explicitly rather than scanned from the directory, for the same reason
## [ItemLibrary], [SkillLibrary] and [constant FloorRegistry.AUTHORED] are:
## [code]res://[/code] directory listing is unreliable in exported builds.
##
## Adding a quest is a .tres in [code]resources/quests/[/code], an entry in
## [constant QUESTS], and a dialogue branch that offers it. The quest test fails
## if an objective in one names an enemy, item or conversation that isn't there.

const QUEST_PATH := "res://resources/quests/%s.tres"

const QUESTS: PackedStringArray = [
	# Floor 1, Town of Beginnings
	"argo_first_errand",
	"nezha_first_blade",
	"argo_illfang",
	# Floor 10, Ashlow
	"ashlow_wolves",
	"ashlow_warden",
]

static var _cache: Dictionary[StringName, Quest] = {}
static var _all: Array[Quest] = []


## The quest [param id] names, or null (with an error) if there is no such thing.
## A null return is always a content bug -- a START_QUEST effect pointing at a
## quest that never got a resource -- so it is loud rather than silent.
static func get_quest(id: StringName) -> Quest:
	if id == &"":
		return null
	if _cache.has(id):
		return _cache[id]
	var path := QUEST_PATH % id
	if not ResourceLoader.exists(path):
		push_error("QuestLibrary: no such quest '%s'" % id)
		return null
	var quest: Quest = load(path)
	if quest == null:
		push_error("QuestLibrary: '%s' failed to load" % id)
		return null
	_cache[id] = quest
	return quest


static func exists(id: StringName) -> bool:
	return id != &"" and ResourceLoader.exists(QUEST_PATH % id)


## Every quest, in the order [constant QUESTS] lists them.
static func all() -> Array[Quest]:
	if _all.is_empty():
		for id in QUESTS:
			var quest := get_quest(StringName(id))
			if quest != null:
				_all.append(quest)
	return _all
