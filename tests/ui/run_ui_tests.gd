extends Node

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	GameState.reset(42)
	var local: Node = get_tree().root.get_node("LocalizationDB")
	var catalog: Node = get_tree().root.get_node("NasaDataCatalog")
	local.set_language(&"es")
	_assert(local.translate_key(&"tab.crew") == "Tripulación", "Spanish locale")
	_assert(local.set_language(&"en").ok, "language switch")
	_assert(local.translate_key(&"tab.crew") == "Crew", "English locale")
	var en: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/locales/en.json"))
	var es: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/locales/es.json"))
	for key in en:
		if key != "meta":
			_assert(es.has(key), "missing Spanish: " + key)
	for key in es:
		if key != "meta":
			_assert(en.has(key), "missing English: " + key)
	_assert(catalog.get_curated_events().size() == 1, "curated DONKI event")
	for scene_name in ["main_menu", "astronaut_select", "settings_menu", "hud", "vital_status_bar",
		"time_controls", "workspace", "activity_log", "guide_card", "building_inspector",
		"sol_report", "admin_panel", "audio_controller", "final_result"]:
		_assert(load("res://scenes/ui/%s.tscn" % scene_name) != null, "scene loads: " + scene_name)
	var menu := MainMenu.new()
	add_child(menu)
	menu.queue_free()
	var dialogue := DialogueService.new()
	_assert(dialogue.add_fact(&"warning", &"critical", &"event.tunnel_breach", {}, &"ui:workspace_crew").ok, "critical entry")
	_assert(dialogue.add_fact(&"hint", &"tutorial", &"tutorial.rocket.body").ok, "tutorial entry")
	_assert(dialogue.get_top_notice()["id"] == "warning", "critical priority")
	var speed_before: float = GameClock.get_snapshot()["speed"]
	dialogue.acknowledge(&"warning")
	_assert(dialogue.get_top_notice()["id"] == "warning", "critical survives acknowledgement")
	_assert(GameClock.get_snapshot()["speed"] == speed_before, "notice does not alter clock")
	dialogue.skip_tutorial()
	var chooser := AstronautSelect.new()
	add_child(chooser)
	for i in 4:
		chooser.add_profile(&"medic")
	_assert(chooser.selected.size() == 1, "duplicate selection is rejected")
	for profile in [&"engineer_a", &"botanist_a", &"scientist_a"]:
		chooser.add_profile(profile)
	_assert(chooser.selected.size() == 4, "four distinct profiles selected")
	chooser.queue_free()
	var hud := MissionHud.new()
	add_child(hud)
	_assert(hud._workspace != null and hud._workspace.TABS.size() == 7, "seven tabs")
	_assert(hud._vitals._labels.keys() == ["water", "food", "pressure"], "only water food pressure in HUD")
	var ledger := ResourceLedger.new()
	var building := BuildingService.new()
	var grid := GridService.new()
	var power := PowerService.new()
	var crew := CrewService.new()
	var life := LifeSupportService.new()
	var research := ResearchService.new()
	var rockets := RocketService.new()
	var events := EventService.new()
	var report := SolReportService.new()
	building.ledger = ledger
	building.grid = grid
	building.power = power
	building.research = research
	grid.building_service = building
	power.building_service = building
	power.grid_service = grid
	crew.ledger = ledger
	crew.building_service = building
	life.ledger = ledger
	life.crew_service = crew
	research.power = power
	rockets.ledger = ledger
	rockets.grid = grid
	events.building_service = building
	var session := GameSession.new()
	session.configure({"crew": crew, "building": building, "grid": grid, "power": power,
		"ledger": ledger, "life_support": life, "research": research, "rocket": rockets,
		"event": events, "report": report})
	_assert(session.start_new([&"medic", &"medic", &"medic", &"medic"], 42).ok, "real session starts")
	dialogue.configure(events, building)
	_assert(dialogue.add_fact(&"warning", &"critical", &"event.tunnel_breach", {}, &"ui:workspace_crew").ok, "warning after start")
	_assert(dialogue.add_fact(&"hint", &"tutorial", &"tutorial.rocket.body").ok, "hint after start")
	hud.configure({"crew": crew, "building": building, "grid": grid, "power": power,
		"ledger": ledger, "life_support": life, "research": research, "rocket": rockets,
		"event": events, "report": report, "dialogue": dialogue})
	for tab in hud._workspace.TABS:
		hud._workspace.open_tab(tab)
	_assert(hud._workspace.active_tab == &"codex", "all tabs render with services")
	dialogue.skip_tutorial()
	_assert(hud._guide.visible, "critical remains visible when tutorial skipped")
	hud._log._filter = &"ambient"
	hud._log.refresh()
	await get_tree().process_frame
	_assert(hud._log._list.get_child_count() == 1, "critical survives log filter")
	_assert(GameClock.set_speed(4.0).ok, "x4 available")
	GameState.data["clock"]["sol"] = 11
	events.on_sol_started(11)
	_assert(dialogue.get_top_notice().get("kind") == "critical", "event warning is critical")
	_assert(GameClock.get_snapshot()["speed"] == 4.0, "event warning preserves x4")
	local.set_language(&"es")
	hud._log.refresh()
	await get_tree().process_frame
	_assert(String(hud._log._list.get_child(0).text).contains("Brecha"), "history retranslated")
	var saved := GameState.to_dict()
	var count_before := dialogue.get_entries().size()
	GameState.from_dict(saved)
	SignalBus.state_restored.emit()
	SignalBus.state_restored.emit()
	_assert(dialogue.get_entries().size() == count_before, "restore does not duplicate dialogue")
	dialogue.shutdown()
	hud.queue_free()
	call_deferred("_finish")

func _finish() -> void:
	if failures == 0:
		print("R4 UI tests passed")
	get_tree().quit(1 if failures > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

