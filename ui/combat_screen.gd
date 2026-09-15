extends CanvasLayer
## The battle, drawn.
##
## Purely a view, exactly like [code]ui/dialogue_box.gd[/code]: it renders what
## [CombatManager] announces and answers with [method CombatManager.submit]. It
## decides nothing -- a skill greyed out here is also refused there, because the
## runner is the one place a rule can't be talked around.
##
## The static frame is in the .tscn; enemy entries, menu rows and damage numbers
## are built in code because their count is only known once a fight starts.

const COLOR_ROW := Color(0.76, 0.79, 0.88)
const COLOR_SELECTED := Color(1.0, 0.94, 0.7)
const COLOR_LOCKED := Color(0.44, 0.45, 0.52)
const COLOR_TARGETED := Color(1.0, 0.62, 0.55)

## SAO's cursor colours: green while you're fine, amber when you should think,
## red when you should have thought earlier.
const HP_HEALTHY := Color(0.38, 0.78, 0.42)
const HP_HURT := Color(0.92, 0.78, 0.32)
const HP_CRITICAL := Color(0.88, 0.32, 0.32)
const POISE_COLOR := Color(0.5, 0.68, 0.95)

const DAMAGE_COLOR := Color(1.0, 0.86, 0.4)
const CRIT_COLOR := Color(1.0, 0.55, 0.35)
const HEAL_COLOR := Color(0.5, 0.92, 0.6)
const MISS_COLOR := Color(0.7, 0.72, 0.8)

const FLOATER_RISE := 26.0
const FLOATER_TIME := 0.7
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
## The pause that hides the screen after a fight. Held so the next fight can
## cancel it: a fight that starts inside the pause would otherwise be hidden when
## it runs out, and the manager would wait forever on a menu nobody can see.
var _outro: Tween = null
## Enemy [Combatant] to the panel drawing it, so a report can find its sprite.
var _entries: Dictionary[Combatant, Control] = {}

@onready var _backdrop: ColorRect = $Backdrop
@onready var _enemy_row: HBoxContainer = $Enemies
@onready var _log: Label = $Log/Label
@onready var _party_panel: Control = $Party
@onready var _party_name: Label = $Party/Margin/Rows/Name
@onready var _party_hp: ProgressBar = $Party/Margin/Rows/Hp
@onready var _party_poise: ProgressBar = $Party/Margin/Rows/Poise
@onready var _party_statuses: Label = $Party/Margin/Rows/Statuses
@onready var _menu: Control = $Menu
@onready var _list: VBoxContainer = $Menu/Margin/Column/List
@onready var _hint: Label = $Menu/Margin/Column/Hint
@onready var _floaters: Control = $Floaters


func _ready() -> void:
	_set_visible(false)
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


# --- combat signals --------------------------------------------------------

func _on_combat_began(encounter: Encounter, party: Array[Combatant], enemies: Array[Combatant]) -> void:
	if _outro != null:
		_outro.kill()
		_outro = null
	_set_visible(true)
	_backdrop.color = encounter.backdrop
	_log.text = "%s blocks the way." % encounter.label()
	_build_enemies(enemies)
	_refresh_party(party[0])
	_phase = Phase.BUSY
	_menu.hide()


func _on_command_requested(actor: Combatant) -> void:
	_actor = actor
	_refresh_party(actor)
	_show_root()


func _on_action_resolved(report: CombatReport) -> void:
	_log.text = report.text
	for hit in report.hits:
		_float_number(hit)
	for touched in report.touched():
		if touched.is_player:
			_refresh_party(touched)
		else:
			_refresh_enemy(touched)


func _on_combat_finished(result: CombatResult) -> void:
	_phase = Phase.BUSY
	_menu.hide()
	_log.text = result.summary()
	# Tests run with no pacing at all; there is nobody to read the result to.
	if CombatManager.step_delay <= 0.0:
		_set_visible(false)
		return
	_outro = create_tween()
	_outro.tween_interval(OUTRO_TIME)
	_outro.tween_callback(_set_visible.bind(false))


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
	_populate(labels, locked)
	_hint.text = "[E] choose"


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
	_hint.text = "[Esc] back"


func _show_targets(candidates: Array[Combatant]) -> void:
	_phase = Phase.TARGET
	_target_rows = candidates
	var labels := PackedStringArray()
	for target in candidates:
		labels.append("%s  %d/%d" % [target.display_name, target.hp, target.max_hp])
	_populate(labels, PackedInt32Array())
	_hint.text = "[Esc] back"


## Draws [param labels] as the menu, greying out the [param locked] indices and
## parking the cursor on the first row that can actually be picked.
func _populate(labels: PackedStringArray, locked: PackedInt32Array) -> void:
	for row in _list.get_children():
		_list.remove_child(row)
		row.queue_free()

	_selected = -1
	for i in labels.size():
		var row := Label.new()
		row.add_theme_font_size_override(&"font_size", 12)
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
		var color := COLOR_ROW
		if row.get_meta(&"locked", false):
			color = COLOR_LOCKED
		elif i == _selected:
			color = COLOR_TARGETED if _phase == Phase.TARGET else COLOR_SELECTED
		row.add_theme_color_override(&"font_color", color)
		row.text = ("> " if i == _selected else "  ") + _rows_text[i]

	if _phase == Phase.SKILLS and _selected < _skill_rows.size():
		_hint.text = _skill_rows[_selected].description
	elif _phase == Phase.ITEMS and _selected < _item_rows.size():
		_hint.text = _item_rows[_selected].item.description
	_highlight_target()


## Marks the enemy the cursor is on, so targeting reads on the battlefield and
## not only in the menu.
func _highlight_target() -> void:
	for enemy in _entries:
		var pointer := _entries[enemy].get_node("Pointer") as Label
		var aimed := _phase == Phase.TARGET and _selected < _target_rows.size() \
				and _target_rows[_selected] == enemy
		pointer.visible = aimed


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


# --- battlefield -----------------------------------------------------------

func _build_enemies(enemies: Array[Combatant]) -> void:
	_entries.clear()
	for child in _enemy_row.get_children():
		_enemy_row.remove_child(child)
		child.queue_free()

	for enemy in enemies:
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_END
		column.add_theme_constant_override(&"separation", 2)
		column.custom_minimum_size = Vector2(96, 0)

		var pointer := Label.new()
		pointer.name = "Pointer"
		pointer.text = "▼"
		pointer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pointer.add_theme_color_override(&"font_color", COLOR_TARGETED)
		pointer.hide()
		column.add_child(pointer)

		var sprite := TextureRect.new()
		sprite.name = "Sprite"
		sprite.texture = enemy.battler
		sprite.custom_minimum_size = _battler_size(enemy.battler)
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		column.add_child(sprite)

		var name_label := Label.new()
		name_label.name = "Name"
		name_label.text = enemy.display_name
		name_label.add_theme_font_size_override(&"font_size", 10)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(name_label)

		var bar := ProgressBar.new()
		bar.name = "Hp"
		bar.custom_minimum_size = Vector2(0, 6)
		bar.show_percentage = false
		column.add_child(bar)

		var statuses := Label.new()
		statuses.name = "Statuses"
		statuses.add_theme_font_size_override(&"font_size", 9)
		statuses.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(statuses)

		_enemy_row.add_child(column)
		_entries[enemy] = column
		_refresh_enemy(enemy)


func _refresh_enemy(enemy: Combatant) -> void:
	var column := _entries.get(enemy) as Control
	if column == null:
		return
	var bar := column.get_node("Hp") as ProgressBar
	bar.value = enemy.hp_ratio() * 100.0
	_style_bar(bar, _hp_color(enemy.hp_ratio()))
	(column.get_node("Statuses") as Label).text = " ".join(enemy.status_labels())
	# A downed enemy stays on the field, greyed, rather than popping out and
	# reflowing the whole row mid-fight.
	var sprite := column.get_node("Sprite") as TextureRect
	sprite.modulate = Color(0.35, 0.35, 0.4, 0.55) if not enemy.is_alive() else Color.WHITE
	if not enemy.is_alive():
		(column.get_node("Pointer") as Label).hide()


func _refresh_party(player: Combatant) -> void:
	_party_name.text = "%s   Lv %d" % [player.display_name, player.level]
	_party_hp.value = player.hp_ratio() * 100.0
	_party_hp.tooltip_text = "%d / %d" % [player.hp, player.max_hp]
	_style_bar(_party_hp, _hp_color(player.hp_ratio()))
	_party_poise.value = player.poise_ratio() * 100.0
	_style_bar(_party_poise, POISE_COLOR)
	var tags := player.status_labels()
	if player.staggered:
		tags.append("STAGGERED")
	_party_statuses.text = "%d/%d   %s" % [player.hp, player.max_hp, " ".join(tags)]


func _hp_color(ratio: float) -> Color:
	if ratio > 0.5:
		return HP_HEALTHY
	return HP_HURT if ratio > 0.2 else HP_CRITICAL


func _style_bar(bar: ProgressBar, color: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.13, 0.14, 0.2)
	bar.add_theme_stylebox_override(&"fill", fill)
	bar.add_theme_stylebox_override(&"background", back)


# --- damage numbers --------------------------------------------------------

func _float_number(hit: CombatReport.Hit) -> void:
	var text := ""
	var color := DAMAGE_COLOR
	if hit.missed:
		text = "miss"
		color = MISS_COLOR
	elif hit.amount > 0:
		text = "+%d" % hit.amount
		color = HEAL_COLOR
	elif hit.amount < 0:
		text = str(-hit.amount)
		color = CRIT_COLOR if hit.crit else DAMAGE_COLOR
	else:
		return

	var label := Label.new()
	label.text = text + ("!" if hit.crit else "")
	label.add_theme_font_size_override(&"font_size", 14 if hit.crit else 12)
	label.add_theme_color_override(&"font_color", color)
	label.z_index = 4
	_floaters.add_child(label)
	label.position = _anchor_for(hit.target) - Vector2(0, 8)

	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - FLOATER_RISE, FLOATER_TIME)
	tween.tween_property(label, "modulate:a", 0.0, FLOATER_TIME).set_delay(FLOATER_TIME * 0.4)
	tween.chain().tween_callback(label.queue_free)


## Where a number should pop for [param who]: over their sprite, or over the
## party panel for the player.
func _anchor_for(who: Combatant) -> Vector2:
	var column := _entries.get(who) as Control
	if column != null:
		return column.global_position + Vector2(column.size.x * 0.5, column.size.y * 0.35)
	return _party_panel.global_position + Vector2(_party_panel.size.x * 0.5, -6.0)


func _set_visible(shown: bool) -> void:
	visible = shown
	if not shown:
		_phase = Phase.HIDDEN
		_actor = null
		_staged = null
		_menu.hide()
		_entries.clear()
		for child in _enemy_row.get_children():
			_enemy_row.remove_child(child)
			child.queue_free()
		for child in _floaters.get_children():
			child.queue_free()


## A battler scaled by a whole number, which is what keeps nearest filtering
## crisp: a 16px monster four times over, a pack boss twice (so it towers over its
## escort), and the 64px placeholders as they are. Pack battlers are always frames
## cut from a sheet, which is how a 70px-wide boss is told from a placeholder.
func _battler_size(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2(64, 64)
	var size := texture.get_size()
	var longest := maxf(size.x, size.y)
	var factor := 4.0 if longest <= 24.0 else (2.0 if longest < 64.0 or texture is AtlasTexture else 1.0)
	return size * factor
