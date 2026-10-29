class_name FinalBoss
## What is said at the top of the Ruby Palace, around the last fight.
##
## The boss on floor 100 is Hisukurifu -- the game's own developer, in the avatar
## Heathcliff's name became when it was read out in Japanese -- and he knows it is
## a game. What he says before, after and between his bars reads the player's own
## run (their name, level, time played, how they chose to play), so it is built in
## code rather than written as a [Dialogue] .tres; the lines he says as each bar
## breaks are [BossPhase] data on [code]resources/enemies/hisukurifu.tres[/code].
##
## [BossGate] asks for these on the top floor and nowhere else. Nothing here
## decides anything: the fight is an ordinary boss fight, and clearing the game is
## clearing floor 100 ([method GameState.is_floor_cleared]).

const SPEAKER := "Hisukurifu"
const PORTRAIT := "res://assets/ninja_adventure/Actor/Character/Master/Faceset.png"
## Who speaks for the system. In SAO the announcement after the last boss has no
## face and no name; here it is Cardinal's, as the idle logout is.
const SYSTEM := "Cardinal"
## What he is called until you have stood in front of him. SAO never named its last
## boss in advance -- the name is the reveal -- so the door, the camp and Argo don't
## either.
const UNMET := "???"
## Set as his opening words end: from then on he has a name.
const MET_FLAG := &"final_boss_met"


static func is_final(floor_number: int) -> bool:
	return floor_number >= FloorTuning.TOP_FLOOR


## His name if you have met him, [constant UNMET] if not.
static func known_name() -> String:
	return SPEAKER if GameState.has_flag(MET_FLAG) else UNMET


## Before the door: what he has to say about the run that got you here. Said every
## time you challenge him, shorter once you have heard it.
static func prelude() -> Dialogue:
	var lines: Array = []
	if GameState.has_flag(MET_FLAG):
		lines.append_array([
			["", "Hisukurifu is where you left him."],
			[SPEAKER, "Back already? Level %d. Good -- the respawn works. I tested it." % GameState.level],
			[SPEAKER, "Same rules as before. No flee button, four bars. Come on, then."],
		])
		return _dialogue(&"final_boss_again", lines)
	lines.append_array([
		["", "The last door of the Ruby Palace opens onto a quiet hall."],
		["", "A man in red and white waits in it, a cross shield at his side. The name over his head reads Hisukurifu, and the cursor under it is neither a monster's nor a player's."],
		[SPEAKER, "Welcome to floor 100, %s. Level %d." % [GameState.player_name, GameState.level]],
		[SPEAKER, "You were expecting a dragon. Sorry. The art pack only had so many, and I wanted this one to be me."],
		[SPEAKER, "I made this place. Every floor, every boar on floor 2, every chest that turned out to be a trap. Hisukurifu is just the avatar I wear to come in and look around."],
		[SPEAKER, _how_you_played()],
		[SPEAKER, "Honestly, I wrote this floor last, and I was never sure anyone would test it this far. So thank you. Now let's see what you learned."],
		[SPEAKER, "There's no flee button on this one. I took it out."],
	])
	var dialogue := _dialogue(&"final_boss", lines)
	dialogue.lines[-1].effects.append(_flag(MET_FLAG))
	return dialogue


## After the last bar: his last words, and the system's announcement.
static func farewell() -> Dialogue:
	return _dialogue(&"final_boss_farewell", [
		["", "The placeholder that was Hisukurifu flickers, and for a moment it is a man in red and white again."],
		[SPEAKER, "...Huh. You did it."],
		[SPEAKER, "Good. A boss nobody beats is just a wall, and I didn't build a hundred floors to end on a wall."],
		[SPEAKER, "%s of your life in a world I made. I don't really know how to thank you for that, %s. So: thank you." % [_sentence(time_played()), GameState.player_name]],
		[SPEAKER, "Go on. The castle's yours now."],
		[SYSTEM, "%s: the game has been cleared." % Time.get_time_string_from_system().substr(0, 5)],
		[SYSTEM, "All players will now be logged out, in sequence."],
	])


## What you hear coming to at the entrance after he beats you.
static func defeat_lines() -> PackedStringArray:
	return PackedStringArray([
		"Hisukurifu lowers his sword. \"Respawn. I'll be here -- I'm hardcoded to be.\"",
		"You come to at the entrance to the floor, barely.",
	])


## The epilogue, over white, before the credits roll.
static func epilogue() -> PackedStringArray:
	var how := "in %s" % time_played()
	return PackedStringArray([
		"Aincrad, floor 100. The game has been cleared.",
		"%s reached the top of the castle %s, at level %d." % [GameState.player_name, how, GameState.level],
		"Somewhere below, the camps you passed are villages now. The people in them stopped climbing a long time ago, and they are going home.",
		"The castle is still there. It will be there when you come back.",
	])


## How long the run took, in words: "a minute", "40 minutes", "3 hours and 5 minutes".
## [BossPhase] fills [code]{time}[/code] with it.
static func time_played() -> String:
	var minutes := maxi(1, int(GameState.play_time / 60.0))
	if minutes < 60:
		return _count(minutes, "minute")
	if minutes % 60 == 0:
		return _count(minutes / 60, "hour")
	return "%s and %s" % [_count(minutes / 60, "hour"), _count(minutes % 60, "minute")]


## "a minute", "3 minutes".
static func _count(n: int, unit: String) -> String:
	if unit == "hour" and n == 1:
		return "an hour"
	return "a %s" % unit if n == 1 else "%d %ss" % [n, unit]


## His word on the way the run was played ([enum GameState.Mode]).
static func _how_you_played() -> String:
	match GameState.mode:
		GameState.Mode.HARDCORE:
			return "Hardcore, too. If you lose, I delete your save -- that isn't a threat, it's a few lines in save_game.gd. I'd rather not use them."
		GameState.Mode.MARATHON:
			return "And a marathon. No saves, all in one sitting. Don't go idle on me now; Cardinal is watching even here."
	return "%s on the clock, and a save somewhere behind you. Good. You may want it." % _sentence(time_played())


## [param text] with its first letter a capital, for a sentence it starts.
static func _sentence(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


static func _dialogue(id: StringName, lines: Array) -> Dialogue:
	var dialogue := Dialogue.new()
	dialogue.id = id
	var face := load(PORTRAIT) as Texture2D
	for entry: Array in lines:
		var line := DialogueLine.new()
		line.speaker = entry[0]
		line.text = entry[1]
		if entry[0] == SPEAKER:
			line.portrait = face
		dialogue.lines.append(line)
	return dialogue


static func _flag(flag: StringName) -> DialogueEffect:
	var effect := DialogueEffect.new()
	effect.kind = DialogueEffect.Kind.SET_FLAG
	effect.id = flag
	return effect
