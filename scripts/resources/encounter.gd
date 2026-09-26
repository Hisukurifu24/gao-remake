class_name Encounter
extends Resource
## Who you are fighting, and under what rules.
##
## Handed to [method CombatManager.start]. Most encounters are built at runtime
## by [Bestiary] from the floor you are standing on, but the type is a
## [Resource] so an authored floor can ship a fixed fight as a .tres.
##
## The level applies to every enemy in the list: a floor's monsters are the
## floor's level, and difficulty comes from the curve in [FloorTuning], not from
## per-enemy tuning.

## Who owns the first round. Decided on the overworld, by how the fight was
## started, and honoured by [CombatManager] without it learning what a map is.
enum Opening {
	NORMAL,         ## Speed order from the first round.
	PARTY_FIRST,    ## Struck before it noticed you: the enemies sit round 1 out.
	ENEMIES_FIRST,  ## Caught from behind: the party sits round 1 out.
}

@export var id: StringName = &""
@export var display_name := ""
@export var enemies: Array[EnemyType] = []
@export var level := 1

@export_group("Rules")
## Boss fights can't be walked away from.
@export var can_flee := true
@export var is_boss := false
@export var opening: Opening = Opening.NORMAL

@export_group("Presentation")
## Renames the first enemy. Generated bosses get their name from
## [method FloorTuning.boss_name], which the [EnemyType] template can't know.
@export var boss_name := ""
@export var backdrop := Color(0.07, 0.08, 0.13)
## The floor this fight stands on, tiled across the lower half of the screen.
## Filled in by [Bestiary] from the biome, so the battle draws the ground the
## player was walking on without [CombatManager] ever learning what a map is.
@export var ground_texture: Texture2D
## Where this fight happened, for the victory text. 0 for fights outside a floor.
@export var floor_number := 0


func label() -> String:
	if not display_name.is_empty():
		return display_name
	if not boss_name.is_empty():
		return boss_name
	return "Battle"


## The on-screen name of the [param index]-th enemy: the boss override for the
## first slot, otherwise the template's name, numbered when there are duplicates.
func name_for(index: int) -> String:
	if index == 0 and not boss_name.is_empty():
		return boss_name
	var enemy := enemies[index]
	var duplicates := 0
	var ordinal := 0
	for i in enemies.size():
		if enemies[i] == enemy:
			duplicates += 1
			if i == index:
				ordinal = duplicates
	if duplicates <= 1:
		return enemy.label()
	return "%s %s" % [enemy.label(), char("A".unicode_at(0) + ordinal - 1)]
