extends Node

var main: MissionMain
var failures: Array[String] = []
var captures: Array[Dictionary] = []
var metrics: Array[Dictionary] = []
var phase := "after"
var resolutions := [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(3440, 1440)]

func _ready() -> void:
	main = preload("res://scenes/integration/main.tscn").instantiate()
	add_child(main)
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func find_button(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if node.text == text and not node.is_queued_for_deletion():
			return node
	return null

func settle() -> void:
	for frame in 4:
		await get_tree().process_frame

func key_press(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	get_viewport().push_input(event, true)
	await settle()
	event.pressed = false
	get_viewport().push_input(event, true)
	await settle()

func capture(screen: String) -> void:
	await settle()
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var pixels := get_viewport().get_texture().get_image()
	var path := "user://%s-%s-%dx%d.png" % [phase, screen, pixels.get_width(), pixels.get_height()]
	pixels.save_png(path)
	captures.append({"screen": screen, "size": [pixels.get_width(), pixels.get_height()], "path": ProjectSettings.globalize_path(path)})

func horizontal_bounds(root: Node, frame: Rect2, screen: String) -> void:
	for node in root.get_children():
		if node is Control and node.is_visible_in_tree() and not node.is_queued_for_deletion():
			var rect: Rect2 = node.get_global_rect()
			if node is BaseButton or node is Label or node is SpinBox or node is HSlider:
				check(rect.position.x >= frame.position.x - 2 and rect.end.x <= frame.end.x + 2, "%s: horizontal overflow in %s (%s)" % [screen, node.get_class(), node.text if node is Label or node is BaseButton else node.name])
				if node is Button:
					check(rect.size.y >= 43.5, "%s: button below 44 logical pixels: %s" % [screen, node.text])
			horizontal_bounds(node, frame, screen)

func check_hud(screen: String) -> void:
	var hud := main.hud
	var rect := hud.get_global_rect()
	check(hud._menu_button.get_global_rect().end.y <= rect.end.y + 1, screen + ": footer must fit")
	check(not hud._guide.visible or hud._guide.get_global_rect().end.y <= rect.end.y + 1, screen + ": guide must fit")
	check(hud._map_space.size.x >= rect.size.x * 0.5, screen + ": at least half of width belongs to the map")
	if bool(GameClock.get_snapshot().get("paused", false)):
		check(hud._time._pause.text == UiHelpers.translated(&"ui.resume"), screen + ": pause label must reflect actual clock state")
	horizontal_bounds(hud, rect, screen)
	metrics.append({"screen": screen, "window": [get_window().size.x, get_window().size.y], "logical": [rect.size.x, rect.size.y], "scale": get_window().content_scale_factor, "map_width_percent": 100 * hud._map_space.size.x / rect.size.x})

func menu_pages() -> void:
	main._show_menu()
	main.menu._refresh()
	await capture("menu")
	horizontal_bounds(main.menu, main.menu.get_global_rect(), "menu")
	main.menu._show_settings()
	await capture("settings")
	horizontal_bounds(main.menu, main.menu.get_global_rect(), "settings")
	main.menu._show_select()
	var chooser: AstronautSelect = main.menu._stack.get_child(0)
	for index in 4:
		chooser.add_profile(&"medic")
	await capture("crew-select")
	check(chooser.selected.size() == 4, "repeated profiles still selectable")
	horizontal_bounds(main.menu, main.menu.get_global_rect(), "crew-select")
	main.menu._refresh()

func _run() -> void:
	for resolution in resolutions:
		get_window().size = resolution
		await settle()
		if get_window().size != resolution:
			get_window().size = resolution
			await settle()
		check(get_window().size == resolution, "requested window resolution must be applied: %s" % resolution)
		SettingsService.apply_settings({"language": "es", "ui_scale": 1.0})
		await menu_pages()
		main._start_new([&"medic", &"medic", &"medic", &"medic"])
		main.session.update(0.1)
		GameClock.set_paused(true)
		check(main.dialogue.get_top_notice().get("id") == "tutorial_laboratory", "first guidance points to the first useful building")
		for tab in main.hud._workspace.TABS:
			main.hud._workspace.open_tab(tab)
			await capture("hud-" + String(tab))
			check_hud("hud-" + String(tab))
			check(main.hud._workspace._tab_picker.get_selected_metadata() == tab, "active tool is clearly selected")
		main.events.trigger_event(&"tunnel_breach")
		main.life_support.step(0.0)
		main.hud._vitals.refresh()
		main.world.focus_target(&"tunnel_1")
		await capture("repair")
		check(main.hud._active_panel == &"inspector" and not main.hud._workspace.visible, "inspector replaces workspace")
		check_hud("repair")
		if resolution == Vector2i(1920, 1080):
			main.hud._inspector._confirm_remove()
			await settle()
			var dialogs := main.hud._inspector.find_children("*", "ConfirmationDialog", true, false)
			check(dialogs.size() == 1 and dialogs[0].visible, "building removal asks for confirmation")
			if not dialogs.is_empty():
				dialogs[0].canceled.emit()
			await settle()
			check(main.building.get_status(&"tunnel_1") != null, "cancelling removal preserves the building")
			var repair := find_button(main.hud._inspector, UiHelpers.translated(&"ui.repair_selected"))
			check(repair != null, "repair action is available")
			if repair != null:
				repair.pressed.emit()
			var repair_task := StringName(GameState.data["crew"]["members"]["crew_1"]["task_id"])
			check(not String(repair_task).is_empty(), "repair button assigns a real task")
			if not String(repair_task).is_empty():
				main.crew.cancel_task(repair_task)
		var paused := bool(GameClock.get_snapshot()["paused"])
		var speed := float(GameClock.get_snapshot()["speed"])
		main.hud._toolbar_action("report")
		await capture("report")
		check_hud("report")
		main.hud._toolbar_action("log")
		await capture("history")
		check_hud("history")
		main.hud.close_panel()
		await settle()
		check(not main.hud._dock.visible and main.hud._map_space.size.x > main.hud.size.x * 0.9, "closing the dock gives the map its space back")
		check(bool(GameClock.get_snapshot()["paused"]) == paused and float(GameClock.get_snapshot()["speed"]) == speed, "navigation never changes simulation speed")
		main.hud.show_panel(&"workspace")
		await settle()
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = main.world.camera_rig.camera.unproject_position(Vector3(15.5, 0, 15.5))
		main.world.selected_id = &""
		get_viewport().push_input(click, true)
		await settle()
		check(main.world.selected_id == &"base_1", "map picking works at %s" % resolution)
		click.pressed = false
		get_viewport().push_input(click, true)
		if resolution == Vector2i(1920, 1080):
			main.hud._workspace._coordinates_open = true
			main.hud._workspace.open_tab(&"build")
			await settle()
			var input: SpinBox = main.hud._workspace._body.find_children("*", "SpinBox", true, false)[0]
			input.get_line_edit().grab_focus()
			var editor := input.get_line_edit()
			input.value = 14
			await settle()
			check(is_instance_valid(editor) and editor.is_inside_tree(), "editing a coordinate preserves its input control")
			var camera_focus := main.world.camera_rig.focus
			await key_press(KEY_LEFT)
			check(main.world.camera_rig.focus == camera_focus, "arrow keys in a field do not move the camera")
			editor.release_focus()
			await key_press(KEY_SPACE)
			check(not bool(GameClock.get_snapshot()["paused"]), "Space resumes the mission")
			await key_press(KEY_SPACE)
			check(bool(GameClock.get_snapshot()["paused"]), "Space pauses the mission")
			await key_press(KEY_ESCAPE)
			check(not main.hud._dock.visible, "Escape closes the context panel")
			main.building.place(GameContracts.PlacementRequest.new(&"tunnel", Vector2i(15, 17)))
			main.building.place(GameContracts.PlacementRequest.new(&"laboratory", Vector2i(15, 18)))
			main.power.step(0.0)
			main.hud._workspace.open_tab(&"laboratory")
			var start_research := find_button(main.hud._workspace, UiHelpers.translated(&"action.research"))
			check(start_research != null and not start_research.disabled, "research form becomes available with a powered lab")
			if start_research != null:
				start_research.pressed.emit()
			for index in 2:
				var assign := find_button(main.hud._workspace, UiHelpers.translated(&"ui.assign_worker"))
				check(assign != null and not assign.disabled, "research form offers an available worker")
				if assign != null:
					assign.pressed.emit()
			check(GameClock.advance_to_sol(2).ok, "research UI tasks run through simulation")
			check(main.research.get_snapshot()["unlocked"].has("solar_panel"), "research UI unlocks the selected technology")
		if resolution in [Vector2i(960, 540), Vector2i(1920, 1080)]:
			SettingsService.apply_settings({"ui_scale": 1.25})
			main.hud._workspace.open_tab(&"build")
			await capture("hud-large")
			check_hud("hud-large")
			SettingsService.apply_settings({"language": "en"})
			for tab in main.hud._workspace.TABS:
				main.hud._workspace.open_tab(tab)
				await capture("en-" + String(tab))
				check_hud("en-" + String(tab))
			SettingsService.apply_settings({"ui_scale": 1.0, "language": "es"})
		GameState.data["result"] = "victory"
		SignalBus.game_over.emit(&"victory")
		await capture("victory")
		horizontal_bounds(main.hud._final, main.hud.get_global_rect(), "victory")
		GameState.data["result"] = "defeat"
		SignalBus.game_over.emit(&"defeat")
		await capture("defeat")
		main.hud._final.refresh()
	var result := {"passed": failures.is_empty(), "failures": failures, "captures": captures, "metrics": metrics}
	var file := FileAccess.open("user://ui-audit-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("UI audit: ", captures.size(), " captures, ", failures.size(), " failures")
	await get_tree().create_timer(4.0).timeout
	get_tree().quit(0 if failures.is_empty() else 1)
