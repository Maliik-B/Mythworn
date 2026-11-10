class_name CardSigil
extends RefCounted
## The school coin on a card's face: the pool SIGIL (≈ Water / ⚔ Physical) the card wears via its
## school, built the same way wherever a face is drawn (the fight's hand, the reward screen, the
## shop, the deck). It reads the live Passion zone through CombatEngine.zone_multiplier, which is
## static, so a card shown off the fight shows the zone the keeper is in now.
##
## For a true pole card the coin reflects the zone: FAVORED = an empowered glyph (brighter and a
## breathing pulse), and at the DEEP end (+25% extreme) the glyph sits on a glowing HALO coin, the
## at-a-glance tell that separates a fresh +12% lean from a deep +25% extreme. The fight fades that
## halo in and out when Passion crosses the threshold, so the halo is kept as the holder's
## "halo_disc" meta. DISFAVORED = greyed and faded (uniform across -12% / -25%). A NEUTRAL card that
## merely wears a school symbol never rides the zone, so it stays flat and muted, with no coin.


## The pole's name as the character words it ("Curse" for a negative card).
static func label(pers: CardData.PersonalityType) -> String:
	if pers == CardData.PersonalityType.NEGATIVE:
		return "Curse"
	if RunManager.current_character:
		if pers == CardData.PersonalityType.PRIMARY:
			return RunManager.current_character.primary_personality
		if pers == CardData.PersonalityType.SECONDARY:
			return RunManager.current_character.secondary_personality
	var names = {
		CardData.PersonalityType.PRIMARY: "Primary",
		CardData.PersonalityType.SECONDARY: "Secondary",
	}
	return names.get(pers, "")


static func colour(pers: CardData.PersonalityType) -> Color:
	if pers == CardData.PersonalityType.PRIMARY:
		return StageSkin.c("school_water") # Warm orange for magic
	if pers == CardData.PersonalityType.SECONDARY:
		return StageSkin.c("school_physical") # Cool blue for physical
	if pers == CardData.PersonalityType.NEGATIVE:
		return Color(0.55, 0.5, 0.42) # Dead ash for curses
	return Color(0.6, 0.6, 0.6)


## A persistent identity glyph: rippling water for the Water pole, crossed blades for Physical. The
## water glyph also distinguishes the pole from the ✦ used by the Sword-in-the-Stone map node.
static func glyph(pers: CardData.PersonalityType) -> String:
	if pers == CardData.PersonalityType.PRIMARY:
		return "≈"  # water ripples
	if pers == CardData.PersonalityType.SECONDARY:
		return "+" if StageSkin.is_page() else "⚔"
	return ""


## The coin for `card`, or null for a school-less card.
static func build(card: CardData) -> Control:
	var pole := card.symbol_pole()
	var mark := glyph(pole)
	if mark == "":
		return null
	var col := colour(pole)
	var pole_name := label(pole)
	# Only a true pole card rides the zone; a neutral-schooled card just wears a flat symbol.
	var rides_zone := card.personality == CardData.PersonalityType.PRIMARY \
		or card.personality == CardData.PersonalityType.SECONDARY
	var zm := CombatEngine.zone_multiplier(card.personality) if rides_zone else 1.0

	var lbl := Label.new()
	lbl.text = mark
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.material = StageSkin.no_purple()

	if zm > 1.0:
		# FAVORED — an empowered glyph, styled the SAME at the lean and extreme tiers: the halo
		# COIN (below, pole cards only) is what marks the deep +25%, so the glyph itself doesn't
		# have to carry the lean/extreme distinction.
		lbl.add_theme_font_size_override("font_size", 28)
		lbl.add_theme_color_override("font_color", col if StageSkin.is_page() else col.lightened(0.34))
		if not StageSkin.is_page():
			lbl.add_theme_constant_override("outline_size", 5)
			lbl.add_theme_color_override("font_outline_color", Color(col.r, col.g, col.b, 0.85))
		lbl.tooltip_text = "%s. Resonant: +%d%% damage at your current Passion." \
			% [pole_name, roundi((zm - 1.0) * 100.0)]
		var pulse := lbl.create_tween().set_loops()
		pulse.tween_property(lbl, "modulate", Color(1.18, 1.18, 1.18, 1.0), 0.65) \
			.set_trans(Tween.TRANS_SINE)
		pulse.tween_property(lbl, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.65) \
			.set_trans(Tween.TRANS_SINE)
	elif zm < 1.0:
		# Disfavored: greyed + faded, uniform across the −12% / −25% tiers.
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", col.lerp(Color(0.45, 0.45, 0.45), 0.6))
		lbl.modulate.a = 0.55
		lbl.tooltip_text = "%s. Dissonant: -%d%% damage at your current Passion." \
			% [pole_name, roundi((1.0 - zm) * 100.0)]
	else:
		# Flat: the identity colour, muted. A NEUTRAL card wearing a school symbol (never rides
		# the zone) OR an uncommitted pole card at Steady. Tooltip tells them apart.
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", col)
		lbl.modulate.a = 0.8
		if card.personality == CardData.PersonalityType.NEUTRAL:
			lbl.tooltip_text = "%s-aligned: a neutral card, so no zone bonus or penalty." % pole_name
		else:
			lbl.tooltip_text = "%s card. Commit to its Passion pole for +25%% damage." % pole_name

	# Both shapes below hold the glyph as a full-rect label in the 42x42 coin place, and set it by
	# what it inks (the swords sat 2 px high and the ripples 3 px low): NodeFace measures the glyph
	# once and the answer is written into the label's offsets.
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	NodeFace.centre_glyph(mark, load(StageSkin.LINE_FONT_PATH), lbl.get_theme_font_size("font_size"),
		NodeFace.COIN_SCHOOL_BOX,
		func(shift: Vector2) -> void:
			if is_instance_valid(lbl):
				lbl.offset_left = shift.x
				lbl.offset_right = shift.x
				lbl.offset_top = shift.y
				lbl.offset_bottom = shift.y)

	# A neutral-schooled card never rides the zone → no coin; a bare glyph is enough.
	if not rides_zone:
		var bare := Control.new()
		bare.custom_minimum_size = NodeFace.COIN_SCHOOL_BOX
		bare.add_child(lbl)
		return bare

	# A pole card sits in a fixed 42×42 holder (so the glyph never shifts across tiers) over a halo
	# COIN that is only opaque at the extreme (+25%). The coin is kept present-but-transparent at
	# every tier so it can FADE in/out on a threshold crossing. Disc + glyph are click-through so
	# the card panel keeps its hover; the holder carries the tooltip.
	var extreme := zm >= (CombatEngine.ZONE_LEAN_BONUS + CombatEngine.ZONE_EXTREME_BONUS) * 0.5
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(42, 42)
	holder.tooltip_text = lbl.tooltip_text
	var disc := Panel.new()
	disc.set_anchors_preset(Control.PRESET_FULL_RECT)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	if StageSkin.is_page():
		# A rubricated disc, the cost coin's twin, with the mark struck out of it in the leaf's colour.
		ds.bg_color = col
		ds.set_corner_radius_all(16)
		disc.set_anchors_preset(Control.PRESET_CENTER)
		disc.offset_left = -16.0
		disc.offset_top = -16.0
		disc.offset_right = 16.0
		disc.offset_bottom = 16.0
		if extreme:
			lbl.add_theme_color_override("font_color", StageSkin.c("card_coin_text"))
	else:
		ds.bg_color = Color(col.r, col.g, col.b, 0.30)
		ds.set_corner_radius_all(21)
		ds.shadow_color = Color(col.r, col.g, col.b, 0.5)
		ds.shadow_size = 8
	disc.add_theme_stylebox_override("panel", ds)
	disc.modulate.a = 1.0 if extreme else 0.0
	holder.add_child(disc)
	holder.add_child(lbl)
	holder.set_meta("halo_disc", disc)
	return holder
