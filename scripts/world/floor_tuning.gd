class_name FloorTuning
## The 100-floor difficulty and size curve, in one place.
##
## Every generated floor derives its parameters from its number, so balancing
## the whole game means tuning these functions -- not 100 hand-edited files.

const TOP_FLOOR := 100

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


static func map_size(floor_number: int) -> Vector2i:
	# Grows slowly: floor 1 is 50x38, floor 100 is 75x54.
	return Vector2i(50 + floor_number / 4, 38 + floor_number / 6)


static func room_count(floor_number: int) -> int:
	return clampi(6 + floor_number / 8, 6, 18)


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
