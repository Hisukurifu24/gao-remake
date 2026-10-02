class_name BattleHud
extends CanvasLayer
## The fight's words: the message line and the command menu, on slim plates
## over whatever draws the fight.
##
## Purely a view, exactly like [code]ui/dialogue_box.gd[/code]: it renders what
## [CombatManager] announces and answers with [method CombatManager.submit]. It
## decides nothing -- a skill greyed out here is also refused there, because the
## runner is the one place a rule can't be talked around.
##
## The fight itself is drawn elsewhere -- on the map by a [BattleStage], which
## this puts there when a fight is staged, or by the old battle screen for one
## that isn't -- and the player's vitals are the HUD's own plate, which stays up.
## What those need from the menu is which enemy the cursor is on: [signal aimed].

## The cursor moved onto [param target] while choosing who a skill lands on, or
## off every enemy ([param target] null).
signal aimed(target: Combatant)

## How long the result stays up after the last blow.
const OUTRO_TIME := 1.1

## What the command menu is currently asking for.
enum Phase { HIDDEN, BUSY, ROOT, SKILLS, ITEMS, TARGET }

## The fixed commands. Skills and Items each get their own submenu.
enum Command { ATTACK, SKILLS, ITEM, DEFEND, FLEE }

var _phase := Phase.HIDDEN
var _selected := 0
## Root commands actually on offer -- Flee is absent from a boss fight.
var _commands: Array[Command] = []
var _skill_rows: Array[Skill] = []
var _item_rows: Array[ItemStack] = []
var _target_rows: Array[Combatant] = []
## The text of each menu row, without the cursor. Kept beside the Labels so
## repainting the selection doesn't have to parse what it drew last time.
var _rows_text := PackedStringArray()
## Held between choosing a skill and choosing who it lands on.
var _staged: Skill = null
var _actor: Combatant = null
var _aimed: Combatant = null
## The pause that hides the result after a fight. Held so the next fight can
## cancel it: a fight that starts inside the pause would otherwise be hidden when
## it runs out, and the manager would wait forever on a menu nobody can see.
var _outro: Tween = null

@onready var _log: Control = $Log
@onready var _log_label: Label = $Log/Label
@onready var _menu: Control = $Menu
@onready var _list: VBoxContainer = $Menu/Column/List
@onready var _hint: Label = $Menu/Column/Hint


func _ready() -> void:
	_set_visible(false)
	EventBus.battle_staged.connect(_on_battle_staged)
	CombatManager.combat_began.connect(_on_combat_began)
	CombatManager.command_requested.connect(_on_command_requested)
	CombatManager.action_resolved.connect(_on_action_resolved)
	CombatManager.combat_finished.connect(_on_combat_finished)


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _phase in [Phase.HIDDEN, Phase.BUSY]:
		return

	if event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
		get_viewport().set_input_as_handled()
		_move_selection(-1)
	elif event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
		get_viewport().set_input_as_handled()
		_move_selection(1)
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		_confirm()
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_cancel()


func _confirm() -> void:
	match _phase:
		Phase.ROOT:
			_choose_command(_commands[_selected])
		Phase.SKILLS:
			var skill := _skill_rows[_selected]
			if _actor.is_ready(skill):
				_stage(skill)
		Phase.ITEMS:
			# Party of one, and nothing is thrown at an enemy yet, so an item
			# always lands on the person drinking it.
			_send(CombatAction.use_item(_item_rows[_selected].item, _actor))
		Phase.TARGET:
			_send(CombatAction.use(_staged, _target_rows[_selected]))


## Backs out one step. From the root menu there is nowhere to back out to --
## a fight is not something you can close.
func _cancel() -> void:
	match _phase:
		Phase.SKILLS, Phase.ITEMS:
			_show_root()
		Phase.TARGET:
			if _staged in _skill_rows:
				_show_skills()
			else:
				_show_root()


func _choose_command(command: Command) -> void:
	match command:
		Command.ATTACK:
			_stage(SkillLibrary.basic_attack())
		Command.SKILLS:
			_show_skills()
		Command.ITEM:
			_show_items()
		Command.DEFEND:
			_send(CombatAction.defend())
		Command.FLEE:
			_send(CombatAction.flee())


## Takes a skill as far as it can go on its own: straight out if there is
## nothing to choose, into targeting if there is.
func _stage(skill: Skill) -> void:
	_staged = skill
	var candidates := CombatManager.living_enemies()
	if not skill.needs_target() or not skill.is_offensive() or candidates.size() <= 1:
		_send(CombatAction.use(skill, candidates[0] if not candidates.is_empty() else null))
		return
	_show_targets(candidates)


func _send(action: CombatAction) -> void:
	if CombatManager.submit(action):
		_phase = Phase.BUSY
		_menu.hide()
		_aim(null)


# --- combat signals --------------------------------------------------------

## The fight will be on the map: put a stage there to draw it.
func _on_battle_staged(field: BattleField) -> void:
	var stage := BattleStage.new(field)
	aimed.connect(stage.aim)
	field.map.add_child(stage)


func _on_combat_began(encounter: Encounter, _party: Array[Combatant],
		_enemies: Array[Combatant]) -> void:
	if _outro != null:
		_outro.kill()
		_outro = null
	_set_visible(true)
	_say("%s blocks the way." % encounter.label())
	_phase = Phase.BUSY
	_menu.hide()


func _on_command_requested(actor: Combatant) -> void:
	_actor = actor
	_show_root()


func _on_action_resolved(report: CombatReport) -> void:
	# Anything resolving while the menu is up means the question was answered
	# somewhere else -- an auto-battler, a test, a tool. Nobody is still asking.
	if _phase not in [Phase.HIDDEN, Phase.BUSY]:
		_phase = Phase.BUSY
		_menu.hide()
		_aim(null)
	_say(report.text)


func _on_combat_finished(result: CombatResult) -> void:
	_phase = Phase.BUSY
	_menu.hide()
	_aim(null)
	_say(result.summary())
	# Tests run with no pacing at all; there is nobody to read the result to.
	if CombatManager.step_delay <= 0.0:
		_set_visible(false)
		return
	_outro = create_tween()
	_outro.tween_interval(OUTRO_TIME)
	_outro.tween_callback(_set_visible.bind(false))


func _say(text: String) -> void:
	_log_label.text = text
	# Anchored bottom-left and growing up, so a second line pushes the plate up
	# rather than off the screen.
	UiLayout.shrink_wrap(_log)


# --- menus -----------------------------------------------------------------

func _show_root() -> void:
	_phase = Phase.ROOT
	_staged = null
	_commands = [Command.ATTACK, Command.SKILLS, Command.ITEM, Command.DEFEND]
	if CombatManager.current_encounter().can_flee:
		_commands.append(Command.FLEE)

	var labels := PackedStringArray()
	var locked := PackedInt32Array()
	for i in _commands.size():
		labels.append(_command_label(_commands[i]))
		# Item stays on the list with an empty bag rather than disappearing:
		# a verb that comes and goes is a verb the player never learns.
		if _commands[i] == Command.ITEM and Inventory.usable_stacks(true).is_empty():
			locked.append(i)
	_hint.text = ""
	_populate(labels, locked)


func _show_skills() -> void:
	_phase = Phase.SKILLS
	_skill_rows = _actor.skills.duplicate()
	if _skill_rows.is_empty():
		_show_root()
		return

	var labels := PackedStringArray()
	var locked := PackedInt32Array()
	for i in _skill_rows.size():
		var skill := _skill_rows[i]
		var left := _actor.cooldown_left(skill)
		labels.append("%s  (%d)" % [skill.label(), left] if left > 0 else skill.label())
		if left > 0:
			locked.append(i)
	_populate(labels, locked)


func _show_items() -> void:
	_phase = Phase.ITEMS
	_item_rows = Inventory.usable_stacks(true)
	if _item_rows.is_empty():
		_show_root()
		return

	var labels := PackedStringArray()
	for stack in _item_rows:
		labels.append(stack.label())
	_populate(labels, PackedInt32Array())


func _show_targets(candidates: Array[Combatant]) -> void:
	_phase = Phase.TARGET
	_target_rows = candidates
	var labels := PackedStringArray()
	for target in candidates:
		var tags := target.status_labels()
		labels.append("%s  %d/%d%s" % [target.display_name, target.hp, target.max_hp,
				("  " + " ".join(tags)) if not tags.is_empty() else ""])
	_hint.text = ""
	_populate(labels, PackedInt32Array())


## Draws [param labels] as the menu, greying out the [param locked] indices and
## parking the cursor on the first row that can actually be picked.
func _populate(labels: PackedStringArray, locked: PackedInt32Array) -> void:
	for row in _list.get_children():
		_list.remove_child(row)
		row.queue_free()

	_selected = -1
	for i in labels.size():
		var row := Label.new()
		row.set_meta(&"locked", i in locked)
		_list.add_child(row)
		if _selected < 0 and i not in locked:
			_selected = i

	_selected = maxi(_selected, 0)
	_rows_text = labels
	_paint()
	_menu.show()


func _move_selection(step: int) -> void:
	var count := _list.get_child_count()
	if count == 0:
		return
	for i in range(1, count + 1):
		var candidate := (_selected + step * i + count * count) % count
		if not _list.get_child(candidate).get_meta(&"locked", false):
			_selected = candidate
			break
	_paint()


func _paint() -> void:
	for i in _list.get_child_count():
		var row := _list.get_child(i) as Label
		var color := UiPalette.TEXT
		if row.get_meta(&"locked", false):
			color = UiPalette.LOCKED
		elif i == _selected:
			color = UiPalette.TARGETED if _phase == Phase.TARGET else UiPalette.SELECTED
		row.add_theme_color_override(&"font_color", color)
		row.text = ("> " if i == _selected else "  ") + _rows_text[i]

	if _phase == Phase.SKILLS and _selected < _skill_rows.size():
		_hint.text = _skill_rows[_selected].description
	elif _phase == Phase.ITEMS and _selected < _item_rows.size():
		_hint.text = _item_rows[_selected].item.description
	# The hint is only a row while there is something to say: the root menu and
	# the target list are their own explanation.
	_hint.visible = not _hint.text.is_empty()
	_aim(_target_rows[_selected] if _phase == Phase.TARGET and _selected < _target_rows.size() else null)
	# Collapse onto the new rows: the panel is anchored bottom-right and grows up
	# and left.
	UiLayout.shrink_wrap(_menu)


## Tells whoever draws the enemies which one the cursor is on, so targeting
## reads on the field and not only in the menu.
func _aim(target: Combatant) -> void:
	if target == _aimed:
		return
	_aimed = target
	aimed.emit(target)


func _command_label(command: Command) -> String:
	match command:
		Command.ATTACK:
			return "Attack"
		Command.SKILLS:
			return "Sword Skills"
		Command.ITEM:
			return "Item"
		Command.DEFEND:
			return "Defend"
		_:
			return "Flee"


func _set_visible(shown: bool) -> void:
	visible = shown
	if not shown:
		_phase = Phase.HIDDEN
		_actor = null
		_staged = null
		_menu.hide()
		_aim(null)
