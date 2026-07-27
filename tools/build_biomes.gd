extends SceneTree
## Builds a TileSet + BiomeKit for every placeholder biome atlas.
##
##     "$GODOT" --headless --path . --script res://tools/build_biomes.gd
##
## Run after tools/gen_placeholder_art.py. Safe to re-run: it only regenerates
## derived resources, never scenes.

const TILE := 16
const SOURCE_ID := 0

const TILESET_DIR := "res://resources/tilesets"
const BIOME_DIR := "res://resources/biomes"

# Semantic atlas slots -- see tools/gen_placeholder_art.py.
const SOLID_TILES := [4, 5, 6, 7]  # liquid, obstacle, wall, wall-alt

# --- the wall blob ---------------------------------------------------------
#
# Rows 1+ of each atlas hold 47 wall tiles, one per legal arrangement of wall
# neighbours. The bit layout and the enumeration order mirror
# tools/gen_placeholder_art.py: both files derive the list from the same rule
# rather than sharing a table, so neither can drift into a silent mis-pairing of
# art and peering bits.
const BIT_N := 1
const BIT_E := 2
const BIT_S := 4
const BIT_W := 8
const BIT_NE := 16
const BIT_SE := 32
const BIT_SW := 64
const BIT_NW := 128

## corner bit, and the two sides that must be wall for it to mean anything.
const CORNERS := [
	[BIT_NE, BIT_N, BIT_E], [BIT_SE, BIT_S, BIT_E],
	[BIT_SW, BIT_S, BIT_W], [BIT_NW, BIT_N, BIT_W],
]

## Which peering bit each neighbour bit drives.
const NEIGHBOR_BITS := {
	BIT_N: TileSet.CELL_NEIGHBOR_TOP_SIDE,
	BIT_E: TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	BIT_S: TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
	BIT_W: TileSet.CELL_NEIGHBOR_LEFT_SIDE,
	BIT_NE: TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
	BIT_SE: TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	BIT_SW: TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	BIT_NW: TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
}

const BLOB_ROW := 1
const BLOB_COLUMNS := 8
const WALL_TERRAIN_SET := 0
const WALL_TERRAIN := 0

## Ambient tints give each band a mood without per-biome lighting work.
const BIOMES := {
	"meadow": {"name": "Green Meadow", "tint": Color(1.0, 1.0, 1.0)},
	"forest": {"name": "Deep Forest", "tint": Color(0.92, 0.98, 0.92)},
	"cave": {"name": "Winding Caves", "tint": Color(0.82, 0.84, 0.94)},
	"ruins": {"name": "Broken Ruins", "tint": Color(1.0, 0.98, 0.92)},
	"swamp": {"name": "Fetid Swamp", "tint": Color(0.9, 0.96, 0.86)},
	"desert": {"name": "Scorched Waste", "tint": Color(1.0, 0.97, 0.88)},
	"ice": {"name": "Frozen Reach", "tint": Color(0.92, 0.97, 1.0)},
	"volcanic": {"name": "Molten Depths", "tint": Color(1.0, 0.9, 0.86)},
	"sky": {"name": "Cloud Gardens", "tint": Color(0.97, 0.99, 1.0)},
	"castle": {"name": "Ruby Palace", "tint": Color(1.0, 0.94, 0.97)},
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(TILESET_DIR)
	DirAccess.make_dir_recursive_absolute(BIOME_DIR)
	for id in BIOMES:
		_build(id, BIOMES[id])
	quit()


func _build(id: String, info: Dictionary) -> void:
	var texture_path := "res://assets/placeholder/tiles_%s.png" % id
	if not ResourceLoader.exists(texture_path):
		push_error("missing atlas %s -- run tools/gen_placeholder_art.py" % texture_path)
		return

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)  # "world"

	var source := TileSetAtlasSource.new()
	source.texture = load(texture_path)
	source.texture_region_size = Vector2i(TILE, TILE)
	# Must be attached before tiles are created, or the tiles get no physics
	# layers and every collision polygon call fails.
	tile_set.add_source(source, SOURCE_ID)
	for column in 8:
		source.create_tile(Vector2i(column, 0))

	var masks := _blob_masks()
	for index in masks.size():
		source.create_tile(_blob_coords(index))

	# The terrain set has to exist before any tile can be assigned to it.
	tile_set.add_terrain_set()
	tile_set.set_terrain_set_mode(WALL_TERRAIN_SET, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	tile_set.add_terrain(WALL_TERRAIN_SET)
	tile_set.set_terrain_name(WALL_TERRAIN_SET, WALL_TERRAIN, "wall")
	tile_set.set_terrain_color(WALL_TERRAIN_SET, WALL_TERRAIN, Color(0.86, 0.42, 0.32))

	var half := TILE / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])
	for column in SOLID_TILES:
		_add_collision(source.get_tile_data(Vector2i(column, 0), 0), square)

	for index in masks.size():
		var data := source.get_tile_data(_blob_coords(index), 0)
		_add_collision(data, square)
		data.terrain_set = WALL_TERRAIN_SET
		data.terrain = WALL_TERRAIN
		for bit in NEIGHBOR_BITS:
			data.set_terrain_peering_bit(
					NEIGHBOR_BITS[bit],
					WALL_TERRAIN if masks[index] & bit else -1)

	var tileset_path := "%s/%s.tres" % [TILESET_DIR, id]
	ResourceSaver.save(tile_set, tileset_path)

	var biome := BiomeKit.new()
	biome.id = StringName(id)
	biome.display_name = info["name"]
	biome.tile_set = load(tileset_path)  # from disk, so it links instead of embedding
	biome.ambient_tint = info["tint"]
	biome.wall_terrain_set = WALL_TERRAIN_SET
	biome.wall_terrain = WALL_TERRAIN
	ResourceSaver.save(biome, "%s/%s.tres" % [BIOME_DIR, id])
	print("wrote biome %s (%d blob tiles)" % [id, masks.size()])


func _add_collision(data: TileData, square: PackedVector2Array) -> void:
	data.add_collision_polygon(0)
	data.set_collision_polygon_points(0, 0, square)


## Every legal neighbour arrangement, ascending. Exactly 47 of them: a corner
## only distinguishes anything when both sides beside it are wall, so the other
## 209 combinations can never occur on a map.
func _blob_masks() -> Array[int]:
	var masks: Array[int] = []
	for mask in 256:
		var legal := true
		for corner in CORNERS:
			if mask & corner[0] and not (mask & corner[1] and mask & corner[2]):
				legal = false
				break
		if legal:
			masks.append(mask)
	return masks


func _blob_coords(index: int) -> Vector2i:
	return Vector2i(index % BLOB_COLUMNS, BLOB_ROW + index / BLOB_COLUMNS)
