class_name MissionHud
extends Control

signal save_requested()
signal menu_requested()
signal pause_requested()
signal settings_requested()

var services: Dictionary = {}
var world: Node
var _vitals: VitalStatusBar
var _workspace: MissionWorkspace
var _inspector: BuildingInspector
var _guide: GuideCard
var _log: ActivityLog
var _report: SolReportView
var _admin: AdminPanel
var _final: FinalResultView
var _save_button: Button
var _pause_button: Button
var _map_space: Control
var _dock: VBoxContainer
var _dock_title: Label
var _back: Button
var _views: Dictionary = {}
var _toolbar: Dictionary = {}
var _active_panel: StringName = &"workspace"
var _time: TimeControls
var _tutorial_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiHelpers.mission_game_theme()
	mouse_filter = Control.MOUSE_FILTER_PASS
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 6)
	var column := UiHelpers.column(margin)
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	var status := PanelContainer.new()
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = Color("101b27")
	status_style.border_color = Color("354c5c")
	status_style.set_border_width_all(1)
	status_style.set_corner_radius_all(6)
	status_style.content_margin_left = 8.0
	status_style.content_margin_right = 8.0
	status_style.content_margin_top = 6.0
	status_style.content_margin_bottom = 6.0
	status.add_theme_stylebox_override("panel", status_style)
	column.add_child(status)
	var status_column := UiHelpers.column(status)
	_vitals = VitalStatusBar.new()
	status_column.add_child(_vitals)
	_time = TimeControls.new()
	_time.settings_requested.connect(func(): settings_requested.emit())
	status_column.add_child(_time)
	status_column.add_theme_constant_override("separation", 5)
	var center := UiHelpers.row(column)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_space = Control.new()
	_map_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(_map_space)
	_dock = UiHelpers.column(center)
	var navigation := UiHelpers.row(_dock)
	_back = UiHelpers.button("", func(): show_panel(&"workspace"))
	navigation.add_child(_back)
	_dock_title = UiHelpers.label("", 18)
	navigation.add_child(_dock_title)
	var close := UiHelpers.button("×", close_panel)
	close.custom_minimum_size.x = 44
	close.tooltip_text = UiHelpers.translated(&"ui.close_panel")
	navigation.add_child(close)
	_workspace = MissionWorkspace.new()
	_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dock.add_child(_workspace)
	_workspace._tab_picker.reparent(navigation)
	navigation.move_child(_workspace._tab_picker, 0)
	_workspace._tab_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_views["workspace"] = _workspace
	_inspector = BuildingInspector.new()
	_mount_view("inspector", _inspector)
	_report = SolReportView.new()
	_mount_view("report", _report)
	_log = ActivityLog.new()
	_mount_view("log", _log)
	_admin = AdminPanel.new()
	_mount_view("admin", _admin)
	_guide = GuideCard.new()
	_guide.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	add_child(_guide)
	_guide.layout_requested.connect(_layout_guide)
	var footer := HFlowContainer.new()
	footer.add_theme_constant_override("h_separation", 8)
	footer.add_theme_constant_override("v_separation", 6)
	column.add_child(footer)
	for id in ["tools", "report", "log", "help", "demo"]:
		var item := UiHelpers.button("", func(): _toolbar_action(id))
		_toolbar[id] = item
		_compact_footer_button(item)
		footer.add_child(item)
	_save_button = UiHelpers.button("", func(): save_requested.emit())
	_pause_button = UiHelpers.button("", func(): pause_requested.emit())
	_compact_footer_button(_save_button)
	_compact_footer_button(_pause_button)
	footer.add_child(_save_button)
	_tutorial_button = UiHelpers.button("", func():
		if services.has("dialogue"):
			services["dialogue"].recall_tutorial())
	_compact_footer_button(_tutorial_button)
	footer.add_child(_tutorial_button)
	footer.add_child(_pause_button)
	_final = FinalResultView.new()
	add_child(_final)
	_final.menu_requested.connect(func(): menu_requested.emit())
	add_child(AudioController.new())
	SignalBus.language_changed.connect(_refresh_buttons)
	SignalBus.state_restored.connect(rebuild_from_state)
	SignalBus.game_over.connect(func(_result): rebuild_from_state())
	SignalBus.guide_dialogue_changed.connect(func(_id, _state): _refresh_tutorial_button())
	_workspace.tab_opened.connect(func(_id): show_panel(&"workspace"))
	_guide.focus_requested.connect(focus_target)
	resized.connect(_layout)
	_map_space.resized.connect(func(): call_deferred("_update_camera"); call_deferred("_layout_guide"))
	_refresh_buttons()
	close_panel()
	configure(services, world)
	_layout()

func _compact_footer_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(0.0, 32.0)
	button.add_theme_font_size_override("font_size", 14)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBox
		style.content_margin_left = 7.0
		style.content_margin_right = 7.0
		style.content_margin_top = 3.0
		style.content_margin_bottom = 3.0
		button.add_theme_stylebox_override(state, style)

func _mount_view(id: String, view: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dock.add_child(scroll)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(view)
	_views[id] = scroll

func show_panel(id: StringName) -> void:
	if not _views.has(String(id)):
		return
	_active_panel = id
	_dock.show()
	for key in _views:
		_views[key].visible = key == String(id)
	_back.visible = id != &"workspace"
	_dock_title.visible = id != &"workspace"
	_workspace._tab_picker.visible = id == &"workspace"
	_dock_title.text = UiHelpers.translated(StringName("ui.panel.%s" % id))
	call_deferred("_update_camera")

func close_panel() -> void:
	_dock.hide()
	if world != null:
		world.cancel_placement()
	call_deferred("_update_camera")

func _toolbar_action(id: String) -> void:
	match id:
		"tools": show_panel(&"workspace")
		"report":
			_report.show_sol(maxi(1, int(GameClock.get_snapshot().get("sol", 1)) - 1))
			show_panel(&"report")
		"log": show_panel(&"log")
		"demo": show_panel(&"admin")
		"help":
			show_panel(&"workspace")
			_workspace.open_tab(&"codex")

func _layout() -> void:
	if _dock == null:
		return
	_dock.custom_minimum_size.x = clampf(size.x * 0.22, 260.0, 320.0)
	_layout_guide()
	call_deferred("_update_camera")

func _layout_guide() -> void:
	if not is_instance_valid(_guide) or size.x <= 0.0 or size.y <= 0.0:
		return
	var width := minf(size.x - 24.0, clampf(size.x * 0.38, 360.0, 500.0))
	var height := minf(size.y - 24.0, 210.0)
	if _guide.tutorial_mode and is_instance_valid(_map_space):
		var area := _map_space.get_global_rect()
		width = minf(maxf(0.0, area.size.x - 16.0), clampf(area.size.x * 0.56, 420.0, 560.0))
		height = minf(maxf(0.0, area.size.y - 16.0), 205.0)
		_guide.size = Vector2(width, height)
		_guide.position = Vector2(area.position.x + (area.size.x - width) * 0.5, area.end.y - height - 8.0)
		return
	_guide.size = Vector2(width, height)
	_guide.position = (size - _guide.size) * 0.5

func _update_camera() -> void:
	if world != null and is_instance_valid(_map_space) and size.x > 0.0 and size.y > 0.0:
		var rect := _map_space.get_global_rect()
		world.camera_rig.set_map_view(Rect2(rect.position / size, rect.size / size))

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is OptionButton:
		return
	if event.keycode == KEY_ESCAPE:
		close_panel()
	elif event.keycode == KEY_SPACE:
		_time._toggle_pause()
	else:
		return
	get_viewport().set_input_as_handled()

func configure(dependencies: Dictionary, world_node: Node = null) -> void:
	services = dependencies
	world = world_node
	if _vitals == null:
		return
	_vitals.configure(dependencies)
	_workspace.configure(dependencies)
	_workspace.set_world(world)
	_inspector.configure(dependencies)
	_admin.configure(dependencies)
	if dependencies.has("dialogue"):
		_log.configure(dependencies["dialogue"])
		_guide.configure(dependencies["dialogue"])
	if dependencies.has("report"):
		_report.configure(dependencies["report"])
	if world != null and not world.target_selected.is_connected(_on_target_selected):
		world.target_selected.connect(_on_target_selected)
	if world != null and not world.placement_requested.is_connected(_workspace.apply_placement):
		world.placement_requested.connect(_workspace.apply_placement)
	rebuild_from_state()
	call_deferred("_update_camera")

func _on_target_selected(id: StringName) -> void:
	_inspector.show_target(id)
	if _inspector.visible:
		show_panel(&"inspector")

func focus_target(id: StringName) -> void:
	if String(id).begins_with("ui:tutorial_") and services.has("dialogue"):
		var kind := StringName(String(id).trim_prefix("ui:tutorial_"))
		var cell: Vector2i = services["dialogue"].tutorial_build_site(kind)
		_workspace._build_type = kind
		_workspace._build_cell = cell
		_workspace._coordinates_open = true
		_workspace.open_tab(&"build")
		if world != null:
			world.camera_rig.focus_cell(cell)
			world.begin_placement(kind)
			var definition := BuildingDefinition.from_balance(kind)
			world.preview.show_at(cell, definition.footprint, services["building"].validate_placement(GameContracts.PlacementRequest.new(kind, cell)).ok)
	elif String(id).begins_with("ui:workspace_"):
		var tab := StringName(String(id).trim_prefix("ui:workspace_"))
		if tab == &"laboratory" and services.has("dialogue"):
			var step: Dictionary = services["dialogue"].get_tutorial_step()
			var condition := String(step.get("condition", ""))
			if condition.get_slice(":", 0) in ["research", "workers", "unlocked"]:
				_workspace._research_choice = condition.get_slice(":", 1)
		_workspace.open_tab(tab)
	elif id == &"ui:time_controls":
		_time._pause.grab_focus()
	elif id == &"world:scan_sector":
		_workspace.open_tab(&"laboratory")
	elif world != null:
		world.focus_target(id)

func rebuild_from_state() -> void:
	if _vitals == null:
		return
	_vitals.refresh()
	_workspace.refresh()
	_inspector.refresh()
	_log.refresh()
	_guide.refresh()
	_report.refresh()
	_final.refresh()
	_time.refresh()
	_refresh_tutorial_button()

func _refresh_tutorial_button() -> void:
	if not is_instance_valid(_tutorial_button):
		return
	var step: Dictionary = services["dialogue"].get_tutorial_step() if services.has("dialogue") else {}
	var skipped: bool = GameState.data.get("tutorial", {}).get("skipped", false)
	_tutorial_button.visible = not step.is_empty() or skipped
	_tutorial_button.text = UiHelpers.translated(&"onboarding.reactivate") if skipped else UiHelpers.translated(&"onboarding.goal", {"step": step.get("index", 1), "total": step.get("total", 19)})
	_tutorial_button.tooltip_text = UiHelpers.translated(&"onboarding.recall")

func show_message(value: String) -> void:
	_workspace._feedback.text = value
	_workspace._feedback.show()
	show_panel(&"workspace")

func _refresh_buttons(_code: StringName = &"") -> void:
	if _save_button == null:
		return
	_save_button.text = UiHelpers.translated(&"ui.save_game")
	_pause_button.text = UiHelpers.translated(&"menu.pause_title")
	_pause_button.tooltip_text = UiHelpers.translated(&"ui.pause_tip")
	for id in _toolbar:
		_toolbar[id].text = UiHelpers.translated(StringName("ui.toolbar.%s" % id))
	_dock_title.text = UiHelpers.translated(StringName("ui.panel.%s" % _active_panel))
	_back.text = UiHelpers.translated(&"ui.tools_back")
	_refresh_tutorial_button()
