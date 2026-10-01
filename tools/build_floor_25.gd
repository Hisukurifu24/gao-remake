extends "res://tools/authored_floor.gd"
## Builds Floor 25 -- Lanternfall -- the third authored floor.
##
##     "$GODOT" --headless --path . --script res://tools/build_floor_25.gd
##     "$GODOT" --headless --path . --script res://tools/build_floor_25.gd -- --preview
##
## A mining camp in a cavern at the top of the floor, and under it the workings
## the miners dug looking for iron: a chain of caverns, one below the next, ending
## at the labyrinth door they broke into by accident. Like build_floor_10.gd this
## file is only the layout; the plumbing is in tools/authored_floor.gd, and it
## overwrites its output.
##
## [b]A chain, where Ashlow is a loop.[/b] Ashlow's glades join in a ring so the
## walk home never retraces the walk out. Lanternfall is one way down -- camp,
## upper galleries, the lake cavern, the lower workings, the Breach -- with three
## dead-end galleries hanging off it. The dead ends are the point rather than the
## price: they are where a raid runs when it breaks, which is why the Army's tags
## are in them and not on the main line.
##
## [b]A lift is how a chain gets you home.[/b] The Breach is directly under the
## camp, and a lift runs up the shaft between them -- only up, because its
## counterweight is at the bottom, so it has to be reached the long way before it
## will carry anyone. It is a MapExit back into this same map, arriving at the
## camp's [code]from_lift[/code] spawn. The reload that implies brings the floor's
## monsters back, which is the fare: the short way up costs you the tunnels you
## cleared on the way down.
##
## [b]Caverns, not rooms.[/b] Everything is carved with [method _carve_cave] --
## wobbled ellipses rather than rectangles -- and joined by tunnels that jog
## instead of making one L. The main line is three tiles wide, the branches to the
## dead ends two, so a side passage reads as one before anyone walks down it.

const BIOME_PATH := "res://resources/biomes/cave.tres"
const OUT_PATH := "res://scenes/world/floor_25.tscn"

const FLOOR_NUMBER := 25
const BOSS_NAME := "Karvos the Twin-Headed"

const SIZE := Vector2i(80, 62)
const MAIN_WIDTH := 3
const BRANCH_WIDTH := 2

# --- caverns, in tiles -----------------------------------------------------
#
# Lanternfall is in the north-west. The workings run east along the top, down the
# east side, and back west along the bottom, so the Breach ends up under the camp
# with forty rows of rock between them -- the shape the lift exists to cut short.

const CAMP := Rect2i(2, 2, 30, 20)
const UPPER := Rect2i(42, 2, 24, 14)
const STILLWATER := Rect2i(44, 21, 32, 17)
const LOWER := Rect2i(44, 42, 30, 14)
const BREACH := Rect2i(4, 44, 24, 14)

## The three dead ends, one off each of the upper galleries, Stillwater and the
## tunnel into the Breach.
const GALLERIES := [
	Rect2i(69, 3, 9, 10),
	Rect2i(28, 24, 11, 9),
	Rect2i(28, 36, 11, 8),
]

## Stillwater's lake, set in the middle of the cavern so the way through splits
## round it. Blocked as an ellipse after the carve, like a boulder.
const LAKE := Rect2i(54, 27, 12, 6)

## Named places, for the map screen -- what the miners call them.
const LANDMARKS := {
	"Lanternfall": CAMP,
	"Upper galleries": UPPER,
	"Stillwater": STILLWATER,
	"Lower workings": LOWER,
	"the Breach": BREACH,
}

## The main line, top to bottom. Each run is waypoints joined by straight legs.
const MAIN_LINE := [
	[Vector2i(28, 12), Vector2i(36, 12), Vector2i(36, 7), Vector2i(46, 7)],
	[Vector2i(52, 13), Vector2i(52, 18), Vector2i(57, 18), Vector2i(57, 24)],
	[Vector2i(64, 35), Vector2i(64, 39), Vector2i(58, 39), Vector2i(58, 45)],
	[Vector2i(48, 49), Vector2i(40, 49), Vector2i(40, 53), Vector2i(30, 53),
		Vector2i(30, 50), Vector2i(22, 50)],
]

## Off the main line to each of [constant GALLERIES], in the same order.
const BRANCHES := [
	[Vector2i(62, 11), Vector2i(66, 11), Vector2i(66, 7), Vector2i(72, 7)],
	[Vector2i(47, 29), Vector2i(41, 29), Vector2i(41, 27), Vector2i(35, 27)],
	[Vector2i(36, 52), Vector2i(36, 47), Vector2i(33, 47), Vector2i(33, 41)],
]

const STAIRS_CELL := Vector2i(5, 12)
const SPAWN_CELL := Vector2i(9, 12)
const GATE_CELL := Vector2i(7, 51)

## The bottom of the shaft, in the Breach, and where it lets you off in the camp.
const LIFT_CELL := Vector2i(15, 46)
const LIFT_TOP := Vector2i(16, 17)
const LIFT_HEAD := Rect2i(15, 18, 4, 2)

## Three tents round the square as [rect, house], see [method _house]. The cave
## biome's houses are 0 and 1 two camp tents and 2 a torn one, all 3x3. The Army
## took the western tent when it came up and has worn it through, which is why
## Dorran is standing outside it.
const TENTS := [
	[Rect2i(10, 6, 3, 3), 2],
	[Rect2i(21, 6, 3, 3), 0],
	[Rect2i(22, 14, 3, 3), 1],
]

const NPCS := [
	{"at": Vector2i(11, 9), "name": "Dorran", "display": "Dorran of the Army", "look": "Knight",
		"flag": &"met_dorran", "dialogue": "res://resources/dialogue/dorran.tres"},
	{"at": Vector2i(22, 9), "name": "Maren", "display": "Maren the foreman", "look": "Villager2",
		"flag": &"met_maren", "dialogue": "res://resources/dialogue/maren.tres"},
	{"at": Vector2i(12, 15), "name": "Miner", "display": "a miner", "look": "Caveman2", "flag": &"",
		"lines": [
			"Two years digging for iron. Found a door instead. Nobody pays for doors.",
			"The bats are the worst of it. The kobolds at least have the decency to be afraid of lamps.",
		]},
	{"at": Vector2i(19, 18), "name": "LiftKeeper", "display": "the lift-keeper", "look": "OldMan",
		"flag": &"",
		"lines": [
			"She only runs up. The counterweight's at the bottom of the shaft, in the Breach.",
			"Somebody has to walk all the way down and let it go. After that it's a short ride home.",
		]},
]

## The three tags are the only chests the Army's job cares about, and the only
## things in the dead ends. The other three sit on the main line, where a player
## who never speaks to Dorran still walks past them.
const CHESTS := [
	{"at": Vector2i(74, 9), "item": &"raid_tag", "amount": 1,
		"flag": &"chest_lanternfall_tag_upper"},
	{"at": Vector2i(32, 28), "item": &"raid_tag", "amount": 1,
		"flag": &"chest_lanternfall_tag_lake"},
	{"at": Vector2i(32, 39), "item": &"raid_tag", "amount": 1,
		"flag": &"chest_lanternfall_tag_deep"},
	{"at": Vector2i(58, 5), "item": &"health_potion", "amount": 2,
		"flag": &"chest_lanternfall_upper"},
	{"at": Vector2i(68, 31), "item": &"antidote", "amount": 2,
		"flag": &"chest_lanternfall_lake"},
	{"at": Vector2i(68, 51), "item": &"whetstone", "amount": 2,
		"flag": &"chest_lanternfall_lower"},
]

## Ten, which is [method FloorTuning.monster_count] for this floor. Five are
## kobolds because "The Door Under the Camp" asks for four, and the last of them
## stands in the Breach, between the lift and the door.
const MONSTERS := [
	[Vector2i(48, 6), &"cave_bat"],
	[Vector2i(57, 11), &"kobold_trooper"],
	[Vector2i(60, 7), &"cave_bat"],
	[Vector2i(50, 26), &"cave_bat"],
	[Vector2i(52, 33), &"kobold_trooper"],
	[Vector2i(70, 27), &"cave_bat"],
	[Vector2i(52, 47), &"kobold_trooper"],
	[Vector2i(64, 52), &"kobold_trooper"],
	[Vector2i(69, 46), &"cave_bat"],
	[Vector2i(20, 53), &"kobold_trooper"],
]

## Stalagmites. None in the galleries -- a dead end is a small place and a
## boulder in one is a wall.
const BOULDERS := [
	Vector2i(50, 11), Vector2i(58, 13),
	Vector2i(49, 32), Vector2i(71, 32),
	Vector2i(56, 52), Vector2i(66, 45),
	Vector2i(12, 54), Vector2i(22, 47),
]


func _init() -> void:
	floor_number = FLOOR_NUMBER
	size = SIZE
	biome_path = BIOME_PATH
	out_path = OUT_PATH


func _build() -> Node2D:
	var map := _new_map("Floor25", &"floor_25", "Floor 25 - Lanternfall")
	_name_places(map, LANDMARKS)

	_carve_cave(CAMP, _biome.floor_tile, 0.10, 3, 0.0)
	_carve_cave(UPPER, _biome.floor_tile, 0.15, 4, 1.0)
	_carve_cave(STILLWATER, _biome.floor_tile, 0.12, 5, 2.0)
	_carve_cave(LOWER, _biome.floor_tile, 0.15, 3, 4.0)
	_carve_cave(BREACH, _biome.special_tile, 0.10, 2, 0.5)
	for gallery in GALLERIES:
		_carve_cave(gallery, _biome.floor_alt_tile, 0.10, 3, 1.5)
	for run in MAIN_LINE:
		_carve_path(run, MAIN_WIDTH)
	for run in BRANCHES:
		_carve_path(run, BRANCH_WIDTH)

	# After the tunnels, so a tunnel mouth can never carve through a hut.
	_furnish_camp()
	_decorate()
	_join_walls()

	# Every arrival but the lift lands on the camp's street: up the stairs, back
	# down them, or waking up here after losing to Karvos.
	_add_spawns(map, {
		&"default": SPAWN_CELL, &"from_below": SPAWN_CELL, &"from_above": SPAWN_CELL,
		&"from_lift": LIFT_TOP,
	})
	_add_stairs(map, STAIRS_CELL)
	for entry in NPCS:
		_add_npc(map, entry)
	for index in CHESTS.size():
		_add_chest(map, index, CHESTS[index])
	for index in MONSTERS.size():
		_add_monster(map, index, MONSTERS[index][0], MONSTERS[index][1])
	_add_exit(map, "LiftUp", LIFT_CELL, OUT_PATH, &"from_lift", "Ride",
			"the lift up to Lanternfall")
	_add_boss_gate(map, GATE_CELL, BOSS_NAME, "the Breach door")
	_add_player(map, SPAWN_CELL)
	return map


## A street across the cavern, one down the middle to the lift head, a lit square
## where they cross, and three tents. Paved rather than carved, so the streets stop
## where the cavern does.
func _furnish_camp() -> void:
	_pave(Rect2i(CAMP.position.x, 11, CAMP.size.x, 2), _biome.path_tile)
	_pave(Rect2i(16, CAMP.position.y, 2, CAMP.size.y), _biome.path_tile)
	_pave(Rect2i(14, 10, 6, 4), _biome.special_tile)
	_pave(LIFT_HEAD, _biome.special_tile)
	for tent in TENTS:
		_house(tent[0], tent[1])


func _decorate() -> void:
	_block_cells(_ellipse(LAKE), _biome.liquid_tile)
	for cell in BOULDERS:
		_block(Rect2i(cell, Vector2i.ONE), _biome.obstacle_tile)
