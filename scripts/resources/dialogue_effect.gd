class_name DialogueEffect
extends Resource
## Something a dialogue line or choice does to the world when it is reached.
##
## Effects never call into another system directly -- they set [GameState] or
## announce on [EventBus], so dialogue keeps working whether or not Inventory and
## QuestLog exist yet. GIVE_ITEM found its listener in M3 and START_QUEST found
## one in M5, neither time by changing this file, which is the argument for the
## arrangement.
##
## [Quest] reuses this class for its rewards, so everything here is also something
## a quest can pay -- see the [Quest] class docs for why.

enum Kind {
	SET_FLAG,      ## GameState.set_flag(flag)
	CLEAR_FLAG,    ## GameState.set_flag(flag, false)
	GRANT_XP,      ## GameState.grant_xp(amount)
	GIVE_ITEM,     ## EventBus.item_granted(id, amount) -- Inventory picks this up
	START_QUEST,   ## EventBus.quest_started(id) -- QuestLog picks this up
	## EventBus.quest_turn_in_requested(id) -- QuestLog picks this up. The player
	## saying "here, it's done" to the NPC who asked; refused unless every
	## objective is met, so the dialogue branch offering it should be gated on the
	## quest's [code]_ready[/code] flag.
	TURN_IN_QUEST,
	GIVE_COL,      ## EventBus.col_granted(amount) -- the purse picks this up
	## EventBus.col_charged(amount) -- the purse picks this up, and refuses the
	## whole charge if it cannot pay. Gate the line on MIN_COL so it never has to.
	TAKE_COL,
	## EventBus.forge_requested(smith) for the [Smith] named by id -- the forge
	## screen picks this up and opens once the conversation closes. A smith who
	## also has things to say: Nezha's "work on my gear".
	OPEN_FORGE,
	## Queues Argo's door-information pitch ([method DoorIntel.conversation]) to
	## follow this conversation: built when asked, since what she has to sell
	## depends on where you have been. The one effect that starts a conversation,
	## which is still the dialogue system talking to itself.
	SELL_INTEL,
}

@export var kind: Kind = Kind.SET_FLAG

## Flag name for SET_FLAG / CLEAR_FLAG, item, quest or forge id for the others.
@export var id: StringName = &""
## Amount for GRANT_XP, GIVE_ITEM, GIVE_COL and TAKE_COL.
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
				EventBus.item_granted.emit(id, amount)
		Kind.START_QUEST:
			if id != &"":
				EventBus.quest_started.emit(id)
		Kind.TURN_IN_QUEST:
			if id != &"":
				EventBus.quest_turn_in_requested.emit(id)
		Kind.GIVE_COL:
			EventBus.col_granted.emit(amount)
		Kind.TAKE_COL:
			EventBus.col_charged.emit(amount)
		Kind.SELL_INTEL:
			DialogueRunner.start(DoorIntel.conversation())
		Kind.OPEN_FORGE:
			var smith := ShopLibrary.get_smith(id) if id != &"" else null
			if smith != null:
				EventBus.forge_requested.emit(smith)


static func apply_all(effects: Array[DialogueEffect]) -> void:
	for effect in effects:
		if effect != null:
			effect.apply()


## How this reads in a list of quest rewards: "40 XP", "Small Potion x2". Empty
## for the effects that have nothing to show the player -- a flag being set is
## bookkeeping, not a payment.
func summary() -> String:
	match kind:
		Kind.GRANT_XP:
			return "%d XP" % amount
		Kind.GIVE_COL:
			return "%d col" % amount
		Kind.GIVE_ITEM:
			var item := ItemLibrary.get_item(id) if ItemLibrary.exists(id) else null
			var name := item.label() if item != null else String(id)
			return name if amount <= 1 else "%s x%d" % [name, amount]
	return ""
