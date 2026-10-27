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

## How long "Saved" stays up, fading for the last third.
const SAVED_TIME := 1.2
## A floor's headline ([signal EventBus.floor_announced]): held this long once in,
## after waiting out the fade the map arrived behind.
const HEADLINE_DELAY := 0.6
const HEADLINE_FADE := 0.5
const HEADLINE_TIME := 2.8

var _target: Interactable = null
## "Saved", bottom-right, for a moment after the game is written.
var _saved: Label = null
var _saved_fade: Tween = null
## A floor's modifier, top-centre, for a moment after arriving on it.
var _headline: VBoxContainer = null
var _headline_title: Label = null
var _headline_line: Label = null
var _headline_fade: Tween = null
## The player in the fight on now; null on the map.
var _fighter: Combatant = null


func _ready() -> void:
	_prompt.hide()
	EventBus.interact_target_changed.connect(_on_interact_target_changed)
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	EventBus.input_lock_changed.connect(func(_locked: bool) -> void: _refresh())
	EventBus.hp_changed.connect(_on_hp_changed)
	EventBus.leveled_up.connect(_on_leveled_up)
	CombatManager.combat_began.connect(_on_combat_began)
	CombatManager.command_requested.connect(_on_command_requested)
	CombatManager.action_resolved.connect(_on_action_resolved)
	CombatManager.combat_finished.connect(_on_combat_finished)
	EventBus.game_saved.connect(_on_game_saved)
	EventBus.game_loaded.connect(func(_slot: int) -> void: _refresh_vitals())
	# The game menu's dim is see-through, and its tab strip stands where the plate
	# does: the Status tab already says everything the plate would.
	EventBus.game_menu_toggled.connect(func(open: bool) -> void: _vitals.visible = not open)
	EventBus.floor_announced.connect(_on_floor_announced)
	_build_saved_note()
	_build_headline()
	_refresh_vitals()


## Made here rather than in the scene: one shadowed word in a corner, nothing to
## lay out.
func _build_saved_note() -> void:
	_saved = Label.new()
	_saved.name = "Saved"
	_saved.text = "Saved"
	_saved.theme_type_variation = &"FieldLabel"
	_saved.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_saved.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_saved.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_saved.offset_right = -8.0
	_saved.offset_bottom = -4.0
	_saved.modulate.a = 0.0
	add_child(_saved)


## Two shadowed lines straight on the map, centred under the top edge: the floor's
## modifier and what it means. Built here for the same reason as "Saved".
func _build_headline() -> void:
	_headline = VBoxContainer.new()
	_headline.name = "Headline"
	_headline.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_headline.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_headline.offset_top = 52.0
	_headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_headline.add_theme_constant_override(&"separation", 0)
	_headline.modulate.a = 0.0
	_headline_title = Label.new()
	_headline_title.theme_type_variation = &"TitleLabel"
	_headline_line = Label.new()
	_headline_line.theme_type_variation = &"FieldLabel"
	for label in [_headline_title, _headline_line]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_headline.add_child(label)
	add_child(_headline)


## The headline of a floor with a modifier, faded in once the map is up. A map
## with none puts out whatever the last one left up.
func _on_floor_announced(title: String, line: String) -> void:
	if _headline_fade != null:
		_headline_fade.kill()
		_headline_fade = null
	_headline.modulate.a = 0.0
	if title.is_empty():
		return
	_headline_title.text = title
	_headline_line.text = line
	UiLayout.shrink_wrap(_headline)
	_headline_fade = create_tween()
	_headline_fade.tween_interval(HEADLINE_DELAY)
	_headline_fade.tween_property(_headline, "modulate:a", 1.0, HEADLINE_FADE)
	_headline_fade.tween_interval(HEADLINE_TIME)
	_headline_fade.tween_property(_headline, "modulate:a", 0.0, HEADLINE_FADE * 2.0)


## What the headline says while it is up, or empty -- for the tests.
func headline() -> String:
	return _headline_title.text if _headline_fade != null and _headline_fade.is_running() else ""


func _on_game_saved(_slot: int, _auto: bool) -> void:
	if _saved_fade != null:
		_saved_fade.kill()
	_saved.modulate.a = 1.0
	_saved_fade = create_tween()
	_saved_fade.tween_interval(SAVED_TIME * 2.0 / 3.0)
	_saved_fade.tween_property(_saved, "modulate:a", 0.0, SAVED_TIME / 3.0)


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
