extends CanvasLayer
## Global popup that fires whenever a title is earned (Events.title_earned).
## Pops in from the top of the screen with the title's flavor and accent color,
## holds while the player reads, dismisses on click or after a timeout.
##
## Stays out of the way of gameplay: sits on a high layer above scene content
## but below SceneTransition's fade. Multiple titles earned in quick succession
## queue up rather than overlapping.

const HOLD_TIMEOUT := 4.0  # seconds before auto-dismiss
const ANIMATE_IN_DURATION := 0.4
const ANIMATE_OUT_DURATION := 0.25
const CARD_W := 340.0       # fixed width; the card grows downward on hover only
const MARGIN := 24.0        # inset from the top-right corner

var _root: Control
var _queue: Array[StringName] = []
var _showing: bool = false
var _current_dismiss_timer: SceneTreeTimer = null
## Track the live card here so the auto-dismiss timer doesn't have to capture
## a reference that may be freed before it fires. The timer reads this and
## no-ops if it's already null.
var _live_card: PanelContainer = null
## While true, earned titles queue without showing. A staged moment holds the toast so nothing
## cheers over it; the scene that held it lets it go on the way out (see `release`).
var _held: bool = false


func _ready() -> void:
	layer = 90  # below SceneTransition (100) but above scene content
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	Events.title_earned.connect(_on_title_earned)


func _on_title_earned(title_id: StringName) -> void:
	_queue.append(title_id)
	if not _showing and not _held:
		_show_next()


## Queue titles instead of showing them until `release`.
func hold() -> void:
	_held = true


## Shows anything held back. Safe to call when nothing is held.
func release() -> void:
	if not _held:
		return
	_held = false
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var id: StringName = _queue.pop_front()
	_present_card(id)


func _present_card(title_id: StringName) -> void:
	var data: TitleData = TitlePool.get_title(title_id)
	if not data:
		_show_next()
		return

	# Compact card tucked into the TOP-RIGHT corner so it never overlaps event or
	# combat content. Collapsed by default; the full description appears only while
	# the player hovers (at their discretion), and it grows downward, never over the
	# text they might be reading.
	var card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.08, 0.13, 0.96)
	style.set_corner_radius_all(8)
	style.set_border_width_all(3)
	style.border_color = data.accent_color
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# Badge: "TITLE EARNED" in accent color
	var badge = Label.new()
	badge.text = "✦ TITLE EARNED"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", data.accent_color)
	vbox.add_child(badge)

	# Title name (Original tier name: players see the title's "true" name when earning)
	var name_lbl = Label.new()
	name_lbl.text = data.original_name
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	vbox.add_child(name_lbl)

	# Description (Original tier flavor), hidden until hover.
	var desc_lbl = Label.new()
	desc_lbl.text = data.original_description
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", Color(0.72, 0.7, 0.64))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.custom_minimum_size.x = CARD_W - 40
	desc_lbl.visible = false
	vbox.add_child(desc_lbl)

	# Hint
	var hint = Label.new()
	hint.name = "Hint"
	hint.text = "hover for details · click to dismiss"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.5, 0.47, 0.44))
	vbox.add_child(hint)

	_root.add_child(card)
	_live_card = card
	card.gui_input.connect(_on_card_input.bind(card))

	# Hover expands the details (grows the card downward), at the player's discretion.
	card.mouse_entered.connect(func():
		desc_lbl.visible = true
		hint.text = "click to dismiss"
	)
	card.mouse_exited.connect(func():
		desc_lbl.visible = false
		hint.text = "hover for details · click to dismiss"
	)

	# Slide in from off the right edge into the corner.
	var target_x := _root.size.x - CARD_W - MARGIN
	card.position = Vector2(_root.size.x + 20.0, MARGIN)
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "position:x", target_x, ANIMATE_IN_DURATION)

	# Auto-dismiss timer reads `_live_card` instead of capturing `card`. When
	# the player manually dismisses, `_live_card` is cleared, so the timer
	# safely no-ops on fire, avoiding Godot's "freed lambda capture" warning
	# and the older bind-typed-arg conversion error.
	_current_dismiss_timer = get_tree().create_timer(HOLD_TIMEOUT)
	_current_dismiss_timer.timeout.connect(_on_auto_dismiss_timeout)


func _on_auto_dismiss_timeout() -> void:
	if is_instance_valid(_live_card):
		_dismiss_card(_live_card)


func _on_card_input(event: InputEvent, card: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dismiss_card(card)


func _dismiss_card(card: Control) -> void:
	if not is_instance_valid(card):
		# Already gone (e.g. from rapid double-dismiss)
		_live_card = null
		_show_next()
		return
	# Clear the live ref immediately so a pending auto-dismiss timer firing
	# after this point will see null and no-op cleanly.
	if _live_card == card:
		_live_card = null
	# Disable input on the card so a second click doesn't queue another dismiss
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_parallel(true)
	tween.tween_property(card, "position:x", _root.size.x + 20.0, ANIMATE_OUT_DURATION)
	tween.tween_property(card, "modulate:a", 0.0, ANIMATE_OUT_DURATION)
	tween.chain().tween_callback(func():
		if is_instance_valid(card):
			card.queue_free()
		_show_next()
	)
