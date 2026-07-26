class_name Dialogue
extends Resource
## A conversation: an ordered array of [DialogueLine]s plus where to start.
##
## Saved as a [code].tres[/code] in [code]resources/dialogue/[/code] and handed to
## [code]DialogueRunner.start()[/code]. The array is the authoring unit -- lines
## run top to bottom unless a line jumps -- and ids are only needed by lines that
## something jumps to.
##
## Reactive dialogue falls out of [method entry_index]: when [member start] is
## empty the runner enters at the first line whose conditions pass, so an NPC
## greets you differently once you have met them, cleared their floor, or taken
## their quest. Put the most specific line first; end with an unconditional one
## so there is always something to say.

## Identifies the conversation on [EventBus] signals; also the natural key for
## "has the player heard this?" flags.
@export var id: StringName = &""
## Used by every line that does not name its own speaker.
@export var default_speaker := ""
## Shown for lines without their own portrait.
@export var default_portrait: Texture2D

@export var lines: Array[DialogueLine] = []
## Entry point. Empty means "first line whose conditions pass".
@export var start: StringName = &""


func index_of(line_id: StringName) -> int:
	if line_id == &"":
		return -1
	for i in lines.size():
		if lines[i] != null and lines[i].id == line_id:
			return i
	return -1


## Where this conversation begins right now, or -1 if it has nothing to say.
##
## Only the *start of a block* can be entered: a line that the previous line
## falls through into is a continuation, never a way in. Without that rule the
## second half of "Illfang's down." / "So bring me ore." would be a legal opening
## line the moment the first half's condition failed.
func entry_index() -> int:
	if start != &"":
		return index_of(start)
	for i in lines.size():
		if lines[i] == null:
			continue
		if i > 0 and lines[i - 1] != null and lines[i - 1].falls_through():
			continue
		if lines[i].is_available():
			return i
	return -1


func speaker_for(line: DialogueLine) -> String:
	return line.speaker if not line.speaker.is_empty() else default_speaker


func portrait_for(line: DialogueLine) -> Texture2D:
	return line.portrait if line.portrait != null else default_portrait


## Builds a throwaway linear conversation from plain strings -- the "You found a
## potion." path, where authoring a resource would be ceremony. See
## [code]DialogueRunner.say()[/code].
static func from_lines(speaker: String, texts: PackedStringArray) -> Dialogue:
	var dialogue := Dialogue.new()
	dialogue.id = &"adhoc"
	dialogue.default_speaker = speaker
	for text in texts:
		var line := DialogueLine.new()
		line.text = text
		dialogue.lines.append(line)
	return dialogue
