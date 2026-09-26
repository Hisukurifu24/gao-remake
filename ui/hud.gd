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

@onready var _prompt: Control = $InteractPrompt
@onready var _prompt_label: Label = $InteractPrompt/Row/Label
@onready var _vitals: Control = $Vitals
@onready var _vitals_label: Label = $Vitals/Rows/Label
@onready var _hp_bar: ProgressBar = $Vitals/Rows/Bar/Hp

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
	# The key is the pack's keycap beside the label, not "[E]" in the text.
	_prompt_label.text = _target.get_prompt()
	_prompt.show()
	# Shrink-wrap round the new label: a PanelContainer grows to fit but never
	# shrinks back on its own. It grows both ways from the anchor, so it stays
	# centred.
	_prompt.offset_left = -0.5
	_prompt.offset_right = 0.5


func _refresh_vitals() -> void:
	# total_max_hp(), not max_hp: a +HP coat has to show up in the bar it raised.
	var max_hp := GameState.total_max_hp()
	var ratio := float(GameState.hp) / float(maxi(1, max_hp))
	_vitals_label.text = "%s  Lv %d   %d/%d" % [
			GameState.player_name, GameState.level, GameState.hp, max_hp]
	_hp_bar.value = ratio * 100.0
	UiPalette.paint_bar(_hp_bar, UiPalette.hp_color(ratio))
