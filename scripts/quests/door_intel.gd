class_name DoorIntel
## Argo's trade: where a floor's boss door is, for Col.
##
## What she sells is the location, not the way. Buying a floor sets its
## [code]boss_found_<n>[/code] -- the flag walking into the boss room sets -- so
## the door stands visible, and when that floor's map is next built [GameMap]
## charts the boss room on **M** ([method GameMap._chart_found_doors]). The
## labyrinth between you and it is still unwalked, still dark, and still has its
## monsters in it: the purchase saves the hunting, not the walk.
##
## [b]The price is a floor's hunting[/b] -- every monster on it at its Col
## ([method price]) -- so it is for the floor you are tired of, not a toll you pay
## on every floor. She only sells floors you have stood on (that is how she knows
## you'll pay), never floor 1 (that one she gives away), never a door you have
## found or a floor you have cleared.
##
## Built in code, like [LocalQuests]' conversations: the offer is a [Dialogue] of
## ordinary lines, choices, MIN_COL conditions and TAKE_COL / SET_FLAG effects, so
## the runner gates and charges it with no new rules. Argo's menu queues it with a
## [code]SELL_INTEL[/code] effect.

## How many floors she offers at once: the highest first. The dialogue box has
## room for four choices and "Not today." is the fifth.
const OFFERS_SHOWN := 4
const PORTRAIT := "res://assets/ninja_adventure/Actor/Character/NinjaYellow/Faceset.png"


## What one floor's door costs: a floor's worth of kills on it.
static func price(floor_number: int) -> int:
	return FloorTuning.kill_col(floor_number) * FloorTuning.monster_count(floor_number)


## Whether she will sell [param floor_number]'s door right now.
static func on_offer(floor_number: int) -> bool:
	return floor_number > 1 and GameState.has_visited(floor_number) \
			and not GameState.is_floor_cleared(floor_number) \
			and not GameState.has_flag(BossGate.found_flag(floor_number))


## The floors on offer, highest first, at most [constant OFFERS_SHOWN].
static func offers() -> Array[int]:
	var floors: Array[int] = []
	var visited := GameState.visited_floors()
	visited.reverse()
	for n in visited:
		if on_offer(n):
			floors.append(n)
		if floors.size() >= OFFERS_SHOWN:
			break
	return floors


## The boss behind [param floor_number]'s door, as the floor names it.
static func boss_of(floor_number: int) -> String:
	var definition := FloorRegistry.get_floor(floor_number)
	return definition.boss_name if definition != null and not definition.boss_name.is_empty() \
			else FloorTuning.boss_name(floor_number)


## Her pitch, built for what is on offer now.
static func conversation() -> Dialogue:
	var talk := Dialogue.new()
	talk.id = &"argo_intel"
	talk.default_speaker = "Argo"
	talk.default_portrait = load(PORTRAIT)
	var floors := offers()
	if floors.is_empty():
		talk.lines.append(_line(&"none",
				"Doors? Every one you've been near, you've already found. Go stand on a new floor."))
		return talk

	var pitch := _line(&"pitch", "Doors, kiddo. I know where they are. You know what that's worth.")
	var choices: Array[DialogueChoice] = []
	var sold: Array[DialogueLine] = []
	for n in floors:
		var cost := price(n)
		var choice := DialogueChoice.new()
		choice.text = "Floor %d's door. (%d col)" % [n, cost]
		choice.next = StringName("sold_%d" % n)
		var afford := DialogueCondition.new()
		afford.test = DialogueCondition.Test.MIN_COL
		afford.number = cost
		var gates: Array[DialogueCondition] = [afford]
		choice.conditions = gates
		choice.hide_when_locked = false
		choice.locked_hint = "(%d col -- you're short)" % cost
		var charge := DialogueEffect.new()
		charge.kind = DialogueEffect.Kind.TAKE_COL
		charge.amount = cost
		var found := DialogueEffect.new()
		found.kind = DialogueEffect.Kind.SET_FLAG
		found.id = BossGate.found_flag(n)
		var effects: Array[DialogueEffect] = [charge, found]
		choice.effects = effects
		choices.append(choice)
		sold.append(_line(choice.next, ("Floor %d. %s keeps the door at the heart of the maze. "
				+ "It's on your map now -- getting through to it is your problem.") % [n, boss_of(n)]))
	var leave := DialogueChoice.new()
	leave.text = "Not today."
	leave.next = DialogueLine.END
	choices.append(leave)
	pitch.choices = choices
	talk.lines.append(pitch)
	talk.lines.append_array(sold)
	return talk


static func _line(id: StringName, text: String) -> DialogueLine:
	var line := DialogueLine.new()
	line.id = id
	line.text = text
	line.next = DialogueLine.END
	return line
