class_name Chest
extends Interactable
## A one-shot container.
##
## Opened state is stored as a world flag in [GameState], not on the node, so a
## chest stays open after leaving and re-entering the map.
##
## The reward is granted through [signal EventBus.item_granted] rather than by
## calling [Inventory] -- a chest announces what it gave up and does not need to
## know where it went. The one thing it does check is whether the bag can take
## it: opening is irreversible, so a chest that would overflow stays shut.
##
## A [member gilded] chest -- the pack's big red one -- is the richer one, and it
## is the one that may be trapped. That is the whole tell: a gilded chest is not
## always a trap, but a trap is always a gilded chest. The trap springs as the lid
## opens, after the item is in the bag -- the loot is the bait, not the price.
##
## A [member sealed] chest is the third kind: a puzzle's reward, never trapped,
## holding the floor's best. Plain is found, gilded is gambled, sealed is earned.
## Most stay [member hidden_until] their puzzle is solved -- not drawn, not solid,
## not offered -- and then appear where the puzzle said they would.

enum Trap { NONE, ALARM, TELEPORT }

## How many of the floor's monsters an alarm brings, and how far off they appear.
const ALARM_PACK := 3
const ALARM_RANGE := 3
const MONSTER_SCENE := preload("res://scenes/world/monster.tscn")
const GILDED_TEXTURE := preload("res://assets/ninja_adventure/Items/Treasure/BigTreasureChest.png")
## How long a sealed chest takes to appear once its puzzle is solved.
const APPEAR_TIME := 0.6

## The big chest turned from red to the sealed tier's blue, made once.
static var _sealed_texture: Texture2D = null

## What is inside, by [ItemLibrary] id.
@export var item_id: StringName = &"small_potion"
@export_range(1, 99) var amount := 1
## Must be unique per chest, e.g. &"chest_town_well".
@export var opened_flag: StringName = &""
## The big red chest: drawn richer, and the only kind that is ever trapped.
@export var gilded := false
@export var trap := Trap.NONE
## Where a TELEPORT trap puts you, map-local.
@export var trap_target := Vector2.ZERO
## The floor whose monsters an ALARM brings.
@export var floor_number := 0
## A puzzle's reward: drawn as the sealed tier, never trapped.
@export var sealed := false
## Hidden until this flag is set -- the puzzle's solved flag. Empty for always there.
@export var hidden_until: StringName = &""
## Set as the chest opens, beside its item: one of a vault's sigils.
@export var sigil_flag: StringName = &""
## Col inside, beside the item. -1 is the floor's going rate for the chest's tier
## ([method FloorTuning.chest_col]), which is what every built chest uses: read off
## the floor at opening rather than stored, so no floor's rng was asked for it.
@export var col := -1

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	if gilded or sealed:
		_sprite.texture = _sealed_look() if sealed else GILDED_TEXTURE
		_sprite.offset = Vector2(0, -7)
	if is_opened():
		_show_opened()
	if is_hidden():
		_set_present(false)
		EventBus.flag_changed.connect(_on_flag_changed)


func interact(by: Node) -> void:
	super.interact(by)
	if is_opened():
		_say("The chest is empty.")
		return

	var item := ItemLibrary.get_item(item_id)
	if item == null:
		# A content bug, already shouted about by ItemLibrary. Open it anyway
		# rather than leaving the player prodding a chest that never responds.
		_open()
		_say("The chest is empty after all.")
		return

	if not Inventory.fits(item, amount):
		_say("Your bag is too full for %s." % item.label())
		return

	_open()
	EventBus.item_granted.emit(item_id, amount)
	var coins := col_amount()
	if coins > 0:
		EventBus.col_granted.emit(coins)
	var found := "You found %s." % _found_text(item)
	if coins > 0:
		found = "You found %s and %d col." % [_found_text(item), coins]
	if sigil_flag != &"":
		found += " Under it lies a sigil, warm to the touch."
	match trap:
		Trap.ALARM:
			_say(found, "The lid clicks. An alarm shrieks through the floor, and something answers it.")
			_sound_alarm(by as Node2D)
		Trap.TELEPORT:
			_say(found, "The lid clicks. The floor flares white under your feet --")
			await _teleport(by as Node2D)
		_:
			_say(found)


## The Col this chest holds: its own [member col], or its tier's going rate.
func col_amount() -> int:
	if col >= 0:
		return col
	var tier := 2 if sealed else 1 if gilded else 0
	return FloorTuning.chest_col(maxi(1, floor_number), tier)


func is_opened() -> bool:
	return opened_flag != &"" and GameState.has_flag(opened_flag)


func is_available() -> bool:
	return not is_opened() and not is_hidden()


## Whether the puzzle this chest pays out for is still unsolved.
func is_hidden() -> bool:
	return hidden_until != &"" and not GameState.has_flag(hidden_until)


func _open() -> void:
	if opened_flag != &"":
		GameState.set_flag(opened_flag)
	if sigil_flag != &"":
		GameState.set_flag(sigil_flag)
	_show_opened()


func _on_flag_changed(flag: StringName, _value: Variant) -> void:
	if flag != hidden_until or is_hidden():
		return
	EventBus.flag_changed.disconnect(_on_flag_changed)
	# Drawn at once, solid once the player isn't standing where it appeared.
	visible = true
	SolidWhenClear.attach($Solid)
	modulate.a = 0.0
	create_tween().tween_property(self, ^"modulate:a", 1.0, APPEAR_TIME)


## Drawn and solid, or neither.
func _set_present(present: bool) -> void:
	visible = present
	for shape in $Solid.get_children():
		(shape as CollisionShape2D).set_deferred(&"disabled", not present)


## The gilded chest's art with its reds turned to blues: one drawing, three tiers.
static func _sealed_look() -> Texture2D:
	if _sealed_texture == null:
		var image := GILDED_TEXTURE.get_image()
		image.convert(Image.FORMAT_RGBA8)
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a > 0.0 and pixel.s > 0.3:
					pixel.h = fposmod(pixel.h + 0.55, 1.0)
					image.set_pixel(x, y, pixel)
		_sealed_texture = ImageTexture.create_from_image(image)
	return _sealed_texture


func _found_text(item: Item) -> String:
	return item.label() if amount <= 1 else "%s x%d" % [item.label(), amount]


func _say(text: String, more := "") -> void:
	var lines := PackedStringArray([text])
	if not more.is_empty():
		lines.append(more)
	EventBus.message_requested.emit("", lines)


## Brings [constant ALARM_PACK] of the floor's monsters to stand round the chest,
## [constant ALARM_RANGE] cells off on whatever floor is free -- close enough that
## they see you the moment the box closes. They are ordinary roaming monsters from
## then on: outrunnable, gone for good once beaten, back only if the floor is.
func _sound_alarm(by: Node2D) -> void:
	var map := get_parent() as GameMap
	var pool := Bestiary.pool_for_floor(maxi(1, floor_number))
	if map == null or pool.is_empty():
		return
	var walls := map.get_node("Walls") as TileMapLayer
	map.refresh_solids()
	var at := walls.local_to_map(walls.to_local(global_position))
	var spots: Array[Vector2i] = []
	for offset in _ring(ALARM_RANGE):
		var cell := at + offset
		if map.is_standable(cell) and not map.is_safe_cell(cell):
			spots.append(cell)
	spots.shuffle()
	var you := walls.local_to_map(walls.to_local(by.global_position)) if by else at
	for i in mini(ALARM_PACK, spots.size()):
		var monster := MONSTER_SCENE.instantiate() as Monster
		monster.name = "Alarm%d" % i
		monster.enemy = pool[randi() % pool.size()]
		monster.floor_number = floor_number
		monster.position = map.to_local(walls.to_global(walls.map_to_local(spots[i])))
		map.add_child(monster)
		monster.face(Vector2(you - spots[i]))


## The cells [param radius] steps from the chest, a square ring.
static func _ring(radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if maxi(absi(x), absi(y)) == radius:
				cells.append(Vector2i(x, y))
	return cells


## Once the message is read, a flash, and you are standing at [member trap_target].
func _teleport(by: Node2D) -> void:
	if by == null:
		return
	if DialogueRunner.is_running():
		await EventBus.dialogue_finished
	await SceneRouter.blink(func() -> void:
		if not is_instance_valid(by):
			return
		by.global_position = (get_parent() as Node2D).to_global(trap_target)
		var camera := by.get_node_or_null("Camera2D") as Camera2D
		if camera:
			camera.reset_smoothing())
	_say("You are somewhere else, deeper in, and it is dark.")


func _show_opened() -> void:
	# The sheet's second frame is the lid thrown open; art without one just dims.
	if _sprite.hframes > 1:
		_sprite.frame = 1
	else:
		_sprite.modulate = Color(0.55, 0.55, 0.6)
