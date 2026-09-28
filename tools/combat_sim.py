"""
Fable combat balance simulator (Python) — fast analytical sweep.

A re-implementation of Fable's combat rules for quick number sweeps, kept in rough
agreement with the AUTHORITATIVE in-engine GDScript harness (tools/combat_harness.tscn).
It is NOT the real engine: it models the rules (block reset per turn, Strength / Weak /
Vulnerable / Poison / Intangible / Frozen / Enraged, multi-hit vs block, X-cost torrents,
the graduated Passion zone modifier, separate-bar boss phases with a guaranteed transition
cost, and the weighted enemy AI with HP-gating + cooldowns) and drives the player with a
greedy heuristic. So it sets bands and shows the Passion swing; final tuning is the GDScript
harness + playtest.

Resynced 2026-09-24 to the balance pass (docs/BALANCE_SNAPSHOTS.md):
  - signed Passion axis [-100, +100] (was wrongly clamped to [0, 100], so the Physical
    pole could never be modelled),
  - graduated zone (extremes +-25%, mid-leans +-12%, Steady flat),
  - the full pole RE-IDENTITY (Water = glass swing, NO block; Physical = the block/steady
    floor), X-cost Maelstrom, Intangible-as-defense,
  - current enemy roster incl. the 3 new regulars + Iron Verdict, and Caedmon as two
    separate 78-HP bars with the anti-burst transition (lash + Enraged + Strength).

Run: python tools/combat_sim.py
"""

import random
import statistics

# ----------------------------------------------------------------------------
# ASSUMPTIONS (the levers that most affect the output — challenge these first)
# ----------------------------------------------------------------------------
PLAYER_MAX_HP = 80
ENERGY = 3
HAND_SIZE = 5
TRIALS = 4000
CHIP_TOLERANCE = 5      # HP of incoming the player will "eat" before bothering to block
SAFETY_FRAC = 0.35      # below this fraction of max HP, the player blocks hard
SPIKE = 12              # a single telegraphed hit >= this is worth answering

# Graduated Passion zone (mirrors CombatEngine.zone_multiplier): extremes +-25%,
# mid-leans (Inspired / Wavering) +-12%, the dispassionate centre (Steady) flat.
ZONE_EXTREME_BONUS = 1.25
ZONE_EXTREME_PENALTY = 0.75
ZONE_LEAN_BONUS = 1.12
ZONE_LEAN_PENALTY = 0.88

# Signed Passion axis (matches the game): -100..+100, start 0 (Steady, the centre).
# Thresholds [blazing_min, inspired_min, steady_min, wavering_min]; below = hollow.
PASSION_THRESHOLDS = [50, 18, -18, -50]
PASSION_MIN, PASSION_MAX = -60, 60   # capped at ±60 so "at your pole" is a tight band mechanics can bite
PASSION_START = 0
VOLATILITY = 1.0        # Emo Hybrid passion_volatility
ZEAL_SCALE = 0.12       # each Prophet Zealotry stack multiplies its center-pull by this

NEUTRAL, PRIMARY, SECONDARY = "neutral", "primary", "secondary"  # primary=Water, secondary=Physical


def tier(v):
    if v >= PASSION_THRESHOLDS[0]: return "Blazing"
    if v >= PASSION_THRESHOLDS[1]: return "Inspired"
    if v >= PASSION_THRESHOLDS[2]: return "Steady"
    if v >= PASSION_THRESHOLDS[3]: return "Wavering"
    return "Hollow"


def zone_mult(personality, passion):
    """Card damage multiplier at the current tier (mirrors CombatEngine.zone_multiplier)."""
    if personality == NEUTRAL:
        return 1.0
    t = tier(passion)
    if t == "Steady":
        return 1.0
    if t == "Blazing":
        primary_favored, lean = True, False
    elif t == "Inspired":
        primary_favored, lean = True, True
    elif t == "Hollow":
        primary_favored, lean = False, False
    else:  # Wavering
        primary_favored, lean = False, True
    on_type = (personality == PRIMARY) == primary_favored
    if on_type:
        return ZONE_LEAN_BONUS if lean else ZONE_EXTREME_BONUS
    return ZONE_LEAN_PENALTY if lean else ZONE_EXTREME_PENALTY


def change_passion(p, amount):
    return max(PASSION_MIN, min(PASSION_MAX, p + int(amount * VOLATILITY)))


def pull_to_center(p, strength):
    """Multiplicative pull toward 0 (the False Prophet's tool): keep (1-strength)."""
    eff = min(1.0, strength * VOLATILITY)
    return int(round(p * (1.0 - eff)))


# ----------------------------------------------------------------------------
# COMBATANTS
# ----------------------------------------------------------------------------
class Combatant:
    def __init__(self, hp, max_hp=None):
        self.hp = hp
        self.max_hp = max_hp if max_hp is not None else hp
        self.block = 0
        self.strength = 0
        self.weak = 0
        self.vulnerable = 0
        self.poison = 0
        self.intangible = 0
        self.frozen = 0
        self.enraged = 0
        self.zealotry = 0

    def alive(self):
        return self.hp > 0

    def tick_poison(self):
        if self.poison > 0:
            dmg = 1 if self.intangible > 0 else self.poison
            self.hp -= dmg
            self.poison -= 1


def deal_damage(target, base, source=None, zone=1.0):
    """Mirrors CombatEngine.deal_damage: Strength -> Weak -> zone -> Vulnerable ->
    Intangible clamp -> block, then Enraged retaliation on the attacker. Returns HP lost."""
    amt = base
    if source is not None:
        amt += source.strength
        if source.weak > 0:
            amt = int(amt * 0.75)
    amt = int(amt * zone)
    if target.vulnerable > 0:
        amt = int(amt * 1.5)
    amt = max(0, amt)
    if amt > 0 and target.intangible > 0:
        amt = 1
    blocked = min(target.block, amt)
    target.block -= blocked
    actual = amt - blocked
    target.hp -= actual
    if actual > 0 and source is not None and source is not target and target.enraged > 0:
        source.hp -= target.enraged   # raw lash, bypasses block, fires per hit
    return actual


# ----------------------------------------------------------------------------
# ENEMY DEFINITIONS  (the numbers we are balancing — mirror scripts/core/enemy_pool.gd)
# effect tuples: ("dmg", n) | ("dmg_x", n, hits) | ("block", n) | ("str", n) |
#   ("weak", n) | ("vuln", n) | ("poison", n) | ("passion", n) | ("passion_center", frac) |
#   ("self_enraged", n) | ("ally_str", n)
# move: M(name, weight, [effects], cd, lo, hi)   (lo/hi = HP-fraction gate)
# ----------------------------------------------------------------------------
def M(name, weight, effects, cd=0, lo=0.0, hi=1.0):
    return dict(name=name, weight=weight, cd=cd, lo=lo, hi=hi, effects=effects)


ENEMIES = {
    # --- Regulars ---
    "Corrupted Knight": dict(hp=46, moves=[
        M("Vanguard Strike", 2.0, [("dmg", 7)]),
        M("Oathbound Guard", 1.2, [("block", 6), ("str", 1)]),
        M("Rally", 0.7, [("str", 2)], cd=2),
    ]),
    "Court Conspirator": dict(hp=26, moves=[
        M("Jab", 1.3, [("dmg", 4)]),
        M("Undermine", 1.2, [("weak", 1)]),
        M("Slander", 1.0, [("vuln", 1)]),
        M("Whisper", 2.2, [("passion", -4), ("weak", 1)], cd=3),
        M("Rally the Court", 1.1, [("ally_str", 1)], cd=2),
    ]),
    "Siege Golem": dict(hp=72, moves=[
        M("Grind", 2.0, [("dmg", 8)]),
        M("Crushing Step", 1.0, [("dmg", 12)]),
        M("Siege Slam", 1.6, [("dmg", 18)], cd=2),
    ]),
    "Realm Shade": dict(hp=34, moves=[
        M("Fade Strike", 1.5, [("dmg", 6)]),
        M("Shroud", 1.4, [("block", 7)]),
        M("Hex", 1.0, [("weak", 1)]),
        M("Corrupt", 1.1, [("weak", 1)], cd=2),   # approximates the deck-pollution tempo hit
    ]),
    "Man-at-Arms": dict(hp=44, moves=[
        M("Halberd Swing", 2.0, [("dmg", 9)]),
        M("Raise Shield", 1.0, [("block", 8)]),
        M("Overhead Chop", 1.4, [("dmg", 14)], cd=2),
    ]),
    "Corrupted Squire": dict(hp=24, moves=[
        M("Harry", 1.6, [("dmg", 5)]),
        M("Expose Weakness", 1.4, [("vuln", 1)], cd=2),
        M("Reckless Charge", 1.1, [("dmg", 11)], cd=2),
    ]),
    "Prophet's Acolyte": dict(hp=34, moves=[
        M("Censure", 1.5, [("dmg", 6)]),
        M("Sap Will", 1.3, [("weak", 2)], cd=2),
        M("Wane", 1.2, [("block", 6), ("dmg", 4)]),
    ]),
    # --- Elites ---
    "Champion of the Usurper": dict(hp=100, moves=[
        M("Usurper's Blade", 2.0, [("dmg", 11)], lo=0.66),
        M("Challenge", 1.0, [("str", 2)], cd=2, lo=0.66),
        M("Regroup", 1.5, [("block", 12), ("str", 1)], lo=0.33, hi=0.66),
        M("Measured Strike", 1.5, [("dmg", 9)], lo=0.33, hi=0.66),
        M("Last Stand", 2.0, [("dmg", 16)], hi=0.33),
        M("Reckless Fury", 1.5, [("dmg", 8), ("str", 2)], hi=0.33),
    ]),
    "The False Prophet": dict(hp=110, moves=[
        # The Passion crucible: an ESCALATING multiplicative pull. Both preaching moves build
        # Zealotry, which multiplies the pull (see apply_enemy_effects) — race to silence it.
        M("False Sermon", 2.6, [("passion_center", 0.26), ("weak", 1), ("self_zealotry", 1)], cd=2),
        M("Doubt", 2.4, [("passion_center", 0.18), ("self_zealotry", 1)]),
        M("Condemn", 1.1, [("dmg", 10), ("vuln", 1)]),
        M("Zealot's Ward", 1.1, [("block", 14)]),
    ]),
    "The Iron Verdict": dict(hp=92, starting=[("enraged", 2)], moves=[
        M("Backhand", 1.6, [("dmg", 9)]),
        M("Iron Bulwark", 1.2, [("block", 14)]),
        M("Retribution", 1.0, [("self_enraged", 1)], cd=2),
        M("Cleaving Sentence", 1.3, [("dmg", 17)], cd=2),
    ]),
    # --- Boss (two separate 78-HP bars; transition applies the anti-burst cost) ---
    "Sir Caedmon": dict(
        phase_hps=[78, 78],
        # phase-enter effects, index by phase (phase 1 entry = index 1): lash + Str + Enraged
        phase_enter=dict(dmg=[0, 16], str=[0, 2], enraged=[0, 1]),
        phases=[
            [  # phase 1: disciplined
                M("Vanguard Strike", 2.0, [("dmg", 10)]),
                M("Oathbound Guard", 1.3, [("block", 12), ("str", 1)]),
                M("Rallying Blow", 1.4, [("dmg", 20)], cd=3),
            ],
            [  # phase 2: compelled, guard dropped
                M("Compelled Onslaught", 2.0, [("dmg_x", 7, 3)]),
                M("Hollowing Gaze", 1.6, [("passion", -6), ("weak", 2)], cd=2),
                M("Puppet's Fervor", 1.2, [("str", 3)], cd=1),
            ],
        ],
    ),
    # --- Training wall (pole-ramp probe: outlasts the ~9-turn ramp) ---
    "Training Wall": dict(hp=300, moves=[M("Chip", 1.0, [("dmg", 4)])]),
}


class EnemyState:
    def __init__(self, name, rng):
        d = ENEMIES[name]
        self.name = name
        self.rng = rng
        self.phases = d.get("phases")
        self.phase_hps = d.get("phase_hps")
        self.phase_index = 0
        if self.phases:
            self.moves = self.phases[0]
            hp = self.phase_hps[0]
        else:
            self.moves = d["moves"]
            hp = d["hp"]
        self.c = Combatant(hp)
        for (st, val) in d.get("starting", []):
            setattr(self.c, st, getattr(self.c, st) + val)
        self.turn = 0
        self.last_used = {}
        self.intent = None
        self.select_intent()

    def has_next_phase(self):
        return self.phases is not None and self.phase_index < len(self.phases) - 1

    def advance_phase(self, player):
        """Deplete-to-transition: refill to the next bar (overkill discarded), swap moves,
        and apply the guaranteed transition cost (lash on the player + Str + Enraged)."""
        self.phase_index += 1
        bar = self.phase_hps[self.phase_index]
        self.c.hp = bar
        self.c.max_hp = bar
        self.c.block = 0
        self.moves = self.phases[self.phase_index]
        pe = ENEMIES[self.name].get("phase_enter", {})
        self.c.strength += pe.get("str", [0] * (self.phase_index + 1))[self.phase_index]
        self.c.enraged += pe.get("enraged", [0] * (self.phase_index + 1))[self.phase_index]
        lash = pe.get("dmg", [0] * (self.phase_index + 1))[self.phase_index]
        if lash > 0:
            player.c.hp -= lash   # unavoidable, bypasses block
        self.last_used = {}
        self.select_intent()

    def _eligible(self, mv, for_turn):
        frac = self.c.hp / self.c.max_hp if self.c.max_hp else 1.0
        if frac < mv["lo"] - 1e-4 or frac > mv["hi"] + 1e-4:
            return False
        if mv["cd"] > 0 and mv["name"] in self.last_used:
            if for_turn - self.last_used[mv["name"]] <= mv["cd"]:
                return False
        return True

    def _roll(self, for_turn):
        elig = [m for m in self.moves if self._eligible(m, for_turn)]
        if not elig:
            elig = self.moves
        total = sum(m["weight"] for m in elig)
        r = self.rng.random() * total
        c = 0.0
        for m in elig:
            c += m["weight"]
            if r <= c:
                return m
        return elig[-1]

    def select_intent(self):
        self.turn += 1
        self.intent = self._roll(self.turn)
        self.last_used[self.intent["name"]] = self.turn

    def predicted_damage(self, player_vuln):
        dmg = 0
        for e in self.intent["effects"]:
            if e[0] == "dmg":
                dmg += e[1] + self.c.strength
            elif e[0] == "dmg_x":
                dmg += (e[1] + self.c.strength) * e[2]
        if self.c.weak > 0:
            dmg = int(dmg * 0.75)
        if player_vuln > 0:
            dmg = int(dmg * 1.5)
        return dmg


# ----------------------------------------------------------------------------
# PLAYER CARDS + DECKS  (mirror card_pool.gd / character_pool.gd)
# effect tuples add: ("dmg_x_energy", n) X-cost | ("intangible_self", n) |
#   ("stun", n) enemy | ("str_target", n) enemy Strength soak
# ----------------------------------------------------------------------------
def C(name, cost, kind, effects, pers=NEUTRAL, exhaust=False, x_cost=False):
    return dict(name=name, cost=cost, kind=kind, pers=pers, effects=effects,
                exhaust=exhaust, x_cost=x_cost)


# Starter (CharacterPool.emo_starting_deck) — 10 cards: leaned neutral backbone (Strike -1,
# Defend +1) + 3 self-scaling cards per pole (Water: multi-hit x control; Physical: Strength
# ramp via Tempered Strike). See GAME_DESIGN "Starting deck — iteration log".
STRIKE   = C("Strike", 1, "atk", [("dmg", 6), ("self_passion", -1)])
DEFEND   = C("Defend", 1, "blk", [("block", 5), ("self_passion", 1)])
OUTPOUR  = C("Outpouring", 1, "atk", [("dmg", 7), ("self_passion", 3)], PRIMARY)
RIPTIDE  = C("Riptide", 1, "atk", [("dmg_x", 4, 2), ("self_passion", 3)], PRIMARY)
EBB      = C("Ebb", 1, "atk", [("dmg", 5), ("weak", 1), ("self_passion", 3)], PRIMARY)
MEASURED = C("Measured Blow", 1, "atk", [("dmg", 10), ("self_passion", -3)], SECONDARY)
TEMPERED = C("Tempered Strike", 1, "atk", [("dmg", 5), ("self_str", 1), ("self_passion", -3)], SECONDARY)
SUNDER   = C("Sunder", 1, "atk", [("dmg", 5), ("vuln", 1), ("self_passion", -3)], SECONDARY)
GUARD    = C("Guard", 1, "blk", [("block", 8), ("self_passion", -3)], SECONDARY)

# Water (Primary) pool — glass swing, NO block. Mirrors build_emo_primary_pool.
TIDAL     = C("Tidal Strike", 1, "atk", [("dmg", 9), ("self_passion", 4)], PRIMARY)
CHILLBRAND= C("Chillbrand", 1, "atk", [("dmg", 6), ("weak", 2), ("self_passion", 4)], PRIMARY)
UNDERTOW  = C("Undertow", 1, "skl", [("weak", 2), ("str_target", -2), ("self_passion", 4)], PRIMARY)
DEEPFREEZE= C("Deep Freeze", 2, "skl", [("stun", 1), ("vuln", 1), ("self_passion", 6)], PRIMARY)
MAELSTROM = C("Maelstrom", 0, "atk", [("dmg_x_energy", 5), ("self_passion", 6)], PRIMARY, x_cost=True)
# (Soulstep / Creeping Tide exist in the pool but aren't in the harness mid-deck.)

# Physical (Secondary) pool — the block/steady floor. Mirrors build_emo_secondary_pool.
POWERSLSH = C("Power Slash", 1, "atk", [("dmg", 7), ("block", 3), ("self_passion", -3)], SECONDARY)
RAMPAGE   = C("Rampage", 2, "atk", [("dmg", 14), ("self_passion", -4)], SECONDARY)
BRACE     = C("Brace", 1, "blk", [("block", 9), ("self_passion", -3)], SECONDARY)
IRONCURT  = C("Iron Curtain", 2, "blk", [("block", 16), ("self_passion", -4)], SECONDARY)
DEVASTATE = C("Devastating Blow", 3, "atk", [("dmg", 28), ("self_passion", -5)], SECONDARY)

EXCALIBUR = C("Excalibur", 2, "atk", [("dmg", 14)])   # Sword-mode injected card


FRESH_DECK = [STRIKE] * 2 + [DEFEND] * 2 + [OUTPOUR, RIPTIDE, EBB, MEASURED, TEMPERED, SUNDER, GUARD]


def mid_deck():
    # Mirrors combat_harness._mid_deck: starter + a Water-leaning spread + 2 Physical.
    return FRESH_DECK[:] + [TIDAL, CHILLBRAND, MAELSTROM, UNDERTOW, DEEPFREEZE,
                            POWERSLSH, RAMPAGE]


def physical_deck():
    # Mirrors combat_harness._physical_deck: neutral core (minus Water starters) + Physical.
    d = [c for c in FRESH_DECK if c["pers"] != PRIMARY]
    return d + [POWERSLSH, RAMPAGE, DEVASTATE, BRACE, IRONCURT]


def boss_deck():
    # Mirrors combat_harness._boss_deck: mid deck with the first 2 of
    # [Maelstrom, Deep Freeze, Chillbrand, Tidal] upgraded. In deck order that's
    # Tidal (9->12) then Chillbrand (6->9); +1 passion each.
    d = []
    up = 0
    for c in mid_deck():
        if up < 2 and c["name"] in ("Tidal Strike", "Chillbrand"):
            c = _upgrade(c)
            up += 1
        d.append(c)
    return d


def _upgrade(card):
    up = dict(card)
    up["effects"] = []
    for e in card["effects"]:
        if e[0] in ("dmg", "block"):
            up["effects"].append((e[0], e[1] + 3))
        elif e[0] == "self_passion":
            up["effects"].append((e[0], e[1] + (1 if e[1] > 0 else -1)))
        else:
            up["effects"].append(e)
    up["name"] = card["name"] + "+"
    return up


class Player:
    def __init__(self, deck, rng, passion=PASSION_START, commit=False, commit_target=0,
                 start_str=0, turn_block=0):
        self.c = Combatant(PLAYER_MAX_HP)
        self.c.strength = start_str
        self.rng = rng
        self.passion = passion
        self.commit = commit
        self.commit_target = commit_target   # signed pole floor/ceiling
        self.turn_block = turn_block          # e.g. Guardian's Sigil +5/turn
        self.draw = deck[:]
        rng.shuffle(self.draw)
        self.hand = []
        self.discard = []
        self.exhausted = []

    def _draw_cards(self, n):
        for _ in range(n):
            if not self.draw:
                self.draw = self.discard[:]
                self.discard = []
                self.rng.shuffle(self.draw)
            if self.draw:
                self.hand.append(self.draw.pop())

    def start_turn(self):
        self.discard += self.hand
        self.hand = []
        self.c.block = 0
        self.c.tick_poison()
        if self.turn_block:
            self.c.block += self.turn_block
        self._draw_cards(HAND_SIZE)

    def end_turn(self):
        self.c.weak = max(0, self.c.weak - 1)
        self.c.vulnerable = max(0, self.c.vulnerable - 1)
        self.c.intangible = max(0, self.c.intangible - 1)

    # -- estimates for the policy --
    def _card_damage(self, card, energy):
        dmg = 0
        for e in card["effects"]:
            if e[0] == "dmg":
                per = e[1] + self.c.strength
                if self.c.weak > 0:
                    per = int(per * 0.75)
                dmg += int(per * zone_mult(card["pers"], self.passion))
            elif e[0] == "dmg_x":
                per = e[1] + self.c.strength
                if self.c.weak > 0:
                    per = int(per * 0.75)
                dmg += int(per * zone_mult(card["pers"], self.passion)) * e[2]
            elif e[0] == "dmg_x_energy":
                per = e[1] + self.c.strength
                if self.c.weak > 0:
                    per = int(per * 0.75)
                dmg += int(per * zone_mult(card["pers"], self.passion)) * energy
        return dmg

    def _passion_gain(self, card):
        return sum(e[1] for e in card["effects"] if e[0] == "self_passion")

    def _has(self, card, key):
        return any(e[0] == key for e in card["effects"])

    def take_turn(self, enemies):
        energy = ENERGY
        guard = 0
        while energy > 0 and guard < 20:
            guard += 1
            card = self._choose(enemies, energy)
            if card is None:
                return
            energy = self._play(card, enemies, energy)

    def _choose(self, enemies, energy):
        living = [e for e in enemies if e.c.alive()]
        if not living:
            return None
        playable = [c for c in self.hand
                    if (energy >= c["cost"]) and not (c["x_cost"] and energy <= 0)]
        if not playable:
            return None
        incoming = sum(e.predicted_damage(self.c.vulnerable) for e in living)
        biggest = max((e.predicted_damage(self.c.vulnerable) for e in living), default=0)
        unblocked = max(0, incoming - self.c.block)

        can_lethal = False
        if len(living) == 1:
            burst = sum(self._card_damage(c, energy) for c in playable if c["kind"] == "atk")
            can_lethal = burst >= living[0].c.hp

        # 1) Survive: block a spike / low-HP hit. Glass Water falls back to Intangible
        #    then Freeze (it has no block).
        threatened = biggest >= SPIKE or (self.c.hp - unblocked) < SAFETY_FRAC * PLAYER_MAX_HP
        if not can_lethal and threatened and self.c.block < incoming - CHIP_TOLERANCE:
            blk = self._cheapest([c for c in playable if self._has(c, "block")])
            if blk:
                return blk
            if biggest >= SPIKE:
                intang = self._cheapest([c for c in playable if self._has(c, "intangible_self")])
                if intang:
                    return intang
                frz = self._cheapest([c for c in playable if self._has(c, "stun")])
                if frz:
                    return frz
        # 2) Hold the pole (signed): climb toward a + target, sink toward a - target.
        if self.commit and not can_lethal:
            if self.commit_target >= 0 and self.passion < self.commit_target:
                up = [c for c in playable if self._passion_gain(c) > 0]
                if up:
                    return max(up, key=self._passion_gain)
            elif self.commit_target < 0 and self.passion > self.commit_target:
                dn = [c for c in playable if self._passion_gain(c) < 0]
                if dn:
                    return min(dn, key=self._passion_gain)
        # 3) Vulnerable setup on a healthy lowest target.
        target = self._lowest(enemies)
        if target and target.c.vulnerable == 0 and target.c.hp > 14:
            vuln = self._cheapest([c for c in playable if self._has(c, "vuln")])
            if vuln:
                return vuln
        # 4) Biggest effective damage.
        atks = [c for c in playable if c["kind"] == "atk" and self._card_damage(c, energy) > 0]
        if atks:
            return max(atks, key=lambda c: self._card_damage(c, energy))
        # 5) Leftover: block if a hit is still coming.
        if self.c.block < incoming:
            blk2 = self._cheapest([c for c in playable if self._has(c, "block")])
            if blk2:
                return blk2
        return None

    def _play(self, card, enemies, energy):
        self.hand.remove(card)
        (self.exhausted if card["exhaust"] else self.discard).append(card)
        mult = zone_mult(card["pers"], self.passion)
        x = energy if card["x_cost"] else 0
        spent = energy if card["x_cost"] else card["cost"]
        for e in card["effects"]:
            k = e[0]
            if k == "dmg":
                self._hit(enemies, e[1], mult)
            elif k == "dmg_x":
                for _ in range(e[2]):
                    self._hit(enemies, e[1], mult)
            elif k == "dmg_x_energy":
                for _ in range(x):
                    self._hit(enemies, e[1], mult)
            elif k == "block":
                self.c.block += e[1]
            elif k == "vuln":
                t = self._lowest(enemies)
                if t: t.c.vulnerable += e[1]
            elif k == "weak":
                t = self._lowest(enemies)
                if t: t.c.weak += e[1]
            elif k == "str_target":
                t = self._lowest(enemies)
                if t: t.c.strength += e[1]
            elif k == "poison":
                t = self._lowest(enemies)
                if t: t.c.poison += e[1]
            elif k == "stun":
                t = self._lowest(enemies)
                if t: t.c.frozen = max(t.c.frozen, e[1])
            elif k == "intangible_self":
                self.c.intangible += e[1]
            elif k == "self_str":
                self.c.strength += e[1]
            elif k == "self_passion":
                self.passion = change_passion(self.passion, e[1])
        return energy - spent

    def _hit(self, enemies, base, mult):
        target = self._lowest(enemies)
        if not target:
            return
        deal_damage(target.c, base, source=self.c, zone=mult)
        if target.c.hp <= 0 and target.has_next_phase():
            target.advance_phase(self)

    def _cheapest(self, cards):
        return min(cards, key=lambda c: c["cost"]) if cards else None

    def _lowest(self, enemies):
        living = [e for e in enemies if e.c.alive()]
        return min(living, key=lambda e: e.c.hp) if living else None

    @property
    def hp(self):
        return self.c.hp


# ----------------------------------------------------------------------------
# COMBAT LOOP
# ----------------------------------------------------------------------------
def apply_enemy_effects(enemy, player, enemies):
    for e in enemy.intent["effects"]:
        k = e[0]
        if k == "dmg":
            deal_damage(player.c, e[1], source=enemy.c)
        elif k == "dmg_x":
            for _ in range(e[2]):
                deal_damage(player.c, e[1], source=enemy.c)
        elif k == "block":
            enemy.c.block += e[1]
        elif k == "str":
            enemy.c.strength += e[1]
        elif k == "self_enraged":
            enemy.c.enraged += e[1]
        elif k == "ally_str":
            for a in enemies:
                if a.c.alive():
                    a.c.strength += e[1]
        elif k == "weak":
            player.c.weak += e[1]
        elif k == "vuln":
            player.c.vulnerable += e[1]
        elif k == "poison":
            player.c.poison += e[1]
        elif k == "self_zealotry":
            enemy.c.zealotry += e[1]
        elif k == "passion":
            player.passion = change_passion(player.passion, e[1])
        elif k == "passion_center":
            s = min(0.85, e[1] * (1.0 + enemy.c.zealotry * ZEAL_SCALE))
            player.passion = pull_to_center(player.passion, s)


def simulate(deck, enemy_names, seed, start_passion=PASSION_START, max_turns=60,
             commit=False, commit_target=0, start_str=0, turn_block=0):
    rng = random.Random(seed)
    player = Player(deck, rng, start_passion, commit, commit_target, start_str, turn_block)
    enemies = [EnemyState(n, rng) for n in enemy_names]
    ttb = -1
    extreme = "Blazing" if commit_target >= 0 else "Hollow"
    turns = 0
    while turns < max_turns:
        turns += 1
        player.start_turn()
        if player.hp <= 0:
            break
        player.take_turn(enemies)
        if ttb < 0 and tier(player.passion) == extreme:
            ttb = turns
        if all(not e.c.alive() for e in enemies):
            return dict(win=True, turns=turns, hp=max(0, player.hp), passion=player.passion, ttb=ttb)
        player.end_turn()
        # Enemy turn
        for e in enemies:
            if not e.c.alive():
                continue
            e.c.block = 0
            e.c.tick_poison()
            if e.c.hp <= 0:
                continue
            if e.c.frozen > 0:          # Frozen: forfeit the action, then thaw
                e.c.frozen -= 1
            else:
                apply_enemy_effects(e, player, enemies)
            if e.c.weak > 0:
                e.c.weak -= 1
            if e.c.vulnerable > 0:
                e.c.vulnerable -= 1
            if player.hp <= 0:
                return dict(win=False, turns=turns, hp=0, passion=player.passion, ttb=ttb)
        for e in enemies:
            if e.c.alive():
                e.select_intent()
    return dict(win=player.hp > 0, turns=turns, hp=max(0, player.hp), passion=player.passion, ttb=ttb)


# ----------------------------------------------------------------------------
# SCENARIOS + REPORT
# ----------------------------------------------------------------------------
def run(deck, enemy_names, start_passion=PASSION_START, commit=False, commit_target=0,
        start_str=0, turn_block=0):
    res = [simulate(deck, enemy_names, s, start_passion, 60, commit, commit_target,
                    start_str, turn_block) for s in range(TRIALS)]
    wins = [r for r in res if r["win"]]
    winrate = 100.0 * len(wins) / len(res)
    hp_lost = [PLAYER_MAX_HP - r["hp"] for r in wins] or [PLAYER_MAX_HP]
    turns = [r["turns"] for r in wins] or [0]
    p90 = sorted(hp_lost)[min(len(hp_lost) - 1, int(0.9 * len(hp_lost)))]
    ttbs = [r["ttb"] for r in res if r["ttb"] >= 0]
    return dict(winrate=winrate, hp_mean=statistics.mean(hp_lost), hp_p90=p90,
                turns=statistics.mean(turns), end_passion=statistics.mean(r["passion"] for r in res),
                ttb=(statistics.mean(ttbs) if ttbs else -1.0), ttb_frac=len(ttbs) / len(res))


def bar(label, r):
    print(f"  {label:30s} win {r['winrate']:5.1f}%  turns {r['turns']:4.1f}  "
          f"HP-lost avg {r['hp_mean']:4.1f} p90 {r['hp_p90']:4.0f}  (of {PLAYER_MAX_HP})")


def pbar(label, r):
    ttb = "never" if r["ttb"] < 0 else f"{r['ttb']:.1f} ({int(round(r['ttb_frac']*100))}%)"
    print(f"  {label:30s} win {r['winrate']:5.1f}%  end-Passion {r['end_passion']:6.1f} "
          f"({tier(round(r['end_passion']))})  reaches extreme: {ttb}")


if __name__ == "__main__":
    print(f"\nFable combat sim (Python) — {TRIALS} trials, player {PLAYER_MAX_HP} HP / {ENERGY} energy")
    print("Signed Passion -100..+100 (Blazing >= +50). Rough companion to the GDScript harness.\n")

    print("REGULAR ENCOUNTERS (fresh Water starter deck):")
    for lbl, comp in [
        ("Knight (solo opener)", ["Corrupted Knight"]),
        ("Knight + Conspirator", ["Corrupted Knight", "Court Conspirator"]),
        ("2 Realm Shades", ["Realm Shade", "Realm Shade"]),
        ("Siege Golem (solo)", ["Siege Golem"]),
        ("Golem + Conspirator", ["Siege Golem", "Court Conspirator"]),
        ("Knight + Shade", ["Corrupted Knight", "Realm Shade"]),
        ("Man-at-Arms + Acolyte", ["Man-at-Arms", "Prophet's Acolyte"]),
        ("Knight + Squire", ["Corrupted Knight", "Corrupted Squire"]),
    ]:
        bar(lbl, run(FRESH_DECK, comp))

    print("\nELITES (mid-act deck):")
    bar("Champion of the Usurper", run(mid_deck(), ["Champion of the Usurper"]))
    bar("The Iron Verdict", run(mid_deck(), ["The Iron Verdict"]))

    print("\nPASSION POLES (vs a durable wall, committing from 0):")
    pbar("Water build  (target +50)", run(mid_deck(), ["Training Wall"], 0, True, 50))
    pbar("Physical build (target -50)", run(physical_deck(), ["Training Wall"], 0, True, -50))

    print("\nFALSE PROPHET — the Passion crucible (mid deck, start Blazing +50):")
    pbar("ignores Passion", run(mid_deck(), ["The False Prophet"], 50, False, 50))
    pbar("holds pole (Water)", run(mid_deck(), ["The False Prophet"], 50, True, 50))

    print("\nBOSS — Sir Caedmon (realistic: boss deck + Excalibur + Iron Quill + Guardian's Sigil):")
    for sp, name in [(50, "Blazing +50"), (18, "Inspired +18"), (-30, "Wavering -30")]:
        r = run(boss_deck() + [EXCALIBUR], ["Sir Caedmon"], sp, True, 50,
                start_str=1, turn_block=5)
        print(f"    start {name:12s} win {r['winrate']:5.1f}%  turns {r['turns']:4.1f}  "
              f"HP-lost avg {r['hp_mean']:4.1f} p90 {r['hp_p90']:4.0f}  "
              f"end-Passion {r['end_passion']:5.1f} ({tier(round(r['end_passion']))})")
    print()
