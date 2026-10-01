extends Node
## Exercises the whole combat system with no UI loaded.
##
##     "$GODOT" --headless --path . res://test/combat_test.tscn
##
## Run as a *scene*, not with --script: autoloads are registered after a script
## main loop is compiled, so CombatManager & co. wouldn't resolve.
##
## Three things this is really here to catch:
##   * the data not loading -- a skill or enemy .tres that silently became null;
##   * the turn loop hanging, which a view would hide behind an animation;
##   * the balance drifting until the tower stops being climbable. The last
##     section fights real bosses and asserts win rates, so a stat edit that
##     makes floor 50 impossible fails here instead of in a playthrough.

var _failures: PackedStringArray = PackedStringArray()
var _checks := 0

## Signal spies. Members, not captured locals: GDScript lambdas capture by value.
var _reports: Array[CombatReport] = []
## [round, is_player] for every turn taken while [method _spy_turns] is on.
var _turns: Array = []
var _defeated: Array[StringName] = []
var _items: Array[StringName] = []
## What the auto-player does when asked for a command.
var _policy := &"attack"
var _policy_skill: Skill = null


func _ready() -> void:
	CombatManager.step_delay = 0.0
	await _run()
	print("")
	if _failures.is_empty():
		print("combat test: %d checks passed" % _checks)
		get_tree().quit(0)
		return
	printerr("combat test: %d of %d checks FAILED" % [_failures.size(), _checks])
	for failure in _failures:
		printerr("  - ", failure)
	get_tree().quit(1)


func _run() -> void:
	# Connected for the whole run: every fight below needs somebody to answer
	# the player's turn, or the loop parks forever and the suite hangs.
	CombatManager.command_requested.connect(_on_command_requested)
	_test_content()
	_test_scaling()
	_test_math()
	_test_statuses()
	_test_cooldowns_and_stagger()
	await _test_one_fight()
	await _test_rules()
	await _test_opening()
	await _test_determinism()
	await _test_balance()


# --- content ---------------------------------------------------------------

func _test_content() -> void:
	print("\n-- content --")
	_check(SkillLibrary.basic_attack() != null, "the basic attack resource loads")
	_check(SkillLibrary.basic_attack().cooldown == 0, "the basic attack has no cooldown")
	_check(SkillLibrary.all().size() == SkillLibrary.PLAYER_SKILLS.size(),
			"every listed player skill loads (%d of %d)" % [
				SkillLibrary.all().size(), SkillLibrary.PLAYER_SKILLS.size()])

	var level_1 := SkillLibrary.for_level(1)
	var level_20 := SkillLibrary.for_level(20)
	_check(level_1.size() < level_20.size(), "skills unlock with level (%d at 1, %d at 20)" % [
			level_1.size(), level_20.size()])
	_check(SkillLibrary.get_skill(&"vorpal_strike") != null, "a skill can be found by id")
	_check(SkillLibrary.unlock_level_of(&"nonsense") == -1, "an unknown skill id reports no level")

	var missing := PackedStringArray()
	for id in Bestiary.ENEMIES:
		var type := Bestiary.get_enemy(StringName(id))
		if type == null or type.battler == null or type.id == &"":
			missing.append(id)
	_check(missing.is_empty(), "every enemy loads with a sprite and an id (%s)" % missing)

	var orphans := PackedStringArray()
	for archetype in FloorTuning.BOSS_ARCHETYPES:
		if not Bestiary.BOSS_TEMPLATES.has(archetype):
			orphans.append(archetype)
	_check(orphans.is_empty(), "every boss archetype maps to a template (%s)" % orphans)

	var poolless := PackedStringArray()
	for band in FloorRegistry.BIOME_BANDS:
		if not Bestiary.BIOME_POOLS.has(StringName(band["biome"])):
			poolless.append(band["biome"])
	_check(poolless.is_empty(), "every biome band has a monster pool (%s)" % poolless)

	# The battle draws the place: every band's fights stand on its ground in front
	# of its scenery -- the tree line, the ridge, or (the sky) its painted clouds.
	var bare := PackedStringArray()
	for band in FloorRegistry.BIOME_BANDS:
		var encounter := Bestiary.boss_encounter(band["through"])
		var scenery := encounter.scenery
		if encounter.ground_texture == null or scenery == null or scenery.get_width() < 320 \
				or (scenery.get_height() < 32 and encounter.sky_texture == null):
			bare.append(band["biome"])
	_check(bare.is_empty(), "every band's battle has ground and scenery (%s)" % bare)


func _test_scaling() -> void:
	print("\n-- scaling --")
	var boar := Bestiary.get_enemy(&"frenzy_boar")
	_check(boar.hp_at(1) == boar.max_hp, "a level-1 enemy is exactly its base stats")
	_check(boar.hp_at(10) > boar.hp_at(5) and boar.attack_at(10) > boar.attack_at(5),
			"enemy stats grow with level")
	_check(boar.hp_at(0) >= 1, "a nonsense level still yields a live monster")

	var bossless := PackedStringArray()
	for floor_number in [1, 2, 50, 100]:
		var encounter := Bestiary.boss_encounter(floor_number)
		if encounter == null or encounter.enemies.is_empty():
			bossless.append(str(floor_number))
	_check(bossless.is_empty(), "every sampled floor produces a boss encounter (%s)" % bossless)

	var floor_1 := Bestiary.boss_encounter(1)
	_check(floor_1.boss_name == "Illfang the Kobold Lord",
			"an authored floor keeps its authored boss (got '%s')" % floor_1.boss_name)
	_check(not floor_1.can_flee, "a boss fight cannot be fled")
	_check(floor_1.enemies.size() == 2, "Illfang brings an escort")

	var boss := Bestiary.build_boss(floor_1.enemies[0], floor_1.level, floor_1.boss_name)
	var plain := Combatant.from_enemy(floor_1.enemies[0], floor_1.level)
	_check(boss.max_hp > plain.max_hp * 2, "a boss is far tougher than its template")
	_check(boss.skills.size() > plain.skills.size(), "a boss gains the shared rampage skill")

	var deep := Bestiary.boss_encounter(100)
	_check(deep.enemies.size() <= 2, "no boss brings more than one escort")


# --- formulas --------------------------------------------------------------

func _test_math() -> void:
	print("\n-- damage --")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var attacker := _dummy("A", 20, 100, 5)
	var soft := _dummy("Soft", 0, 100, 5)
	var armoured := _dummy("Armoured", 40, 100, 5)
	var strike := SkillLibrary.basic_attack()

	var on_soft := 0
	var on_armoured := 0
	for i in 200:
		on_soft += CombatMath.strike(attacker, soft, strike, rng)["amount"]
		on_armoured += CombatMath.strike(attacker, armoured, strike, rng)["amount"]
	_check(on_soft > on_armoured, "defence reduces damage (%d vs %d over 200 hits)" % [
			on_soft, on_armoured])
	_check(on_armoured > 0, "even heavy armour still takes damage")

	# The whole reason the formula is a ratio rather than a fixed curve: the same
	# attack-to-defence matchup must mitigate the same fraction whether the
	# numbers are floor 1's or floor 100's.
	var low := _ratio(_dummy("l", 0, 100, 5, 8), _dummy("l", 4, 100, 5), strike)
	var high := _ratio(_dummy("h", 0, 100, 5, 240), _dummy("h", 120, 100, 5), strike)
	_check(absf(low - high) < 0.08,
			"mitigation is scale-free (%.2f at 8v4, %.2f at 240v120)" % [low, high])

	var defender := _dummy("D", 5, 100, 5)
	var open := CombatMath.taken_multiplier(defender)
	defender.defending = true
	var guarded := CombatMath.taken_multiplier(defender)
	defender.defending = false
	defender.staggered = true
	var reeling := CombatMath.taken_multiplier(defender)
	_check(guarded < open and reeling > open, "guarding cuts damage, reeling raises it")

	var slow := _dummy("Slow", 0, 100, 1)
	var quick := _dummy("Quick", 0, 100, 40)
	_check(CombatMath.flee_chance(quick, [slow]) > CombatMath.flee_chance(slow, [quick]),
			"the faster combatant escapes more easily")


func _ratio(attacker: Combatant, defender: Combatant, skill: Skill) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var total := 0
	for i in 300:
		total += CombatMath.strike(attacker, defender, skill, rng)["amount"]
	return (total / 300.0) / attacker.effective_attack()


# --- combatant behaviour ---------------------------------------------------

func _test_statuses() -> void:
	print("\n-- statuses --")
	var poison: StatusEffect = load("res://resources/statuses/poison.tres")
	var weakened: StatusEffect = load("res://resources/statuses/weakened.tres")

	var victim := _dummy("Victim", 5, 200, 10)
	victim.apply_status(poison)
	_check(victim.has_status(&"poison"), "a status attaches")
	var first := victim.tick_statuses()
	_check(first < 0, "poison costs HP each turn (%d)" % first)
	_check(victim.hp == victim.max_hp + first, "the HP actually came off")

	# Percent of max HP, so poison is worth casting at every point in the tower.
	var big := _dummy("Big", 5, 2000, 10)
	big.apply_status(poison)
	_check(-big.tick_statuses() > -first * 5, "damage-over-time scales with max HP")

	victim.apply_status(poison)
	_check(victim.statuses.size() == 1, "re-applying refreshes rather than stacks")
	for i in 10:
		victim.tick_statuses()
	_check(not victim.has_status(&"poison"), "a status expires")

	var fighter := _dummy("Fighter", 5, 100, 10)
	var base := fighter.effective_attack()
	fighter.apply_status(weakened)
	_check(fighter.effective_attack() < base, "an attack debuff lowers effective attack")
	_check(fighter.attack == base, "the debuff did not touch the base stat")

	var dying := _dummy("Dying", 0, 10, 10)
	dying.take_damage(9)
	dying.apply_status(poison)
	dying.tick_statuses()
	_check(not dying.is_alive(), "a status can land the killing blow")
	_check(dying.statuses.is_empty(), "death clears the status list")


func _test_cooldowns_and_stagger() -> void:
	print("\n-- cooldowns and stagger --")
	var slant := SkillLibrary.get_skill(&"slant")
	var fighter := _dummy("Fighter", 5, 100, 10)
	fighter.skills = [slant]

	_check(fighter.is_ready(slant), "a fresh skill is ready")
	_check(slant in fighter.usable_skills(), "a ready skill is offered")
	fighter.start_cooldown(slant)
	_check(not fighter.is_ready(slant), "using a skill puts it on cooldown")
	_check(slant not in fighter.usable_skills(), "a skill on cooldown is not offered")
	_check(SkillLibrary.basic_attack() in fighter.usable_skills(),
			"the basic attack is always offered")
	for i in slant.cooldown:
		fighter.tick_cooldowns()
	_check(fighter.is_ready(slant), "a cooldown runs out")

	var target := _dummy("Target", 5, 100, 10)
	target.max_poise = 20
	target.poise = 20
	_check(not target.take_stagger(5), "a light hit does not break poise")
	_check(target.take_stagger(50), "emptying poise staggers")
	_check(target.is_incapacitated(), "a staggered combatant loses its turn")
	_check(not target.take_stagger(50), "an already-staggered combatant cannot be re-staggered")
	target.recover_from_stagger()
	_check(not target.is_incapacitated() and target.poise > 0, "recovering restores some poise")


# --- the turn loop ---------------------------------------------------------

func _test_one_fight() -> void:
	print("\n-- a fight, end to end --")
	_set_player(12)
	_spy(true)
	_policy = &"attack"

	CombatManager.set_seed(4242)
	var xp_before := GameState.xp
	# Walk in already hurt, so the write-back is observable whether or not the
	# fight lands a single hit on the player.
	GameState.set_hp(GameState.max_hp - 10)
	var result: CombatResult = await CombatManager.start(
			Bestiary.single_encounter(Bestiary.get_enemy(&"little_nepent"), 2))

	_check(result != null and result.victory, "a level-12 player beats a level-2 nepent")
	_check(result.rounds > 0, "the fight took at least one round")
	_check(not CombatManager.is_running(), "the manager is idle afterwards")
	_check(not GameState.is_input_locked(), "combat releases the input lock")
	_check(_defeated.has(&"little_nepent"), "a kill is announced on EventBus")
	_check(result.xp > 0 and GameState.xp > xp_before, "victory pays XP into GameState")
	_check(GameState.hp <= GameState.max_hp - 10,
			"HP carries into the fight and back out of it (%d/%d)" % [
				GameState.hp, GameState.max_hp])
	_check(not _reports.is_empty(), "the fight reported what happened")

	var had_damage := false
	for report in _reports:
		for hit in report.hits:
			if hit.amount < 0:
				had_damage = true
	_check(had_damage, "at least one report carried a damage number")
	_spy(false)


func _test_rules() -> void:
	print("\n-- rules the runner enforces --")
	_set_player(30)
	_spy(true)

	# Fleeing a boss must be refused by the runner, not only greyed out in the UI.
	_policy = &"flee"
	CombatManager.set_seed(99)
	var boss_result: CombatResult = await CombatManager.start(Bestiary.boss_encounter(1))
	_check(not boss_result.fled, "the runner refuses to flee a boss fight")

	# ...but an ordinary monster can be walked away from. A golem is the safe
	# case to assert on: outrunning the slowest thing in the bestiary is the
	# high end of [method CombatMath.flee_chance], not a coin flip.
	_policy = &"flee"
	var escaped := false
	for attempt in 12:
		_set_player(4)
		CombatManager.set_seed(500 + attempt)
		var roam: CombatResult = await CombatManager.start(
				Bestiary.single_encounter(Bestiary.get_enemy(&"stone_golem"), 1))
		if roam.fled:
			escaped = true
			break
	_check(escaped, "an ordinary fight can be fled")

	# A skill on cooldown is refused even if a caller asks for it directly.
	_set_player(30)
	_policy = &"double_slant"
	_policy_skill = SkillLibrary.get_skill(&"slant")
	CombatManager.set_seed(31)
	await CombatManager.start(
			Bestiary.single_encounter(Bestiary.get_enemy(&"stone_golem"), 30))
	_check(true, "a fight with repeated illegal submissions still terminates")

	# Defeat: a level-1 player against a floor-90 boss can only lose.
	_set_player(1)
	_policy = &"attack"
	CombatManager.set_seed(77)
	var lost: CombatResult = await CombatManager.start(Bestiary.boss_encounter(90))
	_check(lost != null and not lost.victory, "an outmatched player loses")
	_check(lost.defeated(), "the result reports a defeat rather than a flight")
	_check(GameState.hp == 0, "defeat writes the player's HP back as 0")
	_check(not GameState.is_input_locked(), "a lost fight also releases the input lock")
	_spy(false)


## Who struck first on the map owns round 1, and nothing after it. The monster
## decides which opening it was; this checks the runner honours whatever it is told.
func _test_opening() -> void:
	print("\n-- who struck first --")
	_policy = &"attack"
	_check(Bestiary.boss_encounter(1).opening == Encounter.Opening.NORMAL,
			"a boss fight has no opening advantage")

	for opening: Encounter.Opening in [Encounter.Opening.NORMAL,
			Encounter.Opening.PARTY_FIRST, Encounter.Opening.ENEMIES_FIRST]:
		_set_player(12)
		_spy(true)
		_turns.clear()
		CombatManager.turn_began.connect(_spy_turn)
		CombatManager.set_seed(808)
		# A golem at the player's own level: sturdy enough that round 1 cannot end
		# the fight before both sides would have had their turn in it.
		var encounter := Bestiary.single_encounter(Bestiary.get_enemy(&"stone_golem"), 12)
		encounter.opening = opening
		var result: CombatResult = await CombatManager.start(encounter)
		CombatManager.turn_began.disconnect(_spy_turn)

		var party_in_1 := false
		var enemy_in_1 := false
		var enemy_later := false
		for turn: Array in _turns:
			if turn[0] == 1:
				party_in_1 = party_in_1 or turn[1]
				enemy_in_1 = enemy_in_1 or not turn[1]
			elif not turn[1]:
				enemy_later = true
		var announced := not _reports.is_empty() \
				and _reports[0].kind == CombatReport.Kind.OPENING
		_spy(false)

		match opening:
			Encounter.Opening.NORMAL:
				_check(party_in_1 and enemy_in_1, "no opening: both sides act in round 1")
				_check(not announced, "and nothing is announced")
			Encounter.Opening.PARTY_FIRST:
				_check(party_in_1 and not enemy_in_1,
						"a pre-emptive strike: only the party acts in round 1")
				_check(announced, "and the log says so first")
			Encounter.Opening.ENEMIES_FIRST:
				_check(enemy_in_1 and not party_in_1,
						"caught from behind: only the enemies act in round 1")
				_check(announced, "and the log says so first")
		_check(result != null and result.rounds > 1 and (enemy_later or result.victory),
				"the opening costs one round, not the fight")


func _spy_turn(actor: Combatant) -> void:
	_turns.append([CombatManager.round_number(), actor.is_player])


func _test_determinism() -> void:
	print("\n-- determinism --")
	var first := await _transcript(1234)
	var same := await _transcript(1234)
	var other := await _transcript(9999)
	_check(first == same, "the same seed replays the same fight")
	_check(first != other, "a different seed plays a different fight")
	_check(Bestiary.boss_encounter(63).boss_name == Bestiary.boss_encounter(63).boss_name,
			"a floor's boss is the same boss every time")


## Fights a fixed battle and returns the log, so two runs can be compared.
func _transcript(with_seed: int) -> PackedStringArray:
	_set_player(20)
	_policy = &"attack"
	_spy(true)
	CombatManager.set_seed(with_seed)
	await CombatManager.start(
			Bestiary.single_encounter(Bestiary.get_enemy(&"lizardman_soldier"), 18))
	var lines := PackedStringArray()
	for report in _reports:
		var amounts := PackedStringArray()
		for hit in report.hits:
			amounts.append(str(hit.amount))
		lines.append("%s|%s" % [report.text, ",".join(amounts)])
	_spy(false)
	return lines


# --- balance ---------------------------------------------------------------

## The check that keeps the tower climbable. These numbers were measured, not
## chosen: if a stat edit moves them, the climb has changed shape and somebody
## should decide whether that was intended.
func _test_balance() -> void:
	print("\n-- balance --")
	_policy = &"play"

	var illfang_at_3 := await _win_rate(1, 3, 12)
	var illfang_at_5 := await _win_rate(1, 5, 12)
	_check(illfang_at_3 < 12, "Illfang is not a walkover at level 3 (%d/12)" % illfang_at_3)
	_check(illfang_at_5 >= 9, "Illfang is beatable at level 5 (%d/12)" % illfang_at_5)

	# Every band's boss, and every authored one past Illfang, fought at the level
	# its floor expects. None of them should be hopeless and none should be free.
	var floors: Array[int] = [10, 30, 50, 70, 90, 100]
	for floor_number in Bestiary.AUTHORED_BOSSES:
		if floor_number > 1 and floor_number not in floors:
			floors.append(floor_number)
	floors.sort()
	for floor_number in floors:
		var level := FloorTuning.enemy_level(floor_number) + 6
		var wins := await _win_rate(floor_number, level, 8)
		_check(wins >= 4, "floor %d's boss is beatable at level %d (%d/8)" % [
				floor_number, level, wins])

	var fair := await _win_rate(50, 12, 4)
	_check(fair == 0, "a badly underlevelled player loses to a floor 50 boss (%d/4)" % fair)


func _win_rate(floor_number: int, level: int, trials: int) -> int:
	var wins := 0
	for trial in trials:
		_set_player(level)
		CombatManager.set_seed(floor_number * 1000 + trial)
		var result: CombatResult = await CombatManager.start(Bestiary.boss_encounter(floor_number))
		if result != null and result.victory:
			wins += 1
	return wins


# --- helpers ---------------------------------------------------------------

## The auto-player.
##
## Every branch falls back to a plain attack when the runner refuses the move,
## exactly as the combat screen does -- it leaves the menu up rather than
## consuming the turn. A policy that shrugs and returns leaves the turn loop
## parked forever with nobody to answer it, which is a hung suite, not a
## failing one.
func _on_command_requested(actor: Combatant) -> void:
	var enemies := CombatManager.living_enemies()
	if enemies.is_empty():
		return

	var accepted := false
	match _policy:
		&"flee":
			accepted = CombatManager.submit(CombatAction.flee())
		&"double_slant":
			# Illegal from the second use onwards: the runner must refuse it and
			# still take a legal answer for the same turn.
			accepted = CombatManager.submit(CombatAction.use(_policy_skill, enemies[0]))
		&"play":
			accepted = _play_well(actor, enemies)
		_:
			accepted = CombatManager.submit(
					CombatAction.use(SkillLibrary.basic_attack(), enemies[0]))

	if not accepted:
		CombatManager.submit(CombatAction.use(SkillLibrary.basic_attack(), enemies[0]))


## Competent, not optimal: heal when low, biggest thing off cooldown otherwise,
## weakest enemy first. Roughly how an attentive player fights, which is the
## standard the balance checks are written against.
func _play_well(actor: Combatant, enemies: Array[Combatant]) -> bool:
	var target: Combatant = enemies[0]
	for enemy in enemies:
		if enemy.max_hp < target.max_hp:
			target = enemy

	var best: Skill = SkillLibrary.basic_attack()
	for skill in actor.usable_skills():
		if skill.kind == Skill.Kind.HEAL:
			if actor.hp_ratio() < 0.45:
				return CombatManager.submit(CombatAction.use(skill, actor))
			continue
		if skill.power > best.power:
			best = skill
	return CombatManager.submit(CombatAction.use(best, target))


## A bare combatant with the stats a check needs and nothing else.
func _dummy(dummy_name: String, defense: int, max_hp: int, speed: int, attack := 20) -> Combatant:
	var c := Combatant.new()
	c.display_name = dummy_name
	c.level = 1
	c.max_hp = max_hp
	c.hp = max_hp
	c.attack = attack
	c.defense = defense
	c.speed = speed
	c.max_poise = 100
	c.poise = 100
	return c


## The player as GameState would have them at [param level], following the curve
## in GameState._level_up().
func _set_player(level: int) -> void:
	GameState.level = level
	GameState.max_hp = 60 + 6 * (level - 1)
	GameState.attack = 8 + 2 * (level - 1)
	GameState.defense = 4 + (level - 1)
	GameState.speed = 10 + (level / 2)
	GameState.hp = GameState.max_hp
	GameState.xp = 0


func _spy(on: bool) -> void:
	_reports.clear()
	_defeated.clear()
	_items.clear()
	if on:
		CombatManager.action_resolved.connect(_spy_report)
		EventBus.enemy_defeated.connect(_spy_defeat)
		EventBus.item_added.connect(_spy_item)
	else:
		CombatManager.action_resolved.disconnect(_spy_report)
		EventBus.enemy_defeated.disconnect(_spy_defeat)
		EventBus.item_added.disconnect(_spy_item)


func _spy_report(report: CombatReport) -> void:
	_reports.append(report)


func _spy_defeat(enemy_id: StringName) -> void:
	_defeated.append(enemy_id)


func _spy_item(item_id: StringName, _amount: int) -> void:
	_items.append(item_id)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", description)
	else:
		print("  FAIL ", description)
		_failures.append(description)
