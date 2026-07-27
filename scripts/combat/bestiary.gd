class_name Bestiary
## What lives on floor N, and what is waiting at the end of it.
##
## Ten templates cover a hundred floors. A monster's numbers come from its level
## ([method EnemyType.stat_at]) and its level comes from [FloorTuning], so the
## bestiary itself is just a routing table: biome band to a pool of trash,
## boss archetype to the template that plays it.
##
## Boss composition is deterministic, exactly like the floors themselves --
## floor 63's boss is the same monster, at the same level, with the same escorts,
## every time. Fights that reshuffle can't be balanced and can't be reported.

const ENEMY_PATH := "res://resources/enemies/%s.tres"

## Every template, listed explicitly (see [SkillLibrary] for why).
const ENEMIES: PackedStringArray = [
	"frenzy_boar", "dire_wolf", "little_nepent", "kobold_trooper", "cave_bat",
	"ruin_wraith", "lizardman_soldier", "stone_golem", "ember_drake", "illfang",
]

## Which monsters roam which biome band. Order matters: the first entry is the
## band's rank-and-file and the one bosses take as an escort.
const BIOME_POOLS := {
	&"meadow": [&"frenzy_boar", &"little_nepent"],
	&"forest": [&"dire_wolf", &"little_nepent"],
	&"cave": [&"cave_bat", &"kobold_trooper"],
	&"ruins": [&"kobold_trooper", &"ruin_wraith"],
	&"swamp": [&"little_nepent", &"lizardman_soldier"],
	&"desert": [&"lizardman_soldier", &"frenzy_boar"],
	&"ice": [&"stone_golem", &"dire_wolf"],
	&"volcanic": [&"ember_drake", &"stone_golem"],
	&"sky": [&"cave_bat", &"ruin_wraith"],
	&"castle": [&"ruin_wraith", &"ember_drake", &"stone_golem"],
}

## [constant FloorTuning.BOSS_ARCHETYPES] to the template that plays it. Every
## archetype must appear here or generated floors lose their boss.
const BOSS_TEMPLATES := {
	"Gigas": &"stone_golem",
	"Kobold Lord": &"kobold_trooper",
	"Nepent Sovereign": &"little_nepent",
	"Lizardman General": &"lizardman_soldier",
	"Wraith": &"ruin_wraith",
	"Golem": &"stone_golem",
	"Chimera": &"dire_wolf",
	"Drake": &"ember_drake",
	"Executioner": &"lizardman_soldier",
	"Sentinel": &"kobold_trooper",
}

## Milestone floors whose boss is a character rather than an archetype.
const AUTHORED_BOSSES := {
	1: &"illfang",
}

## What being the floor boss is worth on top of the template's own numbers.
const BOSS_HP := 3.0
const BOSS_ATTACK := 1.2
const BOSS_DEFENSE := 1.15
const BOSS_POISE := 2.5
const BOSS_XP := 4.0
## Every generated boss gets this on top of its template's skills.
const BOSS_SKILL := "res://resources/skills/enemy/rampage.tres"

static var _cache: Dictionary[StringName, EnemyType] = {}


static func get_enemy(id: StringName) -> EnemyType:
	if _cache.has(id):
		return _cache[id]
	var path := ENEMY_PATH % id
	if not ResourceLoader.exists(path):
		push_error("Bestiary: no such enemy '%s'" % id)
		return null
	var type: EnemyType = load(path)
	_cache[id] = type
	return type


## The monsters that roam [param floor_number], strongest-first is not implied --
## the pool is a set, not a ranking.
## Whether [param id] names a template at all, without the error [method get_enemy]
## raises. For validating content that points at enemies by id -- a
## [QuestObjective]'s KILL target -- where a missing one is a question, not a bug.
static func exists(id: StringName) -> bool:
	return id != &"" and ResourceLoader.exists(ENEMY_PATH % id)


static func pool_for_floor(floor_number: int) -> Array[EnemyType]:
	var biome := FloorRegistry.biome_id(floor_number)
	var types: Array[EnemyType] = []
	for id in BIOME_POOLS.get(biome, BIOME_POOLS[&"meadow"]):
		var type := get_enemy(id)
		if type != null:
			types.append(type)
	return types


## The fight one monster standing on the map is worth.
static func single_encounter(type: EnemyType, at_level: int, floor_number := 0) -> Encounter:
	var encounter := Encounter.new()
	encounter.id = StringName("roam_%s" % type.id)
	encounter.display_name = type.label()
	encounter.enemies = [type]
	encounter.level = maxi(1, at_level)
	encounter.floor_number = floor_number
	encounter.backdrop = _backdrop(maxi(1, floor_number))
	return encounter


## A roaming fight for [param floor_number]. Seeded by the caller so a monster
## placed on the map always leads to the same battle.
static func random_encounter(floor_number: int, rng: RandomNumberGenerator) -> Encounter:
	var pool := pool_for_floor(floor_number)
	if pool.is_empty():
		return null

	var encounter := Encounter.new()
	encounter.id = StringName("floor_%d_roam" % floor_number)
	encounter.level = FloorTuning.enemy_level(floor_number)
	encounter.floor_number = floor_number
	encounter.backdrop = _backdrop(floor_number)
	# One enemy low down, up to three once the player has a party's worth of
	# skills to spend on them.
	var count := rng.randi_range(1, clampi(1 + floor_number / 15, 1, 3))
	for i in count:
		encounter.enemies.append(pool[rng.randi() % pool.size()])
	encounter.display_name = encounter.enemies[0].label() if count == 1 else "Ambush"
	return encounter


## The fight behind the labyrinth door. Authored floors override the template
## and the name; everything else is assembled from the archetype.
static func boss_encounter(floor_number: int) -> Encounter:
	floor_number = clampi(floor_number, 1, FloorTuning.TOP_FLOOR)
	var definition := FloorRegistry.get_floor(floor_number)

	var template := _boss_template(floor_number)
	if template == null:
		push_error("Bestiary: no boss template for floor %d" % floor_number)
		return null

	var encounter := Encounter.new()
	encounter.id = StringName("floor_%d_boss" % floor_number)
	encounter.level = FloorTuning.boss_level(floor_number)
	encounter.floor_number = floor_number
	encounter.is_boss = true
	encounter.can_flee = false
	encounter.backdrop = _backdrop(floor_number)
	encounter.boss_name = definition.boss_name if not definition.boss_name.is_empty() \
			else FloorTuning.boss_name(floor_number)
	encounter.display_name = encounter.boss_name
	encounter.enemies.append(template)

	var escort := _escort_for(floor_number)
	if escort != null:
		for i in _escort_count(floor_number):
			encounter.enemies.append(escort)
	return encounter


## Turns a template into the actual boss: bigger, meaner, and worth the climb.
## Escorts stay ordinary, which is what makes the boss read as the boss.
static func build_boss(template: EnemyType, at_level: int, boss_name: String) -> Combatant:
	var boss := Combatant.from_enemy(template, at_level, boss_name)
	boss.max_hp = roundi(boss.max_hp * BOSS_HP)
	boss.hp = boss.max_hp
	boss.attack = roundi(boss.attack * BOSS_ATTACK)
	boss.defense = roundi(boss.defense * BOSS_DEFENSE)
	boss.max_poise = roundi(boss.max_poise * BOSS_POISE)
	boss.poise = boss.max_poise
	boss.xp_reward = roundi(boss.xp_reward * BOSS_XP)
	if ResourceLoader.exists(BOSS_SKILL):
		var rampage: Skill = load(BOSS_SKILL)
		if rampage not in boss.skills:
			boss.skills.append(rampage)
	return boss


static func _boss_template(floor_number: int) -> EnemyType:
	if AUTHORED_BOSSES.has(floor_number):
		return get_enemy(AUTHORED_BOSSES[floor_number])
	var archetype := FloorTuning.boss_archetype(floor_number)
	if not BOSS_TEMPLATES.has(archetype):
		push_error("Bestiary: archetype '%s' has no template" % archetype)
		return null
	return get_enemy(BOSS_TEMPLATES[archetype])


## Illfang brings a Ruin Kobold Sentinel; from the middle of the tower every
## boss brings one of whatever its band is full of.
##
## Capped at one on purpose. Against a party of one, a second full-strength
## escort stops being a complication and becomes an attrition race the player
## cannot win -- measured at roughly 1 win in 20 on floor 100. It can go up when
## the party does (M6).
static func _escort_count(floor_number: int) -> int:
	if floor_number == 1:
		return 1
	return mini(1, (floor_number - 1) / 45)


static func _escort_for(floor_number: int) -> EnemyType:
	if _escort_count(floor_number) <= 0:
		return null
	var pool := pool_for_floor(floor_number)
	return pool[0] if not pool.is_empty() else null


## The battle backdrop, tinted by the floor's biome so a cave fight doesn't look
## like a sky-garden fight.
static func _backdrop(floor_number: int) -> Color:
	var biome := FloorRegistry.get_biome(floor_number)
	var base := Color(0.10, 0.11, 0.17)
	return base * biome.ambient_tint if biome != null else base
