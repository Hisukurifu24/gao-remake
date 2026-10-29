class_name FloorCamp
extends RefCounted
## The adventurers' camp on a generated floor: where you arrive, where the teleport
## gate stands, and where a few players have pitched their tents (plan.md, M6
## "Floor variety"). Floor 1's town and the authored floors' hubs are their own.
##
## The camp's plot is reserved *by rule* round the room you arrive in, never drawn
## from the floor's rng, so carving it moved nothing the rng put down: every chest,
## monster, trap and door is where it was before camps existed. It is sized for the
## settlement's last tier rather than its first, so a camp that grows later fills
## the plot in and the floor's layout never changes as it does.
##
## What stands in it -- which tents, who is there and what they say -- comes from a
## stream of its own ([code]hash("<seed>:camp")[/code]), as the puzzles' does; where
## it stands is decided by rule, keeping off every corridor the generator swept.
##
## Two passes, like [FloorPuzzles]: [method plan] on the layout before it is
## dressed (tents are solid, so the wall pass draws round them and the puzzles walk
## round them), [method place] once the map's nodes are going down.
##
## [b]The camp settles[/b] once the floor [constant LocalQuests.SETTLE_AFTER] above
## it is cleared: the players who camped there have gone up with the front line,
## houses of the band's own look go up round the tents they left, and a settler
## stands outside each of two of them with a job ([LocalQuests]), and a trader keeps
## the band's counter ([method ShopLibrary.village_shop]) on a camper's old ground. Where they go is
## planned on every floor, settled or not, and kept out of what the puzzles see --
## so a floor that settles moves nothing but the houses going up. Which houses
## comes from a stream of its own ([code]hash("<seed>:village")[/code]).

const TILE := 16
const SOURCE_ID := 0

## The plot, in tiles: room for the village a generated floor's camp grows into.
## Shrunk only when the arrival room has neighbours too close for it.
const PLOT := Vector2i(16, 12)
## Rock kept between the plot and any other room: two cells, what every biome can
## draw a wall with.
const CLEARANCE := 2
const TENTS := 2
## How many people are in the camp: a seeded pick in this range.
const PEOPLE := Vector2i(2, 3)
## How far from the fire they stand, in tiles, middle to middle.
const GATHER := 4.5
## How many spots for the fire are tried, nearest the plot's middle first.
const FIRE_TRIES := 24
## How many houses a village wants, and how far from the fire they stand, in
## tiles, middle to middle: round the camp rather than on top of it.
const HOUSES := 3
## Fewer than this and a tent is rebuilt as a cabin (see [method _plan_village]).
const MIN_HOUSES := 2
const HOUSE_RING := 6.0
## How far from a house's door its settler may stand, in tiles: a free cell
## between them, since nothing solid in the camp stands against anything else.
const DOORSTEP := 3.5

## Whether the camp is a village: -1 asks [method LocalQuests.is_settled], 0 and 1
## force it. The floor test's, as [member FloorGenerator.with_puzzles] is.
static var settle_override := -1

const NPC_SCENE := preload("res://scenes/world/npc.tscn")
const CAMPFIRE_SCENE := preload("res://scenes/world/campfire.tscn")
const CHARACTERS := "res://assets/ninja_adventure/Actor/Character/%s/%s.png"
## Who pitches a tent on the front line: the pack's fighters, never a sheet one of
## the authored floors' named people wears.
const SHEETS: PackedStringArray = [
	"FighterRed", "FighterWhite", "GladiatorBlue", "Samurai", "NinjaBlue",
	"NinjaGreen", "NinjaRed", "NinjaGray", "Monk", "Monk2", "KnightGold",
	"RedGladiator", "Woman", "NinjaMasked", "MaskRacoon", "Eskimo",
]
## Players' handles, not names: everyone up here is logged in under one.
const HANDLES: PackedStringArray = [
	"Daichi", "Mirela", "Tor", "Kaede", "Brann", "Sora", "Ilse", "Rook", "Pell",
	"Yuzu", "Corvin", "Haru", "Wren", "Osk", "Tamsin", "Jiro", "Fen", "Marlo",
	"Aoi", "Garrick", "Nell", "Kestrel", "Ume", "Dask",
]
const SIDES: PackedStringArray = ["east", "west", "south", "north"]

## What each of the camp's people talks about. Each is a list of openings for a
## floor whose boss stands; the [code]_found[/code] and [code]_cleared[/code]
## lines say the same person's piece once you have found its door, or beaten it.
## [code]{side}[/code], [code]{boss}[/code], [code]{level}[/code],
## [code]{monster}[/code], [code]{floor}[/code] and [code]{next}[/code] are filled
## in from the floor.
const ROLES := {
	"scout": [
		"The labyrinth's on the {side} side of the field. Nobody's found the boss room yet -- the door only shows once you're standing in the room.",
		"We've walked the field end to end. The labyrinth's {side} of here, and it goes on a lot longer than it looks from outside.",
		"I went into the labyrinth this morning and came out again by noon. It's {side} of the camp, if you're feeling braver than me.",
	],
	"scout_found": [
		"You found the boss room? Then that's the maze done with. Go back in rested -- {boss} won't wait politely.",
	],
	"scout_cleared": [
		"The stairs to Floor {next} are open, they say. Good. I was sick of that labyrinth.",
	],
	"veteran": [
		"The front line's calling the thing behind the labyrinth door {boss}. I wouldn't knock before level {level}.",
		"{boss}. That's who's waiting at the end of this floor. Level {level} at the least, and bring more potions than you think.",
	],
	"veteran_found": [
		"So you've seen the door. {boss}'s behind it. Level {level}, and don't go in on half a health bar.",
	],
	"veteran_cleared": [
		"You took down {boss}? Then this floor's just somewhere to live now. Strange thought.",
	],
	"local": [
		"Watch yourself out in the field. Some {monster} took half my health before I'd drawn my sword.",
		"Every {monster} out there keeps to its own patch of the field until it sees you. Then it doesn't.",
		"There's a chest or two out in the rooms. Some of the big red ones bite back, mind.",
	],
	"local_cleared": [
		"Floor {floor}'s cleared and here I still am. Someone has to keep the fire going for whoever comes up next.",
	],
	# An open field's: no labyrinth, an arena in plain sight and waystones sealing it.
	"open_scout": [
		"No labyrinth on this floor. Just the field, and an arena on the {side} side of it -- sealed. There are waystones out in the far clearings; wake them all and the gate opens, they say.",
		"You can see the arena from half the field. It's {side} of here. Walk up to the gate if you like; it won't open till every waystone's lit.",
	],
	"open_scout_found": [
		"The arena's open? Then the waystones are done with. Go in rested -- {boss} won't wait politely.",
	],
	"open_scout_cleared": [
		"The stairs to Floor {next} are open, they say. Good. I was sick of walking this field end to end.",
	],
	"open_veteran": [
		"The front line's calling the thing in the arena {boss}. I wouldn't walk in before level {level}.",
		"{boss}. That's who's waiting in the arena. Level {level} at the least, and bring more potions than you think.",
	],
	"open_veteran_found": [
		"So the arena's open. {boss}'s in there. Level {level}, and don't go in on half a health bar.",
	],
	# A dungeon's: no field, levels climbed by stairs that something on each level seals.
	"dungeon_scout": [
		"This whole floor's a dungeon -- {levels} levels of it, and {boss} at the top. Every ladder up is sealed. Something on the level opens it: a warden with the key, levers, old fires, statues.",
		"The way up's {side} of the hall, behind a slab of stone. You don't break it -- you find what opens it. Every level's different.",
	],
	"dungeon_scout_found": [
		"You've been to the top? Then you've seen the hall. Go back up rested -- {boss} won't wait politely.",
	],
	"dungeon_scout_cleared": [
		"The stairs to Floor {next} are open, they say. Good. I was sick of ladders.",
	],
	"dungeon_veteran": [
		"{boss}'s holed up on the top level. Level {level} at the least, and there's a fire to rest by on the way, halfway up.",
		"They're calling the thing at the top {boss}. I wouldn't climb the last ladder before level {level}.",
	],
	"dungeon_veteran_found": [
		"So you've seen the top. {boss}'s waiting there. Level {level}, and don't go in on half a health bar.",
	],
	# The top floor's: its boss has no name until you meet him ([constant FinalBoss.UNMET]),
	# so nobody in camp says one. As many lines as the plain roles, so the camp's
	# stream draws the same.
	"final_scout_found": [
		"You found the last door? Then that's the maze done with. Go back in rested -- whatever's behind it built the other ninety-nine floors' worth of trouble.",
	],
	"final_veteran": [
		"Every floor, the front line had a name for the boss by now. Not this one. Nobody's come back from the last door to give it one. I wouldn't knock before level {level}.",
		"No name for what's at the top. Argo doesn't sell it, and Argo sells everything. Level {level} at the least, and bring more potions than you think.",
	],
	"final_veteran_found": [
		"So you've seen the last door. No name over it, no cursor behind it. Level {level}, and don't go in on half a health bar.",
	],
	"dungeon_local": [
		"It's black as pitch past these lamps. You see what's in front of you and nothing else -- and neither does the {monster}, till it does.",
		"Mind the chests down there. Some of the big red ones bite back.",
	],
}
## The order the camp's people are drawn in: the first two always, the third only
## in a camp of three.
const ROLE_ORDER: PackedStringArray = ["scout", "veteran", "local"]
## What a newcomer says about the place itself, on top of the [code]local[/code]
## openings: one per band.
const BIOME_LINES := {
	&"meadow": "Nice enough up here, if you don't look at the trees too long. Things move in them.",
	&"forest": "The pines grow so close you lose the sky. I keep this fire going so I can find my way back.",
	&"cave": "No sky at all on this floor. You stop missing it after a day. That's the bit that worries me.",
	&"ruins": "Somebody lived here once. Whatever drove them out still walks between the walls at night.",
	&"swamp": "Don't drink the water. Don't wade the water. Honestly, don't look at the water.",
	&"desert": "Fill every flask at the oases. The sand out there is hotter than it has any right to be.",
	&"ice": "Keep moving and you stay warm. Stop for long out there and you stop for good.",
	&"volcanic": "Mind the lava. It looks like it's sleeping. It isn't.",
	&"sky": "Don't stand near the edges. I watched a man walk off one. He didn't come back up.",
	&"castle": "Red brick and grey stone, all the way up. We're close now. You can feel it.",
}

## The plot, in tiles.
var plot := Rect2i()
## Each tent's whole 3x3, in tiles; its bottom two rows are solid.
var tents: Array[Rect2i] = []
var tent_variants: Array[int] = []
## The cookfire's 2x2 (the pit in its bottom row, the flame above), in tiles.
## Empty when the plot had no room for one.
var fire := Rect2i()
## Where the camp's people stand, in tiles.
var people: Array[Vector2i] = []
## Whether the camp has grown into a village (see the class docs).
var village := false
## Whether the floor is an open field, which its people talk about instead of a
## labyrinth. Set before [method place].
var open_field := false
## Whether it is a dungeon's, in its entrance hall: its people talk about levels.
var dungeon := false
## The floor's modifier ([enum FloorModifier.Kind]) and, in a storm, its weather:
## the scout says a word about it. Set before [method place].
var modifier := 0
var weather: StringName = &""
## What the veteran says about the floor's event ([FloorEvents]), after their
## opening; empty for none. Set before [method place].
var event_line := ""
## What the camp says about the floor's landmark ([FloorLandmarks]), after an
## opening -- the local's, or the scout's in a camp of two; empty for none. Set
## before [method place].
var landmark_line := ""
## Each house's whole rect, in tiles, and which of the band's village tiles it
## is; planned whether or not the camp has settled, built only once it has.
var houses: Array[Rect2i] = []
var house_variants: Array[int] = []
## The tents a small plot's village rebuilds as cabins, by index: in [member houses]
## too, and drawn as houses rather than tents once the camp has settled.
var cabins: Array[int] = []
## Where each job's settler stands, in tiles, outside a house.
var settlers: Array[Vector2i] = []
## Where the village's trader stands, in tiles, or (-1, -1) where no camper's cell
## is left free: one of [member people], so it was never open to the puzzles.
var trader_cell := Vector2i(-1, -1)
## Where the floor's lost player waits, in tiles: a dead end in the labyrinth.
var lost_cell := Vector2i(-1, -1)

var floor_number := 0
var _rng := RandomNumberGenerator.new()
var _village_rng := RandomNumberGenerator.new()
var _biome: BiomeKit
var _ground: TileMapLayer
var _walls: TileMapLayer
var _open: Dictionary[Vector2i, bool]
## Cells nothing may stand on or beside: the arrival, the gate and the stairs.
var _keep: Dictionary[Vector2i, bool] = {}
## Every corridor's sweep near the plot: nothing stands in one, but it is open
## floor, so it serves as the walk round whatever stands beside it.
var _lanes: Dictionary[Vector2i, bool] = {}
var _arrival := Vector2i.ZERO


func _init(number: int, generation_seed: int, biome: BiomeKit, ground: TileMapLayer,
		walls: TileMapLayer, open: Dictionary[Vector2i, bool]) -> void:
	floor_number = number
	_rng.seed = hash("%d:camp" % generation_seed)
	_village_rng.seed = hash("%d:village" % generation_seed)
	if settle_override >= 0:
		village = settle_override == 1
	else:
		village = LocalQuests.is_settled(number)
	_biome = biome
	_ground = ground
	_walls = walls
	_open = open


## Picks the plot and carves it: [constant PLOT] round [param entry], inside the
## [param field] with a wall ring to spare, [constant CLEARANCE] from every other
## room, and as near centred on the arrival room as that allows -- or the biggest
## that fits, when a neighbour stands too close. Rule, not rng.
## Carved as plain floor, since the floor's [method FloorGenerator._carve] asks
## the rng about every cell it paints.
func reserve(field: Rect2i, rooms: Array[Rect2i], entry: Rect2i) -> void:
	plot = entry
	var bounds := field.grow(-CLEARANCE)
	var full := PLOT.max(entry.size)
	# Biggest first, squarer first among equals: a plot cut short one way only
	# keeps more room than one cut short both ways.
	var sizes: Array[Vector2i] = []
	for w in range(entry.size.x, full.x + 1):
		for h in range(entry.size.y, full.y + 1):
			sizes.append(Vector2i(w, h))
	sizes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x * a.y != b.x * b.y:
			return a.x * a.y > b.x * b.y
		return absi(a.x - a.y) < absi(b.x - b.y) or (absi(a.x - a.y) == absi(b.x - b.y) and a.x > b.x))
	for size in sizes:
		var best := _centred(size, bounds, rooms, entry)
		if best.has_area():
			plot = best
			break
	for y in range(plot.position.y, plot.end.y):
		for x in range(plot.position.x, plot.end.x):
			var cell := Vector2i(x, y)
			if not _open.has(cell):
				_walls.erase_cell(cell)
				_ground.set_cell(cell, SOURCE_ID, Vector2i(_biome.floor_tile, 0))
				_open[cell] = true


## The [param size] rect holding [param entry] whose middle is nearest the
## room's, in reading order on a tie; empty if every one is too near a room.
func _centred(size: Vector2i, bounds: Rect2i, rooms: Array[Rect2i], entry: Rect2i) -> Rect2i:
	var best := Rect2i()
	var best_distance := INF
	for y in range(maxi(bounds.position.y, entry.end.y - size.y), mini(entry.position.y, bounds.end.y - size.y) + 1):
		for x in range(maxi(bounds.position.x, entry.end.x - size.x), mini(entry.position.x, bounds.end.x - size.x) + 1):
			var candidate := Rect2i(Vector2i(x, y), size)
			var clear := true
			for room in rooms:
				if room != entry and room.grow(CLEARANCE).intersects(candidate):
					clear = false
					break
			if not clear:
				continue
			var distance := _middle(candidate).distance_squared_to(_middle(entry))
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best


## Decides where the fire, the tents and the people stand, and puts the tents'
## solid rows on the walls. [param arrival] is where you come in; [param lanes]
## every cell a corridor swept, plot or not; [param keep] the rects the arrival,
## the gate and the stairs need clear. Nothing stands in a lane, so the camp
## narrows no corridor; everything has a cell's walk round it (a lane will do) or
## the plot's rock behind it; and nothing is put down that cuts a cell of the plot
## off from the arrival.
##
## The fire goes first, nearest the plot's middle -- but a spot is only taken if
## the tents and the people fit round it, so the next is tried until a whole camp
## does (the best of [constant FIRE_TRIES] if none).
func plan(arrival: Vector2i, lanes: Dictionary[Vector2i, bool], keep: Array[Rect2i]) -> void:
	_arrival = arrival
	var ring := plot.grow(1)
	for cell in lanes:
		if ring.has_point(cell):
			_lanes[cell] = true
	for rect in keep:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				_keep[Vector2i(x, y)] = true

	var wanted := _rng.randi_range(PEOPLE.x, PEOPLE.y)
	var best: Array = []
	var best_score := -1
	var spots := _ranked(Vector2i(2, 2), _middle(plot), Vector2.ZERO, {})
	for spot in spots.slice(0, FIRE_TRIES):
		var layout := _around(spot, wanted)
		if layout.is_empty():
			continue
		var score: int = (layout[1] as Array).size() * 10 + (layout[2] as Array).size()
		if score > best_score:
			best_score = score
			best = layout
		if (layout[1] as Array).size() == TENTS and (layout[2] as Array).size() == wanted:
			break
	if best.is_empty():
		return

	fire = best[0]
	_open.erase(fire.end - Vector2i.ONE)
	_open.erase(fire.end - Vector2i(2, 1))
	for tent: Rect2i in best[1]:
		tents.append(tent)
		tent_variants.append(_rng.randi() % maxi(1, _biome.camp_tiles.size()))
		for y in range(tent.position.y + 1, tent.end.y):
			for x in range(tent.position.x, tent.end.x):
				var cell := Vector2i(x, y)
				_walls.set_cell(cell, SOURCE_ID, Vector2i(_biome.wall_alt_tile, 0))
				_open.erase(cell)
	for spot: Rect2i in best[2]:
		people.append(spot.position)
		_open.erase(spot.position)
	_plan_village(best)
	# Trodden earth round the fire.
	for y in range(fire.position.y - 2, fire.end.y + 2):
		for x in range(fire.position.x - 2, fire.end.x + 2):
			var cell := Vector2i(x, y)
			if plot.has_point(cell) and _walls.get_cell_source_id(cell) == -1:
				_ground.set_cell(cell, SOURCE_ID, Vector2i(_biome.path_tile, 0))


## Where the village goes, round the fire and tents of [param layout]
## ([method _around]'s) -- its people will have gone:
## up to [constant HOUSES] houses about [constant HOUSE_RING] from the fire, each
## with its free cell all round, and a settler outside the first
## [constant LocalQuests.PER_FLOOR] of them. Planned on every floor and taken out
## of the open cells either way, so the puzzles, planned next, never use a cell a
## house may one day stand on; built -- solid, on the walls -- only in a village.
func _plan_village(layout: Array) -> void:
	if _biome.village_tiles.is_empty():
		return
	# Round the fire and the tents, not the camp's people: by the time a floor has
	# settled, the players who camped on it have gone up with the front line.
	var taken: Dictionary[Vector2i, bool] = {}
	_mark(taken, layout[0], true)
	for tent: Rect2i in layout[1]:
		_mark(taken, tent, true)
	for cell in people:
		_open[cell] = true
	var hearth := _middle(layout[0])
	var source := _biome.tile_set.get_source(SOURCE_ID) as TileSetAtlasSource
	var order: Array[int] = []
	for i in _biome.village_tiles.size():
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j := _village_rng.randi_range(0, i)
		var held := order[i]
		order[i] = order[j]
		order[j] = held

	# Under a roof: walked behind, so not solid -- but nothing else may stand there.
	var roofs: Dictionary[Vector2i, bool] = {}
	for n in HOUSES:
		# The next house in the shuffled order first, then whichever of the others
		# fits -- a small plot still gets its houses, just smaller ones.
		for k in order.size():
			var variant := order[(n + k) % order.size()]
			var size := source.get_tile_size_in_atlas(_biome.village_tiles[variant])
			var spot := _house_spot(size, hearth, taken, roofs)
			if spot.has_area():
				houses.append(spot)
				house_variants.append(variant)
				for x in range(spot.position.x, spot.end.x):
					roofs[Vector2i(x, spot.position.y)] = true
				break
	# A plot with no room for its houses rebuilds a tent as a cabin -- the same
	# footprint, so it moves nothing -- but always leaves one standing.
	var cabin := -1
	for i in _biome.village_tiles.size():
		if source.get_tile_size_in_atlas(_biome.village_tiles[i]) == Vector2i(3, 3):
			cabin = i
			break
	var tent := tents.size() - 1
	while houses.size() < MIN_HOUSES and cabin >= 0 and tent >= 1:
		houses.append(tents[tent])
		house_variants.append(cabin)
		cabins.append(tent)
		for x in range(tents[tent].position.x, tents[tent].end.x):
			roofs[Vector2i(x, tents[tent].position.y)] = true
		tent -= 1

	# Outside their own door if there is room, else by the fire.
	for i in LocalQuests.PER_FLOOR:
		var near := hearth
		var reach := GATHER
		if i < houses.size():
			near = Vector2(houses[i].position.x + houses[i].size.x / 2.0, houses[i].end.y + 0.5)
			reach = DOORSTEP
		var spot := _person_spot(near, reach, taken, roofs)
		if spot.x < 0 and reach != GATHER:
			spot = _person_spot(hearth, GATHER, taken, roofs)
		if spot.x >= 0:
			settlers.append(spot)
	# The trader on the first camper's cell the village leaves free and in one
	# piece. Only the campers' cells: they are out of the open cells the puzzles
	# read on every floor, so a counter moves nothing -- and no stream is asked.
	for cell in people:
		if not roofs.has(cell) and not taken.has(cell) and _fits(Rect2i(cell, Vector2i.ONE), taken):
			trader_cell = cell
			break

	for house in houses:
		for y in range(house.position.y, house.end.y):
			for x in range(house.position.x, house.end.x):
				var cell := Vector2i(x, y)
				_open.erase(cell)
				# The roof's top row is walked behind; the rest stands.
				if village and y > house.position.y:
					_walls.set_cell(cell, SOURCE_ID, Vector2i(_biome.wall_alt_tile, 0))
	# The camp's people and the village's both: the puzzles keep off either.
	for cell in settlers + people:
		_open.erase(cell)


## The free cell nearest [param near] and within [param reach] of it, under no
## roof, that leaves the plot in one piece -- taken in [param taken] -- or
## (-1, -1).
func _person_spot(near: Vector2, reach: float, taken: Dictionary[Vector2i, bool],
		roofs: Dictionary[Vector2i, bool]) -> Vector2i:
	for spot in _ranked(Vector2i.ONE, near, Vector2.ZERO, taken):
		if _middle(spot).distance_to(near) > reach:
			break
		if not roofs.has(spot.position) and _fits(spot, taken):
			return spot.position
	return Vector2i(-1, -1)


## Where a [param size] house goes, nearest [constant HOUSE_RING] from
## [param hearth]; empty if nowhere. Its solid rows -- all but the roof's top one --
## are a free rect that leaves the plot in one piece, taken in [param taken]; the
## roof row hangs over open plot floor with nothing standing in it (a corridor
## will do: you walk behind it), and the row in front of the door is plot floor
## too, never the rock at its edge. [param roofs] are the roofs already up.
func _house_spot(size: Vector2i, hearth: Vector2, taken: Dictionary[Vector2i, bool],
		roofs: Dictionary[Vector2i, bool]) -> Rect2i:
	var solid := Vector2i(size.x, size.y - 1)
	var spots: Array[Rect2i] = []
	var keys: Dictionary[Rect2i, float] = {}
	for spot in _ranked(solid, hearth, Vector2.ZERO, taken):
		var house := Rect2i(spot.position - Vector2i(0, 1), size)
		if house.position.y < plot.position.y or spot.end.y >= plot.end.y:
			continue
		var clear := true
		for x in range(house.position.x, house.end.x):
			for cell: Vector2i in [Vector2i(x, house.position.y), Vector2i(x, spot.end.y)]:
				if roofs.has(cell) or _keep.has(cell) or taken.has(cell) or not _open.has(cell):
					clear = false
			for y in range(spot.position.y, spot.end.y):
				clear = clear and not roofs.has(Vector2i(x, y))
		if clear:
			spots.append(house)
			keys[house] = absf(_middle(house).distance_to(hearth) - HOUSE_RING)
	spots.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		if keys[a] != keys[b]:
			return keys[a] < keys[b]
		return a.position.y < b.position.y or (a.position.y == b.position.y and a.position.x < b.position.x))
	for house in spots:
		if _fits(Rect2i(house.position + Vector2i(0, 1), solid), taken):
			return house
	return Rect2i()


## The camp round a fire at [param hearth_rect]: [code][fire, tents, people][/code],
## as many tents as fit facing it and up to [param wanted] people within
## [constant GATHER] of it. Empty if the fire itself would cut the plot.
func _around(hearth_rect: Rect2i, wanted: int) -> Array:
	var taken: Dictionary[Vector2i, bool] = {}
	_mark(taken, hearth_rect, true)
	if not _connected(taken):
		return []
	var hearth := _middle(hearth_rect)
	var placed_tents: Array[Rect2i] = []
	for _i in TENTS:
		# By its door, a cell below its middle: a tent faces the fire.
		for spot in _ranked(Vector2i(3, 3), hearth, Vector2(0.0, 2.5), taken):
			if _fits(spot, taken):
				placed_tents.append(spot)
				break
	var placed_people: Array[Rect2i] = []
	for _i in wanted:
		for spot in _ranked(Vector2i.ONE, hearth, Vector2.ZERO, taken):
			if _middle(spot).distance_to(hearth) > GATHER:
				break
			if _fits(spot, taken):
				placed_people.append(spot)
				break
	return [hearth_rect, placed_tents, placed_people]


## Takes [param spot] in [param taken] if the plot stays in one piece with it
## there; leaves [param taken] as it was if not.
func _fits(spot: Rect2i, taken: Dictionary[Vector2i, bool]) -> bool:
	_mark(taken, spot, true)
	if _connected(taken):
		return true
	_mark(taken, spot, false)
	return false


## Every free [param size] rect in the plot, nearest [param to] first (its middle
## moved by [param bias]), reading order on a tie. Free: plot floor, in no lane;
## and nothing kept or [param taken] in it or the ring round it, which is open
## floor, a corridor or the plot's own rock.
func _ranked(size: Vector2i, to: Vector2, bias: Vector2,
		taken: Dictionary[Vector2i, bool]) -> Array[Rect2i]:
	var found: Array[Rect2i] = []
	var keys: Array[float] = []
	for y in range(plot.position.y, plot.end.y - size.y + 1):
		for x in range(plot.position.x, plot.end.x - size.x + 1):
			var candidate := Rect2i(Vector2i(x, y), size)
			if _free(candidate, taken):
				found.append(candidate)
	found.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		var da := (_middle(a) + bias).distance_squared_to(to)
		var db := (_middle(b) + bias).distance_squared_to(to)
		if da != db:
			return da < db
		return a.position.y < b.position.y or (a.position.y == b.position.y and a.position.x < b.position.x))
	return found


func _free(rect: Rect2i, taken: Dictionary[Vector2i, bool]) -> bool:
	var around := rect.grow(1)
	for y in range(around.position.y, around.end.y):
		for x in range(around.position.x, around.end.x):
			var cell := Vector2i(x, y)
			if _keep.has(cell) or taken.has(cell):
				return false
			if rect.has_point(cell):
				if _lanes.has(cell) or not _open.has(cell) or not plot.has_point(cell):
					return false
			elif plot.has_point(cell) and not _open.has(cell):
				return false
			elif not plot.has_point(cell) and _open.has(cell) and not _lanes.has(cell):
				return false
	return true


## Whether every open cell of the plot can still be walked to from the arrival,
## with [param taken] solid. Conservative: a tent's roof row and the fire's flame
## are walkable in the game, and solid here.
func _connected(taken: Dictionary[Vector2i, bool]) -> bool:
	var seen: Dictionary[Vector2i, bool] = {_arrival: true}
	var queue: Array[Vector2i] = [_arrival]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + step
			if seen.has(next) or not plot.has_point(next) or taken.has(next) or not _open.has(next):
				continue
			seen[next] = true
			queue.append(next)
	for y in range(plot.position.y, plot.end.y):
		for x in range(plot.position.x, plot.end.x):
			var cell := Vector2i(x, y)
			if _open.has(cell) and not taken.has(cell) and not seen.has(cell):
				return false
	return true


## [param rect]'s middle, in tiles: [method Rect2i.get_center] rounds it to a cell.
static func _middle(rect: Rect2i) -> Vector2:
	return Vector2(rect.position) + Vector2(rect.size) / 2.0


func _mark(taken: Dictionary[Vector2i, bool], rect: Rect2i, on: bool) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if on:
				taken[Vector2i(x, y)] = true
			else:
				taken.erase(Vector2i(x, y))


## Puts the camp on [param map]: the tents on its props layer, the cookfire, and
## its people with what they have to say -- and, in a village, its houses, its
## settlers and their jobs. [param side] is the labyrinth's
## ([enum FloorGenerator.Side]), which the scout knows. [param dead_ends] are the
## labyrinth's free dead ends, as [code][cell, the way out][/code] in tiles, for
## a lost player to wait in.
func place(map: Node2D, side: int, boss_name: String, dead_ends: Array = []) -> void:
	if not tents.is_empty() and not _biome.camp_tiles.is_empty():
		var props := MapDresser.props_layer(map, _biome)
		for i in tents.size():
			if not (village and i in cabins):
				props.set_cell(MapDresser.anchor_for(tents[i]), SOURCE_ID, _biome.camp_tiles[tent_variants[i]])
	# Drawn on every floor so the stream does not depend on the tier.
	var lost_pick := _village_rng.randi() % maxi(1, dead_ends.size())
	if village:
		_place_village(map, dead_ends[lost_pick] if not dead_ends.is_empty() else [])
	if fire.has_area():
		var hearth := CAMPFIRE_SCENE.instantiate()
		hearth.name = "Cookfire"
		hearth.position = Vector2((fire.position.x + 1) * TILE, fire.end.y * TILE)
		hearth.set(&"rests", false)
		hearth.set(&"prompt_verb", "Look at")
		hearth.set(&"display_name", "the cookfire")
		map.add_child(hearth)

	var sheets := Array(SHEETS)
	var handles := Array(HANDLES)
	_shuffle(sheets)
	_shuffle(handles)
	var words := _words(side, boss_name)
	# A village's campers have moved on up; their ground is the houses'.
	for i in (0 if village else people.size()):
		var role: String = ROLE_ORDER[i % ROLE_ORDER.size()]
		var sheet: String = sheets[i % sheets.size()]
		var handle: String = handles[i % handles.size()]
		var npc := NPC_SCENE.instantiate()
		npc.name = "Camper%d" % i
		npc.position = Vector2(people[i].x * TILE + TILE / 2.0, people[i].y * TILE + TILE / 2.0)
		npc.set(&"sprite_sheet", load(CHARACTERS % [sheet, "SpriteSheet"]))
		npc.set(&"display_name", handle)
		npc.set(&"dialogue", _talk(i, role, handle, load(CHARACTERS % [sheet, "Faceset"]), words))
		# Facing the fire: the sheet's columns are down, up, left, right.
		var to_fire := _middle(fire) - _middle(Rect2i(people[i], Vector2i.ONE))
		var column := (0 if to_fire.y > 0 else 1) if absf(to_fire.y) >= absf(to_fire.x) \
				else (3 if to_fire.x > 0 else 2)
		(npc.get_node("Sprite2D") as Sprite2D).frame = column
		map.add_child(npc)


## The village's houses, the settlers outside them with their jobs, and the
## floor's lost player -- in the labyrinth until their job is taken (hidden till
## then), and gone once they have been found.
func _place_village(map: Node2D, dead_end: Array) -> void:
	var props := MapDresser.props_layer(map, _biome)
	for i in houses.size():
		props.set_cell(MapDresser.anchor_for(houses[i]), SOURCE_ID, _biome.village_tiles[house_variants[i]])
	var jobs := LocalQuests.ids_for(floor_number)
	for i in mini(settlers.size(), jobs.size()):
		var who := LocalQuests.giver(jobs[i])
		var npc := _person(settlers[i], who["sheet"], who["name"], LocalQuests.giver_dialogue(jobs[i]))
		npc.name = "Settler%d" % i
		map.add_child(npc)
	var counter := ShopLibrary.village_shop(_biome.id)
	var keeper := LocalQuests.trader(floor_number)
	if trader_cell.x >= 0 and counter != null and not keeper.is_empty():
		# The band's counter, kept by this floor's trader.
		var shop := counter.duplicate() as Shop
		shop.keeper = keeper["name"]
		var npc := _person(trader_cell, keeper["sheet"], keeper["name"], null)
		npc.name = "Trader"
		npc.set(&"shop", shop)
		npc.set(&"prompt_verb", "Trade with")
		map.add_child(npc)
	var lost := LocalQuests.lost_person(floor_number)
	var job := LocalQuests.talk_quest(floor_number)
	if lost.is_empty() or dead_end.is_empty() \
			or GameState.has_flag(QuestLog.flag_for(job, "ready")) \
			or GameState.has_flag(QuestLog.flag_for(job, "done")):
		return
	lost_cell = dead_end[0]
	var npc := _person(lost_cell, lost["sheet"], lost["name"], LocalQuests.lost_dialogue(floor_number))
	npc.name = "LostPlayer"
	npc.set(&"hidden_until", QuestLog.flag_for(job, "started"))
	# Looking back the way they came in, which is the way you come.
	var out: Vector2i = dead_end[1]
	(npc.get_node("Sprite2D") as Sprite2D).frame = 0 if out.y > 0 else 1 if out.y < 0 \
			else 3 if out.x > 0 else 2
	map.add_child(npc)


## Someone standing at [param cell], drawn from the pack's [param sheet], facing
## down, who says [param talk].
func _person(cell: Vector2i, sheet: String, who: String, talk: Dialogue) -> Node2D:
	var npc := NPC_SCENE.instantiate()
	npc.position = Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)
	npc.set(&"sprite_sheet", load(CHARACTERS % [sheet, "SpriteSheet"]))
	npc.set(&"display_name", who)
	npc.set(&"dialogue", talk)
	return npc


## What the camp's people fill their lines in with.
func _words(side: int, boss_name: String) -> Dictionary:
	var pool := Bestiary.pool_for_floor(floor_number)
	var monster := "monster"
	if not pool.is_empty():
		monster = pool[_rng.randi() % pool.size()].display_name.to_lower()
	return {
		"side": SIDES[side] if side >= 0 and side < SIDES.size() else "far",
		"boss": boss_name,
		"level": FloorTuning.boss_level(floor_number),
		"monster": monster,
		"floor": floor_number,
		"next": floor_number + 1,
		"levels": FloorTuning.dungeon_levels(floor_number),
	}


## A conversation that reads the floor: what the person says once its boss is
## down, once its door is found, and before either.
func _talk(index: int, role: String, handle: String, portrait: Texture2D,
		words: Dictionary) -> Dialogue:
	var talk := Dialogue.new()
	talk.id = StringName("camp_%d_%d" % [floor_number, index])
	talk.default_speaker = handle
	talk.default_portrait = portrait
	var cleared := DialogueCondition.new()
	cleared.test = DialogueCondition.Test.FLOOR_CLEARED
	cleared.number = floor_number
	var found := DialogueCondition.new()
	found.test = DialogueCondition.Test.FLAG_SET
	found.flag = BossGate.found_flag(floor_number)

	var cleared_key := _role_key(role + "_cleared")
	if ROLES.has(cleared_key):
		talk.lines.append(_line(_pick(ROLES[cleared_key], words), [cleared]))
	var found_key := _role_key(role + "_found")
	if ROLES.has(found_key):
		talk.lines.append(_line(_pick(ROLES[found_key], words), [found]))
	var openings: Array = ROLES[_role_key(role)].duplicate()
	if role == "local" and BIOME_LINES.has(_biome.id):
		openings.append(BIOME_LINES[_biome.id])
	var opening := _line(_pick(openings, words), [])
	talk.lines.append(opening)
	# The scout's word on the floor's modifier, after the opening it falls through
	# from: a continuation, never an entry. Fixed words, so no stream moves.
	var remarks: Array[String] = []
	if role == "scout":
		remarks.append(FloorModifier.camp_line(modifier, weather))
	# And the veteran's on what is happening on it, the same way.
	if role == "veteran":
		remarks.append(event_line)
	# And whoever knows the floor best on its landmark: the local, or the scout
	# where nobody local is in camp.
	if role == "local" or (role == "scout" and people.size() < ROLE_ORDER.size()):
		remarks.append(landmark_line)
	var last := opening
	for remark in remarks:
		if remark.is_empty():
			continue
		last.next = &""
		last = _line(remark, [])
		talk.lines.append(last)
	return talk


## [param key]'s open-field lines on an open field, or a dungeon's in a dungeon,
## where it has them.
func _role_key(key: String) -> String:
	if FinalBoss.is_final(floor_number) and ROLES.has("final_" + key):
		return "final_" + key
	var shaped := "open_" + key if open_field else "dungeon_" + key if dungeon else key
	return shaped if ROLES.has(shaped) else key


func _line(text: String, conditions: Array[DialogueCondition]) -> DialogueLine:
	var line := DialogueLine.new()
	line.text = text
	line.conditions = conditions
	# Every line is a block of its own, so each can be an entry point.
	line.next = DialogueLine.END
	return line


func _pick(lines: Array, words: Dictionary) -> String:
	return (lines[_rng.randi() % lines.size()] as String).format(words)


## Fisher-Yates on the camp's stream: [method Array.shuffle] uses the global rng.
func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var held = items[i]
		items[i] = items[j]
		items[j] = held
