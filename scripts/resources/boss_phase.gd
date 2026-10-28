class_name BossPhase
extends Resource
## One more HP bar on a boss, and what it fights like once it is down to it.
##
## SAO draws a boss's health as stacked bars, and the fight changes when one
## empties -- Illfang throws away his axe and buckler on the last. A boss whose
## [EnemyType] lists [member EnemyType.phases] has that many bars more than one,
## its HP shared evenly between them ([method EnemyType.bars]), so adding a phase
## moves its total HP nowhere. When a bar empties, [CombatManager] starts the next
## phase on a full one: whatever is set here changes, whatever is left empty
## stays as it was.
##
## Pure data, like a [Skill]: the runner applies it ([method Combatant.enter_phase]),
## the stage draws it, and an empty phase is just one more bar to cut through.

## What it is called from this bar on. Empty keeps the name.
@export var display_name := ""
## The shape it takes, read for its look alone -- [member EnemyType.battler],
## [member EnemyType.sheet], [member EnemyType.idle_frames] and
## [member EnemyType.strike_fx]. Null keeps the look it has.
@export var form: EnemyType
## Its moves from this bar on, in place of the previous bar's. Empty keeps them.
## A boss's own [constant Bestiary.BOSS_SKILL] is kept either way.
@export var skills: Array[Skill] = []
## How often it reaches for one of them; below 0 keeps it.
@export_range(-1.0, 1.0) var skill_bias := -1.0

@export_group("Stats")
## Multipliers on the stats it came into the fight with -- not on the last bar's.
@export var attack_scale := 1.0
@export var defense_scale := 1.0
@export var speed_scale := 1.0

@export_group("Entering it")
## Told as the bar breaks, before anyone speaks: what you see, not what is said.
@export_multiline var narration: PackedStringArray = []
## Said as the bar breaks, in a box over the fight, one line a page. Both may use
## [code]{player}[/code], [code]{level}[/code], [code]{floor}[/code],
## [code]{hours}[/code], [code]{minutes}[/code] and [code]{seed}[/code] ([method spoken]).
@export_multiline var lines: PackedStringArray = []
## Who says them.
@export var speaker := ""
@export var portrait: Texture2D
## Put on itself as the bar starts -- a guard, a haste.
@export var buff: StatusEffect
## Swung the moment the bar starts, out of turn: the new phase announces itself.
@export var opens_with: Skill
## The fight's music from this bar on ([MusicLibrary]); empty keeps it.
@export var music: StringName = &""


## What is shown as the bar breaks, as a conversation: [member narration], then
## [member lines] in [member speaker]'s voice. Null when there is nothing to show.
func interlude() -> Dialogue:
	if narration.is_empty() and lines.is_empty():
		return null
	var dialogue := Dialogue.new()
	dialogue.id = &"boss_phase"
	for text in _filled(narration):
		var told := DialogueLine.new()
		told.text = text
		dialogue.lines.append(told)
	for text in _filled(lines):
		var said := DialogueLine.new()
		said.text = text
		said.speaker = speaker
		said.portrait = portrait
		dialogue.lines.append(said)
	return dialogue


## [param texts] with the player's own numbers in them.
func _filled(texts: PackedStringArray) -> PackedStringArray:
	var minutes := int(GameState.play_time / 60.0)
	var keys := {
		"player": GameState.player_name,
		"level": GameState.level,
		"floor": GameState.current_floor,
		"hours": minutes / 60,
		"minutes": minutes % 60,
		"seed": GameState.world_seed,
	}
	var out := PackedStringArray()
	for text in texts:
		out.append(text.format(keys))
	return out
