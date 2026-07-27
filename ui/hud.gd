extends CanvasLayer
## The always-on overlay: the interact prompt, and the player's vitals.
##
## The conversation box used to live here as an M1 stopgap; it is now
## [code]ui/dialogue_box.tscn[/code], driven by DialogueRunner. The battle
## interface is [code]ui/combat_screen.tscn[/code], and this steps aside while a
## fight is on -- the fight draws a better version of the same bar.
##
## Vitals follow [EventBus] rather than polling [GameState], so anything that
## comes to hurt the player later (a trap, a status on the map) shows up here
## without touching this file.

## The same cursor colours the combat screen uses -- one health language.
const HP_HEALTHY := Color(0.38, 0.78, 0.42)
const HP_HURT := Color(0.92, 0.78, 0.32)
const HP_CRITICAL := Color(0.88, 0.32, 0.32)

@onready var _prompt: Control = $InteractPrompt
@onready var _prompt_label: Label = $InteractPrompt/Label
@onready var _vitals: Control = $Vitals
@onready var _vitals_label: Label = $Vitals/Rows/Label
@onready var _hp_bar: ProgressBar = $Vitals/Rows/Hp

var _target: Interactable = null


func _ready() -> void:
	_prompt.hide()
	EventBus.interact_target_changed.connect(_on_interact_target_changed)
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	EventBus.hp_changed.connect(_on_hp_changed)
	EventBus.leveled_up.connect(_on_leveled_up)
	CombatManager.combat_began.connect(_on_combat_began)
	CombatManager.combat_finished.connect(_on_combat_finished)
	_refresh_vitals()


func _on_interact_target_changed(target: Node) -> void:
	_target = target as Interactable
	_refresh()


func _on_dialogue_started(_dialogue_id: StringName) -> void:
	_prompt.hide()


func _on_dialogue_finished(_dialogue_id: StringName) -> void:
	_refresh()


func _on_hp_changed(_hp: int, _max_hp: int) -> void:
	_refresh_vitals()


func _on_leveled_up(_new_level: int) -> void:
	_refresh_vitals()


func _on_combat_began(_encounter: Encounter, _party: Array[Combatant],
		_enemies: Array[Combatant]) -> void:
	_prompt.hide()
	_vitals.hide()


func _on_combat_finished(_result: CombatResult) -> void:
	_vitals.show()
	_refresh_vitals()
	_refresh()


func _refresh() -> void:
	# The player keeps its target while talking; the prompt just steps aside.
	# The input lock covers everything else that takes over the screen -- the
	# bag, a map fade -- without this file having to know about any of them.
	if _target == null or GameState.is_input_locked() \
			or DialogueRunner.is_running() or CombatManager.is_running():
		_prompt.hide()
		return
	_prompt_label.text = "[E]  %s" % _target.get_prompt()
	_prompt.show()


func _refresh_vitals() -> void:
	# total_max_hp(), not max_hp: a +HP coat has to show up in the bar it raised.
	var max_hp := GameState.total_max_hp()
	var ratio := float(GameState.hp) / float(maxi(1, max_hp))
	_vitals_label.text = "%s  Lv %d   %d/%d" % [
			GameState.player_name, GameState.level, GameState.hp, max_hp]
	_hp_bar.value = ratio * 100.0

	var fill := StyleBoxFlat.new()
	fill.bg_color = HP_HEALTHY if ratio > 0.5 else (HP_HURT if ratio > 0.2 else HP_CRITICAL)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.13, 0.14, 0.2)
	_hp_bar.add_theme_stylebox_override(&"fill", fill)
	_hp_bar.add_theme_stylebox_override(&"background", back)
