extends CanvasLayer
## The always-on overlay: the interact prompt, and the player's vitals.
##
## The conversation box used to live here as an M1 stopgap; it is now
## [code]ui/dialogue_box.tscn[/code], driven by DialogueRunner. A fight's words
## and menu are [code]ui/battle_hud.tscn[/code]'s, but its vitals are this plate:
## it stays up, grows a poise bar and a status line, and follows the player's
## [Combatant] rather than [GameState] until the fight writes back -- one vitals
## plate in the game, not two.
##
## Vitals follow [EventBus] rather than polling [GameState], so anything that
## comes to hurt the player later (a trap, a status on the map) shows up here
## without touching this file.

@onready var _prompt: Control = $InteractPrompt
@onready var _prompt_label: Label = $InteractPrompt/Row/Label
@onready var _vitals: Control = $Vitals
@onready var _vitals_label: Label = $Vitals/Rows/Label
@onready var _hp_bar: ProgressBar = $Vitals/Rows/Bar/Gauges/Hp
@onready var _poise_bar: ProgressBar = $Vitals/Rows/Bar/Gauges/Poise
@onready var _statuses: Label = $Vitals/Rows/Statuses

var _target: Interactable = null
## The player in the fight on now; null on the map.
var _fighter: Combatant = null


func _ready() -> void:
	_prompt.hide()
	EventBus.interact_target_changed.connect(_on_interact_target_changed)
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	EventBus.hp_changed.connect(_on_hp_changed)
	EventBus.leveled_up.connect(_on_leveled_up)
	CombatManager.combat_began.connect(_on_combat_began)
	CombatManager.command_requested.connect(_on_command_requested)
	CombatManager.action_resolved.connect(_on_action_resolved)
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


func _on_combat_began(_encounter: Encounter, party: Array[Combatant],
		_enemies: Array[Combatant]) -> void:
	_prompt.hide()
	_fighter = party[0]
	_refresh_vitals()


func _on_command_requested(actor: Combatant) -> void:
	if actor.is_player:
		_fighter = actor
		_refresh_vitals()


func _on_action_resolved(_report: CombatReport) -> void:
	# A status ticking down touches nobody, and still changes the line.
	if _fighter != null:
		_refresh_vitals()


func _on_combat_finished(_result: CombatResult) -> void:
	_fighter = null
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
	# Shrink-wrap round the new label. It grows both ways from the anchor, so it
	# stays centred.
	UiLayout.shrink_wrap(_prompt)


func _refresh_vitals() -> void:
	# total_max_hp(), not max_hp: a +HP coat has to show up in the bar it raised.
	var hp := GameState.hp
	var max_hp := GameState.total_max_hp()
	if _fighter != null:
		hp = _fighter.hp
		max_hp = _fighter.max_hp
	var ratio := float(hp) / float(maxi(1, max_hp))
	_vitals_label.text = "%s  Lv %d   %d/%d" % [GameState.player_name, GameState.level, hp, max_hp]
	_hp_bar.value = ratio * 100.0
	UiPalette.paint_bar(_hp_bar, UiPalette.hp_color(ratio))

	_poise_bar.visible = _fighter != null
	var tags := PackedStringArray()
	if _fighter != null:
		_poise_bar.value = _fighter.poise_ratio() * 100.0
		UiPalette.paint_bar(_poise_bar, UiPalette.POISE)
		tags = _fighter.status_labels()
		if _fighter.staggered:
			tags.append("STAGGERED")
	_statuses.text = " ".join(tags)
	_statuses.visible = not tags.is_empty()
	# Anchored top-left and growing down, so the plate takes the rows it has.
	UiLayout.shrink_wrap(_vitals)
