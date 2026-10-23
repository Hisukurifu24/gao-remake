class_name UiPalette
extends RefCounted
## Every colour the screens paint with, in one place.
##
## [code]ui/theme/gao_theme.tres[/code] is the look -- font, frames, buttons, bars --
## and the project applies it to every Control (Project Settings > GUI > Theme).
## [code]ui/theme/glass_theme.tres[/code] is the same look for what is drawn over
## the map. Both are built by [code]tools/build_ui_skin.gd[/code] from the frame
## colours at the bottom of this file. The rest are the colours a screen chooses at
## runtime because they *mean* something (ready, locked, rarity, health). They used
## to be redeclared by each screen, which is how six screens drift into six shades
## of "selected".
##
## Two grounds, two sets, after SAO's own: the menus are white panels written in
## dark ink with an orange cursor, and whatever sits over the map -- the vitals,
## the dialogue box, the battle plates, the quest tracker -- is dark glass written
## in light text, so it reads on snow and on grass alike.

# --- on the menus (light panels) --------------------------------------------
const TEXT := Color("2b3038")
const DIM := Color("66707c")
const LOCKED := Color("a0a8b2")
const HEADER := Color("c25f12")
const SELECTED := Color("1f72b0")
const READY := Color("a36600")
const DONE := Color("3d8526")
const TRACKED := Color("a3428a")
const TARGETED := Color("cc5418")
const GOOD := Color("3d8526")
const BAD := Color("c23a3a")
## Writing on the orange plate under the cursor.
const ON_ACCENT := Color("2a1d10")

# --- on glass (over the map) -------------------------------------------------
const GLASS_TEXT := Color("f2f5f8")
const GLASS_DIM := Color("a8b4c2")
const GLASS_LOCKED := Color("6f7b88")
const GLASS_HEADER := Color("ffad5d")
## Where the cursor is in the combat menu. Blue on purpose: it has to stand off
## GLASS_TEXT at a glance, and amber already means *ready* and orange *targeted*.
const GLASS_SELECTED := Color("9fd8ef")
const GLASS_READY := Color("ffcb4d")
const GLASS_DONE := Color("b9d977")
const GLASS_TARGETED := Color("ff9554")
## Text straight on the map, with no panel under it, and its shadow.
const FIELD := Color("f2f5f8")
const SHADOW := Color("0b0f15")

# --- health ------------------------------------------------------------------
## SAO's cursor colours: green while you're fine, amber when you should think,
## red when you should have thought earlier.
const HP_HEALTHY := Color("74a334")
const HP_HURT := Color("f1a83a")
const HP_CRITICAL := Color("e0394c")
const POISE := Color("79b8ce")
const BAR_TROUGH := Color("151b24")

# --- numbers that pop --------------------------------------------------------
const DAMAGE := Color("ffe18d")
const CRIT := Color("ff9554")
const HEAL := Color("b9d977")
const MISS := Color("abc2bc")

# --- the bag -----------------------------------------------------------------
## Where a dragged stack may land.
const DROP := Color("b9d977")
## Unused slots sit a shade under the lit ones, so the end of the bag reads.
const EMPTY_SLOT := Color(0.86, 0.86, 0.86)

## [method Item.rarity_color] is drawn for dark ground -- a cell's tint, a name on
## glass. On the white panels the same rarities are written a shade darker.
const RARITY_INK: Array[Color] = [
	Color("4a525e"),  # common
	Color("2f8a3c"),  # uncommon
	Color("2a6fc9"),  # rare
	Color("8a4fd0"),  # epic
	Color("c7731a"),  # legendary
]

# --- the map ------------------------------------------------------------------
## The map is a hologram, as SAO draws its own: a dark sheet ([constant MAP_FRAME_FILL])
## with what you have seen lit up on it. Where you have walked is the brightest;
## what you have only glimpsed -- a side passage seen from its junction -- is a
## shade under it, stippled; rock is a dark wash with a bright line where it meets
## the floor; and the floor's whole extent, unexplored, is a deeper wash, so how
## much is left shows without saying what is in it. The symbols borrow SAO's
## cursors -- green is you, red the boss -- and carry their own dark outlines
## (see [MapGlyph]).
const MAP_UNSEEN := Color("172433")
const MAP_GRID := Color("34506b")
const MAP_FLOOR := Color("cfe8f5")
const MAP_GLIMPSED := Color("7ea6bf")
const MAP_WALL := Color("263a4f")
const MAP_EDGE := Color("8fd3f0")
const MAP_WATER := Color("3d7db5")
const MAP_YOU := Color("74c043")
const MAP_DOOR := Color("e0394c")
const MAP_EXIT := Color("43c6d6")
const MAP_CHEST := Color("ffcb4d")
## A gilded chest, red as it is drawn on the floor -- a shade off the door.
const MAP_GILDED := Color("d25a3c")
const MAP_PERSON := Color("f2f6fa")
const MAP_QUEST := Color("ffcb4d")
const MAP_CAMP := Color("f08a3c")
## Something to work out -- a wisp waiting, unlit braziers, a dark altar, a sealed
## door -- and the sealed chest it pays out in, blue as it is drawn.
const MAP_PUZZLE := Color("c08ee8")
const MAP_SEALED := Color("5aa9e6")
## The purse you dropped: coin gold, paler than a chest.
const MAP_COL := Color("ffe18d")
const MAP_OUTLINE := Color("0b111a")
## Names of places and the header, and the halo a name wears where it crosses rock.
const MAP_LABEL := Color("e6f3fa")
const MAP_DIM := Color("8fb0c4")
const MAP_HALO := Color("0b111a")

# --- frames --------------------------------------------------------------------
## What [code]tools/build_ui_skin.gd[/code] paints the frames with: each is a line
## and a fill, with a one-pixel gap between them where the ground shows through.
## Change one, re-run the tool.
const WINDOW_LINE := Color("f6f8fa")
const WINDOW_FILL := Color(0.91, 0.925, 0.94, 0.96)
const INSET_LINE := Color("b3bdc8")
const INSET_FILL := Color("fbfcfd")
const TAB_FILL := Color("d5dce3")
## The cursor: SAO's orange.
const ACCENT_LINE := Color("d97b1c")
const ACCENT_FILL := Color("f4a043")
## The card under the cursor: the inset, lit.
const LIT_FILL := Color("fff3e3")
const LOCKED_LINE := Color("c8cfd6")
const LOCKED_FILL := Color("e4e8ec")
const BADGE_FILL := Color("c23a3a")
const GLASS_LINE := Color(0.88, 0.91, 0.94, 0.9)
const GLASS_FILL := Color(0.06, 0.08, 0.11, 0.84)
const MAP_FRAME_LINE := Color(0.56, 0.83, 0.94, 0.9)
const MAP_FRAME_FILL := Color(0.05, 0.08, 0.12, 0.97)


static func hp_color(ratio: float) -> Color:
	if ratio > 0.5:
		return HP_HEALTHY
	return HP_HURT if ratio > 0.2 else HP_CRITICAL


## An item's rarity ([member Item.rarity]), written on a white panel. Takes the
## number, not the item, so the skin tool can name this class without compiling
## the item model.
static func rarity_ink(rarity: int) -> Color:
	return RARITY_INK[clampi(rarity, 0, RARITY_INK.size() - 1)]


## Recolours a [ProgressBar]'s fill, keeping the theme's outlined shape: SAO's
## health is a traffic light, so the fill is drawn here as a 1px dark outline round
## a flat colour.
static func paint_bar(bar: ProgressBar, color: Color) -> void:
	var fill := bar.get_theme_stylebox(&"fill").duplicate() as StyleBoxFlat
	if fill == null:
		return
	fill.bg_color = color
	bar.add_theme_stylebox_override(&"fill", fill)
