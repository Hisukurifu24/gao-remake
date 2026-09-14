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
	for id in FloorGenerator.CHEST_CONSUMABLES + FloorGenerator.CHEST_GEAR:
		if not ItemLibrary.exists(id):
			chest_orphans.append(String(id))
	_check(chest_orphans.is_empty(), "every generated-chest item exists (%s)" % chest_orphans)

	# Authored floors fill their chests from a layout table rather than the pools
	# above, and a typo there is just as silent -- the chest opens onto nothing.
	var authored_orphans := PackedStringArray()
	for floor_number in FloorRegistry.AUTHORED:
		authored_orphans.append_array(_authored_chest_orphans(floor_number))
	_check(authored_orphans.is_empty(), "every authored-floor chest item exists (%s)" % authored_orphans)

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

	Inventory.add(sword, 1)
	_equipped.clear()
	_check(Inventory.equip(sword), "a carried weapon can be worn")
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

	chest.queue_free()
	full.queue_free()


# --- helpers ---------------------------------------------------------------

## Empties the bag and returns the player to their base numbers. Every section
## starts from here so an earlier failure can't cascade.
func _reset() -> void:
	Inventory.clear()
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
