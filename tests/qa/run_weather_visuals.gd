extends Node

var main: MissionMain
var failures: Array[String] = []
var checks := 0
var captures: Array[String] = []

func _ready() -> void:
	main = preload("res://scenes/integration/main.tscn").instantiate()
	add_child(main)
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL ", message)

func settle() -> void:
	for frame in 6:
		await get_tree().process_frame

func capture(label: String) -> void:
	# Dismiss the existing modal alert exactly as "Got it" does, to inspect the map.
	for entry in main.dialogue.get_entries():
		main.dialogue.acknowledge(StringName(entry["id"]))
	main.hud._guide.refresh()
	await settle()
	await RenderingServer.frame_post_draw
	var path := "user://weather-%s.png" % label
	get_viewport().get_texture().get_image().save_png(path)
	captures.append(path)

func run() -> void:
	check(not main.world.weather.visible, "weather hidden in initial menu")
	main._start_new([&"medic", &"engineer_a", &"botanist_a", &"scientist_a"])
	GameClock.set_paused(true)
	GameState.data["clock"]["elapsed"] = 15.0
	main.dialogue.skip_tutorial()
	main.hud.close_panel()
	await settle()
	var weather := main.world.weather
	var environment: Environment = main.world.get_node("WorldEnvironment").environment
	check(not weather.visible and environment.fog_enabled and environment.fog_density < 0.002, "clear weather has a faint ambient haze only")
	var clear_sun: float = main.world.get_node("Sun").light_energy
	check(clear_sun <= 0.2521, "daytime sun stays below the reduced lighting cap")
	await capture("clear")
	GameState.data["clock"]["sol"] = 11
	main.events.on_sol_started(11)
	await settle()
	check(weather.visible and weather.phases.get("dust_storm") == "warning", "scheduled storm warning appears on map")
	check(not weather.dust_active and environment.fog_density < 0.002, "warning does not pretend the storm is active")
	await capture("warning")
	GameState.data["clock"]["sol"] = 12
	main.events.on_sol_started(12)
	await settle()
	check(weather.dust_active and environment.fog_enabled, "scheduled storm activates wind and real 3D haze")
	check(main.world.get_node("Sun").light_energy < clear_sun, "dust reduces sunlight visually")
	check(weather.mouse_filter == Control.MOUSE_FILTER_IGNORE, "weather does not intercept map input")
	check(weather._label.text.contains("Tormenta"), "map badge names the storm in Spanish")
	check(weather._badge.size.y < 100.0, "weather badge stays compact instead of covering the colony")
	await capture("dust")
	var saved := SaveService.export_state()
	check(main.events.clear_event(&"dust_storm").ok, "storm can be cleared")
	await settle()
	check(not weather.visible and environment.fog_enabled and environment.fog_density < 0.002, "ending the storm restores the faint ambient haze")
	check(is_equal_approx(main.world.get_node("Sun").light_energy, clear_sun), "ending restores normal sunlight")
	check(SaveService.import_state(saved) == OK, "active weather save loads")
	await settle()
	check(weather.dust_active and environment.fog_enabled, "loading restores weather visuals")
	# The overlay is pure presentation even while drawing and advancing its animation.
	var before := JSON.stringify(GameState.to_dict())
	weather._process(0.5)
	await settle()
	check(JSON.stringify(GameState.to_dict()) == before, "drawing weather cannot mutate simulation state or RNG")
	check(is_zero_approx(weather._animation_time), "paused game freezes weather animation")
	GameClock.set_paused(false)
	weather._process(0.05)
	GameClock.set_paused(true)
	check(weather._animation_time > 0.0, "weather animation advances while running")
	check(JSON.stringify(GameState.to_dict()) == before, "animating weather does not consume simulation time or RNG")
	# Real map picking must still pass through the weather control.
	var input := InputEventMouseButton.new()
	input.button_index = MOUSE_BUTTON_LEFT
	input.pressed = true
	input.position = main.world.camera_rig.camera.unproject_position(Vector3(31.0, 0.0, 31.0))
	get_viewport().push_input(input, true)
	await settle()
	check(main.world.selected_id == &"base_1", "real map click selects a building through the storm")
	input.pressed = false
	get_viewport().push_input(input, true)
	main.hud.close_panel()
	main.events.on_sol_started(14)
	await settle()
	check(weather.dust_active and weather.phases.get("solar_flare") == "warning", "active dust and upcoming flare are shown separately")
	main.events.clear_event(&"dust_storm")
	check(main.events.trigger_event(&"solar_flare").ok, "solar flare starts")
	await settle()
	check(weather.flare_active and not weather.dust_active and environment.fog_density < 0.002, "flare has its own glow and arcs without storm fog")
	check(weather._label.text.contains("RADIACIÓN"), "flare is labelled independently of its color")
	await capture("flare")
	SettingsService.apply_settings({"language": "en"})
	await settle()
	check(weather._label.text.contains("Solar flare"), "weather badge follows language changes")
	SettingsService.apply_settings({"language": "es"})
	GameState.data["clock"]["elapsed"] = 45.0
	await settle()
	check(main.world.get_node("Sun").light_energy < clear_sun * 0.5, "flare preserves the night/day distinction")
	await capture("flare-night")
	main.events.clear_event(&"solar_flare")
	await settle()
	check(not weather.visible, "ending flare removes its effect")
	# Random event IDs and simultaneous saved phases are resolved by event type.
	GameState.data["events"]["items"]["random_23"] = {"id": "random_23", "type": "dust_storm", "phase": "active", "end_sol": 24}
	SignalBus.state_restored.emit()
	await settle()
	check(weather.dust_active, "random event alias restores storm appearance")
	main._show_menu()
	check(not weather.visible, "returning to menu hides weather even when world processing stops")
	main._show_game()
	await settle()
	check(weather.visible, "returning to world restores active weather")
	for resolution in [Vector2i(960, 540), Vector2i(1920, 1080), Vector2i(3440, 1440)]:
		get_window().size = resolution
		await settle()
		var viewport_size := get_viewport().get_visible_rect().size
		var map_rect := main.world.camera_rig.map_view
		check(weather.get_rect().is_equal_approx(Rect2(map_rect.position * viewport_size, map_rect.size * viewport_size)), "weather tracks map area at " + str(resolution))
		check(weather.clip_contents, "particles stay clipped to map at " + str(resolution))
	main.events.set_event_enabled(&"random_events", false)
	main.events.on_sol_started(24)
	await settle()
	check(not weather.dust_active and environment.fog_density < 0.002, "natural expiration removes storm fog and restores ambient haze")
	GameState.data["events"]["items"].clear()
	SignalBus.state_restored.emit()
	await settle()
	check(not weather.visible and environment.fog_enabled and environment.fog_density < 0.002, "empty restored state clears storm weather")
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "captures": captures}
	var output := FileAccess.open("user://weather-result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	print("WEATHER QA: ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
