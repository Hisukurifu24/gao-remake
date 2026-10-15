class_name ShopLibrary
## Every [Shop] in the game, by id. Listed rather than scanned, for the reason
## [ItemLibrary] is: [code]res://[/code] directory listing is unreliable in
## exported builds. The inventory test sweeps every one of these, so a ware that
## names no item, or an item on a shelf with no price, fails there.

const SHOP_PATH := "res://resources/shops/%s.tres"

const SHOPS: PackedStringArray = [
	"town_outfitter", "ashlow_trader", "lanternfall_quartermaster", "travelling_merchant",
]

## Every [Smith]'s forge -- the other kind of counter -- by id.
const SMITH_PATH := "res://resources/smiths/%s.tres"
const SMITHS: PackedStringArray = ["town_forge"]


static func get_smith(id: StringName) -> Smith:
	var path := SMITH_PATH % id
	if not ResourceLoader.exists(path):
		push_error("ShopLibrary: no such forge '%s'" % id)
		return null
	return load(path) as Smith


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
