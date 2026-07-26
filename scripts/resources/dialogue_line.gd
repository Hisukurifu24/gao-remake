class_name DialogueLine
extends Resource
## A single beat of a conversation: one speaker, one box of text, and how to
## leave it.
##
## Flow, in order of precedence:
##   - [member choices] non-empty -> the player picks, and the choice says where to go.
##   - [member next] set          -> jump to that line id ([constant END] finishes).
##   - otherwise                  -> fall through to the next line in the array.
##
## Fall-through is why a linear conversation needs no ids at all: drop lines in
## the array in order and the last one ends it.

## Reserved [member next] value meaning "close the box".
const END := &"end"

## Jump target. Only lines that are jumped to (or condition-gated entry points)
## need one.
@export var id: StringName = &""
## Overrides the dialogue's default speaker. Leave empty for narration.
@export var speaker := ""
@export_multiline var text := ""
@export var portrait: Texture2D

@export_group("Flow")
@export var next: StringName = &""
@export var choices: Array[DialogueChoice] = []

@export_group("Availability")
## Checked only when this line is a candidate *entry point* (see
## [method Dialogue.entry_index]). A line reached by an explicit jump always plays.
@export var conditions: Array[DialogueCondition] = []

@export_group("Result")
## Applied when the line is shown, before the player reads it.
@export var effects: Array[DialogueEffect] = []


func is_available() -> bool:
	return DialogueCondition.all_met(conditions)


## True when this line simply runs on into the next one -- no jump, no ending,
## no choices. [method Dialogue.entry_index] uses this to tell where one block of
## conversation ends and the next begins.
func falls_through() -> bool:
	return next == &"" and choices.is_empty()


## Choices worth drawing: locked ones survive only if they asked to be seen.
func listed_choices() -> Array[DialogueChoice]:
	var listed: Array[DialogueChoice] = []
	for choice in choices:
		if choice != null and choice.is_listed():
			listed.append(choice)
	return listed
