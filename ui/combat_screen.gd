extends CanvasLayer
## The old battle stage: a fight drawn on a screen of its own, for a fight that
## was not staged on the map -- a boss, until bosses step out of their doors
## (plan.md M5.5 §6 step 4). The words and the menu are [BattleHud]'s and the
## player's vitals the HUD's, for either kind of fight; this draws only the
## place and the fighters, and decides nothing.
##
## The static frame is in the .tscn; enemy entries and damage numbers are built
## in code because their count is only known once a fight starts.

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

## The pause that hides the screen after a fight. Held so the next fight can
## cancel it -- see [member BattleHud._outro].
var _outro: Tween = null
## Enemy [Combatant] to the panel drawing it, so a report can find its sprite.
var _entries: Dictionary[Combatant, Control] = {}
var _idle_time := 0.0
var _hero_texture := AtlasTexture.new()
var _shake: Tween = null
## A field arrived for the fight about to begin: the map draws it, not this.
var _staged_next := false

@onready var _backdrop: ColorRect = $Backdrop
@onready var _sky: TextureRect = $Sky
@onready var _sky_glow: TextureRect = $SkyGlow
@onready var _scenery: TextureRect = $Scenery
@onready var _hero: TextureRect = $Hero
@onready var _ground: TextureRect = $Ground
@onready var _horizon: ColorRect = $Horizon
@onready var _enemy_row: HBoxContainer = $Enemies
@onready var _floaters: Control = $Floaters


func _ready() -> void:
	_set_visible(false)
	_hero_texture.atlas = Player.SHEET
	_hero.texture = _hero_texture
	_pose_hero(0)
	EventBus.battle_staged.connect(_on_battle_staged)
	CombatManager.combat_began.connect(_on_combat_began)
	CombatManager.action_resolved.connect(_on_action_resolved)
	CombatManager.combat_finished.connect(_on_combat_finished)
	var hud := get_node_or_null(^"../BattleHud") as BattleHud
	if hud != null:
		hud.aimed.connect(_highlight_target)


# --- combat signals --------------------------------------------------------

func _on_combat_began(encounter: Encounter, _party: Array[Combatant], enemies: Array[Combatant]) -> void:
	if _outro != null:
		_outro.kill()
		_outro = null
	var on_map := _staged_next
	_staged_next = false
	_set_visible(not on_map)
	if on_map:
		return
	_paint_backdrop(encounter)
	_build_enemies(enemies)


## The blow lands at the far end of the actor's step, so a number, a flash and
## a falling bar all arrive when the strike does.
func _on_action_resolved(report: CombatReport) -> void:
	if not visible:
		return
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
		if not touched.is_player:
			_refresh_enemy(touched)


func _on_combat_finished(_result: CombatResult) -> void:
	_highlight_target(null)
	if not visible:
		return
	# Tests run with no pacing at all; there is nobody to read the result to.
	if CombatManager.step_delay <= 0.0:
		_set_visible(false)
		return
	_outro = create_tween()
	_outro.tween_interval(BattleHud.OUTRO_TIME)
	_outro.tween_callback(_set_visible.bind(false))


## The fight will be on the map, and [BattleHud] puts a stage there to draw it.
func _on_battle_staged(_field: BattleField) -> void:
	_staged_next = true


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


# --- battlefield -----------------------------------------------------------

## Marks the enemy [BattleHud]'s cursor is on, so targeting reads on the
## battlefield and not only in the menu.
func _highlight_target(target: Combatant) -> void:
	for enemy in _entries:
		var pointer := _entries[enemy].get_node("Pointer") as CanvasItem
		pointer.modulate.a = 1.0 if enemy == target and enemy.is_alive() else 0.0


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
