class_name QuestObjective
extends Resource
## One thing a [Quest] asks the player to do.
##
## Four kinds, chosen because each one already has a signal announcing it and
## needed no new plumbing anywhere:
##
## [codeblock]
## KILL     EventBus.enemy_defeated    counted as it happens
## COLLECT  Inventory.count()          read from the bag, not counted
## TALK     EventBus.dialogue_finished counted as it happens
## REACH    GameState.is_floor_cleared read from the world
## [/codeblock]
##
## The split between *counted* and *read* is the one real decision here.
## [b]A collect objective reads the bag; it does not count deliveries.[/b]
## Counting [signal EventBus.item_added] would let a player satisfy "bring me
## five hides" by picking five up and then throwing them away, and the objective
## could never go back down. Kills and conversations are the opposite -- they are
## events with no lasting record, so they have to be counted when they happen.
## [method is_state_based] is that distinction, and [QuestLog] is what acts on it.

enum Kind {
	KILL,     ## Defeat [member target] (an [EnemyType] id) [member required] times.
	COLLECT,  ## Hold [member required] of [member target] (an [Item] id) in the bag.
	TALK,     ## Finish a conversation with [member target] (a [Dialogue] id).
	REACH,    ## Clear floor [member number].
}

## Dialogue is the one target kind with no library to ask -- nothing else in the
## game ever needs to find a conversation by id, so building one for a single
## validation check would be the wrong trade. See [method target_is_valid].
const DIALOGUE_PATH := "res://resources/dialogue/%s.tres"

## Unique within its quest. This is what [signal EventBus.quest_objective_updated]
## names and what [QuestProgress] keys its counters on, so renaming one resets
## progress -- which is correct, it is a different objective.
@export var id: StringName = &""
@export var kind: Kind = Kind.KILL

## Enemy id for KILL, item id for COLLECT, dialogue id for TALK. Unused by REACH.
@export var target: StringName = &""
## Floor number for REACH. Unused by the others.
@export var number := 0
@export_range(1, 999) var required := 1

## What the journal shows. Leave empty and [method label] writes one from the
## target, which is fine for "Defeat 3 Frenzy Boar" and poor for anything with
## flavour -- author it for real quests.
@export var description := ""


## The line the journal and the tracker draw. Never empty: an objective with no
## description still has to be readable, or the player is told to do nothing.
func label() -> String:
	if not description.is_empty():
		return description
	match kind:
		Kind.KILL:
			return "Defeat %s" % _target_label(_enemy_label())
		Kind.COLLECT:
			return "Collect %s" % _target_label(_item_label())
		Kind.TALK:
			return "Speak with %s" % _target_label(String(target))
		Kind.REACH:
			return "Clear floor %d" % number
	return String(id)


## "Defeat 3 Frenzy Boar   1/3". Single-step objectives drop the counter, because
## "1/1" is noise on "Clear floor 1".
func progress_text(current: int) -> String:
	if required <= 1:
		return label()
	return "%s   %d/%d" % [label(), mini(current, required), required]


## Whether progress is *read* from the world rather than counted as it happens --
## see the class docs. [QuestLog] recomputes these from scratch whenever the thing
## they read changes, so they can go down as well as up.
func is_state_based() -> bool:
	return kind == Kind.COLLECT or kind == Kind.REACH


## Progress this objective has right now, for the kinds that can answer without
## a history. Counted kinds return 0 -- their tally lives in [QuestProgress].
func current_state() -> int:
	match kind:
		Kind.COLLECT:
			return mini(Inventory.count(target), required)
		Kind.REACH:
			return required if GameState.is_floor_cleared(number) else 0
	return 0


## Whether [param event_target] advances this objective by one. The id a kill or a
## conversation announces, matched against what this objective is watching.
func matches_event(event_kind: Kind, event_target: StringName) -> bool:
	return kind == event_kind and target != &"" and target == event_target


## Whether this objective names something that exists.
##
## [b]The load-bearing check in the quest suite.[/b] A KILL objective naming an
## enemy id with no resource behind it is silent in every other way: the kill
## simply never registers and the quest can never be finished. Same for a COLLECT
## on a misspelt item, or a TALK on a conversation that was renamed.
func target_is_valid() -> bool:
	match kind:
		Kind.KILL:
			return Bestiary.exists(target)
		Kind.COLLECT:
			return ItemLibrary.exists(target)
		Kind.TALK:
			return target != &"" and ResourceLoader.exists(DIALOGUE_PATH % target)
		Kind.REACH:
			return number >= 1 and number <= FloorTuning.TOP_FLOOR
	return false


func kind_name() -> String:
	match kind:
		Kind.KILL: return "Defeat"
		Kind.COLLECT: return "Collect"
		Kind.TALK: return "Talk"
		Kind.REACH: return "Reach"
	return "Objective"


## "3 Frenzy Boar", or just "Frenzy Boar" when one is enough.
func _target_label(name: String) -> String:
	return name if required <= 1 else "%d %s" % [required, name]


func _enemy_label() -> String:
	var type := Bestiary.get_enemy(target) if Bestiary.exists(target) else null
	return type.label() if type != null else String(target)


func _item_label() -> String:
	var item := ItemLibrary.get_item(target) if ItemLibrary.exists(target) else null
	return item.label() if item != null else String(target)
