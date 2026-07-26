extends Node
## Runs a battle. Owns the turn loop, never a pixel of it.
##
## The same split as [DialogueRunner]: this decides who acts, what it costs and
## who wins; [code]ui/combat_screen.tscn[/code] listens to the signals below and
## calls [method submit] back with the player's choice. Nothing here touches a
## node in the combat screen, which is why [code]test/combat_test.tscn[/code]
## can fight a hundred battles with no UI loaded at all.
##
## Typical use, from the labyrinth door:
##     var result := await CombatManager.start(Bestiary.boss_encounter(3))
##     if result.victory:
##         GameState.clear_floor(3)
##
## The caller is responsible for what a defeat means -- this reports it and
## writes the player's HP back to [GameState], but it does not decide whether
## you respawn, reload or die for real.

## The fight is set up and about to begin. Both arrays are live [Combatant]s;
## a view may hold on to them until [signal combat_finished].
signal combat_began(encounter: Encounter, party: Array[Combatant], enemies: Array[Combatant])
signal round_began(round_number: int)
signal turn_began(actor: Combatant)
## The player must choose. Answer with [method submit].
signal command_requested(actor: Combatant)
## Something happened: a swing, a poison tick, a death. One per resolved step,
## in the order they occurred.
signal action_resolved(report: CombatReport)
signal combat_finished(result: CombatResult)

## A fight that has gone this long is not going to resolve itself.
const MAX_ROUNDS := 50

## Seconds the loop waits after each step so a view can animate it. Tests set
## this to 0; the runner then yields a frame instead, keeping the loop async
## without spending real time.
var step_delay := 0.55

var _encounter: Encounter = null
var _party: Array[Combatant] = []
var _enemies: Array[Combatant] = []
var _actor: Combatant = null
var _round := 0
var _running := false
var _awaiting := false
## The action [method submit] accepted, held until [method _decide] picks it up.
## Kept as state rather than passed by signal alone so a caller that answers
## *during* [signal command_requested] -- an auto-battler, a replay, a test --
## is not answering before the loop is listening.
var _pending: CombatAction = null
var _rng := RandomNumberGenerator.new()

## Parked on while the player decides. Private for the same reason
## [DialogueRunner]'s are: input must go through [method submit], which is the
## one place that refuses an illegal move.
signal _command_submitted(action: CombatAction)


# --- public state ----------------------------------------------------------

func is_running() -> bool:
	return _running


func is_awaiting_command() -> bool:
	return _awaiting


func current_actor() -> Combatant:
	return _actor


func current_encounter() -> Encounter:
	return _encounter


func party() -> Array[Combatant]:
	return _party


func enemies() -> Array[Combatant]:
	return _enemies


func living_enemies() -> Array[Combatant]:
	return _living(_enemies)


func round_number() -> int:
	return _round


## Fixes the dice. Combat is random by default; tests and (later) replays seed it
## so the same fight plays out the same way twice.
func set_seed(value: int) -> void:
	_rng.seed = value


# --- running a fight -------------------------------------------------------

## Fights [param encounter] to a conclusion and returns how it went. Awaitable:
## callers get control back only once the battle is over.
func start(encounter: Encounter) -> CombatResult:
	if _running:
		push_warning("CombatManager: a battle is already running.")
		return null
	if encounter == null or encounter.enemies.is_empty():
		push_error("CombatManager: refusing to start an empty encounter.")
		return null

	_begin(encounter)
	var result := await _fight()
	_end(result)
	return result


## The player's answer to [signal command_requested]. Returns false and changes
## nothing if the move is illegal -- an out-of-range target, a skill still on
## cooldown, fleeing a boss. The UI checks too; this is the check that counts.
func submit(action: CombatAction) -> bool:
	if not _awaiting or action == null or _actor == null:
		return false
	match action.kind:
		CombatAction.Kind.SKILL:
			if action.skill == null or not _actor.is_ready(action.skill):
				return false
			if action.skill not in _actor.usable_skills():
				return false
		CombatAction.Kind.FLEE:
			if not _encounter.can_flee:
				return false
	_awaiting = false
	_pending = action
	_command_submitted.emit(action)
	return true


func _begin(encounter: Encounter) -> void:
	_running = true
	_encounter = encounter
	_round = 0
	_actor = null

	_party = [Combatant.from_player()]
	_enemies = []
	for index in encounter.enemies.size():
		var type := encounter.enemies[index]
		var enemy_name := encounter.name_for(index)
		if encounter.is_boss and index == 0:
			_enemies.append(Bestiary.build_boss(type, encounter.level, enemy_name))
		else:
			_enemies.append(Combatant.from_enemy(type, encounter.level, enemy_name))

	GameState.push_input_lock()
	EventBus.combat_started.emit(encounter.id)
	combat_began.emit(encounter, _party, _enemies)


func _fight() -> CombatResult:
	var result := CombatResult.new()
	await _pause()

	while _round < MAX_ROUNDS:
		_round += 1
		round_began.emit(_round)
		for actor in _turn_order():
			if not actor.is_alive():
				continue  # felled earlier this round
			var over := await _take_turn(actor, result)
			if over:
				result.rounds = _round
				return result
	result.rounds = _round
	result.stalemate = true
	return result


## Speed decides the order, recomputed every round so a slow debuff bites
## immediately. Ties go to the player: being outsped should cost a stat, not a
## coin flip.
func _turn_order() -> Array[Combatant]:
	var order: Array[Combatant] = []
	order.append_array(_living(_party))
	order.append_array(_living(_enemies))
	order.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		if a.effective_speed() != b.effective_speed():
			return a.effective_speed() > b.effective_speed()
		return a.is_player and not b.is_player)
	return order


## Runs one combatant's turn. Returns true when the battle ended during it.
func _take_turn(actor: Combatant, result: CombatResult) -> bool:
	_actor = actor
	actor.defending = false
	actor.tick_cooldowns()
	actor.post_motion = maxi(0, actor.post_motion - 1)
	turn_began.emit(actor)
	EventBus.turn_started.emit(actor.display_name)

	# Whether the turn can be taken is decided before the statuses age, or a
	# one-turn daze would expire on the very turn it was meant to cost.
	var incapacitated := actor.is_incapacitated()
	var was_staggered := actor.staggered

	if await _tick_statuses(actor):
		return await _settle(result)

	if incapacitated:
		var reason := "reels, off balance" if was_staggered else "cannot move"
		var skipped := CombatReport.make(CombatReport.Kind.SKIPPED, actor,
				"%s %s." % [actor.display_name, reason])
		actor.recover_from_stagger()
		await _report(skipped)
		EventBus.turn_ended.emit(actor.display_name)
		return await _settle(result)

	var action := await _decide(actor)
	await _resolve(actor, action, result)
	EventBus.turn_ended.emit(actor.display_name)
	return await _settle(result)


## Ages [param actor]'s statuses. Returns true if it died to one of them.
func _tick_statuses(actor: Combatant) -> bool:
	if actor.statuses.is_empty():
		return false
	var delta := actor.tick_statuses()
	if delta != 0:
		var verb := "takes %d damage" % -delta if delta < 0 else "recovers %d HP" % delta
		var report := CombatReport.make(CombatReport.Kind.STATUS, actor,
				"%s %s." % [actor.display_name, verb])
		var hit := CombatReport.Hit.new(actor)
		hit.amount = delta
		report.add_hit(hit)
		await _report(report)
	if not actor.is_alive():
		await _announce_defeat(actor)
		return true
	return false


func _decide(actor: Combatant) -> CombatAction:
	if not actor.is_player:
		return _ai_choose(actor)
	_pending = null
	_awaiting = true
	command_requested.emit(actor)
	if _pending == null:
		await _command_submitted
	var action := _pending
	_pending = null
	return action


func _resolve(actor: Combatant, action: CombatAction, result: CombatResult) -> void:
	match action.kind:
		CombatAction.Kind.DEFEND:
			actor.defending = true
			actor.post_motion = 0  # bracing is the opposite of over-committing
			actor.poise = mini(actor.max_poise,
					actor.poise + roundi(actor.max_poise * CombatMath.DEFEND_POISE_RECOVERY))
			await _report(CombatReport.make(CombatReport.Kind.DEFEND, actor,
					"%s takes a guard stance." % actor.display_name))
		CombatAction.Kind.FLEE:
			await _resolve_flee(actor, result)
		CombatAction.Kind.SKILL:
			await _resolve_skill(actor, action)


func _resolve_flee(actor: Combatant, result: CombatResult) -> void:
	var success := _rng.randf() < CombatMath.flee_chance(actor, _enemies)
	var report := CombatReport.make(CombatReport.Kind.FLEE, actor,
			"%s breaks away!" % actor.display_name if success
			else "%s cannot break away!" % actor.display_name)
	report.success = success
	result.fled = success
	await _report(report)


func _resolve_skill(actor: Combatant, action: CombatAction) -> void:
	var skill := action.skill
	var report := CombatReport.make(CombatReport.Kind.SKILL, actor, skill.announcement(actor.display_name))
	report.skill = skill

	for target in _targets_for(actor, skill, action.target):
		match skill.kind:
			Skill.Kind.STRIKE:
				report.add_hit(_apply_strike(actor, target, skill))
			Skill.Kind.HEAL:
				var hit := CombatReport.Hit.new(target)
				hit.amount = target.heal(CombatMath.healing(actor, skill))
				if CombatMath.rolls_status(skill, _rng):
					target.apply_status(skill.applies)
				report.add_hit(hit)
			Skill.Kind.STATUS:
				if CombatMath.rolls_status(skill, _rng):
					target.apply_status(skill.applies)
				report.add_hit(CombatReport.Hit.new(target))

	actor.start_cooldown(skill)
	actor.post_motion = maxi(actor.post_motion, skill.post_motion)
	await _report(report)

	for hit in report.hits:
		if not hit.target.is_alive():
			await _announce_defeat(hit.target)


func _apply_strike(actor: Combatant, target: Combatant, skill: Skill) -> CombatReport.Hit:
	var hit := CombatReport.Hit.new(target)
	var roll := CombatMath.strike(actor, target, skill, _rng)
	if roll["missed"]:
		hit.missed = true
		return hit
	hit.crit = roll["crit"]
	hit.amount = -target.take_damage(roll["amount"])
	hit.staggered = target.take_stagger(skill.stagger)
	if target.is_alive() and CombatMath.rolls_status(skill, _rng):
		target.apply_status(skill.applies)
	return hit


## Who a skill actually lands on. A chosen target that has since died (or was
## never on the right side) falls back to the first living candidate, so a
## queued command can never fizzle into nothing.
func _targets_for(actor: Combatant, skill: Skill, chosen: Combatant) -> Array[Combatant]:
	var opposition := _living(_enemies if actor.is_player else _party)
	var allies := _living(_party if actor.is_player else _enemies)

	match skill.target:
		Skill.Target.SELF:
			return [actor]
		Skill.Target.ALL_ENEMIES:
			return opposition
		Skill.Target.ALL_ALLIES:
			return allies
		Skill.Target.ONE_ALLY:
			if chosen != null and chosen.is_alive() and chosen in allies:
				return [chosen]
			return [allies[0]] if not allies.is_empty() else [actor]
		_:
			if chosen != null and chosen.is_alive() and chosen in opposition:
				return [chosen]
			return [opposition[0]] if not opposition.is_empty() else []


func _announce_defeat(fallen: Combatant) -> void:
	await _report(CombatReport.make(CombatReport.Kind.DEFEAT, fallen,
			"%s is defeated." % fallen.display_name))
	if not fallen.is_player and fallen.source != null:
		EventBus.enemy_defeated.emit(fallen.source.id)


## Checks whether the battle is over and fills in [param result] if it is.
func _settle(result: CombatResult) -> bool:
	if result.fled:
		return true
	if _living(_enemies).is_empty():
		result.victory = true
		return true
	if _living(_party).is_empty():
		return true
	return false


# --- enemy AI --------------------------------------------------------------

## Deliberately shallow: heal when hurt, otherwise roll against
## [member EnemyType.skill_bias] and pick a skill by weight. Enough to make
## fights feel considered without an AI system to maintain.
func _ai_choose(actor: Combatant) -> CombatAction:
	var ready: Array[Skill] = []
	for skill in actor.skills:
		if actor.is_ready(skill):
			ready.append(skill)

	var wounded := _most_wounded(_living(_enemies if actor.is_player else _party))
	for skill in ready:
		if skill.kind == Skill.Kind.HEAL and wounded != null and wounded.hp_ratio() < 0.5:
			return CombatAction.use(skill, wounded)

	var offensive := ready.filter(func(s: Skill) -> bool: return s.is_offensive())
	var bias: float = actor.source.skill_bias if actor.source != null else 0.5
	if offensive.is_empty() or _rng.randf() > bias:
		return CombatAction.use(SkillLibrary.basic_attack(), _pick_target(actor))
	return CombatAction.use(_weighted_pick(offensive), _pick_target(actor))


## Finishes off a nearly-dead target, otherwise picks at random -- an AI that
## always focuses the weakest is both predictable and miserable to play against.
func _pick_target(actor: Combatant) -> Combatant:
	var candidates := _living(_party if not actor.is_player else _enemies)
	if candidates.is_empty():
		return null
	var wounded := _most_wounded(candidates)
	if wounded != null and wounded.hp_ratio() < 0.3:
		return wounded
	return candidates[_rng.randi() % candidates.size()]


func _weighted_pick(skills: Array) -> Skill:
	var total := 0.0
	for skill in skills:
		total += maxf(0.01, skill.ai_weight)
	var roll := _rng.randf() * total
	for skill in skills:
		roll -= maxf(0.01, skill.ai_weight)
		if roll <= 0.0:
			return skill
	return skills[skills.size() - 1]


func _most_wounded(candidates: Array[Combatant]) -> Combatant:
	var worst: Combatant = null
	for candidate in candidates:
		if worst == null or candidate.hp_ratio() < worst.hp_ratio():
			worst = candidate
	return worst


# --- finishing up ----------------------------------------------------------

func _end(result: CombatResult) -> void:
	var player := _party[0]
	# HP first, then XP: a level-up heals to full and that must be the last word.
	player.write_back()

	if result.victory:
		for enemy in _enemies:
			result.xp += enemy.xp_reward
			if not enemy.loot.is_empty() and _rng.randf() < enemy.loot_chance:
				result.loot.append(enemy.loot[_rng.randi() % enemy.loot.size()])
		if result.xp > 0:
			GameState.grant_xp(result.xp)
		for item_id in result.loot:
			EventBus.item_added.emit(item_id, 1)

	_actor = null
	_awaiting = false
	_pending = null
	_running = false
	GameState.pop_input_lock()
	combat_finished.emit(result)
	if result.fled:
		EventBus.combat_fled.emit()
	EventBus.combat_ended.emit(result.victory)


# --- plumbing --------------------------------------------------------------

func _report(report: CombatReport) -> void:
	action_resolved.emit(report)
	await _pause()


## The beat between steps. Yields a frame even at zero delay so the loop stays a
## coroutine and a view always gets a chance to draw.
func _pause() -> void:
	if step_delay > 0.0:
		await get_tree().create_timer(step_delay).timeout
	else:
		await get_tree().process_frame


func _living(group: Array[Combatant]) -> Array[Combatant]:
	return group.filter(func(c: Combatant) -> bool: return c.is_alive())
