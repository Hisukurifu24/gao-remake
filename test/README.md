# Tests

Three suites, no dependencies. Each exits non-zero on failure.

```sh
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . res://test/smoke_test.tscn     # the game loop
"$GODOT" --headless --path . res://test/floor_test.tscn     # the 100-floor spine
"$GODOT" --headless --path . res://test/dialogue_test.tscn  # the dialogue system
```

They run as **scenes**, not with `--script`. Autoloads are registered after a
script main loop is compiled, so `EventBus` & co. wouldn't resolve there.

## Smoke test

Boots `scenes/main.tscn` for real and walks the whole loop: spawn placement, wall
collision, interact targeting, talking to an NPC, chest flags, map transition,
clearing floor 1, ascending into a generated floor 2, XP/level-up.

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

## GUT (not installed yet)

Once [GUT](https://github.com/bitwes/Gut) is in `addons/gut/`, unit tests go
here as `test_*.gd` and run with:

```sh
"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://test -gexit
```

Good first targets: `GameState` XP curve and flags, `Inventory` stacking (M3),
damage formulas (M4). The smoke test stays as the integration-level check.
