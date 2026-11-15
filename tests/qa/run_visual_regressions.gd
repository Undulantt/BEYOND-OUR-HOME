extends Node

var main: MissionMain
var checks := 0
var failures: Array[String] = []
var captures: Array[Dictionary] = []

func _ready() -> void:
	main = preload("res://scenes/integration/main.tscn").instantiate()
	add_child(main)
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL ", message)

func capture(name: String) -> void:
	for frame in 4:
		await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var file := "user://%s.png" % name
	get_viewport().get_texture().get_image().save_png(file)
	captures.append({"name": name, "path": ProjectSettings.globalize_path(file)})

func simulate(seconds: float) -> void:
	GameClock.set_paused(false)
	main.session.update(seconds)
	GameClock.set_paused(true)

func solar_output() -> float:
	for source in main.building.get_power_inputs()["generators"]:
		if source["building_id"] == "solar_panel_5":
			return float(source["output"])
	return 0.0

func run() -> void:
	get_window().size = Vector2i(1920, 1080)
	main._start_new([&"medic", &"medic", &"medic", &"medic"])
	main.building.place(GameContracts.PlacementRequest.new(&"tunnel", Vector2i(15, 17)))
	main.building.place(GameContracts.PlacementRequest.new(&"laboratory", Vector2i(15, 18)))
	main.power.step(0.0)
	check(main.research.start_research(&"solar_panel").ok, "start solar research")
	check(main.crew.queue_research(&"crew_1", &"laboratory_4", 8.0).ok, "assign first researcher")
	check(main.crew.queue_research(&"crew_2", &"laboratory_4", 8.0).ok, "assign second researcher")
	main.hud._workspace.open_tab(&"laboratory")
	simulate(10.0)
	check(is_equal_approx(main.research.get_snapshot()["progress"], 3.6), "two partial tasks credit exactly 3.6 hours")
	check(is_equal_approx(main.hud._workspace._research_bar.value, 3.6), "bar displays partial work before either task finishes")
	await capture("research-30-percent")
	var hours: SpinBox = main.hud._workspace._body.find_children("*", "SpinBox", true, false)[0]
	hours.get_line_edit().grab_focus()
	var editor := hours.get_line_edit()
	simulate(5.0)
	check(is_instance_valid(editor) and editor.is_inside_tree(), "progress never destroys a focused editor")
	check(is_equal_approx(main.hud._workspace._research_bar.value, 5.4), "progress updates even while a field has focus")
	await capture("research-45-percent")
	var saved := SaveService.export_state()
	check(SaveService.save_to_slot(&"qa_partial") == OK, "partial progress can be saved")
	simulate(1.0)
	check(SaveService.load_from_slot(&"qa_partial") == OK, "partial progress can be restored")
	main.power.step(0.0)
	check(is_equal_approx(main.research.get_snapshot()["progress"], 5.4), "load restores the exact progress watermark")
	simulate(10.0)
	check(is_equal_approx(main.research.get_snapshot()["progress"], 9.0), "restoring does not duplicate or lose partial work")
	await capture("research-75-percent-after-load")
	var task_id := StringName(GameState.data["crew"]["members"]["crew_1"]["task_id"])
	check(main.crew.cancel_task(task_id).ok, "partial task can be cancelled")
	var credited := float(main.research.get_snapshot()["progress"])
	check(is_equal_approx(credited, 9.0), "cancelling retains work already performed")
	check(SaveService.import_state(saved) == OK, "restore both researchers")
	main.power.step(0.0)
	simulate(30.0)
	check(main.research.get_snapshot()["unlocked"].has("solar_panel"), "technology unlocks once")
	check(main.research.get_snapshot()["unlocked"].count("solar_panel") == 1, "unlock is not duplicated")
	await capture("research-completed")
	check(main.building.place(GameContracts.PlacementRequest.new(&"solar_panel", Vector2i(10, 18))).ok, "place a real unlocked panel")
	main.hud.close_panel()
	GameState.data["clock"]["elapsed"] = 15.0
	main.power.step(0.0)
	main.world._sync_daylight()
	main.hud._time.refresh()
	var day := float(main.world.get_node("Sun").light_energy)
	var day_output := solar_output()
	check(GameClock.get_cycle_snapshot()["day"], "day indicator follows the simulation clock")
	await capture("day-1920")
	GameState.data["clock"]["elapsed"] = 45.0
	main.power.step(0.0)
	main.world._sync_daylight()
	main.hud._time.refresh()
	check(not GameClock.get_cycle_snapshot()["day"], "night indicator follows the simulation clock")
	check(float(main.world.get_node("Sun").light_energy) < day * 0.5, "night lighting is visibly distinct")
	check(solar_output() < day_output * 0.1, "night appearance matches actual solar production")
	var night := SaveService.export_state()
	check(SaveService.import_state(night) == OK, "night state loads")
	main.power.step(0.0)
	main.world._sync_daylight()
	check(not GameClock.get_cycle_snapshot()["day"], "load does not reset the night cycle")
	await capture("night-1920")
	get_window().size = Vector2i(1280, 720)
	await capture("night-1280")
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "captures": captures, "day_solar_output": day_output, "night_solar_output": solar_output()}
	var result_file := FileAccess.open("user://qa-visual-result.json", FileAccess.WRITE)
	result_file.store_string(JSON.stringify(result, "\t"))
	result_file.close()
	print("QA visual result: ", result)
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(4.0).timeout
	get_tree().quit(0 if failures.is_empty() else 1)
