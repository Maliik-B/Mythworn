class_name RevealAnim
## Shared "reveal" motion for a single node/control: it enlarges in (scale up + fade), does
## a horizontal "swap" flip (at whose midpoint an optional callback swaps the node's face
## in), then de-enlarges to rest. Used by the map-reveal flourish (map_scene) AND the dev
## sandbox (scenes/dev/reveal_test_scene) so both play the exact same motion -- tune it here
## once and both update. All timings are params so callers can dial the feel.

## Play the reveal on `ctrl` after `delay` seconds, creating the tween on `host` (any Node in
## the tree). `swap_cb` (optional) fires at the flip midpoint -- use it to change the node's
## visible face (e.g. swap a blank glyph in). Recognized `params` keys (all optional):
##   enlarge (peak scale), enlarge_t, swap_t (full flip), deenlarge_t, start_scale.
static func play_node(host: Node, ctrl: Control, delay: float,
		params: Dictionary = {}, swap_cb: Callable = Callable()) -> void:
	var enlarge: float = params.get("enlarge", 1.4)
	var enlarge_t: float = params.get("enlarge_t", 0.28)
	var swap_t: float = params.get("swap_t", 0.24)
	var deenlarge_t: float = params.get("deenlarge_t", 0.20)
	var start_scale: float = params.get("start_scale", 0.5)

	ctrl.pivot_offset = ctrl.size / 2.0
	ctrl.scale = Vector2(start_scale, start_scale)
	ctrl.modulate.a = 0.0

	var tw := host.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	# Enlarge in (scale up past rest) while fading in.
	tw.tween_property(ctrl, "scale", Vector2(enlarge, enlarge), enlarge_t) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ctrl, "modulate:a", 1.0, enlarge_t * 0.7)
	# Swap: pinch horizontally shut, swap the face at the midpoint, flip back open.
	tw.tween_property(ctrl, "scale:x", 0.0, swap_t * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if swap_cb.is_valid():
		tw.tween_callback(swap_cb)
	tw.tween_property(ctrl, "scale:x", enlarge, swap_t * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# De-enlarge to rest.
	tw.tween_property(ctrl, "scale", Vector2.ONE, deenlarge_t) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
