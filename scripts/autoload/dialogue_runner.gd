extends Node
## Walks a [Dialogue] and drives the box that shows it.
##
## The runner owns *flow*: which line comes next, which choices are offered,
## when effects fire, and the input lock that keeps the player still while a
## conversation is open. It owns no pixels -- [code]ui/dialogue_box.tscn[/code]
## listens to [signal line_shown] / [signal choices_shown] and calls back into
## [method advance] / [method choose]. Anything else that wants to render
## dialogue can do the same without touching this file.
##
## Typical use, from an NPC:
##     await DialogueRunner.start(preload("res://resources/dialogue/argo.tres"))
##
## Callers may ignore the await; [method start] is a coroutine only so that
## quests and cutscenes can wait for a conversation to end.

## A line is on screen. The runner has already resolved speaker and portrait
## against the dialogue's defaults, so the UI just draws what it is given.
signal line_shown(speaker: String, text: String, portrait: Texture2D)
## The player must pick before the conversation continues. Choices are already
## filtered to the listed ones; ask each one [method DialogueChoice.is_unlocked]
## to know whether it can actually be selected.
signal choices_shown(choices: Array[DialogueChoice])
## The box should close. Fires for every conversation, including cancelled ones.
signal closed()

enum _Wait { NONE, LINE, CHOICE }

var _active: Dialogue = null
var _queue: Array[Dialogue] = []
var _offered: Array[DialogueChoice] = []
var _wait := _Wait.NONE
var _cancelled := false

## Signals the coroutine parks on. Private because input arrives through
## [method advance] and [method choose], which validate what is actually being
## waited for -- a stray advance during a choice must not skip the choice.
signal _advance_requested()
signal _choice_made(index: int)


func _ready() -> void:
	EventBus.message_requested.connect(_on_message_requested)


func is_running() -> bool:
	return _active != null


func current_dialogue_id() -> StringName:
	return _active.id if _active != null else &""


## True while a choice menu is open and the runner is waiting on [method choose].
func is_choosing() -> bool:
	return _wait == _Wait.CHOICE


## The choices currently on offer; empty unless [method is_choosing].
func offered_choices() -> Array[DialogueChoice]:
	return _offered


## Runs [param dialogue] to completion. A conversation started while another is
## open is queued rather than dropped, so a chest opening on the same frame as a
## goodbye still gets its say.
func start(dialogue: Dialogue) -> void:
	if dialogue == null:
		return
	if is_running():
		_queue.append(dialogue)
		return

	var index := dialogue.entry_index()
	if index < 0:
		# Every line is condition-gated and none of them apply right now. That is
		# a legitimate "nothing to say", not an error.
		return

	_active = dialogue
	_cancelled = false
	GameState.push_input_lock()
	EventBus.dialogue_started.emit(dialogue.id)

	while index >= 0 and index < dialogue.lines.size():
		var line := dialogue.lines[index]
		if line == null:
			break
		DialogueEffect.apply_all(line.effects)
		line_shown.emit(dialogue.speaker_for(line), line.text, dialogue.portrait_for(line))

		var choices := line.listed_choices()
		if not choices.is_empty() and not _any_unlocked(choices):
			# Every branch is locked, so the menu would be a dead end. Fall through
			# instead of trapping the player in it.
			push_warning("Dialogue '%s': no selectable choice on line '%s'." % [
				dialogue.id, line.id])
			choices = []

		if choices.is_empty():
			_wait = _Wait.LINE
			await _advance_requested
			if _cancelled:
				break
			index = _next_index(dialogue, line, index)
		else:
			_offered = choices
			choices_shown.emit(choices)
			_wait = _Wait.CHOICE
			var picked: int = await _choice_made
			if _cancelled:
				break
			var choice := _offered[picked]
			EventBus.choice_selected.emit(dialogue.id, picked)
			DialogueEffect.apply_all(choice.effects)
			index = dialogue.index_of(choice.next)

	var finished_id := dialogue.id
	_active = null
	_offered = []
	_wait = _Wait.NONE
	closed.emit()
	GameState.pop_input_lock()
	EventBus.dialogue_finished.emit(finished_id)

	if not _queue.is_empty() and not _cancelled:
		start(_queue.pop_front())
	else:
		_queue.clear()


## Shows plain strings with no branching -- chests, signs, system messages.
## Everything a character actually *says* should be a [Dialogue] resource.
func say(speaker: String, texts: PackedStringArray) -> void:
	if texts.is_empty():
		return
	await start(Dialogue.from_lines(speaker, texts))


## The player pressed continue. Ignored unless a line is actually waiting, so
## the UI can call it freely (e.g. from a click anywhere on the box).
func advance() -> void:
	if _wait != _Wait.LINE:
		return
	_wait = _Wait.NONE
	_advance_requested.emit()


## Picks the [param index]-th of the choices last offered. Out-of-range and
## locked choices are refused here as well as in the UI: the runner is the one
## place that must not be talked into an impossible branch.
func choose(index: int) -> void:
	if _wait != _Wait.CHOICE:
		return
	if index < 0 or index >= _offered.size() or not _offered[index].is_unlocked():
		return
	_wait = _Wait.NONE
	_choice_made.emit(index)


## Closes the conversation wherever it is. For hard interruptions -- a map
## transition, entering combat -- not for the player pressing through.
func cancel() -> void:
	if not is_running():
		return
	_cancelled = true
	match _wait:
		_Wait.LINE:
			_wait = _Wait.NONE
			_advance_requested.emit()
		_Wait.CHOICE:
			_wait = _Wait.NONE
			_choice_made.emit(0)


func _any_unlocked(choices: Array[DialogueChoice]) -> bool:
	for choice in choices:
		if choice.is_unlocked():
			return true
	return false


## Where a line without choices goes: an explicit jump, the end, or simply the
## next line in the array.
func _next_index(dialogue: Dialogue, line: DialogueLine, index: int) -> int:
	if line.next == DialogueLine.END:
		return -1
	if line.next == &"":
		return index + 1
	var target := dialogue.index_of(line.next)
	if target < 0:
		push_error("Dialogue '%s': line '%s' jumps to unknown id '%s'." % [
			dialogue.id, line.id, line.next])
	return target


func _on_message_requested(speaker: String, texts: PackedStringArray) -> void:
	say(speaker, texts)
