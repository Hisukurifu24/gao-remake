class_name CombatAction
extends RefCounted
## What a combatant has decided to do on its turn.
##
## The player builds one from the command menu, the AI builds one from its
## weights, and [CombatManager] resolves both through the same code -- there is
## no separate "enemy attack" path that can drift from the player's.
##
## A plain attack is a [Skill] like any other (see
## [method SkillLibrary.basic_attack]), so [constant Kind.SKILL] covers it.

enum Kind { SKILL, DEFEND, FLEE, ITEM }

var kind: Kind = Kind.SKILL
var skill: Skill = null
## Set for [constant Kind.ITEM]. The bottle is emptied by [CombatManager], not
## here -- an action is a decision, not a transaction.
var item: Item = null
## The chosen target for single-target skills and items; ignored by the rest.
var target: Combatant = null


static func use(of_skill: Skill, on: Combatant = null) -> CombatAction:
	var action := CombatAction.new()
	action.kind = Kind.SKILL
	action.skill = of_skill
	action.target = on
	return action


## Drinking, throwing or eating something from the bag. [param on] defaults to
## the user; only allies can be targeted, since nothing in the game is thrown at
## an enemy yet.
static func use_item(of_item: Item, on: Combatant = null) -> CombatAction:
	var action := CombatAction.new()
	action.kind = Kind.ITEM
	action.item = of_item
	action.target = on
	return action


static func defend() -> CombatAction:
	var action := CombatAction.new()
	action.kind = Kind.DEFEND
	return action


static func flee() -> CombatAction:
	var action := CombatAction.new()
	action.kind = Kind.FLEE
	return action
