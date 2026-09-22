"""
Fable combat balance simulator.

An analytical model of Fable's combat rules used to put enemy HP/damage and the
Passion mechanics into a sane band BEFORE we author them in GDScript. It is NOT the
real engine: it re-implements the rules (block reset per turn, Weak/Vulnerable/
Strength/Poison, multi-hit vs block, the Passion zone modifier, and the weighted
enemy AI with HP-gating + per-move cooldowns that we just added to EnemyCombatState)
and drives the player with a fixed heuristic policy. So it sets bands and shows the
Passion swing; final tuning is playtest (critical-path track A5).

Assumptions are declared up top so they are easy to challenge. Run: python tools/combat_sim.py
"""

import random
import statistics
from dataclasses import dataclass, field

# ----------------------------------------------------------------------------
# ASSUMPTIONS (the levers that most affect the output — challenge these first)
# ----------------------------------------------------------------------------
PLAYER_MAX_HP = 80
ENERGY = 3
HAND_SIZE = 5
TRIALS = 4000
CHIP_TOLERANCE = 6      # HP of incoming the player will "eat" before bothering to block
SAFETY_FRAC = 0.35      # below this fraction of max HP, the player blocks hard
ON_TYPE_BONUS = 0.25    # proposed: on-type cards deal +25% at the committed extreme
OFF_TYPE_PENALTY = 0.75 # existing: off-type cards deal 75% at the committed extreme

# Signed Passion axis (matches the game post-refactor): -100..+100, start 0 (Steady).
# Thresholds [blazing_min, inspired_min, steady_min, wavering_min]; below = hollow.
PASSION_THRESHOLDS = [50, 18, -18, -50]
PASSION_START = 0

NEUTRAL, PRIMARY, SECONDARY = "neutral", "primary", "secondary"  # primary=Magic, secondary=Physical


def tier(v):
    if v >= PASSION_THRESHOLDS[0]: return "Blazing"
    if v >= PASSION_THRESHOLDS[1]: return "Inspired"
    if v >= PASSION_THRESHOLDS[2]: return "Steady"
    if v >= PASSION_THRESHOLDS[3]: return "Wavering"
    return "Hollow"


def passion_center():
    # Midpoint of the Steady band (character-aware, matches RunManager.passion_center()).
    return (PASSION_THRESHOLDS[1] + PASSION_THRESHOLDS[2]) // 2  # = 50


def zone_mult(personality, passion):
    """Card damage multiplier from the proposed complete zone system."""
    if personality == NEUTRAL:
        return 1.0
    t = tier(passion)
    if t == "Blazing":
        return 1.0 + ON_TYPE_BONUS if personality == PRIMARY else OFF_TYPE_PENALTY
    if t == "Hollow":
        return 1.0 + ON_TYPE_BONUS if personality == SECONDARY else OFF_TYPE_PENALTY
    return 1.0  # Inspired / Steady / Wavering: flat (the dispassionate middle)


# ----------------------------------------------------------------------------
# COMBATANTS
# ----------------------------------------------------------------------------
@dataclass
class Combatant:
    hp: int
    max_hp: int
    block: int = 0
    strength: int = 0
    weak: int = 0
    vulnerable: int = 0
    poison: int = 0

    def alive(self):
        return self.hp > 0

    def take_hit(self, raw, attacker_strength=0, attacker_weak=False):
        dmg = raw + attacker_strength
        if attacker_weak:
            dmg = int(dmg * 0.75)
        if self.vulnerable > 0:
            dmg = int(dmg * 1.5)
        blocked = min(self.block, dmg)
        self.block -= blocked
        self.hp -= (dmg - blocked)
        return dmg - blocked

    def tick_start(self):
        # Poison ticks (bypasses block), then decrements.
        if self.poison > 0:
            self.hp -= self.poison
            self.poison -= 1


# ----------------------------------------------------------------------------
# ENEMY DEFINITIONS  (the numbers we are balancing)
# effects: list of tuples. ("dmg", n) | ("dmg_x", n, hits) | ("block", n) |
#          ("str", n) | ("weak", n) | ("vuln", n) | ("poison", n) |
#          ("passion", n) | ("passion_center", n)
# move: (name, weight, cooldown, min_hp_frac, max_hp_frac, [effects])
# ----------------------------------------------------------------------------
def M(name, weight, effects, cd=0, lo=0.0, hi=1.0):
    return dict(name=name, weight=weight, cd=cd, lo=lo, hi=hi, effects=effects)


ENEMIES = {
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
    ]),
    "Siege Golem": dict(hp=64, moves=[
        M("Grind", 2.0, [("dmg", 8)]),
        M("Crushing Step", 1.0, [("dmg", 11)]),
        M("Siege Slam", 1.6, [("dmg", 15)], cd=2),
    ]),
    "Realm Shade": dict(hp=34, moves=[
        M("Fade Strike", 1.5, [("dmg", 6)]),
        M("Shroud", 1.4, [("block", 7)]),
        M("Hex", 1.0, [("weak", 1)]),
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
    # Tanky attrition body so the centering has time to bite, but with counterplay:
    # the pull is modest enough that a player who spends Passion cards can hold their
    # pole. This is the reference enemy for tuning card Passion values.
    "The False Prophet": dict(hp=110, moves=[
        # A Passion specialist: it pulls you toward center on nearly every turn
        # (Sermon on cd, Doubt fills the gaps), with damage/block as the minority.
        M("False Sermon", 2.6, [("passion_center", 7), ("weak", 1)], cd=2),
        M("Doubt", 2.4, [("passion_center", 5)]),
        M("Condemn", 1.1, [("dmg", 10), ("vuln", 1)]),
        M("Zealot's Ward", 1.1, [("block", 14)]),
    ]),
    # --- Boss ---
    "Sir Caedmon": dict(hp=130, moves=[
        # Phase 1 (>50%): disciplined
        M("Vanguard Strike", 2.0, [("dmg", 10)], lo=0.5),
        M("Oathbound Guard", 1.3, [("block", 12), ("str", 1)], lo=0.5),
        M("Rallying Blow", 1.4, [("dmg", 20)], cd=3, lo=0.5),
        # Phase 2 (<50%): Compelled, reckless, Guard dropped
        M("Compelled Onslaught", 2.0, [("dmg_x", 6, 3)], hi=0.5),
        M("Hollowing Gaze", 1.6, [("passion", -6), ("weak", 2)], cd=2, hi=0.5),
        M("Puppet's Fervor", 1.2, [("str", 3)], cd=1, hi=0.5),
    ]),
}


class EnemyState:
    def __init__(self, name, rng):
        d = ENEMIES[name]
        self.name = name
        self.c = Combatant(hp=d["hp"], max_hp=d["hp"])
        self.moves = d["moves"]
        self.rng = rng
        self.turn = 0
        self.last_used = {}
        self.intent = None
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
        """Attack damage this enemy's telegraphed intent will deal to the player."""
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
# PLAYER CARDS + DECKS
# card: dict(name, cost, kind, personality, effects)
# effects use same tuple vocab; player damage tuples are ("dmg", n) / ("dmg_x", n, hits)
# ----------------------------------------------------------------------------
def C(name, cost, kind, effects, pers=NEUTRAL):
    return dict(name=name, cost=cost, kind=kind, pers=pers, effects=effects)


# --- Pole-defined starting deck (mirrors CharacterPool.emo_starting_deck) ---
# Neutral backbone (no Passion shift) + a couple of cards down each pole. Water
# cards BUILD +Passion (toward Blazing); Physical cards build −Passion (toward
# Hollow). See GAME_DESIGN "Starting deck — iteration log".
STRIKE   = C("Strike", 1, "atk", [("dmg", 6)])
DEFEND   = C("Defend", 1, "blk", [("block", 5)])
OUTPOUR  = C("Outpouring", 1, "atk", [("dmg", 9), ("self_passion", 3)], PRIMARY)
RIPTIDE  = C("Riptide", 1, "atk", [("dmg_x", 4, 2), ("self_passion", 3)], PRIMARY)
MEASURED = C("Measured Blow", 1, "atk", [("dmg", 8), ("self_passion", -3)], SECONDARY)
GUARD    = C("Guard", 1, "blk", [("block", 8), ("self_passion", -3)], SECONDARY)

# Pool approximations for a mid-act Water-leaning deck.
TIDAL    = C("Tidal Strike", 1, "atk", [("dmg", 9), ("self_passion", 3)], PRIMARY)
MAELSTROM= C("Maelstrom", 2, "atk", [("dmg_x", 5, 3), ("self_passion", 5)], PRIMARY)
POWERSLSH= C("Power Slash", 1, "atk", [("dmg", 7), ("block", 3), ("self_passion", -3)], SECONDARY)


FRESH_DECK = [STRIKE]*2 + [DEFEND]*2 + [OUTPOUR, RIPTIDE, MEASURED, GUARD]


def build_mid_deck():
    # A Water(Primary)-leaning mid-act deck that WANTS to sit at Blazing. Water cards
    # BUILD Passion toward the pole, so committing is a matter of playing them; the
    # Prophet's center-pull is the pressure the counterplay fights.
    return FRESH_DECK[:] + [TIDAL, MAELSTROM, POWERSLSH]


MID_DECK = build_mid_deck()


class Player:
    def __init__(self, deck, rng, passion=PASSION_START, defend_passion=False, desired_min=0):
        self.c = Combatant(hp=PLAYER_MAX_HP, max_hp=PLAYER_MAX_HP)
        self.rng = rng
        self.passion = passion
        # Counterplay: when True, the player will spend a Passion card per turn to
        # climb back toward desired_min (their pole) if the Prophet is centering them.
        self.defend_passion = defend_passion
        self.desired_min = desired_min
        self.draw = deck[:]
        rng.shuffle(self.draw)
        self.hand = []
        self.discard = []

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
        self._draw_cards(HAND_SIZE)

    def _card_damage(self, card):
        dmg = 0
        for e in card["effects"]:
            if e[0] == "dmg":
                dmg += e[1]
            elif e[0] == "dmg_x":
                dmg += e[1] * e[2]
        return int(dmg * zone_mult(card["pers"], self.passion))

    def take_turn(self, enemies):
        energy = ENERGY
        living = [e for e in enemies if e.c.alive()]
        incoming = sum(e.predicted_damage(self.c.vulnerable) for e in living)
        biggest = max((e.predicted_damage(self.c.vulnerable) for e in living), default=0)
        # If we can plausibly kill everything this turn, skip blocking and go for it.
        avail_dmg = sum(self._card_damage(c) for c in self.hand
                        if c["kind"] == "atk" and c["cost"] <= energy)
        can_lethal = avail_dmg >= sum(e.c.hp for e in living)
        # 1) Block proactively against a telegraphed spike, or when a hit would drop
        #    us below the safety margin. A real player Defends the big telegraph.
        unblocked = max(0, incoming - self.c.block)
        spike = biggest >= 12
        if not can_lethal and (spike or self.hp_after(unblocked) < SAFETY_FRAC * PLAYER_MAX_HP):
            blocks = sorted([c for c in self.hand if c["kind"] == "blk"], key=lambda c: c["cost"])
            for card in blocks:
                if energy < card["cost"]:
                    continue
                if self.c.block >= incoming - CHIP_TOLERANCE:
                    break
                energy = self._play(card, enemies, energy)
        # 1.5) Passion counterplay: spend one card to hold our pole against centering.
        if self.defend_passion and not can_lethal and self.passion < self.desired_min:
            pcards = [c for c in self.hand if c["cost"] <= energy
                      and any(e[0] == "self_passion" and e[1] > 0 for e in c["effects"])]
            if pcards:
                energy = self._play(pcards[0], enemies, energy)
        # 2) Spend the rest on offense. Apply Vulnerable to a healthy target first.
        target = self._lowest(enemies)
        if target and target.c.vulnerable == 0 and target.c.hp > 14:
            stag = next((c for c in self.hand if "vuln" in [x[0] for x in c["effects"]]
                         and c["cost"] <= energy), None)
            if stag:
                energy = self._play(stag, enemies, energy)
        # Then biggest effective damage on the lowest-HP living enemy.
        while energy > 0:
            atks = [c for c in self.hand if c["kind"] in ("atk", "blk")
                    and c["cost"] <= energy and self._useful(c, enemies)]
            if not atks:
                break
            atks.sort(key=lambda c: self._card_damage(c), reverse=True)
            energy = self._play(atks[0], enemies, energy)

    def _useful(self, card, enemies):
        # A block card is only "useful" late if it also deals damage (Retaliate).
        if card["kind"] == "blk":
            return any(e[0] in ("dmg", "dmg_x") for e in card["effects"])
        return True

    def _play(self, card, enemies, energy):
        self.hand.remove(card)
        self.discard.append(card)
        target = self._lowest(enemies)
        mult = zone_mult(card["pers"], self.passion)
        for e in card["effects"]:
            if e[0] == "dmg" and target:
                target.c.take_hit(int(e[1] * mult))
            elif e[0] == "dmg_x" and target:
                for _ in range(e[2]):
                    target.c.take_hit(int(e[1] * mult))
            elif e[0] == "block":
                self.c.block += e[1]
            elif e[0] == "vuln" and target:
                target.c.vulnerable += e[1]
            elif e[0] == "self_passion":
                self.passion = max(0, min(100, self.passion + e[1]))
        return energy - card["cost"]

    def _lowest(self, enemies):
        living = [e for e in enemies if e.c.alive()]
        return min(living, key=lambda e: e.c.hp) if living else None

    def hp_after(self, dmg):
        return self.c.hp - dmg

    @property
    def hp(self):
        return self.c.hp


# ----------------------------------------------------------------------------
# COMBAT LOOP
# ----------------------------------------------------------------------------
def apply_enemy_effects(enemy, player):
    for e in enemy.intent["effects"]:
        k = e[0]
        if k == "dmg":
            player.c.take_hit(e[1], enemy.c.strength, enemy.c.weak > 0)
        elif k == "dmg_x":
            for _ in range(e[2]):
                player.c.take_hit(e[1], enemy.c.strength, enemy.c.weak > 0)
        elif k == "block":
            enemy.c.block += e[1]
        elif k == "str":
            enemy.c.strength += e[1]
        elif k == "weak":
            player.c.weak += e[1]
        elif k == "vuln":
            player.c.vulnerable += e[1]
        elif k == "poison":
            player.c.poison += e[1]
        elif k == "passion":
            player.passion = max(0, min(100, player.passion + e[1]))
        elif k == "passion_center":
            center = passion_center()
            if player.passion > center:
                player.passion = max(center, player.passion - e[1])
            elif player.passion < center:
                player.passion = min(center, player.passion + e[1])


def simulate(deck, enemy_names, seed, start_passion=PASSION_START, max_turns=40,
             defend_passion=False, desired_min=0):
    rng = random.Random(seed)
    player = Player(deck, rng, start_passion, defend_passion, desired_min)
    enemies = [EnemyState(n, rng) for n in enemy_names]
    turns = 0
    while turns < max_turns:
        turns += 1
        # Player turn
        player.c.weak = max(0, player.c.weak)  # statuses persist; decremented at end
        player.start_turn()
        # tick player poison at start of player turn
        player.c.tick_start()
        if player.hp <= 0:
            return dict(win=False, turns=turns, hp=0, passion=player.passion)
        player.take_turn(enemies)
        if all(not e.c.alive() for e in enemies):
            return dict(win=True, turns=turns, hp=max(0, player.hp), passion=player.passion)
        # decrement player debuffs (Weak/Vulnerable) after player's turn, STS-style
        player.c.weak = max(0, player.c.weak - 1)
        player.c.vulnerable = max(0, player.c.vulnerable - 1)
        # Enemy turn
        for e in enemies:
            if not e.c.alive():
                continue
            e.c.block = 0
            if e.c.weak > 0:
                pass
            apply_enemy_effects(e, player)
            if e.c.weak > 0:
                e.c.weak -= 1
            if player.hp <= 0:
                return dict(win=False, turns=turns, hp=0, passion=player.passion)
        # enemies choose next telegraph
        for e in enemies:
            if e.c.alive():
                e.select_intent()
    return dict(win=player.hp > 0, turns=turns, hp=max(0, player.hp), passion=player.passion)


# ----------------------------------------------------------------------------
# SCENARIOS + REPORT
# ----------------------------------------------------------------------------
def run(label, deck, enemy_names, start_passion=PASSION_START,
        defend_passion=False, desired_min=0):
    res = [simulate(deck, enemy_names, s, start_passion, 40, defend_passion, desired_min)
           for s in range(TRIALS)]
    wins = [r for r in res if r["win"]]
    winrate = 100.0 * len(wins) / len(res)
    hp_lost = [PLAYER_MAX_HP - r["hp"] for r in wins] or [PLAYER_MAX_HP]
    turns = [r["turns"] for r in wins] or [0]
    p90 = sorted(hp_lost)[int(0.9 * len(hp_lost)) - 1]
    end_pass = statistics.mean(r["passion"] for r in res)
    return dict(label=label, winrate=winrate,
                hp_mean=statistics.mean(hp_lost), hp_p90=p90,
                turns=statistics.mean(turns), end_passion=end_pass,
                start_passion=start_passion)


def bar(label, r):
    print(f"  {label:34s} win {r['winrate']:5.1f}%  "
          f"turns {r['turns']:4.1f}  HP-lost avg {r['hp_mean']:4.1f} p90 {r['hp_p90']:4.0f}"
          f"  (of {PLAYER_MAX_HP})")


if __name__ == "__main__":
    print(f"\nFable combat sim — {TRIALS} trials/scenario, player {PLAYER_MAX_HP} HP / {ENERGY} energy")
    print(f"on-type bonus +{int(ON_TYPE_BONUS*100)}%, off-type penalty -{int((1-OFF_TYPE_PENALTY)*100)}%\n")

    print("REGULAR ENCOUNTERS (fresh deck):")
    for lbl, comp in [
        ("Knight (solo, opener)", ["Corrupted Knight"]),
        ("Knight + Conspirator", ["Corrupted Knight", "Court Conspirator"]),
        ("2 Realm Shades", ["Realm Shade", "Realm Shade"]),
        ("Siege Golem (solo)", ["Siege Golem"]),
        ("Siege Golem + Conspirator", ["Siege Golem", "Court Conspirator"]),
        ("Knight + Shade", ["Corrupted Knight", "Realm Shade"]),
    ]:
        bar(lbl, run(lbl, FRESH_DECK, comp))

    print("\nELITES (mid-act deck):")
    bar("Champion of the Usurper", run("champ", MID_DECK, ["Champion of the Usurper"]))

    print("\n  False Prophet, starting at Blazing +60 (the pole a Water build wants):")
    ignore = run("prophet", MID_DECK, ["The False Prophet"], start_passion=60)
    defend = run("prophet", MID_DECK, ["The False Prophet"], start_passion=60,
                 defend_passion=True, desired_min=50)
    for tag, r in [("ignores Passion", ignore), ("defends pole (Water cards)", defend)]:
        print(f"    {tag:26s} win {r['winrate']:5.1f}%  turns {r['turns']:4.1f}"
              f"  HP-lost avg {r['hp_mean']:4.1f} p90 {r['hp_p90']:4.0f}"
              f"  end-Passion {r['end_passion']:4.1f} ({tier(round(r['end_passion']))})")

    print("\nBOSS — Sir Caedmon (mid-act deck):")
    for sp, name in [(60, "Blazing +60"), (30, "Inspired +30"), (-30, "Wavering -30")]:
        r = run("caedmon", MID_DECK, ["Sir Caedmon"], start_passion=sp)
        print(f"    start {name:12s} win {r['winrate']:5.1f}%  turns {r['turns']:4.1f}"
              f"  HP-lost avg {r['hp_mean']:4.1f} p90 {r['hp_p90']:4.0f}"
              f"  end-Passion {r['end_passion']:4.1f} ({tier(round(r['end_passion']))})")
    print()
