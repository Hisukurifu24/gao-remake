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
## world seed -> every floor's modifier, by [method _pick_modifiers].
var _modifiers: Dictionary[int, Array] = {}
## world seed -> every floor's event, by [method _pick_events].
var _events: Dictionary[int, Array] = {}
## world seed -> every floor's landmark, by [method _pick_landmarks].
var _landmarks: Dictionary[int, Array] = {}
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


## Floor [param floor_number]'s modifier ([enum FloorModifier.Kind]) in this world.
## Its own stream, [code]hash("<seed>:modifier")[/code], like the shape's: a floor
## with a modifier is the floor it would be without one, plus what the modifier adds.
##
## About [constant FloorModifier.CHANCE] of generated floors carry one, never the
## authored floors, floor 2 or the top. A storm wants a sky
## ([method FloorModifier.weather_for]) and not a dungeon's roof; a floor that rolls
## one without either is infested instead.
func modifier_of(floor_number: int) -> FloorModifier.Kind:
	if FloorGenerator.modifier_override >= 0:
		return FloorGenerator.modifier_override as FloorModifier.Kind
	return modifier_in(GameState.world_seed, floor_number)


## [method modifier_of] in the world [param world_seed], overrides aside.
func modifier_in(world_seed: int, floor_number: int) -> FloorModifier.Kind:
	if not _modifiers.has(world_seed):
		_modifiers[world_seed] = _pick_modifiers(world_seed)
	return _modifiers[world_seed][clampi(floor_number, 1, FloorTuning.TOP_FLOOR)] as FloorModifier.Kind


## Every floor's modifier, 1 to the top, in [param world_seed]. Index 0 is unused.
func _pick_modifiers(world_seed: int) -> Array[int]:
	var picks: Array[int] = [FloorModifier.Kind.NONE]
	var rng := RandomNumberGenerator.new()
	for n in range(1, FloorTuning.TOP_FLOOR + 1):
		var pick := FloorModifier.Kind.NONE
		if not (AUTHORED.has(n) or n <= 2 or n >= FloorTuning.TOP_FLOOR):
			rng.seed = hash("%d:modifier" % seed_in(world_seed, n))
			if rng.randf() < FloorModifier.CHANCE:
				pick = FloorModifier.Kind.INFESTED if rng.randf() < 0.5 else FloorModifier.Kind.STORM
				if pick == FloorModifier.Kind.STORM and (FloorModifier.weather_for(biome_id(n)) == &""
						or shape_in(world_seed, n) == FloorDefinition.Shape.DUNGEON):
					pick = FloorModifier.Kind.INFESTED
		picks.append(pick)
	return picks


## Floor [param floor_number]'s event ([enum FloorEvents.Kind]) in this world. Its
## own stream, [code]hash("<seed>:event")[/code], like the shape's and the
## modifier's: a floor with an event is the floor it would be without one, plus
## what the event puts down.
##
## About [constant FloorEvents.CHANCE] of the floors that may have one do, and never
## the same kind two floors running. Never an authored floor, floor 2, the top or a
## dungeon (whose seals are what happens on it).
func event_of(floor_number: int) -> FloorEvents.Kind:
	if FloorGenerator.event_override >= 0:
		return FloorGenerator.event_override as FloorEvents.Kind
	return event_in(GameState.world_seed, floor_number)


## [method event_of] in the world [param world_seed], overrides aside.
func event_in(world_seed: int, floor_number: int) -> FloorEvents.Kind:
	if not _events.has(world_seed):
		_events[world_seed] = _pick_events(world_seed)
	return _events[world_seed][clampi(floor_number, 1, FloorTuning.TOP_FLOOR)] as FloorEvents.Kind


## Every floor's event, 1 to the top, in [param world_seed]. Index 0 is unused.
func _pick_events(world_seed: int) -> Array[int]:
	var picks: Array[int] = [FloorEvents.Kind.NONE]
	var rng := RandomNumberGenerator.new()
	var last := FloorEvents.Kind.NONE
	for n in range(1, FloorTuning.TOP_FLOOR + 1):
		var pick := FloorEvents.Kind.NONE
		var shape := shape_in(world_seed, n)
		if not (AUTHORED.has(n) or n <= 2 or n >= FloorTuning.TOP_FLOOR
				or shape == FloorDefinition.Shape.DUNGEON):
			rng.seed = hash("%d:event" % seed_in(world_seed, n))
			if rng.randf() < FloorEvents.CHANCE:
				var kinds: Array[int] = []
				for kind in range(FloorEvents.Kind.FIELD_BOSS, FloorEvents.Kind.size()):
					if kind != last:
						kinds.append(kind)
				pick = kinds[rng.randi() % kinds.size()]
		picks.append(pick)
		last = pick
	return picks


## Floor [param floor_number]'s landmark ([enum FloorLandmarks.Kind]) in this world.
## Its own stream, [code]hash("<seed>:landmark")[/code], like the event's: a floor
## with a landmark is the floor it would be without one, plus the landmark.
##
## About [constant FloorLandmarks.CHANCE] of the floors that may have one do, never
## the same kind two floors running and only a kind the band can draw
## ([method FloorLandmarks.kinds_for]). Never an authored floor, floor 2, the top or a
## dungeon. A pick is what the floor tries first: [FloorLandmarks] falls back to
## another kind where no room fits it.
func landmark_of(floor_number: int) -> FloorLandmarks.Kind:
	if FloorGenerator.landmark_override >= 0:
		return FloorGenerator.landmark_override as FloorLandmarks.Kind
	return landmark_in(GameState.world_seed, floor_number)


## [method landmark_of] in the world [param world_seed], overrides aside.
func landmark_in(world_seed: int, floor_number: int) -> FloorLandmarks.Kind:
	if not _landmarks.has(world_seed):
		_landmarks[world_seed] = _pick_landmarks(world_seed)
	return _landmarks[world_seed][clampi(floor_number, 1, FloorTuning.TOP_FLOOR)] as FloorLandmarks.Kind


## Every floor's landmark, 1 to the top, in [param world_seed]. Index 0 is unused.
func _pick_landmarks(world_seed: int) -> Array[int]:
	var picks: Array[int] = [FloorLandmarks.Kind.NONE]
	var rng := RandomNumberGenerator.new()
	var last := FloorLandmarks.Kind.NONE
	for n in range(1, FloorTuning.TOP_FLOOR + 1):
		var pick := FloorLandmarks.Kind.NONE
		if not (AUTHORED.has(n) or n <= 2 or n >= FloorTuning.TOP_FLOOR
				or shape_in(world_seed, n) == FloorDefinition.Shape.DUNGEON):
			rng.seed = hash("%d:landmark" % seed_in(world_seed, n))
			if rng.randf() < FloorLandmarks.CHANCE:
				var kinds: Array[int] = []
				for kind in FloorLandmarks.kinds_for(biome_id(n)):
					if kind != last:
						kinds.append(kind)
				pick = kinds[rng.randi() % kinds.size()]
		picks.append(pick)
		last = pick
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
