extends SceneTree
## Builds the UI's pixel font from the glyph table below.
##
##     "$GODOT" --headless --path . --script res://tools/build_ui_font.gd
##
## Writes [code]ui/theme/pixel_font.tres[/code]. Safe to re-run; it only touches
## that derived resource.
##
## The pack ships two fonts and neither reads at the map's pixel scale.
## [code]NormalFont.ttf[/code] draws its "i" as a stub with the dot knocked
## sideways and has a two-pixel word space, so "Kirito" reads "K.r.to".
## [code]font8x8.png[/code] is legible but two faces in one: capitals and digits
## drawn in two-pixel strokes six tall, lowercase in one-pixel strokes, so every
## capital looks bold against the word it starts, and at 320x180 the whole thing
## is too large for a dialogue box. So the glyphs are drawn here instead, in
## one-pixel strokes to a five-pixel cap height, and the tool only turns the table
## into a [FontFile] -- nothing about a glyph is typed twice.
##
## A glyph is rows separated by "|", starting at the cap line; its width is the
## row length. Lowercase bodies are the bottom four of the five cap rows, and
## descenders continue below. Every row of one glyph must be the same length.

const OUT := "res://ui/theme/pixel_font.tres"

## The glyph cell: one row above the caps for accents, five cap rows, two below.
const HEIGHT := 8
const CAP_TOP := 1
const BASELINE := 6
## One blank column after every glyph.
const TRACKING := 1
const SPACE_ADVANCE := 3

const GLYPHS := {
	"A": ".##.|#..#|####|#..#|#..#",
	"B": "###.|#..#|###.|#..#|###.",
	"C": ".###|#...|#...|#...|.###",
	"D": "###.|#..#|#..#|#..#|###.",
	"E": "####|#...|###.|#...|####",
	"F": "####|#...|###.|#...|#...",
	"G": ".###|#...|#.##|#..#|.###",
	"H": "#..#|#..#|####|#..#|#..#",
	"I": "###|.#.|.#.|.#.|###",
	"J": "..##|...#|...#|#..#|.##.",
	"K": "#..#|#.#.|##..|#.#.|#..#",
	"L": "#...|#...|#...|#...|####",
	"M": "#...#|##.##|#.#.#|#...#|#...#",
	"N": "#..#|##.#|#.##|#..#|#..#",
	"O": ".##.|#..#|#..#|#..#|.##.",
	"P": "###.|#..#|###.|#...|#...",
	"Q": ".##.|#..#|#..#|#.#.|.#.#",
	"R": "###.|#..#|###.|#.#.|#..#",
	"S": ".###|#...|.##.|...#|###.",
	"T": "#####|..#..|..#..|..#..|..#..",
	"U": "#..#|#..#|#..#|#..#|.##.",
	"V": "#...#|#...#|.#.#.|.#.#.|..#..",
	"W": "#...#|#...#|#.#.#|##.##|#...#",
	"X": "#...#|.#.#.|..#..|.#.#.|#...#",
	"Y": "#...#|.#.#.|..#..|..#..|..#..",
	"Z": "####|...#|.##.|#...|####",

	"a": "....|.###|#..#|#..#|.###",
	"b": "#...|###.|#..#|#..#|###.",
	"c": "...|.##|#..|#..|.##",
	"d": "...#|.###|#..#|#..#|.###",
	"e": "....|.##.|####|#...|.##.",
	"f": ".##|#..|###|#..|#..",
	"g": "....|.###|#..#|#..#|.###|...#|.##.",
	"h": "#...|###.|#..#|#..#|#..#",
	"i": "#|.|#|#|#",
	"j": ".#|..|.#|.#|.#|.#|#.",
	"k": "#..|#.#|##.|#.#|#.#",
	"l": "#.|#.|#.|#.|.#",
	"m": ".....|####.|#.#.#|#.#.#|#.#.#",
	"n": "....|###.|#..#|#..#|#..#",
	"o": "....|.##.|#..#|#..#|.##.",
	"p": "....|###.|#..#|#..#|###.|#...|#...",
	"q": "....|.###|#..#|#..#|.###|...#|...#",
	"r": "...|#.#|##.|#..|#..",
	"s": "....|.###|##..|..##|###.",
	"t": "#..|###|#..|#..|.##",
	"u": "....|#..#|#..#|#..#|.###",
	"v": "...|#.#|#.#|#.#|.#.",
	"w": ".....|#...#|#.#.#|#.#.#|.#.#.",
	"x": "...|#.#|.#.|#.#|#.#",
	"y": "....|#..#|#..#|#..#|.###|...#|.##.",
	"z": "....|####|..#.|.#..|####",

	"0": "###|#.#|#.#|#.#|###",
	"1": ".#.|##.|.#.|.#.|###",
	"2": "###|..#|###|#..|###",
	"3": "###|..#|.##|..#|###",
	"4": "#.#|#.#|###|..#|..#",
	"5": "###|#..|###|..#|###",
	"6": "###|#..|###|#.#|###",
	"7": "###|..#|.#.|.#.|.#.",
	"8": "###|#.#|###|#.#|###",
	"9": "###|#.#|###|..#|###",

	".": ".|.|.|.|#",
	",": ".|.|.|.|#|#",
	"!": "#|#|#|.|#",
	"?": "##.|..#|.#.|...|.#.",
	":": ".|#|.|#|.",
	";": "..|.#|..|.#|#.",
	"'": "#|#",
	"\"": "#.#|#.#",
	"`": "#.|.#",
	"-": "...|...|###",
	"+": "...|.#.|###|.#.",
	"=": "...|###|...|###",
	"_": "...|...|...|...|...|###",
	# A star, not an x: the journal marks "tracked" with it beside "done"'s x.
	"*": "..#..|#####|.###.|.#.#.",
	"/": "..#|..#|.#.|#..|#..",
	"\\": "#..|#..|.#.|..#|..#",
	"|": "#|#|#|#|#|#",
	"(": ".#|#.|#.|#.|.#",
	")": "#.|.#|.#|.#|#.",
	"[": "##|#.|#.|#.|##",
	"]": "##|.#|.#|.#|##",
	"{": ".##|.#.|#..|.#.|.##",
	"}": "##.|.#.|..#|.#.|##.",
	"<": "..#|.#.|#..|.#.|..#",
	">": "#..|.#.|..#|.#.|#..",
	"^": ".#.|#.#",
	"~": "....|.#.#|#.#.",
	"#": ".#.#.|#####|.#.#.|#####|.#.#.",
	"%": "#.#|..#|.#.|#..|#.#",
	"&": ".#..|#.#.|.#.#|#.#.|.#.#",
	"@": ".###.|#..##|#.#.#|#..##|.#...",
	"$": ".##|##.|.#.|.##|##.",
}

## Accented letters are a base glyph plus a one-row mark in the accent row, so
## they cannot drift out of step with the letters they decorate.
const MARKS := {
	"acute": "..#",
	"grave": "#..",
	"circumflex": ".#.",
	"diaeresis": "#.#",
}
const ACCENTED := {
	"à": ["a", "grave"], "á": ["a", "acute"], "â": ["a", "circumflex"], "ä": ["a", "diaeresis"],
	"è": ["e", "grave"], "é": ["e", "acute"], "ê": ["e", "circumflex"], "ë": ["e", "diaeresis"],
	"ì": ["i", "grave"], "í": ["i", "acute"], "î": ["i", "circumflex"], "ï": ["i", "diaeresis"],
	"ò": ["o", "grave"], "ó": ["o", "acute"], "ô": ["o", "circumflex"], "ö": ["o", "diaeresis"],
	"ù": ["u", "grave"], "ú": ["u", "acute"], "û": ["u", "circumflex"], "ü": ["u", "diaeresis"],
	"À": ["A", "grave"], "É": ["E", "acute"], "È": ["E", "grave"], "Ä": ["A", "diaeresis"],
	"Ö": ["O", "diaeresis"], "Ü": ["U", "diaeresis"],
}


func _init() -> void:
	var glyphs := {}
	for ch: String in GLYPHS:
		glyphs[ch] = _rows(ch, GLYPHS[ch])
		if glyphs[ch].is_empty():
			quit(1)
			return
	for ch: String in ACCENTED:
		glyphs[ch] = _accent(glyphs[ACCENTED[ch][0]], MARKS[ACCENTED[ch][1]])

	# One strip, each glyph in its own HEIGHT-tall cell with a blank column
	# between cells so nearest sampling never bleeds a neighbour in.
	var width := 0
	for ch: String in glyphs:
		width += (glyphs[ch][0] as String).length() + 1
	var image := Image.create_empty(width, HEIGHT, false, Image.FORMAT_RGBA8)

	var font := FontFile.new()
	font.fixed_size = HEIGHT
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.multichannel_signed_distance_field = false
	# A missing glyph should show as a box and get noticed, not borrow a system
	# font that looks nothing like the rest of the screen.
	font.allow_system_fallback = false

	var size := Vector2i(HEIGHT, 0)
	font.set_cache_ascent(0, HEIGHT, BASELINE)
	font.set_cache_descent(0, HEIGHT, HEIGHT - BASELINE)

	var x := 0
	for ch: String in glyphs:
		var rows: Array = glyphs[ch]
		var w: int = (rows[0] as String).length()
		for y in HEIGHT:
			for i in w:
				if (rows[y] as String)[i] == "#":
					image.set_pixel(x + i, y, Color.WHITE)
		var cp := ch.unicode_at(0)
		font.set_glyph_advance(0, HEIGHT, cp, Vector2(w + TRACKING, 0))
		font.set_glyph_offset(0, size, cp, Vector2(0, -BASELINE))
		font.set_glyph_size(0, size, cp, Vector2(w, HEIGHT))
		font.set_glyph_uv_rect(0, size, cp, Rect2(x, 0, w, HEIGHT))
		font.set_glyph_texture_idx(0, size, cp, 0)
		x += w + 1

	var space := " ".unicode_at(0)
	font.set_glyph_advance(0, HEIGHT, space, Vector2(SPACE_ADVANCE, 0))
	font.set_glyph_size(0, size, space, Vector2.ZERO)
	font.set_glyph_texture_idx(0, size, space, 0)
	font.set_texture_image(0, size, 0, image)

	var err := ResourceSaver.save(font, OUT)
	if err != OK:
		push_error("could not save %s (%s)" % [OUT, error_string(err)])
		quit(1)
		return
	print("pixel font: %d glyphs -> %s" % [glyphs.size() + 1, OUT])
	quit()


## A table entry as HEIGHT rows of equal width, placed from the cap line down.
func _rows(ch: String, spec: String) -> Array:
	var drawn := spec.split("|")
	var w := drawn[0].length()
	if drawn.size() > HEIGHT - CAP_TOP:
		push_error("glyph %s is %d rows; the cell has %d below the accent row"
				% [ch, drawn.size(), HEIGHT - CAP_TOP])
		return []
	var rows := []
	for y in HEIGHT:
		var i := y - CAP_TOP
		var row := drawn[i] if i >= 0 and i < drawn.size() else ".".repeat(w)
		if row.length() != w:
			push_error("glyph %s: row %d is %d wide, row 0 is %d" % [ch, i, row.length(), w])
			return []
		rows.append(row)
	return rows


## [param base] with [param mark] centred in its accent row.
func _accent(base: Array, mark: String) -> Array:
	var rows := base.duplicate()
	var w := (rows[0] as String).length()
	if w < mark.length():
		# Narrower than the mark ("i"): the mark is the glyph's width, so
		# widen the whole glyph around its stem.
		var pad := mark.length() - w
		var lead := pad / 2
		for y in HEIGHT:
			rows[y] = ".".repeat(lead) + rows[y] + ".".repeat(pad - lead)
		w = mark.length()
		# The i's own dot is replaced by the mark.
		rows[CAP_TOP] = ".".repeat(w)
	var left := (w - mark.length()) / 2
	rows[0] = ".".repeat(left) + mark + ".".repeat(w - mark.length() - left)
	return rows
