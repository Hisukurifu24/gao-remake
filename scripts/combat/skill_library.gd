class_name SkillLibrary
## The player's sword skills, and the plain attack everyone shares.
##
## Listed explicitly rather than scanned from the directory: res:// listing is
## unreliable in exported builds, same reason [constant FloorRegistry.AUTHORED]
## is a dictionary. Adding a skill is a .tres plus one line here.
##
## Which skills the player has is a pure function of their level -- there is no
## learn-a-skill state to save yet. When M5 adds skill trees this becomes a
## lookup against [GameState] and nothing else has to change.

const BASIC_ATTACK := "res://resources/skills/strike.tres"

const PLAYER_SKILLS: PackedStringArray = [
	"res://resources/skills/slant.tres",
	"res://resources/skills/horizontal_arc.tres",
	"res://resources/skills/sonic_leap.tres",
	"res://resources/skills/vorpal_strike.tres",
	"res://resources/skills/second_wind.tres",
]

static var _basic: Skill = null
static var _all: Array[Skill] = []


## The swing available to everyone, every turn, forever. Enemies with no skills
## of their own fight entirely with this.
static func basic_attack() -> Skill:
	if _basic == null:
		_basic = load(BASIC_ATTACK)
	return _basic


## Every player skill, in the order they unlock.
static func all() -> Array[Skill]:
	if _all.is_empty():
		for path in PLAYER_SKILLS:
			var skill: Skill = load(path)
			if skill == null:
				push_error("SkillLibrary: missing skill at %s" % path)
				continue
			_all.append(skill)
		_all.sort_custom(func(a: Skill, b: Skill) -> bool:
			return a.unlock_level < b.unlock_level)
	return _all


## The skills a player of [param level] knows. Excludes the plain attack, which
## is not a choice -- see [method Combatant.usable_skills].
static func for_level(level: int) -> Array[Skill]:
	var known: Array[Skill] = []
	for skill in all():
		if skill.unlock_level <= level:
			known.append(skill)
	return known


static func get_skill(id: StringName) -> Skill:
	if basic_attack().id == id:
		return basic_attack()
	for skill in all():
		if skill.id == id:
			return skill
	return null


## The level at which [param id] becomes available, or -1 if it never does.
## Lets dialogue and the UI say "at level 8" without hard-coding the table.
static func unlock_level_of(id: StringName) -> int:
	var skill := get_skill(id)
	return skill.unlock_level if skill != null else -1
