extends Node
## Global signal bus. All cross-system communication goes through here.
## Systems emit signals; other systems connect and react.

# -- Card events --
signal card_played(card_data: CardData, target)
signal card_drawn(card_data: CardData)
signal card_discarded(card_data: CardData)
signal card_exhausted(card_data: CardData)

# -- Combat events --
signal combat_started()
signal combat_won()
signal combat_lost()
signal player_turn_started()
signal enemy_turn_started()
## Fired just before a single enemy resolves its move, so the UI can pace the
## enemy turn: announce "X uses Y", lunge the model, then the effect lands.
signal enemy_action_started(enemy, move)
## Fired instead of enemy_action_started when a Frozen enemy skips its turn, so
## the UI can float a "Frozen!" callout in place of the usual move announcement.
signal enemy_stunned(enemy)
signal turn_ended()
signal player_damaged(amount: int, new_hp: int)
## Fired when the player recovers HP (heal effects, the control-heal passive). Lets the
## combat UI log it and refresh the bar, mirroring player_damaged.
signal player_healed(amount: int, new_hp: int)
signal enemy_damaged(enemy, amount: int, new_hp: int)
## Fired when an enemy recovers HP (e.g. the Hollow Prelate's self-heal). Lets the
## combat UI log it and refresh the bar, mirroring enemy_damaged.
signal enemy_healed(enemy, amount: int, new_hp: int)
signal enemy_died(enemy)
## Fired when a multi-phase boss depletes a phase's HP and transitions to the next
## instead of dying. `line` is the dialogue spoken on entering the new phase (may be
## empty). The UI refills the HP bar, swaps the intent, and floats a speech bubble.
signal enemy_phase_changed(enemy, phase_index: int, line: String)
signal block_gained(target, amount: int)

# -- Passion events --
signal passion_changed(old_value: int, new_value: int)
signal passion_tier_changed(old_tier: int, new_tier: int)

# -- Status effect events --
signal status_applied(target, effect: StatusEffectData, stacks: int)
signal status_removed(target, effect: StatusEffectData)

# -- Navigation events --
signal map_node_selected(node_data)
signal scene_transition_requested(scene_path: String)

# -- Story / VN events --
signal vn_choice_made(choice_data)

# -- Realm events --
signal realm_configured(realm_data)
## Emitted when the player's current realm changes (act transitions, realm switching).
## Title degradation, UI accent colors, and codex tracking listen here.
signal realm_changed(previous_realm_id: StringName, new_realm_id: StringName)
## Emitted when the player switches between staying in or leaving a realm post-boss.
## Reserved for Phase C (realm switching UX implementation).
signal realm_left(realm_id: StringName)

# -- Run lifecycle events --
signal run_started(character: CharacterData)
signal run_ended(victory: bool)
signal act_started(act_number: int)
signal act_ended(act_number: int)

# -- Perk events --
signal perk_selected(perk: PerkData)

# -- Item events --
signal relic_acquired(relic: RelicData)
signal equipment_changed(slot, old_equipment, new_equipment)

# -- Title events --
## Emitted when the player earns a new title (added to earned list).
signal title_earned(title_id: StringName)
## Emitted when the player equips/unequips a title in one of the two slots.
## previous_id is &"" if the slot was empty; new_id is &"" if unequipping.
signal title_equipped(slot: int, previous_id: StringName, new_id: StringName)
## Emitted when a title's effective tier changes (degrade on leave, returning on come-back, reclamation, etc.)
signal title_tier_changed(title_id: StringName, new_tier: int)

## Emitted when the player toggles Excalibur between Sword and Sight modes.
## new_mode is one of RunManager.ExcaliburMode.SWORD / SIGHT.
signal excalibur_mode_changed(new_mode: int)

## Emitted when the player toggles The Thurible (the Reliquary censer relic) between
## swinging Passion toward Blazing and toward Hollow. new_mode is one of
## RunManager.ThuribleMode.BLAZING / HOLLOW. The map UI re-renders the toggle on this.
signal thurible_mode_changed(new_mode: int)

## Emitted when the player makes the Crown decision after defeating an act boss
## while holding Excalibur. took_crown=true → King of Camelot path;
## took_crown=false → refused, alternative paths (advisor, leave, wander).
## Phase 2 will hook governing philosophy modifiers off this signal.
signal crown_decided(took_crown: bool)

## Emitted after the Be the King score is computed on a crown-stakes boss
## victory. tier maps to BeTheKing.Tier (0 Battered → 3 Triumphant). Score is
## the raw 0-1 value before tier quantization; UI displays the narrative
## phrase for the tier, not the score.
signal be_the_king_scored(score: float, tier: int)

## Emitted from the philosophy_choice_scene after Take Crown. strength_tier
## is the locked Act 1 BTK tier (0-3) and stays constant for the rest of the
## run; modifier hooks across reward / shop / combat / map all read it via
## RunManager helpers.
signal philosophy_chosen(philosophy_id: StringName, strength_tier: int)

## Emitted when a crowned player gives up the throne at an Act 2/3 transition.
## fork is one of AbdicationFork.{QUIET, FORCED, FALLEN} resolved from the
## philosophy × realm_standing matrix in the abdication scene.
signal abdicated(realm_id: StringName, fork: int)

## Emitted when the per-realm standing dial moves. Negative deltas are
## betrayals; positive deltas are loyalty acts. Content gating (hostile
## events, map density) listens here rather than polling.
signal realm_standing_changed(realm_id: StringName, old_value: int, new_value: int)

## Emitted after kings_reputation is updated by a post-Act-1 boss BTK roll.
## new_value is the blended 0-1 dial used by king's-roll events at narrative
## beats. NOT used to set modifier magnitude (that's the locked Act 1 tier).
signal kings_reputation_updated(new_value: float)
