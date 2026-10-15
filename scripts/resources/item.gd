class_name Item
extends Resource
## One kind of thing the player can carry: a potion, a sword, a boar hide.
##
## Items are pure data, like [Skill] and [StatusEffect]. [Inventory] knows how to
## hold them, [CombatManager] knows how to drink one, and the equipment screen
## knows how to wear one -- none of them know what any *particular* item is, so
## adding a sword is a .tres plus a line in [ItemLibrary].
##
## Two rules the numbers here follow, both borrowed from [StatusEffect]:
## [member heal_percent] is a percentage of the drinker's max HP rather than
## flat points, because a flat 20-point potion is everything on floor 2 and
## nothing on floor 90; and equipment bonuses are flat *additions* to the
## player's base stats, because mitigation is a ratio ([CombatMath]) and a
## multiplier on top of a ratio compounds out of control across 100 floors.

enum Kind {
	CONSUMABLE,  ## Spent on use. See the Consumable group.
	WEAPON,
	ARMOR,
	ACCESSORY,
	MATERIAL,    ## Crafting and quest fodder. Does nothing on its own.
	KEY,         ## Quest items and maps. Never dropped, never sold.
}

## Purely how an item reads: its name colour and its place in a sorted bag.
## Rarity is not a stat -- a Legendary with bad numbers is still bad.
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

## Which [Inventory] slot each wearable kind occupies. Kinds absent from this
## table cannot be equipped, which is the whole test -- see [method slot].
const EQUIP_SLOTS := {
	Kind.WEAPON: &"weapon",
	Kind.ARMOR: &"armor",
	Kind.ACCESSORY: &"accessory",
}

const RARITY_COLORS: Array[Color] = [
	Color(0.78, 0.80, 0.86),  # common
	Color(0.52, 0.84, 0.56),  # uncommon
	Color(0.44, 0.70, 0.98),  # rare
	Color(0.76, 0.56, 0.96),  # epic
	Color(0.98, 0.74, 0.36),  # legendary
]

const RARITY_NAMES: PackedStringArray = [
	"Common", "Uncommon", "Rare", "Epic", "Legendary",
]

## How far the smith can take a piece, by rarity. Starter steel tops out early, a
## boss's blade has room in it -- the reason to keep the Anneal Blade.
const MAX_PLUS: Array[int] = [3, 5, 8, 10, 10]
## The one stat each wearable kind is sharpened in. Not attack everywhere: a coat
## that gets more attack from the smith is a sword with sleeves.
const ENHANCED_STAT := {
	Kind.WEAPON: &"attack",
	Kind.ARMOR: &"defense",
	Kind.ACCESSORY: &"max_hp",
}
## What each +1 adds, as a share of the piece's own bonus in that stat -- so a
## better blade sharpens into more -- and the least it ever adds, so every +1 on
## a cheap piece still shows. Accessories grow HP in bigger steps, since an HP
## point is worth far less than an attack point.
const PLUS_SHARE := 0.1
const PLUS_MIN_STEP := {&"attack": 1, &"defense": 1, &"max_hp": 5}

@export var id: StringName = &""
@export var display_name := ""
@export_multiline var description := ""
## The 16x16 icon drawn in the bag grid.
@export var icon: Texture2D
@export var kind: Kind = Kind.MATERIAL
@export var rarity: Rarity = Rarity.COMMON
## How many fit in one slot. Ignored for equipment, which never stacks --
## see [method stack_limit].
@export_range(1, 999) var max_stack := 99

@export_group("Equipment")
## Added to the player's base stat while worn. May be negative: a heavy shield
## that costs speed is a real trade, and the ratio-based mitigation in
## [CombatMath] keeps it a readable one.
@export var attack_bonus := 0
@export var defense_bonus := 0
@export var speed_bonus := 0
@export var max_hp_bonus := 0

@export_group("Consumable")
## Percent of the *drinker's* max HP restored. Percent, never flat -- a potion
## should still be worth a turn on floor 90.
@export_range(0, 100) var heal_percent := 0
## Applied to whoever drinks it. Buffs work here exactly as they do on a skill.
@export var applies: StatusEffect
## Strips every debuff currently riding on the drinker.
@export var cures_debuffs := false
@export var usable_in_battle := true
@export var usable_in_field := true

@export_group("Trade")
## What a shop charges, in Col. [b]Fixed[/b]: the same on every floor. A potion
## heals a percentage, so it stays worth carrying and simply gets cheap as income
## grows -- the climb shows on the shelf, not on the price tag. 0 is worthless:
## no shop sells it and none will buy it. Selling fetches half (see
## [method sell_price]).
@export var price := 0
## The floor the player must have reached before a shop shelves this -- stock
## climbs with progression, read from [method GameState.highest_floor_reached].
## 0 is never sold, only found: a boss's blade can be sold off but not bought.
@export var shop_floor := 0


func label() -> String:
	return display_name if not display_name.is_empty() else String(id)


func is_equipment() -> bool:
	return EQUIP_SLOTS.has(kind)


# --- enhancement ------------------------------------------------------------
## The smith's +N lives on the [ItemStack] (a copy of the sword, not every sword),
## and reaches combat the way the base bonuses do: [method Inventory.bonus] adds
## [method plus_bonus], [GameState]'s [code]total_*[/code] accessors fold it in.

## How far this can be enhanced; 0 for anything that is not equipment.
func max_plus() -> int:
	return MAX_PLUS[clampi(rarity, 0, MAX_PLUS.size() - 1)] if is_equipment() else 0


## The stat enhancement raises, or [code]&""[/code].
func enhanced_stat() -> StringName:
	return ENHANCED_STAT.get(kind, &"")


## What one +1 adds to [method enhanced_stat].
func plus_step() -> int:
	var stat := enhanced_stat()
	if stat == &"":
		return 0
	return maxi(PLUS_MIN_STEP[stat], roundi(base_bonus(stat) * PLUS_SHARE))


## What [param plus] levels of enhancement add to [param stat].
func plus_bonus(stat: StringName, plus: int) -> int:
	if plus <= 0 or stat != enhanced_stat():
		return 0
	return plus * plus_step()


## The worn bonus to one stat before any enhancement.
func base_bonus(stat: StringName) -> int:
	match stat:
		&"attack": return attack_bonus
		&"defense": return defense_bonus
		&"speed": return speed_bonus
		&"max_hp": return max_hp_bonus
	return 0


## The name with its enhancement: "Anneal Blade +3".
func label_at(plus: int) -> String:
	return label() if plus <= 0 else "%s +%d" % [label(), plus]


## The slot this goes in, or [code]&""[/code] if it is not wearable.
func slot() -> StringName:
	return EQUIP_SLOTS.get(kind, &"")


func is_consumable() -> bool:
	return kind == Kind.CONSUMABLE


## Whether drinking this would actually do anything. A consumable that heals
## nothing, applies nothing and cures nothing is content missing its numbers,
## not a valid item, and [Inventory] refuses to spend one.
func has_effect() -> bool:
	return heal_percent > 0 or applies != null or cures_debuffs


## Equipment never stacks: three swords are three slots, so any one of them can
## be worn without splitting a pile first.
func stack_limit() -> int:
	return 1 if is_equipment() else maxi(1, max_stack)


## Points of HP this restores to something with [param max_hp].
func heal_amount(max_hp: int) -> int:
	if heal_percent <= 0:
		return 0
	return maxi(1, roundi(max_hp * heal_percent / 100.0))


## What a shop pays for one. Half the price, the usual shopkeeper's cut.
func sell_price() -> int:
	return price / 2


## Whether a shop will take it off your hands. Key items are never sold.
func is_sellable() -> bool:
	return kind != Kind.KEY and sell_price() > 0


## Whether it can be on a shelf once its floor is reached.
func is_stocked() -> bool:
	return shop_floor > 0 and price > 0


func rarity_color() -> Color:
	return RARITY_COLORS[clampi(rarity, 0, RARITY_COLORS.size() - 1)]


func rarity_name() -> String:
	return RARITY_NAMES[clampi(rarity, 0, RARITY_NAMES.size() - 1)]


func kind_name() -> String:
	match kind:
		Kind.CONSUMABLE: return "Consumable"
		Kind.WEAPON: return "Weapon"
		Kind.ARMOR: return "Armor"
		Kind.ACCESSORY: return "Accessory"
		Kind.KEY: return "Key Item"
		_: return "Material"


## The stat line shown under an item in the bag: "ATK +6  SPD -1", or the
## potion's effect. Empty for something that does nothing but sit there.
## [param plus] folds a copy's enhancement in.
func summary(plus := 0) -> String:
	var parts := PackedStringArray()
	if is_equipment():
		for pair in [["ATK", &"attack"], ["DEF", &"defense"], ["SPD", &"speed"], ["HP", &"max_hp"]]:
			var amount: int = base_bonus(pair[1]) + plus_bonus(pair[1], plus)
			if amount != 0:
				parts.append("%s %+d" % [pair[0], amount])
	else:
		if heal_percent > 0:
			parts.append("Heals %d%%" % heal_percent)
		if cures_debuffs:
			parts.append("Cures")
		if applies != null:
			parts.append(applies.label())
	return "  ".join(parts)
