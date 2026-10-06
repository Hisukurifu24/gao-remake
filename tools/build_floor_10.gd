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
## of, four glades, the Hollow's edge -- and the Hollow itself, the floor's
## labyrinth, grown by the generator's own maze code from a seed fixed here, so
## the door is found the way a generated floor's is: from inside its room.

const BIOME_PATH := "res://resources/biomes/forest.tres"
const OUT_PATH := "res://scenes/world/floor_10.tscn"

const FLOOR_NUMBER := 10
const CORRIDOR_WIDTH := 3

## Six columns of wood east of the Hollow, so the Warden's fight -- framed at x1,
## ten tiles either side -- is never pinned against the map's edge.
const SIZE := Vector2i(122, 58)

# --- regions, in tiles -----------------------------------------------------
#
# Ashlow sits in the north-west, the three glades run diagonally across the
# middle, a fourth hides off the north one, and the Hollow -- the labyrinth -- is
# east of everything, past a clearing at its edge. Corridors join the glades in a
# loop rather than a chain, so a player who does not want to fight their way back
# the way they came doesn't have to.

const VILLAGE := Rect2i(3, 3, 26, 20)
const GLADE_A := Rect2i(36, 5, 12, 9)
const GLADE_B := Rect2i(33, 24, 13, 10)
const GLADE_C := Rect2i(14, 34, 14, 10)
## Off the north glade, behind a bend: the braziers' ring, and the vault.
const GLADE_D := Rect2i(58, 12, 13, 9)
## The clearing at the Hollow's edge, where the wisp's shrine stands.
const EDGE := Rect2i(56, 38, 14, 11)

## The Hollow: 10x7 cells of maze (42x30 tiles) east of the edge, its mouth on its
## west wall level with the clearing. Seed fixed, so the maze is the same every
## build; a seed that grows no safe zone is refused by the builder.
const HOLLOW_AT := Vector2i(74, 24)
const HOLLOW_CELLS := Vector2i(10, 7)
const HOLLOW_MOUTH := 4
const HOLLOW_SEED := 10

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
## The way round to the fourth glade, bending so it isn't seen from the north one.
const TO_GLADE_D := [Vector2i(46, 10), Vector2i(52, 10), Vector2i(52, 16), Vector2i(59, 16)]

## The teleport gate, on the square's north-east corner, clear of both streets.
const TELEPORT_CELL := Vector2i(18, 10)
const TELEPORT_ARRIVAL := Vector2i(18, 11)
const SPAWN_CELL := Vector2i(16, 20)
const STAIRS_CELL := Vector2i(12, 20)

## Six buildings as [rect, house], see [method _house]. The forest biome's houses
## are 0 an A-frame (4x5), 1 a log house (4x4), 2 a corner house (3x3), 3 a shed
## (3x3), and each rect is exactly its house's size.
const BUILDINGS := [
	[Rect2i(6, 4, 4, 5), 0],
	[Rect2i(20, 5, 4, 4), 1],
	[Rect2i(25, 6, 3, 3), 2],
	[Rect2i(5, 16, 3, 3), 2],
	[Rect2i(9, 17, 3, 3), 3],
	[Rect2i(22, 15, 4, 5), 0],
]

## Three wide, because the pack draws a road's edge inside the road: two wide
## reads as one.
const STREET_EAST_WEST := Rect2i(3, 11, 26, 3)
const STREET_NORTH_SOUTH := Rect2i(14, 3, 3, 20)
const SQUARE := Rect2i(12, 9, 7, 7)

const NPCS := [
	{"at": Vector2i(12, 10), "name": "Rue", "display": "Rue the forester", "look": "ManGreen",
		"flag": &"met_rue", "dialogue": "res://resources/dialogue/rue.tres"},
	{"at": Vector2i(20, 15), "name": "Sable", "display": "Sable the cartographer",
		"look": "Inspector", "flag": &"met_sable", "dialogue": "res://resources/dialogue/sable.tres"},
	{"at": Vector2i(8, 14), "name": "Logger", "display": "a logger", "look": "Villager",
		"flag": &"", "lines": [
			"Nine floors up and the trees still win.",
			"Rue says four wolves. Rue has said four wolves since spring.",
		]},
	{"at": Vector2i(24, 10), "name": "Runner", "display": "a courier", "look": "Villager4",
		"flag": &"", "lines": [
			"I carry mail down to Floor Nine and back. Twice a week, when the path holds.",
			"Last month it stopped holding. The wood grew over the road overnight.",
		]},
]

## The deep glade's charm sits in a gilded chest that throws you into the Hollow,
## and the one at its edge brings the wolves down: the edge is where the wood
## starts fighting back.
const CHESTS := [
	{"at": Vector2i(39, 8), "item": &"health_potion", "amount": 2,
		"flag": &"chest_ashlow_glade_north"},
	{"at": Vector2i(36, 26), "item": &"swift_charm", "amount": 1,
		"flag": &"chest_ashlow_glade_deep", "gilded": true, "trap": &"teleport"},
	{"at": Vector2i(18, 37), "item": &"whetstone", "amount": 2,
		"flag": &"chest_ashlow_glade_south"},
	{"at": Vector2i(66, 46), "item": &"guard_ring", "amount": 1,
		"flag": &"chest_ashlow_edge", "gilded": true, "trap": &"alarm"},
]
## Waiting at one of the Hollow's dead ends.
const HOLLOW_CHEST := {"item": &"health_potion", "amount": 3, "flag": &"chest_ashlow_hollow"}

## Nine in the glades, which is [method FloorTuning.monster_count] for this floor --
## authored does not mean exempt from the curve, it means the placement is chosen
## -- and [constant HOLLOW_MONSTERS] more in the maze. Most are wolves because "Past
## the Tree Line" asks for four.
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
## Walking the Hollow's passages, placed by its seed.
const HOLLOW_MONSTERS := [&"dire_wolf", &"little_nepent", &"dire_wolf"]

## Boulders and standing water, placed rather than scattered. Every one is at
## least two tiles inside its glade and clear of the corridor mouths; the
## completability check is what actually holds that to it.
const BOULDERS := [
	Vector2i(40, 12), Vector2i(46, 7), Vector2i(41, 26),
	Vector2i(19, 36), Vector2i(24, 38), Vector2i(59, 41),
]
const POOL := Rect2i(35, 29, 3, 2)

## Named places, for the map screen. The glades go unnamed: Ashlow's people
## don't go into them. The Hollow is named by [method _add_labyrinth].
const LANDMARKS := {
	"Ashlow": VILLAGE,
}


func _init() -> void:
	floor_number = FLOOR_NUMBER
	size = SIZE
	biome_path = BIOME_PATH
	out_path = OUT_PATH


func _build() -> Node2D:
	var map := _new_map("Floor10", &"floor_10", "Floor 10 - Ashlow Wood")
	_name_places(map, LANDMARKS)

	_carve_village()
	for glade in [GLADE_A, GLADE_B, GLADE_C, GLADE_D, EDGE]:
		_carve(glade, _biome.floor_tile)
	for run in CORRIDORS:
		_carve_corridor(run[0], run[1], CORRIDOR_WIDTH)
	_carve_path(TO_GLADE_D, CORRIDOR_WIDTH)
	_grow_labyrinth(HOLLOW_AT, HOLLOW_CELLS, Side.EAST, HOLLOW_MOUTH, HOLLOW_SEED)
	_carve_path([EDGE.end - Vector2i(3, 6), _lab.doorstep], CORRIDOR_WIDTH)

	_decorate()
	# The puzzles, chosen: a wisp from the south glade to the Hollow's edge (it
	# knows the way in), a ring of four fires in the hidden glade with a vault off
	# its north side, and a split boulder in the south glade's treeline.
	var chest_cells: Array[Vector2i] = []
	for entry in CHESTS:
		chest_cells.append(entry["at"])
	var keep_out: Array[Vector2i] = [SPAWN_CELL, STAIRS_CELL, TELEPORT_CELL]
	for entry in NPCS:
		keep_out.append(entry["at"])
	_new_puzzles(chest_cells, keep_out)
	_pin(_puzzles.pin_wisp(GLADE_C, EDGE), "the wisp")
	_pin(_puzzles.pin_rite(GLADE_D, Rite.ORDERED, 4), "the braziers")
	_pin(_puzzles.pin_vault(GLADE_D, Vector2i.UP), "the vault")
	_pin(_puzzles.pin_crack(GLADE_C, Vector2i.LEFT), "the cracked boulder")
	_join_walls()

	# All three land on the village square: you arrive in Ashlow whether you came
	# up the stairs, back down them, or woke up here after losing to the Warden.
	_add_spawns(map, {
		&"default": SPAWN_CELL, &"from_below": SPAWN_CELL, &"from_above": SPAWN_CELL,
		&"gate": TELEPORT_ARRIVAL,
	})
	_add_stairs(map, STAIRS_CELL)
	_add_teleport_gate(map, TELEPORT_CELL)
	for entry in NPCS:
		_add_npc(map, entry)
	for index in CHESTS.size():
		_add_chest(map, index, CHESTS[index])
	for index in MONSTERS.size():
		_add_monster(map, index, MONSTERS[index][0], MONSTERS[index][1])
	_add_labyrinth(map, "the Hollow", HOLLOW_MONSTERS, MONSTERS.size(), HOLLOW_CHEST, CHESTS.size())
	_place_puzzles(map)
	_add_boss_gate(map, Vector2i.ZERO, "Nerith the Hollow Warden", "the hollow door")
	_add_player(map, SPAWN_CELL)
	return map


## Ashlow: two streets crossing at a trodden square, six buildings, and lawn
## everywhere else. Carved as one rectangle first so the buildings are put *back*
## rather than left standing -- a building is a thing inside the village, not a
## piece of the wood the village failed to clear.
func _carve_village() -> void:
	_carve(VILLAGE, _biome.floor_tile)
	_fill(_ground, STREET_EAST_WEST, _biome.path_tile)
	_fill(_ground, STREET_NORTH_SOUTH, _biome.path_tile)
	_fill(_ground, SQUARE, _biome.special_tile)
	for building: Array in BUILDINGS:
		_house(building[0], building[1])


func _decorate() -> void:
	for cell in BOULDERS:
		_block(Rect2i(cell, Vector2i.ONE), _biome.obstacle_tile)
	_block(POOL, _biome.liquid_tile)
