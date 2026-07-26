# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**GAO Remake** — a 2D top-down RPG built in **Godot 4.7** (Mobile renderer, 640x360 viewport, nearest-neighbour filtering). The setting draws on *Sword Art Online* lore (a floating-castle world of stacked floors, players trapped in a death-game VRMMO, sword-skill combat). Planned core systems: **inventory**, **turn-based combat**, **quests**, and **dialogue**.

The world is **100 floors** of a stacked castle, each ending in a boss; floor 100 is the final fight. Milestone floors are hand-authored, the rest are procedurally generated — see "The floor system" below.

`plan.md` is the roadmap and the source of truth for what's built. **M0 (foundation), M1 (overworld, movement, interaction, map transitions), M2 (dialogue), M4 (turn-based combat) and the 100-floor spine are done**; inventory and quests are not — treat the architecture sections below as the target for those, and as a description of what already exists.

The core loop is completable end to end: walk, talk, fight the monsters on the floor, level up, beat the floor boss, climb. No placeholders remain in it.

**Dialogue is custom, not Dialogic** — decided so dialogue stays on the same `Resource`/`.tres` model as items, skills and quests, and conditions can read `GameState` flags directly. See "The dialogue system" below.

## Commands

Godot has no separate build step; the editor imports assets and the engine runs scenes directly. The engine binary lives inside the installed app:

```sh
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"

# Run the game (main scene)
"$GODOT" --path .

# Run a specific scene without changing the main scene
"$GODOT" --path . res://path/to/Scene.tscn

# Headless import (regenerate .godot/ import cache, e.g. in CI or after adding assets)
"$GODOT" --headless --path . --import

# Open the editor
"$GODOT" --editor --path .
```

`.godot/` is generated import/cache output and is gitignored — never edit it by hand. If imports look stale, delete `.godot/imported/` and re-run the import command.

### Tools

Run in this order — each step consumes the previous one's output.

```sh
# 1. Placeholder art: one 8-slot atlas per biome, plus characters, dialogue
#    portraits, props and enemy battlers (pure-stdlib PNG writer, no Pillow)
python3 tools/gen_placeholder_art.py

# 2. A TileSet + BiomeKit per biome. Safe to re-run; only touches derived resources.
"$GODOT" --headless --path . --script res://tools/build_biomes.gd

# 3. The authored Floor 1 maps.
#    OVERWRITES scenes/world/town.tscn and field.tscn -- stop using it once maps
#    are being painted in the editor.
"$GODOT" --headless --path . --script res://tools/build_placeholder_maps.gd

# Boot the game, capture frames to user://screenshots, exit (needs a real window)
"$GODOT" --path . res://tools/screenshot.tscn
```

Biome atlases share one **semantic slot layout** (`0 floor, 1 floor-alt, 2 path, 3 special, 4 liquid, 5 obstacle, 6 wall, 7 wall-alt`; slots 4–7 collide). The generator paints "wall" without knowing which biome it's in, so a new biome is a palette entry in `gen_placeholder_art.py` plus a row in `build_biomes.gd` — no generator changes.

Maps are engine-generated because `tile_map_data` is a binary blob inside the `.tscn` — it can't be hand-authored as text. Entity scenes (player, NPC, chest, exits) are plain hand-written `.tscn`.

### Tests

```sh
# Boots the real game, walks the loop: spawn, collision, interaction, transition,
# clearing floor 1, ascending into a generated floor 2
"$GODOT" --headless --path . res://test/smoke_test.tscn

# The floor system: registry, biome bands, seed determinism, progression gating,
# and a flood-fill of ALL 99 generated floors proving each is completable
"$GODOT" --headless --path . res://test/floor_test.tscn

# The dialogue system: conditions, entry selection, branching, effects, the input
# lock, and the real Argo/Nezha resources. Drives DialogueRunner with no UI.
"$GODOT" --headless --path . res://test/dialogue_test.tscn

# The combat system: content loading, scaling, formulas, statuses, cooldowns,
# stagger, the turn loop, the rules the runner enforces, seed determinism, and
# measured win rates against real bosses. ~90s; the balance section fights
# hundreds of battles.
"$GODOT" --headless --path . res://test/combat_test.tscn
```

All four exit non-zero on failure. Two checks are load-bearing and should not be weakened:

- **The floor test's completability flood fill.** An unreachable boss door is the failure mode procedural generation reliably ships, and playtesting will not find it.
- **The combat test's balance section.** Its numbers were measured, not chosen. A stat, curve or growth-rate edit that makes floor 50 unwinnable fails here instead of 20 hours into a playthrough. If one moves, decide whether the climb *should* have changed shape before re-baselining it.

Run it as a **scene**, not with `--script`: autoloads are registered *after* a script main loop is compiled, so `EventBus`/`GameState`/`SceneRouter` don't resolve there.

For unit tests, prefer [GUT](https://github.com/bitwes/Gut) (not installed yet). Once it's in `addons/gut/`:

```sh
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://test -gexit
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gtest=res://test/test_inventory.gd -gexit
```

## Architecture conventions

Godot projects are trees of **scenes** (`.tscn`) composed of **nodes**, with behavior in **GDScript** (`.gd`) attached to nodes. Prefer this Godot-idiomatic structure over a monolithic manager:

- **Autoload singletons** (Project Settings → Autoload) for cross-scene state that must persist: e.g. `GameState`, `Inventory`, `QuestLog`, `PartyManager`. These are the backbone of the four systems — combat, dialogue, and quests all read/write them. Access them by their autoload name from anywhere.
- **Signals over polling.** Systems communicate by emitting signals (e.g. `inventory.item_added`, `combat.turn_ended`, `dialogue.finished`, `quest.objective_completed`). UI subscribes to these rather than the model reaching into the UI. A global event bus autoload is acceptable for decoupled cross-system events.
- **Data as Resources.** Model items, enemies, skills, quests, and dialogue trees as custom `Resource` classes (`extends Resource`, `@export` fields) saved as `.tres` files. This keeps content data-driven and editable in the inspector rather than hard-coded. Combat and inventory operate on these resources, not on ad-hoc dictionaries.
- **Scene boundaries mirror game modes.** The overworld (top-down exploration) and turn-based combat are typically separate scenes; entering combat swaps/overlays the combat scene and returns to the overworld afterward, carrying results through the autoloads.

Top-level layout: `scenes/` (player, world, main), `scripts/` (`autoload/`, `combat/`, `player/`, `resources/`, `world/`), `resources/` (the `.tres` data: `biomes/`, `dialogue/`, `enemies/`, `floors/`, `skills/`, `statuses/`, `tilesets/`), `ui/`, `assets/`, `test/`, `tools/` (generators), `addons/` (plugins like GUT).

### What exists (M0/M1/M2)

- **Autoloads** — `EventBus` (signals only, no logic; signals for all four systems are already declared), `GameState` (stats, level/XP curve, world flags, a *counted* input lock), `SceneRouter`, `DialogueRunner`, `CombatManager`.
- **`scenes/main.tscn` is the main scene and never unloads.** Maps are swapped in and out of its `WorldRoot` by `SceneRouter.change_map(path, spawn)` — not via `change_scene_to_file`, so the HUD and fade overlay survive transitions. A map arrives at a *named spawn point*; `GameMap._ready()` resolves the name and places the player.
- **`Interactable`** (`scripts/world/interactable.gd`, physics layer 4) is the base for NPC / chest / map exit / boss gate / monster. The player's `InteractSensor` picks the nearest one it's facing and announces it via `EventBus.interact_target_changed`.
- **Persistence is flags, not node state** — e.g. an opened chest sets `GameState` flag `chest_town_square`, so it stays open across map reloads. Monsters are the deliberate exception: they are `queue_free()`d and come back on the next visit, because a player who has hit a wall needs somewhere to earn levels.
- **`ui/hud.gd` is the interact prompt and the player's vitals.** Conversations live in `ui/dialogue_box.tscn`, battles in `ui/combat_screen.tscn`; the HUD hides itself while either is up.

Physics layers: 1 world, 2 player, 3 enemy, 4 interactable. Input actions: `move_up/down/left/right`, `interact`.

### The dialogue system

- **Flow and view are separate.** `DialogueRunner` (autoload) walks the graph, evaluates conditions, applies effects and holds the input lock; `ui/dialogue_box.tscn` only draws what it is told and calls `advance()` / `choose(i)` back. `test/dialogue_test.tscn` runs the whole system with no box instantiated — if it passes and the game looks wrong, the bug is in the view.
- **A `Dialogue` is an ordered array of `DialogueLine`s**, run top to bottom. A line's `next` jumps to another line's `id`; `&"end"` (`DialogueLine.END`) closes the box; empty falls through to the next array element. Linear conversations therefore need no ids at all.
- **Entry selection is what makes dialogue reactive.** With `start` empty the runner enters at the first *block-opening* line whose conditions pass, so an NPC greets you differently once you've met them or cleared their floor. A line that the previous line falls through into is a **continuation and never an entry point** — without that rule the second half of a gated block becomes a legal opening line the moment its first half's condition fails. Put specific blocks first, end with an unconditional one.
- **`DialogueCondition`** asks `GameState` one small question (`FLAG_SET`, `FLOOR_CLEARED`, `MIN_LEVEL`, each negatable). A line's or choice's conditions are ANDed; for OR, write two blocks. **`DialogueEffect`** sets a flag, grants XP, or emits `EventBus.item_added` / `quest_started` — dialogue never calls Inventory or QuestLog, so it works before they exist.
- **Locked choices** either vanish (`hide_when_locked`, the default) or stay visible and greyed with a `locked_hint` — "(not until Illfang falls)". The runner refuses out-of-range and locked indices as well as the UI, since it is the one place that must not be talked into an impossible branch.
- **Two entry points, one pipeline**: `DialogueRunner.start(dialogue)` for conversations, `EventBus.message_requested` (→ `say()`) for unbranching text from chests, signs and system notices. A conversation started while one is open is queued, not dropped.
- **`Npc.dialogue` beats `Npc.lines`**; `lines` stays for extras who say one thing. `met_flag` is set *after* the conversation, so a first-meeting block can still see "we haven't met".
- Adding a conversation: a `.tres` in `resources/dialogue/`, then point an NPC's `dialogue` export at it. Hand-writing one is fine — note that typed arrays serialize as `Array[ExtResource("choice")]([SubResource("...")])`, and sub-resources must appear before the resources referencing them.

### The combat system

- **Flow and view are separate**, same as dialogue. `CombatManager` (autoload) owns the turn loop, targeting, statuses, AI and the input lock; `ui/combat_screen.tscn` draws what it announces and answers with `CombatManager.submit(action)`. `test/combat_test.tscn` fights hundreds of battles with no screen instantiated — if it passes and the game looks wrong, the bug is in the view.
- **`CombatManager.start(encounter)` is awaitable** and returns a `CombatResult`. That object is all a caller needs: `BossGate` clears the floor on `victory`, a `Monster` frees itself. XP and loot are already granted by the time it arrives.
- **`submit()` is the only door in, and it refuses illegal moves** — a skill on cooldown, an out-of-range target, fleeing a boss. The UI greys those out too, but the runner is the one place that must not be talked into an impossible move. **It must also accept a synchronous answer**: a caller that submits during the `command_requested` signal is answering before the loop parks, which is why the accepted action is held in `_pending` rather than delivered by signal alone.
- **Everything a combatant can do is a `Skill`**, including the plain attack (`SkillLibrary.basic_attack()`). There is no separate enemy-attack path that can drift from the player's.
- **`Combatant` is runtime-only** and dies with the fight; `write_back()` is the single path back into `GameState`, and only the player uses it. HP carries in and out — there is no free heal at the door.
- **All balance lives in three places**: `CombatMath` (the formulas), `FloorTuning` (the 100-floor curve), and the `.tres` files (per-enemy stats). Never tune inside `CombatManager`.
- **Mitigation is `attack / (attack + defence)`**, not subtraction and not a fixed curve. A ratio holds its shape whether the numbers are 8 and 4 or 240 and 130; the other two break at one end of a 100-floor climb. `test/combat_test.gd` asserts this directly.
- **The XP curve is linear** (`GameState.XP_BASE + XP_STEP * (level - 1)`) because monster payouts are linear in their level. Making one exponential without the other stalls the climb around floor 17 — measured, not theoretical.
- **Statuses are percentages of max HP, never flat points.** A flat 4-damage poison is everything on floor 2 and nothing on floor 90.
- Adding an enemy: a `.tres` in `resources/enemies/`, a sprite entry in `gen_placeholder_art.py`'s `BATTLERS`, and an id in `Bestiary.ENEMIES` + the relevant `BIOME_POOLS` row. Adding a skill: a `.tres` in `resources/skills/` plus a line in `SkillLibrary.PLAYER_SKILLS` (enemy skills are referenced by their `EnemyType` and need no registry).
- **Boss escorts are capped at one** in `Bestiary._escort_count` *because the party is one*. Two full-strength escorts against a solo player measured at ~1 win in 20 on floor 100. Lift the cap when the party grows, not before.

### The floor system

- **`FloorDefinition`** (`.tres`) describes a floor. If it has an `authored_scene` it's hand-built; otherwise it's generated. `FloorRegistry` returns one for any floor 1–100, synthesising non-authored ones from the biome band table + `FloorTuning`.
- **`FloorRegistry.build_floor(n)`** is the single entry point — it hides which kind you got. `SceneRouter.enter_floor(n, spawn)` is what gameplay calls.
- **`FloorGenerator`** builds rooms + L-corridors and returns *the same node shape as an authored map* (`Ground` / `Walls` / `SpawnPoints` / `Player` + interactables). Keep it that way: `GameMap`, the camera and the router all depend on that shape and on nothing else.
- **Determinism is a requirement, not a nicety.** Seeds come from `FloorRegistry.seed_for(n)` = `hash(world_seed, floor_number)`. Never use unseeded `randi()` in generation — it breaks save consistency and makes bugs irreproducible.
- **`FloorTuning`** holds the whole 100-floor curve (level, map size, room/chest counts, boss names). Balance changes go there, not into individual floors.
- **Progression** is `GameState.clear_floor(n)` → `is_floor_unlocked(n+1)`. `BossGate` is the gate, and it runs a real fight (`Bestiary.boss_encounter(n)`). Losing drops the player at the floor entrance on 35% HP with the floor rebuilt, so its monsters are back — the way through a wall is levels.
- **Every generated floor carries `FloorTuning.monster_count(n)` roaming monsters.** That count is not decoration: it is the measured number of kills that puts a player at the level the floor's boss expects. Monsters have no collision, so they can never wall off a corridor and the completability flood fill never sees them.
- Adding a milestone floor: build the scene, add a `FloorDefinition` `.tres` in `resources/floors/`, and register it in `FloorRegistry.AUTHORED` (explicit dictionary — `res://` directory scanning is unreliable in exported builds).

## Godot 4.7 gotchas

- GDScript 2.0 syntax: `@export`, `@onready`, `signal name(args)`, `await signal_or_coroutine`, typed variables (`var hp: int = 10`). Do not use Godot 3.x idioms (`export var`, `yield`, `.instance()` → now `.instantiate()`).
- Every `.tscn`/`.gd`/asset has a companion `.uid`/`.import` or embedded UID; when moving files, use the editor's FileSystem dock (or update references) so `uid://` and `res://` paths stay valid.
- Rendering is **Mobile** and stretch mode is `canvas_items` with `expand` aspect — the 2D UI scales cleanly across resolutions; design UI with anchors/containers, not fixed pixel positions. The base viewport is 640x360, so UI is laid out in those units.
- `TileSetAtlasSource` must be added to the `TileSet` *before* creating tiles, or the tiles get no physics layers and every collision-polygon call fails silently-ish (an error per tile).
- GDScript lambdas capture locals **by value** — a lambda that writes to a captured local silently discards the write. Use a member variable for signal spies and accumulators.
- `Input.action_press()` sets the action's *state* but never synthesises an event, so nothing in `_unhandled_input` sees it. To drive UI from a tool or test, feed a real `InputEventAction` through `Input.parse_input_event()` (see `tools/screenshot.gd`).
- **`await some_signal` parks unconditionally**, even if the thing you are waiting for already happened during the emit that preceded it. Any coroutine that emits a request and then awaits the reply needs a "did it already answer?" check first, or a synchronous responder deadlocks it. `CombatManager._decide()` is the worked example.
