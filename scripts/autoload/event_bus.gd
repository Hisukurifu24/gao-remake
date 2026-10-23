extends Node
## Global signal bus.
##
## Systems announce facts here instead of calling into each other. Anything may
## emit; anything may connect. Signals are declared up-front (even for systems
## that don't exist yet) so the wiring points are visible while building.
##
## Rule of thumb: emit *what happened*, never *what to do about it*.

# --- World / interaction (M1) ---
## The interactable the player is currently facing, or null when there is none.
signal interact_target_changed(target: Node)
## Unbranching text with no author behind it: chests, signs, system notices.
## DialogueRunner picks this up and shows it in the same box as a real
## conversation. Anything a character *says* should be a [Dialogue] instead.
signal message_requested(speaker: String, lines: PackedStringArray)

# --- Dialogue (M2) ---
signal dialogue_started(dialogue_id: StringName)
signal dialogue_finished(dialogue_id: StringName)
signal choice_selected(dialogue_id: StringName, choice_index: int)

# --- Inventory (M3) ---
## The world is handing the player something: combat loot, a chest, a dialogue
## reward. A *request*, and the one exception to the rule of thumb above --
## [Inventory] is its only listener and answers with [signal item_added]. Emit
## this rather than calling Inventory, so a giver never has to know whether an
## inventory exists or what a full bag does.
signal item_granted(item_id: StringName, amount: int)
## It is in the bag. [param amount] is what was actually accepted, which is not
## always what was granted.
signal item_added(item_id: StringName, amount: int)
signal item_removed(item_id: StringName, amount: int)
signal item_used(item_id: StringName)
## [param item_id] is [code]&""[/code] when the slot was emptied.
signal item_equipped(slot: StringName, item_id: StringName)
## The smith's work took: one copy of [param item_id] is now +[param plus].
signal item_enhanced(item_id: StringName, plus: int)
## Nothing fit. [param lost] is how many of the grant fell on the floor.
signal inventory_full(item_id: StringName, lost: int)
## Anything at all changed: added, removed, worn, sorted. For views that repaint
## wholesale rather than tracking individual stacks.
signal inventory_changed()

# --- Col (M5.6) ---
## Exactly the [signal item_granted] / [signal item_added] pair, for money. The
## world paying -- a kill, a chest, a sale, a quest -- is [signal col_granted], a
## *request* whose only listener is the purse in [GameState]; the purse answers
## with [signal col_changed]. Nothing but the purse emits [signal col_changed].
signal col_granted(amount: int)
## The world charging: a dialogue line that costs money. Also a request, and the
## purse refuses it whole if it cannot pay -- gate the line on MIN_COL.
signal col_charged(amount: int)
## The purse's reply to either, and to a purchase or a drop: [param col] is what
## it holds now.
signal col_changed(col: int)
## The player fell and the purse fell with them, at [param position] on
## [param map_id] -- or, with [param amount] 0, the Col lying there was picked up
## or lost to a second fall. Emitted by the purse; [GameMap] puts the pouch down.
signal col_dropped(map_id: StringName, position: Vector2, amount: int)
## The player is at a shop counter. A request, like [signal teleport_requested]:
## the shop screen is its only listener.
signal shop_requested(shop: Shop)
## The player asked a smith to work on their gear -- a [Smith]'s forge. A request:
## the forge screen is its only listener, and opens once any conversation that
## asked for it has closed.
signal forge_requested(smith: Smith)

# --- Combat (M4) ---
## A fight is about to start where the player stands, and this is where
## everyone in it will stand. Emitted by whoever starts the fight, just before
## [method CombatManager.start]; the view pairs the field's nodes with the
## combatants. A fight with no field (a test, nowhere to stand) is drawn by
## nothing but [BattleHud]'s plates.
signal battle_staged(field: BattleField)
signal combat_started(encounter_id: StringName)
signal combat_ended(victory: bool)
signal turn_started(actor_name: String)
signal turn_ended(actor_name: String)
signal enemy_defeated(enemy_id: StringName)
## The party fled instead of finishing the fight. Separate from
## [signal combat_ended] because quests count kills, not escapes.
signal combat_fled()

# --- Quests (M5) ---
## Two signals per direction, exactly like [signal item_granted] /
## [signal item_added]: the *_requested pair below is the world asking, and the
## other four are [QuestLog] reporting what it did about it. A quest whose
## prerequisites fail is asked for and never accepted, and the journal has to be
## able to tell those apart.

## Somebody is offering the player a quest -- a dialogue choice, another quest's
## reward. A *request*: [QuestLog] is its only listener and answers with
## [signal quest_accepted].
signal quest_started(quest_id: StringName)
## It is in the journal. Prerequisites passed and it was not already taken.
signal quest_accepted(quest_id: StringName)
signal quest_objective_updated(quest_id: StringName, objective_id: StringName, progress: int, required: int)
## Every objective is met and the quest wants turning in. Fires once per quest;
## the tracker uses it to say "go and see Argo".
signal quest_ready(quest_id: StringName)
## The player is telling the giver it is done. A *request*, same as
## [signal quest_started] -- [QuestLog] refuses it unless the quest is ready, and
## answers with [signal quest_completed].
signal quest_turn_in_requested(quest_id: StringName)
## Paid out and closed.
signal quest_completed(quest_id: StringName)
## Anything at all changed: accepted, advanced, turned in. For views that repaint
## wholesale rather than tracking one quest.
signal quest_log_changed()

# --- Progression / persistent state ---
signal flag_changed(flag: StringName, value: Variant)
## The input lock went on (the first push) or came off (the last pop). For views
## that step aside while anything holds the screen -- a shop, the gate menu, a fade
## -- without having to know what each of those is.
signal input_lock_changed(locked: bool)
## The game menu opened or closed. For views that would show through its dim --
## the vitals, under the tab strip. Nothing in the game reacts to it.
signal game_menu_toggled(open: bool)
signal hp_changed(hp: int, max_hp: int)
signal xp_gained(amount: int)
signal leveled_up(new_level: int)
signal floor_cleared(floor_number: int)
## The player touched the teleport gate on [param floor_number] and wants to go
## somewhere. A *request*, like [signal item_granted]: the gate menu is its only
## listener, and answers by sending them -- or by not, if they think better of it.
signal teleport_requested(floor_number: int)
## The player walked into a floor's hidden boss room and the door showed itself.
signal boss_room_found(floor_number: int)

# --- The save ---
## The game was written to [param slot] -- asked for, or an autosave. For the
## view that says so; nothing in the game reacts to having been saved.
signal game_saved(slot: int, auto: bool)
## A save was read back and the player is standing where it left them.
signal game_loaded(slot: int)
## The game has been left -- quit from the pause menu, or ended by a death game --
## and the title screen should come up, saying [param notice] if it isn't empty.
## Also how the game proper boots. The title screen is its only listener.
signal title_requested(notice: String)
