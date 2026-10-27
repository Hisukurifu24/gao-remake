class_name FloorEvents
extends RefCounted
## Something happening on a generated floor (plan.md, M6 "Floor variety"): what
## makes a floor a story rather than a layout. [method FloorRegistry.event_of]
## decides it per world, on a stream of its own; at most one a floor.
##
## - [b]FIELD_BOSS[/b]: a monster far bigger than its kind stands guard in a far
##   field room, in front of a stone door into a [b]hoard[/b] -- a room carved out
##   of the rock behind the room's wall, the vault's shape ([method FloorPuzzles.pin_vault]).
##   It fights as a boss and stays beaten ([member Monster.defeat_flag]); its fall
##   is the door's key, and the door opens itself on a sealed chest.
## - [b]ESCORT[/b]: a player cornered in the farthest field room, two of the floor's
##   monsters round them. Take the job ([method build], a quest named
##   [code]event_<n>_escort[/code], as a settled floor's jobs are) and they follow
##   you ([Escortee]); walk them into the camp and it pays out.
## - [b]AMBUSH[/b]: player killers hiding in a field room on the way to the
##   labyrinth ([Ambush]): pay their toll or fight the pair of them.
## - [b]RACE[/b]: a rival party in the camp who reckon they'll clear the floor
##   today ([RivalParty]). Bet against them and race them to the boss room; lose,
##   and they clear the floor -- the boss is theirs. Only on a classic floor: it is
##   a race through a labyrinth.
##
## Two passes, as [FloorPuzzles] has: [method plan] on the finished layout before it
## is dressed -- the hoard is carved there, so its walls join like any -- and
## [method place] once everything else is on the map. Everything is drawn from its
## own stream ([code]hash("<seed>:events")[/code], and the cast from
## [code]hash("<seed>:event_cast")[/code]), never the floor's, and planned after the
## puzzles: a floor with its event is the floor without, plus the event.
## [member FloorGenerator.event_override] forces a kind for the tests and tools.

enum Kind { NONE, FIELD_BOSS, ESCORT, AMBUSH, RACE }
const KIND_NAMES: PackedStringArray = ["none", "field boss", "escort", "ambush", "race"]

## The share of the floors that may have an event that do.
const CHANCE := 0.5
const TILE := 16
## How fast a rival party walks to the door, in pixels a second: well under the
## player's 90, since they know the way and you have to find it. A race is walked
## in the time it takes them to walk it without a stop -- see [method race_time].
const RIVAL_SPEED := 32.0
## How far a field boss drifts from its post.
const FIELD_BOSS_WANDER := 12.0
## Its sprite's tint: gilded, like what it guards.
const FIELD_BOSS_TINT := Color(1.0, 0.86, 0.55)
const FIELD_BOSS_TITLES: PackedStringArray = ["Hoardkeeper", "Gatekeeper", "Hoard Tyrant"]
## The monsters round a stranded player, on top of the floor's count.
const BESIEGERS := 2
## What getting a stranded player home pays, in the floor's monsters' worth: XP,
## and Col by the same count.
const ESCORT_KILLS := 4.0
const ESCORT_GEAR: Array[StringName] = [&"guard_ring", &"swift_charm", &"leather_coat", &"kobold_blade"]
## A race's stake, and a player killer's toll, in the floor's kills' worth of Col.
const STAKE_KILLS := 6
const TOLL_KILLS := 4
const RACE_PRIZES: Array[StringName] = [&"swift_charm", &"guard_ring", &"blackwyrm_coat", &"health_potion"]

const CHARACTERS := "res://assets/ninja_adventure/Actor/Character/%s/%s.png"
const STRANDED_SHEETS: PackedStringArray = ["Hunter", "NinjaGreen", "Woman", "FighterWhite", "Monk", "Eskimo"]
const STRANDED_NAMES: PackedStringArray = [
	"Tamsin", "Kirra", "Dax", "Pell", "Wren", "Juno", "Rook", "Nim", "Orrin", "Lark",
]
const GUILDS: PackedStringArray = [
	"the Iron Wolves", "the Dawnriders", "the Scarlet Lances", "the Blue Lanterns",
	"the Kestrel Company", "the Long Road",
]
const LEADERS: PackedStringArray = ["Garran", "Vessa", "Holt", "Mira", "Tarkin", "Ilse"]
const RIVAL_SHEETS: PackedStringArray = [
	"Knight", "SamuraiBlue", "GladiatorBlue", "NinjaBlue", "KnightGold", "Samurai", "FighterRed",
	"RedGladiator",
]
const PLAYER_KILLERS: PackedStringArray = ["Vex", "Kuro", "Slate", "Mott", "Cinder"]
const PK_SHEET := "NinjaDark"

const CHEST_SCENE := preload("res://scenes/world/chest.tscn")
const SEAL_SCENE := preload("res://scenes/world/sealed_door.tscn")
const MONSTER_SCENE := preload("res://scenes/world/monster.tscn")
const NPC_SCENE := preload("res://scenes/world/npc.tscn")
const ESCORTEE_SCENE := preload("res://scenes/world/escortee.tscn")

const STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]

## What the camp's veteran adds about the floor's event, after their opening.
## {side}, {name}, {guild} and {leader} are filled in.
const CAMP_LINES := {
	Kind.FIELD_BOSS: "Mind the rooms to the {side}. There's something big sat in front of a stone door out there, like it's guarding it. A field boss -- and they never guard nothing.",
	Kind.ESCORT: "Have you seen {name}? Went out to scout the rooms to the {side} and never came back. If they're cornered out there, they won't make it back on their own.",
	Kind.AMBUSH: "And watch yourself on the way to the labyrinth. Orange cursors were seen on this floor -- player killers. They hide, and they wait.",
	Kind.RACE: "See {guild} over there? They reckon they'll clear this floor today. {leader}'s been looking for someone fool enough to race them for it.",
}

static var _casts: Dictionary[String, Dictionary] = {}

var kind := Kind.NONE
var floor_number := 0
## The hoard in tiles, its doorway, its chest, and where its keeper stands.
var hoard := Rect2i()
var hoard_door := Rect2i()
var hoard_chest := Vector2i(-1, -1)
var guard_cell := Vector2i(-1, -1)
## Where the stranded player waits, and the monsters round them.
var stranded_cell := Vector2i(-1, -1)
var besieger_cells: Array[Vector2i] = []
## The room the event happens in -- the hoard's, the stranded player's, the
## ambush's. Empty for a race, which is the whole floor.
var room := Rect2i()

var _rng := RandomNumberGenerator.new()
var _seed := 0
var _biome: BiomeKit
var _ground: TileMapLayer
var _walls: TileMapLayer
var _open: Dictionary[Vector2i, bool]
var _field := Rect2i()
var _taken: Dictionary[Vector2i, bool] = {}


## [param open] is the generator's carved cells with decor taken out -- read,
## never written. [param field] is where the rooms are.
func _init(number: int, generation_seed: int, biome: BiomeKit, ground: TileMapLayer,
		walls: TileMapLayer, open: Dictionary[Vector2i, bool], field: Rect2i) -> void:
	floor_number = number
	_seed = generation_seed
	_rng.seed = hash("%d:events" % generation_seed)
	_biome = biome
	_ground = ground
	_walls = walls
	_open = open
	_field = field


# --- the floor's words ----------------------------------------------------------

## The flag an event keeps its state in: [code]event_<n>_<what>[/code].
static func flag(number: int, what: String) -> StringName:
	return StringName("event_%d_%s" % [number, what])


static func escort_quest(number: int) -> StringName:
	return flag(number, "escort")


## The conversation a stranded player has once they are home: the escort job's
## TALK target, and the one with no .tres behind it.
static func escort_talk(number: int) -> StringName:
	return flag(number, "escort_home")


## A race's stake, which each side puts up; a player killer's toll.
static func stake(number: int) -> int:
	return FloorTuning.kill_col(number) * STAKE_KILLS


static func toll(number: int) -> int:
	return FloorTuning.kill_col(number) * TOLL_KILLS


## Whether floor [param number]'s race has been run, won or lost.
static func race_over(number: int) -> bool:
	return GameState.has_flag(flag(number, "race_won")) or GameState.has_flag(flag(number, "race_lost"))


## Who the stranded player is on floor [param number]: [code]{name, sheet}[/code].
static func stranded(number: int) -> Dictionary:
	var cast := _cast(number)
	return {"name": cast["stranded"], "sheet": cast["stranded_sheet"]}


## The rival party on floor [param number]: [code]{guild, leader, sheets, prize}[/code].
static func rivals(number: int) -> Dictionary:
	var cast := _cast(number)
	return {"guild": cast["guild"], "leader": cast["leader"], "sheets": cast["rival_sheets"],
			"prize": cast["prize"]}


## Who speaks for the player killers on floor [param number].
static func player_killer(number: int) -> String:
	return _cast(number)["pk"]


## What the camp's veteran says about [param event] -- [param words] fill it in.
static func camp_line(event: int, words: Dictionary) -> String:
	return (CAMP_LINES.get(event, "") as String).format(words)


# --- the escort job ----------------------------------------------------------------

## Whether [param id] names the escort job of a floor that has one.
static func owns(id: StringName) -> bool:
	var number := _floor_of(id, 3)
	return number > 0 and id == escort_quest(number) and _has_escort(number)


## Whether [param id] is the conversation an escort job asks for.
static func is_conversation(id: StringName) -> bool:
	var number := _floor_of(id, 4)
	return number > 0 and id == escort_talk(number) and _has_escort(number)


## The escort job [param id] names, built from its floor; null if it names none.
static func build(id: StringName) -> Quest:
	if not owns(id):
		return null
	var number := _floor_of(id, 3)
	var who := stranded(number)
	var worth := _worth(number)
	var quest := Quest.new()
	quest.id = id
	quest.title = "%s, Stranded" % who["name"]
	quest.giver = who["name"]
	quest.summary = "%s got cornered out in the field on Floor %d and can't fight their way back alone. Get them to the camp." % [
			who["name"], number]
	quest.needs_turn_in = false
	var objective := QuestObjective.new()
	objective.id = &"home"
	objective.kind = QuestObjective.Kind.TALK
	objective.target = escort_talk(number)
	objective.description = "Bring %s back to the camp" % who["name"]
	var objectives: Array[QuestObjective] = [objective]
	quest.objectives = objectives
	var rewards: Array[DialogueEffect] = [
		_effect(DialogueEffect.Kind.GRANT_XP, &"", roundi(worth["xp"] * ESCORT_KILLS)),
		_effect(DialogueEffect.Kind.GIVE_COL, &"", roundi(worth["col"] * ESCORT_KILLS)),
		_effect(DialogueEffect.Kind.GIVE_ITEM, _cast(number)["escort_gear"], 1),
	]
	quest.rewards = rewards
	return quest


## What the stranded player says where you find them: the offer, and once taken,
## that they are ready to go on.
static func escort_dialogue(number: int) -> Dialogue:
	var who := stranded(number)
	var id := escort_quest(number)
	var talk := Dialogue.new()
	talk.id = flag(number, "escort_found")
	talk.default_speaker = who["name"]
	talk.default_portrait = load(CHARACTERS % [who["sheet"], "Faceset"])
	talk.lines.append(_line("You came back! Lead the way -- I'll be right behind you.",
			[_quest_flag(id, "started")]))
	var offer := _line("A player! Thank god. I came out to scout and they cornered me in here -- I can't fight my way back to the camp on my own. Will you take me?", [])
	var take := _choice("Stay close.", [], [_effect(DialogueEffect.Kind.START_QUEST, id, 1)])
	take.next = &"go"
	offer.choices = [take, _choice("Not yet.", [], [])] as Array[DialogueChoice]
	talk.lines.append(offer)
	var go := _line("Right behind you. Don't let them get between us.", [])
	go.id = &"go"
	talk.lines.append(go)
	return talk


## What they say once they are in the camp: the job's TALK target.
static func home_dialogue(number: int) -> Dialogue:
	var who := stranded(number)
	var talk := Dialogue.new()
	talk.id = escort_talk(number)
	talk.default_speaker = who["name"]
	talk.default_portrait = load(CHARACTERS % [who["sheet"], "Faceset"])
	talk.lines.append(_line("We made it... I really thought that was it for me. I owe you one -- here, take this. I won't be needing it down in town.", []))
	return talk


# --- the ambush and the race --------------------------------------------------------

## What the player killers say as they drop their hiding: their toll, or the fight.
static func ambush_dialogue(number: int) -> Dialogue:
	var cost := toll(number)
	var talk := Dialogue.new()
	talk.id = flag(number, "ambush_talk")
	talk.default_speaker = player_killer(number)
	talk.default_portrait = load(CHARACTERS % [PK_SHEET, "Faceset"])
	var hello := _line("Well, well. A solo player, all on their own, this far out.", [])
	# Falls through to the demand: one block, one way in.
	hello.next = &""
	talk.lines.append(hello)
	var demand := _line("Here's how this goes. Hand over %d col and walk away. Or don't, and we take it off you." % cost, [])
	var pay := _choice("Pay them. (%d col)" % cost, [_min_col(cost)], [
		_effect(DialogueEffect.Kind.TAKE_COL, &"", cost),
		_effect(DialogueEffect.Kind.SET_FLAG, flag(number, "ambush_paid"), 1),
	])
	pay.hide_when_locked = false
	pay.locked_hint = "(you haven't got it)"
	var fight := _choice("Draw your sword.", [], [])
	fight.next = &"fight"
	demand.choices = [pay, fight] as Array[DialogueChoice]
	talk.lines.append(demand)
	var answer := _line("Wrong answer.", [])
	answer.id = &"fight"
	talk.lines.append(answer)
	return talk


## What the rival party's leader says in the camp: the bet, or why there's no race.
static func race_dialogue(number: int) -> Dialogue:
	var cast := rivals(number)
	var bet := stake(number)
	var talk := Dialogue.new()
	talk.id = flag(number, "race_talk")
	talk.default_speaker = cast["leader"]
	talk.default_portrait = load(CHARACTERS % [cast["sheets"][0], "Faceset"])
	var found := DialogueCondition.new()
	found.test = DialogueCondition.Test.FLAG_SET
	found.flag = BossGate.found_flag(number)
	talk.lines.append(_line("You already know where the door is? Then there's no race in it. Go on -- it's yours.", [found]))
	var offer := _line("We're %s, and we're clearing Floor %d today. Fancy a race? First into the boss room takes the floor. Put up %d col and we'll match it." % [
			cast["guild"], number, bet], [])
	var take := _choice("You're on. (%d col)" % bet, [_min_col(bet)], [
		_effect(DialogueEffect.Kind.TAKE_COL, &"", bet),
		_effect(DialogueEffect.Kind.SET_FLAG, flag(number, "race"), 1),
	])
	take.hide_when_locked = false
	take.locked_hint = "(you need %d col)" % bet
	take.next = &"go"
	offer.choices = [take, _choice("Not today.", [], [])] as Array[DialogueChoice]
	talk.lines.append(offer)
	var go := _line("Then go! Last one to the door buys the drinks.", [])
	go.id = &"go"
	talk.lines.append(go)
	return talk


# --- planning -------------------------------------------------------------------

## Decides where floor's event [param picked] happens, and carves the hoard. The
## rooms are the floor's; [param entry] is where you arrive, [param plot] the camp,
## [param keep_out] rooms that are something else already (a safe zone);
## [param route_to] is the labyrinth's or the arena's doorstep, the way the floor
## goes; [param keep] cells nothing may stand on or crowd. Before dressing.
func plan(picked: Kind, rooms: Array[Rect2i], entry: Rect2i, plot: Rect2i, keep_out: Array[Rect2i],
		chest_cells: Array[Vector2i], puzzles: FloorPuzzles, keep: Array[Vector2i],
		route_to: Vector2i) -> void:
	for cell in chest_cells:
		_reserve(cell, 1)
	for cell in keep:
		_reserve(cell, 1)
	if puzzles != null:
		for cell in puzzles.claimed():
			_taken[cell] = true
	var steps := _walk_from(_center(entry))
	var candidates: Array[Rect2i] = []
	for each in rooms:
		if each != entry and not each.intersects(plot) and not each in keep_out \
				and _room_steps(steps, each) < 1 << 20:
			candidates.append(each)
	# Farthest walk first: what happens out there happens far from help.
	candidates.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		return _room_steps(steps, a) > _room_steps(steps, b))
	match picked:
		Kind.FIELD_BOSS:
			_plan_hoard(candidates, chest_cells)
		Kind.ESCORT:
			_plan_stranded(candidates)
		Kind.AMBUSH:
			_plan_ambush(candidates, steps, entry, route_to)
		Kind.RACE:
			kind = Kind.RACE


## The hoard off a far room's wall, the north first so its door faces you as you
## walk up -- the vault's way, by the vault's code -- and its keeper two steps out
## in front of it.
func _plan_hoard(candidates: Array[Rect2i], chest_cells: Array[Vector2i]) -> void:
	var vaults := FloorPuzzles.new(floor_number, _seed, _biome, _ground, _walls, _open, _field)
	vaults.hold(chest_cells, [] as Array[Rect2i])
	for cell: Vector2i in _taken:
		vaults.keep_clear(cell, 0)
	# A vault's size where any room has the rock for it; a hollow's where none has.
	for size: Vector2i in [FloorPuzzles.VAULT_ROOM, FloorPuzzles.HOLLOW]:
		for side in SIDES:
			for each in candidates:
				if vaults.pin_vault(each, side, size):
					_keep_hoard(vaults, each, side)
					return


## Takes the hoard [param vaults] just carved off [param each]'s [param side] wall,
## and stands its keeper two steps out in front of the door.
func _keep_hoard(vaults: FloorPuzzles, each: Rect2i, side: Vector2i) -> void:
	hoard = vaults.vault
	hoard_door = vaults.vault_door
	hoard_chest = vaults.vault_chest
	var front := _front_of(hoard_door, side, each)
	for out in [2, 3, 1]:
		var cell: Vector2i = front - side * out
		if each.has_point(cell) and _open.has(cell) and not _taken.has(cell):
			guard_cell = cell
			break
	if guard_cell.x < 0:
		guard_cell = front
	room = each
	kind = Kind.FIELD_BOSS


## The room cell in front of the left (or upper) half of [param door], off
## [param from]'s [param side] wall.
static func _front_of(door: Rect2i, side: Vector2i, from: Rect2i) -> Vector2i:
	match side:
		Vector2i.UP:
			return Vector2i(door.position.x, from.position.y)
		Vector2i.DOWN:
			return Vector2i(door.position.x, from.end.y - 1)
		Vector2i.LEFT:
			return Vector2i(from.position.x, door.position.y)
	return Vector2i(from.end.x - 1, door.position.y)


## The stranded player in the farthest room, with room round them, and the
## monsters that have them cornered a couple of steps off.
func _plan_stranded(candidates: Array[Rect2i]) -> void:
	for each in candidates:
		var cell := _spot(each, func(at: Vector2i) -> bool: return _clear(at, 1))
		if cell.x < 0:
			continue
		var ring: Array[Vector2i] = []
		for y in range(each.position.y + 1, each.end.y - 1):
			for x in range(each.position.x + 1, each.end.x - 1):
				var at := Vector2i(x, y)
				var off := (at - cell).abs()
				if maxi(off.x, off.y) in [2, 3] and _clear(at, 0):
					ring.append(at)
		var picked: Array[Vector2i] = []
		while picked.size() < BESIEGERS and not ring.is_empty():
			var pick: Vector2i = ring[_rng.randi() % ring.size()]
			ring.erase(pick)
			if picked.all(func(other: Vector2i) -> bool:
					return maxi(absi(other.x - pick.x), absi(other.y - pick.y)) >= 2):
				picked.append(pick)
		if picked.size() < BESIEGERS:
			continue
		stranded_cell = cell
		besieger_cells = picked
		room = each
		kind = Kind.ESCORT
		return


## The player killers wait in a room on the way from the arrival to
## [param route_to] -- halfway along it, where you have stopped expecting company
## -- or, if the way crosses none, in a room halfway out.
func _plan_ambush(candidates: Array[Rect2i], steps: Dictionary[Vector2i, int], entry: Rect2i,
		route_to: Vector2i) -> void:
	if candidates.is_empty():
		return
	var crossed: Array[Rect2i] = []
	var cell := route_to
	if steps.has(cell):
		while steps[cell] > 0:
			for each in candidates:
				if each.has_point(cell) and not each in crossed:
					crossed.push_front(each)
			var back := cell
			for step in STEPS:
				if steps.get(cell + step, 1 << 30) == steps[cell] - 1:
					back = cell + step
					break
			if back == cell:
				break
			cell = back
	room = crossed[crossed.size() / 2] if not crossed.is_empty() else candidates[candidates.size() / 2]
	kind = Kind.AMBUSH


# --- putting it down --------------------------------------------------------------

## Puts the event on [param map], once everything else is on it. [param plot] is
## the camp, [param gate_cell] the boss door's cell and [param lab] the labyrinth,
## in tiles.
func place(map: Node2D, plot: Rect2i, gate_cell: Vector2i, lab: Rect2i) -> void:
	if kind == Kind.NONE:
		return
	map.set_meta(&"event", kind)
	match kind:
		Kind.FIELD_BOSS:
			_place_hoard(map)
		Kind.ESCORT:
			_place_stranded(map, plot)
		Kind.AMBUSH:
			if not GameState.has_flag(flag(floor_number, "ambush")):
				var ambush := Ambush.new()
				ambush.name = "Ambush"
				ambush.floor_number = floor_number
				ambush.area = room
				map.add_child(ambush)
			map.set_meta(&"ambush", room)
		Kind.RACE:
			_place_rivals(map, plot, gate_cell, lab)


func _place_hoard(map: Node2D) -> void:
	var key := flag(floor_number, "boss")
	var pool := Bestiary.pool_for_floor(floor_number)
	var enemy: EnemyType = pool[_rng.randi() % pool.size()]
	var title := FIELD_BOSS_TITLES[_rng.randi() % FIELD_BOSS_TITLES.size()]
	var keeper := "%s %s" % [enemy.label(), title]
	var seal := SEAL_SCENE.instantiate()
	seal.name = "HoardSeal"
	seal.position = Vector2(hoard_door.position * TILE) + Vector2(hoard_door.size * TILE) / 2.0
	seal.set(&"display_name", "the hoard's door")
	seal.set(&"sigils", [key] as Array[StringName])
	seal.set(&"opened_flag", flag(floor_number, "hoard"))
	seal.set(&"opens_itself", true)
	seal.set(&"described", "A door of fitted stone, banded in old iron.")
	seal.set(&"hint", "There's a keyhole in it. Whatever stands guard out here carries the key -- the %s." % keeper)
	seal.set(&"opening_lines", PackedStringArray([
		"As the %s falls, a lock turns over in the stone behind it." % keeper,
		"The hoard is open.",
	]))
	map.add_child(seal)
	var chest := CHEST_SCENE.instantiate() as Chest
	chest.name = "ChestHoard"
	chest.position = _world(hoard_chest)
	chest.sealed = true
	chest.item_id = FloorPuzzles.SEALED_LOOT[_rng.randi() % FloorPuzzles.SEALED_LOOT.size()]
	chest.amount = 1
	chest.floor_number = floor_number
	chest.opened_flag = StringName("floor_%d_chest_hoard" % floor_number)
	map.add_child(chest)
	var boss := MONSTER_SCENE.instantiate()
	boss.name = "FieldBoss"
	boss.position = _world(guard_cell)
	boss.set(&"enemy", enemy)
	boss.set(&"level", FloorTuning.field_boss_level(floor_number))
	boss.set(&"floor_number", floor_number)
	boss.set(&"defeat_flag", key)
	boss.set(&"boss", true)
	boss.set(&"wander_radius", FIELD_BOSS_WANDER)
	boss.set(&"display_name", keeper)
	(boss.get_node("Sprite2D") as Sprite2D).self_modulate = FIELD_BOSS_TINT
	map.add_child(boss)
	var places: Dictionary[String, Rect2i] = map.get(&"landmarks")
	places["The Hoard"] = hoard
	map.set(&"landmarks", places)
	map.set_meta(&"hoard", hoard)
	map.set_meta(&"hoard_door", hoard_door)


func _place_stranded(map: Node2D, plot: Rect2i) -> void:
	var id := escort_quest(floor_number)
	map.set_meta(&"stranded", stranded_cell)
	if GameState.has_flag(QuestLog.flag_for(id, "done")):
		return
	var who := stranded(floor_number)
	var npc := ESCORTEE_SCENE.instantiate()
	npc.name = "Stranded"
	npc.position = _world(stranded_cell)
	npc.set(&"sprite_sheet", load(CHARACTERS % [who["sheet"], "SpriteSheet"]))
	npc.set(&"display_name", who["name"])
	npc.set(&"dialogue", escort_dialogue(floor_number))
	npc.set(&"floor_number", floor_number)
	npc.set(&"home", plot)
	map.add_child(npc)
	_unsolid(npc)
	var pool := Bestiary.pool_for_floor(floor_number)
	for i in besieger_cells.size():
		var monster := MONSTER_SCENE.instantiate()
		monster.name = "Besieger%d" % i
		monster.position = _world(besieger_cells[i])
		monster.set(&"enemy", pool[_rng.randi() % pool.size()])
		monster.set(&"level", FloorTuning.enemy_level(floor_number))
		monster.set(&"floor_number", floor_number)
		map.add_child(monster)


## The rival party stands in the camp until the race is run -- on a floor not yet
## cleared -- on a free cell with
## a free cell either side of it for the other two; the way they will walk is the
## shortest from there to the door, round anything standing.
func _place_rivals(map: Node2D, plot: Rect2i, gate_cell: Vector2i, lab: Rect2i) -> void:
	# A floor already cleared is nothing to race for -- unless it was this race
	# that cleared it, which the party settles as it arrives.
	if race_over(floor_number) or (GameState.is_floor_cleared(floor_number)
			and not GameState.has_flag(flag(floor_number, "race"))):
		return
	var solid := _solid_cells(map)
	var leader := Vector2i(-1, -1)
	var middle := _center(plot)
	var best := 1 << 30
	for y in range(plot.position.y + 1, plot.end.y - 1):
		for x in range(plot.position.x + 1, plot.end.x - 1):
			var cell := Vector2i(x, y)
			var off := (cell - middle).abs()
			if off.x + off.y >= best:
				continue
			var fits := true
			for dx in [-1, 0, 1]:
				var at: Vector2i = cell + Vector2i(dx, 0)
				if not plot.has_point(at) or not _walkable(at) or _near(solid, at, 1):
					fits = false
			if fits:
				best = off.x + off.y
				leader = cell
	if leader.x < 0:
		return
	var path := _path(leader, gate_cell, solid)
	if path.size() < 2:
		path = _path(leader, gate_cell, {} as Dictionary[Vector2i, bool])
	if path.size() < 2:
		return
	path.pop_back()
	var points := PackedVector2Array()
	var mouth := -1
	for i in path.size():
		points.append(_world(path[i]))
		if mouth < 0 and lab.has_point(path[i]):
			mouth = i
	var cast := rivals(floor_number)
	if not GameState.has_flag(flag(floor_number, "race")):
		var npc := NPC_SCENE.instantiate()
		npc.name = "RivalLeader"
		npc.position = _world(leader)
		npc.set(&"sprite_sheet", load(CHARACTERS % [cast["sheets"][0], "SpriteSheet"]))
		npc.set(&"display_name", cast["leader"])
		npc.set(&"dialogue", race_dialogue(floor_number))
		map.add_child(npc)
		_unsolid(npc)
	var party := RivalParty.new()
	party.name = "RivalParty"
	party.floor_number = floor_number
	party.path = points
	party.mouth_index = mouth
	var sheets: Array[Texture2D] = []
	for sheet: String in cast["sheets"]:
		sheets.append(load(CHARACTERS % [sheet, "SpriteSheet"]))
	party.sheets = sheets
	map.add_child(party)
	map.set_meta(&"rival_path", path)


## The shortest walk over floor -- no wall, nothing in [param avoid] -- from
## [param from] to [param to], both included; empty if there is none.
func _path(from: Vector2i, to: Vector2i, avoid: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var came: Dictionary[Vector2i, Vector2i] = {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		if cell == to:
			break
		for step in STEPS:
			var next := cell + step
			if came.has(next) or not (_walkable(next) or next == to) \
					or (avoid.has(next) and next != to):
				continue
			came[next] = cell
			queue.append(next)
	var path: Array[Vector2i] = []
	if not came.has(to):
		return path
	var at := to
	while at != from:
		path.push_front(at)
		at = came[at]
	path.push_front(from)
	return path


func _walkable(cell: Vector2i) -> bool:
	return _walls.get_cell_source_id(cell) == -1 and _ground.get_cell_source_id(cell) != -1


## Not solid: someone an event puts down must never be what walls a corridor off.
static func _unsolid(npc: Node) -> void:
	for shape in npc.get_node("Solid").get_children():
		(shape as CollisionShape2D).disabled = true


## The cells something solid stands on: anything with a [code]Solid[/code] body.
static func _solid_cells(map: Node2D) -> Dictionary[Vector2i, bool]:
	var cells: Dictionary[Vector2i, bool] = {}
	for child in map.get_children():
		if child is Node2D and child.has_node(^"Solid"):
			cells[Vector2i(((child as Node2D).position / TILE).floor())] = true
	return cells


static func _near(cells: Dictionary[Vector2i, bool], at: Vector2i, radius: int) -> bool:
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if cells.has(at + Vector2i(x, y)):
				return true
	return false


## What the camp's veteran says about it, filled in: where the room is from the
## camp, who is out there, who the rivals are.
func camp_words(plot: Rect2i) -> Dictionary:
	var words := {"side": "far", "name": "", "guild": "", "leader": ""}
	if room.has_area():
		var off := _center(room) - _center(plot)
		if absi(off.x) >= absi(off.y):
			words["side"] = "east" if off.x > 0 else "west"
		else:
			words["side"] = "south" if off.y > 0 else "north"
	words["name"] = stranded(floor_number)["name"]
	var cast := rivals(floor_number)
	words["guild"] = cast["guild"]
	words["leader"] = cast["leader"]
	return words


# --- the stream -----------------------------------------------------------------

## Who the event's people are on floor [param number], from its own stream, cached
## by seed as well as floor.
static func _cast(number: int) -> Dictionary:
	var generation_seed := FloorRegistry.seed_for(number)
	var key := "%d:%d" % [generation_seed, number]
	if _casts.has(key):
		return _casts[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:event_cast" % generation_seed)
	var first := rng.randi() % RIVAL_SHEETS.size()
	var cast := {
		"stranded": STRANDED_NAMES[rng.randi() % STRANDED_NAMES.size()],
		"stranded_sheet": STRANDED_SHEETS[rng.randi() % STRANDED_SHEETS.size()],
		"escort_gear": ESCORT_GEAR[rng.randi() % ESCORT_GEAR.size()],
		"guild": GUILDS[rng.randi() % GUILDS.size()],
		"leader": LEADERS[rng.randi() % LEADERS.size()],
		"rival_sheets": [RIVAL_SHEETS[first], RIVAL_SHEETS[(first + 3) % RIVAL_SHEETS.size()],
				RIVAL_SHEETS[(first + 5) % RIVAL_SHEETS.size()]],
		"prize": RACE_PRIZES[rng.randi() % RACE_PRIZES.size()],
		"pk": PLAYER_KILLERS[rng.randi() % PLAYER_KILLERS.size()],
	}
	_casts[key] = cast
	return cast


static func _has_escort(number: int) -> bool:
	return number >= 1 and number <= FloorTuning.TOP_FLOOR \
			and FloorRegistry.event_of(number) == Kind.ESCORT


## The floor in an [code]event_<n>_...[/code] id of [param parts] parts; 0 if none.
static func _floor_of(id: StringName, parts: int) -> int:
	var split := String(id).split("_")
	if split.size() != parts or split[0] != "event" or not split[1].is_valid_int():
		return 0
	return int(split[1])


## A monster of floor [param number]'s worth: its XP and its Col.
static func _worth(number: int) -> Dictionary:
	var pool := Bestiary.pool_for_floor(number)
	var level := FloorTuning.enemy_level(number)
	if pool.is_empty():
		return {"xp": 10, "col": FloorTuning.kill_col(number)}
	return {"xp": pool[0].xp_at(level), "col": pool[0].col_at(level)}


static func _line(text: String, conditions: Array[DialogueCondition]) -> DialogueLine:
	var line := DialogueLine.new()
	line.text = text
	line.conditions = conditions
	line.next = DialogueLine.END
	return line


static func _choice(text: String, conditions: Array[DialogueCondition],
		effects: Array[DialogueEffect]) -> DialogueChoice:
	var choice := DialogueChoice.new()
	choice.text = text
	choice.conditions = conditions
	choice.effects = effects
	choice.next = DialogueLine.END
	return choice


static func _effect(effect_kind: DialogueEffect.Kind, id: StringName, amount: int) -> DialogueEffect:
	var effect := DialogueEffect.new()
	effect.kind = effect_kind
	effect.id = id
	effect.amount = amount
	return effect


static func _quest_flag(id: StringName, suffix: String) -> DialogueCondition:
	var condition := DialogueCondition.new()
	condition.test = DialogueCondition.Test.FLAG_SET
	condition.flag = QuestLog.flag_for(id, suffix)
	return condition


static func _min_col(amount: int) -> DialogueCondition:
	var condition := DialogueCondition.new()
	condition.test = DialogueCondition.Test.MIN_COL
	condition.number = amount
	return condition


# --- plumbing ---------------------------------------------------------------

## Walking distance over carved floor from [param from], within the field.
func _walk_from(from: Vector2i) -> Dictionary[Vector2i, int]:
	var steps: Dictionary[Vector2i, int] = {from: 0}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for step in STEPS:
			var next := cell + step
			if not steps.has(next) and _open.has(next):
				steps[next] = steps[cell] + 1
				queue.append(next)
	return steps


static func _room_steps(steps: Dictionary[Vector2i, int], rect: Rect2i) -> int:
	var best := 1 << 20
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			best = mini(best, steps.get(Vector2i(x, y), 1 << 20))
	return best


## The cell of [param rect] nearest its middle that [param fits], or (-1, -1).
func _spot(rect: Rect2i, fits: Callable) -> Vector2i:
	var middle := _center(rect)
	var best := Vector2i(-1, -1)
	var best_off := 1 << 30
	for y in range(rect.position.y + 1, rect.end.y - 1):
		for x in range(rect.position.x + 1, rect.end.x - 1):
			var cell := Vector2i(x, y)
			var off := (cell - middle).abs()
			if off.x + off.y < best_off and fits.call(cell):
				best_off = off.x + off.y
				best = cell
	return best


func _clear(cell: Vector2i, radius: int) -> bool:
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var at := cell + Vector2i(x, y)
			if not _open.has(at) or _taken.has(at):
				return false
	return true


func _reserve(cell: Vector2i, radius: int) -> void:
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			_taken[cell + Vector2i(x, y)] = true


static func _center(rect: Rect2i) -> Vector2i:
	return rect.position + rect.size / 2


static func _world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)
