class_name FloorDefinition
extends Resource
## One floor of Aincrad.
##
## A floor is either *authored* (a hand-built scene, for milestones like 1, 25,
## 50, 74 and 100) or *generated* (everything else). Both kinds are handed to
## SceneRouter the same way, so nothing downstream needs to know which it got.
##
## Authored floors live in resources/floors/ and are listed in FloorRegistry.
## Generated ones are synthesised on demand from the biome band + FloorTuning.

@export var floor_number := 1
@export var display_name := ""

## Set for authored floors. When present, generation parameters are ignored.
@export var authored_scene: PackedScene

@export_group("Generation")
@export var biome: BiomeKit
## The field -- rooms and corridors. A labyrinth, if there is one, is added on a
## side of it, so the map is bigger than this.
@export var size := Vector2i(64, 48)
## The labyrinth guarding the boss room, in maze cells. Zero means none: the boss
## door stands in the field's farthest room, in plain view.
@export var labyrinth := Vector2i.ZERO
@export var room_count := 9
@export var chest_count := 3
## 0 = no water/lava pools, 1 = as many as rooms allow.
@export_range(0.0, 1.0) var liquid_density := 0.25
@export_range(0.0, 1.0) var obstacle_density := 0.06

@export_group("Encounter")
@export var boss_name := ""
@export var enemy_level := 1
## Milestone floors get authored bosses and a stronger presentation.
@export var is_milestone := false


func is_authored() -> bool:
	return authored_scene != null


func label() -> String:
	if display_name.is_empty():
		return "Floor %d" % floor_number
	return "Floor %d - %s" % [floor_number, display_name]
