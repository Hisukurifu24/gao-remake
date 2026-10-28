extends Node
## What the game sounds like: the music, the sound effects and the jingles.
##
## A view, like the HUD: nothing in the game reads anything here, and a game
## with no sound plays exactly the same. Most of it is heard off [EventBus] --
## a level gained, a quest taken, a door found, a fight begun and how it ended --
## so the systems that announce those never learn there is a speaker. Things only
## a node knows about (a lid opening, a wall breaking, a cursor moving) call
## [method play] themselves, by id; [SoundLibrary] says what each id is.
##
## **Music is chosen by place, then by fight.** [GameMap] says where the player
## stands ([signal EventBus.map_area_entered]) and [MusicLibrary] turns that into
## a track; a fight plays its own over it until it is finished, and the place's
## track comes back where it left off. The title plays its own. Two decks
## crossfade, so nothing ever cuts.
##
## **Jingles take turns.** One plays at a time and the music ducks under it; a
## jingle asked for while another plays waits, and one already waiting isn't
## queued twice. A level gained in a fight waits for the fight's own fanfare.
##
## Volumes are the buses' ([code]default_bus_layout.tres[/code]: Music and
## Sounds under Master), set by [Settings]; nothing here knows the player's
## levels.

## Something was played -- for tests, which can't hear.
signal played(id: StringName)

const MUSIC_BUS := &"Music"
const SOUND_BUS := &"Sounds"
## Sounds at once. A ninth asked for steals the oldest.
const VOICES := 8
## The same sound twice inside this many milliseconds is one sound: a fight's
## three hits landing together, every monster on a floor noticing at once.
const SAME_SOUND_MS := 60
## How long a place's track takes to cross into the next.
const FADE := 1.0
## A fight cuts in quicker than a walk changes the music, and goes out slower.
const FIGHT_IN := 0.35
const FIGHT_OUT := 1.6
## The music's level under a jingle.
const DUCK := 0.25
const DUCK_TIME := 0.15
## The most jingles waiting at once: a debug start that levels through twenty
## levels in one frame doesn't play twenty fanfares.
const QUEUE := 3

var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _last_played: Dictionary[StringName, int] = {}

var _decks: Array[AudioStreamPlayer] = []
var _deck := 0
## Each deck's level, 0-1, before the duck.
var _levels: Array[float] = [0.0, 0.0]
var _duck := 1.0
var _fade: Tween = null
var _duck_tween: Tween = null
var _track: StringName = &""
## Where each track was left, so the place's music comes back after a fight
## where it stopped rather than from the top.
var _left_at: Dictionary[StringName, float] = {}
## What the place wants, and what the fight wants over it (empty: no fight).
var _place_track: StringName = &""
var _fight_track: StringName = &""
var _fight_encounter: Encounter = null

var _jingle: AudioStreamPlayer = null
var _jingle_id: StringName = &""
var _waiting: Array[StringName] = []
## Jingles held until the fight's own is under way.
var _after_fight: Array[StringName] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = SOUND_BUS
		add_child(voice)
		_voices.append(voice)
	for i in 2:
		var deck := AudioStreamPlayer.new()
		deck.bus = MUSIC_BUS
		deck.volume_db = linear_to_db(0.0)
		add_child(deck)
		_decks.append(deck)
	_jingle = AudioStreamPlayer.new()
	_jingle.bus = SOUND_BUS
	_jingle.finished.connect(_on_jingle_finished)
	add_child(_jingle)

	EventBus.map_area_entered.connect(_on_map_area_entered)
	EventBus.title_requested.connect(_on_title_requested)
	EventBus.leveled_up.connect(_on_leveled_up)
	EventBus.quest_accepted.connect(func(_id: StringName) -> void: play(&"quest_accepted"))
	EventBus.quest_completed.connect(func(_id: StringName) -> void: play(&"quest_done"))
	EventBus.boss_room_found.connect(func(_floor: int) -> void: play(&"secret"))
	EventBus.col_granted.connect(_on_col_granted)
	EventBus.item_used.connect(_on_item_used)
	EventBus.inventory_full.connect(func(_id: StringName, _lost: int) -> void: play(&"refuse"))
	EventBus.item_enhanced.connect(func(_id: StringName, _plus: int) -> void: play(&"forge"))
	EventBus.game_saved.connect(_on_game_saved)
	EventBus.combat_fled.connect(func() -> void: play(&"flee"))
	EventBus.idle_countdown.connect(_on_idle_countdown)
	EventBus.avatar_logged_out.connect(_on_logged_out)
	CombatManager.combat_began.connect(_on_combat_began)
	CombatManager.combat_finished.connect(_on_combat_finished)


func _process(_delta: float) -> void:
	for i in _decks.size():
		_decks[i].volume_db = linear_to_db(maxf(_levels[i] * _duck, 0.0001))


# --- sounds ------------------------------------------------------------------

## Plays the sound or jingle [param id] ([SoundLibrary]). An id that isn't there
## warns and plays nothing.
func play(id: StringName) -> void:
	if not SoundLibrary.has(id):
		push_warning("Audio: no sound called '%s'" % id)
		return
	if SoundLibrary.is_jingle(id):
		_queue_jingle(id)
		return
	var now := Time.get_ticks_msec()
	if _last_played.has(id) and now - _last_played[id] < SAME_SOUND_MS:
		return
	_last_played[id] = now
	var voice := _free_voice()
	voice.stream = SoundLibrary.stream(id)
	voice.volume_db = SoundLibrary.volume_db(id)
	var spread := SoundLibrary.pitch_spread(id)
	voice.pitch_scale = 1.0 + randf_range(-spread, spread) if spread > 0.0 else 1.0
	voice.play()
	played.emit(id)


## A voice with nothing in it, or else the one that started longest ago.
func _free_voice() -> AudioStreamPlayer:
	for i in _voices.size():
		var voice := _voices[(_next_voice + i) % _voices.size()]
		if not voice.playing:
			_next_voice = (_next_voice + i + 1) % _voices.size()
			return voice
	var oldest := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	return oldest


# --- jingles -----------------------------------------------------------------

func _queue_jingle(id: StringName) -> void:
	if _jingle.playing or not _jingle_id.is_empty():
		if id != _jingle_id and id not in _waiting and _waiting.size() < QUEUE:
			_waiting.append(id)
		return
	_start_jingle(id)


func _start_jingle(id: StringName) -> void:
	_jingle_id = id
	_jingle.stream = SoundLibrary.stream(id)
	_jingle.volume_db = SoundLibrary.volume_db(id)
	_jingle.play()
	_duck_to(DUCK)
	played.emit(id)


func _on_jingle_finished() -> void:
	_jingle_id = &""
	if not _waiting.is_empty():
		_start_jingle(_waiting.pop_front())
		return
	_duck_to(1.0)


## The jingle playing now, or empty.
func jingle_playing() -> StringName:
	return _jingle_id


func _duck_to(level: float) -> void:
	if _duck_tween != null:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(self, "_duck", level, DUCK_TIME)


# --- music -------------------------------------------------------------------

## The track playing (or fading in) now, or empty for silence.
func current_track() -> StringName:
	return _track


## Crosses into [param id] over [param seconds]; empty fades to silence. The
## track it leaves is remembered where it stopped.
func play_music(id: StringName, seconds := FADE) -> void:
	if id == _track:
		return
	var old := _decks[_deck]
	if not _track.is_empty() and old.playing and not MusicLibrary.is_fight(_track):
		_left_at[_track] = old.get_playback_position()
	_track = id
	_deck = 1 - _deck
	var new := _decks[_deck]
	new.stop()
	if not id.is_empty():
		new.stream = MusicLibrary.stream(id)
		var from := _left_at.get(id, 0.0) as float
		new.play(from if new.stream != null and from < new.stream.get_length() else 0.0)
	if _fade != null:
		_fade.kill()
	var into := _deck
	var start_in := _levels[into]
	var start_out := _levels[1 - into]
	var cross := func(t: float) -> void:
		_levels[into] = lerpf(start_in, 0.0 if id.is_empty() else 1.0, t)
		_levels[1 - into] = lerpf(start_out, 0.0, t)
	if seconds <= 0.0:
		cross.call(1.0)
		old.stop()
		return
	_fade = create_tween()
	_fade.tween_method(cross, 0.0, 1.0, seconds)
	_fade.tween_callback(old.stop)


## What should be playing: the fight's track over the place's.
func _refresh_music(seconds: float) -> void:
	play_music(_fight_track if not _fight_track.is_empty() else _place_track, seconds)


func _on_map_area_entered(map: Node, area: StringName) -> void:
	var game_map := map as GameMap
	if game_map == null:
		return
	_place_track = MusicLibrary.for_place(game_map.floor_number, game_map.music, area)
	_refresh_music(FADE)


func _on_title_requested(_notice: String) -> void:
	_place_track = &"title"
	_fight_track = &""
	_refresh_music(FADE)


## A page that plays its own track over the place's -- the credits -- or, with
## empty, gives the place its music back.
func play_over(id: StringName) -> void:
	play_music(id if not id.is_empty() else _place_track, FADE)


func _on_combat_began(encounter: Encounter, _party: Array[Combatant],
		_enemies: Array[Combatant]) -> void:
	_fight_encounter = encounter
	_fight_track = MusicLibrary.for_fight(encounter)
	_refresh_music(FIGHT_IN)


func _on_combat_finished(result: CombatResult) -> void:
	var boss := _fight_encounter != null and _fight_encounter.is_boss
	_fight_encounter = null
	_fight_track = &""
	if result.victory:
		play(&"boss_victory" if boss else &"victory")
	elif not result.fled:
		play(&"defeat")
	for held in _after_fight:
		play(held)
	_after_fight.clear()
	_refresh_music(FIGHT_OUT)


# --- what the bus announces --------------------------------------------------

func _on_leveled_up(_level: int) -> void:
	if CombatManager.is_running():
		if &"level_up" not in _after_fight:
			_after_fight.append(&"level_up")
		return
	play(&"level_up")


## The world paying: a chest, a sale, a quest, a purse picked up. A fight's pay
## is under its fanfare.
func _on_col_granted(_amount: int) -> void:
	if not CombatManager.is_running():
		play(&"coin")


## A potion drunk in the field. In a fight the stage plays the item's own.
func _on_item_used(_id: StringName) -> void:
	if not CombatManager.is_running():
		play(&"heal")


func _on_game_saved(_slot: int, auto: bool) -> void:
	if not auto:
		play(&"save")


func _on_idle_countdown(seconds_left: int) -> void:
	if seconds_left <= 10:
		play(&"countdown")


func _on_logged_out() -> void:
	play(&"shatter")
	play(&"logged_out")
	_place_track = &""
	_fight_track = &""
	_refresh_music(FIGHT_IN)
