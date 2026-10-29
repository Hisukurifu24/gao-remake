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
## [code]{hours}[/code], [code]{minutes}[/code], [code]{time}[/code] (the two in words,
## [method FinalBoss.time_played]) and [code]{seed}[/code] ([method spoken]).
@export_multiline var lines: PackedStringArray = []
## Who says them.
@export var speaker := ""
@export var portrait: Texture2D
## Put on itself as the bar starts -- a guard, a haste.
@export var buff: StatusEffect
## Swung the moment the bar starts, out of turn: the new phase announces itself.
@export var opens_with: Skill
## Swung by the shape it is leaving as the last bar empties, before this one
## takes over -- a parting shot. What it costs the user ([member Skill.post_motion])
## carries into this bar: a spell that takes everything leaves the next shape spent.
@export var parting: Skill
## The fight's music from this bar on ([MusicLibrary]); empty keeps it.
@export var music: StringName = &""
## Seconds the change takes on the stage, for a bar that should land: above 0,
## the old shape takes the blow and flickers in silence while [member narration]
## is read, then washes out to white and the new one comes back out of it over
## this long, its name and its music with it, before it says [member lines]. 0 is
## the quick flare every other boss gets, the shape changing under it at once.
@export_range(0.0, 10.0) var hold := 0.0


## What is shown as the bar breaks, as a conversation: [member narration], then
## [member lines] in [member speaker]'s voice. Null when there is nothing to show.
func interlude() -> Dialogue:
	return _conversation(true, true)


## [member narration] alone, or null: what a held change ([member hold]) shows
## before the new shape arrives.
func told() -> Dialogue:
	return _conversation(true, false)


## [member lines] alone, or null: what the new shape says once it has arrived.
func said() -> Dialogue:
	return _conversation(false, true)


func _conversation(with_narration: bool, with_lines: bool) -> Dialogue:
	var dialogue := Dialogue.new()
	dialogue.id = &"boss_phase"
	if with_narration:
		for text in _filled(narration):
			var told_line := DialogueLine.new()
			told_line.text = text
			dialogue.lines.append(told_line)
	if with_lines:
		for text in _filled(lines):
			var said_line := DialogueLine.new()
			said_line.text = text
			said_line.speaker = speaker
			said_line.portrait = portrait
			dialogue.lines.append(said_line)
	return dialogue if not dialogue.lines.is_empty() else null


## [param texts] with the player's own numbers in them.
func _filled(texts: PackedStringArray) -> PackedStringArray:
	var minutes := int(GameState.play_time / 60.0)
	var keys := {
		"player": GameState.player_name,
		"level": GameState.level,
		"floor": GameState.current_floor,
		"hours": minutes / 60,
		"minutes": minutes % 60,
		"time": FinalBoss.time_played(),
		"seed": GameState.world_seed,
	}
	var out := PackedStringArray()
	for text in texts:
		out.append(text.format(keys))
	return out
