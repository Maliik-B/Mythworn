# Sprite Asset Credits

## Enemies

### Monsters Creatures Fantasy — LuizMelo
- **Contents**: Goblin, Skeleton, Mushroom, Flying Eye (idle, run, attack, death, take hit)
- **License**: CC0 (Creative Commons Zero)
- **Source**: https://luizmelo.itch.io/monsters-creatures-fantasy

### Fire Worm — LuizMelo
- **Contents**: Fire Worm (idle, walk, attack, death, get hit) + fire ball projectile
- **License**: CC0 (Creative Commons Zero)
- **Source**: https://luizmelo.itch.io/fire-worm

### Camelot roster (corruption-recolored) — LuizMelo
These CC0 packs stand in for the Camelot demo enemies; the shipped strips are recolored
(algorithmically, not AI) toward the hollowed greyed-gold corruption palette. CC0 permits
modification and commercial use; credited here regardless.
- **Medieval Warrior Pack** (Man-at-Arms): bearded armored warrior (idle, attack, hit, death).
  CC0 — https://luizmelo.itch.io/medieval-warrior-pack
  `man_at_arms_whole/` is the same strips recolored by hand into living colour, also not AI; it
  stands in for Sir Caedmon until his own sheet lands.

`baked/` holds the same sheets again, run through `tools/bake_sheet.py` for the page look: one value
ramp, one outline, one window, lapis on one object. An algorithmic recolor of CC0 art, not AI.

## Bosses

### Evil Wizard 2 — LuizMelo
- **Contents**: Hooded wizard with staff (idle, run, attack x2, jump, fall, take hit, death)
- **License**: CC0 (Creative Commons Zero)
- **Source**: https://luizmelo.itch.io/evil-wizard-2

## Icons

### Weapons and Potions Free Pack — Clockwork Raven
- **Contents**: the thirteen 64x64 icons the cards use, from the pack's 100+ weapon and potion icons
- **License**: Free for commercial and non-commercial use. Cannot be redistributed as a standalone product.
- **Source**: https://clockworkraven.itch.io/free-rpg-icon-pack-100-weapons-and-po-clockwork-raven-studios

### 30 Free Pixel Art RPG Icons — In The Void
- **Contents**: the five icons the cards and the altar use: a shield, a blue gem, a gauntlet, a red scroll and a chestplate
- **License**: Free for commercial and non-commercial use
- **Source**: https://in-the-void.itch.io/free-rpg-icons

## Set pieces

The sword in the Excalibur set piece (`assets/sprites/set_pieces/excalibur_sword.png`) and the altar's scabbard (`scabbard_bare.png`, `scabbard_ornate.png`) are one CC0 model, rendered and baked: the page's colours and outline put on a nearest-neighbour reduction of an orthographic render, no pixels drawn, then straightened by the same tool: each is rebuilt as a mirror-symmetric stack of cross-sections of one width, the render supplying the widths and the shading. Both bakes of the scabbard are the one render, the bare in the page's grey ramp and the ornate in kermes and burnished gold. See "Sword + Scabbard" below. The man beside the sword is the Man-at-Arms above, and the stone, plinth, light and darkness on those stages are code-drawn chrome. The altar's shield (In The Void's `shield.png`, drained for its worn form) is kept as a second figure that is not staged.

### Sword + Scabbard (IkBenAnders)
- **Contents**: a low-poly sword and scabbard, `sword.blend` (served as `sword_14.blend`), rendered with Blender and baked by `tools/bake_prop.py`.
- **License**: CC0, as stated on the page (textures from ambientCG, public domain). Page dated 21 May 2023, checked 9 November 2026.
- **Source**: https://opengameart.org/content/sword-scabbard

## Fonts

All under the SIL Open Font License 1.1; the licence text sits beside each font in `assets/fonts/`.

- **Grenze Gotisch** (names and card titles), Copyright 2020 The Grenze Gotisch Project Authors. https://github.com/Omnibus-Type/Grenze-Gotisch
- **Castoro Titling** (numerals), by Tiro Typeworks. https://github.com/TiroTypeworks/Castoro
- **Marcellus SC** (kept for trying against the others, not in use), Copyright (c) 2012 Brian J. Bonislawsky DBA Astigmatic (AOETI). https://fonts.google.com/specimen/Marcellus+SC
- **EB Garamond** (card rules), Copyright 2017 The EB Garamond Project Authors. https://github.com/octaviopardo/EBGaramond12

## Backgrounds

### Parallax Backgrounds: Snowy Mountains, by Admurin
- **Used in**: the cold frame of the staged crossing (`realms/cold_edge/`). The pack's five layers, as downloaded, in their own palette and otherwise unchanged; `snowy_sky`, `snowy_mountains`, `snowy_pines_far`, `snowy_pines_near` and `snowy_ground` are the pack's `5`, `4`, `3`, `2` and `1`. The stage lifts the layers to stand clear of the hand's row.
- **License**: "You can use this asset in any game project, personal or commercial"; "Modify to suit your needs"; "DO NOT resell or redistribute AS A GAME ASSET, it has to be part of a project"; no NFTs; not to be used to train AI. Credit not required, and given with thanks. The page states "No generative AI was used".
- **Not in this repository**: the licence bars redistributing the pack's art as loose files, so it ships only inside built games.
- **Source**: https://admurin.itch.io/parallax-backgrounds-snowy-mountains
