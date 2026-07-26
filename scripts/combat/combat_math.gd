class_name CombatMath
## Every number that decides a swing, in one file.
##
## Kept out of [CombatManager] so balance can be read, tested and tuned without
## reading the turn loop, and so the whole thing stays a pure function of
## (attacker, defender, skill, rng). Nothing here mutates a combatant.
##
## Mitigation compares the two combatants rather than reading defence on an
## absolute scale: [code]attack / (attack + defence)[/code]. Both subtractive
## armour and a fixed defence curve break somewhere on a 100-floor climb -- one
## end stops landing hits, the other stops caring about armour. A ratio holds its
## shape whether the numbers are 8 and 4 or 240 and 130.

## How much a point of defence is worth against a point of attack. 1.0 means an
## enemy with defence equal to your attack halves your damage.
const DEFENSE_WEIGHT := 1.0
const CRIT_MULTIPLIER := 1.6
## Damage taken while reeling from a stagger, and while stuck in post-motion.
const STAGGERED_TAKEN := 1.5
const POST_MOTION_TAKEN := 1.35
const DEFENDING_TAKEN := 0.5
## Damage rolls land within +/-10% so identical turns don't look identical.
const VARIANCE := 0.1
## Defending pays for itself in poise as well as HP.
const DEFEND_POISE_RECOVERY := 0.25


## Resolves one hit. Returns [code]{amount, crit, missed}[/code]; [param amount]
## is 0 on a miss.
static func strike(attacker: Combatant, defender: Combatant, skill: Skill,
		rng: RandomNumberGenerator) -> Dictionary:
	if rng.randi_range(1, 100) > skill.accuracy:
		return {"amount": 0, "crit": false, "missed": true}

	var offence := float(attacker.effective_attack())
	var armour := defender.effective_defense() * DEFENSE_WEIGHT
	var raw := offence * skill.power / 100.0
	var mitigated := raw * offence / (offence + armour)
	mitigated *= rng.randf_range(1.0 - VARIANCE, 1.0 + VARIANCE)

	var crit := rng.randi_range(1, 100) <= skill.crit_chance
	if crit:
		mitigated *= CRIT_MULTIPLIER
	mitigated *= taken_multiplier(defender)

	return {"amount": maxi(1, roundi(mitigated)), "crit": crit, "missed": false}


## How much of an incoming hit [param defender] actually eats, before armour.
## Being caught mid-recovery or reeling hurts; bracing for it does not.
static func taken_multiplier(defender: Combatant) -> float:
	var multiplier := 1.0
	if defender.staggered:
		multiplier *= STAGGERED_TAKEN
	if defender.post_motion > 0:
		multiplier *= POST_MOTION_TAKEN
	if defender.defending:
		multiplier *= DEFENDING_TAKEN
	return multiplier


## Healing ignores defence and variance: a potion is a potion.
static func healing(actor: Combatant, skill: Skill) -> int:
	return maxi(1, roundi(actor.effective_attack() * skill.power / 100.0))


static func rolls_status(skill: Skill, rng: RandomNumberGenerator) -> bool:
	return skill.applies != null and rng.randi_range(1, 100) <= skill.apply_chance


## Fleeing is a race: faster than what's chasing you and you're gone. Clamped so
## there is always a chance and never a certainty.
static func flee_chance(runner: Combatant, enemies: Array[Combatant]) -> float:
	var fastest := 1
	for enemy in enemies:
		if enemy.is_alive():
			fastest = maxi(fastest, enemy.effective_speed())
	return clampf(0.4 + (runner.effective_speed() - fastest) * 0.06, 0.15, 0.9)
