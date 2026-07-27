class_name BiomeKit
extends Resource
## The art and flavour for a band of floors.
##
## Every biome atlas uses the same semantic slot layout (see
## tools/gen_placeholder_art.py), so the generator paints "floor" or "wall"
## without knowing whether it's a cave or a sky garden. The tile indices are
## exported anyway -- a future hand-drawn biome may want a different atlas order.

@export var id: StringName = &""
@export var display_name := ""
@export var tile_set: TileSet

@export_group("Atlas slots")
@export var floor_tile := 0
@export var floor_alt_tile := 1
@export var path_tile := 2
@export var special_tile := 3
@export var liquid_tile := 4
@export var obstacle_tile := 5
@export var wall_tile := 6
@export var wall_alt_tile := 7

@export_group("Autotiling")
## The terrain set holding the wall blob, or -1 if this biome's TileSet has none.
## Generation paints [member wall_tile] first and only then joins the mass up, so
## a biome without a blob still produces a correct -- if flat -- floor.
@export var wall_terrain_set := -1
@export var wall_terrain := 0

@export_group("Flavour")
## Tinted onto the map root -- cheap mood without per-biome lighting.
@export var ambient_tint := Color.WHITE
@export_multiline var description := ""
