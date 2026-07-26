class_name DialogueEffect
extends Resource
## Something a dialogue line or choice does to the world when it is reached.
##
## Effects never call into another system directly -- they set [GameState] or
## announce on [EventBus], so dialogue keeps working whether or not Inventory
## (M3) and QuestLog (M5) exist yet. Until those land, GIVE_ITEM and START_QUEST
## emit into an empty room, which is the intended shape: dialogue reports what
## happened and the systems that care subscribe.

enum Kind {
	SET_FLAG,     ## GameState.set_flag(flag)
	CLEAR_FLAG,   ## GameState.set_flag(flag, false)
	GRANT_XP,     ## GameState.grant_xp(amount)
	GIVE_ITEM,    ## EventBus.item_added(id, amount) -- M3 picks this up
	START_QUEST,  ## EventBus.quest_started(id) -- M5 picks this up
}

@export var kind: Kind = Kind.SET_FLAG

## Flag name for SET_FLAG / CLEAR_FLAG, item or quest id for the others.
@export var id: StringName = &""
## Amount for GRANT_XP and GIVE_ITEM.
@export var amount := 1


func apply() -> void:
	match kind:
		Kind.SET_FLAG:
			if id != &"":
				GameState.set_flag(id)
		Kind.CLEAR_FLAG:
			if id != &"":
				GameState.set_flag(id, false)
		Kind.GRANT_XP:
			GameState.grant_xp(amount)
		Kind.GIVE_ITEM:
			if id != &"":
				EventBus.item_added.emit(id, amount)
		Kind.START_QUEST:
			if id != &"":
				EventBus.quest_started.emit(id)


static func apply_all(effects: Array[DialogueEffect]) -> void:
	for effect in effects:
		if effect != null:
			effect.apply()
