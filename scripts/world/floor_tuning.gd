class_name FloorTuning
## The 100-floor difficulty and size curve, in one place.
##
## Every generated floor derives its parameters from its number, so balancing
## the whole game means tuning these functions -- not 100 hand-edited files.

const TOP_FLOOR := 100

## What an ordinary monster carries in Col, at level 1 and per level after:
## [EnemyType]'s defaults. Linear, like XP -- see [method EnemyType.col_at].
const KILL_COL := 6
const KILL_COL_GROWTH := 2.0
## A chest's Col, in kills of its floor: plain, gilded, sealed. The sealed chest is
## a solved puzzle and pays the most; the gilded one is a gamble and pays for it.
const CHEST_COL_KILLS: Array[float] = [3.0, 6.0, 15.0]

## Boss names are assembled rather than authored: 10 affixes x 10 archetypes is
## plenty of variety for the ~88 generated floors. Milestone floors override it.
const BOSS_AFFIXES: PackedStringArray = [
	"Bellicose", "Frost-Clad", "Ember", "Venomous", "Radiant",
	"Shattered", "Abyssal", "Storm-Born", "Gilded", "Pale",
]
const BOSS_ARCHETYPES: PackedStringArray = [
	"Gigas", "Kobold Lord", "Nepent Sovereign", "Lizardman General", "Wraith",
	"Golem", "Chimera", "Drake", "Executioner", "Sentinel",
]


static func enemy_level(floor_number: int) -> int:
	# Roughly level 120 by the top floor, so a fully-cleared player is never
	# more than a handful of levels ahead of the curve.
	return maxi(1, roundi(floor_number * 1.2))


## A boss outranks its floor, but by a share of the climb rather than a flat
## bonus: +3 levels is a rounding error on floor 90 and an unwinnable wall on
## floor 2, where the player has barely any levels to be three behind.
static func boss_level(floor_number: int) -> int:
	return enemy_level(floor_number) + 1 + floor_number / 20


## The field: the rooms and corridors you arrive in. Grows slowly: floor 1 is
## 50x38, floor 100 is 75x54. The labyrinth is built onto one side of it, so a
## generated map is bigger than this by [method labyrinth_cells]' footprint.
static func map_size(floor_number: int) -> Vector2i:
	return Vector2i(50 + floor_number / 4, 38 + floor_number / 6)


## The labyrinth in front of the boss room, in maze cells (each is four tiles
## square: a two-wide passage and a two-thick wall). Floor 2 is 12x7 -- 50x30
## tiles, two and a half screens each way -- and floor 100 is 20x12. It is what
## the walk to the door is made of. The first cut (6x4) fitted on barely more than
## one screen, and a maze you can read from outside is a corridor with extra
## steps -- see M5.5 §5 in plan.md.
static func labyrinth_cells(floor_number: int) -> Vector2i:
	return Vector2i(12 + floor_number / 12, 7 + floor_number / 20)


## The Col an ordinary monster on [param floor_number] carries.
static func kill_col(floor_number: int) -> int:
	return EnemyType.stat_at(KILL_COL, KILL_COL_GROWTH, enemy_level(maxi(1, floor_number)))


## What a chest on [param floor_number] holds in Col beside its item. [param tier]
## is 0 plain, 1 gilded, 2 sealed. Read off the floor rather than rolled, so
## adding Col to chests drew nothing from any floor's rng.
static func chest_col(floor_number: int, tier: int) -> int:
	return roundi(kill_col(floor_number) * CHEST_COL_KILLS[clampi(tier, 0, 2)])


## An open field's field ([enum FloorDefinition.Shape]): with no labyrinth to walk,
## the field is the floor, so it takes about the ground the maze would have --
## 65x49 on floor 2 where a classic floor is 50x38 plus a 50x30 maze. The arena
## stands on one side of it, like the labyrinth.
static func open_field_size(floor_number: int) -> Vector2i:
	return Vector2i(roundi(map_size(floor_number).x * 1.3), roundi(map_size(floor_number).y * 1.3))


## A dungeon's levels ([enum FloorDefinition.Shape]): three low down, four from
## floor 40, five from floor 80. The boss is on the top one.
static func dungeon_levels(floor_number: int) -> int:
	return clampi(3 + floor_number / 40, 3, 5)


## A dungeon level's rooms and corridors, before the stair chamber is built onto a
## side of it -- about a view and three-quarters across, two down, on floor 2 (34x24),
## and 46x32 near the top. A level is small; the floor is its levels.
static func dungeon_level_size(floor_number: int) -> Vector2i:
	return Vector2i(34 + floor_number / 8, 24 + floor_number / 12)


## Rooms on each of a dungeon's levels below the top.
static func dungeon_room_count(floor_number: int) -> int:
	return clampi(4 + floor_number / 30, 4, 7)


static func room_count(floor_number: int) -> int:
	return clampi(6 + floor_number / 8, 6, 18)


## An open field's clearings: half as many again as a classic field's rooms, over
## the bigger field, so the walk between them is about as long.
static func open_room_count(floor_number: int) -> int:
	return room_count(floor_number) * 3 / 2


static func chest_count(floor_number: int) -> int:
	return clampi(2 + floor_number / 12, 2, 10)


## Roaming monsters standing on the floor. Eight is not decoration -- it is the
## measured number of kills that puts a player at the level their floor boss
## expects, so a floor that ships fewer is a floor that cannot be cleared
## without backtracking.
static func monster_count(floor_number: int) -> int:
	return clampi(8 + floor_number / 10, 8, 16)


static func boss_name(floor_number: int) -> String:
	# Deterministic: floor 37's boss is always floor 37's boss. The two indices
	# are mixed on different strides so they don't cycle in lockstep -- this
	# pairing yields 100 distinct names across 100 floors.
	var affix := BOSS_AFFIXES[(floor_number * 3) % BOSS_AFFIXES.size()]
	return "%s %s" % [affix, boss_archetype(floor_number)]


## The archetype half of the name. Split out because it is also what decides
## which monster template actually shows up -- see [constant Bestiary.BOSS_TEMPLATES].
static func boss_archetype(floor_number: int) -> String:
	return BOSS_ARCHETYPES[(floor_number / 10 + floor_number * 7) % BOSS_ARCHETYPES.size()]


## Milestone floors are the hand-authored ones. They exist as .tres files in
## resources/floors/; this is the intended schedule so the bands stay readable.
static func is_milestone(floor_number: int) -> bool:
	return floor_number in [1, 10, 25, 40, 50, 60, 74, 80, 90, 100]
