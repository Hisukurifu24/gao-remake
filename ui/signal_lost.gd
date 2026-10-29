extends CanvasLayer
## Marathon's idle countdown, and the avatar shattering when it runs out -- the
## view of [IdleWatch], which owns the clock and the ending.
##
## While it counts down, a system notice hangs at the top of the screen, the world
## dims towards black and the avatar flickers, more often the less time is left:
## the connection going. Any input and it is all gone at once. When it runs out
## the avatar flares white and breaks into shards of light, as SAO draws a death,
## and the game leaves for the title under it.
##
## Built in code: one panel, two lines and a dim, nothing to lay out.

const GLASS := preload("res://ui/theme/glass_theme.tres")

## How dark the world gets by the last second of the countdown.
const DIM_MAX := 0.45
## Shards the avatar breaks into, and how long they fly.
const SHARDS := 30
const SHARD_TIME := 1.5
const FLARE_TIME := 0.35

var _dim: ColorRect = null
var _notice: PanelContainer = null
var _header: Label = null
var _line: Label = null
var _seconds_left := -1
var _flicker := 0.0


func _ready() -> void:
	layer = 9
	_build()
	_reset()
	EventBus.idle_countdown.connect(_on_countdown)
	EventBus.idle_cleared.connect(_reset)
	EventBus.avatar_logged_out.connect(_on_logged_out)
	EventBus.title_requested.connect(func(_notice_text: String) -> void: _reset())


func _build() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(UiPalette.SHADOW, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_notice = PanelContainer.new()
	_notice.name = "Notice"
	_notice.theme = GLASS
	_notice.theme_type_variation = &"HudPanel"
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.offset_top = 36.0
	add_child(_notice)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 2)
	_notice.add_child(rows)
	_header = Label.new()
	_header.theme_type_variation = &"HeaderLabel"
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_theme_color_override(&"font_color", UiPalette.HP_CRITICAL)
	rows.add_child(_header)
	_line = Label.new()
	_line.custom_minimum_size = Vector2(300, 0)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_line)


func _reset() -> void:
	_seconds_left = -1
	_notice.hide()
	_dim.color.a = 0.0
	var sprite := _avatar()
	if sprite != null:
		sprite.self_modulate.a = 1.0


func _on_countdown(seconds_left: int) -> void:
	_seconds_left = seconds_left
	_header.text = "WARNING: NO SIGNAL"
	_line.text = "No input from your NerveGear. Cardinal will log this avatar out in %d:%02d." \
			% [seconds_left / 60, seconds_left % 60]
	_notice.show()
	var gone := 1.0 - clampf(seconds_left / maxf(1.0, IdleWatch.warning), 0.0, 1.0)
	create_tween().tween_property(_dim, "color:a", DIM_MAX * gone, 0.5)


## The avatar drops out for a frame or two now and then, more often towards the end.
func _process(delta: float) -> void:
	if _seconds_left < 0:
		return
	var sprite := _avatar()
	if sprite == null:
		return
	_flicker -= delta
	if _flicker > 0.0:
		return
	var urgency := 1.0 - clampf(_seconds_left / maxf(1.0, IdleWatch.warning), 0.0, 1.0)
	if sprite.self_modulate.a < 1.0:
		sprite.self_modulate.a = 1.0
		_flicker = lerpf(1.6, 0.25, urgency) * randf_range(0.5, 1.5)
	else:
		sprite.self_modulate.a = randf_range(0.15, 0.5)
		_flicker = randf_range(0.04, 0.12)


func _on_logged_out() -> void:
	_seconds_left = -1
	_header.text = "LOGGED OUT"
	_line.text = "Cardinal has logged out an idle avatar."
	_notice.show()
	create_tween().tween_property(_dim, "color:a", DIM_MAX, 0.3)
	var sprite := _avatar()
	if sprite == null or IdleWatch.shatter_time <= 0.0:
		return
	sprite.self_modulate = Color(1, 1, 1, 1)
	var flare := sprite.create_tween()
	flare.tween_property(sprite, "self_modulate", Color(2.2, 2.6, 3.0, 1.0), FLARE_TIME)
	flare.tween_callback(_shatter.bind(sprite))


func _shatter(sprite: Sprite2D) -> void:
	var map := SceneRouter.current_map()
	if map == null:
		sprite.self_modulate.a = 0.0
		return
	Shards.burst(sprite, map, SHARDS, SHARD_TIME)


## The player's sprite on the map that is up, or null.
func _avatar() -> Sprite2D:
	var map := SceneRouter.current_map()
	return map.get_node_or_null("Player/Sprite2D") as Sprite2D if map != null else null
