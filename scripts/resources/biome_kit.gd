class_name BiomeKit
extends Resource
## The art and flavour for a band of floors.
##
## Every biome atlas uses the same semantic slot layout (see
## tools/gen_placeholder_art.py), so the generator paints "floor" or "wall"
## without knowing whether it's a cave or a sky garden. The tile indices are
## exported anyway -- a future hand-drawn biome may want a different atlas order.

enum WallStyle {
	## One terrain, autotiled into edges and corners by the wall blob.
	BLOB,
	## Forest: the mass stays plain wall underneath, and [MapDresser] stands a
	## y-sorted canopy of [member tree_tiles] over it.
	TREES,
}

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
## How the wall mass is drawn -- see [MapDresser].
@export var wall_style := WallStyle.BLOB
## The terrain set holding the wall blob, or -1 if this biome's TileSet has none.
## Generation paints [member wall_tile] first and only then joins the mass up, so
## a biome without a blob still produces a correct -- if flat -- floor.
@export var wall_terrain_set := -1
@export var wall_terrain := 0
## Grass and dirt joined into edges and corners, or -1 for a biome whose ground
## stays flat slots. Path and special cells are dirt, the rest grass.
@export var ground_terrain_set := -1
@export var ground_grass := 0
@export var ground_dirt := 1
## Pools joined into a shoreline, or -1 to leave them flat.
@export var liquid_terrain_set := -1
@export var liquid_terrain := 0

@export_group("Dressing")
## 2x2 standing tiles [MapDresser] plants over a TREES wall mass.
@export var tree_tiles: Array[Vector2i] = []
## 1x1 scatter for open grass.
@export var decor_tiles: Array[Vector2i] = []
@export_range(0.0, 1.0) var decor_density := 0.06
## Standing multi-cell buildings for authored maps, placed with
## [method MapDresser.anchor_for].
@export var house_tiles: Array[Vector2i] = []

@export_group("Backdrop")
## Drawn repeating behind the map, where a see-through wall mass shows it -- the
## sky under the sky band's lawns. Null for a biome whose walls are opaque.
@export var backdrop: Texture2D
## How far the backdrop moves as the camera does: under 1 reads as far below.
@export var backdrop_scroll := Vector2(0.5, 0.5)
## Pixels a second the backdrop drifts on its own.
@export var backdrop_drift := Vector2(-4, 0)

@export_group("Flavour")
## Tinted onto the map root -- cheap mood without per-biome lighting.
@export var ambient_tint := Color.WHITE
@export_multiline var description := ""
