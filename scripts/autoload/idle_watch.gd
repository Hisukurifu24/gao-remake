extends Node
## Marathon's dead man's switch. A marathon is never saved, so the only way to
## keep one is never to close the game -- and a run left open overnight, or for a
## week, is not a marathon any more. So the castle does to an idle avatar what SAO
## does to anyone who logs out: after [constant LIMIT] seconds with no input at
## all, Cardinal logs the avatar out, the avatar shatters, and the run is over.
##
## The last [constant WARNING] seconds are counted down on screen
## ([signal EventBus.idle_countdown]); any key, click, mouse movement or stick
## push stops it ([signal EventBus.idle_cleared]). Only a marathon is watched, and
## only while a map is up: the title and the fade between maps never count.
##
## Nowhere is safe to stand still -- not a menu, not a conversation, not a fight.
## A fight would otherwise be the perfect hiding place, waiting forever on a
## command nobody gives, so a fight is lost on the spot ([method CombatManager.forfeit])
## and the defeat that follows asks [method SaveGame.end_if_fatal] like any other,
## which answers that the game is already ending.
##
## The clock is the wall clock, not frames: a laptop shut on a running marathon
## and opened in the morning has been idle all night, and finds out.
##
## Flow and view are separate, as everywhere: this owns the clock and the ending;
## [code]ui/signal_lost.gd[/code] draws the countdown and the shatter.

## Seconds with no input before the avatar is logged out.
const LIMIT := 300.0
## The last of them, counted down on screen.
const WARNING := 60.0
## How long the avatar takes to shatter before the game leaves for the title.
const SHATTER_TIME := 2.6
## The pause after a forfeited fight, so its result is read before the shatter.
const AFTER_FIGHT := 1.2
## A stick pushed less than this far is drift, not a player.
const STICK_DEADZONE := 0.5

## Overridable, for the save test, which can't wait five minutes.
var limit := LIMIT
var warning := WARNING
var shatter_time := SHATTER_TIME
## Seconds since an arbitrary point; the wall clock unless a test swaps it.
var clock: Callable = func() -> float: return Time.get_unix_time_from_system()

var _last_input := 0.0
## The whole second last counted down, or -1 with no countdown showing.
var _shown := -1
var _logging_out := false


func _ready() -> void:
	# The window's own signal, before anything handles the event: the game menu
	# eats its tab keys in _input, and an autoload hears _input last.
	get_tree().root.window_input.connect(_on_window_input)
	_last_input = clock.call()


## Whether a marathon is being watched right now.
func is_watching() -> bool:
	return GameState.mode == GameState.Mode.MARATHON and SceneRouter.current_map() != null \
			and not _logging_out


## Whether the avatar is being logged out -- the game is ending, and nothing that
## happens on the way (a fight lost, a box closing) should do anything about it.
func is_logging_out() -> bool:
	return _logging_out


## Seconds left before the avatar is logged out; [member limit] when unwatched.
func seconds_left() -> float:
	if not is_watching():
		return limit
	return maxf(0.0, limit - (float(clock.call()) - _last_input))


## The player is here. What every input event calls; public for tests and tools.
func touch() -> void:
	if _logging_out:
		return
	_last_input = clock.call()
	_clear()


func _on_window_input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) < STICK_DEADZONE:
		return
	if event.is_echo():
		return
	touch()


func _process(_delta: float) -> void:
	var now: float = clock.call()
	if not is_watching():
		if not _logging_out:
			_last_input = now
			_clear()
		return
	# A clock set back would otherwise make the run immortal until it caught up.
	if now < _last_input:
		_last_input = now
	var left := limit - (now - _last_input)
	if left <= 0.0:
		_log_out()
	elif left <= warning:
		var whole := ceili(left)
		if whole != _shown:
			_shown = whole
			EventBus.idle_countdown.emit(whole)
	else:
		_clear()


func _clear() -> void:
	if _shown >= 0:
		_shown = -1
		EventBus.idle_cleared.emit()


func _log_out() -> void:
	_logging_out = true
	_clear()
	var who := GameState.player_name
	var where := GameState.current_floor
	var fought := CombatManager.is_running()
	while CombatManager.is_running():
		if CombatManager.is_awaiting_command():
			CombatManager.forfeit("%s stands motionless. The blow lands, and the next." % who)
		await get_tree().process_frame
	if fought:
		await _beat(AFTER_FIGHT)
	while SceneRouter.is_busy():
		await get_tree().process_frame
	while DialogueRunner.is_running():
		DialogueRunner.cancel()
		await get_tree().process_frame
	EventBus.screens_close_requested.emit()
	GameState.push_input_lock()
	EventBus.avatar_logged_out.emit()
	await _beat(shatter_time)
	GameState.pop_input_lock()
	await SaveGame.quit_to_title(
			"%s was logged out for idling on Floor %d. The marathon is over." % [who, where], false)
	_logging_out = false
	_last_input = clock.call()


func _beat(seconds: float) -> void:
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
	else:
		await get_tree().process_frame

