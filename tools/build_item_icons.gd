extends SceneTree
## The bag's icons: one 16x16 PNG per item in assets/icons/items/, cut from the
## Ninja Adventure pack where it draws the thing and drawn here where it doesn't.
##
##   "$GODOT" --headless --path . --script res://tools/build_item_icons.gd
##
## Every icon is padded onto the same 16x16 canvas, centred, so every screen that
## draws one -- the bag, a shop row, the battle menu -- draws it at its own size.
## The pack's sprites are anything from 6x17 to 9x11, and a TextureRect that
## fits a 9x11 potion to a 16x16 box scales it by 1.45: no pixel the same size as
## its neighbour.
##
## The pack has no armour, rings or lanterns in its item set, so those four are
## pixel tables below, drawn in the pack's construction -- a one-pixel ink outline,
## a lit edge and a shaded one. Adding an item: a row in [constant ICONS] (a pack
## path, or a table and palette in [constant DRAWN]), then run this and point the
## item's .tres at the PNG. The inventory test refuses an icon that isn't here.

const OUT := "res://assets/icons/items"
const PACK := "res://assets/ninja_adventure/Items/"
const SIZE := 16

## Item id -> the pack sprite it is drawn as, or "" for one of [constant DRAWN].
const ICONS := {
	&"bronze_sword": "Weapons/Sword2/Sprite.png",
	&"kobold_blade": "Weapons/Katana/Sprite.png",
	&"anneal_blade": "Weapons/BigSword/Sprite.png",
	&"heartwood_blade": "Weapons/Sword2/Sprite.png",
	&"deepiron_blade": "Weapons/Rapier/Sprite.png",
	&"leather_coat": "",
	&"blackwyrm_coat": "",
	&"guard_ring": "",
	&"swift_charm": "Resource/feather.png",
	&"small_potion": "Potion/WaterPot.png",
	&"health_potion": "Potion/LifePot.png",
	&"antidote": "Potion/Medipack.png",
	&"whetstone": "Resource/BarIron.png",
	&"boar_hide": "Food/Beaf.png",
	&"wolf_fang": "Food/SeedLargeWhite.png",
	&"kobold_fang": "Food/SeedLarge.png",
	&"bat_wing": "Food/TeaLeaf.png",
	&"nepent_ovule": "Food/SeedBig1.png",
	&"lizard_scale": "Resource/GemGreen.png",
	&"drake_scale": "Resource/GemRed.png",
	&"golem_core": "Resource/Rock.png",
	&"spirit_ash": "Resource/GemPurple.png",
	&"map_floor_2": "Scroll/Scroll.png",
	&"raid_tag": "Other/Stamp.png",
	&"warden_seal": "Other/Letter3.png",
	&"foremans_lantern": "",
}

## Item id -> a colour the sprite's pale, unsaturated pixels -- a blade's steel --
## are multiplied by, for a piece drawn as another's sprite in another metal.
const TINTS := {
	&"heartwood_blade": Color(0.62, 0.95, 0.5),
}

const INK := "141b1b"

## A coat from the front, drawn as its left half and mirrored: o ink, c lit, a
## cloth, b shade, d the opening down the middle, e the belt.
const COAT_HALF := [
	"........",
	"....oooo",
	"..oocaad",
	".ocaaaad",
	"ocaaaaad",
	"ocaoaaad",
	"ocaoaaad",
	"ocaoaaad",
	"ocaoeeee",
	"obaobaad",
	"obaobaad",
	"oooobaad",
	"...obaad",
	"...obbbd",
	"...ooooo",
	"........",
]

const RING := [
	"................",
	"................",
	"................",
	"......oooo......",
	"....oocaaaoo....",
	"...ocaoooobao...",
	"..ocao....obao..",
	"..oao......obo..",
	"..oao......obo..",
	"..oabo....obbo..",
	"...obboooobbo...",
	"....oobbbboo....",
	"......oooo......",
	"................",
	"................",
	"................",
]

const LANTERN := [
	"................",
	"......oooo......",
	".....o....o.....",
	"....oooooooo....",
	"...ommmmmmmmo...",
	"....oddddddo....",
	"....oylllyyo....",
	"....oyllfyyo....",
	"....oylffyyo....",
	"....oyyffyyo....",
	"....oyyyyyyo....",
	"....oddddddo....",
	"...ommmmmmmmo...",
	"....oooooooo....",
	"................",
	"................",
]

## Item id -> [table, palette]. A table is 16 rows of 16 (or, mirrored, 8).
var DRAWN := {
	&"leather_coat": [_mirror(COAT_HALF),
			{"c": "c8895a", "a": "a0673f", "b": "7a4a2c", "d": "4e2e1c", "e": "d8b26a"}],
	&"blackwyrm_coat": [_mirror(COAT_HALF),
			{"c": "6b7486", "a": "454c5c", "b": "2e3340", "d": "1b1f26", "e": "a33c3c"}],
	&"guard_ring": [RING, {"c": "ffffff", "a": "c9d4d8", "b": "7d8c94"}],
	&"foremans_lantern": [LANTERN,
			{"m": "c9944c", "d": "7a4f2e", "y": "ffd27a", "l": "fff4c8", "f": "f08a3c"}],
}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var failed := 0
	for id: StringName in ICONS:
		var icon := _icon(id)
		if icon == null:
			failed += 1
			continue
		var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT, id])
		if icon.save_png(path) != OK:
			push_error("build_item_icons: can't write %s" % path)
			failed += 1
	print("build_item_icons: %d icons, %d failed" % [ICONS.size() - failed, failed])
	quit(1 if failed > 0 else 0)


func _icon(id: StringName) -> Image:
	var canvas := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var source := String(ICONS[id])
	if source.is_empty():
		var drawn: Array = DRAWN[id]
		_paint(canvas, drawn[0], drawn[1])
		return canvas
	var sprite := Image.load_from_file(ProjectSettings.globalize_path(PACK + source))
	if sprite == null:
		push_error("build_item_icons: %s has no sprite at %s" % [id, source])
		return null
	sprite.convert(Image.FORMAT_RGBA8)
	var used := sprite.get_used_rect()
	if used.size.x > SIZE or used.size.y > SIZE:
		push_error("build_item_icons: %s is %s, bigger than a tile" % [source, used.size])
		return null
	# Centred, rounding down: an odd margin goes to the right and the bottom.
	var at := (Vector2i(SIZE, SIZE) - used.size) / 2
	canvas.blit_rect(sprite, used, at)
	if TINTS.has(id):
		_tint(canvas, TINTS[id])
	return canvas


func _tint(canvas: Image, by: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			var pixel := canvas.get_pixel(x, y)
			if pixel.a > 0.0 and pixel.s < 0.2 and pixel.v > 0.45:
				canvas.set_pixel(x, y, Color(pixel.r * by.r, pixel.g * by.g, pixel.b * by.b, pixel.a))


func _paint(canvas: Image, table: Array, palette: Dictionary) -> void:
	for y in table.size():
		var row: String = table[y]
		for x in row.length():
			var key := row[x]
			if key == ".":
				continue
			canvas.set_pixel(x, y, Color(INK if key == "o" else palette[key]))


func _mirror(half: Array) -> Array:
	var rows := []
	for row: String in half:
		var back := ""
		for i in range(row.length() - 1, -1, -1):
			back += row[i]
		rows.append(row + back)
	return rows
