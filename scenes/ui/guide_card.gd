class_name GuideCard
extends PanelContainer

signal focus_requested(target_id: StringName)
signal layout_requested()

const ROBOT_TEXTURE: Texture2D = preload("res://assets/robot/Designer (7).png")

var dialogue: DialogueService
var _content: HBoxContainer
var tutorial_mode := false

func _ready() -> void:
	theme = UiHelpers.mission_game_theme()
	_content = HBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_content)
	_content.minimum_size_changed.connect(func(): call_deferred("_request_layout"))
	SignalBus.guide_dialogue_changed.connect(func(_id, _state): refresh())
	SignalBus.log_entry_added.connect(func(_entry): refresh())
	SignalBus.language_changed.connect(func(_code): refresh())
	SignalBus.state_restored.connect(refresh)
	refresh()

func configure(service: DialogueService) -> void:
	dialogue = service
	refresh()

func refresh() -> void:
	if not is_instance_valid(_content):
		return
	UiHelpers.clear(_content)
	visible = false
	if dialogue == null:
		return
	var entry: Dictionary = dialogue.get_display_notice()
	if entry.is_empty():
		return
	# Critical entries remain active until the hazard is resolved, but "Got it"
	# should dismiss their popup. Keep the warning in the simulation and history.
	if entry.get("acknowledged", false):
		return
	if entry.get("kind") == "tutorial" and GameState.data.get("tutorial", {}).get("skipped", false):
		return
	visible = true
	var critical: bool = entry.get("kind") == "critical"
	tutorial_mode = entry.get("kind") == "tutorial"
	var step := dialogue.get_tutorial_step() if tutorial_mode else {}
	_apply_card_style(critical)

	var portrait := TextureRect.new()
	portrait.texture = ROBOT_TEXTURE
	portrait.custom_minimum_size = Vector2(56.0, 56.0) if tutorial_mode else Vector2(76.0, 72.0)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.visible = not tutorial_mode
	_content.add_child(portrait)
	UiHelpers.add_si_mark(portrait, 10)

	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 5)
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(text_column)

	var heading := _tr(&"ui.alert_title" if critical else &"ui.guide_title")
	if not step.is_empty():
		heading = "%s · %s" % [_tr(&"onboarding.goal", {"step": step["index"], "total": step["total"]}), _tr(StringName(step["title_key"]))]
	var title := UiHelpers.label(heading, 17)
	title.max_lines_visible = 2
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.modulate = Color("ffd29a") if critical else Color("a3dfd2")
	text_column.add_child(title)

	var message_scroll := ScrollContainer.new()
	message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	message_scroll.custom_minimum_size.y = 75.0
	message_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_column.add_child(message_scroll)
	var message := UiHelpers.label(_tr(StringName(entry["message_key"]), entry.get("params", {})), 15)
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	message_scroll.add_child(message)

	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 6)
	buttons.alignment = FlowContainer.ALIGNMENT_CENTER
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_child(buttons)
	if not String(entry.get("focus_target", "")).is_empty():
		buttons.add_child(UiHelpers.button(_tr(&"onboarding.focus" if tutorial_mode else &"ui.focus"), _focus_notice.bind(entry, step), true))
	var confirm_key := &"ui.acknowledge"
	if not step.is_empty():
		confirm_key = &"onboarding.learn" if step["condition"] == "begin" else &"onboarding.next" if step["condition"] == "ack" else &"onboarding.act"
		if step["id"] == "finish":
			confirm_key = &"onboarding.finish"
	buttons.add_child(UiHelpers.button(_tr(confirm_key), func(): _acknowledge(StringName(entry["id"]))))
	if entry.get("kind") == "tutorial":
		buttons.add_child(UiHelpers.button(_tr(&"dialogue.skip_tutorial"), func(): dialogue.skip_tutorial(); refresh()))
	call_deferred("_request_layout")

func _request_layout() -> void:
	if is_inside_tree():
		layout_requested.emit()

func _focus_notice(entry: Dictionary, step: Dictionary) -> void:
	var dismiss: bool = entry.get("kind") == "critical" or (not step.is_empty() and step["condition"] not in ["ack", "begin"])
	if dismiss:
		dialogue.acknowledge(StringName(entry["id"]))
	focus_requested.emit(StringName(entry["focus_target"]))
	if dismiss:
		refresh()

func _acknowledge(id: StringName) -> void:
	var result := dialogue.acknowledge(id)
	if result.ok:
		visible = false
	refresh()

func _apply_card_style(critical: bool) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.035, 0.05, 0.07, 0.94)
	panel.border_color = Color("d79a5b") if critical else Color("73c7b7")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(7)
	panel.content_margin_left = 9.0
	panel.content_margin_right = 9.0
	panel.content_margin_top = 8.0
	panel.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", panel)

func _tr(key: StringName, params: Dictionary = {}) -> String:
	return get_tree().root.get_node("LocalizationDB").translate_key(key, params)
