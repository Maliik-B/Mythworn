# Mythworn: architecture

This document explains how the game's code is put together, what each main decision bought and what it cost, and why the game is built on Godot. It describes the code as it stands. The [README](../README.md) has the pitch and the design, and this document borrows three of its words: a keeper is the character you play, a realm is a setting with its own map and content, and the pledge is the choice at Camelot's gate that sets the state of the realm for the act.

It starts with the layers and the rules they keep, then follows a run from screen to screen. After that it takes the systems one at a time: content, combat, Passion, randomness, the map, and events and story. It ends with how the game is tested, what is still rough, and why Godot.

## The shape

```
+--------------------------------------+
| scenes/ and scripts/ui/              |
| one script for each screen           |
+--------------------------------------+
    | calls            ^ signals,
    v                  | through Events
+--------------------------------------+
| scripts/core/                        |
| rules and content: CombatEngine,     |
| MapGenerator, the *_pool registries  |
+--------------------------------------+
    | reads and writes
    v
+--------------------------------------+
| scripts/autoloads/                   |
| run state and services: RunManager,  |
| RngManager, Events, six smaller ones |
+--------------------------------------+

tools/ load the lower two layers to
check content and run fights headless
```

**Rules and content** are in `scripts/core/`: the data classes (`CardData`, `EnemyData`, `RelicData`, `TitleData` and the rest), the registries that build every piece of content, the map generator and the combat engine.

**Run state and services** are nine autoloads in `scripts/autoloads/`. An autoload is a Godot singleton: it is loaded once at startup, and any script can reach it. Three of them carry the weight:

- `RunManager` owns the run: deck, relics, titles, held consumables, companion, gold, HP, Passion, the map, the realm's configuration, and the hand-offs between screens.
- `RngManager` owns the run seed and its random streams.
- `Events` is the signal bus. Every signal that crosses a system boundary is declared there, grouped by domain.

The other six are small: `RealmRegistry` (the realms and what each looks like), `ProfileManager` (settings and seen cutscenes, in `user://profile.cfg`), `SceneTransition`, `AudioManager`, `PauseMenu` and `TitleEarnedPopup`.

**Screens** are in `scenes/`, one folder each. Drawing that more than one screen shares is in `scripts/ui/`: the card face, the Passion gauge, the combat stage, and the set pieces that stage a moment such as drawing the sword. Screens also read and write `RunManager` directly, which is how one hands off to the next.

Three rules hold across the layers, and the tools depend on all of them:

1. **The rules run with no screen loaded.** The combat engine reports what happened through signals and never reaches for the interface, so a harness can run a fight headless.
2. **Screens do not call each other.** Every change of screen goes through `SceneTransition`, and what the next screen needs is left for it in `RunManager`.
3. **Every shuffle that decides gameplay draws from a named stream.** Nothing in the game calls `Array.shuffle()`.

The cost of this shape is global state. The engine reads the run straight from `RunManager`, so a test has to set that singleton up before it can build a fight.

## How a run flows

```
splash -> title -> character select
  -> send-off -> pledge   (story scenes)
  -> map -> a node:
       fight -> rewards -> map
       event -> [fight -> event] -> map
       shop  -> map
       rest  -> map
  -> boss -> rewards
  -> the crown   (only with Excalibur)
  -> the end screen
```

A screen that is finishing writes what the next one needs into `RunManager` (`pending_enemies` for a fight, `pending_special_event` for a special event, `pending_vn` for a story scene) and asks `SceneTransition` for the next scene. The next screen reads its field and clears it. Because of this every screen can be loaded on its own, which is how the tools open them. The price is a set of `pending_` fields on one singleton that only convention keeps correct: a screen has to clear what it reads.

The pledge, the second story scene, is where the state of the realm is set. Its choice produces a `RealmConfig`: enemy strength, the count of elites, shop prices, reward rarity, a starting boon, a Passion shift and the player's standing with court and folk. `RunManager` holds it, and the map, the fights, the shops and the events read it for the rest of the act.

The diagram is the build as it runs today. The tree also holds a crossing between realms, built and switched off with `MapGenerator.crossing_enabled`, and a reader will meet its code. A crossing is a map node that moves the run onto a map of another realm's edge, then brings it home to its own map as it was left. `tools/crossing_walk` switches it on for its own run and walks it.

## Content as code

Cards, enemies, relics, events, titles, consumables and companions are built by static functions in the `*_pool.gd` files, not stored as `.tres` resources. That buys three things:

- **One source.** The game, the tests and the harnesses build from the same functions, so what is tested is what ships.
- **Parameters.** A builder can take arguments. An enemy is built at a difficulty multiplier, and the text that describes a pledge reads its numbers from the same `RealmConfig` the game applies.
- **Fresh objects.** Every call returns new instances, and a card entering a deck is a copy, so upgrading it cannot change the card in the pool.

The cost is the editor. Nothing here can be changed in Godot's inspector, so adding a card means writing code.

A realm's content is looked up by a pair, the realm and its configuration. `RealmRoutes` holds that rule, and `EnemyPool` and `EventPool` each keep a table keyed by the pair, so another realm, or another state of the same realm, is a row in each table. Asking for a pair that has no content is a loud error and an empty answer, never another realm's content.

## Combat

`CombatEngine` is a state machine over a round: the player's turn starting, the player's turn, the turn ending, the enemy turn, and the two ways a fight ends. It owns the energy, the turn count, the player's `CombatantStats`, one `EnemyCombatState` for each enemy, and a `PileManager` for the draw pile, hand, discard and exhaust.

Whoever drives the engine has two switches. `instant` skips the pacing timers of the enemy turn, so a harness can run fights as fast as they resolve. `hold()` and `release()` let a staged moment on the screen, such as a boss going down and getting up, pause the fight until it is over.

### How a card resolves

A card is a `CardData` holding an array of `CardEffect` resources, whose classes are in `scripts/core/effects/`. Playing one goes like this:

1. The combat screen calls `CombatEngine.play_card(card, target)`.
2. `can_play_card` refuses unless it is the player's turn, nothing is holding the fight, the card is in the hand and playable, and the energy covers its cost.
3. The engine pays the cost and takes the card out of the hand. An X-cost card spends all the energy that is left.
4. Each effect is applied in order to the player, to the target or to every living enemy, as the card's target type says. An area card applies every one of its effects once for each living enemy, a Passion shift included, so its Passion grows with the size of the fight. A damage or Block effect changes nothing itself. It calls back into the engine (`deal_damage`, `apply_block`), which applies the modifiers in one fixed order and emits the signals for what happened. For damage the order is:
   1. Strength, then Weak, on the attacker.
   2. The flat bonuses a title or a relic adds.
   3. The Passion multiplier.
   4. Vulnerable on the target.
   5. What the target takes off, then its Block.
5. The engine emits `Events.card_played` and files the card: exhausted, discarded, returned to the hand, or nowhere for a power or a companion's card.
6. `check_battle_end` looks for a win or a loss.

The combat screen never works out a result. It calls step 1, then redraws from the signals and the engine's state.

An `EnemyMove` holds the same kind of effect array, so a new effect class works for both sides as soon as it is written.

### Enemies and bosses

An enemy picks its move by weight from the moves that are legal this turn. A move is legal when the enemy's HP sits inside the move's band and the move is off its cooldown. The cooldown puts a heavy hit on a rhythm, and the band keeps a move for low health. The move the enemy settles on is shown to the player as its intent.

A boss can carry several life bars. `EnemyData.phase_hps` gives each phase its own bar and `phase_movesets` its own moves. When a bar empties, the enemy refills to the next one, drops its Block and statuses, speaks its line, and applies that phase's entry effects. Only the last bar's end is a death. Two enemies are built this way, the Beast at the Stone and Sir Caedmon, with no code of their own in the engine.

## Passion

`PassionState` is a signed value with a limit at each end. The positive side is the keeper's first self and the negative side the second, and the tier boundaries are set for each character, which gives the five tiers the README names, from Hollow at the bottom to Blazing at the top. The state belongs to the run, not the fight, which is how Passion carries from one fight to the next.

Two rules read the tier, and each is one function. The damage rule is the static function `CombatEngine.zone_multiplier`. Combat calls it when an attack lands and the card face calls it when it prints the card's number, so the two cannot disagree about the multiplier. The reward rule is `CardPool._get_tier_split`, which turns the tier into how many of the offered cards come from each pool.

## Randomness

`RngManager` derives five generators from the run seed: deck, enemy, loot, event and map. A draw on one never moves another, so reshuffling a deck cannot change what the map, the loot or an enemy rolls. Inside one stream, order still matters. The loot stream rolls rewards and shop stock, and also an event's wager and the shopkeeper's greeting, so those share one sequence. The switched-off crossing derives two more streams of its own, so that seating it moves nothing else.

Godot's `Array.shuffle()` draws from the engine's global generator, which sits outside these streams. The game has one Fisher-Yates of its own, which is handed the stream to draw from, and every shuffle that decides gameplay goes through it.

This is what lets `tools/realm_route_proof` compare two commits on the same seeds. Each stream can also report and restore its state, though a run is not saved between sessions in this build.

## The map

`MapGenerator.generate` builds one act from a generator, the realm, the act and the two fields of the configuration that shape a map, so the same inputs always give the same map. Paths are walked upward from the bottom row and merged into one boss node at the top, and edges that cross are straightened so the drawn map is never ambiguous about where a line leads. Node types are assigned by weights that change with height, then corrected so that no route carries more than a cap of elites and a shop can always be reached. A shop is not put on every route, since routing to one is the player's decision.

After that the realm places its own fixed nodes. Camelot's are the Sword in the Stone at the centre, a questline's giver and its payoff, the huntsman who sells a companion, and a place that keeps records. Last, the pledge's changes are applied, and each changed node is recorded so the map can show the player what their choice did. The court's pledge adds elites at this step, after the cap, so a pledged route can carry more than the cap allows.

## Events and story

An event is an `EventData` with a list of choices, and a choice is a set of plain fields: HP, gold and Passion changes, a card or relic granted, a title awarded, a fight started, a quest armed, a standing with court or folk required, a wager rolled. Most events are written by filling those fields in.

Events that need more are special events, built by id in the event screen's own script. A choice can chain to another beat, or start a fight and return to the same page afterwards with its text intact. A quest armed in one event marks a payoff node elsewhere on the map, and the map shows it on the next visit.

Story scenes are `VNData` (VN for visual novel): beats of narration and speech, then choices. A choice can carry a `RealmConfig`, which is how the pledge becomes the state of the realm.

## Testing

There is no CI yet. The checks are scenes in `tools/` that run headless, and they are run by hand before each commit. They are scenes and not bare scripts because a tool that touches an autoload has to run inside the project. The README has the commands.

| Tool | What it does | Where it stands |
|---|---|---|
| `roster_test` | Assertions against the real enemies, cards, relics, titles and maps: when a move is legal, the bosses' phases, Passion's rules, each relic and title, what the map guarantees across seeds. | 736 checks, all passing. |
| `content_linter` | 20 rules over the registries and the references between them. Each rule is a pure function, and a self-test hands it a copy of the data with one bug planted in it. | Clean, with two known findings listed in the tool: two cards that nothing grants yet. |
| `combat_harness` | Single fights on the real engine with a planning player. | Two known 3 HP mismatches in its model ([below](#the-planner-and-its-forward-model)). |
| `run_harness` | Whole runs: a fixed act of 16 nodes, real encounters, the real engine, real card drafts. Paired sweeps measure what a companion, a relic or a title adds on the same seeds. | Its fights are the game's. Its events are not ([What is rough](#what-is-rough)). |
| `gamebreak_hunt` | A search for degenerate builds. It hill-climbs from random starts over cards, relics, titles, held items and companions, and scores each build on its damage to a dummy with 1,000,000 HP. | It flags a turn that outdamages the boss's first bar, plays more than 25 cards or ends with more than 12 energy. |
| `realm_route_proof` | Same-seed output to diff between two commits: each map, and the encounters and events along a route through it, for 40 seeds under three realm configurations. It plays no fight and takes no reward, so it does not exercise the deck or loot streams. | It reads the two pledges from the realm-entry scene, so a change to a pledge's numbers moves its output. |
| `crossing_walk` | A walk through the real scenes from one realm's map to another's and back. | The crossing it tests is switched off in the game. |

Two more are for looking, not asserting: `card_manifest` shows every card face on one screen with a Passion toggle, and `map_path_analysis` prints how much the routes up a map differ. `bake_sheet.py` and `bake_prop.py` are the art bakes, which put a sprite sheet or a rendered prop through one value ramp, outline and rim light so packs by different artists look like one set.

### The planner and its forward model

The harness's player, `HarnessCombat`, plans a whole turn at a time. It plays each candidate plan out through the enemy turn that follows and prices the rest of the fight with an estimate. A player told to commit to a self takes the plan that moves Passion furthest toward it, unless another plan wins the fight or that one would not survive. Otherwise, and between plans that tie, it takes the plan it expects to cost the least HP. It weighs up to 800 plans a decision.

The engine emits global signals and reads global run state, so it is not something to copy and step a few hundred times a decision. The planner searches on a light model of the fight that it keeps itself. That is a second implementation of the rules, which is the thing the harness exists to avoid, so `--verify` holds the model to the engine. Before each card it predicts the state after it, and before each enemy turn it predicts the player's HP and each enemy's state after that turn. Each prediction is compared with what the engine then did. It skips what it cannot predict: an enemy turn after a bar has just broken, and the player's HP when a relic heals at the start of the turn.

On the current build that is 25,633 cards and 7,061 enemy turns across 11 loadouts and 5 fights, with two mismatches. Two cards, Cascade and Riptide, each once left the player 3 HP above the prediction. The cause has not been chased down, and the tool exits 1 while they stand.

## What is rough

Four of these are structural.

- **Screens build their layout in code.** Each `.tscn` is a root node and a script, and the script constructs the interface when the scene loads, where Godot's own way is to lay it out in the scene file. The price is long screen scripts and no layout work in the editor. `scenes/combat/combat_scene.gd` is the largest at about 3,500 lines. Shared drawing has moved out into `scripts/ui/`, but the layouts have not moved into scenes.
- **Some content lives in a screen.** The special events, and the code that resolves a choice, are in `scenes/event/event_scene.gd`. The linter and the run harness create an instance of that screen's script to reach them. Both belong in `scripts/core/` with the rest.
- **The run harness resolves events itself.** It applies an event's choice in its own code, a second implementation beside the event screen's, and the two have drifted. A wager draws from a different stream than it does in the game, shop stock is drawn in a different order, a story beat pinned to a visit is skipped, and arming a quest is not modelled.
- **The engine knows some content by name.** A relic or title whose effect does not fit the generic triggers is handled inside `CombatEngine`, as are Camelot's own scoring and one event's boon, so each adds a field and a branch there.

Two are gaps in behaviour.

- **A card's number leaves out flat bonuses.** The card face prints Strength, Weak, the Passion multiplier and Vulnerable, but not what a title or a relic adds to each hit, so a hit can land higher than the card says.
- **The court's elites are added after the cap** on elites along a route, as The map describes.

The rest are small.

- `Events` declares more than the game uses. About half of its signals have no listener, and a few are never emitted.
- `scripts/core/reveal_anim.gd` is an animation helper filed with the rules. It belongs in `scripts/ui/`.
- `EquipmentData` and `PerkData` are stubs from an earlier design. Titles replaced equipment.
- `tools/combat_sim.py` is an older Python model of combat. The in-engine harness replaced it, and it has not kept up.

## Why Godot

- Scenes, scripts and resources are text, so every change can be read, diffed and reviewed.
- It is a 2D engine first, with a full interface toolkit, and it exports a native desktop build.
- The engine is MIT licensed, with no royalty and no per-install fee.
- The genre is proven on it: Slay the Spire 2 is built in Godot.
- The project uses the compatibility renderer, which keeps a browser build within reach.

The alternatives weighed were a web stack in TypeScript, Unity and Unreal. The web stack would have needed a desktop wrapper to ship on Steam. Unity is heavier than a 2D card game needs, and its 2023 change of terms made it hard to plan around. Unreal is a 3D engine, and its Blueprint and widget assets are binary, so they cannot be read or diffed as text.
