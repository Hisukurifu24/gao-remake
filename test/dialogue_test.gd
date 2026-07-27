extends Node
## Exercises the M2 dialogue system against the real Argo/Nezha resources.
##
##     "$GODOT" --headless --path . res://test/dialogue_test.tscn
##
## Run as a *scene*, not with --script: autoloads are registered after a script
## main loop is compiled, so DialogueRunner & co. wouldn't resolve.
##
## No dialogue box is instantiated here on purpose -- the runner is driven
## directly through advance()/choose(). If these pass and the game still looks
## wrong, the bug is in the view, not the flow.

const ARGO := "res://resources/dialogue/argo.tres"
const NEZHA := "res://resources/dialogue/nezha.tres"

var _failures: PackedStringArray = PackedStringArray()
var _checks := 0

# Signal spies. Members, not captured locals: GDScript lambdas capture by value.
var _lines_seen: PackedStringArray = PackedStringArray()
var _speakers_seen: PackedStringArray = PackedStringArray()
var _started: Array[StringName] = []
var _finished: Array[StringName] = []
var _items: Array[StringName] = []
var _quests: Array[StringName] = []


func _ready() -> void:
	DialogueRunner.line_shown.connect(_spy_line)
	EventBus.dialogue_started.connect(func(id: StringName) -> void: _started.append(id))
	EventBus.dialogue_finished.connect(func(id: StringName) -> void: _finished.append(id))
	EventBus.item_added.connect(func(id: StringName, _n: int) -> void: _items.append(id))
	EventBus.quest_started.connect(func(id: StringName) -> void: _quests.append(id))

	_run()

	print("")
	if _failures.is_empty():
		print("dialogue test: %d checks passed" % _checks)
		get_tree().quit(0)
		return
	printerr("dialogue test: %d of %d checks FAILED" % [_failures.size(), _checks])
	for failure in _failures:
		printerr("  - ", failure)
	get_tree().quit(1)


func _run() -> void:
	_test_conditions()
	_test_plain_text()
	_test_entry_selection()
	_test_choices()
	_test_effects()
	_test_jumps()
	_test_queue_and_cancel()
	_test_progression_gated_content()


# --- conditions ------------------------------------------------------------

func _test_conditions() -> void:
	GameState.set_flag(&"cond_probe", false)
	var flag_set := _condition(DialogueCondition.Test.FLAG_SET, &"cond_probe")
	_check(not flag_set.is_met(), "an unset flag fails FLAG_SET")

	GameState.set_flag(&"cond_probe")
	_check(flag_set.is_met(), "a set flag passes FLAG_SET")

	flag_set.negate = true
	_check(not flag_set.is_met(), "negate inverts the test")

	var level := _condition(DialogueCondition.Test.MIN_LEVEL, &"")
	level.number = GameState.level + 1
	_check(not level.is_met(), "MIN_LEVEL fails below the requirement")
	level.number = GameState.level
	_check(level.is_met(), "MIN_LEVEL passes at the requirement")

	var floor_cleared := _condition(DialogueCondition.Test.FLOOR_CLEARED, &"")
	floor_cleared.number = 1
	_check(not floor_cleared.is_met(), "FLOOR_CLEARED fails before the boss")

	var empty: Array[DialogueCondition] = []
	_check(DialogueCondition.all_met(empty), "no conditions means always available")


# --- plain text ------------------------------------------------------------

func _test_plain_text() -> void:
	_lines_seen.clear()
	DialogueRunner.say("Chest", PackedStringArray(["One.", "Two.", "Three."]))
	_check(DialogueRunner.is_running(), "say() opens a conversation")
	_check(GameState.is_input_locked(), "an open conversation locks input")
	_check(_lines_seen.size() == 1, "lines are shown one at a time")

	DialogueRunner.advance()
	DialogueRunner.advance()
	_check(_lines_seen.size() == 3, "advancing walks the array in order (got %d)" % _lines_seen.size())
	_check(_speakers_seen[2] == "Chest", "the default speaker carries to every line")

	DialogueRunner.advance()
	_check(not DialogueRunner.is_running(), "advancing off the last line ends it")
	_check(not GameState.is_input_locked(), "ending a conversation unlocks input")

	# EventBus.message_requested is the same path -- chests and signs use it.
	_lines_seen.clear()
	EventBus.message_requested.emit("", PackedStringArray(["The chest is empty."]))
	_check(DialogueRunner.is_running(), "message_requested reaches the runner")
	DialogueRunner.advance()
	_check(not DialogueRunner.is_running(), "a one-line message closes on the first press")


# --- entry selection -------------------------------------------------------

func _test_entry_selection() -> void:
	var argo := load(ARGO) as Dialogue
	_check(argo != null and argo.id == &"argo", "the Argo resource loads")
	_check(argo.lines.size() > 0, "the Argo resource has lines")

	GameState.set_flag(&"met_argo", false)
	_check(argo.lines[argo.entry_index()].id == &"greet_first",
			"a stranger gets the first-meeting greeting")

	GameState.set_flag(&"met_argo")
	_check(argo.lines[argo.entry_index()].id == &"greet_return",
			"a known player gets the returning greeting")

	_started.clear()
	_finished.clear()
	DialogueRunner.start(argo)
	_check(_started == [&"argo"], "starting a dialogue announces its id")
	_check(DialogueRunner.current_dialogue_id() == &"argo", "the runner reports what is open")
	_close()
	_check(_finished == [&"argo"], "finishing a dialogue announces its id")

	# A gated block is skipped in full: the line it would have fallen through to
	# is a continuation, not a second way in.
	var blocks := Dialogue.new()
	blocks.id = &"blocks"
	var gated := DialogueLine.new()
	gated.id = &"gated"
	gated.text = "Gated opener."
	gated.conditions = [_condition(DialogueCondition.Test.FLAG_SET, &"never_set")]
	var continuation := DialogueLine.new()
	continuation.text = "Gated continuation."
	continuation.next = DialogueLine.END
	var fallback := DialogueLine.new()
	fallback.id = &"fallback"
	fallback.text = "Fallback."
	blocks.lines = [gated, continuation, fallback]
	_check(blocks.lines[blocks.entry_index()].id == &"fallback",
			"a gated block is skipped whole, continuation included")

	# A dialogue whose every line is gated off has nothing to say, which is not
	# an error -- it must simply not open.
	var silent := Dialogue.new()
	silent.id = &"silent"
	var line := DialogueLine.new()
	line.text = "Never."
	line.conditions = [_condition(DialogueCondition.Test.FLAG_SET, &"never_set")]
	silent.lines = [line]
	DialogueRunner.start(silent)
	_check(not DialogueRunner.is_running(), "a fully gated dialogue does not open")
	_check(not GameState.is_input_locked(), "a dialogue that never opened leaks no input lock")


# --- choices ---------------------------------------------------------------

func _test_choices() -> void:
	GameState.set_flag(&"met_nezha", false)
	QuestLog.clear()
	_open_menu()
	_check(DialogueRunner.is_choosing(), "the menu line offers choices")

	var labels := _choice_texts()
	_check(not labels.has("What do you know about Nezha?"),
			"a hidden choice is absent until its condition passes")
	_check(labels.has("Sell me a map of Floor Two."),
			"a locked choice with hide_when_locked=false is still listed")

	var map_choice := DialogueRunner.offered_choices()[_choice_index("Sell me a map")]
	_check(not map_choice.is_unlocked(), "the map choice is locked before floor 1 falls")
	_check(map_choice.label().ends_with("(not until Illfang falls)"),
			"a locked choice shows its hint")

	var before := _lines_seen.size()
	DialogueRunner.choose(_choice_index("Sell me a map"))
	_check(DialogueRunner.is_choosing() and _lines_seen.size() == before,
			"choosing a locked option is refused")
	DialogueRunner.choose(99)
	_check(DialogueRunner.is_choosing(), "choosing out of range is refused")
	_close()

	GameState.set_flag(&"met_nezha")
	_open_menu()
	_check(_choice_texts().has("What do you know about Nezha?"),
			"meeting Nezha unlocks the question about him")
	_close()


# --- effects ---------------------------------------------------------------

func _test_effects() -> void:
	QuestLog.clear()
	_quests.clear()
	_open_menu()
	_check(_choice_texts().has("Got any work for me?"), "the errand is on offer")

	DialogueRunner.choose(_choice_index("Got any work"))
	_check(_quests == [&"argo_first_errand"], "taking the errand starts the quest")
	# The dialogue's own bookkeeping flag is gone: QuestLog writes
	# quest_<id>_started and Argo's choice reads that, so there is one answer to
	# "has this been taken" instead of two that can disagree.
	_check(GameState.has_flag(&"quest_argo_first_errand_started"),
			"taking the errand puts it in the quest log")
	_close()

	_open_menu()
	_check(not _choice_texts().has("Got any work for me?"),
			"an errand already taken is no longer offered")
	_close()


# --- flow ------------------------------------------------------------------

func _test_jumps() -> void:
	_open_menu()
	_lines_seen.clear()
	DialogueRunner.choose(_choice_index("Where do I find"))
	_check(_lines_seen.size() == 1 and _lines_seen[0].begins_with("Illfang the Kobold Lord"),
			"a choice jumps to its target line")

	DialogueRunner.advance()
	_check(_lines_seen.size() == 2, "a line with no next falls through to the following one")

	DialogueRunner.advance()
	_check(DialogueRunner.is_choosing(), "the branch returns to the menu")
	_close()

	# Explicit END, versus falling off the end of the array.
	var ends := Dialogue.new()
	ends.id = &"ends"
	var first := DialogueLine.new()
	first.text = "Stop here."
	first.next = DialogueLine.END
	var unreachable := DialogueLine.new()
	unreachable.text = "Never seen."
	ends.lines = [first, unreachable]

	_lines_seen.clear()
	DialogueRunner.start(ends)
	DialogueRunner.advance()
	_check(not DialogueRunner.is_running() and _lines_seen.size() == 1,
			"next = END closes the box without reading on")


func _test_queue_and_cancel() -> void:
	var first := Dialogue.from_lines("A", PackedStringArray(["First."]))
	first.id = &"first"
	var second := Dialogue.from_lines("B", PackedStringArray(["Second."]))
	second.id = &"second"

	_finished.clear()
	DialogueRunner.start(first)
	DialogueRunner.start(second)
	_check(DialogueRunner.current_dialogue_id() == &"first",
			"a second conversation waits its turn")
	DialogueRunner.advance()
	_check(DialogueRunner.current_dialogue_id() == &"second",
			"the queued conversation follows the first")
	_check(_finished == [&"first"], "only the finished one is announced")
	DialogueRunner.advance()
	_check(not DialogueRunner.is_running(), "the queue drains")
	_check(not GameState.is_input_locked(), "a queued run leaves the input lock balanced")

	DialogueRunner.start(load(ARGO) as Dialogue)
	DialogueRunner.cancel()
	_check(not DialogueRunner.is_running(), "cancel() closes a conversation mid-line")
	_check(not GameState.is_input_locked(), "cancel() releases the input lock")

	_open_menu()
	DialogueRunner.cancel()
	_check(not DialogueRunner.is_running(), "cancel() closes a conversation mid-choice")
	_check(not GameState.is_input_locked(), "cancel() at a choice releases the input lock")


# --- progression-gated content ---------------------------------------------
## Runs last: clearing a floor cannot be undone from here.

func _test_progression_gated_content() -> void:
	var nezha := load(NEZHA) as Dialogue
	_check(nezha.lines[nezha.entry_index()].id == &"first",
			"Nezha opens with the pre-boss line")

	GameState.clear_floor(1)

	_check(nezha.lines[nezha.entry_index()].id == &"after_boss",
			"clearing the floor changes what Nezha says")

	_items.clear()
	_open_menu()
	var map_choice := DialogueRunner.offered_choices()[_choice_index("Sell me a map")]
	_check(map_choice.is_unlocked(), "clearing floor 1 unlocks the map choice")
	_check(map_choice.label() == "Sell me a map of Floor Two.",
			"an unlocked choice drops its hint")

	DialogueRunner.choose(_choice_index("Sell me a map"))
	_check(_items == [&"map_floor_2"], "the map line hands over an item")
	_close()


# --- helpers ---------------------------------------------------------------

func _condition(test: DialogueCondition.Test, flag: StringName) -> DialogueCondition:
	var condition := DialogueCondition.new()
	condition.test = test
	condition.flag = flag
	return condition


## Opens Argo's dialogue and presses through to its choice menu.
func _open_menu(limit := 20) -> void:
	DialogueRunner.start(load(ARGO) as Dialogue)
	for _i in limit:
		if DialogueRunner.is_choosing() or not DialogueRunner.is_running():
			return
		DialogueRunner.advance()
	_check(false, "timed out reaching the choice menu")


## Presses through whatever is open, taking the last choice ("leave") at a menu.
func _close(limit := 40) -> void:
	for _i in limit:
		if not DialogueRunner.is_running():
			return
		if DialogueRunner.is_choosing():
			DialogueRunner.choose(DialogueRunner.offered_choices().size() - 1)
		else:
			DialogueRunner.advance()
	_check(false, "timed out closing the dialogue")


func _choice_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for choice in DialogueRunner.offered_choices():
		texts.append(choice.text)
	return texts


func _choice_index(prefix: String) -> int:
	var choices := DialogueRunner.offered_choices()
	for i in choices.size():
		if choices[i].text.begins_with(prefix):
			return i
	_check(false, "no choice starting with '%s'" % prefix)
	return -1


func _spy_line(speaker: String, text: String, _portrait: Texture2D) -> void:
	_speakers_seen.append(speaker)
	_lines_seen.append(text)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", description)
	else:
		print("  FAIL ", description)
		_failures.append(description)
