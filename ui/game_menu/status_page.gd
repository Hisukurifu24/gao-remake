extends MenuPage
## Status: who you are and how far you have come -- face, level, health and
## experience, what the gear adds to each stat, what you are wearing, where you
## are, and how long you have been at it.

const FACE := "res://assets/ninja_adventure/Actor/Character/SamuraiBlue/Faceset.png"
## [label, GameState's base field, Inventory's bonus name, GameState's total getter].
const STATS := [
	["ATK", &"attack", &"attack", &"total_attack"],
	["DEF", &"defense", &"defense", &"total_defense"],
	["SPD", &"speed", &"speed", &"total_speed"],
	["HP", &"max_hp", &"max_hp", &"total_max_hp"],
]

var _name: Label
var _level: Label
var _mode: PanelContainer
var _mode_text: Label
var _place: Label
var _hp_bar: ProgressBar
var _hp_text: Label
var _xp_bar: ProgressBar
var _xp_text: Label
var _stat_values: Array[Label] = []
var _stat_gear: Array[Label] = []
var _gear_icons: Array[TextureRect] = []
var _gear_names: Array[Label] = []
var _floors: Label
var _played: Label


func title() -> String:
	return "Status"


func _init() -> void:
	var row := box(false, 8, self)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Who: the face, the name, the level, the way this run is played.
	var card := panel(&"InsetPanel", row)
	card.custom_minimum_size = Vector2(176, 0)
	var who := box(true, 4, card)
	who.alignment = BoxContainer.ALIGNMENT_BEGIN
	var frame := panel(&"FacesetFrame", who)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_rect(load(FACE) as Texture2D, Vector2(38, 38), frame)
	_name = label("", &"HeaderLabel", who)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level = label("", &"", who)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode = panel(&"BadgePanel", who)
	_mode.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mode_text = label("", &"BadgeLabel", _mode)
	spacer(who)
	_place = label("", &"HintLabel", who)
	_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var right := box(true, 6, row)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Health and experience, as bars.
	var vitals := box(true, 4, panel(&"InsetPanel", right))
	for which in ["HP", "XP"]:
		var line := box(false, 8, vitals)
		var name_label := label(which, &"HeaderLabel", line)
		name_label.custom_minimum_size = Vector2(32, 0)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(bar)
		var amount := label("", &"", line)
		amount.custom_minimum_size = Vector2(96, 0)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if which == "HP":
			_hp_bar = bar
			_hp_text = amount
		else:
			_xp_bar = bar
			_xp_text = amount
	UiPalette.paint_bar(_xp_bar, UiPalette.POISE)

	# The four stats, each with what the gear adds to it.
	var stats := GridContainer.new()
	stats.columns = 6
	stats.add_theme_constant_override(&"h_separation", 8)
	stats.add_theme_constant_override(&"v_separation", 2)
	panel(&"InsetPanel", right).add_child(stats)
	for stat: Array in STATS:
		var name_label := label(stat[0], &"HeaderLabel", stats)
		name_label.custom_minimum_size = Vector2(36, 0)
		var value := label("", &"", stats)
		value.custom_minimum_size = Vector2(44, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var gear := label("", &"HintLabel", stats)
		gear.custom_minimum_size = Vector2(80, 0)
		_stat_values.append(value)
		_stat_gear.append(gear)

	# What is worn.
	var worn := box(true, 2, panel(&"InsetPanel", right))
	for slot in Inventory.SLOTS:
		var line := box(false, 8, worn)
		_gear_icons.append(icon_rect(null, Vector2(16, 16), line))
		var slot_label := label(String(slot).capitalize(), &"HintLabel", line)
		slot_label.custom_minimum_size = Vector2(104, 0)
		slot_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var item_label := label("", &"", line)
		item_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_gear_names.append(item_label)

	var footer := box(false, 16, right)
	_floors = label("", &"", footer)
	spacer(footer)
	_played = label("", &"", footer)


func shown() -> void:
	_name.text = GameState.player_name
	_level.text = "Level %d" % GameState.level
	_mode.visible = GameState.mode != GameState.Mode.STANDARD
	_mode_text.text = "Death Game" if GameState.mode == GameState.Mode.DEATH_GAME else "Hardcore"
	var map := SceneRouter.current_map() as GameMap
	var place := map.display_name if map != null and not map.display_name.is_empty() else ""
	_place.text = SaveCard.where({"floor": GameState.current_floor, "place": place})

	var top := GameState.total_max_hp()
	_hp_bar.max_value = top
	_hp_bar.value = GameState.hp
	UiPalette.paint_bar(_hp_bar, UiPalette.hp_color(float(GameState.hp) / maxf(1.0, top)))
	_hp_text.text = "%d / %d" % [GameState.hp, top]
	var need := GameState.xp_to_next_level()
	_xp_bar.max_value = need
	_xp_bar.value = GameState.xp
	_xp_text.text = "%d / %d" % [GameState.xp, need]

	for i in STATS.size():
		var stat: Array = STATS[i]
		var total: int = GameState.call(stat[3])
		var gear := Inventory.bonus(stat[2])
		_stat_values[i].text = str(total)
		_stat_gear[i].text = "" if gear == 0 else "%+d gear" % gear
		_stat_gear[i].add_theme_color_override(&"font_color", UiPalette.GOOD if gear > 0 else UiPalette.BAD)

	for i in Inventory.SLOTS.size():
		var stack := Inventory.worn(Inventory.SLOTS[i])
		_gear_icons[i].texture = stack.item.icon if stack != null else null
		_gear_names[i].text = stack.item.label_at(stack.plus) if stack != null else "--"
		_gear_names[i].add_theme_color_override(&"font_color",
				UiPalette.rarity_ink(stack.item.rarity) if stack != null else UiPalette.LOCKED)

	var cleared := 0
	for n in range(1, FloorTuning.TOP_FLOOR + 1):
		if GameState.is_floor_cleared(n):
			cleared += 1
	_floors.text = "Floors cleared %d / %d" % [cleared, FloorTuning.TOP_FLOOR]
	_played.text = "Played %s" % SaveCard.play_time(int(GameState.play_time))
