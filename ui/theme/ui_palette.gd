class_name UiPalette
extends RefCounted
## Every colour the screens paint with, in one place, picked for the pack's panels.
##
## [code]ui/theme/gao_theme.tres[/code] is the look -- font, frames, buttons, bars --
## and the project applies it to every Control (Project Settings > GUI > Theme).
## This is the other half: the colours a screen chooses at runtime because they
## *mean* something (ready, locked, rarity, health). They used to be redeclared by
## each screen, which is how six screens drift into six shades of "selected".
##
## Two grounds, two sets. The wood and metal panels have a dark sage centre, so
## text on them is light. The dialogue box is the pack's paper, so its text is ink.

# --- on the dark panels -----------------------------------------------------
const TEXT := Color("f2eaf1")
const DIM := Color("abc2bc")
const LOCKED := Color("8f9a88")
const HEADER := Color("ffad5d")
## Where the cursor is in the combat menu. Blue on purpose: it has to stand off
## TEXT at a glance, and amber already means *ready* and orange *targeted*.
const SELECTED := Color("9fd8ef")
const READY := Color("ffcb4d")
const DONE := Color("b9d977")
const TRACKED := Color("e3b4d2")
const TARGETED := Color("ff9554")
const GOOD := Color("b9d977")
const BAD := Color("ef9597")

# --- on paper ---------------------------------------------------------------
const INK := Color("141b1b")
const INK_SELECTED := Color("d14b34")
const INK_LOCKED := Color("9c8a80")

# --- health ------------------------------------------------------------------
## SAO's cursor colours: green while you're fine, amber when you should think,
## red when you should have thought earlier.
const HP_HEALTHY := Color("74a334")
const HP_HURT := Color("f1a83a")
const HP_CRITICAL := Color("e0394c")
const POISE := Color("79b8ce")

# --- numbers that pop --------------------------------------------------------
const DAMAGE := Color("ffe18d")
const CRIT := Color("ff9554")
const HEAL := Color("b9d977")
const MISS := Color("abc2bc")

# --- the bag -----------------------------------------------------------------
## Where a dragged stack may land.
const DROP := Color("b9d977")
## Unused slots sit a shade under the lit ones, so the end of the bag reads.
const EMPTY_SLOT := Color(0.72, 0.72, 0.72)

# --- the map ------------------------------------------------------------------
## The map is drawn in ink on the pack's paper, tinted to parchment
## ([constant MAP_SHEET]). Where you have walked is the paper at its brightest;
## what you have only glimpsed -- a side passage seen from its junction -- is a
## shade under it, stippled; rock is a brown wash with an ink line where it meets the floor;
## and the floor's whole extent, unexplored, is a darker wash, so how much is left
## shows without saying what is in it. The symbols borrow SAO's cursors -- green is
## you, red the boss -- and carry their own ink outlines (see [MapGlyph]).
const MAP_SHEET := Color(1.0, 0.93, 0.8)
const MAP_UNSEEN := Color("d8bf9f")
const MAP_GRID := Color("c4a888")
const MAP_FLOOR := Color("fff8ea")
const MAP_GLIMPSED := Color("f3e3c6")
const MAP_WALL := Color("a88063")
const MAP_EDGE := Color("5b3b2c")
const MAP_WATER := Color("7fb0cf")
const MAP_YOU := Color("74a334")
const MAP_DOOR := Color("e0394c")
const MAP_EXIT := Color("9fd8ef")
const MAP_CHEST := Color("ffcb4d")
const MAP_PERSON := Color("f2eaf1")
const MAP_QUEST := Color("ffcb4d")
const MAP_OUTLINE := Color("141b1b")


static func hp_color(ratio: float) -> Color:
	if ratio > 0.5:
		return HP_HEALTHY
	return HP_HURT if ratio > 0.2 else HP_CRITICAL


## Recolours a [ProgressBar]'s fill, keeping the theme's outlined shape. The
## pack's bar is red only; SAO's health is a traffic light, so the fill is drawn
## here in the pack's own construction (a 1px ink outline round a flat colour).
static func paint_bar(bar: ProgressBar, color: Color) -> void:
	var fill := bar.get_theme_stylebox(&"fill").duplicate() as StyleBoxFlat
	if fill == null:
		return
	fill.bg_color = color
	bar.add_theme_stylebox_override(&"fill", fill)
