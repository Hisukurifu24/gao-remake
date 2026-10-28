class_name Weather
extends Node2D
## A storm over the map ([FloorModifier]): what falls, and the haze it falls
## through -- the pack's rain and its splashes, its snowflakes (drawn again as blown
## sand and as ash), and its fog.
##
## View only: the storm's rule is [member GameMap.notice_scale], and nothing here is
## read by anything. Over everything on the map but the dark: you see the storm
## where you can see, and a labyrinth's black stays black. It keeps itself over whatever
## camera is current, the player's or a fight's, so the weather never runs out at
## the edge of a view; what has already fallen stays where it fell in the world.
## And it is heard: the pack's rain or wind, looping on the Sounds bus for as long
## as the map is up.

const RAIN := preload("res://assets/ninja_adventure/FX/Particle/Rain.png")
const SPLASH := preload("res://assets/ninja_adventure/FX/Particle/RainOnFloor.png")
const FLAKES := preload("res://assets/ninja_adventure/FX/Particle/Snow.png")
const FOG := preload("res://assets/ninja_adventure/FX/Environment/Fog.png")

## Each weather: the map's tint under it, what falls ([code]sheet[/code] and its
## frames, drawn in [code]colour[/code]) -- along [code]fall[/code] at
## [code]speed[/code] px/s, [code]amount[/code] at once, each for
## [code]life[/code] seconds -- whether rain splashes, and the haze's colour and
## drift in px/s -- and what it sounds like, a looping file under
## [constant SoundLibrary.ROOT] at [code]db[/code].
const LOOKS := {
	&"rain": {
		"tint": Color(0.76, 0.8, 0.9), "sheet": "rain", "frames": 3,
		"colour": Color(0.85, 0.9, 1.0, 0.75), "fall": Vector2(-0.45, 1.0),
		"speed": Vector2(230, 270), "amount": 110, "life": 0.65, "splash": true,
		"haze": Color(0.8, 0.85, 0.95, 0.22), "drift": Vector2(-10, 4),
		"sound": "Sounds/Ambient/Rain2.wav", "db": -8.0,
	},
	&"snow": {
		"tint": Color(0.9, 0.93, 1.0), "sheet": "flakes", "frames": 7,
		"colour": Color(0.78, 0.85, 1.0, 0.95), "fall": Vector2(1.0, 0.55),
		"speed": Vector2(70, 110), "amount": 170, "life": 3.5, "splash": false,
		"haze": Color(1, 1, 1, 0.26), "drift": Vector2(36, 8),
		"sound": "Sounds/Ambient/Wind.wav", "db": -6.0,
	},
	&"sand": {
		"tint": Color(1.0, 0.88, 0.72), "sheet": "flakes", "frames": 7,
		"colour": Color(0.95, 0.8, 0.55, 0.85), "fall": Vector2(1.0, 0.12),
		"speed": Vector2(170, 230), "amount": 130, "life": 2.0, "splash": false,
		"haze": Color(0.95, 0.78, 0.5, 0.42), "drift": Vector2(70, 2),
		"sound": "Sounds/Ambient/Wind2.wav", "db": -6.0,
	},
	&"ash": {
		"tint": Color(0.82, 0.74, 0.72), "sheet": "flakes", "frames": 7,
		"colour": Color(0.78, 0.74, 0.72, 0.9), "fall": Vector2(0.25, 1.0),
		"speed": Vector2(16, 30), "amount": 180, "life": 7.0, "splash": false,
		"haze": Color(0.35, 0.25, 0.22, 0.25), "drift": Vector2(6, 3),
		"sound": "Sounds/Ambient/Wind.wav", "db": -14.0,
	},
}
## Over everything on the map but the dark ([Darkness] is 10).
const Z := 9
## How far past the view the weather reaches, so a moving camera never outruns it.
const MARGIN := 48.0

var kind: StringName = &""
var _haze: Sprite2D = null
var _drift := Vector2.ZERO
var _drifted := Vector2.ZERO
var _falling: CPUParticles2D = null
var _splashes: CPUParticles2D = null


## The map's tint under [param weather]: multiplied into its ambient one.
static func tint(weather: StringName) -> Color:
	return LOOKS[weather]["tint"] if LOOKS.has(weather) else Color.WHITE


## Builds the storm's pieces. Needs no tree: the generator calls it.
func setup(weather: StringName) -> void:
	kind = weather
	name = "Weather"
	z_index = Z
	var look: Dictionary = LOOKS.get(weather, LOOKS[&"rain"])
	_haze = Sprite2D.new()
	_haze.name = "Haze"
	_haze.texture = FOG
	_haze.centered = false
	_haze.region_enabled = true
	_haze.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_haze.modulate = look["haze"]
	_drift = look["drift"]
	add_child(_haze)
	_falling = _particles("Falling", RAIN if look["sheet"] == "rain" else FLAKES, look["frames"])
	_falling.amount = look["amount"]
	_falling.lifetime = look["life"]
	_falling.preprocess = look["life"]
	_falling.direction = look["fall"]
	_falling.spread = 4.0
	_falling.initial_velocity_min = look["speed"].x
	_falling.initial_velocity_max = look["speed"].y
	_falling.color = look["colour"]
	# A raindrop is drawn as it falls, short to long; a flake is any of the sheet's.
	if look["sheet"] == "rain":
		_falling.anim_speed_min = 1.0
		_falling.anim_speed_max = 1.0
	else:
		_falling.anim_offset_max = 1.0
	# Fading in and out, so nothing pops into the air or out of it.
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color.WHITE)
	fade.add_point(0.85, Color.WHITE)
	_falling.color_ramp = fade
	if look["splash"]:
		_splashes = _particles("Splashes", SPLASH, 3)
		_splashes.amount = 40
		_splashes.lifetime = 0.35
		_splashes.direction = Vector2.DOWN
		_splashes.spread = 0.0
		_splashes.initial_velocity_min = 0.0
		_splashes.initial_velocity_max = 0.0
		_splashes.anim_speed_min = 1.0
		_splashes.anim_speed_max = 1.0
		_splashes.color = Color(0.85, 0.9, 1.0, 0.6)
	# Plays once the map is in the tree, and stops with it.
	var sound := AudioStreamPlayer.new()
	sound.name = "Sound"
	sound.stream = load(SoundLibrary.ROOT + str(look["sound"])) as AudioStream
	sound.volume_db = look["db"]
	sound.bus = &"Sounds"
	sound.autoplay = true
	add_child(sound)


func _particles(node_name: String, sheet: Texture2D, frames: int) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.name = node_name
	particles.texture = sheet
	var material := CanvasItemMaterial.new()
	material.particles_animation = true
	material.particles_anim_h_frames = frames
	material.particles_anim_v_frames = 1
	material.particles_anim_loop = false
	particles.material = material
	particles.gravity = Vector2.ZERO
	# What has fallen stays where it fell in the world as the view moves on.
	particles.local_coords = false
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(particles)
	return particles


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var view := get_viewport_rect().size / camera.zoom
	var centre := to_local(camera.get_screen_center_position())
	var reach := view / 2.0 + Vector2(MARGIN, MARGIN)
	for particles: CPUParticles2D in [_falling, _splashes]:
		if particles == null:
			continue
		particles.position = centre
		particles.emission_rect_extents = reach
	# The haze is anchored in the world and drifts through it, so it doesn't slide
	# along with the player.
	_drifted += _drift * delta
	_haze.position = (centre - reach).floor()
	_haze.region_rect = Rect2(_haze.position - _drifted.floor(), reach * 2.0)
