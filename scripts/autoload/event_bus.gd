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
## Nothing fit. [param lost] is how many of the grant fell on the floor.
signal inventory_full(item_id: StringName, lost: int)
## Anything at all changed: added, removed, worn, sorted. For views that repaint
## wholesale rather than tracking individual stacks.
signal inventory_changed()

# --- Combat (M4) ---
## A fight is about to start where the player stands, and this is where
## everyone in it will stand. Emitted by whoever starts the fight, just before
## [method CombatManager.start]; the view pairs the field's nodes with the
## combatants. A fight with no field (a test, nowhere to stand) is drawn on the
## battle screen instead.
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
signal hp_changed(hp: int, max_hp: int)
signal xp_gained(amount: int)
signal leveled_up(new_level: int)
signal floor_cleared(floor_number: int)
## The player walked into a floor's hidden boss room and the door showed itself.
signal boss_room_found(floor_number: int)
