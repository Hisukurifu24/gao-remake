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
	_check(_argo_offers(argo, "Got any work for me?"), "Argo offers the errand")
	_check(not _argo_offers(argo, "The fields are handled."), "and does not offer to take it back yet")
	_check(not _argo_offers(argo, "Still working on it."), "nor asks how it is going")

	QuestLog.start(ERRAND)
	_check(not _argo_offers(argo, "Got any work for me?"), "once taken the offer is gone")
	_check(_argo_offers(argo, "Still working on it."), "and she asks how it is going instead")

	_finish_errand_objectives()
	_check(_argo_offers(argo, "The fields are handled."), "with it done she will take the report")
	_check(not _argo_offers(argo, "Still working on it."), "and stops asking")

	QuestLog.turn_in(ERRAND)
	_check(not _argo_offers(argo, "The fields are handled."), "reported once is reported")
	_check(_argo_offers(argo, "Anything bigger than boars?"),
			"and the follow-up is on offer")

	# The one failure mode of gating quests in dialogue: a choice offered for a
	# quest the log would refuse. Every offer in Argo's menu has to be startable
	# at the moment it is visible.
	_reset()
	GameState.set_flag(&"met_argo")
	_check(_argo_offers(argo, "Got any work for me?") == QuestLog.can_start(ERRAND),
			"the errand offer appears exactly when the errand can be started")
	_check(_argo_offers(argo, "Anything bigger than boars?") == QuestLog.can_start(ILLFANG),
			"and the follow-up offer tracks its own prerequisites")


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


## Opens Argo's menu, reads whether [param text] is a selectable choice, closes it.
func _argo_offers(argo: Dialogue, text: String) -> bool:
	DialogueRunner.start(argo)
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
