extends "res://tools/authored_floor.gd"
## Builds Floor 40 -- Brackwater -- the fourth authored floor.
##
##     "$GODOT" --headless --path . --script res://tools/build_floor_40.gd
##     "$GODOT" --headless --path . --script res://tools/build_floor_40.gd -- --preview
##
## A fen, and in the middle of it the one island that doesn't move: Brackwater, a
## village of stilt huts round a landing with a stone frog on it. Earth causeways
## run out from it over the open bog to four islands -- the peat cuttings, the
## reedbeds, a drowned chapel and a heronry -- and a fifth runs south to the
## Sinkmouth, where the labyrinth is. Like the other floor tools this file is the
## layout; the plumbing is in tools/authored_floor.gd, and it overwrites.
##
## [b]A hub, where Ashlow is a loop and Lanternfall a chain.[/b] Every causeway
## starts in the village and ends at its island, so every trip out is a trip back
## through Brackwater -- past the chandler, past the reeve -- and the quests that
## send you somewhere send you home the same way. No causeway joins another.
##
## [b]The bog is open water, and you can see across it.[/b] Fog of war sees over
## water, so from the village the islands are in view long before they are in
## reach; the causeways jog rather than run straight, so the way to what you can
## see is never quite the line to it. Every rock cell inside [constant FEN] that
## nothing carved is turned to bog ([method _flood_fen]) -- except the
## [constant THICKETS], wooded hummocks left standing in it, and the houses.
##
## [b]Islands against the treeline.[/b] The fen is an ellipse inside the map, and
## the islands that need a wall of rock behind them -- the cracked boulder in the
## peat cuttings, the chapel's sealed vault -- stand at its edge, half in the bog
## and half in the forest, so what a puzzle carves into is wood and not water.

const BIOME_PATH := "res://resources/biomes/swamp.tres"
const OUT_PATH := "res://scenes/world/floor_40.tscn"

const FLOOR_NUMBER := 40
const BOSS_NAME := "Gulmaw the Mire Sovereign"

## Room enough below the labyrinth that Gulmaw's fight, framed at x1, is never
## pinned against the map's bottom edge.
const SIZE := Vector2i(120, 98)
const CAUSEWAY_WIDTH := 3

# --- the fen, in tiles -------------------------------------------------------

## The bog: the ellipse inscribed in this, its edge wobbled, is water wherever
## nothing was carved. Everything outside it is forest.
const FEN := Rect2i(14, 2, 96, 56)
const FEN_WOBBLE := 0.10
## Wooded hummocks in the bog, left as forest rather than flooded.
const THICKETS := [
	Rect2i(23, 38, 11, 8),
	Rect2i(64, 4, 10, 7),
	Rect2i(36, 44, 8, 6),
	Rect2i(84, 26, 6, 5),
]

## Brackwater: the island the fen doesn't move, banked square with peat by people
## who wanted one thing in the fen to stay where it was put.
const VILLAGE := Rect2i(46, 15, 28, 21)
## Three wide, because the pack draws a road's edge inside the road: two reads as one.
const STREET_EAST_WEST := Rect2i(46, 24, 28, 3)
const STREET_NORTH_SOUTH := Rect2i(58, 15, 3, 21)
## The landing, where the streets cross and the frog sits.
const LANDING := Rect2i(56, 22, 7, 7)

## Cut peat banks are square, so the cuttings are a rect; the west end stands in
## the forest, which is where the cracked boulder is. The cut strips are bared
## earth, three wide so they read as more than a path.
const PEAT := Rect2i(9, 21, 19, 12)
const PEAT_CUTS := [Rect2i(12, 22, 13, 3), Rect2i(12, 27, 13, 3)]
const REEDBEDS := Rect2i(26, 4, 20, 11)
## Flagstones in the bog -- a ruin older than the village -- with the statues on
## them and a vault behind the east wall, in the wood.
const CHAPEL := Rect2i(92, 11, 16, 14)
const HERON := Rect2i(86, 35, 14, 11)
## The south shore, where the fen drains down into the labyrinth.
const SINKMOUTH := Rect2i(47, 47, 26, 9)

## The labyrinth -- the Undermire -- 13x8 cells (54x34 tiles) under the
## Sinkmouth, its mouth in its north wall.
const LABYRINTH_AT := Vector2i(33, 60)
const LABYRINTH_CELLS := Vector2i(13, 8)
const LABYRINTH_MOUTH := 6
const LABYRINTH_SEED := 40
## Down from the Sinkmouth's floor to the maze's mouth.
const INTO_LABYRINTH := Vector2i(60, 53)

## Each causeway, village to island, as waypoints joined by straight legs. None
## touches another: that is the hub.
const CAUSEWAYS := [
	# West, to the peat cuttings.
	[Vector2i(47, 25), Vector2i(39, 25), Vector2i(39, 29), Vector2i(26, 29)],
	# North, to the reedbeds.
	[Vector2i(59, 16), Vector2i(59, 9), Vector2i(50, 9), Vector2i(50, 7), Vector2i(43, 7)],
	# East, to the drowned chapel.
	[Vector2i(72, 25), Vector2i(80, 25), Vector2i(80, 18), Vector2i(93, 18)],
	# South-east, to the heronry.
	[Vector2i(72, 32), Vector2i(78, 32), Vector2i(78, 41), Vector2i(87, 41)],
	# South, to the Sinkmouth.
	[Vector2i(59, 34), Vector2i(59, 41), Vector2i(55, 41), Vector2i(55, 48)],
]

## Where the puzzles go. A wisp in the reedbeds that knows the way through the fen
## to a shrine on the heronry -- the long way, through the village; four statues on
## the chapel's flagstones with a vault behind its east wall; and a cracked boulder
## in the peat cuttings' treeline.
const WISP_FROM := Rect2i(29, 6, 14, 7)
const WISP_TO := Rect2i(88, 37, 10, 7)
const RING_ROOM := Rect2i(93, 12, 14, 12)
const VAULT_ROOM := CHAPEL
const CRACK_ROOM := PEAT

## Named places, for the map screen. The labyrinth is named by [method _add_labyrinth].
const LANDMARKS := {
	"Brackwater": VILLAGE,
	"the Peat Cuttings": PEAT,
	"the Reedbeds": REEDBEDS,
	"the Drowned Chapel": CHAPEL,
	"Heron Isle": HERON,
	"the Sinkmouth": SINKMOUTH,
}

const STAIRS_CELL := Vector2i(56, 33)
const SPAWN_CELL := Vector2i(56, 31)
## The teleport gate, on the street east of the landing; its base is three wide,
## and the street is three deep below it.
const TELEPORT_CELL := Vector2i(64, 23)
const TELEPORT_ARRIVAL := Vector2i(64, 24)

## Buildings as [rect, house], see [method _house]. The swamp's houses are 0 a
## stilt hut (3x5), 1 a mossy cabin (3x3), 2 an A-frame (4x5), 3 the reeve's hall
## (4x5) and 4 the frog idol (2x2), and each rect is exactly its house's size.
const BUILDINGS := [
	[Rect2i(48, 17, 4, 5), 2],
	[Rect2i(53, 17, 3, 5), 0],
	[Rect2i(66, 17, 4, 5), 3],
	[Rect2i(62, 19, 2, 2), 4],
	[Rect2i(48, 29, 3, 5), 0],
	[Rect2i(53, 29, 3, 3), 1],
	[Rect2i(63, 28, 3, 3), 1],
	[Rect2i(68, 29, 3, 5), 0],
]

const NPCS := [
	{"at": Vector2i(54, 22), "name": "Isolde", "display": "Isolde the net-mender",
		"look": "Village6", "flag": &"met_isolde", "dialogue": "res://resources/dialogue/isolde.tres"},
	{"at": Vector2i(68, 22), "name": "Oskar", "display": "Oskar the reeve", "look": "OldMan2",
		"flag": &"met_oskar", "dialogue": "res://resources/dialogue/oskar.tres"},
	{"at": Vector2i(64, 31), "name": "Pell", "display": "Pell the chandler", "look": "Villager5",
		"flag": &"", "shop": "brackwater_chandler"},
	{"at": Vector2i(72, 28), "name": "Fisher", "display": "an eel-fisher", "look": "Hunter",
		"flag": &"", "lines": [
			"Eels don't care how high the water is. Eels are the only thing in Brackwater that's happy.",
			"Don't swim. Not because of the eels. Because of what the eels are keeping away from.",
		]},
	{"at": Vector2i(47, 27), "name": "PeatCutter", "display": "a peat-cutter", "look": "Monk2",
		"flag": &"", "lines": [
			"The cuttings are west, over the causeway. Lizardmen took them a week back. We'd been cutting there forty years.",
			"Before the village there was the frog. Before the frog there was Gulmaw. Nobody says what was before Gulmaw.",
		]},
]

## Four on the islands, two of them gilded: the heronry's, out where the wisp goes,
## drops you into the Undermire, and the one at the Sinkmouth calls up what the
## drain lets through.
const CHESTS := [
	{"at": Vector2i(34, 6), "item": &"health_potion", "amount": 3,
		"flag": &"chest_brackwater_reedbeds"},
	{"at": Vector2i(19, 31), "item": &"whetstone", "amount": 3,
		"flag": &"chest_brackwater_peat"},
	{"at": Vector2i(105, 13), "item": &"antidote", "amount": 3,
		"flag": &"chest_brackwater_chapel"},
	{"at": Vector2i(96, 44), "item": &"lizardhide_vest", "amount": 1,
		"flag": &"chest_brackwater_heron", "gilded": true, "trap": &"teleport"},
	{"at": Vector2i(70, 49), "item": &"kingdom_signet", "amount": 1,
		"flag": &"chest_brackwater_sinkmouth", "gilded": true, "trap": &"alarm"},
]
## The Undermire's own, at one of its dead ends.
const LABYRINTH_CHEST := {"item": &"health_potion", "amount": 3,
	"flag": &"chest_brackwater_undermire"}

## Twelve, which is [method FloorTuning.monster_count] for this floor, half of them
## lizardmen because "The Fen Rising" asks for four -- out on the causeways they
## took, and on the islands at the far ends of them.
const MONSTERS := [
	[Vector2i(14, 24), &"little_nepent"],
	[Vector2i(23, 30), &"lizardman_soldier"],
	[Vector2i(39, 27), &"lizardman_soldier"],
	[Vector2i(32, 9), &"little_nepent"],
	[Vector2i(39, 11), &"little_nepent"],
	[Vector2i(54, 9), &"lizardman_soldier"],
	[Vector2i(97, 16), &"lizardman_soldier"],
	[Vector2i(102, 21), &"little_nepent"],
	[Vector2i(85, 18), &"lizardman_soldier"],
	[Vector2i(91, 40), &"little_nepent"],
	[Vector2i(51, 51), &"lizardman_soldier"],
	[Vector2i(66, 51), &"little_nepent"],
]
const LABYRINTH_MONSTERS := [&"lizardman_soldier", &"little_nepent", &"lizardman_soldier"]

## Reed stands on the islands, two tiles in from every edge and clear of the
## causeway mouths; the completability check is what actually holds that.
const REEDS := [
	Vector2i(13, 28), Vector2i(24, 23),
	Vector2i(30, 11), Vector2i(41, 6),
	Vector2i(95, 21), Vector2i(104, 17),
	Vector2i(89, 38), Vector2i(50, 49), Vector2i(68, 53),
]


func _init() -> void:
	floor_number = FLOOR_NUMBER
	size = SIZE
	biome_path = BIOME_PATH
	out_path = OUT_PATH


func _build() -> Node2D:
	var map := _new_map("Floor40", &"floor_40", "Floor 40 - Brackwater")
	_name_places(map, LANDMARKS)

	_carve_village()
	_carve(PEAT, _biome.floor_alt_tile)
	for cut: Rect2i in PEAT_CUTS:
		_pave(cut, _biome.path_tile)
	_carve_cave(REEDBEDS, _biome.floor_tile, 0.12, 4, 0.7)
	_carve(CHAPEL, _biome.special_tile)
	_carve_cave(HERON, _biome.floor_tile, 0.12, 3, 2.1)
	_carve_cave(SINKMOUTH, _biome.floor_tile, 0.10, 5, 1.3)
	for run in CAUSEWAYS:
		_carve_path(run, CAUSEWAY_WIDTH)
	_grow_labyrinth(LABYRINTH_AT, LABYRINTH_CELLS, Side.SOUTH, LABYRINTH_MOUTH, LABYRINTH_SEED)
	_carve_path([INTO_LABYRINTH, _lab.doorstep], CAUSEWAY_WIDTH)

	_flood_fen()
	for building: Array in BUILDINGS:
		_house(building[0], building[1])
	for cell in REEDS:
		_block(Rect2i(cell, Vector2i.ONE), _biome.obstacle_tile)

	var chest_cells: Array[Vector2i] = []
	for entry in CHESTS:
		chest_cells.append(entry["at"])
	var keep_out: Array[Vector2i] = [SPAWN_CELL, STAIRS_CELL, TELEPORT_CELL]
	for entry in NPCS:
		keep_out.append(entry["at"])
	_new_puzzles(chest_cells, keep_out)
	_pin(_puzzles.pin_wisp(WISP_FROM, WISP_TO), "the wisp")
	_pin(_puzzles.pin_statues(RING_ROOM), "the statues")
	_pin(_puzzles.pin_vault(VAULT_ROOM, Vector2i.RIGHT), "the vault")
	_pin(_puzzles.pin_crack(CRACK_ROOM, Vector2i.LEFT), "the cracked boulder")
	_join_walls()

	# Every arrival but the gate's lands by the stairs: up them, back down them,
	# or waking on the landing after losing to Gulmaw.
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
	_add_labyrinth(map, "the Undermire", LABYRINTH_MONSTERS, MONSTERS.size(), LABYRINTH_CHEST,
			CHESTS.size())
	_place_puzzles(map)
	_add_boss_gate(map, Vector2i.ZERO, BOSS_NAME, "the labyrinth door")
	_add_player(map, SPAWN_CELL)
	return map


## Brackwater: carved square, its corners taken back by the fen, two streets
## crossing at the landing. The houses go up after the fen is flooded, so it never
## mistakes a footprint for rock.
func _carve_village() -> void:
	_carve(VILLAGE, _biome.floor_tile)
	for corner in [VILLAGE.position, Vector2i(VILLAGE.end.x - 1, VILLAGE.position.y),
			Vector2i(VILLAGE.position.x, VILLAGE.end.y - 1), VILLAGE.end - Vector2i.ONE]:
		var inward := Vector2i(1 if corner.x == VILLAGE.position.x else -1,
				1 if corner.y == VILLAGE.position.y else -1)
		for dy in 3:
			for dx in 3 - dy:
				_close_cell(corner + Vector2i(dx * inward.x, dy * inward.y), _biome.wall_tile)
	_fill(_ground, STREET_EAST_WEST, _biome.path_tile)
	_fill(_ground, STREET_NORTH_SOUTH, _biome.path_tile)
	_fill(_ground, LANDING, _biome.special_tile)


## Turns every uncarved cell of the fen's ellipse to open bog, but for the
## thickets. Only the plain wall slot floods: a house footprint or a reed stand is
## something standing in the village, not rock. Water is painted over ground, as a
## pool carved and filled is, so the shore has grass under it to draw against.
func _flood_fen() -> void:
	var dry := {}
	for thicket: Rect2i in THICKETS:
		for cell in _ellipse(thicket, 0.15, 3, float(thicket.position.x)):
			dry[cell] = true
	for cell in _ellipse(FEN, FEN_WOBBLE, 5, 0.4):
		if _open.has(cell) or dry.has(cell):
			continue
		if _walls.get_cell_atlas_coords(cell) != Vector2i(_biome.wall_tile, 0):
			continue
		_paint(_ground, cell, _biome.floor_tile)
		_paint(_walls, cell, _biome.liquid_tile)
