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

var _floors: Dictionary[int, FloorDefinition] = {}
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
	return hash("%d:%d" % [GameState.world_seed, floor_number])


func build_floor(floor_number: int) -> Node2D:
	var definition := get_floor(floor_number)
	if definition.is_authored():
		return definition.authored_scene.instantiate()
	return FloorGenerator.generate(definition, seed_for(floor_number))


func _synthesise(floor_number: int) -> FloorDefinition:
	var definition := FloorDefinition.new()
	definition.floor_number = floor_number
	definition.display_name = ""
	definition.biome = get_biome(floor_number)
	definition.size = FloorTuning.map_size(floor_number)
	definition.room_count = FloorTuning.room_count(floor_number)
	definition.chest_count = FloorTuning.chest_count(floor_number)
	definition.boss_name = FloorTuning.boss_name(floor_number)
	definition.enemy_level = FloorTuning.enemy_level(floor_number)
	definition.is_milestone = FloorTuning.is_milestone(floor_number)
	return definition
