class_name Combatant
extends RefCounted
## One fighter for the length of one battle.
##
## The runtime counterpart to [EnemyType] and to the player's numbers in
## [GameState]: it holds current HP, poise, cooldowns and statuses, none of
## which should outlive the fight. [method write_back] is the only path from
## here into persistent state, and only the player uses it.
##
## Stats are read through the [code]effective_*[/code] methods, never directly,
## so a status effect applies everywhere at once.

## The three-quarters mark of an enemy's poise is enough to stagger it in two
## heavy hits; a plain attack takes several.
const STAGGER_RECOVERY := 0.6

## A [StatusEffect] currently riding on a combatant, with its remaining turns.
class Active extends RefCounted:
	var effect: StatusEffect
	var turns: int

	func _init(from: StatusEffect) -> void:
		effect = from
		turns = from.duration

var display_name := "Combatant"
var is_player := false
## Set for enemies; used for [signal EventBus.enemy_defeated] and loot.
var source: EnemyType = null
var battler: Texture2D = null

var level := 1
var max_hp := 1
var hp := 1
var attack := 1
var defense := 0
var speed := 1
var max_poise := 30
var poise := 30

var skills: Array[Skill] = []
var xp_reward := 0
var loot: Array[StringName] = []
var loot_chance := 0.0

## Turns remaining before each skill id can be used again.
var cooldowns: Dictionary[StringName, int] = {}
var statuses: Array[Active] = []
## Set by Defend, cleared at the start of the next turn.
var defending := false
## Turns of post-motion vulnerability left over from a heavy skill.
var post_motion := 0
## Set when poise runs out: the next turn is lost and damage taken goes up.
var staggered := false


static func from_enemy(type: EnemyType, at_level: int, override_name := "") -> Combatant:
	var c := Combatant.new()
	c.display_name = override_name if not override_name.is_empty() else type.label()
	c.source = type
	c.battler = type.battler
	c.level = at_level
	c.max_hp = type.hp_at(at_level)
	c.hp = c.max_hp
	c.attack = type.attack_at(at_level)
	c.defense = type.defense_at(at_level)
	c.speed = type.speed_at(at_level)
	c.max_poise = type.poise_at(at_level)
	c.poise = c.max_poise
	c.skills = type.skills.duplicate()
	c.xp_reward = type.xp_at(at_level)
	c.loot = type.loot.duplicate()
	c.loot_chance = type.loot_chance
	return c


## The player as they stand in [GameState] right now. HP carries into the
## fight and back out of it -- there is no free heal at the door.
static func from_player() -> Combatant:
	var c := Combatant.new()
	c.display_name = GameState.player_name
	c.is_player = true
	c.level = GameState.level
	c.max_hp = GameState.max_hp
	c.hp = GameState.hp
	c.attack = GameState.attack
	c.defense = GameState.defense
	c.speed = GameState.speed
	c.max_poise = GameState.max_poise()
	c.poise = c.max_poise
	c.skills = SkillLibrary.for_level(GameState.level)
	return c


## Pushes the fight's outcome back into persistent state. Only ever called for
## the player, and only once, by [CombatManager].
func write_back() -> void:
	if is_player:
		GameState.set_hp(hp)


# --- state -----------------------------------------------------------------

func is_alive() -> bool:
	return hp > 0


func hp_ratio() -> float:
	return float(hp) / float(maxi(1, max_hp))


func poise_ratio() -> float:
	return float(poise) / float(maxi(1, max_poise))


func effective_attack() -> int:
	return maxi(1, roundi(attack * _stat_multiplier(StatusEffect.Kind.ATTACK_MOD)))


func effective_defense() -> int:
	return maxi(0, roundi(defense * _stat_multiplier(StatusEffect.Kind.DEFENSE_MOD)))


func effective_speed() -> int:
	return maxi(1, roundi(speed * _stat_multiplier(StatusEffect.Kind.SPEED_MOD)))


## Loses its turn this round: stunned by a status, or reeling from a stagger.
func is_incapacitated() -> bool:
	return staggered or has_status_kind(StatusEffect.Kind.STUN)


# --- damage ----------------------------------------------------------------

func take_damage(amount: int) -> int:
	var dealt := mini(amount, hp)
	hp = maxi(0, hp - amount)
	if hp == 0:
		# Dying clears the reeling state so a corpse never reports as staggered.
		staggered = false
		statuses.clear()
	return dealt


func heal(amount: int) -> int:
	var before := hp
	hp = mini(max_hp, hp + maxi(0, amount))
	return hp - before


## Chips away at poise. Returns true on the hit that breaks it.
func take_stagger(amount: int) -> bool:
	if amount <= 0 or staggered or not is_alive():
		return false
	poise = maxi(0, poise - amount)
	if poise > 0:
		return false
	staggered = true
	return true


## Called when the stagger has been paid for with a lost turn.
func recover_from_stagger() -> void:
	staggered = false
	poise = roundi(max_poise * STAGGER_RECOVERY)


# --- statuses --------------------------------------------------------------

## Re-applying refreshes rather than stacks -- see [StatusEffect].
func apply_status(effect: StatusEffect) -> void:
	if effect == null or not is_alive():
		return
	for active in statuses:
		if active.effect.id == effect.id:
			active.turns = maxi(active.turns, effect.duration)
			return
	statuses.append(Active.new(effect))


func has_status(id: StringName) -> bool:
	for active in statuses:
		if active.effect.id == id:
			return true
	return false


func has_status_kind(kind: StatusEffect.Kind) -> bool:
	for active in statuses:
		if active.effect.kind == kind:
			return true
	return false


func status_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	for active in statuses:
		labels.append("%s %d" % [active.effect.label(), active.turns])
	return labels


## Ages every status by one turn and drops the expired ones. Returns the net HP
## change from damage- and heal-over-time, negative for damage.
func tick_statuses() -> int:
	var delta := 0
	var survivors: Array[Active] = []
	for active in statuses:
		match active.effect.kind:
			StatusEffect.Kind.DAMAGE_OVER_TIME:
				delta -= take_damage(active.effect.tick_amount(max_hp))
			StatusEffect.Kind.HEAL_OVER_TIME:
				delta += heal(active.effect.tick_amount(max_hp))
		active.turns -= 1
		if active.turns > 0 and is_alive():
			survivors.append(active)
	statuses = survivors
	return delta


# --- cooldowns -------------------------------------------------------------

func is_ready(skill: Skill) -> bool:
	return skill != null and cooldowns.get(skill.id, 0) <= 0


func cooldown_left(skill: Skill) -> int:
	return cooldowns.get(skill.id, 0) if skill != null else 0


func start_cooldown(skill: Skill) -> void:
	if skill != null and skill.cooldown > 0:
		cooldowns[skill.id] = skill.cooldown


func tick_cooldowns() -> void:
	for id in cooldowns.keys():
		cooldowns[id] = maxi(0, cooldowns[id] - 1)


## Everything this combatant could use right now, plain attack first.
func usable_skills() -> Array[Skill]:
	var ready: Array[Skill] = [SkillLibrary.basic_attack()]
	for skill in skills:
		if skill != null and is_ready(skill):
			ready.append(skill)
	return ready


func _stat_multiplier(kind: StatusEffect.Kind) -> float:
	var product := 1.0
	for active in statuses:
		if active.effect.kind == kind:
			product *= active.effect.multiplier()
	return product
