class_name MusicLibrary
## Every piece of music in the game, by id, and which plays where -- all of it
## the Ninja Adventure pack's ([code]assets/ninja_adventure/Audio/Musics/[/code]).
##
## What plays is decided by place first and the fight second ([Audio]): a map
## plays its own track ([member GameMap.music]) or its band's, a labyrinth's
## dark and a safe zone's fire have tracks of their own wherever they are, and a
## fight plays over all of it until it is over. Every track loops (its import
## says so, and the audio test checks it).

const ROOT := "res://assets/ninja_adventure/Audio/Musics/"

const TRACKS := {
	&"title": "1 - Adventure Begin.ogg",
	&"credits": "15 - Credit Theme.ogg",
	&"town": "4 - Village.ogg",
	# The bands, by the floors they climb through.
	&"meadow": "35 - Adventure.ogg",
	&"forest": "37 - Dark Forest.ogg",
	&"cave": "2 - The Cave.ogg",
	&"ruins": "30 - Ruins.ogg",
	&"swamp": "14 - Curse.ogg",
	&"desert": "12 - Temple.ogg",
	&"ice": "22 - Dream.ogg",
	&"volcanic": "28 - Tension.ogg",
	&"sky": "19 - Ascension.ogg",
	&"castle": "10 - Dark Castle.ogg",
	# Places that sound the same on every floor.
	&"labyrinth": "21 - Dungeon.ogg",
	&"safe_zone": "11 - Clearing.ogg",
	# Fights.
	&"fight": "17 - Fight.ogg",
	&"boss": "34  - Fight.ogg",
	&"final_boss": "24 - Final Area.ogg",
}

## Where on a map the player stands, as [GameMap] tells it
## ([signal EventBus.map_area_entered]): out in the open, in a labyrinth's dark,
## or by a safe zone's fire.
const OPEN := &"open"
const DARK := &"dark"
const SAFE := &"safe"

static var _cache: Dictionary[StringName, AudioStream] = {}


static func has(id: StringName) -> bool:
	return TRACKS.has(id)


## Whether [param id] is a fight's: a fight starts its music from the top, where
## a place picks its own up where it was left.
static func is_fight(id: StringName) -> bool:
	return id in [&"fight", &"boss", &"final_boss"]


static func path(id: StringName) -> String:
	return ROOT + str(TRACKS[id]) if TRACKS.has(id) else ""


static func stream(id: StringName) -> AudioStream:
	if not TRACKS.has(id):
		return null
	if not _cache.has(id):
		_cache[id] = load(path(id)) as AudioStream
	return _cache[id]


## What plays on a map of [param floor_number] whose own track is [param own]
## (empty for its band's), with the player standing in [param area]. A dark and
## a fire sound alike on every floor; the open sounds like the map or its band.
static func for_place(floor_number: int, own: StringName, area: StringName) -> StringName:
	if area == SAFE:
		return &"safe_zone"
	if area == DARK:
		return &"labyrinth"
	if not own.is_empty():
		return own
	return band_track(floor_number)


## The band's track: its biome's id. Off the tower (floor 0), the town's.
static func band_track(floor_number: int) -> StringName:
	if floor_number <= 0:
		return &"town"
	for band in FloorRegistry.BIOME_BANDS:
		if floor_number <= int(band["through"]):
			return StringName(band["biome"])
	return &"castle"


## The fight's track: a boss's -- the last one's on the top floor -- or a plain fight's.
static func for_fight(encounter: Encounter) -> StringName:
	if encounter == null or not encounter.is_boss:
		return &"fight"
	if encounter.floor_number >= FloorTuning.TOP_FLOOR:
		return &"final_boss"
	return &"boss"
