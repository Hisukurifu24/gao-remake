extends Node
## What the player has been asked to do, and how far along they are.
##
## The whole system is one autoload plus five signal handlers, because every input
## a quest needs was already being announced by the time this was built:
##
## [codeblock]
## EventBus.quest_started       -> start()          somebody offered a quest
## EventBus.enemy_defeated      -> KILL objectives
## EventBus.inventory_changed   -> COLLECT objectives (recomputed from the bag)
## EventBus.dialogue_finished   -> TALK objectives
## EventBus.floor_cleared       -> REACH objectives
## EventBus.quest_turn_in_requested -> turn_in()    the player reported back
## [/codeblock]
##
## Nothing in combat, inventory, dialogue or the floor system knows this file
## exists. That is the payoff of the event bus and it is why quests landed without
## touching any of them.
##
## [b]Quest state is mirrored into [GameState] flags[/b] --
## [code]quest_<id>_started[/code], [code]_ready[/code], [code]_done[/code]. That
## single decision is what lets an NPC gate a line on a quest, a quest gate itself
## on another quest, and a chest open only for a quest-holder, all through
## [DialogueCondition]'s existing FLAG_SET test. Dialogue still knows nothing about
## quests, and there is one condition language in the game instead of two.
##
## Flow and view are separate, same as dialogue, inventory and combat: this owns
## the state, [code]ui/quest_journal.tscn[/code] and
## [code]ui/quest_tracker.tscn[/code] draw it, and
## [code]test/quest_test.tscn[/code] runs the whole system with neither
## instantiated.

## Where a quest is. LOCKED and UNKNOWN both mean "not in the journal"; they are
## separate because the first is a quest the player will get later and the second
## is a typo.
enum State {
	UNKNOWN,    ## No such quest id.
	LOCKED,     ## Exists, prerequisites not met.
	AVAILABLE,  ## Exists, could be taken, hasn't been.
	ACTIVE,     ## Taken, objectives outstanding.
	READY,      ## Every objective met, waiting to be turned in.
	COMPLETED,  ## Turned in and paid out.
}

## Suffixes on the [GameState] flags this writes. See the class docs.
const FLAG_STARTED := "started"
const FLAG_READY := "ready"
const FLAG_DONE := "done"

var _active: Dictionary[StringName, QuestProgress] = {}
## Id to the [Quest] that was finished, not to a bool: a quest handed in is still
## something the journal has to draw, and asking [QuestLibrary] for it again would
## make a quest that came from anywhere else unprintable.
var _completed: Dictionary[StringName, Quest] = {}
## Order taken, so the journal lists quests in the order the player picked them up
## rather than in whatever order a Dictionary feels like today.
var _order: Array[StringName] = []
## Which quest the on-screen tracker shows. The newest one that still needs doing,
## unless the player picks another in the journal.
var _tracked: StringName = &""


func _ready() -> void:
	EventBus.quest_started.connect(_on_quest_started)
	EventBus.quest_turn_in_requested.connect(_on_turn_in_requested)
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	EventBus.floor_cleared.connect(_on_floor_cleared)
	EventBus.inventory_changed.connect(_on_inventory_changed)


# --- reading ---------------------------------------------------------------

func state_of(id: StringName) -> State:
	if _completed.has(id):
		return State.COMPLETED
	if _active.has(id):
		return State.READY if _active[id].is_complete() else State.ACTIVE
	var quest := QuestLibrary.get_quest(id) if QuestLibrary.exists(id) else null
	if quest == null:
		return State.UNKNOWN
	return State.AVAILABLE if quest.is_available() else State.LOCKED


func is_active(id: StringName) -> bool:
	return _active.has(id)


## Taken, every objective met, not yet handed in. What a turn-in dialogue branch
## should be gated on -- or its [code]_ready[/code] flag, from a .tres.
func is_ready(id: StringName) -> bool:
	return _active.has(id) and _active[id].is_complete()


func is_completed(id: StringName) -> bool:
	return _completed.has(id)


## Whether [method start] would accept this quest right now.
func can_start(id: StringName) -> bool:
	return state_of(id) == State.AVAILABLE


func progress_for(id: StringName) -> QuestProgress:
	return _active.get(id, null)


## Live quests in the order they were taken, ready ones first -- the journal's
## list, and the reason the player does not have to scroll to find the one they
## can hand in.
func active_quests() -> Array[QuestProgress]:
	var ready: Array[QuestProgress] = []
	var running: Array[QuestProgress] = []
	for id in _order:
		var progress: QuestProgress = _active.get(id, null)
		if progress == null:
			continue
		if progress.is_complete():
			ready.append(progress)
		else:
			running.append(progress)
	return ready + running


func completed_quests() -> Array[Quest]:
	var done: Array[Quest] = []
	for id in _order:
		if _completed.has(id):
			done.append(_completed[id])
	return done


func active_count() -> int:
	return _active.size()


func completed_count() -> int:
	return _completed.size()


## The quest the on-screen tracker is showing, or null when there is nothing to
## show.
func tracked() -> QuestProgress:
	var progress: QuestProgress = _active.get(_tracked, null)
	if progress != null:
		return progress
	var live := active_quests()
	return live[0] if not live.is_empty() else null


## Points the tracker at [param id]. Ignored for anything that is not a live
## quest, so the journal can call it on whatever the cursor is over.
func track(id: StringName) -> bool:
	if not _active.has(id):
		return false
	_tracked = id
	EventBus.quest_log_changed.emit()
	return true


## The [GameState] flag naming one piece of a quest's state. The bridge described
## in the class docs -- dialogue conditions read these.
static func flag_for(id: StringName, suffix: String) -> StringName:
	return StringName("quest_%s_%s" % [id, suffix])


# --- taking a quest --------------------------------------------------------

## Puts [param id] in the journal. Refused for an unknown quest, one already taken
## or finished, and one whose prerequisites do not pass -- which is the case worth
## refusing loudly, because the dialogue choice that offered it should have been
## gated on the same conditions.
##
## Objectives are evaluated immediately on the way in, so a quest asking for five
## hides from a player already carrying five is [constant State.READY] before the
## conversation ends. Anything else would make the player throw them away and pick
## them back up.
func start(id: StringName) -> bool:
	if not can_start(id):
		return false
	return accept(QuestLibrary.get_quest(id))


## [method start] for a [Quest] already in hand. The library is a lookup, not a
## gatekeeper, so anything holding a quest resource can put it in the journal --
## which is what makes the no-turn-in path testable without shipping a quest to
## demonstrate it.
##
## Still checks prerequisites and still refuses a duplicate: the rules live here,
## not in whoever found the resource.
func accept(quest: Quest) -> bool:
	if quest == null or quest.id == &"":
		return false
	if _active.has(quest.id) or _completed.has(quest.id) or not quest.is_available():
		return false

	var id := quest.id
	var progress := QuestProgress.new(quest)
	_active[id] = progress
	if id not in _order:
		_order.append(id)
	_tracked = id
	GameState.set_flag(flag_for(id, FLAG_STARTED))

	_refresh_state_based(progress)
	EventBus.quest_accepted.emit(id)
	for objective in quest.listed_objectives():
		EventBus.quest_objective_updated.emit(
				id, objective.id, progress.of(objective), objective.required)
	_settle(progress)
	EventBus.quest_log_changed.emit()
	return true


# --- finishing it ---------------------------------------------------------

## Hands [param id] in: spends whatever it asked the player to collect, pays the
## rewards, and closes it. Refused unless the quest is [constant State.READY].
##
## Two things are re-checked here rather than trusted. The collect items, because
## the bag can empty between "ready" and the player walking back across town; and
## room for the reward, because a quest that pays into a full bag has destroyed
## what it paid. The room check runs *before* the collect items are spent, so it
## can refuse a turn-in that would in fact have fitted once three hides left the
## bag -- conservative on purpose, and it tells the player to make room rather
## than silently eating an Anneal Blade.
func turn_in(id: StringName) -> bool:
	if not is_ready(id):
		return false
	var quest: Quest = _active[id].quest

	if not _can_pay_collect(quest):
		_refresh_state_based(_active[id])
		_settle(_active[id])
		EventBus.quest_log_changed.emit()
		return false
	if not _has_room_for_rewards(quest):
		EventBus.message_requested.emit("", PackedStringArray([
			"Your bag is too full to take the reward for %s." % quest.label()]))
		return false

	# Closed out *before* the items are spent. Spending them emits
	# inventory_changed, which comes straight back here as a COLLECT refresh --
	# and a quest that is still in _active at that moment gets its progress reset
	# to zero on the way out the door.
	_active.erase(id)
	_completed[id] = quest
	if _tracked == id:
		_tracked = &""
	GameState.set_flag(flag_for(id, FLAG_READY), false)
	GameState.set_flag(flag_for(id, FLAG_DONE))

	for objective in quest.listed_objectives():
		if objective.kind == QuestObjective.Kind.COLLECT:
			Inventory.remove(objective.target, objective.required)

	# Rewards last, so a START_QUEST reward lands in a journal that already knows
	# this quest is finished -- a follow-up gated on quest_<id>_done must pass.
	DialogueEffect.apply_all(quest.rewards)

	EventBus.quest_completed.emit(id)
	EventBus.quest_log_changed.emit()
	return true


func clear() -> void:
	for id in _order:
		GameState.set_flag(flag_for(id, FLAG_STARTED), false)
		GameState.set_flag(flag_for(id, FLAG_READY), false)
		GameState.set_flag(flag_for(id, FLAG_DONE), false)
	_active.clear()
	_completed.clear()
	_order.clear()
	_tracked = &""
	EventBus.quest_log_changed.emit()


# --- objective progress ---------------------------------------------------

## Advances every live objective watching [param event_kind] / [param target] by
## one. The path for the *counted* kinds, KILL and TALK: an event with no lasting
## record, so if it is not tallied when it happens it is gone.
func _advance_event(event_kind: QuestObjective.Kind, target: StringName) -> void:
	var moved := false
	# Over a copy: announcing an objective is a signal, and a listener is allowed
	# to start a quest off the back of it.
	for progress in _active.values().duplicate():
		for objective in progress.quest.listed_objectives():
			if not objective.matches_event(event_kind, target):
				continue
			if progress.advance(objective):
				_announce(progress, objective)
				moved = true
	if moved:
		_settle_all()
		EventBus.quest_log_changed.emit()


## Re-reads every *state-based* objective from the world -- COLLECT from the bag,
## REACH from the cleared-floor list. Called whenever either changes, and these can
## go [i]down[/i]: spend the hides you were asked for and the objective is unmet
## again, which is the only honest answer when the requirement is "hold five".
func _refresh_state_based(progress: QuestProgress) -> bool:
	var moved := false
	for objective in progress.quest.listed_objectives():
		if not objective.is_state_based():
			continue
		if progress.set_progress(objective, objective.current_state()):
			_announce(progress, objective)
			moved = true
	return moved


func _refresh_all_state_based() -> void:
	var moved := false
	for progress in _active.values().duplicate():
		if _refresh_state_based(progress):
			moved = true
	if moved:
		_settle_all()
		EventBus.quest_log_changed.emit()


## Moves a quest into or out of [constant State.READY] after its progress changed.
## The [code]_ready[/code] flag is the whole reason a turn-in dialogue branch needs
## no new condition type, and it has to be able to go back off again.
func _settle(progress: QuestProgress) -> void:
	var id: StringName = progress.quest.id
	var complete := progress.is_complete()
	var flag := flag_for(id, FLAG_READY)
	var was_ready := GameState.has_flag(flag)

	if complete and not progress.quest.needs_turn_in:
		# Nothing to report back to. Pay it out where it was earned -- and if that
		# is refused (a full bag), fall through and leave it sitting at READY so it
		# is still consistent and still payable.
		if turn_in(id):
			return

	if complete == was_ready:
		return
	GameState.set_flag(flag, complete)
	if complete:
		EventBus.quest_ready.emit(id)


func _settle_all() -> void:
	# Over a copy: an auto-turn-in inside _settle mutates _active.
	for progress in _active.values().duplicate():
		if _active.has(progress.quest.id):
			_settle(progress)


func _announce(progress: QuestProgress, objective: QuestObjective) -> void:
	EventBus.quest_objective_updated.emit(progress.quest.id, objective.id,
			progress.of(objective), objective.required)


## Whether the bag still holds everything a COLLECT objective asked for.
## [method Inventory.remove] is all-or-nothing per item, so several collect
## objectives have to be checked together before any of them is spent.
func _can_pay_collect(quest: Quest) -> bool:
	var owed: Dictionary[StringName, int] = {}
	for objective in quest.listed_objectives():
		if objective.kind == QuestObjective.Kind.COLLECT:
			owed[objective.target] = owed.get(objective.target, 0) + objective.required
	for item_id in owed:
		if not Inventory.has(item_id, owed[item_id]):
			return false
	return true


func _has_room_for_rewards(quest: Quest) -> bool:
	for reward in quest.rewards:
		if reward == null or reward.kind != DialogueEffect.Kind.GIVE_ITEM:
			continue
		var item := ItemLibrary.get_item(reward.id)
		if item != null and not Inventory.fits(item, reward.amount):
			return false
	return true


# --- the five listeners ---------------------------------------------------

func _on_quest_started(id: StringName) -> void:
	start(id)


func _on_turn_in_requested(id: StringName) -> void:
	turn_in(id)


func _on_enemy_defeated(enemy_id: StringName) -> void:
	_advance_event(QuestObjective.Kind.KILL, enemy_id)


## A TALK objective naming the giver's own conversation completes on the very talk
## that handed the quest over, because this fires after that conversation closes.
## Deliberately not special-cased: "go back and tell them" is a *turn-in*, not an
## objective, and it has its own path.
func _on_dialogue_finished(dialogue_id: StringName) -> void:
	_advance_event(QuestObjective.Kind.TALK, dialogue_id)


func _on_floor_cleared(_floor_number: int) -> void:
	_refresh_all_state_based()


func _on_inventory_changed() -> void:
	_refresh_all_state_based()
