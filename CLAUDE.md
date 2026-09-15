# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**GAO Remake** — a 2D top-down RPG built in **Godot 4.7** (Mobile renderer, 640x360 viewport, nearest-neighbour filtering). The setting draws on *Sword Art Online* lore (a floating-castle world of stacked floors, players trapped in a death-game VRMMO, sword-skill combat). Planned core systems: **inventory**, **turn-based combat**, **quests**, and **dialogue**.

The world is **100 floors** of a stacked castle, each ending in a boss; floor 100 is the final fight. Milestone floors are hand-authored, the rest are procedurally generated — see "The floor system" below.

`plan.md` is the roadmap and the source of truth for what's built. **M0 (foundation), M1 (overworld, movement, interaction, map transitions), M2 (dialogue), M3 (inventory & items), M4 (turn-based combat), M5 (quests) and the 100-floor spine are done.** What's left is M5.5 (exploration feel), M6 (world depth, authored floors) and M7 (save/load, polish, audio). **M5.5 is under way**: the camera is zoomed 2× and monsters wander, chase and start fights on contact; the hidden boss room is next. **Wall autotiling landed**, so generated floors read as rooms rather than as flat rectangles, **Floor 10 — Ashlow Wood — is the second authored floor**: a village hub, three glades, a hollow with an authored boss, and two quests on it. **Floor 25 — Lanternfall — is the third**: a mining camp over a chain of caverns, three dead-end galleries, a one-way lift home, an authored boss and two more quests. Authored floors share one builder, `tools/authored_floor.gd`. **The art is moving to the Ninja Adventure pack** (CC0, whole, in `assets/ninja_adventure/`): the meadow and forest biomes and Floors 1 and 10 are converted — forest walls, grass/dirt and shoreline transitions, decor, houses, pack characters, portraits, monsters and battlers — while the other eight biomes, Floor 25, and the rest of the roster still draw placeholders. See "Map dressing and the art pack" below.

The core loop is completable end to end: walk, talk, take a job, fight the monsters on the floor, level up, beat the floor boss, climb. No placeholders remain in it.

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
# 1. Placeholder art: one atlas per biome (8 semantic slots + a 47-tile wall
#    blob), plus characters, dialogue
#    portraits, props, enemy battlers and item icons (pure-stdlib PNG writer,
#    no Pillow). ITEM_ICONS must stay in step with ItemLibrary.ITEMS.
python3 tools/gen_placeholder_art.py

# 2. Re-import, so step 3 cuts tiles from the atlas step 1 just wrote rather than
#    from the stale one. Load-bearing, not housekeeping.
"$GODOT" --headless --path . --import

# 3. A TileSet + BiomeKit per biome. Safe to re-run; only touches derived resources.
#    Biomes listed in PACK_BIOMES (meadow and forest, so far) are cut straight from
#    assets/ninja_adventure/ and embedded, so they don't depend on step 2.
"$GODOT" --headless --path . --script res://tools/build_biomes.gd

# 4. The authored Floor 1 maps.
#    OVERWRITES scenes/world/town.tscn and field.tscn -- stop using it once maps
#    are being painted in the editor.
"$GODOT" --headless --path . --script res://tools/build_placeholder_maps.gd

# 5. The authored Floor 10 and 25 maps. Same caveat: each OVERWRITES its
#    scenes/world/floor_NN.tscn. Both extend tools/authored_floor.gd, which refuses
#    to write a floor with anything on it unreachable from the spawn, so a bad edit
#    to a layout table fails here rather than in the game. Add `-- --preview` to
#    print the layout as text instead of writing it.
"$GODOT" --headless --path . --script res://tools/build_floor_10.gd
"$GODOT" --headless --path . --script res://tools/build_floor_25.gd

# Boot the game, capture frames to user://screenshots, exit (needs a real window)
"$GODOT" --path . res://tools/screenshot.tscn
```

Biome atlases share one **semantic slot layout** in row 0 (`0 floor, 1 floor-alt, 2 path, 3 special, 4 liquid, 5 obstacle, 6 wall, 7 wall-alt`; slots 4–7 collide). The generator paints "wall" without knowing which biome it's in, so a new biome is a palette entry in `gen_placeholder_art.py` plus a row in `build_biomes.gd` — no generator changes.

A **pack biome** keeps the same row-0 slots and adds the rows placeholders lack — grass/dirt and water transitions, 2×2 trees, decor, houses — laid out by `PACK_BIOMES` in `build_biomes.gd` as sheet-and-cell references into the pack. Its transitions' terrain peering bits are read off the pixels (`_links`), never typed in, for the reason the blob derives its masks from a rule.

Rows 1–6 hold the **47-tile wall blob** for autotiling. Both tools derive the mask list from the same rule (`_blob_masks`) rather than sharing a table, so the art and the terrain peering bits cannot drift into a silent mis-pairing — and the floor test checks every chosen tile against its actual neighbours in case they do.

Maps are engine-generated because `tile_map_data` is a binary blob inside the `.tscn` — it can't be hand-authored as text. Entity scenes (player, NPC, chest, exits) are plain hand-written `.tscn`.

### Tests

```sh
# Boots the real game, walks the loop: spawn, collision, interaction, transition,
# clearing floor 1, ascending into a generated floor 2 -- then, on that floor,
# monsters noticing through line of sight, chasing, engaging on contact, the
# input lock, the grace period and who gets the first round
"$GODOT" --headless --path . res://test/smoke_test.tscn

# The floor system: registry, biome bands, seed determinism, progression gating,
# wall autotiling, the forest and ground dressing, a flood-fill of EVERY generated floor proving each is
# completable and still sealed, and the same walk over every authored floor
# (plus its monster count against the curve)
"$GODOT" --headless --path . res://test/floor_test.tscn

# The dialogue system: conditions, entry selection, branching, effects, the input
# lock, and the real Argo/Nezha resources. Drives DialogueRunner with no UI.
"$GODOT" --headless --path . res://test/dialogue_test.tscn

# The inventory system: stacking, slot caps, equipment, consumables in the
# field and in battle, and a sweep proving every loot/chest/dialogue item id
# has a resource behind it
"$GODOT" --headless --path . res://test/inventory_test.tscn

# The combat system: content loading, scaling, formulas, statuses, cooldowns,
# stagger, the turn loop, the rules the runner enforces, seed determinism, and
# measured win rates against real bosses. The balance section fights hundreds
# of battles.
"$GODOT" --headless --path . res://test/combat_test.tscn

# The quest system: availability and prerequisites, all four objective kinds,
# turn-in, rewards and chaining, the GameState flag bridge, and Argo's real
# conversation driven through the runner with no box
"$GODOT" --headless --path . res://test/quest_test.tscn
```

All six exit non-zero on failure. Four checks are load-bearing and should not be weakened:

- **The floor test's completability flood fill.** An unreachable boss door is the failure mode procedural generation reliably ships, and playtesting will not find it. It also checks the outer ring is still sealed: autotiling rewrites every wall on the floor, and dropping one instead of replacing it would open the map onto the void — which the flood fill alone would answer by quietly reaching *further*, not by failing. **Authored floors get the same walk**, since hand-building fails at this the same way and with no seed to blame; that walk follows `MapExit`s, because an authored floor may span several maps (Floor 1's door is in the field, not the town). Its flood fill is *bounded* to the walls' used rect — an authored map is allowed holes in its border where an exit sits in them, and an unbounded fill walks out through one and expands forever. Whether a map's ring must be sealed is decided *per map*: an exit to another map excuses holes, an exit back into the same map (Lanternfall's lift) does not.
- **The combat test's balance section.** Its numbers were measured, not chosen. A stat, curve or growth-rate edit that makes floor 50 unwinnable fails here instead of 20 hours into a playthrough. If one moves, decide whether the climb *should* have changed shape before re-baselining it.
- **The inventory test's item-id sweep.** Every id the rest of the game emits — `EnemyType.loot`, `FloorGenerator.CHEST_*`, every authored floor's chests, dialogue's `GIVE_ITEM` — must name a real `.tres`. A typo is silent everywhere else: the drop simply never arrives.
- **The quest test's objective-target sweep.** The same failure, one layer up: every KILL must name an enemy id, every COLLECT an item id, every TALK a conversation, every REACH a floor in range. A typo makes an objective that can never be completed, and nothing else in the game will say so.

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

Top-level layout: `assets/` (`placeholder/` generated art, `ninja_adventure/` the art pack with its LICENSE), `scenes/` (player, world, main), `scripts/` (`autoload/`, `combat/`, `inventory/`, `player/`, `quests/`, `resources/`, `world/`), `resources/` (the `.tres` data: `biomes/`, `dialogue/`, `enemies/`, `floors/`, `items/`, `quests/`, `skills/`, `statuses/`, `tilesets/`), `ui/`, `assets/`, `test/`, `tools/` (generators), `addons/` (plugins like GUT).

### What exists (M0/M1/M2)

- **Autoloads** — `EventBus` (signals only, no logic; signals for all four systems are already declared), `GameState` (stats, level/XP curve, world flags, a *counted* input lock), `Inventory`, `QuestLog`, `SceneRouter`, `DialogueRunner`, `CombatManager`.
- **`scenes/main.tscn` is the main scene and never unloads.** Maps are swapped in and out of its `WorldRoot` by `SceneRouter.change_map(path, spawn)` — not via `change_scene_to_file`, so the HUD and fade overlay survive transitions. A map arrives at a *named spawn point*; `GameMap._ready()` resolves the name and places the player.
- **`Interactable`** (`scripts/world/interactable.gd`, physics layer 4) is the base for NPC / chest / map exit / boss gate / monster. The player's `InteractSensor` picks the nearest one it's facing and announces it via `EventBus.interact_target_changed`.
- **Persistence is flags, not node state** — e.g. an opened chest sets `GameState` flag `chest_town_square`, so it stays open across map reloads. Monsters are the deliberate exception: they are `queue_free()`d and come back on the next visit, because a player who has hit a wall needs somewhere to earn levels.
- **`ui/hud.gd` is the interact prompt and the player's vitals.** Conversations live in `ui/dialogue_box.tscn`, battles in `ui/combat_screen.tscn`, the tracked quest in `ui/quest_tracker.tscn`; the HUD hides itself while either of the first two is up.

Physics layers: 1 world, 2 player, 3 enemy, 4 interactable. Input actions: `move_up/down/left/right`, `interact`, `inventory`, `journal`.

### The dialogue system

- **Flow and view are separate.** `DialogueRunner` (autoload) walks the graph, evaluates conditions, applies effects and holds the input lock; `ui/dialogue_box.tscn` only draws what it is told and calls `advance()` / `choose(i)` back. `test/dialogue_test.tscn` runs the whole system with no box instantiated — if it passes and the game looks wrong, the bug is in the view.
- **A `Dialogue` is an ordered array of `DialogueLine`s**, run top to bottom. A line's `next` jumps to another line's `id`; `&"end"` (`DialogueLine.END`) closes the box; empty falls through to the next array element. Linear conversations therefore need no ids at all.
- **Entry selection is what makes dialogue reactive.** With `start` empty the runner enters at the first *block-opening* line whose conditions pass, so an NPC greets you differently once you've met them or cleared their floor. A line that the previous line falls through into is a **continuation and never an entry point** — without that rule the second half of a gated block becomes a legal opening line the moment its first half's condition fails. Put specific blocks first, end with an unconditional one.
- **`DialogueCondition`** asks `GameState` one small question (`FLAG_SET`, `FLOOR_CLEARED`, `MIN_LEVEL`, each negatable). A line's or choice's conditions are ANDed; for OR, write two blocks. **`DialogueEffect`** sets a flag, grants XP, or emits `EventBus.item_added` / `quest_started` — dialogue never calls Inventory or QuestLog, so it works before they exist.
- **Locked choices** either vanish (`hide_when_locked`, the default) or stay visible and greyed with a `locked_hint` — "(not until Illfang falls)". The runner refuses out-of-range and locked indices as well as the UI, since it is the one place that must not be talked into an impossible branch.
- **Two entry points, one pipeline**: `DialogueRunner.start(dialogue)` for conversations, `EventBus.message_requested` (→ `say()`) for unbranching text from chests, signs and system notices. A conversation started while one is open is queued, not dropped.
- **`Npc.dialogue` beats `Npc.lines`**; `lines` stays for extras who say one thing. `met_flag` is set *after* the conversation, so a first-meeting block can still see "we haven't met".
- Adding a conversation: a `.tres` in `resources/dialogue/`, then point an NPC's `dialogue` export at it. Hand-writing one is fine — note that typed arrays serialize as `Array[ExtResource("choice")]([SubResource("...")])`, and sub-resources must appear before the resources referencing them.

### The inventory system

- **Two signals, one direction each.** `EventBus.item_granted` is the world saying *"here, have this"* — combat loot, a chest, a dialogue reward — and `Inventory` is its only listener. `EventBus.item_added` is Inventory replying *"it is in the bag"*, and that is what UI and (in M5) quest objectives listen to. Keeping them apart is what stops a full bag from silently reporting success, and what stops `add()` from re-triggering itself. **Nothing outside `Inventory` should emit `item_added`.**
- **Flow and view are separate**, same as dialogue and combat. `Inventory` (autoload) owns the bag; `ui/inventory_screen.tscn` draws it and calls `use()` / `equip()` / `drop_stack()` back. `test/inventory_test.tscn` runs the whole system with no screen instantiated.
- **Gear reaches combat through `GameState` and nowhere else.** Worn bonuses are summed by `Inventory.bonus()` and folded into `GameState.total_attack()` / `total_defense()` / `total_speed()` / `total_max_hp()`; `Combatant.from_player()` reads those. A sword is `+6 attack` by the time combat sees it — **never** add an item lookup to `CombatMath` or `CombatManager`. The bare `GameState.attack` fields are *base* stats; don't read them directly.
- **Equipment leaves the bag when worn.** A slot is a place, not a flag, so the bag count is the truth and unequipping into a full bag is refused rather than quietly deleting a sword. Equipment also never stacks: three swords are three slots, so any one of them can be worn without splitting a pile.
- **`remove()` is all-or-nothing.** Asking for more than there is removes none of it and returns 0 — a caller that spends three and silently gets two taken has a corrupted bag and no way to notice.
- **Consumables are percentages of max HP, never flat points**, for exactly the reason statuses are: a flat 20-point potion is everything on floor 2 and nothing on floor 90.
- **Statuses live on a `Combatant`, so field use can only heal.** An item whose only effect is `applies` declares `usable_in_field = false` and `Inventory.use()` refuses it. In battle it is `CombatManager` that applies the effect; `Inventory.consume()` only empties the bottle.
- **Slot order is bag state, not a view preference.** `Inventory.move_stack(from, to)` is what the screen's drag-and-drop calls, and it decides between merge (same item, target has room), move-to-the-back (target past the last used slot — the bag is a compact list, so every empty slot is the same place) and swap. The screen greys out exactly what `move_stack` would refuse, because it asks the same predicates it paints with.
- **The mouse drives the keyboard's cursor, not a second one.** Hovering a slot *is* selecting it, so there is no moused-over state to keep in step with the arrow-key one. Drag-and-drop goes through `Control.set_drag_forwarding` so slots stay plain `Panel`s and every rule lives in `inventory_screen.gd`; `tools/screenshot.gd` drives a real drag with synthesised mouse events, which is the only way to see the drop-target highlighting.
- **A chest checks `Inventory.fits()` before opening.** Opening is irreversible and the opened-flag would outlive the item it destroyed.
- Adding an item: a `.tres` in `resources/items/`, an id in `ItemLibrary.ITEMS`, and an icon entry in `gen_placeholder_art.py`'s `ITEM_ICONS`. The inventory test will fail if a loot table, chest pool or dialogue effect names an id with no resource behind it.

### The combat system

- **Flow and view are separate**, same as dialogue. `CombatManager` (autoload) owns the turn loop, targeting, statuses, AI and the input lock; `ui/combat_screen.tscn` draws what it announces and answers with `CombatManager.submit(action)`. `test/combat_test.tscn` fights hundreds of battles with no screen instantiated — if it passes and the game looks wrong, the bug is in the view.
- **Items are a combat verb.** `CombatAction.Kind.ITEM` resolves through `_resolve_item()`: it costs the turn but no cooldown and no post-motion, only ever lands on your own side, and spends the item whether or not it healed for full value. `submit()` re-checks the bag, because it can empty between the menu being drawn and the answer arriving.
- **`CombatManager.start(encounter)` is awaitable** and returns a `CombatResult`. That object is all a caller needs: `BossGate` clears the floor on `victory`, a `Monster` frees itself. XP and loot are already granted by the time it arrives.
- **`submit()` is the only door in, and it refuses illegal moves** — a skill on cooldown, an out-of-range target, fleeing a boss. The UI greys those out too, but the runner is the one place that must not be talked into an impossible move. **It must also accept a synchronous answer**: a caller that submits during the `command_requested` signal is answering before the loop parks, which is why the accepted action is held in `_pending` rather than delivered by signal alone.
- **Everything a combatant can do is a `Skill`**, including the plain attack (`SkillLibrary.basic_attack()`). There is no separate enemy-attack path that can drift from the player's.
- **`Combatant` is runtime-only** and dies with the fight; `write_back()` is the single path back into `GameState`, and only the player uses it. HP carries in and out — there is no free heal at the door. Stats come in through `GameState`'s `total_*` accessors, which is where equipment folds in.
- **All balance lives in three places**: `CombatMath` (the formulas), `FloorTuning` (the 100-floor curve), and the `.tres` files (per-enemy stats). Never tune inside `CombatManager`.
- **Mitigation is `attack / (attack + defence)`**, not subtraction and not a fixed curve. A ratio holds its shape whether the numbers are 8 and 4 or 240 and 130; the other two break at one end of a 100-floor climb. `test/combat_test.gd` asserts this directly.
- **The XP curve is linear** (`GameState.XP_BASE + XP_STEP * (level - 1)`) because monster payouts are linear in their level. Making one exponential without the other stalls the climb around floor 17 — measured, not theoretical.
- **Statuses are percentages of max HP, never flat points.** A flat 4-damage poison is everything on floor 2 and nothing on floor 90.
- Adding an enemy: a `.tres` in `resources/enemies/`, a sprite entry in `gen_placeholder_art.py`'s `BATTLERS`, and an id in `Bestiary.ENEMIES` + the relevant `BIOME_POOLS` row. Adding a skill: a `.tres` in `resources/skills/` plus a line in `SkillLibrary.PLAYER_SKILLS` (enemy skills are referenced by their `EnemyType` and need no registry).
- **Boss escorts are capped at one** in `Bestiary._escort_count` *because the party is one*. Two full-strength escorts against a solo player measured at ~1 win in 20 on floor 100. Lift the cap when the party grows, not before.

### The quest system

- **The whole system is one autoload plus six signal handlers**, because every input a quest needs was already being announced by the time it was built: `quest_started` → `start()`, `enemy_defeated` → KILL, `inventory_changed` → COLLECT, `dialogue_finished` → TALK, `floor_cleared` → REACH, `quest_turn_in_requested` → `turn_in()`. **Nothing in combat, inventory, dialogue or the floor system knows `QuestLog` exists.** That is the payoff of the event bus, and it is why quests landed without touching any of them.
- **Quest state is mirrored into `GameState` flags** — `quest_<id>_started`, `_ready`, `_done`. That one decision is what lets an NPC gate a line on a quest, a quest gate itself on another quest, and (later) a chest open only for a quest-holder, all through `DialogueCondition`'s existing `FLAG_SET` test. `DialogueCondition` still only knows about `GameState`, so there is one condition language in the game rather than two that drift. Use `QuestLog.flag_for(id, suffix)` rather than building the string.
- **Prerequisites are `DialogueCondition`s and rewards are `DialogueEffect`s.** Not laziness: a prerequisite asks `GameState` exactly the questions a dialogue line asks, and a reward does exactly what a dialogue effect does — so a quest can pay out by starting another quest for free. They are misnamed for the second job; renaming them would rewrite every dialogue `.tres` for a word.
- **Counted objectives vs. read objectives is the one real decision in the data model.** KILL and TALK are *counted* when they happen, because nothing else remembers a kill. COLLECT and REACH are *read* from the bag and the cleared-floor list, and are recomputed from scratch whenever either changes. So **a collect objective reads the bag; it does not count deliveries** — counting `item_added` would let a player satisfy "bring me five hides" by picking five up and throwing them away, and the objective could never go back down. `QuestObjective.is_state_based()` is that distinction and `QuestLog` is what acts on it.
- **Ready is a state, not a completion.** `needs_turn_in` (the default) parks a quest at `READY` with its `_ready` flag set until the player goes back and says so, which is what a turn-in dialogue branch reads. Ready must be able to come *back off* — spend the hides you were asked for and the quest is not ready any more, or the turn-in fails on arrival. Set `needs_turn_in = false` only when there is nobody on the other end of it.
- **Turn-in re-checks two things rather than trusting them**: the collect items, because the bag can empty on the walk back; and room for the reward, because a quest that pays into a full bag has destroyed what it paid. The room check runs *before* the items are spent, so it is conservative — it can refuse a turn-in that would in fact have fitted once three hides left the bag, and it says so rather than silently eating an Anneal Blade.
- **`turn_in()` closes the quest out before spending the collect items.** Spending them emits `inventory_changed`, which comes straight back as a COLLECT refresh, and a quest still in `_active` at that moment gets its progress reset on the way out the door.
- **The offer and the prerequisites must be gated on the same conditions.** This is the one failure mode the arrangement can produce: a dialogue choice offering a quest `QuestLog.start()` would refuse, so the player picks "I'll take it" and nothing happens. The quest test asserts this directly for both of Argo's offers.
- **Flow and view are separate**, same as everything else. `QuestLog` owns state; `ui/quest_journal.tscn` (**J**) and `ui/quest_tracker.tscn` draw it; `test/quest_test.tscn` runs the whole system with neither instantiated. In the journal the `>` cursor is where the player *is* and colour-plus-glyph is what the quest *is* — never both on one cue, or the selected row and the ready row become indistinguishable.
- Adding a quest: a `.tres` in `resources/quests/`, an id in `QuestLibrary.QUESTS`, and a dialogue branch that offers it (plus one that takes it back, if it needs turning in). `QuestLog.accept(quest)` takes a resource directly for anything that isn't shipped content — the library is a lookup, not a gatekeeper, but the rules still live in the log.

### Roaming monsters

- **A `Monster` is still an `Interactable`, and now it moves.** Wander (a leash round its spawn point) → notice (`AGGRO_RADIUS` plus a raycast on layer 1) → chase at `CHASE_SPEED` 62, *below* the player's 90 → give up past `LOSE_RADIUS` / `LEASH_RADIUS` / a second out of sight → walk home. Contact is its `Contact` area overlapping the player's body, not a keypress; pressing **E** is still a way in.
- **It has no solid body.** It steps by asking the physics space whether its probe fits (`_free_at`), sliding per axis, so it respects walls while nothing can collide with *it*. That is what keeps "a monster can never wall off a corridor" true and keeps it out of the floor test's flood fill. Don't turn it into a `CharacterBody2D`.
- **Who struck first is `Encounter.opening`.** E on a monster that isn't chasing → `PARTY_FIRST`; run down facing away → `ENEMIES_FIRST`; otherwise `NORMAL`. `CombatManager` only honours it in round 1 (`_turn_order()`) and announces it with a `CombatReport.Kind.OPENING`. **The monster decides, combat never learns what a map is.** Bosses stay `NORMAL`.
- **Nothing engages through the input lock** — the monster freezes entirely while it is held. After a fight it survived, it is `STUNNED` for `GRACE_SECONDS` and then walks home ignoring the player; after *any* fight, every monster is calm for `CALM_SECONDS`, so winning one never drops you into the next. Keep it longer than the combat screen's `OUTRO_TIME`: the result covers the map while the player can already move.
- Wandering uses the global RNG on purpose: behaviour, not generation. Nothing about a floor's seed depends on where a boar drifted.
- The camera is `zoom = 2` in `player.tscn` (320×180 visible). The floor test refuses an authored map smaller than one view, because `Camera2D` resolves limits tighter than the screen by pinning right/bottom and showing the void top-left.

### The floor system

- **`FloorDefinition`** (`.tres`) describes a floor. If it has an `authored_scene` it's hand-built; otherwise it's generated. `FloorRegistry` returns one for any floor 1–100, synthesising non-authored ones from the biome band table + `FloorTuning`.
- **`FloorRegistry.build_floor(n)`** is the single entry point — it hides which kind you got. `SceneRouter.enter_floor(n, spawn)` is what gameplay calls.
- **`FloorGenerator`** builds rooms + L-corridors and returns *the same node shape as an authored map* (`Ground` / `Walls` / `SpawnPoints` / `Player` + interactables). Keep it that way: `GameMap`, the camera and the router all depend on that shape and on nothing else.
- **`MapDresser.dress()` dresses the finished layout, and it runs last** — called by `FloorGenerator` and by `authored_floor.gd`'s `_join_walls()` alike, so a built floor and a generated one follow one rule. It is a pass over the finished layout, not a step in building it: carving, decor and the reachability check all happen against plain slot tiles, so the layout can never depend on which tile a cell ended up drawing. A BLOB biome's wall mass is autotiled — only cells still holding `wall_tile` join (decor on the same layer carries no terrain, so the mass draws an edge against a boulder), and `ignore_empty_terrains` must stay `false`, since a carved cell has no terrain and those are precisely the neighbours an edge tile is chosen against. A biome whose `wall_terrain_set` is -1 ships flat. Forest walls, ground and water are under "Map dressing and the art pack".
- **Determinism is a requirement, not a nicety.** Seeds come from `FloorRegistry.seed_for(n)` = `hash(world_seed, floor_number)`. Never use unseeded `randi()` in generation — it breaks save consistency and makes bugs irreproducible.
- **`FloorTuning`** holds the whole 100-floor curve (level, map size, room/chest counts, boss names). Balance changes go there, not into individual floors.
- **Progression** is `GameState.clear_floor(n)` → `is_floor_unlocked(n+1)`. `BossGate` is the gate, and it runs a real fight (`Bestiary.boss_encounter(n)`). Losing drops the player at the floor entrance on 35% HP with the floor rebuilt, so its monsters are back — the way through a wall is levels.
- **Every generated floor carries `FloorTuning.monster_count(n)` roaming monsters.** That count is not decoration: it is the measured number of kills that puts a player at the level the floor's boss expects. Monsters have no solid body (they test walls to move, but nothing collides with them), so they can never wall off a corridor and the completability flood fill never sees them.
- Adding a milestone floor: a `tools/build_floor_NN.gd` that extends `tools/authored_floor.gd` — layout tables plus a `_build()`; the base does painting, wall joining, placing entities, the reachability check and the save — then a `FloorDefinition` `.tres` in `resources/floors/`, registered in `FloorRegistry.AUTHORED` (explicit dictionary — `res://` directory scanning is unreliable in exported builds). An authored boss also wants an id in `Bestiary.AUTHORED_BOSSES`, which overrides the archetype the floor would otherwise have been given; go in near that archetype's numbers and check the combat suite's win rate doesn't move. **Authored does not mean exempt from the curve**: a floor carries at least `FloorTuning.monster_count(n)` monsters at `FloorTuning.enemy_level(n)`, and the floor test enforces the count.
- **Floor 10 is one map, where Floor 1 is two.** Floor 1 splits town and field across a `MapExit`, which is fine there because the boss is a one-way trip. Ashlow has a quest that sends you to the Warden and then *back to the village to report*, so the walk home has to exist — and one map is the version of that walk costing no fade, no second scene and no second set of spawn points. `tools/build_floor_10.gd` is the authoring surface: layout tables at the top, the same carve/join passes the generator uses, and a flood fill that refuses to write an unfinishable floor.
- **Floor 25 is a chain, where Floor 10 is a loop**, and a one-way lift is how the chain gets you home: a `MapExit` whose `target_map` is its own scene, arriving at a `from_lift` spawn in the camp. It stands at the bottom, so the long way down is still the only way down, and the reload is the fare — the floor's monsters come back. Its caverns are `_carve_cave()` ellipses rather than rects; the wobble only pulls inwards, so a cave stays inside the rect its table gives it.

### Map dressing and the art pack

- **Everything dressing adds is visual.** `Walls` keeps every collision it had and gains none; standing things go on `Props` (y-sorted) and flat scatter on `Decor`, both with collision off. That is what keeps the floor test's flood fill — which only reads `Walls` — true without it knowing dressing exists. The floor test checks the layers stay that way.
- **A biome's wall mass has a style.** `BLOB` autotiles it; `TREES` leaves the `wall_tile` cells alone (plain grass underneath, still solid) and plants 2×2 trees over them on a staggered lattice, then fills whatever the lattice missed with a tree or a bush. The floor test refuses a forest edge with nothing standing on it — the forest's version of a mis-paired blob tile. Caves and ruins are meant to get cliffs, the castle stone walls: the pack's outdoor maps wall with trees, and its cliff tiles are for raised ground.
- **Ground and water join by nearest match, not `set_cells_terrain_connect`.** `MapDresser.TerrainMatcher` scores every tile of the right centre against the cell's neighbourhood and takes the closest (ties broken by the cell's hash, so repainting never reshuffles grass). Godot's solver propagates a missing arrangement into the neighbours instead of settling. Path and special slots are dirt, everything else grass. The pack draws its shores only onto its light grass, so a biome on another grass gives `liquid_palette`: two blocks of one sheet drawn alike in two palettes, from which `build_biomes.gd` reads a colour swap and repaints the shoreline — the forest's ponds.
- **The pack draws a transition inside the terrain's own cells.** A path cell beside grass shows dirt on its inner half, a one-wide path is a strip down the middle, and the grass around a path is always plain grass. Two consequences: a 2-wide road *reads* 1 wide, so lay roads 3 wide; and the floor test can demand exact edges (it does) — a dirt cell must describe its real neighbourhood, a grass cell must be plain.
- **Standing tiles are anchored at the bottom row of their footprint** and sort from its bottom edge. `build_biomes.gd`'s `_stand_up()` sets that (`texture_origin`, `y_sort_origin`) and `MapDresser.footprint()` is its inverse — change one, change both. The map root is `y_sort_enabled`; `Ground`/`Walls` sit at `z_index` -2 and `Decor` at -1. `GameMap`'s camera limits read only `Ground` and `Walls`, because a crown on the forest's top row hangs a row above the map.
- **Houses on authored maps** are a footprint and a prop: the bottom rows painted in the invisible `wall_alt` slot (solid), the house tile placed on `Props` with `MapDresser.anchor_for()` *after* `dress()`. The roof's top row stays walkable, so you pass behind it. `authored_floor.gd`'s `_house(rect, variant)` does both on any biome with `house_tiles` (and keeps the old roof-and-wall-course block on one without — Lanternfall, for now), and refuses a rect that isn't exactly its house tile's size.
- **Characters use the pack's sheet layout**: 4 columns (down, up, left, right) by 7 rows, the first 4 the walk cycle; `Npc.sprite_sheet` picks a character, and dialogue portraits are the character's `Faceset.png`. Monsters get `EnemyType.sheet` + `sheet_frames` — 4×4 is four directions, N×1 a side view drawn facing right — and `battler` becomes an `AtlasTexture` frame of it. The combat screen scales a battler by a whole number (×4 at 16 px, ×2 under 64, placeholders ×1).
- **Dressing is deterministic**: the seeded rng is asked in reading order, never in used-cell (hash map) order.
- Converting a biome: an entry in `PACK_BIOMES`, rebuild, and look — `tools/screenshot.gd` stands the player behind a roof, under a grove, at the pond and at the door (`04j`–`04m`), which is the only way to see the depth sort.

## Godot 4.7 gotchas

- GDScript 2.0 syntax: `@export`, `@onready`, `signal name(args)`, `await signal_or_coroutine`, typed variables (`var hp: int = 10`). Do not use Godot 3.x idioms (`export var`, `yield`, `.instance()` → now `.instantiate()`).
- Every `.tscn`/`.gd`/asset has a companion `.uid`/`.import` or embedded UID; when moving files, use the editor's FileSystem dock (or update references) so `uid://` and `res://` paths stay valid.
- Rendering is **Mobile** and stretch mode is `canvas_items` with `expand` aspect — the 2D UI scales cleanly across resolutions; design UI with anchors/containers, not fixed pixel positions. The base viewport is 640x360, so UI is laid out in those units.
- `TileSetAtlasSource` must be added to the `TileSet` *before* creating tiles, or the tiles get no physics layers and every collision-polygon call fails silently-ish (an error per tile).
- GDScript lambdas capture locals **by value** — a lambda that writes to a captured local silently discards the write. Use a member variable for signal spies and accumulators.
- `Input.action_press()` sets the action's *state* but never synthesises an event, so nothing in `_unhandled_input` sees it. To drive UI from a tool or test, feed a real `InputEventAction` through `Input.parse_input_event()` (see `tools/screenshot.gd`).
- **A tile painted at runtime gets its collision on a later frame.** `set_cell()` on a `TileMapLayer` queues the physics update; a raycast in the same physics tick sees through the new wall. A test that paints geometry should wait a few physics frames before anything looks at it.
- **`PortableCompressedTexture2D` drops its source buffer outside the editor.** A `--script` tool that builds one and saves it writes an empty texture, and every tile of a TileSet using it then fails to load ("Cannot create tile... outside the texture"). Set `keep_compressed_buffer = true` before `create_from_image()`.
- **`TileData.texture_origin` moves a tile's texture up and left** — it is drawn at the cell centre − size/2 − origin — and a multi-cell atlas tile is drawn centred on the cell it is placed in.
- **`await some_signal` parks unconditionally**, even if the thing you are waiting for already happened during the emit that preceded it. Any coroutine that emits a request and then awaits the reply needs a "did it already answer?" check first, or a synchronous responder deadlocks it. `CombatManager._decide()` is the worked example.
