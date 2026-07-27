# Tests

Six suites, no dependencies. Each exits non-zero on failure.

```sh
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . res://test/smoke_test.tscn      # the game loop
"$GODOT" --headless --path . res://test/floor_test.tscn      # the 100-floor spine
"$GODOT" --headless --path . res://test/dialogue_test.tscn   # the dialogue system
"$GODOT" --headless --path . res://test/inventory_test.tscn  # the inventory system
"$GODOT" --headless --path . res://test/combat_test.tscn     # the combat system (~20s)
"$GODOT" --headless --path . res://test/quest_test.tscn      # the quest system
```

They run as **scenes**, not with `--script`. Autoloads are registered after a
script main loop is compiled, so `EventBus` & co. wouldn't resolve there.

## Smoke test

Boots `scenes/main.tscn` for real and walks the whole loop: spawn placement, wall
collision, interact targeting, talking to an NPC, chest flags, map transition,
clearing floor 1, ascending into a generated floor 2, XP/level-up — plus a quest
taken in town and finished by the boss fight it asked for, which is the one place
that proves `QuestLog` is wired into a *running* game rather than into a test.

## Floor test

Registry lookups, biome bands, seed determinism, progression gating — and a
flood-fill of **all 99 generated floors** proving the boss door and every chest
are reachable. Keep that check: an unfinishable dungeon is the bug procgen
reliably ships and playtesting will not find it.

## Dialogue test

Conditions, entry selection (including the block rule that keeps a continuation
line from becoming an opening line), branching, locked and hidden choices,
effects, the queue, `cancel()`, and input-lock balance — against the real Argo
and Nezha resources. It instantiates **no dialogue box**: the runner is driven
directly through `advance()` / `choose()`, so a failure here is a flow bug and
never a layout one.

## Inventory test

Stacking and slot caps, all-or-nothing removal, the `item_granted` -> `item_added`
channel, consumables in the field and in battle, equipping and the swap, what
the screen's drag-and-drop moves (`move_stack`: merge if it fits, else swap), and the
one thing nothing else would catch: **every item id the rest of the game already
emits has a resource behind it** — enemy loot tables, generated-chest contents,
dialogue's `GIVE_ITEM`. An id with no `.tres` lands in an empty bag silently.

It also checks that gear reaches the fight. Equipment folds into `GameState`'s
`total_*` accessors and nowhere else, and `Combatant.from_player()` reads those,
so an edit that breaks the chain shows up as a fighter with the wrong attack.
Instantiates **no inventory screen**.

## Combat test

Content loading, scaling, formulas, statuses, cooldowns, stagger, the turn loop,
the rules `submit()` enforces, seed determinism, and **measured** win rates
against real bosses. The balance section is load-bearing: its numbers were
measured, not chosen, so a stat or curve edit that makes floor 50 unwinnable
fails here rather than 20 hours into a playthrough.

## Quest test

Availability and prerequisites, all four objective kinds, ready coming back *off*
again, turn-in (including the two things it re-checks: the collect items, and room
for the reward), rewards chaining into the next quest, the `GameState` flag bridge,
journal ordering, and the tracker's fallback. It drives Argo's **real** conversation
through the runner to prove the offers and the turn-in branch appear exactly when
the log would accept them — the one failure mode of gating quests in dialogue is a
choice offered for a quest `QuestLog.start()` would refuse.

The load-bearing part is the **objective-target sweep**: every KILL names an enemy
id, every COLLECT an item id, every TALK a conversation, every REACH a floor in
range. It is the inventory sweep one layer up, and it exists for the same reason —
a typo'd target makes an objective that can never be completed, and nothing else
in the game will say so.

Every section calls `_reset()` first. For a system built entirely out of persistent
flags, leftovers from the previous section are the easiest way to write a test that
proves nothing. Instantiates **no journal and no tracker**.

## GUT (not installed yet)

Once [GUT](https://github.com/bitwes/Gut) is in `addons/gut/`, unit tests go
here as `test_*.gd` and run with:

```sh
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://test -gexit
```

Good first targets: `GameState` XP curve and flags. The six suites above stay
as the integration-level checks.
