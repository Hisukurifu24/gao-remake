class_name EnemyType
extends Resource
## One kind of monster, stated at level 1 and grown from there.
##
## Aincrad has 100 floors and a handful of enemy templates: the same Little
## Nepent that is a nuisance on floor 2 is a real fight on floor 40 because
## [method stat_at] walks its growth curve up to the floor's level. Bosses are
## the same resources with [constant Bestiary.BOSS_HP] and friends applied on
## top, which is why 10 archetypes cover 100 floor bosses.
##
## Growth is per level *above 1*, so a level-1 enemy is exactly its base stats.

@export var id: StringName = &""
@export var display_name := ""
## The 64x64 front-facing sprite drawn in the combat screen.
@export var battler: Texture2D

@export_group("Base stats")
@export var max_hp := 24
@export var attack := 6
@export var defense := 3
@export var speed := 8
@export var poise := 30

@export_group("Growth per level")
@export var hp_growth := 6.5
@export var attack_growth := 1.1
@export var defense_growth := 0.7
@export var speed_growth := 0.35
@export var poise_growth := 1.6

@export_group("Behaviour")
## Beyond the plain attack every combatant has. May be empty.
@export var skills: Array[Skill] = []
## How often it reaches for a skill rather than swinging. 0 = never.
@export_range(0.0, 1.0) var skill_bias := 0.5

@export_group("Rewards")
@export var xp_reward := 8
@export var xp_growth := 4.0
## Item ids handed to Inventory (M3) via [signal EventBus.item_added].
@export var loot: Array[StringName] = []
@export_range(0.0, 1.0) var loot_chance := 0.3


func label() -> String:
	return display_name if not display_name.is_empty() else String(id)


## A base stat grown to [param level]. The one place the curve is applied, so
## HP, attack and XP can't drift apart.
static func stat_at(base: float, growth: float, level: int) -> int:
	return maxi(1, roundi(base + growth * maxi(0, level - 1)))


func hp_at(level: int) -> int:
	return stat_at(max_hp, hp_growth, level)


func attack_at(level: int) -> int:
	return stat_at(attack, attack_growth, level)


func defense_at(level: int) -> int:
	return stat_at(defense, defense_growth, level)


func speed_at(level: int) -> int:
	return stat_at(speed, speed_growth, level)


func poise_at(level: int) -> int:
	return stat_at(poise, poise_growth, level)


func xp_at(level: int) -> int:
	return stat_at(xp_reward, xp_growth, level)
