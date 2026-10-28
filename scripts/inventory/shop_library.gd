class_name ShopLibrary
## Every [Shop] in the game, by id. Listed rather than scanned, for the reason
## [ItemLibrary] is: [code]res://[/code] directory listing is unreliable in
## exported builds. The inventory test sweeps every one of these, so a ware that
## names no item, or an item on a shelf with no price, fails there.

const SHOP_PATH := "res://resources/shops/%s.tres"

const SHOPS: PackedStringArray = [
	"town_outfitter", "ashlow_trader", "lanternfall_quartermaster", "travelling_merchant",
	"village_meadow", "village_forest", "village_cave", "village_ruins", "village_swamp",
	"village_desert", "village_ice", "village_volcanic", "village_sky", "village_castle",
]
## A settled floor's counter is its band's: [code]village_<biome>[/code]. The first
## wares on it are the band's specialities, sold nowhere else; the rest are staples.
const VILLAGE_FORMAT := "village_%s"
## How many of a village counter's wares, from the front, are its band's own.
const SPECIALITIES := 2

## Every [Smith]'s forge -- the other kind of counter -- by id.
const SMITH_PATH := "res://resources/smiths/%s.tres"
const SMITHS: PackedStringArray = ["town_forge"]


static func get_smith(id: StringName) -> Smith:
	var path := SMITH_PATH % id
	if not ResourceLoader.exists(path):
		push_error("ShopLibrary: no such forge '%s'" % id)
		return null
	return load(path) as Smith


## The counter in a village of [param biome]'s band, or null for a band with none.
static func village_shop(biome: StringName) -> Shop:
	if not (VILLAGE_FORMAT % biome) in SHOPS:
		return null
	return get_shop(StringName(VILLAGE_FORMAT % biome))


static func get_shop(id: StringName) -> Shop:
	var path := SHOP_PATH % id
	if not ResourceLoader.exists(path):
		push_error("ShopLibrary: no such shop '%s'" % id)
		return null
	return load(path) as Shop


static func all() -> Array[Shop]:
	var shops: Array[Shop] = []
	for id in SHOPS:
		var shop := get_shop(StringName(id))
		if shop != null:
			shops.append(shop)
	return shops
