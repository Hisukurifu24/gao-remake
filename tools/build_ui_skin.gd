extends SceneTree
## Builds the UI's font faces and its two themes, the frames from Kenney's Fantasy
## UI Borders (CC0).
##
##     "$GODOT" --headless --path . --script res://tools/build_ui_skin.gd
##
## Writes [code]ui/theme/ui_font.tres[/code] and [code]ui_font_strong.tres[/code]
## (Exo 2 at two weights), [code]ui/theme/gao_theme.tres[/code] (the menus, applied
## project-wide) and [code]ui/theme/glass_theme.tres[/code] (what is drawn over the
## map, set on those screens' own roots). Safe to re-run; it only touches those
## derived resources -- so don't edit them by hand: change the tables here, or the
## colours in [UiPalette], and run it again.
##
## The pack draws its frames white on transparent at twice the art's size, in two
## parts: [code]Border/[/code] is the line, [code]Panel/[/code] the line plus a fill
## inset a pixel inside it. The tool halves both (checking every 2x2 block is one
## colour, so nothing is lost), paints the line one colour and the fill another, and
## leaves the gap between them clear for the ground to show through -- one unit of
## frame, half a world pixel at the map's zoom. A frame's nine-slice margin is read
## off the drawing, never typed: the corner is wherever the rows and columns stop
## matching the straight edge in the middle. The textures are embedded, lossless,
## so the themes need no import step and the sources stay out of the editor's
## imports ([code].gdignore[/code]).
##
## The font is Exo 2 (SIL OFL, [code]assets/fonts/[/code]), a variable font: one
## file, every weight. It is drawn smooth at the window's resolution -- the
## viewport stretches canvas items, so text is rasterised for the screen, not for
## 640x360 -- and its import turns hinting off and positions glyphs to a quarter
## pixel, without which the 2x stretch spaces letters unevenly.

const SOURCE := "res://assets/kenney_fantasy_ui"
const FONT_FILE := "res://assets/fonts/Exo2-Variable.ttf"
const FONT_OUT := "res://ui/theme/ui_font.tres"
const STRONG_OUT := "res://ui/theme/ui_font_strong.tres"
const LIGHT_OUT := "res://ui/theme/gao_theme.tres"
const GLASS_OUT := "res://ui/theme/glass_theme.tres"

## The two weights (Exo 2 runs 100-900): text, and headers and titles.
const WEIGHT := 520
const STRONG_WEIGHT := 680
## Font sizes in 640x360 units. One for text, one for the few big words.
const TEXT_SIZE := 12
const TITLE_SIZE := 24

## The pack's frame numbers this skin draws with.
const PLAIN := 15     # a plain line
const KNOT := 1       # a square knot in each corner -- the windows
const STEPPED := 7    # knot and step -- the dialogue box

## Content margins, [left, top, right, bottom], in 640x360 units. A line of text
## brings its own ascent and descent, a few units each way, so the vertical
## margins are what is left to keep it clear of the frame; the knotted corners
## reach 5 in.
const WINDOW_PAD := [10, 8, 10, 8]
const MENU_WINDOW_PAD := [8, 8, 8, 8]
const HUD_PAD := [6, 3, 6, 4]
const DIALOG_PAD := [12, 8, 12, 8]
const CHOICE_PAD := [9, 5, 9, 5]
const FACESET_PAD := [4, 4, 4, 4]
const NAME_PAD := [7, 1, 7, 2]
const BUTTON_PAD := [8, 2, 8, 2]
const ROW_PAD := [8, 2, 8, 2]
const TAB_PAD := [9, 4, 9, 2]
const BADGE_PAD := [4, 0, 4, 1]
## The slider's groove, drawn this far either side of its middle.
const GROOVE_PAD := [0, 3, 0, 3]
const GRABBER_SIZE := Vector2i(5, 11)

var _font: Font
var _strong: Font
var _sources := {}
var _textures := {}


func _init() -> void:
	_font = _face(WEIGHT)
	_strong = _face(STRONG_WEIGHT)
	for pair: Array in [[_font, FONT_OUT], [_strong, STRONG_OUT]]:
		var err := ResourceSaver.save(pair[0], pair[1])
		if err != OK:
			push_error("could not write %s: %s" % [pair[1], error_string(err)])
			quit(1)
			return
		print("wrote ", pair[1])
		(pair[0] as Resource).take_over_path(pair[1])
	var light := _light_theme()
	var glass := _glass_theme()
	if light == null or glass == null:
		quit(1)
		return
	for pair: Array in [[light, LIGHT_OUT], [glass, GLASS_OUT]]:
		var err := ResourceSaver.save(pair[0], pair[1])
		if err != OK:
			push_error("could not write %s: %s" % [pair[1], error_string(err)])
			quit(1)
			return
		print("wrote ", pair[1])
	quit()


# --- the two themes ------------------------------------------------------------

## The menus: white panels, dark ink, the orange cursor.
func _light_theme() -> Theme:
	var theme := _base(UiPalette.TEXT, UiPalette.DIM, UiPalette.HEADER)
	var window := _frame(KNOT, UiPalette.WINDOW_LINE, UiPalette.WINDOW_FILL, WINDOW_PAD)
	theme.set_stylebox(&"panel", &"Panel", window)
	theme.set_stylebox(&"panel", &"PanelContainer", window)
	_variant(theme, &"MenuWindow", &"PanelContainer",
			_frame(KNOT, UiPalette.WINDOW_LINE, UiPalette.WINDOW_FILL, MENU_WINDOW_PAD))
	_variant(theme, &"InsetPanel", &"PanelContainer",
			_frame(PLAIN, UiPalette.INSET_LINE, UiPalette.INSET_FILL, WINDOW_PAD))
	_variant(theme, &"CardLit", &"PanelContainer",
			_frame(PLAIN, UiPalette.ACCENT_LINE, UiPalette.LIT_FILL, WINDOW_PAD))
	_variant(theme, &"FacesetFrame", &"PanelContainer",
			_frame(PLAIN, UiPalette.INSET_LINE, UiPalette.INSET_FILL, FACESET_PAD))
	_variant(theme, &"CellPanel", &"Panel",
			_frame(PLAIN, UiPalette.INSET_LINE, UiPalette.INSET_FILL, [0, 0, 0, 0]))
	_variant(theme, &"MapPanel", &"PanelContainer",
			_frame(PLAIN, UiPalette.MAP_FRAME_LINE, UiPalette.MAP_FRAME_FILL, WINDOW_PAD))
	# A tag, not a window: a frame line round a word that small crowds it.
	var badge := StyleBoxFlat.new()
	badge.bg_color = UiPalette.BADGE_FILL
	badge.anti_aliasing = false
	_pad(badge, BADGE_PAD)
	_variant(theme, &"BadgePanel", &"PanelContainer", badge)
	_label(theme, &"BadgeLabel", UiPalette.FIELD)
	# A stack's count in the corner of its bag cell, over the icon: ink, with the
	# cell's white as its shadow so it parts from whatever it lands on.
	_label(theme, &"CountLabel", UiPalette.TEXT)
	theme.set_color(&"font_shadow_color", &"CountLabel", UiPalette.INSET_FILL)

	var focus := _frame(PLAIN, UiPalette.ACCENT_FILL, Color.TRANSPARENT, [0, 0, 0, 0], true)
	focus.expand_margin_left = 1.0
	focus.expand_margin_top = 1.0
	focus.expand_margin_right = 1.0
	focus.expand_margin_bottom = 1.0
	_variant(theme, &"FocusFrame", &"Panel", focus)

	_variant(theme, &"TabOn", &"PanelContainer",
			_frame(PLAIN, UiPalette.ACCENT_LINE, UiPalette.ACCENT_FILL, TAB_PAD))
	_variant(theme, &"TabOff", &"PanelContainer",
			_frame(PLAIN, UiPalette.WINDOW_LINE, UiPalette.TAB_FILL, TAB_PAD))
	_variant(theme, &"TabHover", &"PanelContainer",
			_frame(PLAIN, UiPalette.WINDOW_LINE, UiPalette.INSET_FILL, TAB_PAD))

	_variant(theme, &"MenuRow", &"PanelContainer",
			_frame(PLAIN, UiPalette.INSET_LINE, UiPalette.INSET_FILL, ROW_PAD))
	_variant(theme, &"MenuRowFocus", &"PanelContainer",
			_frame(PLAIN, UiPalette.ACCENT_LINE, UiPalette.ACCENT_FILL, ROW_PAD))
	_variant(theme, &"MenuRowLocked", &"PanelContainer",
			_frame(PLAIN, UiPalette.LOCKED_LINE, UiPalette.LOCKED_FILL, ROW_PAD))

	theme.set_stylebox(&"normal", &"Button",
			_frame(PLAIN, UiPalette.INSET_LINE, UiPalette.INSET_FILL, BUTTON_PAD))
	theme.set_stylebox(&"hover", &"Button",
			_frame(PLAIN, UiPalette.ACCENT_LINE, UiPalette.ACCENT_FILL, BUTTON_PAD))
	theme.set_stylebox(&"pressed", &"Button",
			_frame(PLAIN, UiPalette.ACCENT_LINE, UiPalette.ACCENT_LINE, BUTTON_PAD))
	theme.set_stylebox(&"disabled", &"Button",
			_frame(PLAIN, UiPalette.LOCKED_LINE, UiPalette.LOCKED_FILL, BUTTON_PAD))
	theme.set_stylebox(&"focus", &"Button", StyleBoxEmpty.new())
	theme.set_color(&"font_color", &"Button", UiPalette.TEXT)
	theme.set_color(&"font_focus_color", &"Button", UiPalette.TEXT)
	theme.set_color(&"font_hover_color", &"Button", UiPalette.ON_ACCENT)
	theme.set_color(&"font_pressed_color", &"Button", UiPalette.ON_ACCENT)
	theme.set_color(&"font_hover_pressed_color", &"Button", UiPalette.ON_ACCENT)
	theme.set_color(&"font_disabled_color", &"Button", UiPalette.LOCKED)

	# The one box anything is typed into: the inset, its frame lit while it is.
	theme.set_stylebox(&"normal", &"LineEdit",
			_frame(PLAIN, UiPalette.INSET_LINE, UiPalette.INSET_FILL, ROW_PAD))
	theme.set_stylebox(&"focus", &"LineEdit",
			_frame(PLAIN, UiPalette.ACCENT_LINE, UiPalette.INSET_FILL, ROW_PAD))
	theme.set_color(&"font_color", &"LineEdit", UiPalette.TEXT)
	theme.set_color(&"font_selected_color", &"LineEdit", UiPalette.ON_ACCENT)
	theme.set_color(&"selection_color", &"LineEdit", UiPalette.ACCENT_FILL)
	theme.set_color(&"caret_color", &"LineEdit", UiPalette.ACCENT_LINE)

	# A slider sits on a white plate or the lit orange one, so its groove is dark on
	# both, and what is filled in is the orange inside that dark.
	theme.set_stylebox(&"slider", &"HSlider", _groove(UiPalette.BAR_TROUGH))
	theme.set_stylebox(&"grabber_area", &"HSlider", _groove(UiPalette.ACCENT_FILL))
	theme.set_stylebox(&"grabber_area_highlight", &"HSlider", _groove(UiPalette.ACCENT_FILL))
	var grabber := _grabber()
	for icon: StringName in [&"grabber", &"grabber_highlight", &"grabber_disabled"]:
		theme.set_icon(icon, &"HSlider", grabber)
	theme.set_constant(&"center_grabber", &"HSlider", 1)

	# The map is a dark sheet inside the white window, written in its own light.
	_label(theme, &"MapLabel", UiPalette.MAP_LABEL)
	# What sits over the map in a menu's corner is glass, as it is in play.
	_glass_plates(theme)
	return theme


## Over the map: dark glass, light text. Set on a screen's own root, it overrides
## the project theme for everything under it.
func _glass_theme() -> Theme:
	var theme := _base(UiPalette.GLASS_TEXT, UiPalette.GLASS_DIM, UiPalette.GLASS_HEADER)
	var window := _frame(KNOT, UiPalette.GLASS_LINE, UiPalette.GLASS_FILL, WINDOW_PAD)
	theme.set_stylebox(&"panel", &"Panel", window)
	theme.set_stylebox(&"panel", &"PanelContainer", window)
	_variant(theme, &"FacesetFrame", &"PanelContainer",
			_frame(PLAIN, UiPalette.GLASS_LINE, UiPalette.GLASS_FILL, FACESET_PAD))
	_glass_plates(theme)
	return theme


## The plates that are glass in either theme: the HUD's, and the conversation's.
func _glass_plates(theme: Theme) -> void:
	_variant(theme, &"HudPanel", &"PanelContainer",
			_frame(PLAIN, UiPalette.GLASS_LINE, UiPalette.GLASS_FILL, HUD_PAD))
	_variant(theme, &"DialogPanel", &"PanelContainer",
			_frame(STEPPED, UiPalette.GLASS_LINE, UiPalette.GLASS_FILL, DIALOG_PAD))
	_variant(theme, &"ChoicePanel", &"PanelContainer",
			_frame(PLAIN, UiPalette.GLASS_LINE, UiPalette.GLASS_FILL, CHOICE_PAD))
	_variant(theme, &"NameTag", &"PanelContainer",
			_frame(PLAIN, UiPalette.ACCENT_FILL, UiPalette.GLASS_FILL, NAME_PAD))


## Exo 2 at one weight.
func _face(weight: int) -> FontVariation:
	var face := FontVariation.new()
	face.base_font = load(FONT_FILE) as Font
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	face.variation_opentype = {wght: weight}
	return face


## What both themes share: the font, the label roles, the bars.
func _base(text: Color, dim: Color, header: Color) -> Theme:
	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = TEXT_SIZE
	theme.set_color(&"font_color", &"Label", text)
	theme.set_constant(&"line_spacing", &"Label", 0)
	_label(theme, &"HeaderLabel", header)
	theme.set_font(&"font", &"HeaderLabel", _strong)
	_label(theme, &"HintLabel", dim)
	_label(theme, &"InkLabel", text)
	_label(theme, &"FieldLabel", UiPalette.FIELD)
	theme.set_color(&"font_shadow_color", &"FieldLabel", UiPalette.SHADOW)
	_label(theme, &"TitleLabel", UiPalette.FIELD)
	theme.set_color(&"font_shadow_color", &"TitleLabel", UiPalette.SHADOW)
	theme.set_font(&"font", &"TitleLabel", _strong)
	theme.set_font_size(&"font_size", &"TitleLabel", TITLE_SIZE)
	theme.set_constant(&"shadow_offset_x", &"TitleLabel", 1)
	theme.set_constant(&"shadow_offset_y", &"TitleLabel", 1)

	var trough := StyleBoxFlat.new()
	trough.bg_color = UiPalette.BAR_TROUGH
	trough.set_border_width_all(1)
	trough.border_color = UiPalette.SHADOW
	trough.anti_aliasing = false
	theme.set_stylebox(&"background", &"ProgressBar", trough)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiPalette.HP_CRITICAL
	fill.set_border_width_all(1)
	fill.border_color = UiPalette.SHADOW
	fill.anti_aliasing = false
	theme.set_stylebox(&"fill", &"ProgressBar", fill)
	return theme


func _groove(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_border_width_all(1)
	box.border_color = UiPalette.SHADOW
	box.anti_aliasing = false
	_pad(box, GROOVE_PAD)
	return box


## The handle: the inset's white with a line round it, which shows on any plate.
func _grabber() -> Texture2D:
	var drawn := Image.create_empty(GRABBER_SIZE.x, GRABBER_SIZE.y, false, Image.FORMAT_RGBA8)
	drawn.fill(UiPalette.SHADOW)
	drawn.fill_rect(Rect2i(Vector2i.ONE, GRABBER_SIZE - Vector2i(2, 2)), UiPalette.INSET_FILL)
	return _embedded(drawn)


func _variant(theme: Theme, name: StringName, base: StringName, box: StyleBox) -> void:
	theme.set_type_variation(name, base)
	theme.set_stylebox(&"panel", name, box)


func _label(theme: Theme, name: StringName, colour: Color) -> void:
	theme.set_type_variation(name, &"Label")
	theme.set_color(&"font_color", name, colour)


# --- frames --------------------------------------------------------------------

## A nine-slice of frame [param number], its line and fill in the colours given.
## [param thick] doubles the line inwards over the gap -- the cursor, which has to
## read at a glance.
func _frame(number: int, line: Color, fill: Color, pad: Array, thick := false) -> StyleBoxTexture:
	var key := "%d/%s/%s/%s" % [number, line.to_html(), fill.to_html(), thick]
	if not _textures.has(key):
		var parts := _parts(number)
		_textures[key] = _embedded(_paint(parts[0], parts[1], line, fill, thick))
	var box := StyleBoxTexture.new()
	box.texture = _textures[key]
	var margin := _margins(number)
	box.texture_margin_left = margin.x
	box.texture_margin_right = margin.x
	box.texture_margin_top = margin.y
	box.texture_margin_bottom = margin.y
	_pad(box, pad)
	return box


func _embedded(image: Image) -> Texture2D:
	var texture := PortableCompressedTexture2D.new()
	texture.keep_compressed_buffer = true
	texture.create_from_image(image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	return texture


func _pad(box: StyleBox, pad: Array) -> void:
	box.content_margin_left = pad[0]
	box.content_margin_top = pad[1]
	box.content_margin_right = pad[2]
	box.content_margin_bottom = pad[3]


func _paint(border: Image, panel: Image, line: Color, fill: Color, thick: bool) -> Image:
	var size := border.get_size()
	var drawn := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			if _solid(border, x, y):
				drawn.set_pixel(x, y, line)
			elif thick and _beside_line(border, panel, x, y):
				drawn.set_pixel(x, y, line)
			elif _solid(panel, x, y):
				drawn.set_pixel(x, y, fill)
	return drawn


## A gap pixel: clear in both drawings, next to the line, and not outside it.
func _beside_line(border: Image, panel: Image, x: int, y: int) -> bool:
	if _solid(panel, x, y) or not _inside(border, x, y):
		return false
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var at := Vector2i(x, y) + step
		if Rect2i(Vector2i.ZERO, border.get_size()).has_point(at) and _solid(border, at.x, at.y):
			return true
	return false


## Whether a clear pixel is enclosed by the line: some line pixel on all four sides.
func _inside(border: Image, x: int, y: int) -> bool:
	var size := border.get_size()
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var at := Vector2i(x, y) + step
		var found := false
		while Rect2i(Vector2i.ZERO, size).has_point(at):
			if _solid(border, at.x, at.y):
				found = true
				break
			at += step
		if not found:
			return false
	return true


## The nine-slice margins of a frame: how far in from each edge its corner reaches,
## read off the drawing as where the rows (and columns) start matching the straight
## edge at the middle. Symmetric, as the pack draws them.
func _margins(number: int) -> Vector2i:
	var panel: Image = _parts(number)[1]
	var size := panel.get_size()
	return Vector2i(_reach(panel, size.x, size.y, true), _reach(panel, size.y, size.x, false))


func _reach(image: Image, along: int, across: int, columns: bool) -> int:
	var middle := along / 2
	for m in range(1, middle):
		var straight := true
		for i in range(m, middle + 1):
			for j in across:
				var here := _solid(image, i, j) if columns else _solid(image, j, i)
				var mid := _solid(image, middle, j) if columns else _solid(image, j, middle)
				if here != mid:
					straight = false
					break
			if not straight:
				break
		if straight:
			return m
	return middle


func _solid(image: Image, x: int, y: int) -> bool:
	return image.get_pixel(x, y).a > 0.5


## [border, panel], halved.
func _parts(number: int) -> Array:
	if not _sources.has(number):
		_sources[number] = [
			_halve("%s/Border/panel-border-%03d.png" % [SOURCE, number]),
			_halve("%s/Panel/panel-%03d.png" % [SOURCE, number]),
		]
	return _sources[number]


func _halve(path: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	assert(image != null, "missing %s" % path)
	image.convert(Image.FORMAT_RGBA8)
	var size := image.get_size()
	for y in range(0, size.y, 2):
		for x in range(0, size.x, 2):
			var c := image.get_pixel(x, y)
			assert(c == image.get_pixel(x + 1, y) and c == image.get_pixel(x, y + 1)
					and c == image.get_pixel(x + 1, y + 1),
					"%s is not drawn in 2x2 blocks at %d,%d" % [path, x, y])
	image.resize(size.x / 2, size.y / 2, Image.INTERPOLATE_NEAREST)
	return image
