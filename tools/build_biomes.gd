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

	var half := TILE / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])
	for column in SOLID_TILES:
		var data := source.get_tile_data(Vector2i(column, 0), 0)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, square)

	var tileset_path := "%s/%s.tres" % [TILESET_DIR, id]
	ResourceSaver.save(tile_set, tileset_path)

	var biome := BiomeKit.new()
	biome.id = StringName(id)
	biome.display_name = info["name"]
	biome.tile_set = load(tileset_path)  # from disk, so it links instead of embedding
	biome.ambient_tint = info["tint"]
	ResourceSaver.save(biome, "%s/%s.tres" % [BIOME_DIR, id])
	print("wrote biome ", id)
