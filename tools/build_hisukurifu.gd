extends SceneTree
## Hisukurifu, floor 100's boss, drawn: his four bars' figures and their portraits,
## as pixel tables, into assets/hisukurifu/.
##
##   "$GODOT" --headless --path . --script res://tools/build_hisukurifu.gd
##   ... -- --preview <dir>   also writes every sheet and face 8x into <dir>
##
## He is the game's developer, drawn as himself, and on purpose not quite in the
## pack's hand -- taller than anyone in Aincrad, drawn finer, "something out of the
## world": medium-long blonde hair, pale skin, green-blue eyes, a short ordered
## beard, fit. Four shapes, one a bar ([BossPhase]): the Game Master in a white and
## gold robe lined in violet, his staff's orb lit; a white gi and a black belt; the
## man himself in a hoodie (a crimson witch's hat on it -- Megumin's) and
## headphones; and that last one again as a program that has stopped responding.
##
## A table is one letter a pixel, '.' empty. What the code adds is the pack's
## construction: a one-pixel ink line round every shape (any empty pixel touching
## a filled one -- so a '.' left inside a figure draws a line there), and on every
## [constant SHADED] material a lit first and a shaded last pixel along each run
## across. A capital is a material's shade, drawn as written. Idle frames are
## derived, not drawn: he breathes (everything above [code]waist[/code] dips a
## pixel), the orb pulses, the broken one glitches.
##
## Sheets are frames side by side, as [member EnemyType.idle_frames] reads them.
## Re-import after running (the PNGs are new files the first time).

const OUT := "res://assets/hisukurifu"
const INK := "141b1b"

## Materials whose runs are lit on the left and shaded on the right.
const SHADED := "hswgtvnjkr"

const PALETTE := {
	"o": INK,
	# him
	"h": "f2d27a", "H": "c99a42", "y": "fff4c4", "B": "b98a3c",
	"s": "f7e0d2", "S": "dfb9a6", "m": "c08478", "e": "36b7aa", "E": "1d7a72",
	# the Game Master
	"w": "f4f2ec", "W": "c6c3d8", "g": "e8c25a", "G": "b08a2a",
	"v": "5a3184", "V": "3a1d5c", "t": "d6ae4e", "P": "a58cf2", "p": "f6efff",
	"u": "45286a",
	# the gi
	"k": "2a2a32", "K": "15151a", "f": "f7e0d2",
	# the hoodie
	"n": "34405e", "N": "222a40", "j": "41608e", "J": "2c4366", "r": "c8323c",
	"R": "8a1e28", "a": "e6e6ea", "c": "5ad1e6",
}

const WIZARD := [
	"..PP.............hhhh.........",
	".PpPP..........hhhhhhhh.......",
	".PPPP.........hhhhhhhhhh......",
	"g.PP.g.......hhhhhhhhhyhh.....",
	".gggg........hhhyhhhhhhhh.....",
	"..tt.........hhhhhhsssshh.....",
	"..tt.........hhsHHssHHshh.....",
	"..tt.........hhssossosshh.....",
	"..tt.........hhssessesshh.....",
	"..tt.........hhssssSssshh.....",
	"..tt.......gvhhBssssssBhhvg...",
	"..tt.......gvhhBBsmmsBBhhvg...",
	"..tt.......gvhh.BBBBBB.hhvg...",
	"..tt......ggvhh..SSSS..hhvgg..",
	"..tt......gwwwwvvSSSSvvwwwwg..",
	"..tt.....wwwwwwwvvSSvvwwwwwww.",
	"..tt....wwwwwwwwwgvvgwwwwwwwww",
	"..tt...wwwwwwwwwwwggwwwwwwwwww",
	"..tt..wwwwW.wwwwwwggwwwwww.www",
	"..tt.wwwwW..wwwwwwggwwwwww.wwW",
	"..ttwwwwW...wwwwwwggwwwwww.wwW",
	"..tvvwwW....wwwwwwggwwwwww.wwW",
	".sttsvv.....wwwwwwggwwwwww.wwW",
	".sttsv......wwwwwwggwwwwww.vvv",
	"..tt........wwwwwwggwwwwww.vvv",
	"..tt........ggggggGGgggggg.ss.",
	"..tt........ggggggGGgggggg.ss.",
	"..tt........wwwwwwggwwwwww.Pp.",
	"..tt.......wwwwwwwggwwwwwww.P.",
	"..tt.......wwwwwwwggwwwwwww...",
	"..tt.......wwwwwwwggwwwwwww...",
	"..tt.......wwwwwwwggwwwwwww...",
	"..tt.......wwwwwwwggwwwwwww...",
	"..tt......wwwwwwwvggvwwwwwww..",
	"..tt......wwwwwwwvggvwwwwwww..",
	"..tt......wwwwwwwvggvwwwwwww..",
	"..tt.....wwwwwwwvvggvvwwwwwww.",
	"..tt.....wwwwwwwvvggvvwwwwwww.",
	"..tt.....wwwwwwvvvggvvvwwwwww.",
	"..tt....wwwwwwwvvvggvvvwwwwwww",
	"..tt....wwwwwwvvvvggvvvvwwwwww",
	"..tt....gggggggggggggggggggggg",
	"..tt..........uuuu..uuuu......",
	"..tt..........uuuu..uuuu......",
]


const KARATEKA := [
	".................hhhh.........",
	"...............hhhhhhhh.......",
	"..............hhhhhhhhhh......",
	".............hhhhhhhhhyhh.....",
	".............hhhyhhhhhhhh.....",
	".............hhhhhhsssshh.....",
	".............hhsHHssHHshh.....",
	".............hhssossosshh.....",
	".............hhssessesshh.....",
	".............hhssssSssshh.fff.",
	".............hhBssssssBhh.ffff",
	".............hhBBsmmsBBhh.ffff",
	".............hh.BBBBBB.hh.ffff",
	".............hh..SSSS..hh..www",
	"..........wwwwwwsSSSswwwww.www",
	"......wwwwwwwwwwWsSsWwwwww.www",
	"......wwwwwwwwwwwWSWwwwwww.www",
	"......wwwwwwwwwwwwWwwwwwww.www",
	"......wwwwwwwwwwwwwWwwwwww.www",
	"......wwww.wwwwwwwwWwwwwww.www",
	"......wwww.wwwwwwwwwWwwwww.www",
	"......wwww.wwwwwwwwwwWwwww.WWW",
	"......wwww.wwwwwwwwwwwwWww....",
	"......WWWW.wwwwwwwwwwwwwWw....",
	"......ffff.kkkkkkkkkkkkkkk....",
	"......ffff.kkkkkKKKKKkkkkk....",
	"......ffff.wwwwwkkkkkwwwww....",
	"...........wwwwkk.kkwwwwww....",
	"...........wwwkk...kkwwwww....",
	"...........WWWkk...kkWWWWW....",
	"..........wwwwkk....kkwwwww...",
	"..........wwwwwk....kwwwwww...",
	".........wwwwwww....wwwwwww...",
	".........wwwwwww....wwwwwww...",
	"........wwwwwww......wwwwwww..",
	"........wwwwwww......wwwwwww..",
	".......wwwwwww........wwwwwww.",
	".......wwwwwww........wwwwwww.",
	".......wwwwwww........wwwwwww.",
	"......wwwwwww..........wwwwwww",
	"......wwwwwww..........wwwwwww",
	"......WWWWWWW..........WWWWWWW",
	".......fffff............fffff.",
	"......ffffff...........ffffff.",
]

const DEVELOPER := [
	".................kkkk.........",
	"...............kkhhhhkk.......",
	"..............khhhhhhhhk......",
	".............khhhhhhhhyhk.....",
	".............khhyhhhhhhhk.....",
	"............kkhhhhhsssshkk....",
	"............kchsHHssHHshck....",
	"............kchssossosshck....",
	"............kchssessesshck....",
	".............khssssSssshk.....",
	".............hhBssssssBhh.....",
	".............hhBBsmmsBBhh.....",
	".............hh.BBBBBB.hh.....",
	"..........nnnnnnNSSSSNnnnnnn..",
	".........nnnnnnnnNNNNnnnnnnnn.",
	"........nnnnnnnnanNNnannnnnnnn",
	"........nnnnnnnnannnnannnnnnnn",
	"........nnnNnnnaaaaakkannnNnnn",
	"........nnnNnnnaaaakkaannnNnnn",
	"........nnnNnnnaaakkkaannnNnnn",
	"........nnnNnnnaakkkkaannnNnnn",
	"........nnnNnnnarrrrrrannnNnnn",
	"........nnnNnnnkkkkkkkknnnNnnn",
	"........nnnNnnnnnnnnnnnnnnNnnn",
	"........nnnNnNNNNNNNNNNNNnNnnn",
	"........nnnNnNnnnnnnnnnnNnNnnn",
	"........nnnNnNnnnnnnnnnnNnNnnn",
	"........NNNNnNnnnnnnnnnnNnNNNN",
	"...........nNNNNNNNNNNNNNNn...",
	"...........NNNNNNNNNNNNNNNN...",
	"............jjjjjjjjjjjjjj....",
	"............jjjjjj..jjjjjj....",
	"............jjjjjj..jjjjjj....",
	"............jjjjjj..jjjjjj....",
	"............jjjjjj..jjjjjj....",
	"............jjjjjj..jjjjjj....",
	"............jjjjjj..jjjjjj....",
	"............jjjjjj..jjjjjj....",
	"............jjjjjj..jjjjjj....",
	"............jjjjjj..jjjjjj....",
	"............jjjjjj..jjjjjj....",
	"............JJJJJJ..JJJJJJ....",
	"...........aaaaaaa..aaaaaaa...",
	"...........kkkkkkk..kkkkkkk...",
]


## His portrait, a 38 px faceset like the pack's, as its left half: mirrored, on
## the pack's dark ground ('.').
const FACE := [
	"...................",
	"...................",
	"...........hhhhhhhh",
	"........hhhhhhhhhhh",
	"......hhhhhhhhhhhhh",
	".....hhhhhhhyhhhhhh",
	"....hhhhhhyyhhhhhhh",
	"...hhhhhhhhhhhhhhhh",
	"...hhhhhhhhhhhhhhhh",
	"..hhhhhhhhhhhhhhhhh",
	"..hhhhhhHhhhhhhhhhh",
	"..hhhhhHhhhhhhhhhss",
	"..hhhhhhhhhHhhsssss",
	"..hhhhhhhssssssssss",
	"..hhhhhhsssssssssss",
	"..hhhhhhsHHHHHsssss",
	"..hhhhhssssoooossss",
	"..hhhhhssssaeEassss",
	"..hhhhhssssaEEassss",
	"..hhhhhsssssSSsssss",
	"..hhhhhssssssssssss",
	"..hhhhhBssssssssssS",
	"..hhhhhBsssssssssSS",
	"..hhhhhBssssssBBBBB",
	"..hhhhhBBssssssssmm",
	"..hhhhh.BBssssssBBB",
	"..hhhhh..BBBsssBBBB",
	"..hhhhh...BBBBBBBBB",
	"..hhhhh......BBBBBB",
	"..hhhhh.......SSSSS",
	"..hhhhh.......SSSSS",
	"...hhh........SSSSS",
	"..............SSSSS",
	"..............SSSSS",
	"..............SSSSS",
	"..............SSSSS",
	"..............SSSSS",
	"..............SSSSS",
]

## What each shape wears over [constant FACE], as left halves: ' ' keeps the face.
const FACE_WIZARD := [
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                  P",
	"  gggggggggggggggPp",
	"                 gP",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"gv                 ",
	"gvv                ",
	"gvvw               ",
	"gvwwwwwwwwvv       ",
	"gwwwwwwwwwwvv      ",
	"gwwwwwwwwwwwvv     ",
	"wwwwwwwwwwwwwvv    ",
	"wwwwwwwwwwwwwwgvv  ",
	"wwwwwwwwwwwwwwwgvv ",
	"wwwwwwwwwwwwwwwwgvv",
]

const FACE_GI := [
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"    wwwwwww        ",
	"  wwwwwwwwwWW      ",
	" wwwwwwwwwwwWW     ",
	"wwwwwwwwwwwwwWW    ",
	"wwwwwwwwwwwwwwWW   ",
	"wwwwwwwwwwwwwwwWW  ",
	"wwwwwwwwwwwwwwwwWW ",
]

## The gi's raised fist, beside his jaw -- whole rows, since it is on one side.
const FACE_FIST := [
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                                      ",
	"                             fffff    ",
	"                            fffffff   ",
	"                            fSfSfSf   ",
	"                            fffffff   ",
	"                            ffffffS   ",
	"                             fffffS   ",
	"                             wwwwww   ",
	"                             wwwwww   ",
	"                             wwwwwW   ",
	"                             wwwwwW   ",
	"                             wwwwwW   ",
	"                             wwwwwW   ",
	"                             wwwwwW   ",
	"                             wwwwwW   ",
]

const FACE_DEVELOPER := [
	"                   ",
	"         kkkkkkkkkk",
	"      kkkk         ",
	"    kkk            ",
	"   kk              ",
	"  kk               ",
	" kk                ",
	" k                 ",
	" k                 ",
	"kk                 ",
	"kk                 ",
	"kkk                ",
	"kkkk               ",
	"kcck               ",
	"kcckk              ",
	"kcckk              ",
	"kcckk              ",
	"kcckk              ",
	"kkkkk              ",
	"kkkk               ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"                   ",
	"     nnnn          ",
	"   nnnnnnnNN       ",
	" nnnnnnnnnnNN      ",
	"nnnnnnnnnnnnNNN    ",
	"nnnnnnnnnnnnNNNNNNN",
	"nnnnnnnnnnnnnnannnn",
	"nnnnnnnnnnnnnnannnn",
	"nnnnnnnnnnnnnnannnn",
	"nnnnnnnnnnnnnnannnn",
	"nnnnnnnnnnnnnnnnnnn",
]


## Frames on the broken one's sheet, and how hard each glitches.
const EXE_GLITCH := [1, 2, 1, 3, 0, 2]
## Room either side of him on that sheet, for the rows that slip sideways.
const EXE_PAD := 4
## The tear under his right eye, once he is the broken one: cells of [constant DEVELOPER].
const TEAR := [Vector2i(20, 9), Vector2i(20, 10)]
const FACE_TEAR := [Vector2i(25, 19), Vector2i(25, 20), Vector2i(25, 21)]


func _init() -> void:
	var preview := ""
	var args := OS.get_cmdline_user_args()
	var at := args.find("--preview")
	if at >= 0 and at + 1 < args.size():
		preview = args[at + 1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var broken := _with(DEVELOPER, TEAR, "c")
	var out := {
		"wizard": _frames(WIZARD, 4, 25, {"P": ["a58cf2", "b9a4f6", "d0c2fa", "b9a4f6"]}),
		"karateka": _frames(KARATEKA, 4, 24, {}),
		"developer": _frames(DEVELOPER, 4, 28, {"c": ["5ad1e6", "5ad1e6", "a8eef8", "5ad1e6"]}),
		"exe": _broken(broken),
		"face_wizard": _face([FACE_WIZARD]),
		"face_karateka": _face([FACE_GI, FACE_FIST]),
		"face_developer": _face([FACE_DEVELOPER]),
		"face_exe": _glitched(_face([FACE_DEVELOPER], FACE_TEAR), 2, hash("hisukurifu.exe:portrait")),
	}
	var failed := 0
	for file: String in out:
		var img: Image = out[file]
		if img == null:
			failed += 1
			continue
		failed += _write(img, "%s/%s.png" % [OUT, file], preview)
	print("build_hisukurifu: %d images, %d failed" % [out.size() - failed, failed])
	quit(1 if failed > 0 else 0)


## [param table] with [param cells] repainted as [param key].
func _with(table: Array, cells: Array, key: String) -> Array:
	var rows := table.duplicate()
	for cell: Vector2i in cells:
		var row: String = rows[cell.y]
		rows[cell.y] = row.left(cell.x) + key + row.substr(cell.x + 1)
	return rows


## The broken one's sheet: the developer breathing, crying, and coming apart a
## different way every frame ([constant EXE_GLITCH]).
func _broken(table: Array) -> Image:
	if not _square(table):
		return null
	var w: int = (table[0] as String).length() + 2 + EXE_PAD * 2
	var h := table.size() + 2
	var sheet := Image.create(w * EXE_GLITCH.size(), h, false, Image.FORMAT_RGBA8)
	for i in EXE_GLITCH.size():
		var body := _outlined(_paint(_breathe(table, 28, 1 if i % 3 == 1 else 0), PALETTE))
		var frame := Image.create(w, h, false, Image.FORMAT_RGBA8)
		frame.blit_rect(body, Rect2i(Vector2i.ZERO, body.get_size()), Vector2i(EXE_PAD, 0))
		frame = _glitched(frame, EXE_GLITCH[i], hash("hisukurifu.exe:%d" % i))
		sheet.blit_rect(frame, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
	return sheet


## [param img] as a program that has stopped responding: washed towards white,
## as a hung window is, and at [param strength] above 0 some rows slipped
## sideways, the colour split, and patches of the magenta-and-black checks an
## engine draws for a texture it couldn't load. Seeded, so it is the same glitch
## every build.
func _glitched(img: Image, strength: int, with_seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = with_seed
	var out := img.duplicate() as Image
	var ink := Color(INK)
	var size := out.get_size()
	for y in size.y:
		for x in size.x:
			var pixel := out.get_pixel(x, y)
			if pixel.a > 0.0 and pixel != ink:
				out.set_pixel(x, y, pixel.lerp(Color.WHITE, 0.16))
	if strength <= 0:
		return out
	# What a slipped row leaves behind it: the ground, on a portrait.
	var behind := out.get_pixel(0, 0) if out.get_pixel(0, 0).a > 0.0 else Color(0, 0, 0, 0)
	for _band in strength + 1:
		var top := rng.randi_range(0, size.y - 1)
		var tall := rng.randi_range(1, 4)
		var by := rng.randi_range(1, 3) * (1 if rng.randf() < 0.5 else -1)
		var moved := out.duplicate() as Image
		for y in range(top, mini(top + tall, size.y)):
			for x in size.x:
				var from := x - by
				moved.set_pixel(x, y, out.get_pixel(from, y) if from >= 0 and from < size.x else behind)
		out = moved
	if strength >= 2:
		var split := out.duplicate() as Image
		for y in size.y:
			for x in size.x:
				if out.get_pixel(x, y).a == 0.0 or out.get_pixel(x, y) == ink:
					continue
				for side: Array in [[-1, Color("ff3cc8")], [1, Color("3ce6ff")]]:
					var nx: int = x + side[0]
					if nx >= 0 and nx < size.x and (out.get_pixel(nx, y).a == 0.0 or out.get_pixel(nx, y) == ink):
						split.set_pixel(nx, y, side[1])
		out = split
	for _patch in strength:
		var patch := Vector2i(rng.randi_range(3, 7), rng.randi_range(2, 6))
		var corner := Vector2i(rng.randi_range(0, size.x - patch.x), rng.randi_range(0, size.y - patch.y))
		for y in range(corner.y, corner.y + patch.y):
			for x in range(corner.x, corner.x + patch.x):
				var pixel := out.get_pixel(x, y)
				if pixel.a > 0.0 and pixel != ink:
					out.set_pixel(x, y, Color("ff00ff") if (x / 2 + y / 2) % 2 == 0 else Color("000000"))
	return out


## His portrait, wearing [param overlays] -- left halves mirrored, or whole rows
## -- with [param tear] cells cried in.
func _face(overlays: Array, tear: Array = []) -> Image:
	var rows := _mirrored(FACE)
	for overlay: Array in overlays:
		var full: Array = overlay if (overlay[0] as String).length() == rows[0].length() else _mirrored(overlay)
		for y in rows.size():
			var merged := ""
			for x in (rows[y] as String).length():
				var key: String = full[y][x]
				merged += rows[y][x] if key == " " else key
			rows[y] = merged
	rows = _with(rows, tear, "c")
	if not _square(rows):
		return null
	var face := _paint(rows, PALETTE)
	var ground := Image.create(face.get_width(), face.get_height(), false, Image.FORMAT_RGBA8)
	ground.fill(Color(INK))
	ground.blend_rect(face, Rect2i(Vector2i.ZERO, face.get_size()), Vector2i.ZERO)
	return ground


func _mirrored(half: Array) -> Array:
	var rows := []
	for row: String in half:
		rows.append(row + row.reverse())
	return rows


## [param count] idle frames of [param table] side by side: a breath (rows above
## [param waist] down a pixel in the middle two) and, per frame, any palette
## swaps in [param pulse] (key -> a colour a frame).
func _frames(table: Array, count: int, waist: int, pulse: Dictionary) -> Image:
	if not _square(table):
		return null
	var w: int = (table[0] as String).length() + 2
	var h := table.size() + 2
	var sheet := Image.create(w * count, h, false, Image.FORMAT_RGBA8)
	for i in count:
		var dip := 1 if i == 1 or i == 2 else 0
		var colours := PALETTE.duplicate()
		for key: String in pulse:
			colours[key] = pulse[key][i % (pulse[key] as Array).size()]
		var frame := _outlined(_paint(_breathe(table, waist, dip), colours))
		sheet.blit_rect(frame, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
	return sheet


## Every row the same length, or a table drawn askew without anyone noticing.
func _square(table: Array) -> bool:
	var width := (table[0] as String).length()
	for y in table.size():
		if (table[y] as String).length() != width:
			push_error("build_hisukurifu: row %d is %d wide, not %d" % [y, (table[y] as String).length(), width])
			return false
	return true


func _breathe(table: Array, waist: int, dip: int) -> Array:
	if dip == 0:
		return table
	var rows := table.duplicate()
	for y in range(waist, 0, -1):
		rows[y] = table[y - 1]
	rows[0] = ".".repeat((table[0] as String).length())
	return rows


## A table drawn pixel for pixel, its [constant SHADED] runs lit and shaded.
func _paint(table: Array, colours: Dictionary) -> Image:
	var tw := (table[0] as String).length()
	var th := table.size()
	var img := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	for y in th:
		var row: String = table[y]
		for x in tw:
			var key := row[x]
			if key == ".":
				continue
			var colour := Color(colours[key])
			if key in SHADED:
				var run := _run(row, x)
				var first := x == 0 or row[x - 1] != key
				var last := x == tw - 1 or row[x + 1] != key
				var next_last := x + 2 < tw and row[x + 1] == key and row[x + 2] != key
				if run >= 3 and first:
					colour = colour.lightened(0.22)
				elif run >= 3 and (last or (run >= 6 and next_last)):
					colour = colour.darkened(0.2)
			img.set_pixel(x, y, colour)
	return img


## [param img] on a canvas a pixel bigger all round, with an ink line wherever
## nothing touches something.
func _outlined(img: Image) -> Image:
	var out := Image.create(img.get_width() + 2, img.get_height() + 2, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ONE)
	var ink := Color(INK)
	var lines: Array[Vector2i] = []
	for y in out.get_height():
		for x in out.get_width():
			if out.get_pixel(x, y).a > 0.0:
				continue
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n := Vector2i(x, y) + d
				if Rect2i(Vector2i.ZERO, out.get_size()).has_point(n) and out.get_pixelv(n).a > 0.0:
					lines.append(Vector2i(x, y))
					break
	for cell in lines:
		out.set_pixelv(cell, ink)
	return out


## How long the run of [param row]'s letter at [param x] is.
func _run(row: String, x: int) -> int:
	var key := row[x]
	var from := x
	while from > 0 and row[from - 1] == key:
		from -= 1
	var to := x
	while to < row.length() - 1 and row[to + 1] == key:
		to += 1
	return to - from + 1


func _write(img: Image, path: String, preview: String) -> int:
	if img.save_png(ProjectSettings.globalize_path(path)) != OK:
		push_error("build_hisukurifu: can't write %s" % path)
		return 1
	if not preview.is_empty():
		var big := img.duplicate() as Image
		big.resize(img.get_width() * 8, img.get_height() * 8, Image.INTERPOLATE_NEAREST)
		big.save_png(preview.path_join(path.get_file()))
	return 0
