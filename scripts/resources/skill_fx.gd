class_name SkillFx
extends Resource
## How a blow looks where it lands: one of the pack's effect sheets, played once
## over whoever it hits.
##
## Pure presentation, like [member Skill.announce]. Combat never reads it; the
## view that draws the fight does ([code]ui/battle_stage.gd[/code]). One sheet
## is shared by every skill that looks alike, so the effects live in
## [code]resources/fx/[/code] and a skill points at one.

## Frames side by side, evenly spaced, one row.
@export var sheet: Texture2D
@export var frames := 4
@export var frame_time := 0.06
## The pack draws its cuts and claws sweeping one way. Mirrored when the blow
## travels the other, so a slash always follows the swing.
@export var follows_swing := true
