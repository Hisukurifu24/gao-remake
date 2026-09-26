# GAO Remake

A 2D top-down RPG built in **Godot 4.7**, set in a *Sword Art Online*–inspired world: a stacked floating castle where players are trapped in a death-game VRMMO and climb, one floor boss at a time, toward the top.

**100 floors, and the loop is completable end to end** — walk, talk, take a job, fight the monsters standing on the floor, level up, beat the boss, ascend. Ten milestone floors are hand-authored; the rest are procedurally generated from a deterministic seed.

```
  Town of Beginnings  ──►  the field  ──►  the labyrinth  ──►  Illfang  ──►  Floor 2 ──► … ──► 100
    talk, take a job        fight              climb           boss        generated
```

---

## Status

| Milestone | | |
|---|---|---|
| **M0** — Foundation | ✅ | Autoloads, folder layout, Mobile renderer, 320×180 |
| **M1** — Overworld & movement | ✅ | Player controller, tilemaps, interaction, map transitions |
| **M2** — Dialogue | ✅ | Resource-driven graph, conditions, branching, effects |
| **M3** — Inventory & items | ✅ | Stacking bag, equipment, consumables in and out of battle |
| **M4** — Turn-based combat | ✅ | Turn loop, skills, statuses, stagger, AI, measured balance |
| **M5** — Quests & progression | ✅ | `QuestLog`, four objective kinds, turn-in, journal and tracker |
| **M6** — World depth | ◐ | The 100-floor spine, wall autotiling, and authored Floors 10 and 25 are in; seven milestone floors are not |
| **M7** — Save/load, polish, audio | ⬜ | |

Art is programmer-generated placeholder throughout — deliberately, until the systems settle. See [`plan.md`](plan.md) for the full roadmap, including what was deferred and why.

---

## Quick start

Requires **Godot 4.7** (standard build, no C#). The engine binary lives inside the app bundle on macOS:

```sh
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"

"$GODOT" --path .            # play
"$GODOT" --editor --path .   # open in the editor
```

There is no build step — Godot imports assets and runs scenes directly. `.godot/` is generated cache and is gitignored; if imports look stale, delete `.godot/imported/` and run `"$GODOT" --headless --path . --import`.

### Controls

| | |
|---|---|
| **WASD** / arrows | Move |
| **E** | Interact — talk, open chests, take exits, start a boss fight |
| **E** / arrows | Advance dialogue, pick a choice |
| **I** / Tab | Open the bag |
| **E** / **Q** / **R** | In the bag: use or equip, drop, sort |
| Mouse | In the bag: hover to inspect, right-click or double-click to use or equip, drag to move, equip, unequip or discard |
| **J** | Open the quest journal |
| **E** | In the journal: track the selected quest |

---

## Features

**Turn-based combat.** Turn order by speed, recomputed every round so a slow debuff bites immediately. Everything a combatant can do is a `Skill` resource — including the plain attack — so there is no separate enemy path that can drift from the player's. Named sword skills carry cooldowns and post-motion vulnerability windows: Vorpal Strike hits for 265% and leaves you eating 1.35× damage for two rounds. Poise breaks into stagger; statuses are percentages of max HP so poison means the same thing on floor 2 and floor 90.

**Inventory.** A slot-capped bag of `Item` resources: things stack, equipment does not. Worn gear folds into `GameState`'s `total_*` accessors and nowhere else, so a sword is `+6 attack` by the time combat sees it — no line of `CombatMath` knows items exist. The world hands things over on `EventBus.item_granted` and the bag answers with `item_added`, which is what keeps a full bag from silently reporting a success. Potions are a percentage of max HP, never flat points, so they still buy a turn on floor 90. The bag is drag-and-drop: stacks reorder, merge into their own kind, cross into an equipment slot to be worn or onto Discard to be thrown away — and every one of those rules lives in the autoload, so the screen can only ever ask.

**Dialogue.** A custom `Resource` graph rather than a plugin, so conversations live on the same `.tres` model as skills and enemies and their conditions read `GameState` flags directly. NPCs greet you differently once you've met them or cleared their floor; locked choices either vanish or grey out with a hint — *"(not until Illfang falls)"*.

**Quests.** `Quest` resources with kill / collect / talk / reach objectives, prerequisites, and rewards that can chain into the next job. The whole system is one autoload and six signal handlers, because every input it needed was already being announced — combat, inventory, dialogue and the floor system are untouched by it and still don't know `QuestLog` exists. Quest state is mirrored into `GameState` flags, which is how an NPC gates a line on a quest through the *same* condition type dialogue already had: Argo offers the errand, asks how it's going, takes the report, then offers the follow-up. Collect objectives **read the bag rather than counting deliveries**, so they can go back down when you spend what you were asked for — and the turn-in re-checks both the items and the room for the reward before paying.

**The floor system.** `FloorRegistry.build_floor(n)` returns any floor 1–100 and hides which kind you got. Generated floors are rooms joined by L-corridors with a boss room at the far end, drawn from ten biome bands (meadow → forest → cave → ruins → swamp → desert → ice → volcanic → sky → Ruby Palace). Seeds are `hash(world_seed, floor_number)`, so floor 37 is always the same floor 37 in a given save and bugs reproduce.

**Progression.** A single 100-floor curve in `FloorTuning` — level, map size, room and chest counts, boss names — not 100 tuned files. Lose to a boss and you wake at the floor entrance on 35% HP with the floor rebuilt and its monsters back; the way through a wall is levels.

---

## Architecture

Godot-idiomatic: scenes of nodes, behaviour in GDScript, cross-scene state in autoload singletons, and systems that talk over signals instead of reaching into each other.

```
                      EventBus  (signals only, no logic)
     ┌───────────┬───────────┼───────────┬───────────┐
 Dialogue     Combat      Floors     Inventory    Quests
     └───────────┴───────────┼───────────┴───────────┘
                        GameState   (stats, level, flags, input lock)
```

- **`scenes/main.tscn` is the main scene and never unloads.** Maps are swapped into its `WorldRoot` by `SceneRouter`, so the HUD and fade overlay survive transitions.
- **Flow and view are separate, everywhere.** `DialogueRunner`, `CombatManager`, `Inventory` and `QuestLog` own their logic and the input lock; the screens in `ui/` only draw what they're told. Every headless suite drives its autoload with no UI instantiated at all — if they pass and the game looks wrong, the bug is in the view.
- **The runner is the authority, not the UI.** `CombatManager.submit()` refuses a skill on cooldown, an out-of-range target, or fleeing a boss even though the screen greys those out too.
- **Content is data.** Items, enemies, skills, statuses, dialogue, quests and floors are `Resource` subclasses saved as `.tres`. Adding an enemy is a file plus two registry lines, not a code change.
- **Persistence is flags, not node state** — an opened chest sets a `GameState` flag, so it stays open across map reloads. Quest state is mirrored into the same flags, which is how dialogue reads it without knowing quests exist.
- **All balance lives in three places**: `CombatMath` (formulas), `FloorTuning` (the 100-floor curve), and the `.tres` files (per-enemy stats). Never inside `CombatManager`.

```
scenes/      player, world maps, main
scripts/     autoload/  combat/  inventory/  player/  quests/  resources/  world/
resources/   biomes  dialogue  enemies  floors  items  quests  skills  statuses  tilesets
ui/          hud, dialogue box, combat screen, inventory screen, quest journal, quest tracker
tools/       placeholder-art, biome and map generators
test/        six headless suites
```

---

## Tests

Six headless suites, all exiting non-zero on failure:

```sh
"$GODOT" --headless --path . res://test/smoke_test.tscn      #  41 checks — the game loop, end to end
"$GODOT" --headless --path . res://test/floor_test.tscn      #  25 checks — registry, seeds, every floor walked
"$GODOT" --headless --path . res://test/dialogue_test.tscn   #  56 checks — conditions, branching, effects
"$GODOT" --headless --path . res://test/inventory_test.tscn  # 126 checks — stacking, equipment, item ids
"$GODOT" --headless --path . res://test/combat_test.tscn     #  74 checks — formulas, turn loop, balance
"$GODOT" --headless --path . res://test/quest_test.tscn      # 173 checks — objectives, turn-in, flag bridge
```

Run them as **scenes**, not with `--script` — autoloads are registered after a script main loop is compiled, so `EventBus` and friends don't resolve there.

Four checks are load-bearing:

- **The floor test flood-fills every generated floor**, and walks every hand-built one, to prove the boss door and every chest are reachable. An unreachable boss door is the bug procedural generation reliably ships, hand-building ships it just as easily, and playtesting will not find it.
- **The combat test's balance section** fights hundreds of battles and asserts measured win rates — every band's boss beatable at its floor's level, an underlevelled player reliably losing. A stat edit that makes floor 50 unwinnable fails here instead of 20 hours into a playthrough.
- **The inventory test's id sweep** checks that every item id the rest of the game already emits — enemy loot tables, generated and authored chest contents, dialogue rewards — has a resource behind it. A typo'd id is silent everywhere else: the drop just never arrives.
- **The quest test's objective-target sweep** is the same failure one layer up: every kill objective must name a real enemy, every collect a real item, every talk a real conversation. A typo makes an objective that can never be completed, and nothing else will say so.

---

## Tooling

Placeholder art and derived resources are generated, not committed by hand. Run in order — each step consumes the previous one's output:

```sh
python3 tools/gen_placeholder_art.py                                          # atlases, sprites, portraits, item icons
"$GODOT" --headless --path . --import                                         # so the next step cuts tiles from the new atlases
"$GODOT" --headless --path . --script res://tools/build_biomes.gd             # TileSets + BiomeKits
"$GODOT" --headless --path . --script res://tools/build_placeholder_maps.gd   # the authored Floor 1 maps
"$GODOT" --headless --path . --script res://tools/build_floor_10.gd           # Ashlow Wood
"$GODOT" --headless --path . --script res://tools/build_floor_25.gd           # Lanternfall
```

Maps are engine-generated because `tile_map_data` is a binary blob inside the `.tscn` and can't be hand-authored as text. All biome atlases share one semantic slot layout, so a new biome is a palette entry plus a table row — no generator changes. The milestone-floor tools share `tools/authored_floor.gd`, so a new milestone floor is its layout tables and nothing else; run one with `-- --preview` to see the layout as text without writing it.

> ⚠ `build_placeholder_maps.gd` **overwrites** `town.tscn` and `field.tscn`, and each `build_floor_NN.gd` overwrites its `floor_NN.tscn`. Stop running a tool once its map is being painted in the editor. `build_biomes.gd` is always safe — it only touches derived resources.

---

## Contributing

[`CLAUDE.md`](CLAUDE.md) documents the conventions and the Godot 4.7 gotchas worth knowing before touching this code — the autoload/signal boundaries, why dialogue is custom, and where balance is allowed to live. [`plan.md`](plan.md) is the roadmap and the source of truth for what's built.

---

## Notice

A personal fan project, unaffiliated with and unendorsed by the rights holders of *Sword Art Online*. All code and placeholder art here are original; no assets from the source material are used or redistributed.
