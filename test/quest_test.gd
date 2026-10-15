extends Node
## Exercises the M5 quest system against the real quest and dialogue resources.
##
##     "$GODOT" --headless --path . res://test/quest_test.tscn
##
## Run as a *scene*, not with --script: autoloads are registered after a script
## main loop is compiled, so QuestLog & co. wouldn't resolve.
##
## No journal and no tracker are instantiated here on purpose -- QuestLog is driven
## directly. If these pass and the game still looks wrong, the bug is in the view.
##
## The load-bearing part of this suite is [b]the objective-target sweep[/b] in
## `_test_content`. Every KILL names an enemy id, every COLLECT an item id, every
## TALK a conversation, every REACH a floor in range. A typo in any of them is
## silent in every other way the game can be observed: the kill simply never
## registers, and the quest can never be finished. It is the exact analogue of the
## inventory suite's item-id sweep and it exists for the same reason.

const ERRAND := &"argo_first_errand"
const BLADE := &"nezha_first_blade"
const ILLFANG := &"argo_illfang"
const WOLVES := &"ashlow_wolves"
const WARDEN := &"ashlow_warden"
const TAGS := &"lanternfall_tags"
const BREACH := &"lanternfall_breach"

var _failures: PackedStringArray = PackedStringArray()
var _checks := 0

# Signal spies. Members, not captured locals: GDScript lambdas capture by value.
var _accepted: Array[StringName] = []
var _ready_quests: Array[StringName] = []
var _completed: Array[StringName] = []
var _updates: Array[Array] = []
var _log_changes := 0


func _ready() -> void:
	EventBus.quest_accepted.connect(func(id: StringName) -> void: _accepted.append(id))
	EventBus.quest_ready.connect(func(id: StringName) -> void: _ready_quests.append(id))
	EventBus.quest_completed.connect(func(id: StringName) -> void: _completed.append(id))
	EventBus.quest_log_changed.connect(func() -> void: _log_changes += 1)
	EventBus.quest_objective_updated.connect(
		func(quest: StringName, objective: StringName, progress: int, required: int) -> void:
			_updates.append([quest, objective, progress, required]))

	_run()

	print("")
	if _failures.is_empty():
		print("quest test: %d checks passed" % _checks)
		get_tree().quit(0)
		return
	printerr("quest test: %d of %d checks FAILED" % [_failures.size(), _checks])
	for failure in _failures:
		printerr("  - ", failure)
	get_tree().quit(1)


func _run() -> void:
	_test_content()
	_test_availability()
	_test_kill_objectives()
	_test_talk_objectives()
	_test_collect_objectives()
	_test_reach_objectives()
	_test_turn_in()
	_test_rewards_and_chaining()
	_test_auto_complete()
	_test_flags_and_dialogue()
	_test_ashlow()
	_test_lanternfall()
	_test_settled_floors()
	_test_door_intel()
	_test_journal_ordering()


# --- content ---------------------------------------------------------------

func _test_content() -> void:
	print("\n-- content --")
	_reset()

	_check(QuestLibrary.all().size() == QuestLibrary.QUESTS.size(),
			"every listed quest loads (%d of %d)" % [
				QuestLibrary.all().size(), QuestLibrary.QUESTS.size()])

	var broken := PackedStringArray()
	for quest in QuestLibrary.all():
		if quest.id == &"" or quest.title.is_empty() or quest.summary.is_empty():
			broken.append(String(quest.id))
	_check(broken.is_empty(), "every quest has an id, a title and a summary (%s)" % broken)

	var mismatched := PackedStringArray()
	for id in QuestLibrary.QUESTS:
		var quest := QuestLibrary.get_quest(StringName(id))
		if quest != null and quest.id != StringName(id):
			mismatched.append("%s says %s" % [id, quest.id])
	_check(mismatched.is_empty(), "each quest's id matches its filename (%s)" % mismatched)

	var empty := PackedStringArray()
	for quest in QuestLibrary.all():
		if quest.listed_objectives().is_empty():
			empty.append(String(quest.id))
	_check(empty.is_empty(), "no quest ships with nothing to do (%s)" % empty)

	var duplicates := PackedStringArray()
	for quest in QuestLibrary.all():
		var seen: Array[StringName] = []
		for objective in quest.listed_objectives():
			if objective.id in seen:
				duplicates.append("%s/%s" % [quest.id, objective.id])
			seen.append(objective.id)
	_check(duplicates.is_empty(), "objective ids are unique within a quest (%s)" % duplicates)

	# The reason this suite exists. See the class docs.
	var orphans := PackedStringArray()
	for quest in QuestLibrary.all():
		for objective in quest.listed_objectives():
			if not objective.target_is_valid():
				orphans.append("%s/%s -> %s" % [
					quest.id, objective.id,
					objective.target if objective.target != &"" else str(objective.number)])
	_check(orphans.is_empty(), "every objective names something real (%s)" % orphans)

	var unreadable := PackedStringArray()
	for quest in QuestLibrary.all():
		for objective in quest.listed_objectives():
			if objective.label().strip_edges().is_empty():
				unreadable.append("%s/%s" % [quest.id, objective.id])
	_check(unreadable.is_empty(), "every objective has a readable line (%s)" % unreadable)

	# A reward that pays an item nobody has a resource for pays nothing at all,
	# and Inventory's push_error is the only sign of it.
	var bad_rewards := PackedStringArray()
	for quest in QuestLibrary.all():
		for reward in quest.rewards:
			if reward == null:
				continue
			if reward.kind == DialogueEffect.Kind.GIVE_ITEM and not ItemLibrary.exists(reward.id):
				bad_rewards.append("%s pays %s" % [quest.id, reward.id])
			if reward.kind == DialogueEffect.Kind.START_QUEST and not QuestLibrary.exists(reward.id):
				bad_rewards.append("%s chains into %s" % [quest.id, reward.id])
	_check(bad_rewards.is_empty(), "every reward names something real (%s)" % bad_rewards)

	var unpaid := PackedStringArray()
	for quest in QuestLibrary.all():
		if quest.reward_summary().is_empty():
			unpaid.append(String(quest.id))
	_check(unpaid.is_empty(), "every quest pays something the journal can show (%s)" % unpaid)

	var no_col := PackedStringArray()
	for quest in QuestLibrary.all():
		if _col_paid(quest) <= 0:
			no_col.append(String(quest.id))
	_check(no_col.is_empty(), "every quest pays Col (%s)" % no_col)

	_check(QuestLibrary.get_quest(&"no_such_quest") == null, "an unknown id yields null")
	_check(not QuestLibrary.exists(&"no_such_quest"), "exists() agrees about an unknown id")

	# Argo's dialogue has been emitting this id since M2. It is the one quest id
	# hard-coded in content rather than reachable from QuestLibrary, so if it ever
	# drifts the errand silently stops existing.
	_check(QuestLibrary.exists(ERRAND), "the id Argo's dialogue starts has a resource")


# --- availability ----------------------------------------------------------

func _test_availability() -> void:
	print("\n-- availability --")
	_reset()

	_check(QuestLog.state_of(&"no_such_quest") == QuestLog.State.UNKNOWN,
			"an unknown quest is UNKNOWN, not locked")
	_check(QuestLog.state_of(ERRAND) == QuestLog.State.AVAILABLE,
			"an unconditional quest is available from the start")
	_check(QuestLog.state_of(ILLFANG) == QuestLog.State.LOCKED,
			"a quest gated on another is locked until it")
	_check(not QuestLog.can_start(ILLFANG), "and cannot be started")
	_check(not QuestLog.start(ILLFANG), "start() refuses it")
	_check(QuestLog.active_count() == 0, "and nothing went into the journal")

	GameState.level = 1
	_check(QuestLog.state_of(BLADE) == QuestLog.State.LOCKED,
			"Nezha's quest is locked at level 1")
	GameState.level = 2
	_check(QuestLog.state_of(BLADE) == QuestLog.State.AVAILABLE,
			"and available at level 2")

	_accepted.clear()
	_check(QuestLog.start(ERRAND), "an available quest starts")
	_check(_accepted == [ERRAND], "and is announced as accepted")
	_check(QuestLog.state_of(ERRAND) == QuestLog.State.ACTIVE, "it is now ACTIVE")
	_check(not QuestLog.start(ERRAND), "starting it twice is refused")
	_check(QuestLog.active_count() == 1, "and it is in the journal once")

	# The request signal is the world asking; the log is what decides.
	_accepted.clear()
	EventBus.quest_started.emit(ILLFANG)
	_check(_accepted.is_empty(), "asking for a locked quest is refused, not queued")
	EventBus.quest_started.emit(BLADE)
	_check(_accepted == [BLADE], "asking for an available one accepts it")


# --- KILL ------------------------------------------------------------------

func _test_kill_objectives() -> void:
	print("\n-- kill objectives --")
	_reset()
	QuestLog.start(ERRAND)
	var progress := QuestLog.progress_for(ERRAND)
	var boars := QuestLibrary.get_quest(ERRAND).objective(&"boars")

	_check(progress != null and boars != null, "the errand has a kill objective")
	_check(progress.of(boars) == 0, "it starts at zero")

	_updates.clear()
	EventBus.enemy_defeated.emit(&"frenzy_boar")
	_check(progress.of(boars) == 1, "a kill counts")
	_check(_updates.size() == 1 and _updates[0][1] == &"boars",
			"and is announced with the objective it moved")
	_check(_updates[0][2] == 1 and _updates[0][3] == boars.required,
			"the announcement carries progress and requirement")

	EventBus.enemy_defeated.emit(&"little_nepent")
	_check(progress.of(boars) == 1, "killing something else does not count")

	_updates.clear()
	for i in 5:
		EventBus.enemy_defeated.emit(&"frenzy_boar")
	_check(progress.of(boars) == boars.required, "progress caps at the requirement")
	_check(_updates.size() == boars.required - 1,
			"and stops announcing once it is met (%d)" % _updates.size())
	_check(progress.is_objective_complete(boars), "the objective is complete")
	_check(not progress.is_complete(), "but the quest is not -- the talk is outstanding")
	_check(QuestLog.state_of(ERRAND) == QuestLog.State.ACTIVE, "so it stays ACTIVE")

	# A kill with nobody watching must not reach a quest that is not taken.
	_reset()
	EventBus.enemy_defeated.emit(&"frenzy_boar")
	_check(QuestLog.progress_for(ERRAND) == null, "a kill with no active quest goes nowhere")


# --- TALK ------------------------------------------------------------------

func _test_talk_objectives() -> void:
	print("\n-- talk objectives --")
	_reset()
	QuestLog.start(ERRAND)
	var progress := QuestLog.progress_for(ERRAND)
	var smith := QuestLibrary.get_quest(ERRAND).objective(&"smith")

	EventBus.dialogue_finished.emit(&"argo")
	_check(progress.of(smith) == 0, "the wrong conversation does not count")
	EventBus.dialogue_finished.emit(&"nezha")
	_check(progress.of(smith) == 1, "finishing the right one does")
	EventBus.dialogue_finished.emit(&"nezha")
	_check(progress.of(smith) == 1, "and talking again does not overshoot")


# --- COLLECT ---------------------------------------------------------------

func _test_collect_objectives() -> void:
	print("\n-- collect objectives --")
	_reset()
	GameState.level = 2
	QuestLog.start(BLADE)
	var progress := QuestLog.progress_for(BLADE)
	var hides := QuestLibrary.get_quest(BLADE).objective(&"hides")

	_check(progress.of(hides) == 0, "an empty bag means no progress")

	Inventory.add_id(&"boar_hide", 2)
	_check(progress.of(hides) == 2, "picking items up advances it")
	_check(not progress.is_objective_complete(hides), "two of three is not enough")

	# The decision this whole objective kind turns on: progress is *read* from the
	# bag, not accumulated from item_added, so it can go back down.
	Inventory.remove(&"boar_hide", 2)
	_check(progress.of(hides) == 0, "and throwing them away takes it back down")

	Inventory.add_id(&"boar_hide", 9)
	_check(progress.of(hides) == hides.required, "a surplus reads as complete, not as nine")

	Inventory.add_id(&"nepent_ovule", 2)
	_check(progress.is_complete(), "both collect objectives met completes the quest")
	_check(QuestLog.state_of(BLADE) == QuestLog.State.READY, "which puts it at READY")
	_check(_ready_quests == [BLADE], "and announces it once")
	_check(GameState.has_flag(&"quest_nezha_first_blade_ready"),
			"the ready flag is set so a turn-in branch can see it")

	# Ready has to be able to come back off again, or a player who drinks the
	# quest item keeps a turn-in that would fail.
	_ready_quests.clear()
	Inventory.remove(&"nepent_ovule", 1)
	_check(QuestLog.state_of(BLADE) == QuestLog.State.ACTIVE, "spending one drops it back to ACTIVE")
	_check(not GameState.has_flag(&"quest_nezha_first_blade_ready"), "and clears the ready flag")
	Inventory.add_id(&"nepent_ovule", 1)
	_check(QuestLog.state_of(BLADE) == QuestLog.State.READY, "putting it back makes it ready again")
	_check(_ready_quests == [BLADE], "and announces it again")

	# Taken with the bag already full of what it wants.
	_reset()
	GameState.level = 2
	Inventory.add_id(&"boar_hide", 3)
	Inventory.add_id(&"nepent_ovule", 2)
	QuestLog.start(BLADE)
	_check(QuestLog.state_of(BLADE) == QuestLog.State.READY,
			"a quest taken with its items already in the bag is ready at once")


# --- REACH -----------------------------------------------------------------

func _test_reach_objectives() -> void:
	print("\n-- reach objectives --")
	_reset()
	GameState.set_flag(QuestLog.flag_for(ERRAND, QuestLog.FLAG_DONE))
	_check(QuestLog.start(ILLFANG), "the follow-up unlocks once its flag is set")
	var progress := QuestLog.progress_for(ILLFANG)
	var objective := QuestLibrary.get_quest(ILLFANG).objective(&"illfang")

	_check(progress.of(objective) == 0, "an uncleared floor is no progress")
	GameState.clear_floor(2)
	_check(progress.of(objective) == 0, "clearing the wrong floor does not count")
	GameState.clear_floor(1)
	_check(progress.of(objective) == objective.required, "clearing floor 1 completes it")
	_check(QuestLog.state_of(ILLFANG) == QuestLog.State.READY, "and the quest is ready")

	# Read from the world, like COLLECT: a quest taken after the fact is already done.
	_reset()
	GameState.clear_floor(1)
	GameState.set_flag(QuestLog.flag_for(ERRAND, QuestLog.FLAG_DONE))
	QuestLog.start(ILLFANG)
	_check(QuestLog.state_of(ILLFANG) == QuestLog.State.READY,
			"taken after the boss is already down, it is ready immediately")


# --- turn-in ---------------------------------------------------------------

func _test_turn_in() -> void:
	print("\n-- turning in --")
	_reset()
	QuestLog.start(ERRAND)
	_check(not QuestLog.turn_in(ERRAND), "turning in an unfinished quest is refused")
	_check(QuestLog.is_active(ERRAND), "and it stays in the journal")

	_finish_errand_objectives()
	_check(QuestLog.is_ready(ERRAND), "with both objectives met it is ready")

	_completed.clear()
	_check(QuestLog.turn_in(ERRAND), "and turning it in is accepted")
	_check(_completed == [ERRAND], "which announces completion")
	_check(QuestLog.state_of(ERRAND) == QuestLog.State.COMPLETED, "the state is COMPLETED")
	_check(not QuestLog.is_active(ERRAND), "it is out of the active list")
	_check(QuestLog.completed_count() == 1, "and into the finished one")
	_check(not QuestLog.turn_in(ERRAND), "turning it in twice is refused")
	_check(not QuestLog.start(ERRAND), "and a finished quest cannot be retaken")

	# The request signal, same shape as quest_started.
	_reset()
	_completed.clear()
	EventBus.quest_turn_in_requested.emit(ERRAND)
	_check(_completed.is_empty(), "asking to turn in a quest you never took does nothing")
	QuestLog.start(ERRAND)
	EventBus.quest_turn_in_requested.emit(ERRAND)
	_check(_completed.is_empty(), "asking before the objectives are met does nothing")
	_finish_errand_objectives()
	EventBus.quest_turn_in_requested.emit(ERRAND)
	_check(_completed == [ERRAND], "asking once it is ready finishes it")

	# Collect turn-ins spend what they asked for. This is the only sink the
	# materials have, so it is the check that keeps them from being vendor trash.
	_reset()
	GameState.level = 2
	Inventory.add_id(&"boar_hide", 4)
	Inventory.add_id(&"nepent_ovule", 2)
	QuestLog.start(BLADE)
	_check(QuestLog.turn_in(BLADE), "a collect quest turns in")
	_check(Inventory.count(&"boar_hide") == 1,
			"and spends exactly what it asked for (%d left of 4)" % Inventory.count(&"boar_hide"))
	_check(Inventory.count(&"nepent_ovule") == 0, "including the second material")
	_check(Inventory.count(&"whetstone") == 2, "and pays the reward")

	# Ready, then the bag empties before the player walks back.
	_reset()
	GameState.level = 2
	Inventory.add_id(&"boar_hide", 3)
	Inventory.add_id(&"nepent_ovule", 2)
	QuestLog.start(BLADE)
	_check(QuestLog.is_ready(BLADE), "ready with the materials in hand")
	Inventory.remove(&"boar_hide", 3)
	_check(not QuestLog.turn_in(BLADE), "turning in after spending them is refused")
	_check(QuestLog.is_active(BLADE), "the quest is still live")
	_check(not QuestLog.is_ready(BLADE), "and no longer claims to be ready")
	_check(Inventory.count(&"nepent_ovule") == 2, "the other material was not eaten by the attempt")


# --- rewards ---------------------------------------------------------------

func _test_rewards_and_chaining() -> void:
	print("\n-- rewards --")
	_reset()
	QuestLog.start(ERRAND)
	_finish_errand_objectives()

	var xp_before := GameState.xp
	var level_before := GameState.level
	QuestLog.turn_in(ERRAND)
	var gained := GameState.xp - xp_before + (GameState.level - level_before) * 25
	_check(gained > 0, "turning in pays XP (%d)" % gained)
	_check(Inventory.count(&"small_potion") == 2, "and hands over the item reward")

	# Rewards go out after the quest is closed, so a follow-up gated on this
	# quest's _done flag can be started by this quest's own reward.
	_check(GameState.has_flag(QuestLog.flag_for(ERRAND, QuestLog.FLAG_DONE)),
			"the done flag is set")
	_check(not GameState.has_flag(QuestLog.flag_for(ERRAND, QuestLog.FLAG_READY)),
			"and the ready flag is cleared")
	_check(QuestLog.can_start(ILLFANG), "which unlocks the quest that was waiting on it")

	# A reward that cannot be paid should not be paid halfway.
	_reset()
	GameState.level = 2
	Inventory.add_id(&"boar_hide", 3)
	Inventory.add_id(&"nepent_ovule", 2)
	QuestLog.start(BLADE)
	_fill_bag()
	_check(not QuestLog.turn_in(BLADE), "a turn-in that could not pay out is refused")
	_check(QuestLog.is_active(BLADE), "the quest is untouched")
	_check(Inventory.count(&"boar_hide") == 3, "and the materials are still there")


# --- quests that need no turn-in ------------------------------------------

func _test_auto_complete() -> void:
	print("\n-- quests with nobody to report to --")
	_reset()

	# Built here rather than shipped: nothing in the floor-1 content has nobody to
	# report back to, and the path still has to be proven before something does.
	var quest := _auto_quest()
	_check(QuestLog.state_of(quest.id) == QuestLog.State.UNKNOWN,
			"the library does not know a quest it never listed")
	_check(QuestLog.accept(quest), "but the log takes one handed to it directly")
	_check(QuestLog.is_active(quest.id), "and it is active")
	_check(not QuestLog.accept(quest), "accepting the same one twice is refused")

	_completed.clear()
	_ready_quests.clear()
	EventBus.enemy_defeated.emit(&"frenzy_boar")
	_check(_completed == [quest.id], "meeting the last objective finishes it outright")
	_check(_ready_quests.is_empty(), "with no READY step in between")
	_check(QuestLog.state_of(quest.id) == QuestLog.State.COMPLETED, "the state is COMPLETED")
	_check(not GameState.has_flag(QuestLog.flag_for(quest.id, QuestLog.FLAG_READY)),
			"and no stale ready flag is left behind")
	_check(GameState.has_flag(QuestLog.flag_for(quest.id, QuestLog.FLAG_DONE)),
			"while the done flag is set")
	_check(GameState.xp == 5, "the reward is paid where it was earned (%d xp)" % GameState.xp)
	_check(QuestLog.completed_quests().size() == 1,
			"and a quest the library never had still draws in the journal")

	# The rules live in the log, not in whoever found the resource.
	_reset()
	var gated := _auto_quest()
	var condition := DialogueCondition.new()
	condition.test = DialogueCondition.Test.MIN_LEVEL
	condition.number = 5
	gated.prerequisites = [condition]
	_check(not QuestLog.accept(gated), "prerequisites are checked on this path too")
	_check(not QuestLog.accept(null), "and a null quest is refused rather than crashing")

	_reset()
	QuestLog.start(ERRAND)
	_check(QuestLibrary.get_quest(ERRAND).needs_turn_in,
			"the shipped quests all want reporting back")
	_finish_errand_objectives()
	_check(QuestLog.is_ready(ERRAND) and not QuestLog.is_completed(ERRAND),
			"so meeting their objectives is not the same as finishing them")


# --- flags, and the dialogue that reads them ------------------------------

func _test_flags_and_dialogue() -> void:
	print("\n-- flags and dialogue --")
	_reset()

	_check(QuestLog.flag_for(ERRAND, QuestLog.FLAG_STARTED) == &"quest_argo_first_errand_started",
			"the flag name is the documented one")

	_check(not GameState.has_flag(QuestLog.flag_for(ERRAND, QuestLog.FLAG_STARTED)),
			"no flag before the quest is taken")
	QuestLog.start(ERRAND)
	_check(GameState.has_flag(QuestLog.flag_for(ERRAND, QuestLog.FLAG_STARTED)),
			"taking it sets the started flag")
	_finish_errand_objectives()
	_check(GameState.has_flag(QuestLog.flag_for(ERRAND, QuestLog.FLAG_READY)),
			"meeting the objectives sets the ready flag")
	QuestLog.turn_in(ERRAND)
	_check(GameState.has_flag(QuestLog.flag_for(ERRAND, QuestLog.FLAG_DONE)),
			"turning it in sets the done flag")

	# The bridge, end to end: a DialogueCondition reading a quest with no
	# knowledge that quests exist.
	var condition := DialogueCondition.new()
	condition.test = DialogueCondition.Test.FLAG_SET
	condition.flag = QuestLog.flag_for(ERRAND, QuestLog.FLAG_DONE)
	_check(condition.is_met(), "a plain FLAG_SET condition can read quest state")

	# Argo's real conversation, driven through the runner with no box.
	_reset()
	GameState.set_flag(&"met_argo")
	var argo: Dialogue = load("res://resources/dialogue/argo.tres")
	_check(_offers(argo, "Got any work for me?"), "Argo offers the errand")
	_check(not _offers(argo, "The fields are handled."), "and does not offer to take it back yet")
	_check(not _offers(argo, "Still working on it."), "nor asks how it is going")

	QuestLog.start(ERRAND)
	_check(not _offers(argo, "Got any work for me?"), "once taken the offer is gone")
	_check(_offers(argo, "Still working on it."), "and she asks how it is going instead")

	_finish_errand_objectives()
	_check(_offers(argo, "The fields are handled."), "with it done she will take the report")
	_check(not _offers(argo, "Still working on it."), "and stops asking")

	QuestLog.turn_in(ERRAND)
	_check(not _offers(argo, "The fields are handled."), "reported once is reported")
	_check(_offers(argo, "Anything bigger than boars?"),
			"and the follow-up is on offer")

	# The one failure mode of gating quests in dialogue: a choice offered for a
	# quest the log would refuse. Every offer in Argo's menu has to be startable
	# at the moment it is visible.
	_reset()
	GameState.set_flag(&"met_argo")
	_check(_offers(argo, "Got any work for me?") == QuestLog.can_start(ERRAND),
			"the errand offer appears exactly when the errand can be started")
	_check(_offers(argo, "Anything bigger than boars?") == QuestLog.can_start(ILLFANG),
			"and the follow-up offer tracks its own prerequisites")


# --- floor 10, Ashlow ------------------------------------------------------

## Ashlow's pair of quests, and the one arrangement Floor 1 never exercised:
## a quest handed out by [b]another quest's reward[/b] rather than by a dialogue
## choice. Its prerequisite is the first quest's [code]_done[/code] flag, so it
## can only land because [method QuestLog.turn_in] sets that flag before it pays
## the rewards. That ordering is a comment in QuestLog today; here it is a check.
func _test_ashlow() -> void:
	print("\n-- floor 10, Ashlow --")
	_reset()

	var rue: Dialogue = load("res://resources/dialogue/rue.tres")
	var sable: Dialogue = load("res://resources/dialogue/sable.tres")

	_check(QuestLog.state_of(WOLVES) == QuestLog.State.LOCKED,
			"Ashlow's first job is locked until Floor 9 falls")
	_check(not _offers(rue, "I'll thin them out."), "and Rue does not offer it")

	GameState.clear_floor(9)
	_check(_offers(rue, "I'll thin them out.") == QuestLog.can_start(WOLVES),
			"Rue's offer appears exactly when the job can be started")

	QuestLog.start(WOLVES)
	_check(not _offers(rue, "I'll thin them out."), "once taken the offer is gone")
	_check(_offers(rue, "Still counting them."), "and he asks how it is going instead")

	for i in QuestLibrary.get_quest(WOLVES).objective(&"wolves").required:
		EventBus.enemy_defeated.emit(&"dire_wolf")
	_check(QuestLog.is_ready(WOLVES), "four wolves is four wolves")
	_check(_offers(rue, "The pack won't be back."), "and Rue will take the report")

	_check(QuestLog.state_of(WARDEN) == QuestLog.State.LOCKED,
			"the follow-up is locked while the first job is still open")
	QuestLog.turn_in(WOLVES)
	_check(QuestLog.is_active(WARDEN), "turning the first job in starts the follow-up")
	_check(Inventory.count(&"health_potion") == 2, "and pays the potions it promised")

	# Two objectives, and neither is the whole job. Note that reading Sable's
	# menu *is* the TALK objective: _offers finishes a real conversation with her.
	_check(not _offers(sable, "The hollow is empty. I made it empty."),
			"Sable has nothing to take on the way out")
	var survey := QuestLibrary.get_quest(WARDEN).objective(&"survey")
	_check(QuestLog.progress_for(WARDEN).of(survey) == survey.required,
			"but hearing her out ticks the survey off")
	_check(not QuestLog.is_ready(WARDEN), "which is still not a cleared floor")

	GameState.clear_floor(10)
	_check(QuestLog.is_ready(WARDEN), "putting the Warden down finishes it")
	_check(_offers(sable, "The hollow is empty. I made it empty."),
			"and Sable's report branch opens exactly then")

	QuestLog.turn_in(WARDEN)
	_check(QuestLog.is_completed(WARDEN), "Ashlow's chain closes out")
	_check(Inventory.count(&"warden_seal") == 1, "and the seal is in the bag")


# --- floor 25, Lanternfall -------------------------------------------------

## Lanternfall's two jobs, and the two things Ashlow's never asked of the system.
##
## Dorran's is a COLLECT over [b]key items that come out of chests[/b], which is
## the read-not-counted rule at its sharpest: a tag picked up before the job
## existed still counts, and the tags are spent at the turn-in -- the one way a
## key item may leave the bag. Maren's is offered on [b]a level[/b] rather than a
## flag or a floor, so it is the one offer that nothing done on the floor itself
## opens.
func _test_lanternfall() -> void:
	print("\n-- floor 25, Lanternfall --")
	_reset()

	var dorran: Dialogue = load("res://resources/dialogue/dorran.tres")
	var maren: Dialogue = load("res://resources/dialogue/maren.tres")

	_check(QuestLog.state_of(TAGS) == QuestLog.State.LOCKED,
			"Dorran's job is locked until Floor 24 falls")
	_check(not _offers(dorran, "What needs doing?"), "and he does not offer it")

	GameState.clear_floor(24)
	_check(_offers(dorran, "What needs doing?") == QuestLog.can_start(TAGS),
			"Dorran's offer appears exactly when the job can be started")

	# One tag found before the job was offered: the order a player who explores
	# first will actually do it in.
	Inventory.add_id(&"raid_tag", 1)
	QuestLog.start(TAGS)
	var tags := QuestLibrary.get_quest(TAGS).objective(&"tags")
	_check(QuestLog.progress_for(TAGS).of(tags) == 1,
			"a tag picked up before the job was taken still counts")
	_check(_offers(dorran, "Still looking."), "and Dorran asks how the search is going")

	Inventory.add_id(&"raid_tag", 2)
	_check(QuestLog.is_ready(TAGS), "three tags is the job")
	_check(_offers(dorran, "I found them. All three."), "and Dorran will take them")

	QuestLog.turn_in(TAGS)
	_check(QuestLog.is_completed(TAGS), "the names go on the wall")
	_check(Inventory.count(&"raid_tag") == 0, "the tags leave the bag")
	_check(Inventory.count(&"health_potion") == 3, "and the raid's potions come the other way")

	_check(not QuestLog.can_start(BREACH), "Maren's job is refused below level 30")
	_check(not _offers(maren, "Point me at the Breach."), "and she does not offer it")
	_check(_offers(maren, "What's down in the Breach?"), "though she will say why")

	GameState.level = 30
	_check(QuestLog.can_start(BREACH), "at level 30 the job can be started")
	_check(_offers(maren, "Point me at the Breach.") == QuestLog.can_start(BREACH),
			"and her offer appears exactly then")

	QuestLog.start(BREACH)
	GameState.clear_floor(25)
	_check(not QuestLog.is_ready(BREACH), "the door alone is not the whole job")
	for i in QuestLibrary.get_quest(BREACH).objective(&"kobolds").required:
		EventBus.enemy_defeated.emit(&"kobold_trooper")
	_check(QuestLog.is_ready(BREACH), "the kobolds and the door together are")
	_check(_offers(maren, "The Breach is shut. For good."), "and Maren's report branch opens")

	QuestLog.turn_in(BREACH)
	_check(QuestLog.is_completed(BREACH), "Lanternfall's second job closes out")
	_check(Inventory.count(&"foremans_lantern") == 1, "and the lantern is in the bag")


# --- settled floors' jobs ---------------------------------------------------

## A settled floor's jobs are built, not shipped, so the sweep above never sees
## them: this is the same sweep over everything [LocalQuests] can emit, on every
## floor that settles and on two saves -- and then one job of each kind, taken,
## done and handed in through the settler's real conversation.
func _test_settled_floors() -> void:
	print("\n-- settled floors' jobs --")
	_reset()

	var problems := PackedStringArray()
	var kinds: Dictionary[String, int] = {}
	var jobs := 0
	for world: int in [12345, 999]:
		GameState.new_world_seed(world)
		for n in range(1, FloorTuning.TOP_FLOOR + 1):
			var ids := LocalQuests.ids_for(n)
			if not LocalQuests.settles(n):
				if not ids.is_empty():
					problems.append("floor %d never settles but has jobs" % n)
				continue
			if ids.size() != LocalQuests.PER_FLOOR:
				problems.append("floor %d has %d jobs" % [n, ids.size()])
			for id in ids:
				jobs += 1
				var problem := _local_problem(id, n)
				if not problem.is_empty():
					problems.append(problem)
				kinds[String(id).get_slice("_", 2)] = kinds.get(String(id).get_slice("_", 2), 0) + 1
	GameState.new_world_seed(12345)
	_check(problems.is_empty(), "every settled floor's job names something real, says something whole and is offered on its own prerequisite (%d jobs; %s)" % [
			jobs, "; ".join(problems.slice(0, 5))])
	_check(kinds.size() == LocalQuests.KINDS.size(),
			"every kind of job turns up somewhere (%s)" % kinds)
	_check(not QuestLibrary.exists(&"local_10_hunt") and not QuestLibrary.exists(&"local_99_hunt")
			and not QuestLibrary.exists(&"local_7_bake") and not QuestLibrary.exists(&"local_x_hunt"),
			"an authored floor, a floor too high to settle, an unknown job and a garbled id are not jobs")
	_check(LocalQuests.is_conversation(LocalQuests.lost_talk_id(_floor_with("lost")))
			and not LocalQuests.is_conversation(&"local_7_lost_found_again")
			and not LocalQuests.is_conversation(&"argo"),
			"only a real lost player's conversation is one")

	# One of each, the way the player does it.
	for kind: String in ["hunt", "gather", "lost"]:
		_reset()
		var n := _floor_with(kind)
		var id := LocalQuests.quest_id(n, kind)
		var giver := LocalQuests.giver_dialogue(id)
		_check(QuestLog.state_of(id) == QuestLog.State.LOCKED and not _offers(giver, "I'll do it."),
				"floor %d's %s job is locked, and not offered, until it settles" % [n, kind])
		GameState.clear_floor(n + LocalQuests.SETTLE_AFTER)
		_check(_offers(giver, "I'll do it.") == QuestLog.can_start(id) and QuestLog.can_start(id),
				"and offered exactly when it can be taken, once floor %d is cleared" % [n + LocalQuests.SETTLE_AFTER])
		_pick(giver, "I'll do it.")
		_check(QuestLog.is_active(id), "taking floor %d's %s job puts it in the journal" % [n, kind])
		var quest := QuestLibrary.get_quest(id)
		var objective := quest.objectives[0]
		match kind:
			"hunt":
				for i in objective.required:
					EventBus.enemy_defeated.emit(objective.target)
			"gather":
				Inventory.add_id(objective.target, objective.required)
			"lost":
				_offers(LocalQuests.lost_dialogue(n), "")
		_check(QuestLog.is_ready(id), "doing it makes it ready (%s)" % objective.label())
		var level_before := GameState.level
		var xp_before := GameState.xp
		var col_before := GameState.col()
		_pick(giver, "Here.")
		var item: DialogueEffect = null
		var col := 0
		for reward in quest.rewards:
			if reward.kind == DialogueEffect.Kind.GIVE_ITEM:
				item = reward
			elif reward.kind == DialogueEffect.Kind.GIVE_COL:
				col += reward.amount
		_check(QuestLog.is_completed(id) and item != null and Inventory.count(item.id) >= item.amount
				and col > 0 and GameState.col() == col_before + col
				and (GameState.level > level_before or GameState.xp > xp_before),
				"and %s takes it back and pays %s" % [quest.giver, quest.reward_summary()])
		if kind == "gather":
			_check(Inventory.count(objective.target) == 0, "spending what was gathered")


func _col_paid(quest: Quest) -> int:
	var total := 0
	for reward in quest.rewards:
		if reward != null and reward.kind == DialogueEffect.Kind.GIVE_COL:
			total += reward.amount
	return total


## What is wrong with job [param id] on floor [param n], or "".
func _local_problem(id: StringName, n: int) -> String:
	if not QuestLibrary.exists(id):
		return "%s does not exist" % id
	var quest := QuestLibrary.get_quest(id)
	if quest == null or quest.id != id or quest.title.is_empty() or quest.summary.is_empty() \
			or quest.giver.is_empty() or quest.reward_summary().is_empty():
		return "%s is missing its title, summary, giver or pay" % id
	for text in [quest.title, quest.summary]:
		if "{" in text:
			return "%s says \"%s\"" % [id, text]
	for objective in quest.listed_objectives():
		if not objective.target_is_valid() or objective.label().strip_edges().is_empty():
			return "%s/%s names %s" % [id, objective.id, objective.target]
	for reward in quest.rewards:
		if reward.kind == DialogueEffect.Kind.GIVE_ITEM and not ItemLibrary.exists(reward.id):
			return "%s pays %s" % [id, reward.id]
	if _col_paid(quest) <= 0:
		return "%s pays no Col" % id
	var talks: Array[Dialogue] = [LocalQuests.giver_dialogue(id)]
	if String(id).ends_with("_lost"):
		talks.append(LocalQuests.lost_dialogue(n))
	for talk in talks:
		if talk == null or talk.entry_index() < 0 or talk.default_portrait == null:
			return "%s has nobody to say it" % id
		for line in talk.lines:
			if line.text.is_empty() or "{" in line.text:
				return "%s's %s says \"%s\"" % [id, talk.id, line.text]
	# The offer and the prerequisite gated on the same thing, as Quest asks.
	for line in talks[0].lines:
		for choice in line.choices:
			for effect in choice.effects:
				if effect.kind != DialogueEffect.Kind.START_QUEST:
					continue
				var floors: Array[int] = []
				for condition in choice.conditions:
					if condition.test == DialogueCondition.Test.FLOOR_CLEARED:
						floors.append(condition.number)
				var wanted: Array[int] = []
				for condition in quest.prerequisites:
					wanted.append(condition.number)
				if floors != wanted:
					return "%s is offered on %s but needs %s" % [id, floors, wanted]
	return ""


## The lowest floor whose village offers a [param kind] job, on this save.
func _floor_with(kind: String) -> int:
	for n in range(2, FloorTuning.TOP_FLOOR + 1):
		if LocalQuests.quest_id(n, kind) in LocalQuests.ids_for(n):
			return n
	return -1


## Talks [param dialogue] through to its menu, picks [param text], and talks it
## out to the end.
func _pick(dialogue: Dialogue, text: String) -> void:
	DialogueRunner.start(dialogue)
	for i in 12:
		if DialogueRunner.is_choosing():
			break
		DialogueRunner.advance()
	var choices := DialogueRunner.offered_choices()
	for i in choices.size():
		if choices[i].text == text:
			DialogueRunner.choose(i)
			break
	for i in 12:
		if not DialogueRunner.is_running():
			break
		DialogueRunner.advance()
	if DialogueRunner.is_running():
		DialogueRunner.cancel()


# --- Argo's door information (M5.6) ---------------------------------------

## What she sells, at what price, through her real menu and the conversation it
## queues -- and that a bought door is charted when its floor is next built.
func _test_door_intel() -> void:
	print("\n-- Argo's door information --")
	_reset()
	GameState._visited_floors.clear()
	GameState.visit_floor(1)
	_check(DoorIntel.offers().is_empty() and DoorIntel.conversation().lines.size() == 1
			and DoorIntel.conversation().lines[0].choices.is_empty(),
			"with only floor 1 stood on she has nothing to sell, and says so")
	for n in [2, 3, 4, 5]:
		GameState.visit_floor(n)
	GameState.clear_floor(1)
	GameState.clear_floor(2)
	GameState.set_flag(BossGate.found_flag(3))
	_check(DoorIntel.offers() == [5, 4],
			"she sells doors you have stood near and not found, highest first (%s)" % [DoorIntel.offers()])
	_check(DoorIntel.price(5) == FloorTuning.kill_col(5) * FloorTuning.monster_count(5)
			and DoorIntel.price(50) > DoorIntel.price(5),
			"a door costs a floor's hunting: %d col on floor 5, %d on 50" % [DoorIntel.price(5),
			DoorIntel.price(50)])

	var argo: Dialogue = load("res://resources/dialogue/argo.tres")
	GameState.set_flag(&"met_argo")
	_check(_offers(argo, "Know where any doors are?"), "her menu asks about doors once Illfang is down")
	var price := DoorIntel.price(5)
	_check(not _intel_choice(argo, 5, false), "broke, floor 5's door is offered and locked")
	EventBus.col_granted.emit(price + 7)
	_check(_intel_choice(argo, 5, true), "with the Col, it can be bought")
	_check(GameState.col() == 7 and GameState.has_flag(BossGate.found_flag(5)),
			"buying it takes the price and marks the door found")
	_check(DoorIntel.offers() == [4], "and it is off her list")

	# The bought door's room is on the map the next time the floor is built --
	# and the labyrinth in front of it is not.
	var map := FloorRegistry.build_floor(5) as GameMap
	add_child(map)
	var gate := map.get_node_or_null("BossGate") as BossGate
	var seen := GameState.explored_cells(map.map_id)
	var walls := map.get_node("Walls") as TileMapLayer
	var door := walls.local_to_map(walls.to_local(gate.global_position)) if gate != null else Vector2i.ZERO
	var mouth: Vector2i = (map.get_meta(&"labyrinth_mouth", Rect2i()) as Rect2i).get_center()
	_check(gate != null and gate.revealed and seen.has(door),
			"on floor 5 the door stands and its room is charted")
	_check(not seen.has(mouth), "but the way through the labyrinth is not")
	map.free()
	GameState._explored.clear()
	GameState._visited_floors.clear()
	_reset()


## Opens Argo's menu, asks about doors, and in the pitch it queues picks floor
## [param floor_number]'s door if [param buy] -- else just reports whether it was
## there and unlocked. Returns whether that choice was offered and unlocked.
func _intel_choice(argo: Dialogue, floor_number: int, buy: bool) -> bool:
	DialogueRunner.start(argo)
	for i in 12:
		if DialogueRunner.is_choosing():
			break
		DialogueRunner.advance()
	var menu := DialogueRunner.offered_choices()
	for i in menu.size():
		if menu[i].text == "Know where any doors are?":
			DialogueRunner.choose(i)
	var unlocked := false
	var wanted := "Floor %d's door. (%d col)" % [floor_number, DoorIntel.price(floor_number)]
	for i in 12:
		if not DialogueRunner.is_running():
			break
		if DialogueRunner.is_choosing():
			var offered := DialogueRunner.offered_choices()
			for j in offered.size():
				if offered[j].text == wanted and offered[j].is_unlocked():
					unlocked = true
					if buy:
						DialogueRunner.choose(j)
			break
		DialogueRunner.advance()
	for i in 12:
		if not DialogueRunner.is_running():
			break
		if DialogueRunner.is_choosing():
			DialogueRunner.cancel()
		else:
			DialogueRunner.advance()
	return unlocked


# --- the journal's view ---------------------------------------------------

func _test_journal_ordering() -> void:
	print("\n-- journal ordering --")
	_reset()
	GameState.level = 2

	QuestLog.start(ERRAND)
	QuestLog.start(BLADE)
	var order := _active_ids()
	_check(order == [ERRAND, BLADE], "quests list in the order they were taken (%s)" % [order])

	_finish_errand_objectives()
	order = _active_ids()
	_check(order == [ERRAND, BLADE], "a ready quest sorts to the top")

	Inventory.add_id(&"boar_hide", 3)
	Inventory.add_id(&"nepent_ovule", 2)
	QuestLog.turn_in(BLADE)
	_check(_active_ids() == [ERRAND], "a finished quest leaves the active list")
	_check(QuestLog.completed_quests().size() == 1, "and appears in the finished one")

	# The tracker follows the newest live quest unless told otherwise, and never
	# points at a quest that is gone.
	_reset()
	_check(QuestLog.tracked() == null, "nothing is tracked with an empty journal")
	QuestLog.start(ERRAND)
	_check(QuestLog.tracked().quest.id == ERRAND, "taking a quest tracks it")
	GameState.level = 2
	QuestLog.start(BLADE)
	_check(QuestLog.tracked().quest.id == BLADE, "and so does taking the next one")
	_check(QuestLog.track(ERRAND), "the journal can point it back")
	_check(QuestLog.tracked().quest.id == ERRAND, "and it stays there")
	_check(not QuestLog.track(&"no_such_quest"), "tracking a non-quest is refused")
	_check(QuestLog.tracked().quest.id == ERRAND, "and changes nothing")

	_finish_errand_objectives()
	QuestLog.turn_in(ERRAND)
	_check(QuestLog.tracked().quest.id == BLADE,
			"turning in the tracked quest falls back to another live one")


# --- helpers ---------------------------------------------------------------

## Back to a fresh save: empty journal, empty bag, no cleared floors, level 1.
## Every section starts here so one section cannot pass because of another's
## leftovers -- which for a system built entirely out of persistent flags is the
## easiest way to write a test that proves nothing.
func _reset() -> void:
	QuestLog.clear()
	Inventory.clear()
	GameState.reset_col()
	GameState.level = 1
	GameState.xp = 0
	GameState._cleared_floors.clear()
	GameState._flags.clear()
	_accepted.clear()
	_ready_quests.clear()
	_completed.clear()
	_updates.clear()
	_log_changes = 0


func _finish_errand_objectives() -> void:
	var boars := QuestLibrary.get_quest(ERRAND).objective(&"boars")
	for i in boars.required:
		EventBus.enemy_defeated.emit(&"frenzy_boar")
	EventBus.dialogue_finished.emit(&"nezha")


## A one-objective quest with nobody to report back to, for the auto-complete path.
func _auto_quest() -> Quest:
	var quest := Quest.new()
	quest.id = &"test_auto"
	quest.title = "Nobody To Tell"
	quest.needs_turn_in = false

	var objective := QuestObjective.new()
	objective.id = &"boars"
	objective.kind = QuestObjective.Kind.KILL
	objective.target = &"frenzy_boar"
	quest.objectives = [objective]

	var reward := DialogueEffect.new()
	reward.kind = DialogueEffect.Kind.GRANT_XP
	reward.amount = 5
	quest.rewards = [reward]
	return quest


func _active_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for progress in QuestLog.active_quests():
		ids.append(progress.quest.id)
	return ids


## Fills the bag with things no quest wants, so a reward has nowhere to land.
func _fill_bag() -> void:
	while not Inventory.is_full():
		Inventory.add_id(&"bat_wing", 1)
		Inventory.add_id(&"wolf_fang", 1)
		Inventory.add_id(&"lizard_scale", 1)
		Inventory.add_id(&"drake_scale", 1)
		Inventory.add_id(&"golem_core", 1)
		Inventory.add_id(&"spirit_ash", 1)
		Inventory.add_id(&"kobold_fang", 1)
		Inventory.add_id(&"leather_coat", 1)


## Opens an NPC's menu, reads whether [param text] is a selectable choice, closes
## it again.
##
## Closing counts as finishing the conversation, so this emits
## [signal EventBus.dialogue_finished] like any other talk -- which is correct,
## and which a TALK objective watching this NPC will act on. Ask in the order the
## player would.
func _offers(dialogue: Dialogue, text: String) -> bool:
	DialogueRunner.start(dialogue)
	for i in 12:
		if DialogueRunner.is_choosing():
			break
		DialogueRunner.advance()

	var offered := false
	for choice in DialogueRunner.offered_choices():
		if choice.text == text and choice.is_unlocked():
			offered = true
	DialogueRunner.cancel()
	return offered


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", description)
	else:
		print("  FAIL ", description)
		_failures.append(description)
