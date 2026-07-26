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
signal item_added(item_id: StringName, amount: int)
signal item_removed(item_id: StringName, amount: int)
signal item_used(item_id: StringName)
signal item_equipped(slot: StringName, item_id: StringName)

# --- Combat (M4) ---
signal combat_started(encounter_id: StringName)
signal combat_ended(victory: bool)
signal turn_started(actor_name: String)
signal turn_ended(actor_name: String)
signal enemy_defeated(enemy_id: StringName)
## The party fled instead of finishing the fight. Separate from
## [signal combat_ended] because quests count kills, not escapes.
signal combat_fled()

# --- Quests (M5) ---
signal quest_started(quest_id: StringName)
signal quest_objective_updated(quest_id: StringName, objective_id: StringName, progress: int, required: int)
signal quest_completed(quest_id: StringName)

# --- Progression / persistent state ---
signal flag_changed(flag: StringName, value: Variant)
signal hp_changed(hp: int, max_hp: int)
signal xp_gained(amount: int)
signal leveled_up(new_level: int)
signal floor_cleared(floor_number: int)
