class_name SoundLibrary
## Every sound effect and jingle in the game, by id -- all of them the Ninja
## Adventure pack's own ([code]assets/ninja_adventure/Audio/[/code]).
##
## The game names a sound ([code]Audio.play(&"chest")[/code]); this table says
## which file that is and how loud. A sound with several files picks one each
## time, so a run of hits doesn't ring like one bell, and [code]spread[/code]
## detunes it a little each time for the same reason. [code]db[/code] evens the
## pack's levels out against each other: its alerts are loud and its menu ticks
## quiet. A [code]jingle[/code] is a short tune, not a sound: one at a time, in
## turn, with the music ducked under it ([method Audio.play]).
##
## The audio test fails on an id the game asks for that isn't here -- every
## [code]Audio.play(&"...")[/code] in the scripts and every [member SkillFx.sound]
## -- and on a file that isn't there: a missing sound is silent, and nothing else
## would say so.

const ROOT := "res://assets/ninja_adventure/Audio/"

const SOUNDS := {
	# --- menus ---------------------------------------------------------------
	&"move": {"files": ["Sounds/Menu/Move1.wav"], "db": -10.0},
	&"accept": {"files": ["Sounds/Menu/Accept.wav"], "db": -6.0},
	&"cancel": {"files": ["Sounds/Menu/Cancel.wav"], "db": -6.0},
	## Asked for something the screen won't do: a greyed row, a full bag.
	&"refuse": {"files": ["Sounds/Menu/Cancel2.wav"], "db": -6.0},
	&"tab": {"files": ["Sounds/Menu/Move3.wav"], "db": -8.0},
	&"open": {"files": ["Sounds/Menu/Menu10.wav"], "db": -8.0},
	&"close": {"files": ["Sounds/Menu/Menu11.wav"], "db": -8.0},
	## The next page of a conversation.
	&"advance": {"files": ["Sounds/Menu/Move5.wav"], "db": -12.0},
	&"save": {"files": ["Sounds/Menu/Menu12.wav"], "db": -6.0},
	&"buy": {"files": ["Sounds/Bonus/Coin.wav"], "db": -6.0},
	&"equip": {"files": ["Sounds/Whoosh & Slash/Sword2.wav"], "db": -8.0},
	&"drop": {"files": ["Sounds/Jump & Bounce/Bounce3.wav"], "db": -8.0},
	&"forge": {"files": ["Sounds/Bonus/PowerUp1.wav"], "db": -6.0},
	&"forge_failed": {"files": ["Sounds/Hit & Impact/Impact.wav"], "db": -6.0},

	# --- the world -------------------------------------------------------------
	&"coin": {"files": ["Sounds/Bonus/Coin3.wav"], "db": -8.0},
	&"chest": {"files": ["Sounds/Bonus/Bonus.wav"], "db": -6.0},
	&"chest_gilded": {"files": ["Sounds/Bonus/Gold1.wav"], "db": -6.0},
	&"heal": {"files": ["Sounds/Magic & Skill/Heal2.wav"], "db": -6.0},
	&"rest": {"files": ["Sounds/Magic & Skill/Heal.wav"], "db": -4.0},
	## A monster has seen you.
	&"notice": {"files": ["Sounds/Alert/Alert.wav"], "db": -14.0},
	&"alarm": {"files": ["Sounds/Alert/Alert3.wav"], "db": -6.0},
	&"warp": {"files": ["Sounds/Magic & Skill/Spirit.wav"], "db": -6.0},
	&"fire": {"files": ["Sounds/Elemental/Fire.wav"], "db": -6.0},
	&"stone": {"files": ["Sounds/Hit & Impact/Impact3.wav"], "db": -6.0},
	&"crumble": {"files": ["Sounds/Elemental/Explosion2.wav"], "db": -6.0},
	&"unseal": {"files": ["Sounds/Hit & Impact/Impact5.wav"], "db": -4.0},
	&"waystone": {"files": ["Sounds/Magic & Skill/Magic3.wav"], "db": -6.0},
	&"lever": {"files": ["Sounds/Jump & Bounce/Bounce2.wav"], "db": -6.0},
	&"wisp": {"files": ["Sounds/Magic & Skill/Fx.wav"], "db": -8.0},
	&"read": {"files": ["Sounds/Menu/Menu8.wav"], "db": -10.0},
	&"boss_appears": {"files": ["Sounds/Magic & Skill/Strange.wav"], "db": -4.0},
	## Idle in a marathon: the last seconds before Cardinal logs you out.
	&"countdown": {"files": ["Sounds/Alert/Alert6.wav"], "db": -10.0},
	&"shatter": {"files": ["Sounds/Elemental/Explosion6.wav"], "db": -4.0},

	# --- a fight ----------------------------------------------------------------
	&"slash": {"files": ["Sounds/Whoosh & Slash/Slash.wav", "Sounds/Whoosh & Slash/Slash2.wav",
			"Sounds/Whoosh & Slash/Slash3.wav"], "db": -6.0, "spread": 0.08},
	&"slash_heavy": {"files": ["Sounds/Whoosh & Slash/Slash4.wav",
			"Sounds/Whoosh & Slash/Slash5.wav"], "db": -6.0, "spread": 0.08},
	&"claw": {"files": ["Sounds/Hit & Impact/Hit1.wav", "Sounds/Hit & Impact/Hit2.wav"],
			"db": -6.0, "spread": 0.08},
	&"hit": {"files": ["Sounds/Hit & Impact/Hit5.wav", "Sounds/Hit & Impact/Hit6.wav",
			"Sounds/Hit & Impact/Hit7.wav"], "db": -6.0, "spread": 0.08},
	&"crit": {"files": ["Sounds/Hit & Impact/Impact2.wav"], "db": -4.0},
	&"miss": {"files": ["Sounds/Whoosh & Slash/Whoosh.wav", "Sounds/Whoosh & Slash/Whoosh2.wav"],
			"db": -8.0},
	&"guard": {"files": ["Sounds/Jump & Bounce/Bounce.wav"], "db": -8.0},
	&"flame": {"files": ["Sounds/Elemental/Fireball.wav", "Sounds/Elemental/Fire2.wav"], "db": -6.0},
	&"blast": {"files": ["Sounds/Elemental/Explosion.wav"], "db": -6.0},
	&"quake": {"files": ["Sounds/Elemental/Explosion3.wav"], "db": -6.0},
	&"spell": {"files": ["Sounds/Magic & Skill/Magic1.wav", "Sounds/Magic & Skill/Magic2.wav"],
			"db": -6.0},
	&"aura": {"files": ["Sounds/Magic & Skill/Magic4.wav"], "db": -6.0},
	&"spirit": {"files": ["Sounds/Magic & Skill/Spirit.wav"], "db": -6.0},
	&"sparkle": {"files": ["Sounds/Magic & Skill/Heal3.wav"], "db": -6.0},
	&"frost": {"files": ["Sounds/Magic & Skill/Magic5.wav"], "db": -6.0},
	&"thunder": {"files": ["Sounds/Elemental/Explosion5.wav"], "db": -6.0},
	## Hisukurifu's Explosion, under the screen going white.
	&"explosion_spell": {"files": ["Sounds/Elemental/Explosion6.wav"], "db": -2.0},
	&"punch": {"files": ["Sounds/Hit & Impact/Hit3.wav", "Sounds/Hit & Impact/Hit8.wav"],
			"db": -6.0, "spread": 0.08},
	&"kick": {"files": ["Sounds/Hit & Impact/Impact4.wav"], "db": -6.0},
	## A poison's or a bleed's tick.
	&"hurt": {"files": ["Sounds/Elemental/Bubble.wav"], "db": -10.0},
	## A monster going up in smoke.
	&"fall": {"files": ["Sounds/Hit & Impact/Hit9.wav"], "db": -6.0},
	&"flee": {"files": ["Sounds/Jump & Bounce/Jump.wav"], "db": -6.0},
	## A boss's HP bar breaking, and the next phase beginning.
	&"bar_break": {"files": ["Sounds/Elemental/Explosion4.wav"], "db": -4.0},

	# --- jingles ----------------------------------------------------------------
	&"victory": {"files": ["Jingles/Success1.wav"], "db": -4.0, "jingle": true},
	&"boss_victory": {"files": ["Jingles/Success3.wav"], "db": -2.0, "jingle": true},
	&"defeat": {"files": ["Jingles/GameOver.wav"], "db": -4.0, "jingle": true},
	&"level_up": {"files": ["Jingles/LevelUp1.wav"], "db": -4.0, "jingle": true},
	&"secret": {"files": ["Jingles/Secret1.wav"], "db": -4.0, "jingle": true},
	&"solved": {"files": ["Jingles/Secret2.wav"], "db": -4.0, "jingle": true},
	&"quest_accepted": {"files": ["Jingles/Success4.wav"], "db": -6.0, "jingle": true},
	&"quest_done": {"files": ["Jingles/Success2.wav"], "db": -4.0, "jingle": true},
	&"logged_out": {"files": ["Jingles/GameOver2.wav"], "db": -4.0, "jingle": true},
	&"game_clear": {"files": ["Jingles/Secret4.wav"], "db": -2.0, "jingle": true},
}

static var _cache: Dictionary[String, AudioStream] = {}


static func has(id: StringName) -> bool:
	return SOUNDS.has(id)


static func is_jingle(id: StringName) -> bool:
	return bool(SOUNDS.get(id, {}).get("jingle", false))


static func volume_db(id: StringName) -> float:
	return float(SOUNDS.get(id, {}).get("db", 0.0))


## How far either way [param id]'s pitch may wander, as a share of it.
static func pitch_spread(id: StringName) -> float:
	return float(SOUNDS.get(id, {}).get("spread", 0.0))


## Every file [param id] may play, as paths.
static func paths(id: StringName) -> PackedStringArray:
	var found := PackedStringArray()
	for file in SOUNDS.get(id, {}).get("files", []):
		found.append(ROOT + str(file))
	return found


## One of [param id]'s files, loaded -- picked at random where there are
## several (behaviour, not generation: no seed cares which hit rang). Null for
## an id that isn't here.
static func stream(id: StringName) -> AudioStream:
	var all := paths(id)
	if all.is_empty():
		return null
	return _load(all[randi() % all.size()])


static func _load(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) as AudioStream
	return _cache[path]
