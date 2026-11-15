class_name UiHelpers
extends RefCounted

const MENU_DESIGN_SIZE := Vector2(1920.0, 1080.0)
const MENU_FONT: Font = preload("res://assets/fonts/Jura-Variable.ttf")
const MENU_PLANET: Texture2D = preload("res://assets/ui/figma_menu/mars.png")
const MENU_SLIDER_THUMB: Texture2D = preload("res://assets/ui/figma_menu/slider-thumb.svg")
const MENU_RADIO_OUTER: Texture2D = preload("res://assets/ui/figma_menu/radio-outer.svg")
const MENU_RADIO_OUTER_ALT: Texture2D = preload("res://assets/ui/figma_menu/radio-outer-alt.svg")
const MENU_RADIO_INNER: Texture2D = preload("res://assets/ui/figma_menu/radio-inner.svg")

static func create_menu_canvas(parent: Control) -> Control:
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	canvas.size = MENU_DESIGN_SIZE
	canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(canvas)
	parent.resized.connect(func(): fit_menu_canvas(parent, canvas))
	fit_menu_canvas(parent, canvas)
	return canvas

static func fit_menu_canvas(parent: Control, canvas: Control) -> void:
	var viewport_size := parent.get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var scale_value := minf(viewport_size.x / MENU_DESIGN_SIZE.x, viewport_size.y / MENU_DESIGN_SIZE.y)
	canvas.scale = Vector2.ONE * scale_value
	canvas.position = (viewport_size - MENU_DESIGN_SIZE * scale_value) * 0.5

static func add_menu_background(parent: Control, image_position: Vector2) -> TextureRect:
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.position = Vector2.ZERO
	black.size = MENU_DESIGN_SIZE
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(black)

	var planet := TextureRect.new()
	planet.texture = MENU_PLANET
	planet.position = image_position
	planet.size = Vector2(2061.0, 921.0)
	planet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	planet.stretch_mode = TextureRect.STRETCH_SCALE
	planet.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(planet)

	return planet

static func add_menu_label(parent: Control, value: String, position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.position = position_value
	label.size = size_value
	label.add_theme_font_override("font", MENU_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

static func make_menu_option(parent: Control, value: String, position_value: Vector2, size_value: Vector2,
		font_size: int, text_offset: Vector2, action: Callable, header: bool = false) -> Dictionary:
	var row := Control.new()
	row.position = position_value
	row.size = size_value
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)

	var highlight := Panel.new()
	highlight.position = Vector2.ZERO
	highlight.size = size_value
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	outline.border_color = Color(1.0, 1.0, 1.0, 0.72)
	outline.set_border_width_all(2)
	outline.set_corner_radius_all(6)
	outline.set_content_margin_all(0.0)
	highlight.add_theme_stylebox_override("panel", outline)
	highlight.modulate.a = 0.0
	row.add_child(highlight)

	var button := Button.new()
	button.text = value
	button.position = text_offset
	button.size = Vector2(maxf(0.0, size_value.x - text_offset.x), size_value.y)
	style_menu_button(button, font_size)
	row.add_child(button)
	button.pressed.connect(action)

	return {"row": row, "highlight": highlight, "button": button,
		"header": header, "tween": null, "selected": false}

static func animate_menu_option(option: Dictionary, selected: bool, instant: bool = false) -> void:
	option["selected"] = selected
	var highlight: Panel = option["highlight"]
	var previous: Variant = option.get("tween")
	if previous is Tween and previous.is_running():
		previous.kill()
	if instant:
		highlight.position.x = 0.0
		highlight.modulate.a = 1.0 if selected else 0.0
		return
	var tween := highlight.create_tween().set_parallel(true)
	option["tween"] = tween
	if selected:
		highlight.position.x = -8.0
		highlight.modulate.a = 0.0
		tween.tween_property(highlight, "position:x", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(highlight, "modulate:a", 1.0, 0.18)
	else:
		tween.tween_property(highlight, "modulate:a", 0.0, 0.12)

static func style_menu_button(button: Button, font_size: int) -> void:
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", MENU_FONT)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())

static func label(text_value: String, size: int = 18) -> Label:
	var node := Label.new()
	node.text = text_value
	node.add_theme_font_size_override("font_size", maxi(18, size))
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

static func add_si_mark(portrait: TextureRect, font_size: int) -> Label:
	var mark := Label.new()
	mark.name = "SIMark"
	mark.text = "S.I."
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_theme_font_override("font", MENU_FONT)
	mark.add_theme_font_size_override("font_size", font_size)
	mark.add_theme_color_override("font_color", Color(1.0, 0.97, 0.92, 0.85))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.06, 0.65)
	style.set_corner_radius_all(4)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	mark.add_theme_stylebox_override("normal", style)
	portrait.add_child(mark)
	var place_mark := func():
		if portrait.texture == null:
			return
		var texture_size := portrait.texture.get_size()
		var image_scale := minf(portrait.size.x / texture_size.x, portrait.size.y / texture_size.y)
		var image_size := texture_size * image_scale
		mark.size = mark.get_combined_minimum_size()
		# Anchor to the fitted image, including letterboxing in the robot column.
		mark.position = (portrait.size + image_size) * 0.5 - mark.size - Vector2(3, 3)
	portrait.resized.connect(place_mark)
	place_mark.call()
	return mark

static func button(text_value: String, action: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text_value
	node.custom_minimum_size = Vector2(96, 44)
	if primary:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("246b61")
		style.set_corner_radius_all(8)
		style.set_content_margin_all(12)
		node.add_theme_stylebox_override("normal", style)
	node.pressed.connect(action)
	return node

static func translated(key: StringName, params: Dictionary = {}) -> String:
	return Engine.get_main_loop().root.get_node("LocalizationDB").translate_key(key, params)

static func resource_text(values: Dictionary) -> String:
	if values.is_empty():
		return translated(&"ui.none")
	var parts: Array[String] = []
	for id in values:
		var key := StringName("resource.%s" % id)
		if id in ["stored_energy", "research"]:
			key = StringName("ui.%s" % id)
		parts.append("%s %s" % [String.num(float(values[id]), 1).trim_suffix(".0"), translated(key)])
	return " · ".join(parts)

static func entity_name(id: String) -> String:
	var parts := id.rsplit("_", true, 1)
	if parts.size() == 2 and parts[1].is_valid_int():
		if parts[0] in ["crew", "rocket"]:
			return translated(StringName("ui.%s_name" % parts[0]), {"number": parts[1]})
		return "%s %s" % [translated(StringName("building.%s" % parts[0])), parts[1]]
	return id

static func technology_name(id: String) -> String:
	if id.is_empty():
		return translated(&"ui.none")
	if ConfigDB.balance.get("buildings", {}).has(id):
		return translated(StringName("building.%s" % id))
	return translated(StringName("technology.%s" % id))

static func row(parent: Node) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", 8)
	parent.add_child(node)
	return node

static func column(parent: Node) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", 8)
	parent.add_child(node)
	return node

static func clear(parent: Node) -> void:
	for child in parent.get_children():
		_disconnect_observers(child)
		parent.remove_child(child)
		child.queue_free()

static func _disconnect_observers(node: Node) -> void:
	# Removed pages live until frame end. They must not receive language/state
	# changes in that interval, when get_tree() is already unavailable.
	for connection in node.get_incoming_connections():
		var source: Signal = connection["signal"]
		if source.get_object() in [SignalBus, SettingsService]:
			source.disconnect(connection["callable"])
	for child in node.get_children():
		_disconnect_observers(child)

static func mission_game_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 15
	for type in ["Button", "OptionButton", "LineEdit", "Label", "PopupMenu"]:
		result.set_font_size("font_size", type, 15)
	result.set_constant("scrollbar_width", "VScrollBar", 10)
	result.set_color("font_color", "Label", Color("dce7e9"))
	result.set_color("font_color", "Button", Color("e7f1f2"))
	result.set_color("font_hover_color", "Button", Color("ffffff"))
	result.set_color("font_disabled_color", "Button", Color("9c9aa0"))
	result.set_color("font_pressed_color", "Button", Color("ffffff"))
	result.set_color("font_focus_color", "Button", Color("ffffff"))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("101d26")
	panel.border_color = Color("39505a")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(5)
	panel.set_content_margin_all(9)
	result.set_stylebox("panel", "PanelContainer", panel)
	var button := StyleBoxFlat.new()
	button.bg_color = Color("293e49")
	button.border_color = Color("49616b")
	button.set_border_width_all(1)
	button.set_corner_radius_all(4)
	button.set_content_margin_all(8)
	button.content_margin_top = 5
	button.content_margin_bottom = 5
	result.set_stylebox("normal", "Button", button)
	var hover := button.duplicate() as StyleBoxFlat
	hover.bg_color = Color("365968")
	hover.border_color = Color("66a5a6")
	result.set_stylebox("hover", "Button", hover)
	var pressed := button.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("247879")
	pressed.border_color = Color("80c6be")
	result.set_stylebox("pressed", "Button", pressed)
	result.set_stylebox("hover_pressed", "Button", pressed.duplicate())
	var disabled := button.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("26333b")
	disabled.border_color = Color("34434a")
	result.set_stylebox("disabled", "Button", disabled)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color("ffe3a1")
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(8)
	for type in ["Button", "OptionButton", "LineEdit"]:
		result.set_stylebox("focus", type, focus)
		if type != "Button":
			var input_style := panel.duplicate() as StyleBoxFlat
			input_style.content_margin_top = 12
			input_style.content_margin_bottom = 12
			result.set_stylebox("normal", type, input_style)
			result.set_stylebox("hover", type, hover.duplicate())
	return result

static func mission_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 18
	for type in ["Button", "OptionButton", "LineEdit", "Label", "PopupMenu"]:
		result.set_font_size("font_size", type, 18)
	result.set_constant("scrollbar_width", "VScrollBar", 16)
	result.set_color("font_color", "Label", Color("f4efe5"))
	result.set_color("font_color", "Button", Color("fff7e9"))
	result.set_color("font_hover_color", "Button", Color("ffffff"))
	result.set_color("font_disabled_color", "Button", Color("9c9aa0"))
	result.set_color("font_pressed_color", "Button", Color("17202b"))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.045, 0.085, 0.14, 0.98)
	panel.border_color = Color("47627a")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(14)
	result.set_stylebox("panel", "PanelContainer", panel)
	var button := StyleBoxFlat.new()
	button.bg_color = Color("8a4b45")
	button.set_corner_radius_all(6)
	button.set_content_margin_all(12)
	button.content_margin_top = 8
	button.content_margin_bottom = 8
	result.set_stylebox("normal", "Button", button)
	var hover := button.duplicate() as StyleBoxFlat
	hover.bg_color = Color("995047")
	result.set_stylebox("hover", "Button", hover)
	var pressed := button.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("d68462")
	result.set_stylebox("pressed", "Button", pressed)
	var disabled := button.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("514d53")
	result.set_stylebox("disabled", "Button", disabled)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color("ffe3a1")
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(8)
	for type in ["Button", "OptionButton", "LineEdit"]:
		result.set_stylebox("focus", type, focus)
		if type != "Button":
			var input_style := panel.duplicate() as StyleBoxFlat
			input_style.content_margin_top = 12
			input_style.content_margin_bottom = 12
			result.set_stylebox("normal", type, input_style)
			result.set_stylebox("hover", type, hover.duplicate())
	return result
