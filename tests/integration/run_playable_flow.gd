extends Node

var main: MissionMain
var failures: Array[String] = []
var profiles: Array[StringName] = [&"medic", &"medic", &"medic", &"medic"]

func _ready() -> void:
	main = preload("res://scenes/integration/main.tscn").instantiate()
	add_child(main)
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error(label)

func button_with_text(root: Node, text: String) -> Button:
	for child in root.get_children():
		if child is Button and child.text == text:
			return child
		var found := button_with_text(child, text)
		if found != null:
			return found
	return null

func research_round() -> void:
	main.menu.start_requested.emit(profiles)
	main.world.placement_requested.emit(GameContracts.PlacementRequest.new(&"tunnel", Vector2i(15, 17)))
	main.world.placement_requested.emit(GameContracts.PlacementRequest.new(&"laboratory", Vector2i(15, 18)))
	main.power.step(0.0)
	var lab := StringName("")
	for status in main.building.get_all_statuses():
		if status.type == &"laboratory":
			lab = status.building_id
	check(main.research.start_research(&"solar_panel").ok, "research starts")
	check(main.crew.queue_research(&"crew_1", lab, 8.0).ok, "first work assigned")
	check(main.crew.queue_research(&"crew_2", lab, 8.0).ok, "second work assigned")
	main.building.set_enabled(&"reactor_1", false)
	main.power.step(0.0)
	var task_id: String = GameState.data["crew"]["members"]["crew_1"]["task_id"]
	main.crew.scheduler.progress(&"crew_1", 8.0)
	check(float(GameState.data["crew"]["tasks"][task_id]["completed_hours"]) == 0.0, "research waits during power outage")
	main.building.set_enabled(&"reactor_1", true)
	main.power.step(0.0)
	check(GameClock.advance_to_sol(2).ok, "research sol reached")
	check(main.research.get_snapshot()["unlocked"].has("solar_panel"), "research works across new games")

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://menu.png")
	main.menu._show_select()
	for index in 4:
		var plus := button_with_text(main.menu, "+")
		check(plus != null, "profile add button present")
		if plus != null:
			plus.pressed.emit()
	var start := button_with_text(main.menu, LocalizationDB.translate_key(&"setup.select_crew.start"))
	check(start != null and not start.disabled, "four selections enable start")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://crew-selection.png")
		check(start.get_global_rect().end.y <= main.menu.get_global_rect().end.y, "crew selection start button fits viewport")
	if start != null:
		start.pressed.emit()
	check(GameState.is_running(), "mission starts through actual menu controls")
	main.menu.start_requested.emit(profiles)
	main.building.place(GameContracts.PlacementRequest.new(&"tunnel", Vector2i(15, 17)))
	var crop := main.building.place(GameContracts.PlacementRequest.new(&"greenhouse", Vector2i(15, 18)))
	check(crop.ok, "new greenhouse placed")
	main.hud._inspector.show_target(StringName(crop.params.get("building_id", "")))
	var plant := button_with_text(main.hud._inspector, LocalizationDB.translate_key(&"ui.plant_seed"))
	check(plant != null, "new greenhouse exposes planting")
	var seeds := main.ledger.get_amount(&"seeds")
	if plant != null:
		plant.pressed.emit()
	check(main.ledger.get_amount(&"seeds") == seeds - 1.0, "planting consumes one seed through UI")
	research_round()
	research_round()
	check(main.world._crew_visuals.size() == 4, "crew appears in world")
	main.world.placement_requested.emit(GameContracts.PlacementRequest.new(&"solar_panel", Vector2i(10, 18)))
	check(GameClock.advance_to_sol(8).ok, "weekly save boundary reached")
	var expected := SaveService.export_state()
	check(SaveService.load_from_slot(&"autosave") == OK, "weekly save loads")
	check(int(GameClock.get_snapshot()["sol"]) == 8, "weekly save resumes next sol")
	for resource in expected["inventory"]:
		check(is_equal_approx(main.ledger.get_amount(StringName(resource)), float(expected["inventory"][resource])), "weekly save preserves %s" % resource)
	check(GameState.data["buildings"]["instances"]["reactor_1"]["fuel_sols"] == expected["buildings"]["instances"]["reactor_1"]["fuel_sols"], "weekly save preserves fuel")
	check(main.rockets.reserve_landing_zone(&"rocket_1", Rect2i(22, 22, 8, 8)).ok, "late rocket zone reserved")
	check(main.rockets.confirm_manifest(&"rocket_1", {"chips": 1}).ok, "late rocket manifest ready")
	main.hud._workspace.open_tab(&"rocket")
	var arrival := button_with_text(main.hud._workspace, LocalizationDB.translate_key(&"ui.trigger_arrival"))
	check(arrival != null, "late arrival exposed in normal rocket tab")
	if arrival != null:
		arrival.pressed.emit()
	check(main.world._rocket_visuals["rocket_1"].visible, "landed rocket appears in world")
	main.hud._inspector.show_target(&"solar_panel_5")
	var protect := button_with_text(main.hud._inspector, LocalizationDB.translate_key(&"ui.protect_panel"))
	check(protect != null, "panel protection exposed")
	if protect != null:
		protect.pressed.emit()
	check(main.building.get_status(&"solar_panel_5").modifiers["storm_protected"], "panel protection changes real state")
	main.hud._inspector.show_target(&"tunnel_1")
	check(button_with_text(main.hud._inspector, LocalizationDB.translate_key(&"ui.repair_selected")) != null, "breach repair exposed")
	main.hud._workspace._coordinates_open = true
	main.hud._workspace.open_tab(&"build")
	var spin: SpinBox = main.hud._workspace._body.find_children("*", "SpinBox", true, false)[0]
	spin.get_line_edit().grab_focus()
	var editor := spin.get_line_edit()
	main.session.update(0.2)
	await get_tree().process_frame
	check(is_instance_valid(editor) and editor.is_inside_tree(), "simulation preserves active coordinate editor")
	GameClock.set_paused(true)
	var root_rect := main.hud.get_global_rect()
	check(main.hud._menu_button.get_global_rect().end.y <= root_rect.end.y, "menu button stays within viewport")
	check(main.hud._guide.get_global_rect().end.y <= root_rect.end.y, "guide stays within viewport")
	if DisplayServer.get_name() != "headless":
		editor.release_focus()
		await get_tree().process_frame
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = main.world.camera_rig.camera.unproject_position(Vector3(15.5, 0, 15.5))
		get_viewport().push_input(click, true)
		await get_tree().process_frame
		check(main.world.selected_id == &"base_1", "real map click reaches building selection")
		click.pressed = false
		get_viewport().push_input(click, true)
		main.world.focus_target(&"tunnel_1")
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://playable-1280.png")
		get_window().size = Vector2i(960, 540)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://playable-960.png")
	var result := {"passed": failures.is_empty(), "failures": failures}
	var file := FileAccess.open("user://playable-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	print("Playable integration: ", result)
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(4.0).timeout
	get_tree().quit(0 if failures.is_empty() else 1)
