extends Node
## Answers "what is floor N?" for all 100 floors.
##
## Authored floors are loaded from resources/floors/. Everything else is
## synthesised on demand from the biome band table plus [FloorTuning], so the
## other ~88 floors cost nothing to store and stay consistent with the curve.

## Milestone floors, hand-built. Listed explicitly rather than scanned: res://
## directory listing is unreliable in exported builds.
const AUTHORED := {
	1: "res://resources/floors/floor_01.tres",
	10: "res://resources/floors/floor_10.tres",
	25: "res://resources/floors/floor_25.tres",
}

## Which biome a floor belongs to. Ten bands of ten -- the higher you climb the
## stranger Aincrad gets.
const BIOME_BANDS: Array[Dictionary] = [
	{"through": 9, "biome": "meadow"},
	{"through": 19, "biome": "forest"},
	{"through": 29, "biome": "cave"},
	{"through": 39, "biome": "ruins"},
	{"through": 49, "biome": "swamp"},
	{"through": 59, "biome": "desert"},
	{"through": 69, "biome": "ice"},
	{"through": 79, "biome": "volcanic"},
	{"through": 89, "biome": "sky"},
	{"through": 100, "biome": "castle"},
]

const BIOME_PATH := "res://resources/biomes/%s.tres"

## The share of floors a world lays out the classic way. See [method shape_of].
const SHAPE_CLASSIC := 0.6
## The shapes [FloorGenerator] can build. A floor that picks any other is classic.
const BUILT_SHAPES: Array[int] = [FloorDefinition.Shape.CLASSIC, FloorDefinition.Shape.OPEN_FIELD,
		FloorDefinition.Shape.DUNGEON]

var _floors: Dictionary[int, FloorDefinition] = {}
## world seed -> every floor's picked shape, by [method _pick_shapes].
var _shapes: Dictionary[int, Array] = {}
var _biomes: Dictionary[StringName, BiomeKit] = {}


func get_floor(floor_number: int) -> FloorDefinition:
	floor_number = clampi(floor_number, 1, FloorTuning.TOP_FLOOR)
	if _floors.has(floor_number):
		return _floors[floor_number]

	var definition: FloorDefinition
	if AUTHORED.has(floor_number) and ResourceLoader.exists(AUTHORED[floor_number]):
		definition = load(AUTHORED[floor_number])
	else:
		definition = _synthesise(floor_number)
	_floors[floor_number] = definition
	return definition


func get_biome(floor_number: int) -> BiomeKit:
	var id := biome_id(floor_number)
	if _biomes.has(id):
		return _biomes[id]
	var path := BIOME_PATH % id
	if not ResourceLoader.exists(path):
		push_error("FloorRegistry: missing biome '%s' -- run tools/build_biomes.gd" % id)
		return null
	var biome: BiomeKit = load(path)
	_biomes[id] = biome
	return biome


func biome_id(floor_number: int) -> StringName:
	for band in BIOME_BANDS:
		if floor_number <= int(band["through"]):
			return StringName(band["biome"])
	return &"castle"


## Seeded from the save, so a floor is stable for a given playthrough but
## differs between saves.
func seed_for(floor_number: int) -> int:
	return seed_in(GameState.world_seed, floor_number)


## [method seed_for] in the world [param world_seed] rather than this one: what a
## save's migration asks about a world that isn't loaded yet.
static func seed_in(world_seed: int, floor_number: int) -> int:
	return hash("%d:%d" % [world_seed, floor_number])


## What floor [param floor_number] is laid out as ([enum FloorDefinition.Shape]) in
## this world. Its own stream,
## [code]hash("<seed>:shape")[/code], never the floor's: picking a shape draws nothing
## a classic floor's layout reads, so a classic floor is the floor it always was.
##
## About [constant SHAPE_CLASSIC] of floors are classic and the rest split between
## the other shapes, never the same new one two floors running. Authored floors,
## floor 2 (the first generated one, which the smoke test walks) and the top floor
## are always classic -- an authored floor is what its scene is. A shape picked but
## not built yet ([constant BUILT_SHAPES]) is built classic; the picks don't change
## when it lands, only the floors that picked it.
func shape_of(floor_number: int) -> FloorDefinition.Shape:
	if FloorGenerator.shape_override >= 0:
		return FloorGenerator.shape_override as FloorDefinition.Shape
	return shape_in(GameState.world_seed, floor_number)


## [method shape_of] in the world [param world_seed], overrides aside.
func shape_in(world_seed: int, floor_number: int) -> FloorDefinition.Shape:
	if not _shapes.has(world_seed):
		_shapes[world_seed] = _pick_shapes(world_seed)
	var picked: int = _shapes[world_seed][clampi(floor_number, 1, FloorTuning.TOP_FLOOR)]
	return (picked if picked in BUILT_SHAPES else FloorDefinition.Shape.CLASSIC) \
			as FloorDefinition.Shape


## Every floor's pick, 1 to the top, in [param world_seed]. Index 0 is unused.
func _pick_shapes(world_seed: int) -> Array[int]:
	var picks: Array[int] = [FloorDefinition.Shape.CLASSIC]
	var rng := RandomNumberGenerator.new()
	for n in range(1, FloorTuning.TOP_FLOOR + 1):
		var pick := FloorDefinition.Shape.CLASSIC
		if not (AUTHORED.has(n) or n <= 2 or n >= FloorTuning.TOP_FLOOR):
			rng.seed = hash("%d:shape" % seed_in(world_seed, n))
			var roll := rng.randf()
			if roll >= SHAPE_CLASSIC:
				pick = FloorDefinition.Shape.OPEN_FIELD \
						if roll < SHAPE_CLASSIC + (1.0 - SHAPE_CLASSIC) / 2.0 \
						else FloorDefinition.Shape.DUNGEON
			if pick == picks[n - 1]:
				pick = FloorDefinition.Shape.CLASSIC
		picks.append(pick)
	return picks


## Builds floor [param floor_number] -- its [param level], on a dungeon, which is
## several maps; every other floor has one and ignores it.
func build_floor(floor_number: int, level := 1) -> Node2D:
	var definition := get_floor(floor_number)
	if definition.is_authored():
		return definition.authored_scene.instantiate()
	return FloorGenerator.generate(definition, seed_for(floor_number), level)


## How many maps floor [param floor_number] is climbed through: a dungeon's levels,
## or one.
func levels_of(floor_number: int) -> int:
	if get_floor(floor_number).is_authored() \
			or shape_of(floor_number) != FloorDefinition.Shape.DUNGEON:
		return 1
	return FloorTuning.dungeon_levels(floor_number)


func _synthesise(floor_number: int) -> FloorDefinition:
	var definition := FloorDefinition.new()
	definition.floor_number = floor_number
	definition.display_name = ""
	definition.biome = get_biome(floor_number)
	definition.size = FloorTuning.map_size(floor_number)
	definition.labyrinth = FloorTuning.labyrinth_cells(floor_number)
	definition.room_count = FloorTuning.room_count(floor_number)
	definition.chest_count = FloorTuning.chest_count(floor_number)
	definition.boss_name = FloorTuning.boss_name(floor_number)
	definition.enemy_level = FloorTuning.enemy_level(floor_number)
	definition.is_milestone = FloorTuning.is_milestone(floor_number)
	return definition
