extends Node
## Exercises the M3 inventory against the real item resources.
##
##     "$GODOT" --headless --path . res://test/inventory_test.tscn
##
## Run as a *scene*, not with --script: autoloads are registered after a script
## main loop is compiled, so Inventory & co. wouldn't resolve.
##
## No inventory screen is instantiated here on purpose -- the autoload is driven
## directly. If these pass and the game still looks wrong, the bug is in the
## view, not the bag.
##
## Two things this is really here to catch:
##   * an id in a loot table, a chest or a dialogue effect with no resource
##     behind it, which is silent everywhere else until a player finds it;
##   * equipment failing to reach combat. Gear folds into GameState's total_*
##     accessors and nowhere else, and the fight reads those, so an edit that
##     breaks the chain shows up as a Combatant with the wrong attack.

var _failures: PackedStringArray = PackedStringArray()
var _checks := 0

# Signal spies. Members, not captured locals: GDScript lambdas capture by value.
var _added: Array[StringName] = []
var _added_amounts: Array[int] = []
var _removed: Array[StringName] = []
var _used: Array[StringName] = []
var _equipped: Array[StringName] = []
var _overflowed: Array[StringName] = []
var _col_changes: Array[int] = []
var _drops: Array[int] = []


func _ready() -> void:
	CombatManager.step_delay = 0.0
	EventBus.item_added.connect(func(id: StringName, n: int) -> void:
		_added.append(id)
		_added_amounts.append(n))
	EventBus.item_removed.connect(func(id: StringName, _n: int) -> void: _removed.append(id))
	EventBus.item_used.connect(func(id: StringName) -> void: _used.append(id))
	EventBus.item_equipped.connect(func(_slot: StringName, id: StringName) -> void:
		_equipped.append(id))
	EventBus.inventory_full.connect(func(id: StringName, _n: int) -> void:
		_overflowed.append(id))
	EventBus.col_changed.connect(func(col: int) -> void: _col_changes.append(col))
	EventBus.col_dropped.connect(func(_m: StringName, _p: Vector2, n: int) -> void:
		_drops.append(n))

	await _run()

	print("")
	if _failures.is_empty():
		print("inventory test: %d checks passed" % _checks)
		get_tree().quit(0)
		return
	printerr("inventory test: %d of %d checks FAILED" % [_failures.size(), _checks])
	for failure in _failures:
		printerr("  - ", failure)
	get_tree().quit(1)


func _run() -> void:
	_test_content()
	_test_stacking()
	_test_capacity()
	_test_removal()
	_test_ordering()
	_test_granting()
	_test_consumables()
	_test_equipment()
	await _test_items_in_battle()
	_test_chest()
	_test_purse()
	await _test_dropped_col()
	_test_shops()
	_test_forge()
	_test_economy()


# --- content ---------------------------------------------------------------

func _test_content() -> void:
	print("\n-- content --")
	_check(ItemLibrary.all().size() == ItemLibrary.ITEMS.size(),
			"every listed item loads (%d of %d)" % [
				ItemLibrary.all().size(), ItemLibrary.ITEMS.size()])

	var broken := PackedStringArray()
	for item in ItemLibrary.all():
		if item.id == &"" or item.icon == null or item.display_name.is_empty():
			broken.append(String(item.id))
	_check(broken.is_empty(), "every item has an id, a name and an icon (%s)" % broken)

	# Every screen draws an icon at its own size, so every icon must be a tile:
	# one cut by tools/build_item_icons.gd, padded onto 16x16.
	var odd_icons := PackedStringArray()
	for item in ItemLibrary.all():
		if item.icon == null:
			continue
		if item.icon.get_size() != Vector2(16, 16) \
				or item.icon.resource_path != "res://assets/icons/items/%s.png" % item.id:
			odd_icons.append("%s (%s, %s)" % [item.id, item.icon.get_size(), item.icon.resource_path])
	_check(odd_icons.is_empty(), "every icon is its item's 16x16 tile from build_item_icons (%s)" % odd_icons)

	var mismatched := PackedStringArray()
	for id in ItemLibrary.ITEMS:
		var item := ItemLibrary.get_item(StringName(id))
		if item != null and item.id != StringName(id):
			mismatched.append("%s says %s" % [id, item.id])
	_check(mismatched.is_empty(), "each item's id matches its filename (%s)" % mismatched)

	_check(ItemLibrary.get_item(&"no_such_item") == null, "an unknown id yields null")
	_check(not ItemLibrary.exists(&"no_such_item"), "exists() agrees about an unknown id")

	# The reason this suite exists: every id the rest of the game already emits
	# has to name something, or it lands in an empty bag with no complaint.
	var orphans := PackedStringArray()
	for enemy_id in Bestiary.ENEMIES:
		var type := Bestiary.get_enemy(StringName(enemy_id))
		for loot_id in type.loot:
			if not ItemLibrary.exists(loot_id):
				orphans.append("%s drops %s" % [enemy_id, loot_id])
	_check(orphans.is_empty(), "every enemy's loot names a real item (%s)" % orphans)

	var chest_orphans := PackedStringArray()
	for id in FloorGenerator.CHEST_CONSUMABLES + FloorGenerator.CHEST_GEAR + FloorPuzzles.SEALED_LOOT:
		if not ItemLibrary.exists(id):
			chest_orphans.append(String(id))
	_check(chest_orphans.is_empty(), "every generated-chest item exists (%s)" % chest_orphans)

	# A settled floor's jobs pay from tables of their own (LocalQuests), and its
	# gathering asks for whatever the floor's monsters drop -- the loot above.
	var job_orphans := PackedStringArray()
	var pay: Array[StringName] = LocalQuests.LOST_GEAR.duplicate()
	for entry: Array in LocalQuests.HUNT_ITEMS + LocalQuests.GATHER_ITEMS:
		pay.append(entry[0])
	for id in pay:
		if not ItemLibrary.exists(id):
			job_orphans.append(String(id))
	_check(job_orphans.is_empty(), "every item a settled floor's job pays exists (%s)" % job_orphans)

	# And a floor event's: what a stranded player thanks you with, and a duellist's wager.
	var event_orphans := PackedStringArray()
	for id in FloorEvents.ESCORT_GEAR + FloorEvents.DUEL_WAGERS:
		if not ItemLibrary.exists(id):
			event_orphans.append(String(id))
	_check(event_orphans.is_empty(), "every item a floor event pays exists (%s)" % event_orphans)

	# Authored floors fill their chests from a layout table rather than the pools
	# above, and a typo there is just as silent -- the chest opens onto nothing.
	var authored_orphans := PackedStringArray()
	for floor_number in FloorRegistry.AUTHORED:
		authored_orphans.append_array(_authored_chest_orphans(floor_number))
	_check(authored_orphans.is_empty(), "every authored-floor chest item exists (%s)" % authored_orphans)

	# Shops name items too, and a ware with no price can't be put on a shelf.
	var shop_errors := PackedStringArray()
	for shop in ShopLibrary.all():
		for ware in shop.wares:
			if not ItemLibrary.exists(ware):
				shop_errors.append("%s sells %s" % [shop.id, ware])
			elif not ItemLibrary.get_item(ware).is_stocked():
				shop_errors.append("%s sells %s, which has no price or floor" % [shop.id, ware])
	_check(ShopLibrary.all().size() == ShopLibrary.SHOPS.size() and shop_errors.is_empty(),
			"every shop loads and every ware is a priced item (%s)" % shop_errors)

	_check(ItemLibrary.exists(&"map_floor_2"),
			"the item Argo sells exists (dialogue's only GIVE_ITEM)")

	var consumables := 0
	for item in ItemLibrary.all():
		if item.is_consumable() and not item.has_effect():
			_check(false, "consumable '%s' does nothing" % item.id)
		if item.is_consumable():
			consumables += 1
	_check(consumables > 0, "there is at least one consumable")

	# Equipment maps to a slot; nothing else does. That table is what makes
	# "can this be worn" a property of the data rather than a list in the UI.
	var slot_errors := PackedStringArray()
	for item in ItemLibrary.all():
		if item.is_equipment() != (item.slot() != &""):
			slot_errors.append(String(item.id))
		if item.is_equipment() and item.slot() not in Inventory.SLOTS:
			slot_errors.append("%s -> %s" % [item.id, item.slot()])
	_check(slot_errors.is_empty(), "equipment agrees with the slot table (%s)" % slot_errors)


# --- stacking --------------------------------------------------------------

func _test_stacking() -> void:
	print("\n-- stacking --")
	_reset()
	var potion := ItemLibrary.get_item(&"small_potion")

	_check(Inventory.add(potion, 5) == 5, "adding to an empty bag accepts everything")
	_check(Inventory.count(&"small_potion") == 5, "the bag counts what it took")
	_check(Inventory.used_slots() == 1, "five of one item is one slot")

	Inventory.add(potion, 3)
	_check(Inventory.count(&"small_potion") == 8, "a second add tops up the same stack")
	_check(Inventory.used_slots() == 1, "topping up takes no new slot")

	# max_stack = 20 on small_potion, so 15 more must spill into a second slot.
	Inventory.add(potion, 15)
	_check(Inventory.count(&"small_potion") == 23, "an overfull stack keeps the surplus")
	_check(Inventory.used_slots() == 2, "the surplus opens a second slot")

	var sword := ItemLibrary.get_item(&"bronze_sword")
	Inventory.add(sword, 3)
	_check(Inventory.used_slots() == 5, "equipment never stacks: 3 swords are 3 slots")
	_check(sword.stack_limit() == 1, "equipment reports a stack limit of one")

	_check(Inventory.has(&"small_potion", 23), "has() counts across stacks")
	_check(not Inventory.has(&"small_potion", 24), "has() refuses more than there is")
	_check(Inventory.count(&"health_potion") == 0, "counting something absent gives zero")
	_check(Inventory.add(null, 5) == 0, "adding nothing is a no-op")
	_check(Inventory.add(potion, 0) == 0, "adding zero is a no-op")
	_check(Inventory.add(potion, -3) == 0, "adding a negative amount is a no-op")


func _test_capacity() -> void:
	print("\n-- capacity --")
	_reset()
	var sword := ItemLibrary.get_item(&"bronze_sword")
	# Equipment doesn't stack, so this is the shortest way to a full bag.
	var accepted := Inventory.add(sword, Inventory.CAPACITY)
	_check(accepted == Inventory.CAPACITY, "the bag fills to exactly its capacity")
	_check(Inventory.is_full(), "a bag at capacity reports full")

	_overflowed.clear()
	_added.clear()
	_check(Inventory.add(sword, 4) == 0, "a full bag accepts nothing more")
	_check(_overflowed == [&"bronze_sword"], "a rejected grant announces inventory_full")
	_check(_added.is_empty(), "nothing rejected is announced as added")
	_check(not Inventory.fits(sword, 1), "fits() sees a full bag")

	# Stackables still fit, because they don't need a new slot.
	_reset()
	var potion := ItemLibrary.get_item(&"small_potion")
	Inventory.add(potion, 1)
	Inventory.add(sword, Inventory.CAPACITY - 1)
	_check(Inventory.is_full(), "the bag is full again")
	_check(Inventory.fits(potion, 19), "a part-used stack still has room in a full bag")
	_check(not Inventory.fits(potion, 20), "and only as much room as it actually has")

	_added.clear()
	_added_amounts.clear()
	_overflowed.clear()
	_check(Inventory.add(potion, 25) == 19, "a partial grant takes what fits")
	_check(_added_amounts == [19], "item_added reports what was accepted, not what was offered")
	_check(_overflowed == [&"small_potion"], "and the remainder is announced as lost")


func _test_removal() -> void:
	print("\n-- removal --")
	_reset()
	var potion := ItemLibrary.get_item(&"small_potion")
	Inventory.add(potion, 25)  # 20 + 5 across two slots
	_check(Inventory.used_slots() == 2, "25 potions occupy two slots")

	_removed.clear()
	_check(Inventory.remove(&"small_potion", 5) == 5, "remove() reports what it took")
	_check(_removed == [&"small_potion"], "removing announces itself")
	_check(Inventory.count(&"small_potion") == 20, "the count drops by what was taken")
	_check(Inventory.used_slots() == 1, "an emptied stack releases its slot")

	_check(Inventory.remove(&"small_potion", 999) == 0,
			"removing more than there is takes nothing at all")
	_check(Inventory.count(&"small_potion") == 20, "and leaves the bag untouched")
	_check(Inventory.remove(&"health_potion") == 0, "removing something absent is a no-op")

	_check(Inventory.remove(&"small_potion", 20) == 20, "the last of a stack can be removed")
	_check(Inventory.is_empty(), "removing everything empties the bag")

	# Key items are the one thing the drop key refuses.
	Inventory.add_id(&"map_floor_2")
	var key_stack := Inventory.stacks()[0]
	_check(not Inventory.drop_stack(key_stack), "a key item cannot be dropped")
	_check(Inventory.has(&"map_floor_2"), "and is still there afterwards")

	Inventory.add_id(&"boar_hide", 4)
	var hide_stack := Inventory.stacks()[1]
	_check(Inventory.drop_stack(hide_stack), "an ordinary stack can be dropped")
	_check(Inventory.count(&"boar_hide") == 0, "dropping takes the whole stack")


# --- ordering --------------------------------------------------------------
## What the inventory screen's drag-and-drop moves. Order is bag state, not a
## view preference, so the rules are tested here with no screen in existence.

func _test_ordering() -> void:
	print("\n-- ordering --")
	_reset()
	var sword := ItemLibrary.get_item(&"bronze_sword")
	var coat := ItemLibrary.get_item(&"leather_coat")
	var hide := ItemLibrary.get_item(&"boar_hide")
	Inventory.add(sword)
	Inventory.add(coat)
	Inventory.add(hide)

	_check(Inventory.move_stack(0, 2), "a stack can be moved onto another")
	var order := Inventory.stacks()
	_check(order[0].item == hide and order[2].item == sword,
			"two different items swap places")
	_check(order[1].item == coat, "and the stack between them does not move")

	_check(not Inventory.move_stack(1, 1), "moving a stack onto itself is a no-op")
	_check(not Inventory.move_stack(-1, 0), "a negative source is refused")
	_check(not Inventory.move_stack(9, 0), "a source past the end is refused")
	_check(not Inventory.move_stack(0, Inventory.CAPACITY),
			"a target past the bag's capacity is refused")

	# Empty slots are all the same place: the bag is a compact list.
	_check(Inventory.move_stack(0, 15), "a stack can be dropped past the last used slot")
	order = Inventory.stacks()
	_check(order.size() == 3 and order[2].item == hide, "which moves it to the back")
	_check(not Inventory.move_stack(2, 15),
			"and the last stack dropped past the end has nowhere to go")

	# Same item: pour into the target, leave any remainder where it was.
	_reset()
	var potion := ItemLibrary.get_item(&"small_potion")
	var limit := potion.stack_limit()
	Inventory.add(potion, limit + 6)
	_check(Inventory.used_slots() == 2, "an over-full pile of potions takes two slots")

	# The same gesture twice: onto a full target it is a swap, onto one with room
	# it is a merge. Which is why the rule is "merge if it fits, else swap" and
	# not two different drags for the player to tell apart.
	_check(Inventory.move_stack(1, 0), "a stack can be dropped onto its own kind")
	order = Inventory.stacks()
	_check(order[0].count == 6 and order[1].count == limit,
			"a target with no room left swaps instead of merging")

	_check(Inventory.move_stack(1, 0), "and again, now that the target has room")
	order = Inventory.stacks()
	_check(order[0].count == limit, "which fills the target to its limit")
	_check(order[1].count == 6, "and leaves the remainder behind rather than overflowing")
	_check(Inventory.count(&"small_potion") == limit + 6, "either way nothing is lost")


# --- the grant channel -----------------------------------------------------
## EventBus.item_granted is a request and item_added is the answer. Combat loot
## and dialogue rewards emit the first; only Inventory emits the second.

func _test_granting() -> void:
	print("\n-- granting --")
	_reset()
	_added.clear()
	EventBus.item_granted.emit(&"boar_hide", 2)
	_check(Inventory.count(&"boar_hide") == 2, "item_granted reaches the bag")
	_check(_added == [&"boar_hide"], "and is answered with item_added")

	_added.clear()
	EventBus.item_granted.emit(&"no_such_item", 1)
	_check(_added.is_empty(), "granting a nonexistent id adds nothing")
	_check(Inventory.used_slots() == 1, "and leaves the bag as it was")

	# The real path, end to end: a dialogue effect handing over Argo's map.
	_reset()
	var effect := DialogueEffect.new()
	effect.kind = DialogueEffect.Kind.GIVE_ITEM
	effect.id = &"map_floor_2"
	effect.amount = 1
	effect.apply()
	_check(Inventory.has(&"map_floor_2"), "a dialogue GIVE_ITEM effect fills the bag")


# --- consumables -----------------------------------------------------------

func _test_consumables() -> void:
	print("\n-- consumables --")
	_reset()
	GameState.max_hp = 100
	GameState.set_hp(40)
	Inventory.add_id(&"small_potion", 2)

	_used.clear()
	_check(Inventory.use(&"small_potion"), "a potion can be drunk in the field")
	_check(GameState.hp == 75, "it heals 35%% of max HP (hp is %d)" % GameState.hp)
	_check(Inventory.count(&"small_potion") == 1, "drinking spends one")
	_check(_used == [&"small_potion"], "drinking announces item_used")

	GameState.set_hp(GameState.total_max_hp())
	_check(not Inventory.use(&"small_potion"), "a potion at full health is refused")
	_check(Inventory.count(&"small_potion") == 1, "and is not spent")

	GameState.set_hp(10)
	_check(not Inventory.use(&"whetstone"), "an item that only applies a status is not field-usable")
	_check(not Inventory.use(&"bronze_sword"), "a sword is not a drink")

	Inventory.remove(&"small_potion", Inventory.count(&"small_potion"))
	_check(not Inventory.use(&"small_potion"), "an item you do not have cannot be used")

	# Overheal clamps rather than overflowing.
	Inventory.add_id(&"health_potion", 1)
	GameState.set_hp(GameState.total_max_hp() - 1)
	Inventory.use(&"health_potion")
	_check(GameState.hp == GameState.total_max_hp(), "healing past the cap clamps to it")


# --- equipment -------------------------------------------------------------

func _test_equipment() -> void:
	print("\n-- equipment --")
	_reset()
	var base_attack := GameState.attack
	var base_hp := GameState.max_hp
	var sword := ItemLibrary.get_item(&"bronze_sword")
	var blade := ItemLibrary.get_item(&"kobold_blade")
	var coat := ItemLibrary.get_item(&"blackwyrm_coat")

	_check(not Inventory.equip(sword), "equipping something you don't have is refused")

	# The bag's comparison: what wearing a copy would change, against what is worn.
	var trial := ItemStack.new(blade)
	_check(Inventory.change_if_worn(trial, &"attack") == blade.attack_bonus,
			"with nothing worn, trying a blade on would add its whole bonus")
	_check(Inventory.change_if_worn(ItemStack.new(ItemLibrary.get_item(&"small_potion")), &"attack") == 0,
			"and trying on a potion changes nothing")

	Inventory.add(sword, 1)
	_equipped.clear()
	_check(Inventory.equip(sword), "a carried weapon can be worn")
	_check(Inventory.change_if_worn(ItemStack.new(blade), &"attack") == blade.attack_bonus - sword.attack_bonus,
			"and trying a better blade on then says by how much it is better")
	_check(_equipped == [&"bronze_sword"], "equipping announces the slot's new occupant")
	_check(Inventory.equipped(&"weapon") == sword, "the slot reports what is in it")
	_check(Inventory.count(&"bronze_sword") == 0, "worn gear leaves the bag")
	_check(Inventory.is_equipped(sword), "and reports itself as worn")

	_check(GameState.total_attack() == base_attack + sword.attack_bonus,
			"a worn weapon raises total attack (%d vs %d)" % [
				GameState.total_attack(), base_attack])
	_check(GameState.attack == base_attack, "and leaves the base stat alone")

	# The whole point: gear has to reach the fight, and it only can through
	# GameState's total_* accessors.
	var fighter := Combatant.from_player()
	_check(fighter.attack == base_attack + sword.attack_bonus,
			"a Combatant built from the player carries the weapon's attack")

	# Swapping: the old one comes back, the new one goes on, in one move.
	Inventory.add(blade, 1)
	_check(Inventory.equip(blade), "a second weapon replaces the first")
	_check(Inventory.equipped(&"weapon") == blade, "the new weapon is worn")
	_check(Inventory.count(&"bronze_sword") == 1, "the old weapon returns to the bag")
	_check(Inventory.count(&"kobold_blade") == 0, "the new weapon left it")
	_check(GameState.total_speed() == GameState.speed + blade.speed_bonus,
			"a negative bonus lowers the total (%d)" % GameState.total_speed())

	# Slots are independent.
	Inventory.add(coat, 1)
	Inventory.equip(coat)
	_check(Inventory.equipped(&"weapon") == blade, "wearing armor leaves the weapon alone")
	_check(GameState.total_max_hp() == base_hp + coat.max_hp_bonus,
			"a coat with +HP raises the ceiling")

	# Taking off the coat has to be able to lower current HP, which set_hp alone
	# cannot do -- refresh_vitals() is what makes this work.
	GameState.set_hp(GameState.total_max_hp())
	var propped_up := GameState.hp
	Inventory.unequip(&"armor")
	_check(GameState.hp == base_hp, "unequipping +HP gear clamps current HP down (%d -> %d)" % [
			propped_up, GameState.hp])
	_check(Inventory.count(&"blackwyrm_coat") == 1, "unequipped gear returns to the bag")
	_check(Inventory.equipped(&"armor") == null, "and the slot is empty")
	_check(not Inventory.unequip(&"armor"), "unequipping an empty slot is refused")

	_check(not Inventory.equip(ItemLibrary.get_item(&"small_potion")),
			"a potion cannot be equipped")
	_check(not Inventory.equip(null), "equipping nothing is refused")

	# A full bag has nowhere to put what comes off.
	_reset()
	Inventory.add(sword, 1)
	Inventory.equip(sword)
	Inventory.add(ItemLibrary.get_item(&"kobold_blade"), Inventory.CAPACITY)
	_check(Inventory.is_full(), "the bag is full with a weapon still worn")
	_check(not Inventory.unequip(&"weapon"), "unequipping into a full bag is refused")
	_check(Inventory.equipped(&"weapon") == sword, "and the gear stays on rather than vanishing")

	_reset()
	_check(GameState.total_attack() == GameState.attack,
			"an empty loadout leaves every stat at its base")


# --- items in battle -------------------------------------------------------

func _test_items_in_battle() -> void:
	print("\n-- items in battle --")
	_reset()
	GameState.max_hp = 200
	GameState.set_hp(60)
	Inventory.add_id(&"health_potion", 2)
	Inventory.add_id(&"whetstone", 1)

	var encounter := Bestiary.single_encounter(Bestiary.get_enemy(&"frenzy_boar"), 1)
	CombatManager.set_seed(4242)
	CombatManager.command_requested.connect(_answer_with_potion)
	var result: CombatResult = await CombatManager.start(encounter)
	CombatManager.command_requested.disconnect(_answer_with_potion)

	_check(result != null, "the fight resolved")
	_check(Inventory.count(&"health_potion") < 2, "drinking in battle spends a potion")
	_check(GameState.hp > 60 or result.victory, "and the healing landed")

	# The rules the runner enforces, checked directly rather than through a menu.
	_reset()
	GameState.set_hp(GameState.total_max_hp())
	CombatManager.command_requested.connect(_answer_with_rule_probes)
	CombatManager.set_seed(99)
	await CombatManager.start(Bestiary.single_encounter(Bestiary.get_enemy(&"frenzy_boar"), 1))
	CombatManager.command_requested.disconnect(_answer_with_rule_probes)
	_check(Inventory.count(&"whetstone") == 0,
			"resolving an item turn empties the bottle")


func _answer_with_potion(_actor: Combatant) -> void:
	if Inventory.has(&"health_potion"):
		CombatManager.submit(CombatAction.use_item(
				ItemLibrary.get_item(&"health_potion"), CombatManager.party()[0]))
		return
	CombatManager.submit(CombatAction.use(
			SkillLibrary.basic_attack(), CombatManager.living_enemies()[0]))


## Probes submit() with illegal item actions, then answers legally so the loop
## can finish. Runs on the first turn only.
func _answer_with_rule_probes(_actor: Combatant) -> void:
	if CombatManager.round_number() == 1:
		_check(not CombatManager.submit(CombatAction.use_item(null)),
				"submitting a null item is refused")
		_check(not CombatManager.submit(CombatAction.use_item(
					ItemLibrary.get_item(&"health_potion"))),
				"using a potion you do not have is refused")
		_check(not CombatManager.submit(CombatAction.use_item(
					ItemLibrary.get_item(&"boar_hide"))),
				"a material is not usable in battle")
		Inventory.add_id(&"whetstone", 1)
		# submit() only accepts the action; the bottle is emptied when the turn
		# actually resolves, which is checked back in _test_items_in_battle.
		_check(CombatManager.submit(CombatAction.use_item(
					ItemLibrary.get_item(&"whetstone"))),
				"a battle-only item is accepted in battle")
		return
	CombatManager.submit(CombatAction.use(
			SkillLibrary.basic_attack(), CombatManager.living_enemies()[0]))


# --- chests ----------------------------------------------------------------

## The chests on an authored floor whose item has no resource behind it. Follows
## MapExits the way the floor test's walk does, because Floor 1's chests are
## split across a town and a field and the registry only names the town.
func _authored_chest_orphans(floor_number: int) -> PackedStringArray:
	var orphans := PackedStringArray()
	var pending: Array[String] = [FloorRegistry.get_floor(floor_number).authored_scene.resource_path]
	var seen := {}
	while not pending.is_empty():
		var path: String = pending.pop_back()
		if seen.has(path) or not ResourceLoader.exists(path):
			continue
		seen[path] = true
		var map := (load(path) as PackedScene).instantiate()
		for child in map.get_children():
			if "item_id" in child and not ItemLibrary.exists(child.get(&"item_id")):
				orphans.append("%s in %s holds %s" % [child.name, path.get_file(), child.get(&"item_id")])
			if "target_map" in child and not str(child.get(&"target_map")).is_empty():
				pending.append(str(child.get(&"target_map")))
		map.free()
	return orphans


func _test_chest() -> void:
	print("\n-- chests --")
	_reset()
	GameState.set_flag(&"test_chest", false)
	var chest := (load("res://scenes/world/chest.tscn") as PackedScene).instantiate()
	chest.set(&"item_id", &"small_potion")
	chest.set(&"amount", 3)
	chest.set(&"opened_flag", &"test_chest")
	add_child(chest)

	_check(chest.is_available(), "an unopened chest is interactable")
	chest.interact(self)
	_check(Inventory.count(&"small_potion") == 3, "opening a chest fills the bag")
	_check(GameState.has_flag(&"test_chest"), "and sets its flag")
	_check(not chest.is_available(), "an opened chest is not interactable")
	DialogueRunner.cancel()

	# A chest that would overflow must stay shut: opening is irreversible, and
	# the flag saying it was opened would outlive the item it destroyed.
	GameState.set_flag(&"test_chest_2", false)
	var full := (load("res://scenes/world/chest.tscn") as PackedScene).instantiate()
	full.set(&"item_id", &"anneal_blade")
	full.set(&"opened_flag", &"test_chest_2")
	add_child(full)
	Inventory.add(ItemLibrary.get_item(&"bronze_sword"), Inventory.CAPACITY)

	full.interact(self)
	_check(not GameState.has_flag(&"test_chest_2"), "a chest will not open into a full bag")
	_check(full.is_available(), "and stays interactable so nothing is lost")
	DialogueRunner.cancel()

	Inventory.remove(&"bronze_sword", 1)
	full.interact(self)
	_check(GameState.has_flag(&"test_chest_2"), "it opens once there is room")
	_check(Inventory.has(&"anneal_blade"), "and hands over its contents")
	DialogueRunner.cancel()

	# Col rides along at the floor's going rate for the chest's tier -- read off
	# the floor, never rolled, so no floor's rng moved to pay it.
	_check(FloorTuning.chest_col(1, 0) > 0
			and FloorTuning.chest_col(30, 0) > FloorTuning.chest_col(1, 0)
			and FloorTuning.chest_col(30, 2) > FloorTuning.chest_col(30, 1)
			and FloorTuning.chest_col(30, 1) > FloorTuning.chest_col(30, 0),
			"a chest's Col climbs with the floor, and sealed > gilded > plain")
	GameState.reset_col()
	GameState.set_flag(&"test_chest_3", false)
	var sealed := (load("res://scenes/world/chest.tscn") as PackedScene).instantiate()
	sealed.set(&"item_id", &"small_potion")
	sealed.set(&"opened_flag", &"test_chest_3")
	sealed.set(&"sealed", true)
	sealed.set(&"floor_number", 30)
	add_child(sealed)
	Inventory.clear()
	sealed.interact(self)
	_check(GameState.col() == FloorTuning.chest_col(30, 2),
			"a sealed chest on floor 30 pays its tier's Col (%d)" % GameState.col())
	DialogueRunner.cancel()
	sealed.queue_free()

	chest.queue_free()
	full.queue_free()


# --- Col --------------------------------------------------------------------

func _test_purse() -> void:
	print("\n-- the purse --")
	_reset()
	_col_changes.clear()
	EventBus.col_granted.emit(50)
	_check(GameState.col() == 50 and _col_changes == [50], "col_granted fills the purse and it says so")
	EventBus.col_granted.emit(-20)
	_check(GameState.col() == 50, "a negative grant is not a way to charge")
	_check(not GameState.spend_col(60) and GameState.col() == 50,
			"spending more than there is spends none of it")
	_check(GameState.spend_col(30) and GameState.col() == 20, "spending what there is takes it")
	EventBus.col_charged.emit(25)
	_check(GameState.col() == 20, "a charge it can't pay is refused whole")
	EventBus.col_charged.emit(20)
	_check(GameState.col() == 0, "a charge it can pay is taken")

	# Combat pays Col beside XP, linear in level as XP is.
	var boar := Bestiary.get_enemy(&"frenzy_boar")
	_check(boar.col_at(10) > boar.col_at(1)
			and boar.col_at(21) - boar.col_at(11) == boar.col_at(11) - boar.col_at(1),
			"a monster's Col is linear in its level")
	var boss := Bestiary.build_boss(boar, 5, "Test Boss")
	_check(boss.col_reward == roundi(boar.col_at(5) * Bestiary.BOSS_COL),
			"a boss carries BOSS_COL times its template's Col")


func _test_dropped_col() -> void:
	print("\n-- dropped col --")
	_reset()
	_drops.clear()
	EventBus.col_granted.emit(120)
	_check(GameState.drop_col(&"test_map", Vector2(40, 56)) == 120 and GameState.col() == 0,
			"falling drops the whole purse")
	var pile := GameState.dropped_col()
	_check(pile.get("map") == &"test_map" and pile.get("position") == Vector2(40, 56)
			and pile.get("amount") == 120 and _drops.back() == 120,
			"and remembers where, and says so")
	EventBus.col_granted.emit(30)
	_check(GameState.drop_col(&"test_map", Vector2(8, 8)) == 30
			and GameState.dropped_col().get("amount") == 30 and _drops.slice(-2) == [0, 30],
			"falling again first loses the first pile for good")
	GameState.drop_col(&"test_map", Vector2(8, 8))
	_check(GameState.dropped_col().is_empty(), "even falling with an empty purse loses it")
	EventBus.col_granted.emit(75)
	GameState.drop_col(&"test_map", Vector2(16, 16))
	_check(GameState.recover_col() == 75 and GameState.col() == 75
			and GameState.dropped_col().is_empty(), "walking back to it picks it all up")
	_check(GameState.recover_col() == 0, "and there is nothing left to pick up twice")

	# The pouch is the pile's view: put down by the map, gone with the pile.
	var map := GameMap.new()
	map.map_id = &"test_map"
	add_child(map)
	GameState.drop_col(&"test_map", Vector2(24, 24))
	await get_tree().process_frame
	var pouch := map.get_node_or_null("DroppedCol") as DroppedCol
	_check(pouch != null and pouch.amount == 75 and pouch.position == Vector2(24, 24),
			"the map puts a pouch down where the purse fell")
	if pouch != null:
		pouch.interact(self)
		DialogueRunner.cancel()
		await get_tree().process_frame
		_check(GameState.col() == 75 and not is_instance_valid(pouch),
				"picking it up empties the pouch back into the purse")
	map.queue_free()


func _test_shops() -> void:
	print("\n-- shops --")
	_reset()
	var shop := ShopLibrary.get_shop(&"town_outfitter")
	var potion := ItemLibrary.get_item(&"small_potion")
	var charm := ItemLibrary.get_item(&"swift_charm")
	GameState._cleared_floors.clear()
	_check(potion in shop.stock() and charm not in shop.stock(),
			"on floor 1 the outfitter shelves potions, not a floor-%d charm" % charm.shop_floor)
	for n in range(1, charm.shop_floor):
		GameState.clear_floor(n)
	_check(charm in shop.stock(), "and shelves the charm once floor %d is reached" % charm.shop_floor)
	_check(shop.refusal(charm) == "Not enough col." and not shop.buy(charm)
			and not Inventory.has(&"swift_charm"), "a buyer with no Col is refused")

	EventBus.col_granted.emit(charm.price + potion.price)
	_check(shop.buy(charm) and Inventory.has(&"swift_charm") and GameState.col() == potion.price,
			"buying takes the price and hands the item over")
	_check(shop.buy(potion) and GameState.col() == 0, "down to the last coin")

	var anneal := ItemLibrary.get_item(&"anneal_blade")
	_check(shop.refusal(anneal) == "Not on the shelf." and not shop.buy(anneal),
			"what the shop doesn't carry can't be bought")

	# A full bag is refused before the purse is touched.
	Inventory.clear()
	Inventory.add(ItemLibrary.get_item(&"bronze_sword"), Inventory.CAPACITY)
	EventBus.col_granted.emit(potion.price)
	_check(shop.refusal(potion) == "No room in your bag." and not shop.buy(potion)
			and GameState.col() == potion.price, "a full bag refuses the sale and keeps the Col")

	Inventory.clear()
	GameState.reset_col()
	Inventory.add_id(&"boar_hide", 3)
	Inventory.add_id(&"map_floor_2", 1)
	var hide := ItemLibrary.get_item(&"boar_hide")
	var offered := shop.sellable().map(func(s: ItemStack) -> StringName: return s.item.id)
	_check(&"boar_hide" in offered and &"map_floor_2" not in offered,
			"the counter buys hides but never a key item")
	_check(shop.sell(hide) and Inventory.count(&"boar_hide") == 2
			and GameState.col() == hide.sell_price(), "selling one pays half its price")
	_check(not shop.sell(ItemLibrary.get_item(&"map_floor_2")) and Inventory.has(&"map_floor_2"),
			"and refuses the key item outright")
	Inventory.add_id(&"bronze_sword", 1)
	Inventory.equip(ItemLibrary.get_item(&"bronze_sword"))
	_check(not shop.sell(ItemLibrary.get_item(&"bronze_sword")) and Inventory.equipped(&"weapon") != null,
			"the sword you are wearing can't be sold out from under you")

	# Every hub has a counter, and every counter on a map is a listed shop.
	var counters := {}
	for floor_number in FloorRegistry.AUTHORED:
		for shop_id in _authored_shops(floor_number):
			counters[floor_number] = true
			_check(shop_id in ShopLibrary.SHOPS,
					"floor %d's shop '%s' is listed" % [floor_number, shop_id])
	_check(counters.has(1) and counters.has(10) and counters.has(25),
			"the town, Ashlow and Lanternfall each have a shop (%s)" % [counters.keys()])
	GameState._cleared_floors.clear()
	GameState.reset_col()
	_test_village_shops()


## Every band's villages keep a counter whose specialities are the band's own: sold
## at no other counter, a wearable and a consumable, and on the shelf the first
## time a village of that band can be walked into -- floor n settles once n+3 is
## cleared, so its shelf is read with n+3 reached at the most.
func _test_village_shops() -> void:
	var first_village: Dictionary[StringName, int] = {}
	for n in range(1, FloorTuning.TOP_FLOOR + 1):
		var biome := FloorRegistry.get_floor(n).biome.id
		if LocalQuests.settles(n) and not first_village.has(biome):
			first_village[biome] = n
	var elsewhere := {}
	for shop in ShopLibrary.all():
		if not String(shop.id).begins_with("village_"):
			for ware in shop.wares:
				elsewhere[ware] = true
	var problems := PackedStringArray()
	var claimed := {}
	for biome: StringName in first_village:
		var shop := ShopLibrary.village_shop(biome)
		if shop == null:
			problems.append("%s has no village counter" % biome)
			continue
		var own := shop.wares.slice(0, ShopLibrary.SPECIALITIES)
		var kinds := {}
		for ware in own:
			var item := ItemLibrary.get_item(ware)
			if elsewhere.has(ware) or claimed.has(ware):
				problems.append("%s's %s is sold elsewhere too" % [biome, ware])
			claimed[ware] = true
			kinds[item.is_equipment()] = true
			if item.shop_floor > first_village[biome] + LocalQuests.SETTLE_AFTER:
				problems.append("%s's %s isn't shelved until floor %d, past its first village's %d" % [
						biome, ware, item.shop_floor, first_village[biome] + LocalQuests.SETTLE_AFTER])
		if kinds.size() != 2:
			problems.append("%s's specialities aren't a wearable and a consumable" % biome)
		for ware in shop.wares.slice(ShopLibrary.SPECIALITIES):
			if not elsewhere.has(ware):
				problems.append("%s's staple %s is sold nowhere else" % [biome, ware])
	_check(problems.is_empty() and first_village.size() == FloorRegistry.BIOME_BANDS.size(),
			"every band's villages keep a counter of their own specialities, shelved by the first village (%s)" % problems)
	# A speciality whose only effect lands in a fight is refused in the field, like
	# the whetstone: a cure or a buff has nothing to work on outside one.
	var field := PackedStringArray()
	for ware in claimed:
		var item := ItemLibrary.get_item(ware)
		if item.is_consumable() and item.heal_percent == 0 and item.usable_in_field:
			field.append(String(ware))
	_check(field.is_empty(), "no speciality that only works in a fight is offered in the field (%s)" % field)


## The smith (M5.6's deep sink): a copy's +N, how it reaches combat, and the
## forge's rules -- cost, materials by tier, odds, and what a failure costs.
func _test_forge() -> void:
	print("\n-- the forge --")
	_reset()
	for id in ItemLibrary.ITEMS:
		var item := ItemLibrary.get_item(StringName(id))
		if item.is_equipment():
			_check(item.max_plus() > 0 and item.plus_step() > 0 and item.enhanced_stat() != &"",
					"%s can be enhanced (+%d max, +%d %s a level)" % [id, item.max_plus(),
					item.plus_step(), item.enhanced_stat()])
		elif item.max_plus() != 0:
			_check(false, "%s is not equipment and has no enhancement" % id)
	for id in ShopLibrary.SMITHS:
		_check(ShopLibrary.get_smith(StringName(id)) != null, "forge '%s' loads" % id)
	_check(_open_forge_ids(&"nezha") == [&"town_forge"],
			"Nezha's menu opens the town forge (%s)" % [_open_forge_ids(&"nezha")])

	# The +N reaches combat through GameState and nowhere else.
	var blade := ItemLibrary.get_item(&"anneal_blade")
	Inventory.add(blade, 1)
	Inventory.equip(blade)
	var before := GameState.total_attack()
	var worn := Inventory.worn(&"weapon")
	_check(worn != null and worn.plus == 0, "a found blade starts at +0")
	_check(Inventory.enhance(worn) and worn.plus == 1
			and GameState.total_attack() == before + blade.plus_step(),
			"+1 on the worn blade adds its step to total attack (%d -> %d)" % [before,
			GameState.total_attack()])
	_check(Combatant.from_player().attack == GameState.total_attack(),
			"and the fight sees it")
	_check(worn.label() == "Anneal Blade +1" and blade.summary(1).begins_with(
			"ATK +%d" % (blade.attack_bonus + blade.plus_step())), "it reads as +1 in the bag")
	_check(Inventory.unequip(&"weapon") and Inventory.stacks()[0].plus == 1
			and GameState.total_attack() == before - blade.attack_bonus,
			"taken off, the +1 goes into the bag with it")

	# Two copies are two pieces of work.
	Inventory.add(blade, 1)
	_check(Inventory.equip(blade) and Inventory.worn(&"weapon").plus == 1,
			"equipping by item wears the best copy")
	Inventory.unequip(&"weapon")
	Inventory.remove(&"anneal_blade", 1)
	_check(Inventory.count(&"anneal_blade") == 1 and Inventory.stacks()[0].plus == 1,
			"removing one takes the plain copy, never the worked one")
	Inventory.add(blade, 1)
	var plain: ItemStack = Inventory.stacks().filter(func(s: ItemStack) -> bool:
			return s.plus == 0)[0]
	_check(Inventory.equip_stack(plain) and Inventory.worn(&"weapon").plus == 0,
			"equipping a chosen copy wears that copy")
	var shop := ShopLibrary.get_shop(&"town_outfitter")
	Inventory.unequip(&"weapon")
	var worked: ItemStack = Inventory.stacks().filter(func(s: ItemStack) -> bool:
			return s.plus == 1)[0]
	_check(shop.sell_stack(worked) and Inventory.stacks().size() == 1
			and Inventory.stacks()[0].plus == 0, "selling the row you chose sells that copy")

	# The forge's rules.
	_reset()
	var sword := ItemLibrary.get_item(&"bronze_sword")
	Inventory.add(sword, 1)
	var piece := Inventory.stacks()[0]
	_check(Smith.cost(piece) == maxi(Smith.MIN_COST, roundi(sword.price * Smith.COST_SHARE)),
			"the first step costs a quarter of the price")
	_check(Smith.refusal(piece).begins_with("Needs 1 common"), "no materials, no attempt")
	Inventory.add_id(&"drake_scale", 1)
	Inventory.add_id(&"boar_hide", 2)
	Inventory.add_id(&"raid_tag", 3)
	_check(Smith.materials_held(piece) == 3, "monster drops count, a key item never does")
	_check(Smith.refusal(piece).begins_with("Not enough col"), "no Col, no attempt")
	EventBus.col_granted.emit(10000)
	_check(Smith.refusal(piece).is_empty() and Smith.odds(piece) == 100, "+0 to +1 always takes")
	var col := GameState.col()
	var first_cost := Smith.cost(piece)
	_check(Smith.attempt(piece, 0, 0.0) == Smith.Outcome.SUCCEEDED and piece.plus == 1
			and GameState.col() == col - first_cost, "a success spends the Col and raises the piece")
	_check(Smith.cost(piece) == 2 * first_cost or first_cost == Smith.MIN_COST,
			"and the next step costs twice the first")
	_check(Inventory.count(&"boar_hide") == 1 and Inventory.count(&"drake_scale") == 1,
			"and burns the cheapest material, not the drake scale")
	_check(Smith.odds(piece) == Smith.ODDS[1] and Smith.odds(piece, 1) == Smith.ODDS[1] + Smith.EXTRA_ODDS,
			"+1 to +2 is %d%%, and an extra material adds %d" % [Smith.ODDS[1], Smith.EXTRA_ODDS])
	_check(Smith.max_extra(piece) == 0, "with only the two needed, there is nothing extra to add")
	Inventory.add_id(&"wolf_fang", 5)
	_check(Smith.max_extra(piece) == 1, "and extras stop at a sure thing (%d)" % Smith.max_extra(piece))
	var spend := Smith.materials_for(piece, 1)
	_check(spend.get(&"boar_hide", 0) == 1 and spend.get(&"wolf_fang", 0) == 2
			and not spend.has(&"drake_scale"), "the forge picks which, cheapest first (%s)" % [spend])
	col = GameState.col()
	var cost := Smith.cost(piece)
	_check(Smith.attempt(piece, 0, 99.9) == Smith.Outcome.FAILED and piece.plus == 1
			and GameState.col() == col - cost and Inventory.count(&"boar_hide") == 0,
			"a failure keeps the +1 and costs everything put in")
	piece.plus = 3
	_check(Smith.refusal(piece).begins_with("As sharp as it will go"), "a common blade stops at +3")
	var coat := ItemLibrary.get_item(&"blackwyrm_coat")
	Inventory.add(coat, 1)
	var armour: ItemStack = Inventory.stacks().filter(func(s: ItemStack) -> bool:
			return s.item == coat)[0]
	armour.plus = 3
	_check(Smith.tier(armour) == Item.Rarity.UNCOMMON and Smith.materials_held(armour) == 1
			and Smith.refusal(armour).begins_with("Needs 4 uncommon"),
			"from +3 the step wants uncommon materials: fangs won't do, the drake scale will")
	Inventory.add_id(&"lizard_scale", 4)
	_check(Smith.attempt(armour, 0, 0.0) == Smith.Outcome.SUCCEEDED and armour.plus == 4
			and Inventory.count(&"drake_scale") == 1,
			"lizard scales do, and the drake scale still isn't the first thing burnt")
	_check(not Inventory.enhance(Inventory.worn(&"weapon")), "there is nothing to enhance in an empty slot")
	_reset()


## Every forge id an OPEN_FORGE effect in [param dialogue_id] names.
func _open_forge_ids(dialogue_id: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	var dialogue := load("res://resources/dialogue/%s.tres" % dialogue_id) as Dialogue
	for line in dialogue.lines:
		for effect in line.effects:
			if effect.kind == DialogueEffect.Kind.OPEN_FORGE:
				ids.append(effect.id)
	return ids


## The measured check M5.6 asked for: a player killing the floor's
## [method FloorTuning.monster_count] and its boss, and nothing else -- no chests,
## no quests, no selling -- can afford any item the floor it unlocks on puts on
## a shelf by the time that floor is cleared. Prices are fixed and income climbs,
## so this bites low down, where the prices were set against it.
func _test_economy() -> void:
	print("\n-- economy --")
	var income := 0
	var through: Dictionary[int, int] = {}
	var rising := true
	var last := 0
	for n in range(1, FloorTuning.TOP_FLOOR + 1):
		var floor_income := _floor_col(n)
		rising = rising and floor_income >= last
		last = floor_income
		income += floor_income
		through[n] = income
	_check(rising, "a floor never pays less than the one below it")
	var unaffordable := PackedStringArray()
	var stocked := {}
	for shop in ShopLibrary.all():
		for ware in shop.wares:
			stocked[ware] = true
	for ware: StringName in stocked:
		var item := ItemLibrary.get_item(ware)
		if item.price > through[item.shop_floor]:
			unaffordable.append("%s (%d col, floor %d pays %d)" % [
					ware, item.price, item.shop_floor, through[item.shop_floor]])
	_check(unaffordable.is_empty(),
			"every ware is affordable on kills alone once the floor it unlocks on is cleared (%s)" % unaffordable)
	print("  kills alone, cumulative: floor 1 %d, 10 %d, 25 %d, 50 %d, 100 %d" % [
			through[1], through[10], through[25], through[50], through[100]])


## What one floor's kills pay: its monster count at the pool's average, plus its
## boss and escort.
func _floor_col(n: int) -> int:
	var pool := Bestiary.pool_for_floor(n)
	var level := FloorTuning.enemy_level(n)
	var each := 0.0
	for type in pool:
		each += type.col_at(level)
	each /= maxf(1.0, pool.size())
	var total := roundi(each * FloorTuning.monster_count(n))
	var encounter := Bestiary.boss_encounter(n)
	for i in encounter.enemies.size():
		if i == 0:
			total += Bestiary.build_boss(encounter.enemies[0], encounter.level, "").col_reward
		else:
			total += encounter.enemies[i].col_at(encounter.level)
	return total


## The shop ids standing on an authored floor's maps, following exits as
## [method _authored_chest_orphans] does.
func _authored_shops(floor_number: int) -> PackedStringArray:
	var found := PackedStringArray()
	var pending: Array[String] = [FloorRegistry.get_floor(floor_number).authored_scene.resource_path]
	var seen := {}
	while not pending.is_empty():
		var path: String = pending.pop_back()
		if seen.has(path) or not ResourceLoader.exists(path):
			continue
		seen[path] = true
		var map := (load(path) as PackedScene).instantiate()
		for child in map.get_children():
			if child is Npc and (child as Npc).shop != null:
				found.append(String((child as Npc).shop.id))
			if "target_map" in child and not str(child.get(&"target_map")).is_empty():
				pending.append(str(child.get(&"target_map")))
		map.free()
	return found


# --- helpers ---------------------------------------------------------------

## Empties the bag and returns the player to their base numbers. Every section
## starts from here so an earlier failure can't cascade.
func _reset() -> void:
	Inventory.clear()
	GameState.reset_col()
	GameState.level = 1
	GameState.max_hp = 60
	GameState.attack = 8
	GameState.defense = 4
	GameState.speed = 10
	GameState.set_hp(60)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", description)
	else:
		print("  FAIL ", description)
		_failures.append(description)
