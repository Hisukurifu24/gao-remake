class_name FloorModifier
## A seeded twist on a generated floor, on top of its shape: what gives a floor a
## headline. [method FloorRegistry.modifier_of] decides it per world, on a stream of
## its own, so a floor with a modifier is laid out exactly as it would be without.
##
## - [b]INFESTED[/b]: half as many monsters again ([method FloorTuning.infested_count]),
##   each paying as any monster does -- on top of the floor's count, which is the
##   boss's balance and stays where it is. Placed from [code]hash("<seed>:infested")[/code]
##   after the floor's own, so they move nothing it put down.
## - [b]STORM[/b]: weather over the map -- rain, a blizzard, a sandstorm or falling
##   ash, by band ([constant WEATHER]) -- and monsters notice you from
##   [constant FloorTuning.STORM_NOTICE] as far. A floor for sneaking. Only where a
##   band has a sky to storm under: never the caves, the Ruby Palace or a dungeon.
##
## The words for both live here: the arrival's headline ([method title],
## [method blurb]), what the camp's scout says about it ([method camp_line]), and
## what the map and the gate menu call it.

enum Kind { NONE, INFESTED, STORM }

## The share of generated floors that carry one.
const CHANCE := 0.2

## Each band's weather. A band missing here has no sky over it, and no storm.
const WEATHER := {
	&"meadow": &"rain", &"forest": &"rain", &"ruins": &"rain", &"swamp": &"rain",
	&"sky": &"rain", &"desert": &"sand", &"ice": &"snow", &"volcanic": &"ash",
}
const STORM_NAMES := {
	&"rain": "Rainstorm", &"snow": "Blizzard", &"sand": "Sandstorm", &"ash": "Ashfall",
}
const STORM_BLURBS := {
	&"rain": "The rain covers your steps. Monsters notice you late.",
	&"snow": "The snow hides you. Monsters notice you late.",
	&"sand": "The sand blinds them as well as you. Monsters notice you late.",
	&"ash": "The ash gets in every eye. Monsters notice you late.",
}
## The scout's last word on a floor with a modifier, after their opening.
const STORM_LINES := {
	&"rain": "And this rain hasn't let up since we got here. Can't hear yourself think out there -- but nothing out there can hear you either. They won't see you till you're right on them.",
	&"snow": "And this blizzard... you can't see ten paces. Neither can anything out there. Walk quiet and you'll be past them before they turn round.",
	&"sand": "And this sandstorm hasn't dropped since we got here. Keep your head down. The things out there can't see through it any better than you can.",
	&"ash": "And the ash hasn't stopped falling since we got here. It gets in your eyes -- in theirs too. Nothing out there notices you till you're close.",
}
const INFESTED_LINE := "And keep your blade out. Something's stirred this floor up -- there are monsters everywhere, half as many again as there should be. Good hunting, if it's levels you're after."


## The weather a storm brings to [param biome_id]'s band; empty where it has none.
static func weather_for(biome_id: StringName) -> StringName:
	return WEATHER.get(biome_id, &"")


## What the arrival's headline, the map and the gate menu call [param kind]: a
## storm by its weather.
static func title(kind: int, weather: StringName) -> String:
	match kind:
		Kind.INFESTED:
			return "Infested"
		Kind.STORM:
			return STORM_NAMES.get(weather, "Storm")
	return ""


## The line under the headline.
static func blurb(kind: int, weather: StringName) -> String:
	match kind:
		Kind.INFESTED:
			return "Monsters swarm this floor -- half as many again."
		Kind.STORM:
			return STORM_BLURBS.get(weather, "Monsters notice you late.")
	return ""


## What the camp's scout adds about it, after their opening.
static func camp_line(kind: int, weather: StringName) -> String:
	match kind:
		Kind.INFESTED:
			return INFESTED_LINE
		Kind.STORM:
			return STORM_LINES.get(weather, "")
	return ""


## [param floor_number]'s modifier's name, or empty: the gate menu's and the map's.
static func name_of(floor_number: int) -> String:
	var kind := FloorRegistry.modifier_of(floor_number)
	return title(kind, weather_for(FloorRegistry.biome_id(floor_number)))
