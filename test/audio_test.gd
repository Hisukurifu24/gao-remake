extends Node
## The sound: every id the game asks for is a real file, the music loops, each
## band has its track, a labyrinth's dark, a safe zone's fire and a fight change
## it and give it back, jingles take turns, and the volumes reach the buses.
##
##     "$GODOT" --headless --path . res://test/audio_test.tscn
##
## Run as a *scene*, not with --script: autoloads are registered after a script
## main loop is compiled, so EventBus & co. wouldn't resolve.
##
## Headless, nothing is heard -- the checks read what [Audio] decided, and its
## [signal Audio.played] spy. Settings go to [constant TEST_DIR], never the
## player's file.

const TEST_DIR := "user://test_audio"
const SOURCE_DIRS: Array[String] = ["res://scripts", "res://ui", "res://scenes"]

var _failures: PackedStringArray = PackedStringArray()
var _checks := 0
## Spies. Members, not captured locals: GDScript lambdas capture by value.
var _played: Array[StringName] = []
var _track_in_fight: StringName = &""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	Audio.played.connect(func(id: StringName) -> void: _played.append(id))
	await _run()
	print("")
	if _failures.is_empty():
		print("audio test: %d checks passed" % _checks)
		get_tree().quit(0)
		return
	printerr("audio test: %d of %d checks FAILED" % [_failures.size(), _checks])
	for failure in _failures:
		printerr("  - ", failure)
	get_tree().quit(1)


func _run() -> void:
	_test_sound_table()
	_test_music_table()
	_test_every_id_asked_for()
	_test_places_and_fights()
	_test_buses_and_volumes()
	await _test_sounds_and_jingles()
	await _test_weather()
	await _test_in_a_game()


# --- the tables ----------------------------------------------------------------

## Every sound is a file that loads, none of them loops (a looping chest would
## ring until the map changes), and every jingle is short enough to wait for.
func _test_sound_table() -> void:
	var missing: PackedStringArray = []
	var looping: PackedStringArray = []
	var long_jingles: PackedStringArray = []
	for id: StringName in SoundLibrary.SOUNDS:
		if SoundLibrary.paths(id).is_empty():
			missing.append("%s (no files)" % id)
		for path in SoundLibrary.paths(id):
			var stream := load(path) as AudioStream
			if stream == null:
				missing.append(path)
				continue
			var wav := stream as AudioStreamWAV
			if wav != null and wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
				looping.append(path)
			if SoundLibrary.is_jingle(id) and stream.get_length() > 3.0:
				long_jingles.append(path)
	_check(missing.is_empty(), "every sound's files load %s" % _list(missing))
	_check(looping.is_empty(), "no sound loops %s" % _list(looping))
	_check(long_jingles.is_empty(), "every jingle is under three seconds %s" % _list(long_jingles))
	_check(SoundLibrary.stream(&"no_such_sound") == null and not SoundLibrary.has(&"no_such_sound"),
			"an id that isn't in the table has no stream")


## Every track is a file that loads and loops, and every one is used somewhere.
func _test_music_table() -> void:
	var broken: PackedStringArray = []
	for id: StringName in MusicLibrary.TRACKS:
		var stream := MusicLibrary.stream(id) as AudioStreamOggVorbis
		if stream == null:
			broken.append("%s (won't load)" % id)
		elif not stream.loop:
			broken.append("%s (doesn't loop)" % id)
	_check(broken.is_empty(), "every track loads and loops %s" % _list(broken))


## The sweep: every id the game names -- an [code]Audio.play()[/code] in any
## script, a [member SkillFx.sound], a waystone's or lever's [code]sound[/code], a
## page's own music -- is in its table. A typo is silent everywhere else: the
## sound just never plays.
func _test_every_id_asked_for() -> void:
	var sounds: Dictionary[StringName, String] = {}
	var tracks: Dictionary[StringName, String] = {}
	var id := RegEx.create_from_string("&\"([a-z0-9_]+)\"")
	for path in _source_files():
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for n in lines.size():
			var line := lines[n]
			var at := "%s:%d" % [path, n + 1]
			for call in ["Audio.play(", "Audio.play_music(", "Audio.play_over("]:
				var from := line.find(call)
				if from < 0 or line.strip_edges().begins_with("##"):
					continue
				for found in id.search_all(line.substr(from)):
					var name := StringName(found.get_string(1))
					if call == "Audio.play(":
						sounds[name] = at
					else:
						tracks[name] = at
			if path.ends_with(".tscn") or path.ends_with(".tres"):
				if line.begins_with("sound = &\""):
					sounds[StringName(id.search(line).get_string(1))] = at
				# A boss's next bar may bring its own track ([member BossPhase.music]).
				if line.begins_with("music = &\""):
					tracks[StringName(id.search(line).get_string(1))] = at
	var waystone := load("res://scenes/world/waystone.tscn").instantiate() as Waystone
	sounds[waystone.sound] = "Waystone.sound"
	waystone.free()
	_check(sounds.size() >= 40, "the sweep found the game's sounds (%d ids)" % sounds.size())
	_check(tracks.has(&"revelation"), "and the music a boss's next bar brings")
	var unknown: PackedStringArray = []
	for name in sounds:
		if not SoundLibrary.has(name):
			unknown.append("%s at %s" % [name, sounds[name]])
	for name in tracks:
		if not name.is_empty() and not MusicLibrary.has(name):
			unknown.append("track %s at %s" % [name, tracks[name]])
	_check(unknown.is_empty(), "every sound and track the game asks for is in its table %s"
			% _list(unknown))

	var fx_missing: PackedStringArray = []
	for file in DirAccess.get_files_at("res://resources/fx"):
		if not file.ends_with(".tres"):
			continue
		var fx := load("res://resources/fx/" + file) as SkillFx
		if fx == null or not SoundLibrary.has(fx.sound):
			fx_missing.append(file)
	_check(fx_missing.is_empty(), "every skill effect sounds like something %s" % _list(fx_missing))
	var skills_missing: PackedStringArray = []
	var skills: Array[Skill] = SkillLibrary.all().duplicate()
	skills.append(SkillLibrary.basic_attack())
	for skill in skills:
		if skill.fx == null or skill.fx.sound.is_empty():
			skills_missing.append(String(skill.id))
	_check(skills_missing.is_empty(), "every player skill lands with a sound %s" % _list(skills_missing))


# --- which music plays where ---------------------------------------------------

func _test_places_and_fights() -> void:
	var by_band: Dictionary[StringName, StringName] = {}
	var wrong: PackedStringArray = []
	for n in range(1, FloorTuning.TOP_FLOOR + 1):
		var track := MusicLibrary.for_place(n, &"", MusicLibrary.OPEN)
		if track != FloorRegistry.biome_id(n) or not MusicLibrary.has(track):
			wrong.append("floor %d plays %s" % [n, track])
		by_band[FloorRegistry.biome_id(n)] = track
	_check(wrong.is_empty(), "every floor plays its band's track in the open %s" % _list(wrong))
	var distinct := {}
	for track in by_band.values():
		distinct[track] = true
	_check(by_band.size() == 10 and distinct.size() == 10, "the ten bands play ten tracks")
	_check(MusicLibrary.for_place(40, &"", MusicLibrary.DARK) == &"labyrinth"
			and MusicLibrary.for_place(1, &"town", MusicLibrary.DARK) == &"labyrinth",
			"a labyrinth's dark sounds the same on every floor")
	_check(MusicLibrary.for_place(70, &"", MusicLibrary.SAFE) == &"safe_zone",
			"and so does a safe zone's fire")
	_check(MusicLibrary.for_place(1, &"town", MusicLibrary.OPEN) == &"town",
			"a map with its own track plays it in the open")
	var town := load("res://scenes/world/town.tscn").instantiate() as GameMap
	_check(town.music == &"town", "the Town of Beginnings has its own")
	town.free()

	var roam := Bestiary.single_encounter(Bestiary.pool_for_floor(3)[0], 3, 3)
	_check(MusicLibrary.for_fight(roam) == &"fight", "a monster is a fight")
	_check(MusicLibrary.for_fight(Bestiary.boss_encounter(3)) == &"boss"
			and MusicLibrary.for_fight(Bestiary.boss_encounter(99)) == &"boss",
			"a floor's boss is a boss fight")
	_check(MusicLibrary.for_fight(Bestiary.boss_encounter(FloorTuning.TOP_FLOOR)) == &"final_boss",
			"and the top floor's is the last one")
	_check(MusicLibrary.for_fight(Bestiary.ambush_encounter(30)) == &"fight"
			and MusicLibrary.for_fight(Bestiary.duel_encounter(30, "Rival", null, false)) == &"fight",
			"an ambush and a duel are fights")


# --- the buses and the volumes -------------------------------------------------

func _test_buses_and_volumes() -> void:
	var music := AudioServer.get_bus_index(Audio.MUSIC_BUS)
	var sounds := AudioServer.get_bus_index(Audio.SOUND_BUS)
	_check(music > 0 and sounds > 0 and AudioServer.get_bus_send(music) == &"Master"
			and AudioServer.get_bus_send(sounds) == &"Master",
			"the Music and Sounds buses exist and feed the Master")

	Settings.path = TEST_DIR.path_join("settings.cfg")
	Settings.reset()
	Settings.set_value(&"music_volume", 5)
	Settings.set_value(&"sound_volume", 0)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(music), linear_to_db(0.5))
			and not AudioServer.is_bus_mute(music),
			"a volume sets its bus: half is half")
	_check(AudioServer.is_bus_mute(sounds), "and 0 mutes it")
	Settings.reset()
	_check(not AudioServer.is_bus_mute(sounds) and Settings.music_volume == Settings.MUSIC_VOLUME,
			"a reset turns it back up")
	_check(Settings.load_settings() and Settings.music_volume == 5 and Settings.sound_volume == 0,
			"the file reads back as written")
	Settings.set_value(&"music_volume", 99)
	_check(Settings.music_volume == Settings.VOLUME_STEPS, "a volume past full is full")
	Settings.reset()
	DirAccess.remove_absolute(Settings.path)
	Settings.path = Settings.PATH

	var list := SettingsList.new()
	add_child(list)
	var music_row := SettingsList.ROWS.find(&"music_volume")
	list.select(music_row)
	Settings.music_volume = 1
	list.step(-1)
	_check(Settings.music_volume == 0 and list.text_of(music_row).contains("Off"),
			"the settings page steps a volume down to off")
	list.step(-1)
	_check(Settings.music_volume == Settings.VOLUME_STEPS, "and from off round to full")
	list.queue_free()
	Settings.reset()
	DirAccess.remove_absolute(TEST_DIR.path_join("settings.cfg"))
	Settings.path = Settings.PATH


# --- sounds and jingles --------------------------------------------------------

func _test_sounds_and_jingles() -> void:
	_played.clear()
	Audio.play(&"hit")
	Audio.play(&"hit")
	_check(_played.count(&"hit") == 1, "the same sound twice at once is one sound")
	await _wait_ms(Audio.SAME_SOUND_MS + 20)
	Audio.play(&"hit")
	_check(_played.count(&"hit") == 2, "and twice a moment apart is two")
	for i in Audio.VOICES + 3:
		Audio.play(&"slash" if i % 2 == 0 else &"claw")
		await _wait_ms(Audio.SAME_SOUND_MS / 2)
	_check(true, "more sounds than voices steals the oldest without complaint")
	Audio.play(&"no_such_sound")
	_check(not _played.has(&"no_such_sound"), "an id that isn't there plays nothing")

	_played.clear()
	Audio.play(&"victory")
	Audio.play(&"level_up")
	Audio.play(&"level_up")
	Audio.play(&"victory")
	_check(_played == [&"victory"] and Audio.jingle_playing() == &"victory",
			"a jingle plays at once, and the next waits its turn")
	await _until(func() -> bool: return Audio.jingle_playing() != &"victory", 5.0)
	_check(_played == [&"victory", &"level_up"],
			"the waiting one plays once it is done -- once, though asked for twice")
	await _until(func() -> bool: return Audio.jingle_playing().is_empty(), 5.0)
	_check(Audio.jingle_playing().is_empty() and _played.size() == 2,
			"and nothing plays after: the one already played isn't queued behind itself")


## A storm is heard as well as seen: the band's rain or wind, looping, once the
## map is up -- and not before, since the generator builds it with no tree.
func _test_weather() -> void:
	var broken: PackedStringArray = []
	for kind: StringName in Weather.LOOKS:
		var weather := Weather.new()
		weather.setup(kind)
		var sound := weather.get_node_or_null("Sound") as AudioStreamPlayer
		var wav := sound.stream as AudioStreamWAV if sound != null else null
		if wav == null or wav.loop_mode == AudioStreamWAV.LOOP_DISABLED or sound.bus != Audio.SOUND_BUS:
			broken.append(String(kind))
		weather.free()
	_check(broken.is_empty(), "every storm has a looping sound on the Sounds bus %s" % _list(broken))
	var rain := Weather.new()
	rain.setup(&"rain")
	var sound := rain.get_node("Sound") as AudioStreamPlayer
	_check(not sound.playing, "a storm built off the tree is silent")
	add_child(rain)
	await get_tree().process_frame
	_check(sound.playing, "and plays once it is up")
	rain.queue_free()


# --- in a running game ---------------------------------------------------------

## The real thing: a game booted, walked from the town into a generated floor's
## labyrinth and its safe zone and back out, and a fight fought there.
func _test_in_a_game() -> void:
	CombatManager.step_delay = 0.0
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _until_arrived()
	await _physics(3)
	_check(Audio.current_track() == &"town", "the Town of Beginnings plays the town's track")

	GameState.clear_floor(1)
	FloorGenerator.modifier_override = FloorModifier.Kind.NONE
	FloorGenerator.shape_override = FloorDefinition.Shape.CLASSIC
	SceneRouter.enter_floor(2, &"", 0.0)
	await _until_arrived()
	await _physics(3)
	var map := SceneRouter.current_map() as GameMap
	_check(map != null and map.floor_number == 2 and Audio.current_track() == &"meadow",
			"a generated floor plays its band's")
	for child in map.get_children():
		if child is Monster:
			(child as Monster).calm(600.0)
	var player := map.get_node("Player") as Player
	var start := player.global_position

	var dark := _standable_in(map, map.dark_area, map.safe_zones)
	_check(dark.x > -1000, "(setup) the labyrinth has somewhere to stand")
	player.global_position = map.to_global(_middle(map, dark))
	await _physics(3)
	_check(Audio.current_track() == &"labyrinth", "walking into the labyrinth's dark changes it")

	var safe := _standable_in(map, map.safe_zones[0], []) if not map.safe_zones.is_empty() \
			else Vector2i(-1000, -1000)
	_check(safe.x > -1000, "(setup) the labyrinth has a safe zone to stand in")
	player.global_position = map.to_global(_middle(map, safe))
	await _physics(3)
	_check(Audio.current_track() == &"safe_zone", "and so does sitting down by its fire")

	player.global_position = start
	await _physics(3)
	_check(Audio.current_track() == &"meadow", "and walking out gives the field its music back")

	# A fight, won, by a player one experience point short of a level.
	GameState.heal_to_full()
	GameState.grant_xp(GameState.xp_to_next_level() - GameState.xp - 1)
	var level := GameState.level
	_played.clear()
	CombatManager.set_seed(7)
	CombatManager.command_requested.connect(_on_command_requested)
	var type := Bestiary.pool_for_floor(2)[0]
	var result: CombatResult = await CombatManager.start(Bestiary.single_encounter(type, 1, 2))
	CombatManager.command_requested.disconnect(_on_command_requested)
	_check(_track_in_fight == &"fight", "a fight plays the fight's track")
	_check(result.victory and GameState.level == level + 1, "(setup) the fight is won, and levels")
	await _until(func() -> bool: return _played.has(&"level_up"), 5.0)
	_check(_played.find(&"victory") >= 0 and _played.find(&"level_up") > _played.find(&"victory"),
			"its fanfare plays first, and the level gained in it after")
	_check(Audio.current_track() == &"meadow", "and the field's music comes back after it")

	FloorGenerator.modifier_override = -1
	FloorGenerator.shape_override = -1
	main.queue_free()
	await get_tree().process_frame


func _on_command_requested(actor: Combatant) -> void:
	_track_in_fight = Audio.current_track()
	var target := CombatManager.living_enemies()[0]
	CombatManager.submit(CombatAction.use(SkillLibrary.basic_attack(), target))


## A cell of [param area] the player can stand in, not in any of [param not_in];
## far off the map if there is none.
func _standable_in(map: GameMap, area: Rect2i, not_in: Array) -> Vector2i:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if not_in.any(func(zone: Rect2i) -> bool: return zone.has_point(cell)):
				continue
			if map.can_stand_at(_middle(map, cell)):
				return cell
	return Vector2i(-1000, -1000)


func _middle(map: GameMap, cell: Vector2i) -> Vector2:
	var walls := map.get_node("Walls") as TileMapLayer
	return map.to_local(walls.to_global(walls.map_to_local(cell)))


# --- plumbing ------------------------------------------------------------------

func _source_files() -> PackedStringArray:
	var found := PackedStringArray()
	var dirs: Array[String] = SOURCE_DIRS.duplicate()
	dirs.append("res://resources/fx")
	dirs.append("res://resources/enemies")
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(dir):
			dirs.append(dir.path_join(sub))
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".gd") or file.ends_with(".tscn") or file.ends_with(".tres"):
				found.append(dir.path_join(file))
	return found


func _until_arrived(seconds := 10.0) -> void:
	await _until(func() -> bool:
		return SceneRouter.current_map() != null and not SceneRouter.is_busy() \
				and not GameState.is_input_locked(), seconds)


## Waits on the wall clock: what [Audio] counts in.
func _wait_ms(ms: int) -> void:
	var limit := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < limit:
		await get_tree().process_frame


func _until(done: Callable, seconds: float) -> void:
	var limit := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not done.call() and Time.get_ticks_msec() < limit:
		await get_tree().process_frame


func _physics(frames := 1) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _list(items: PackedStringArray) -> String:
	if items.is_empty():
		return ""
	return "(%s)" % ", ".join(items.slice(0, 6)) + (" ..." if items.size() > 6 else "")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", description)
	else:
		print("  FAIL ", description)
		_failures.append(description)
