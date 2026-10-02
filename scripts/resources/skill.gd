class_name Skill
extends Resource
## A sword skill, a spell, a monster's bite -- everything a combatant can do on
## its turn except Defend and Flee.
##
## Skills are the one currency of combat: the player's list comes from
## [SkillLibrary] by level, an enemy's from its [EnemyType], and a plain attack
## is just the skill with no cooldown. [CombatManager] resolves all of them
## through one path, so a new skill is a .tres and nothing else.
##
## SAO's flavour lives in two fields. [member cooldown] is why you can't spam
## Vorpal Strike, and [member post_motion] is the recovery window after a heavy
## swing -- the moments Kirito spends frozen at the end of an animation, here
## paid for as extra damage taken on the way back.

enum Kind {
	STRIKE,  ## Deals damage. May also apply [member applies].
	HEAL,    ## Restores HP scaled by [member power].
	STATUS,  ## Applies [member applies] and nothing else.
}

enum Target {
	ONE_ENEMY,
	ALL_ENEMIES,
	SELF,
	ONE_ALLY,
	ALL_ALLIES,
}

@export var id: StringName = &""
@export var display_name := ""
@export_multiline var description := ""
@export var kind: Kind = Kind.STRIKE
@export var target: Target = Target.ONE_ENEMY

@export_group("Numbers")
## Percent of the user's attack. 100 is a plain swing; see [CombatMath].
@export var power := 100
@export_range(0, 100) var accuracy := 95
@export_range(0, 100) var crit_chance := 5
## Poise damage. Empty a combatant's poise and it is staggered: it loses its
## next turn and takes extra damage until it recovers.
@export var stagger := 10

@export_group("Timing")
## Turns before it can be used again. 0 means always available.
@export var cooldown := 0
## Turns of vulnerability after using it -- SAO's post-motion delay. The user
## takes extra damage while it lasts.
@export var post_motion := 0

@export_group("Status")
@export var applies: StatusEffect
@export_range(0, 100) var apply_chance := 100

@export_group("Availability")
## Player skills unlock at this level. Enemy skills ignore it.
@export var unlock_level := 1
## Relative likelihood an enemy picks this over its other options.
@export var ai_weight := 1.0

@export_group("Presentation")
## Shown when the skill fires; "%s" is the user. Falls back to "X uses Y!".
@export var announce := ""
## Played over whoever it lands on. Empty lands with the flash alone.
@export var fx: SkillFx
## Its row in the command menu, and the greyed one while it cools down -- the
## pack draws both.
@export var icon: Texture2D
@export var icon_disabled: Texture2D


func label() -> String:
	return display_name if not display_name.is_empty() else String(id)


func hits_everyone() -> bool:
	return target in [Target.ALL_ENEMIES, Target.ALL_ALLIES]


## True when the skill is aimed across the line at the other side.
func is_offensive() -> bool:
	return target in [Target.ONE_ENEMY, Target.ALL_ENEMIES]


## Whether the player has to pick a target before this can be used.
func needs_target() -> bool:
	return target in [Target.ONE_ENEMY, Target.ONE_ALLY]


func announcement(user_name: String) -> String:
	if announce.is_empty():
		return "%s uses %s!" % [user_name, label()]
	return announce % user_name
