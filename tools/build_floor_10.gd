extends "res://tools/authored_floor.gd"
## Builds Floor 10 -- Ashlow Wood -- the second authored floor.
##
##     "$GODOT" --headless --path . --script res://tools/build_floor_10.gd
##     "$GODOT" --headless --path . --script res://tools/build_floor_10.gd -- --preview
##
## This file is the layout; everything that isn't Ashlow -- painting, joining,
## placing, checking, saving -- is in tools/authored_floor.gd. The output is an
## ordinary scene; open it in the editor and paint over it if you like, but then
## stop running this, because it overwrites.
##
## [b]One map, not two.[/b] Floor 1 splits its town and its field across a
## MapExit, which is fine there because the boss is a one-way trip you take once.
## Floor 10 has a quest that sends you to the boss and then back to the village to
## report, so the walk home has to exist -- and a single map is the version of that
## walk which costs no fade, no second scene and no second set of spawn points.
##
## What is authored here is the *layout*: a village the generator has no concept
## of, three glades, and a hollow at the end.

const BIOME_PATH := "res://resources/biomes/forest.tres"
const OUT_PATH := "res://scenes/world/floor_10.tscn"

const FLOOR_NUMBER := 10
const CORRIDOR_WIDTH := 3

const SIZE := Vector2i(78, 58)

# --- regions, in tiles -----------------------------------------------------
#
# Ashlow sits in the north-west, the three glades run diagonally across the
# middle, and the hollow with the labyrinth door is as far from the stairs as the
# map gets. Corridors join them in a loop rather than a chain, so a player who
# does not want to fight their way back the way they came doesn't have to.

const VILLAGE := Rect2i(3, 3, 26, 20)
const GLADE_A := Rect2i(36, 5, 12, 9)
const GLADE_B := Rect2i(33, 24, 13, 10)
const GLADE_C := Rect2i(14, 34, 14, 10)
const HOLLOW := Rect2i(56, 38, 16, 13)

## Where the cut paths leave Ashlow. Taken from the village edge rather than its
## centre, so a corridor can never carve a street through a building.
const GATE_EAST := Vector2i(29, 12)
const GATE_SOUTH := Vector2i(15, 23)

const CORRIDORS := [
	[GATE_EAST, Vector2i(42, 9)],
	[Vector2i(42, 9), Vector2i(39, 28)],
	[GATE_SOUTH, Vector2i(21, 39)],
	[Vector2i(21, 39), Vector2i(39, 28)],
	[Vector2i(39, 28), Vector2i(58, 44)],
]

const SPAWN_CELL := Vector2i(16, 20)
const STAIRS_CELL := Vector2i(12, 20)
const GATE_CELL := Vector2i(67, 44)

## Four roofs, see [method _house].
const BUILDINGS := [
	Rect2i(5, 5, 6, 4),
	Rect2i(20, 5, 7, 4),
	Rect2i(5, 16, 6, 4),
	Rect2i(21, 16, 6, 4),
]

const NPCS := [
	{"at": Vector2i(12, 10), "name": "Rue", "display": "Rue the forester",
		"flag": &"met_rue", "dialogue": "res://resources/dialogue/rue.tres"},
	{"at": Vector2i(20, 15), "name": "Sable", "display": "Sable the cartographer",
		"flag": &"met_sable", "dialogue": "res://resources/dialogue/sable.tres"},
	{"at": Vector2i(8, 14), "name": "Logger", "display": "a logger", "flag": &"",
		"lines": [
			"Nine floors up and the trees still win.",
			"Rue says four wolves. Rue has said four wolves since spring.",
		]},
	{"at": Vector2i(24, 10), "name": "Runner", "display": "a courier", "flag": &"",
		"lines": [
			"I carry mail down to Floor Nine and back. Twice a week, when the path holds.",
			"Last month it stopped holding. The wood grew over the road overnight.",
		]},
]

const CHESTS := [
	{"at": Vector2i(39, 8), "item": &"health_potion", "amount": 2,
		"flag": &"chest_ashlow_glade_north"},
	{"at": Vector2i(36, 26), "item": &"swift_charm", "amount": 1,
		"flag": &"chest_ashlow_glade_deep"},
	{"at": Vector2i(18, 37), "item": &"whetstone", "amount": 2,
		"flag": &"chest_ashlow_glade_south"},
]

## Nine, which is [method FloorTuning.monster_count] for this floor -- authored
## does not mean exempt from the curve, it means the placement is chosen. Six of
## them are wolves because "Past the Tree Line" asks for four.
const MONSTERS := [
	[Vector2i(38, 6), &"dire_wolf"],
	[Vector2i(44, 6), &"dire_wolf"],
	[Vector2i(45, 11), &"little_nepent"],
	[Vector2i(35, 26), &"dire_wolf"],
	[Vector2i(43, 31), &"dire_wolf"],
	[Vector2i(37, 32), &"little_nepent"],
	[Vector2i(16, 36), &"dire_wolf"],
	[Vector2i(22, 42), &"dire_wolf"],
	[Vector2i(25, 41), &"little_nepent"],
]

## Boulders and standing water, placed rather than scattered. Every one is at
## least two tiles inside its glade and clear of the corridor mouths; the
## completability check is what actually holds that to it.
const BOULDERS := [
	Vector2i(40, 12), Vector2i(46, 7), Vector2i(41, 26),
	Vector2i(19, 36), Vector2i(24, 38), Vector2i(60, 41), Vector2i(69, 48),
]
const POOL := Rect2i(35, 29, 3, 2)


func _init() -> void:
	floor_number = FLOOR_NUMBER
	size = SIZE
	biome_path = BIOME_PATH
	out_path = OUT_PATH


func _build() -> Node2D:
	var map := _new_map("Floor10", &"floor_10", "Floor 10 - Ashlow Wood")

	_carve_village()
	for glade in [GLADE_A, GLADE_B, GLADE_C]:
		_carve(glade, _biome.floor_tile)
	_carve(HOLLOW, _biome.special_tile)
	for run in CORRIDORS:
		_carve_corridor(run[0], run[1], CORRIDOR_WIDTH)

	_decorate()
	_join_walls()

	# All three land on the village square: you arrive in Ashlow whether you came
	# up the stairs, back down them, or woke up here after losing to the Warden.
	_add_spawns(map, {
		&"default": SPAWN_CELL, &"from_below": SPAWN_CELL, &"from_above": SPAWN_CELL,
	})
	_add_stairs(map, STAIRS_CELL)
	for entry in NPCS:
		_add_npc(map, entry)
	for index in CHESTS.size():
		_add_chest(map, index, CHESTS[index])
	for index in MONSTERS.size():
		_add_monster(map, index, MONSTERS[index][0], MONSTERS[index][1])
	_add_boss_gate(map, GATE_CELL, "Nerith the Hollow Warden", "the hollow door")
	_add_player(map, SPAWN_CELL)
	return map


## Ashlow: two streets crossing at a stone square, four roofs, and floor
## everywhere else. Carved as one rectangle first so the buildings are put *back*
## rather than left standing -- a building is a thing inside the village, not a
## piece of the wood the village failed to clear.
func _carve_village() -> void:
	_carve(VILLAGE, _biome.floor_tile)
	_fill(_ground, Rect2i(VILLAGE.position.x, 12, VILLAGE.size.x, 2), _biome.path_tile)
	_fill(_ground, Rect2i(15, VILLAGE.position.y, 2, VILLAGE.size.y), _biome.path_tile)
	_fill(_ground, Rect2i(14, 11, 5, 5), _biome.special_tile)
	for building in BUILDINGS:
		_house(building)


func _decorate() -> void:
	for cell in BOULDERS:
		_block(Rect2i(cell, Vector2i.ONE), _biome.obstacle_tile)
	_block(POOL, _biome.liquid_tile)
