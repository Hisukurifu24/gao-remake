class_name FloorLandmarks
extends RefCounted
## A generated floor's landmark (plan.md, M6 "Floor variety"): one set piece that
## makes the floor a place rather than a layout -- remembered afterwards as "the one
## with the great tree". [method FloorRegistry.landmark_of] decides it per world, on a
## stream of its own; about half the floors that may have one do.
##
## - [b]LAKE[/b]: water filling a room, walked round on its shore, with a sign by it.
##   The band's own liquid: a frozen mere on the ice, lava on the volcanic floors.
## - [b]GREAT_TREE[/b]: one tree twice the size of anything in the treeline, alone
##   in a clearing -- a dead giant in the bog and the ash. Not underground, nor in
##   the Ruby Palace ([method kinds_for]).
## - [b]MONUMENT[/b]: a memorial the players put up, on a paved square, with the
##   names of the floor's dead cut into it.
## - [b]RUIN[/b]: a stone arch older than any player, rubble round it and a tablet
##   in the system's own script that knows the floor's boss.
##
## Every one is named on [b]M[/b], has something to read, is mentioned by someone in
## the camp, and about half keep a chest. It takes a field room nothing else has --
## no chest, no puzzle, no event, not the arrival, the camp or a safe zone -- and is
## the room's whole: its boulders and pools are cleared for it.
##
## Three passes. [method plan] before dressing, on the finished layout, decides the
## room and every cell; [method paint] after dressing lays it in with
## [method MapDresser.lay_into], which re-dresses only round it; [method place] once
## everything else is down puts up its pieces and its chest and steps any monster
## off it. Everything comes from its own stream ([code]hash("<seed>:landmarks")[/code]),
## never the floor's, and it is planned after everything else: a floor with its
## landmark is the floor without, plus the landmark, down to the flowers outside its
## room. [member FloorGenerator.landmark_override] forces a kind for the tests and tools.

enum Kind { NONE, LAKE, GREAT_TREE, MONUMENT, RUIN }
const KIND_NAMES: PackedStringArray = ["none", "lake", "great tree", "monument", "ruin"]

## The share of the floors that may have a landmark that do.
const CHANCE := 0.5
## The share of landmarks with a chest kept at them.
const CHEST_CHANCE := 0.5
const TILE := 16
## A lake fills its room but for a shore this wide all round -- a corridor's mouth
## lands on the shore, and the walk round is two abreast, as a maze's passages are.
const SHORE := 2
## The least water a lake is, in cells either way, before its corners are rounded.
const LAKE_LEAST := Vector2i(4, 3)

const NATURE := "res://assets/ninja_adventure/Backgrounds/Tilesets/TilesetNature.png"
const HOUSE := "res://assets/ninja_adventure/Backgrounds/Tilesets/TilesetHouse.png"
const ELEMENT := "res://assets/ninja_adventure/Backgrounds/Tilesets/TilesetElement.png"
const CHEST_SCENE := preload("res://scenes/world/chest.tscn")

## A great tree for each band that grows one: the pack's sheet region, drawn twice
## over, and the cells its trunk stands on within the cells it is drawn on.
const TREES := {
	&"meadow": [Rect2i(48, 288, 48, 48), Rect2i(2, 4, 2, 2)],
	&"forest": [Rect2i(48, 288, 48, 48), Rect2i(2, 4, 2, 2)],
	&"ruins": [Rect2i(48, 288, 48, 48), Rect2i(2, 4, 2, 2)],
	&"desert": [Rect2i(144, 288, 48, 48), Rect2i(2, 4, 2, 2)],
	&"ice": [Rect2i(96, 288, 48, 48), Rect2i(2, 4, 2, 2)],
	&"sky": [Rect2i(0, 288, 48, 48), Rect2i(2, 4, 2, 2)],
	&"swamp": [Rect2i(64, 0, 32, 32), Rect2i(0, 3, 4, 1)],
	&"volcanic": [Rect2i(64, 0, 32, 32), Rect2i(0, 3, 4, 1)],
}
## The memorial's statues, sandstone; the grey stone is the same a block below.
const STATUES: Array[Rect2i] = [Rect2i(48, 240, 32, 32), Rect2i(80, 240, 32, 32)]
const GREY := Vector2i(0, 64)
const SANDSTONE: Array[StringName] = [&"meadow", &"ruins", &"desert", &"volcanic"]
## What the statue stands on, within the 4x4 cells it is drawn on: its plinth.
const STATUE_BASE := Rect2i(0, 2, 4, 2)
const ARCH := Rect2i(464, 320, 48, 48)
const PILLAR := Rect2i(0, 240, 16, 48)
const BOULDERS: Array[Rect2i] = [Rect2i(272, 272, 16, 16), Rect2i(288, 272, 16, 16), Rect2i(304, 272, 16, 16)]
const STELE := Rect2i(64, 32, 16, 16)
const SIGN := Rect2i(96, 48, 16, 32)

## A ruin, laid out in an 8x6 box: the arch in the middle on its two legs, the
## tablet you read at its left foot, a broken pillar on its right, a boulder each
## side, and a chest, if any, left in the arch's mouth. Cells relative to the box.
const RUIN_BOX := Vector2i(8, 6)
const RUIN_ARCH := Rect2i(1, 0, 6, 6)
const RUIN_LEGS: Array[Rect2i] = [Rect2i(1, 4, 2, 2), Rect2i(5, 4, 2, 2)]
const RUIN_STELE := Vector2i(0, 5)
const RUIN_PILLAR := Rect2i(7, 3, 1, 3)
const RUIN_ROCKS: Array[Vector2i] = [Vector2i(0, 2), Vector2i(7, 1)]
const RUIN_CHEST := Vector2i(3, 5)

## What each is called on M, by band where the band changes it.
const NAMES := {
	Kind.LAKE: {
		&"meadow": ["Mirror Mere", "Heron Water"], &"forest": ["Blackwater", "the Sunken Pool"],
		&"cave": ["the Underlake", "the Still Pool"], &"ruins": ["the Drowned Court", "the Old Cistern"],
		&"swamp": ["the Black Mere", "Bog's Eye"], &"desert": ["the Oasis", "Sweetwater"],
		&"ice": ["the Frozen Mere", "Glass Lake"], &"volcanic": ["the Molten Mere", "the Fire Lake"],
		&"sky": ["the Sky Pool", "the Cloudwell"], &"castle": ["the Reflecting Pool", "the King's Basin"],
	},
	Kind.GREAT_TREE: {
		&"meadow": ["the Elder Oak", "the Old Father"], &"forest": ["the Grandfather Tree", "the Old Giant"],
		&"ruins": ["the Rootbound Tree", "the Throne Tree"], &"swamp": ["the Hanging Tree", "the Drowned Oak"],
		&"desert": ["the Amber Tree", "the Last Tree"], &"ice": ["the White Tree", "the Frost Oak"],
		&"volcanic": ["the Charred Tree", "the Ember Oak"], &"sky": ["the Blossom Tree", "the Cloud Tree"],
	},
	Kind.MONUMENT: ["the Memorial", "the Stone of the Fallen", "the Monument"],
	Kind.RUIN: ["the Broken Arch", "the Old Shrine", "the Fallen Gate"],
}
## What a lake's sign says under its name, by band where the band changes it.
const LAKE_NOTES := {
	&"": [
		"Underneath, in another hand: \"Fish bite at dusk. The big one is mine.\"",
		"Underneath, scratched in later: \"Deeper than it looks. Don't swim in your armour.\"",
		"Underneath: \"Water's clean. Fill your flasks -- it's the only thing on this floor that's free.\"",
	],
	&"ice": [
		"Underneath, scratched in later: \"The ice holds. Mostly.\"",
		"Underneath: \"Fished through a hole here for a week. Caught nothing. Worth it.\"",
	],
	&"volcanic": [
		"Underneath, in another hand: \"Don't.\" Someone has drawn a little sword falling in.",
		"Underneath: \"It is exactly as hot as it looks.\"",
	],
	&"swamp": [
		"Underneath, in another hand: \"Don't drink it. Don't touch it. Don't look at it too long.\"",
		"Underneath: \"Something lives in the middle. It has never come out. Let's keep it that way.\"",
	],
}
const TREE_LINES: PackedStringArray = [
	"Names are carved into the bark at head height: {party}. A party who swore to clear the floor together. Two of the names have been scratched through.",
	"Someone has hung a sword hilt-up from a low branch and left it there. The blade has gone to rust; nobody has taken it down.",
	"Its roots have broken the ground for yards round it. Under it the air is still, and smells like rain.",
]
const DEAD_TREE_LINES: PackedStringArray = [
	"Dead a long time, and still standing. Names are cut into the trunk: {party}. Two have been scratched through.",
	"Nothing grows on it now. Someone has tied a strip of cloth round the lowest branch -- a guild's colours, faded past knowing.",
]
const MEMORIAL_ENDS: PackedStringArray = [
	"Under the last, in a careful hand: \"We climb for you.\"",
	"There is room left at the bottom. Someone has cut a line under the last name, as if to say: no more.",
	"There are fresh flowers at its foot. Someone still comes.",
]
const TABLET_LINES: PackedStringArray = [
	"\"...let none stand before the {boss} who has not reached the {rank} rank.\"",
	"\"...the stair is kept by the {boss}. Bring light, and bring company.\"",
	"\"...here the old guard fell, and the {boss} took the stair.\"",
]
## What someone in the camp says about it, after their opening. {name} and {side}
## are filled in.
const CAMP_LINES := {
	Kind.LAKE: "There's water off to the {side} -- {name}, someone's sign calls it. Worth the walk, if only to look at.",
	Kind.GREAT_TREE: "Go and see {name} to the {side}, if you've the time. Oldest thing on the floor. Older than us, anyway.",
	Kind.MONUMENT: "Somebody's put up a memorial to the {side}. {name}. Go and read the names, if you can stand to.",
	Kind.RUIN: "There's a ruin off to the {side} -- {name}. The system's own work, older than anything else up here. There's writing on it nobody can make sense of.",
}
const CHEST_WORD := " Somebody left something there, they say."
## Players' handles, for a memorial's dead and the names in a tree's bark.
const HANDLES: PackedStringArray = [
	"Brannoc", "Ivy", "Takeshi", "Morrow", "Fenn", "Lio", "Sabre", "Quill", "Tolle", "Yuzu",
	"Grimm", "Pip", "Rhea", "Kestrel", "Oren", "Mako", "Thistle", "Dunmore", "Aiko", "Vance",
]

var kind := Kind.NONE
var floor_number := 0
## What it is called on M and in the camp.
var title := ""
## The room it takes, in tiles.
var room := Rect2i()
## Whether a chest is kept at it, and where.
var chest_cell := Vector2i(-1, -1)
## Cells it paints, by what: water, solid footprint (invisible), path.
var water: Array[Vector2i] = []
var solid: Array[Vector2i] = []
var paving: Array[Vector2i] = []
## The room's boulders and pools, cleared for it.
var cleared: Array[Vector2i] = []
## Where its readable piece stands, in tiles: the cells you read it from round.
var reading := Rect2i()
## Where its art stands, in tiles: the tree's, statue's or arch's cells (the lake's
## sign's for a lake).
var art := Rect2i()
## A variant drawn for it: which statue, which name, which lines.
var variant := 0

## The tablet's stone, weathered grey from the pack's sandstone once.
static var _grey_stele: Texture2D = null

var _rng := RandomNumberGenerator.new()
var _seed := 0
var _biome: BiomeKit
var _ground: TileMapLayer
var _walls: TileMapLayer
var _open: Dictionary[Vector2i, bool]
## The cells round a chest already in the room being tried: nothing of it goes there.
var _avoid: Dictionary[Vector2i, bool] = {}
## Cells that must stay floor: a wisp's way.
var _ways: Dictionary[Vector2i, bool] = {}


## [param open] is the generator's carved cells with decor taken out: read by
## [method plan], and brought up to date by [method place].
func _init(number: int, generation_seed: int, biome: BiomeKit, ground: TileMapLayer,
		walls: TileMapLayer, open: Dictionary[Vector2i, bool]) -> void:
	floor_number = number
	_seed = generation_seed
	_rng.seed = hash("%d:landmarks" % generation_seed)
	_biome = biome
	_ground = ground
	_walls = walls
	_open = open


## The kinds the band of [param biome_id] can draw: a great tree wants a sky over it.
static func kinds_for(biome_id: StringName) -> Array[int]:
	var kinds: Array[int] = [Kind.LAKE, Kind.MONUMENT, Kind.RUIN]
	if TREES.has(biome_id):
		kinds.insert(1, Kind.GREAT_TREE)
	return kinds


## The flag a landmark's chest keeps its state in.
static func chest_flag(number: int) -> StringName:
	return StringName("floor_%d_chest_landmark" % number)


## Decides where [param picked] stands -- or, if no room has the space for it,
## another kind the band draws -- among [param rooms]: never [param entry], a room
## touching [param plot] or in [param keep_out], nor one holding a puzzle's piece or
## anything in [param taken]. A room with one of the floor's [param chests] in it is
## a second choice, and the landmark keeps a cell clear round the chest. Nothing it
## stands goes on [param ways] -- a wisp's path -- which must stay floor.
## [param arrival] is where the floor is entered: nothing reachable from it before may
## be cut off after. Before dressing.
func plan(picked: Kind, rooms: Array[Rect2i], entry: Rect2i, arrival: Vector2i, plot: Rect2i,
		keep_out: Array[Rect2i], taken: Array[Vector2i], chests: Array[Vector2i],
		ways: Array[Vector2i]) -> void:
	for cell in ways:
		_ways[cell] = true
	var held: Dictionary[Vector2i, bool] = {}
	for cell in taken:
		held[cell] = true
	var empty: Array[Rect2i] = []
	var shared: Array[Rect2i] = []
	for each in rooms:
		if each == entry or each.grow(1).intersects(plot) or each in keep_out:
			continue
		var free := true
		for cell: Vector2i in held:
			if each.grow(1).has_point(cell):
				free = false
				break
		if not free:
			continue
		if chests.any(func(cell: Vector2i) -> bool: return each.grow(1).has_point(cell)):
			shared.append(each)
		else:
			empty.append(each)
	_shuffle(empty)
	_shuffle(shared)
	var candidates: Array[Rect2i] = empty + shared
	# A lake wants the biggest room going: in a small one it is a pond.
	var biggest := candidates.duplicate()
	biggest.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.get_area() > b.get_area())
	var kinds := kinds_for(_biome.id if _biome != null else &"")
	var order: Array[int] = [picked]
	for other in kinds:
		if other != picked:
			order.append(other)
	var reached := _reach(arrival, {})
	var lake_name := _rng.randi()
	var chest_roll := _rng.randf()
	variant = _rng.randi()
	for trying in order:
		for each in (biggest if trying == Kind.LAKE else candidates):
			_reset()
			_avoid.clear()
			for cell in chests:
				if each.grow(1).has_point(cell):
					for y in range(-1, 2):
						for x in range(-1, 2):
							_avoid[cell + Vector2i(x, y)] = true
			if _lay_out(trying as Kind, each) and _clear_of_chests() and _cuts_nothing(arrival, reached):
				kind = trying as Kind
				room = each
				title = _name(lake_name)
				if chest_roll >= CHEST_CHANCE:
					chest_cell = Vector2i(-1, -1)
				return
	_reset()


## Paints it in, once the map is dressed, and re-dresses round it.
func paint(map: Node2D) -> void:
	if kind == Kind.NONE:
		return
	var bare: Array[Vector2i] = []
	for y in range(art.position.y, art.end.y):
		for x in range(art.position.x, art.end.x):
			bare.append(Vector2i(x, y))
	if chest_cell.x >= 0:
		bare.append(chest_cell)
	MapDresser.lay_into(map, _biome, _ground, _walls, cleared, water, paving, solid, bare)


## Puts up its pieces, its chest and its name, once everything else is down; takes
## its cells out of the floor's open ground and steps any monster off them.
func place(map: Node2D, camp: Rect2i) -> void:
	if kind == Kind.NONE:
		return
	for cell in cleared:
		_open[cell] = true
	for cell in water + solid:
		_open.erase(cell)
	var landmark := Landmark.new()
	landmark.name = "Landmark"
	landmark.kind = kind
	match kind:
		Kind.LAKE:
			_build_lake(landmark)
		Kind.GREAT_TREE:
			_build_tree(landmark)
		Kind.MONUMENT:
			_build_monument(landmark)
		Kind.RUIN:
			_build_ruin(landmark)
	landmark.reach(reading)
	map.add_child(landmark)
	if chest_cell.x >= 0:
		var chest := CHEST_SCENE.instantiate() as Chest
		chest.name = "ChestLandmark"
		chest.position = _world(chest_cell)
		var gear := _rng.randf() < FloorGenerator.CHEST_GEAR_CHANCE
		chest.item_id = FloorGenerator.CHEST_GEAR[_rng.randi() % FloorGenerator.CHEST_GEAR.size()] \
				if gear else FloorGenerator.CHEST_CONSUMABLES[_rng.randi() % FloorGenerator.CHEST_CONSUMABLES.size()]
		chest.amount = 1 if gear else _rng.randi_range(1, 3)
		chest.floor_number = floor_number
		chest.opened_flag = chest_flag(floor_number)
		map.add_child(chest)
	_step_monsters_off(map)
	var places: Dictionary[String, Rect2i] = map.get(&"landmarks")
	places[_proper(title)] = room
	map.set(&"landmarks", places)
	map.set_meta(&"landmark", kind)
	map.set_meta(&"landmark_room", room)
	map.set_meta(&"landmark_cells", water + solid)
	if chest_cell.x >= 0:
		map.set_meta(&"landmark_chest", chest_cell)


## What someone in the camp says about it, filled in; empty for none.
func camp_line(plot: Rect2i) -> String:
	if kind == Kind.NONE:
		return ""
	var off := _center(room) - _center(plot)
	var side := ("east" if off.x > 0 else "west") if absi(off.x) >= absi(off.y) \
			else ("south" if off.y > 0 else "north")
	var line := (CAMP_LINES[kind] as String).format({"name": title, "side": side})
	return line + (CHEST_WORD if chest_cell.x >= 0 else "")


# --- laying it out --------------------------------------------------------------

func _reset() -> void:
	water.clear()
	solid.clear()
	paving.clear()
	cleared.clear()
	reading = Rect2i()
	art = Rect2i()
	chest_cell = Vector2i(-1, -1)


## Fits [param trying] into [param each], every cell decided; false if it won't go.
func _lay_out(trying: Kind, each: Rect2i) -> bool:
	for y in range(each.position.y, each.end.y):
		for x in range(each.position.x, each.end.x):
			var cell := Vector2i(x, y)
			if not _open.has(cell) and _walls.get_cell_source_id(cell) != -1:
				cleared.append(cell)
	match trying:
		Kind.LAKE:
			return _lay_lake(each)
		Kind.GREAT_TREE:
			var tree: Array = TREES[_biome.id]
			var size: Vector2i = (tree[0] as Rect2i).size * 2 / TILE
			return _lay_standing(each, size, tree[1], false)
		Kind.MONUMENT:
			return _lay_standing(each, Vector2i(4, 4), STATUE_BASE, true)
		Kind.RUIN:
			return _lay_ruin(each)
	return false


## Water over all but a [constant SHORE] round the room, its corners rounded off;
## the sign in one of the shore's top corners and a chest, if any, in the other --
## the top, since a forest's crowns hang over a room's bottom row.
func _lay_lake(each: Rect2i) -> bool:
	var pool := each.grow(-SHORE)
	if pool.size.x < LAKE_LEAST.x or pool.size.y < LAKE_LEAST.y:
		return false
	for y in range(pool.position.y, pool.end.y):
		for x in range(pool.position.x, pool.end.x):
			var corner := (x == pool.position.x or x == pool.end.x - 1) \
					and (y == pool.position.y or y == pool.end.y - 1)
			if not corner:
				water.append(Vector2i(x, y))
	var left := each.position
	var right := Vector2i(each.end.x - 1, each.position.y)
	var pairs: Array = [[left, right], [right, left]] if variant % 2 == 0 else [[right, left], [left, right]]
	pairs.append([Vector2i(left.x, each.end.y - 1), each.end - Vector2i.ONE])
	pairs.append([each.end - Vector2i.ONE, Vector2i(left.x, each.end.y - 1)])
	for pair: Array in pairs:
		var sign_cell: Vector2i = pair[0]
		var across: Vector2i = pair[1]
		if _open.has(sign_cell) and _open.has(across):
			solid.append(sign_cell)
			reading = Rect2i(sign_cell, Vector2i.ONE)
			art = reading
			chest_cell = across
			return true
	return false


## A tree or a statue standing on [param base] within the [param size] cells it is
## drawn on, as near the middle of the room as it will stand: drawn inside the room,
## its base with a cell of floor all round it. [param paved] lays a square of path
## round it too.
func _lay_standing(each: Rect2i, size: Vector2i, base: Rect2i, paved: bool) -> bool:
	var best := Rect2i()
	var best_off := INF
	for y in range(each.position.y, each.end.y - size.y + 1):
		for x in range(each.position.x, each.end.x - size.x + 1):
			var drawn := Rect2i(x, y, size.x, size.y)
			var foot := Rect2i(drawn.position + base.position, base.size)
			if not each.encloses(foot.grow(1)) or (paved and not each.encloses(drawn.grow(1))):
				continue
			if _touches(drawn.grow(1) if paved else drawn) or _touches(foot.grow(1)):
				continue
			var off := (Vector2(drawn.get_center()) - Vector2(each.get_center())).length()
			if off < best_off:
				best_off = off
				best = drawn
	if not best.has_area():
		return false
	art = best
	var foot := Rect2i(best.position + base.position, base.size)
	reading = foot
	for y in range(foot.position.y, foot.end.y):
		for x in range(foot.position.x, foot.end.x):
			solid.append(Vector2i(x, y))
	if paved:
		var square := best.grow(1)
		for y in range(square.position.y, square.end.y):
			for x in range(square.position.x, square.end.x):
				paving.append(Vector2i(x, y))
		chest_cell = Vector2i(foot.position.x + 1, foot.end.y)
	else:
		chest_cell = Vector2i(foot.position.x - 1, foot.end.y - 1)
	# Never on the room's bottom row, where a forest's crowns would hide it.
	if chest_cell.y >= each.end.y - 1:
		chest_cell = Vector2i(-1, -1)
	return true


## The arch, its tablet, its pillar and its boulders ([constant RUIN_BOX]), as near
## the middle as they stand with a cell of floor round the box.
func _lay_ruin(each: Rect2i) -> bool:
	var best := Rect2i()
	var best_off := INF
	for y in range(each.position.y + 1, each.end.y - RUIN_BOX.y):
		for x in range(each.position.x + 1, each.end.x - RUIN_BOX.x):
			var box := Rect2i(Vector2i(x, y), RUIN_BOX)
			if _touches(box):
				continue
			var off := (Vector2(box.get_center()) - Vector2(each.get_center())).length()
			if off < best_off:
				best_off = off
				best = box
	if not best.has_area():
		return false
	art = Rect2i(best.position + RUIN_ARCH.position, RUIN_ARCH.size)
	for leg in RUIN_LEGS:
		for y in range(leg.position.y, leg.end.y):
			for x in range(leg.position.x, leg.end.x):
				solid.append(best.position + Vector2i(x, y))
	solid.append(best.position + RUIN_STELE)
	solid.append(best.position + Vector2i(RUIN_PILLAR.position.x, RUIN_PILLAR.end.y - 1))
	for rock in RUIN_ROCKS:
		solid.append(best.position + rock)
	reading = Rect2i(best.position + RUIN_STELE, Vector2i.ONE)
	chest_cell = best.position + RUIN_CHEST
	return true


## Whether nothing of it -- what it paints, its chest, the cells its art is drawn
## over -- comes near a chest already in its room.
func _clear_of_chests() -> bool:
	if _avoid.is_empty():
		return true
	var mine: Array[Vector2i] = water + solid + paving
	if chest_cell.x >= 0:
		mine.append(chest_cell)
	for cell in mine:
		if _avoid.has(cell):
			return false
	return not _touches(art)


func _touches(rect: Rect2i) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if _avoid.has(Vector2i(x, y)):
				return true
	return false


## Whether, with it laid out, everything in [param reached] -- what could be walked
## to from [param arrival] before -- still can be, bar its own cells, and the chest
## that may stand at it can be walked up to.
func _cuts_nothing(arrival: Vector2i, reached: Dictionary[Vector2i, bool]) -> bool:
	var blocked: Dictionary[Vector2i, bool] = {}
	for cell in water + solid:
		if _ways.has(cell):
			return false
		blocked[cell] = true
	if _ways.has(chest_cell):
		chest_cell = Vector2i(-1, -1)
	if chest_cell.x >= 0:
		if blocked.has(chest_cell) or not (_open.has(chest_cell) or chest_cell in cleared):
			chest_cell = Vector2i(-1, -1)
		else:
			blocked[chest_cell] = true
	var now := _reach(arrival, blocked)
	for cell: Vector2i in reached:
		if not blocked.has(cell) and not now.has(cell):
			return false
	if chest_cell.x >= 0:
		var beside := false
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			beside = beside or now.has(chest_cell + step)
		if not beside:
			chest_cell = Vector2i(-1, -1)
	return true


## Every open cell walkable from [param from] round [param blocked], with the room's
## cleared cells open.
func _reach(from: Vector2i, blocked: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, bool]:
	var open_too: Dictionary[Vector2i, bool] = {}
	for cell in cleared:
		open_too[cell] = true
	var seen: Dictionary[Vector2i, bool] = {from: true}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := cell + step
			if seen.has(next) or blocked.has(next) or not (_open.has(next) or open_too.has(next)):
				continue
			seen[next] = true
			queue.append(next)
	return seen


# --- putting it up --------------------------------------------------------------

func _build_lake(landmark: Landmark) -> void:
	landmark.position = _world(reading.position)
	landmark.display_name = "the sign"
	landmark.add_piece(load(ELEMENT), SIGN, Rect2i(reading.position + Vector2i.UP, Vector2i(1, 2)))
	var notes: Array = LAKE_NOTES.get(_biome.id, LAKE_NOTES[&""])
	landmark.lines = PackedStringArray([
		"A sign on a post: \"%s.\"" % _proper(title),
		notes[variant % notes.size()],
	])


func _build_tree(landmark: Landmark) -> void:
	var tree: Array = TREES[_biome.id]
	var dead := (tree[0] as Rect2i).size.x < 48
	landmark.position = Vector2((reading.position.x + reading.size.x / 2.0) * TILE, reading.end.y * TILE)
	landmark.prompt_verb = "Look at"
	landmark.display_name = title
	landmark.add_piece(load(NATURE), tree[0], art, 2)
	var lines := DEAD_TREE_LINES if dead else TREE_LINES
	landmark.lines = PackedStringArray([
		"The oldest thing on the floor -- older than the floor's monsters, older than any player who ever walked under it.",
		(lines[variant % lines.size()] as String).format({"party": _names(4, 1)}),
	])


func _build_monument(landmark: Landmark) -> void:
	var region := STATUES[variant % STATUES.size()]
	if not _biome.id in SANDSTONE:
		region.position += GREY
	landmark.position = Vector2((reading.position.x + reading.size.x / 2.0) * TILE, reading.end.y * TILE)
	landmark.display_name = title
	landmark.add_piece(load(HOUSE), region, art, 2)
	landmark.lines = PackedStringArray([
		"A memorial, put up by players. Names fill the stone -- people who died on Floor %d." % floor_number,
		"%s." % _names(5, 2),
		MEMORIAL_ENDS[variant % MEMORIAL_ENDS.size()],
	])


func _build_ruin(landmark: Landmark) -> void:
	var box := Rect2i(art.position - RUIN_ARCH.position, RUIN_BOX)
	landmark.position = _world(reading.position)
	landmark.display_name = "the fallen tablet"
	var house: Texture2D = load(HOUSE)
	var nature: Texture2D = load(NATURE)
	landmark.add_piece(house, ARCH, art, 2)
	landmark.add_piece(_stele(), Rect2i(Vector2i.ZERO, STELE.size), reading)
	landmark.add_piece(house, Rect2i(PILLAR.position + GREY, PILLAR.size),
			Rect2i(box.position + RUIN_PILLAR.position, RUIN_PILLAR.size))
	for i in RUIN_ROCKS.size():
		landmark.add_piece(nature, BOULDERS[(variant + i) % BOULDERS.size()],
				Rect2i(box.position + RUIN_ROCKS[i], Vector2i.ONE))
	var boss := FloorRegistry.get_floor(floor_number).boss_name
	landmark.lines = PackedStringArray([
		"A tablet older than any player: the script is the system's own, worn almost smooth.",
		(TABLET_LINES[variant % TABLET_LINES.size()] as String).format({
			"boss": boss, "rank": _ordinal(FloorTuning.boss_level(floor_number))}),
	])


## The pack's sandstone stele turned to the arch's grey-green stone, made once: the
## system's tablet, not a player's sign.
static func _stele() -> Texture2D:
	if _grey_stele == null:
		var image := (load(ELEMENT) as Texture2D).get_image().get_region(STELE)
		image.convert(Image.FORMAT_RGBA8)
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a > 0.0 and pixel.s > 0.15:
					pixel.h = 0.36
					pixel.s *= 0.22
					image.set_pixel(x, y, pixel)
		_grey_stele = ImageTexture.create_from_image(image)
	return _grey_stele


## A monster the floor put down where it now stands is stepped off it, onto the
## nearest open cell -- moved, not dropped, as a puzzle's piece does: the count is
## the boss's balance.
func _step_monsters_off(map: Node2D) -> void:
	var taken: Dictionary[Vector2i, bool] = {}
	for cell in water + solid:
		taken[cell] = true
	if chest_cell.x >= 0:
		taken[chest_cell] = true
	for child in map.get_children():
		var monster := child as Monster
		if monster == null:
			continue
		var at := Vector2i(monster.position / TILE)
		if not taken.has(at):
			continue
		var seen: Dictionary[Vector2i, bool] = {at: true}
		var queue: Array[Vector2i] = [at]
		var head := 0
		while head < queue.size():
			var cell := queue[head]
			head += 1
			if _open.has(cell) and not taken.has(cell):
				monster.position = _world(cell)
				break
			for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if not seen.has(cell + step) and room.grow(1).has_point(cell + step):
					seen[cell + step] = true
					queue.append(cell + step)


# --- words -----------------------------------------------------------------------

func _name(pick: int) -> String:
	var names = NAMES[kind]
	if names is Dictionary:
		names = names[_biome.id]
	return names[pick % (names as Array).size()]


## [param count] players' handles, joined for reading, from the [param salt]th draw.
func _names(count: int, salt: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:landmark_names:%d" % [_seed, salt])
	var pool: Array[String] = []
	for handle in HANDLES:
		pool.append(handle)
	var picked: PackedStringArray = []
	for i in count:
		picked.append(pool.pop_at(rng.randi() % pool.size()))
	return "%s and %s" % [", ".join(picked.slice(0, count - 1)), picked[count - 1]]


## [param words] with its first letter a capital: "the Elder Oak" heading a line or
## a label on M.
static func _proper(words: String) -> String:
	return words.left(1).to_upper() + words.substr(1)


static func _ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]


## Fisher-Yates on the landmark's stream: [method Array.shuffle] uses the global rng.
func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var held = items[i]
		items[i] = items[j]
		items[j] = held


static func _center(rect: Rect2i) -> Vector2i:
	return rect.position + rect.size / 2


static func _world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)
