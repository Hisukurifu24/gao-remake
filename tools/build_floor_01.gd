extends "res://tools/authored_floor.gd"
## Builds Floor 1's West Field -- the open meadow south of the Town of Beginnings,
## and the first labyrinth anyone in Aincrad walks into.
##
##     "$GODOT" --headless --path . --script res://tools/build_floor_01.gd
##     "$GODOT" --headless --path . --script res://tools/build_floor_01.gd -- --preview
##
## The town is still tools/build_placeholder_maps.gd's. This file is the field;
## everything that isn't the field -- painting, joining, placing, checking, saving
## -- is in tools/authored_floor.gd. It overwrites scenes/world/field.tscn.
##
## [b]A small first maze.[/b] Illfang's door used to stand at the end of the road
## in plain view. Now the road runs east into a labyrinth grown by the generator's
## own code from a seed fixed here, and the door shows only from inside its room --
## the rule every floor above follows. It is deliberately smaller than Floor 2's,
## so the rule is learned on a maze you can hold in your head: one camp, a few dead
## ends, a door.
##
## [b]One curiosity.[/b] A wisp waits by the town gate and leads you across the
## meadow to its shrine by the pond: the gentlest of the puzzles, and the one that
## teaches the others -- a strange thing you can see from a distance pays out in a
## chest that was not there before.

const BIOME_PATH := "res://resources/biomes/meadow.tres"
const OUT_PATH := "res://scenes/world/field.tscn"
const TOWN_PATH := "res://scenes/world/town.tscn"

const FLOOR_NUMBER := 1
## The seed the field was dressed with before it moved onto this builder, kept so
## its trees and flowers stayed where they were.
const DRESS_SEED := 1002

## The meadow and the forest round it, two trees deep, and the labyrinth east of
## it -- 7x5 cells of maze (30x22 tiles), its mouth on its west wall where the
## road arrives. Six columns of forest beyond it: a fight with a boss Illfang's
## size is framed at x1, ten tiles either side of it, and a map edge closer than
## that pins the camera and puts you under the menu.
const SIZE := Vector2i(96, 44)
const MEADOW := Rect2i(2, 2, 56, 40)
const LABYRINTH_AT := Vector2i(60, 13)
const LABYRINTH_CELLS := Vector2i(7, 5)
const LABYRINTH_MOUTH := 2
const LABYRINTH_SEED := 1

## The road south from the town gate, then east to the labyrinth. Three wide,
## because the pack draws a road's edge inside the road.
const TOWN_GATE := Rect2i(23, 0, 3, 2)
const ROAD_SOUTH := Rect2i(23, 0, 3, 26)
const ROAD_EAST := Rect2i(26, 23, 32, 3)

## Stands of trees in the meadow, 2x2 each, and the pond.
const GROVES: Array[Vector2i] = [
	Vector2i(9, 6), Vector2i(13, 9), Vector2i(6, 16), Vector2i(17, 19),
	Vector2i(34, 8), Vector2i(41, 15), Vector2i(52, 11), Vector2i(44, 33),
	Vector2i(30, 36), Vector2i(20, 40), Vector2i(53, 27),
]
const POND := Rect2i(8, 28, 10, 7)

## Where the wisp idles and the meadow it leads you across to its shrine.
const WISP_FROM := Rect2i(27, 3, 9, 7)
const WISP_TO := Rect2i(4, 35, 12, 6)

const SPAWN_CELL := Vector2i(24, 2)

const NPCS := [
	{"at": Vector2i(30, 16), "name": "Scout", "display": "a nervous scout",
		"look": "CamouflageGreen", "flag": &"", "lines": [
			"You're heading further out? Watch the treeline.",
			"Frenzy Boars charge the moment you turn your back.",
			"The road east runs straight into the labyrinth. It's a maze in there, and dark.",
			"Illfang's door is somewhere inside. You won't see it till you're in its room.",
		]},
]

## The first sword anyone finds, in the open; and a big red chest by the pond
## that brings the boars down -- the first gilded chest, and the lesson that
## gilding means a gamble.
const CHESTS := [
	{"at": Vector2i(46, 10), "item": &"bronze_sword", "amount": 1, "flag": &"chest_field_north"},
	{"at": Vector2i(20, 30), "item": &"leather_coat", "amount": 1, "flag": &"chest_field_pond",
		"gilded": true, "trap": &"alarm"},
]
## Waiting at one of the labyrinth's dead ends.
const LABYRINTH_CHEST := {"item": &"health_potion", "amount": 2, "flag": &"chest_field_labyrinth"}

## Seven in the meadow and three in the maze: ten, two over
## [method FloorTuning.monster_count]'s eight, since ten kills is what puts a new
## player at the level Illfang is tuned for. Monster0 stays a boar in the open,
## and none stands where the wisp waits: the first puzzle is not a fight.
const MONSTERS := [
	[Vector2i(12, 5), &"frenzy_boar"],
	[Vector2i(18, 12), &"little_nepent"],
	[Vector2i(40, 5), &"frenzy_boar"],
	[Vector2i(6, 22), &"frenzy_boar"],
	[Vector2i(28, 18), &"little_nepent"],
	[Vector2i(38, 20), &"frenzy_boar"],
	[Vector2i(22, 33), &"frenzy_boar"],
]
const LABYRINTH_MONSTERS := [&"little_nepent", &"frenzy_boar", &"little_nepent"]


func _init() -> void:
	floor_number = FLOOR_NUMBER
	size = SIZE
	biome_path = BIOME_PATH
	out_path = OUT_PATH
	dress_seed = DRESS_SEED


func _build() -> Node2D:
	var map := _new_map("Field", &"field_f1", "West Field")

	_carve(MEADOW, _biome.floor_tile)
	_carve_gap(TOWN_GATE, _biome.path_tile)
	_pave(ROAD_SOUTH, _biome.path_tile)
	_pave(ROAD_EAST, _biome.path_tile)
	_grow_labyrinth(LABYRINTH_AT, LABYRINTH_CELLS, Side.EAST, LABYRINTH_MOUTH, LABYRINTH_SEED)
	_carve_path([Vector2i(ROAD_EAST.end.x - 1, _lab.doorstep.y + 1), _lab.doorstep + Vector2i(0, 1)])

	_block(POND, _biome.liquid_tile)
	for spot in GROVES:
		_block(Rect2i(spot, Vector2i(2, 2)), _biome.wall_tile)

	var chest_cells: Array[Vector2i] = []
	for entry in CHESTS:
		chest_cells.append(entry["at"])
	var keep_out: Array[Vector2i] = [SPAWN_CELL]
	for entry in NPCS:
		keep_out.append(entry["at"])
	_new_puzzles(chest_cells, keep_out)
	_pin(_puzzles.pin_wisp(WISP_FROM, WISP_TO), "the wisp")
	_join_walls()

	_add_spawns(map, {&"default": SPAWN_CELL, &"from_town": SPAWN_CELL})
	for entry in NPCS:
		_add_npc(map, entry)
	for index in CHESTS.size():
		_add_chest(map, index, CHESTS[index])
	for index in MONSTERS.size():
		_add_monster(map, index, MONSTERS[index][0], MONSTERS[index][1])
	_add_exit(map, "ExitToFromField", Vector2i(24, 0), TOWN_PATH, &"from_field", "Go to",
			"the Town of Beginnings", Vector2(2, 1), true)
	_add_labyrinth(map, "the Labyrinth", LABYRINTH_MONSTERS, MONSTERS.size(), LABYRINTH_CHEST,
			CHESTS.size())
	_place_puzzles(map)
	_add_boss_gate(map, Vector2i.ZERO, "Illfang the Kobold Lord", "the labyrinth door")
	_add_player(map, SPAWN_CELL)
	return map
