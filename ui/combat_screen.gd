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

## Colours are [UiPalette]'s -- one health language with the HUD.
const ARROW := preload("res://assets/ninja_adventure/Ui/Arrow.png")

## The player stands in the foreground seen from behind -- the sheet's "up"
## column -- facing the enemies across the field.
const HERO_COLUMN := 1
const HERO_FRAME := Vector2(16, 16)
## A monster with a walk sheet treads in place, this long a frame.
const IDLE_FRAME_TIME := 0.18
## Whoever acts steps this far towards the other side and back; the blow lands
## at the far end of the step.
const LUNGE := 9.0
const LUNGE_TIME := 0.09
## Who is hit flashes this bright for this long.
const FLASH := Color(2.4, 2.4, 2.4)
const FLASH_TIME := 0.12
## A crit, or a blow that staggers, shakes the screen this many units.
const SHAKE := 2.0
const SHAKE_TIME := 0.24

const FLOATER_RISE := 13.0
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
var _idle_time := 0.0
var _hero_texture := AtlasTexture.new()
var _shake: Tween = null

@onready var _backdrop: ColorRect = $Backdrop
@onready var _sky: TextureRect = $Sky
@onready var _sky_glow: TextureRect = $SkyGlow
@onready var _scenery: TextureRect = $Scenery
@onready var _hero: TextureRect = $Hero
@onready var _ground: TextureRect = $Ground
@onready var _horizon: ColorRect = $Horizon
@onready var _enemy_row: HBoxContainer = $Enemies
@onready var _log: Label = $Log/Label
@onready var _party_name: Label = $Party/Rows/Name
@onready var _party_hp: ProgressBar = $Party/Rows/Hp
@onready var _party_poise: ProgressBar = $Party/Rows/Poise
@onready var _party_statuses: Label = $Party/Rows/Statuses
@onready var _menu: Control = $Menu
@onready var _list: VBoxContainer = $Menu/Column/List
@onready var _hint: Label = $Menu/Column/Hint
@onready var _floaters: Control = $Floaters


func _ready() -> void:
	_set_visible(false)
	_hero_texture.atlas = Player.SHEET
	_hero.texture = _hero_texture
	_pose_hero(0)
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
	_paint_backdrop(encounter)
	_log.text = "%s blocks the way." % encounter.label()
	_build_enemies(enemies)
	_refresh_party(party[0])
	_phase = Phase.BUSY
	_menu.hide()


func _on_command_requested(actor: Combatant) -> void:
	_actor = actor
	_refresh_party(actor)
	_show_root()


## The log line at once; the blow itself at the far end of the actor's step, so
## a number, a flash and a falling bar all arrive when the strike does.
func _on_action_resolved(report: CombatReport) -> void:
	_log.text = report.text
	var striker := _stand_of(report.actor)
	var strikes := report.kind == CombatReport.Kind.SKILL and report.hits.any(
			func(hit: CombatReport.Hit) -> bool: return hit.target.is_player != report.actor.is_player)
	if striker == null or not strikes or CombatManager.step_delay <= 0.0:
		_land(report)
		return
	var toward := Vector2(0, -LUNGE) if report.actor.is_player else Vector2(LUNGE * 0.6, LUNGE * 0.6)
	if report.actor.is_player:
		_pose_hero(Player.ATTACK_ROW)
	var home := striker.position
	var step := striker.create_tween()
	step.tween_property(striker, "position", home + toward, LUNGE_TIME)
	step.tween_callback(_land.bind(report))
	step.tween_property(striker, "position", home, LUNGE_TIME * 1.5)
	if report.actor.is_player:
		step.tween_callback(_pose_hero.bind(0))


## What a report does to the field: numbers, flashes, shake, bars.
func _land(report: CombatReport) -> void:
	if not visible:
		return
	var heavy := false
	for hit in report.hits:
		_float_number(hit)
		if hit.amount < 0:
			_flash(hit.target)
			heavy = heavy or hit.crit or hit.staggered
	if heavy:
		_shake_screen()
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


## The field the fight happens on: the biome's own floor tiled across the lower
## half, a horizon line, and the encounter's colour glowing up behind it out of
## the dark. The ground arrives on the [Encounter] because [Bestiary] built it --
## this only draws what it was handed, and a fight with no ground (a test, a
## floor whose biome has no tileset) is the flat backdrop it always was.
func _paint_backdrop(encounter: Encounter) -> void:
	var sky := encounter.backdrop
	_backdrop.color = sky
	_sky_glow.texture = _glow(sky)
	_horizon.color = sky.lerp(Color.BLACK, 0.4)
	_ground.texture = encounter.ground_texture
	_ground.visible = encounter.ground_texture != null
	# Dimmed towards the sky: the ground is a backdrop, and a battler has to read
	# against it.
	_ground.self_modulate = Color.WHITE.lerp(sky, 0.35)
	_horizon.visible = _ground.visible
	# A painted sky (the sky's clouds) replaces the glow; dimmed like the rest,
	# further, since it is further away.
	_sky.texture = encounter.sky_texture
	_sky.visible = encounter.sky_texture != null
	_sky.self_modulate = Color.WHITE.lerp(sky, 0.45)
	_sky_glow.visible = not _sky.visible
	_scenery.texture = encounter.scenery
	_scenery.visible = encounter.scenery != null
	if _scenery.visible:
		_scenery.offset_top = _scenery.offset_bottom - encounter.scenery.get_height()
	_scenery.self_modulate = Color.WHITE.lerp(sky, 0.5)


## A vertical fade from nothing down to [param sky] lifted towards the light,
## sat behind the horizon so the sky has somewhere to be.
func _glow(sky: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(sky.r, sky.g, sky.b, 0.0))
	gradient.set_color(1, sky.lightened(0.28))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 8
	texture.height = 100
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.DOWN
	return texture


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
		row.set_meta(&"locked", i in locked)
		_list.add_child(row)
		if _selected < 0 and i not in locked:
			_selected = i

	_selected = maxi(_selected, 0)
	_rows_text = labels
	_paint()
	_menu.show()
	# Collapse onto the new rows: the panel is anchored bottom-right and grows up
	# and left.
	UiLayout.shrink_wrap(_menu)


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
	_highlight_target()


## Marks the enemy the cursor is on, so targeting reads on the battlefield and
## not only in the menu.
func _highlight_target() -> void:
	for enemy in _entries:
		var pointer := _entries[enemy].get_node("Pointer") as CanvasItem
		var aimed := _phase == Phase.TARGET and _selected < _target_rows.size() \
				and _target_rows[_selected] == enemy
		pointer.modulate.a = 1.0 if aimed else 0.0


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
		column.add_theme_constant_override(&"separation", 1)
		column.custom_minimum_size = Vector2(56, 0)

		# The pack's arrow, held in place by alpha rather than visibility so the
		# sprite under it doesn't jump when targeting starts.
		var pointer := TextureRect.new()
		pointer.name = "Pointer"
		pointer.texture = ARROW
		pointer.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		pointer.modulate.a = 0.0
		column.add_child(pointer)

		# The sprite stands in a plain Control rather than straight in the column,
		# so it can step forward and back without the column laying it out again.
		var stand := Control.new()
		stand.name = "Stand"
		stand.custom_minimum_size = _battler_size(enemy.battler)
		column.add_child(stand)
		var sprite := TextureRect.new()
		sprite.name = "Sprite"
		sprite.texture = _idle_texture(enemy)
		sprite.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		stand.add_child(sprite)

		var name_label := Label.new()
		name_label.name = "Name"
		name_label.text = enemy.display_name
		name_label.theme_type_variation = &"FieldLabel"
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(name_label)

		var bar := ProgressBar.new()
		bar.name = "Hp"
		bar.custom_minimum_size = Vector2(0, 4)
		bar.show_percentage = false
		column.add_child(bar)

		var statuses := Label.new()
		statuses.name = "Statuses"
		statuses.theme_type_variation = &"FieldLabel"
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
	UiPalette.paint_bar(bar, UiPalette.hp_color(enemy.hp_ratio()))
	(column.get_node("Statuses") as Label).text = " ".join(enemy.status_labels())
	# A downed enemy stays on the field, greyed, rather than popping out and
	# reflowing the whole row mid-fight.
	var sprite := column.get_node("Stand/Sprite") as TextureRect
	sprite.modulate = Color(0.35, 0.35, 0.4, 0.55) if not enemy.is_alive() else Color.WHITE
	if not enemy.is_alive():
		(column.get_node("Pointer") as CanvasItem).modulate.a = 0.0


func _refresh_party(player: Combatant) -> void:
	_party_name.text = "%s   Lv %d" % [player.display_name, player.level]
	_party_hp.value = player.hp_ratio() * 100.0
	_party_hp.tooltip_text = "%d / %d" % [player.hp, player.max_hp]
	UiPalette.paint_bar(_party_hp, UiPalette.hp_color(player.hp_ratio()))
	_party_poise.value = player.poise_ratio() * 100.0
	UiPalette.paint_bar(_party_poise, UiPalette.POISE)
	var tags := player.status_labels()
	if player.staggered:
		tags.append("STAGGERED")
	_party_statuses.text = "%d/%d   %s" % [player.hp, player.max_hp, " ".join(tags)]


# --- damage numbers --------------------------------------------------------

func _float_number(hit: CombatReport.Hit) -> void:
	var text := ""
	var color := UiPalette.DAMAGE
	if hit.missed:
		text = "miss"
		color = UiPalette.MISS
	elif hit.amount > 0:
		text = "+%d" % hit.amount
		color = UiPalette.HEAL
	elif hit.amount < 0:
		text = str(-hit.amount)
		color = UiPalette.CRIT if hit.crit else UiPalette.DAMAGE
	else:
		return

	var label := Label.new()
	label.text = text + ("!" if hit.crit else "")
	# The pixel font only scales by whole multiples of 8, so a crit is told
	# apart by colour and its "!" rather than by being a size bigger.
	label.theme_type_variation = &"FieldLabel"
	label.add_theme_font_size_override(&"font_size", 16)
	label.add_theme_color_override(&"font_color", color)
	label.z_index = 4
	_floaters.add_child(label)
	label.position = _anchor_for(hit.target) - Vector2(0, 4)

	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - FLOATER_RISE, FLOATER_TIME)
	tween.tween_property(label, "modulate:a", 0.0, FLOATER_TIME).set_delay(FLOATER_TIME * 0.4)
	tween.chain().tween_callback(label.queue_free)


## Where a number should pop for [param who]: over their sprite, the player's
## included.
func _anchor_for(who: Combatant) -> Vector2:
	var column := _entries.get(who) as Control
	if column != null:
		return column.global_position + Vector2(column.size.x * 0.5, column.size.y * 0.35)
	return _hero.global_position + Vector2(_hero.size.x * 0.5, -3.0)


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
		if _shake != null:
			_shake.kill()
		offset = Vector2.ZERO
		_pose_hero(0)


## A battler scaled so it lands on whole screen pixels, which is what keeps
## nearest filtering crisp: a 16px monster twice over, a pack boss at its own
## size (so it towers over its escort), and the 64px placeholders at half -- the
## screen is laid out in 320x180 units and drawn at least twice that, so half a
## unit is still a whole pixel. Pack battlers are always frames cut from a sheet,
## which is how a 70px-wide boss is told from a placeholder.
func _battler_size(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2(32, 32)
	var size := texture.get_size()
	var longest := maxf(size.x, size.y)
	var factor := 2.0 if longest <= 24.0 else (1.0 if longest < 64.0 or texture is AtlasTexture else 0.5)
	return size * factor


# --- the field moving ------------------------------------------------------

## Monsters with a walk sheet tread in place: alive is something you can see.
func _process(delta: float) -> void:
	if not visible:
		return
	_idle_time += delta
	var frame := int(_idle_time / IDLE_FRAME_TIME)
	for enemy in _entries:
		var sprite := _entries[enemy].get_node("Stand/Sprite") as TextureRect
		var art := sprite.texture as AtlasTexture
		if art == null or not art.has_meta(&"frames") or not enemy.is_alive():
			continue
		var base: Rect2 = art.get_meta(&"base")
		var step: Vector2 = art.get_meta(&"step")
		art.region = Rect2(base.position + step * (frame % int(art.get_meta(&"frames"))), base.size)


## [param enemy]'s battler, as its own copy when it can tread in place -- the
## type's texture is shared, and stepping its region would step every monster of
## that kind at once. A 4x4 sheet treads down its front-facing column, an Nx1
## side view along its row.
func _idle_texture(enemy: Combatant) -> Texture2D:
	var art := enemy.battler as AtlasTexture
	var type := enemy.source
	if art == null or type == null or type.sheet == null or art.atlas != type.sheet:
		return enemy.battler
	var frames := type.sheet_frames
	var cell := type.sheet.get_size() / Vector2(frames)
	var count := frames.y if frames.y > 1 else frames.x
	if count <= 1:
		return enemy.battler
	var own := art.duplicate() as AtlasTexture
	own.set_meta(&"base", art.region)
	own.set_meta(&"step", Vector2(0, cell.y) if frames.y > 1 else Vector2(cell.x, 0))
	own.set_meta(&"frames", count)
	return own


## The player's sheet at [param row] of the facing column: 0 standing,
## [constant Player.ATTACK_ROW] mid-swing.
func _pose_hero(row: int) -> void:
	_hero_texture.region = Rect2(Vector2(HERO_COLUMN, row) * HERO_FRAME, HERO_FRAME)


## What steps forward when [param who] acts: their sprite, or the player's.
func _stand_of(who: Combatant) -> Control:
	if who == null:
		return null
	if who.is_player:
		return _hero
	var column := _entries.get(who) as Control
	return column.get_node("Stand/Sprite") as Control if column != null else null


func _flash(who: Combatant) -> void:
	var sprite := _stand_of(who)
	if sprite == null or (not who.is_player and not who.is_alive()):
		return
	sprite.self_modulate = FLASH
	sprite.create_tween().tween_property(sprite, "self_modulate", Color.WHITE, FLASH_TIME)


## Shakes the whole layer, settling back to rest -- in whole units, so the pixel
## grid never smears.
func _shake_screen() -> void:
	if _shake != null:
		_shake.kill()
	_shake = create_tween()
	var steps := 6
	for i in steps:
		var strength := SHAKE * (1.0 - float(i) / steps)
		var kick := Vector2(strength if i % 2 == 0 else -strength, roundf(strength * 0.5) * (1 if i % 3 == 0 else -1))
		_shake.tween_property(self, "offset", kick.round(), SHAKE_TIME / steps)
	_shake.tween_property(self, "offset", Vector2.ZERO, SHAKE_TIME / steps)
