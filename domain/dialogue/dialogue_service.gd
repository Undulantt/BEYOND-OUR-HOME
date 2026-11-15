class_name DialogueService
extends RefCounted

const KINDS := [&"critical", &"tutorial", &"operational", &"ambient", &"science"]
var events: EventService
var buildings: BuildingService
var _tutorial_definition: Dictionary = {}
var _tutorial_busy := false
var _changing_pause := false

func configure(event_service: EventService = null, building_service: BuildingService = null) -> void:
	events = event_service
	buildings = building_service
	if not SignalBus.sol_started.is_connected(_on_sol_started):
		SignalBus.sol_started.connect(_on_sol_started)
	if not SignalBus.building_changed.is_connected(_on_building_changed):
		SignalBus.building_changed.connect(_on_building_changed)
	if not SignalBus.research_changed.is_connected(_on_research_changed):
		SignalBus.research_changed.connect(_on_research_changed)
	if not SignalBus.event_changed.is_connected(_on_event_changed):
		SignalBus.event_changed.connect(_on_event_changed)
	for binding in [[SignalBus.tick_advanced, _on_tutorial_tick], [SignalBus.crew_changed, _on_tutorial_crew], [SignalBus.rocket_changed, _on_tutorial_rocket], [SignalBus.energy_changed, _on_tutorial_energy], [SignalBus.pause_changed, _on_pause_changed], [SignalBus.resources_changed, _on_tutorial_resources]]:
		if not binding[0].is_connected(binding[1]):
			binding[0].connect(binding[1])

func shutdown() -> void:
	if SignalBus.sol_started.is_connected(_on_sol_started):
		SignalBus.sol_started.disconnect(_on_sol_started)
	if SignalBus.building_changed.is_connected(_on_building_changed):
		SignalBus.building_changed.disconnect(_on_building_changed)
	if SignalBus.research_changed.is_connected(_on_research_changed):
		SignalBus.research_changed.disconnect(_on_research_changed)
	if SignalBus.event_changed.is_connected(_on_event_changed):
		SignalBus.event_changed.disconnect(_on_event_changed)
	for binding in [[SignalBus.tick_advanced, _on_tutorial_tick], [SignalBus.crew_changed, _on_tutorial_crew], [SignalBus.rocket_changed, _on_tutorial_rocket], [SignalBus.energy_changed, _on_tutorial_energy], [SignalBus.pause_changed, _on_pause_changed], [SignalBus.resources_changed, _on_tutorial_resources]]:
		if binding[0].is_connected(binding[1]):
			binding[0].disconnect(binding[1])

func rebuild_from_state() -> void:
	if GameState.data.is_empty():
		return
	_ensure_state()
	_refresh_tutorial()

func add_entry(entry: DialogueEntry) -> GameContracts.ValidationResult:
	if GameState.data.is_empty():
		return GameContracts.failure(&"not_running")
	_ensure_state()
	if String(entry.id).is_empty() or not KINDS.has(entry.kind) or not _localization().has_key_in_both(entry.message_key):
		return GameContracts.failure(&"invalid_dialogue")
	if not String(entry.source_id).is_empty() and _catalog().get_source(entry.source_id).is_empty():
		return GameContracts.failure(&"unknown_source")
	if not String(entry.focus_target).is_empty() and not _valid_focus(entry.focus_target):
		return GameContracts.failure(&"invalid_focus_target")
	for old in GameState.data["dialogue"]["entries"]:
		if old.get("id") == String(entry.id):
			return GameContracts.failure(&"duplicate_dialogue")
	entry.created_sol = int(GameState.data.get("clock", {}).get("sol", 1))
	GameState.data["dialogue"]["entries"].append(entry.as_dict())
	SignalBus.log_entry_added.emit(entry)
	return GameContracts.success()

func add_fact(id: StringName, kind: StringName, key: StringName, params: Dictionary = {}, focus: StringName = &"", source: StringName = &"") -> GameContracts.ValidationResult:
	var entry := DialogueEntry.new()
	entry.id = id
	entry.kind = kind
	entry.severity = &"critical" if kind == &"critical" else &"info"
	entry.message_key = key
	entry.params = params
	entry.focus_target = focus
	entry.source_id = source
	return add_entry(entry)

func get_entries() -> Array[Dictionary]:
	if GameState.data.is_empty():
		return []
	_ensure_state()
	var result: Array[Dictionary] = []
	for item in GameState.data["dialogue"]["entries"]:
		result.append(item.duplicate(true))
	return result

func get_top_notice() -> Dictionary:
	var best: Dictionary = {}
	var rank := 99
	for item in get_entries():
		if item.get("resolved", false):
			continue
		if item.get("kind") == "tutorial" and GameState.data.get("tutorial", {}).get("skipped", false):
			continue
		if item.get("acknowledged", false) and item.get("kind") != "critical":
			continue
		var next_rank := KINDS.find(StringName(item.get("kind", "")))
		if next_rank >= 0 and next_rank < rank:
			best = item
			rank = next_rank
	return best

func acknowledge(id: StringName) -> GameContracts.ValidationResult:
	_ensure_state()
	for item in GameState.data["dialogue"]["entries"]:
		if item.get("id") == String(id):
			var step := get_tutorial_step()
			if not step.is_empty() and String(id) == "tutorial_%s" % step["id"]:
				if step["condition"] == "begin":
					reactivate_tutorial()
					return GameContracts.success()
				if step["condition"] == "ack":
					complete_tutorial_step(StringName(step["id"]))
					_refresh_tutorial()
					return GameContracts.success()
			item["acknowledged"] = true
			SignalBus.guide_dialogue_changed.emit(id, &"acknowledged")
			return GameContracts.success()
	return GameContracts.failure(&"unknown_dialogue")

func resolve(id: StringName) -> GameContracts.ValidationResult:
	_ensure_state()
	for item in GameState.data["dialogue"]["entries"]:
		if item.get("id") == String(id):
			item["resolved"] = true
			SignalBus.guide_dialogue_changed.emit(id, &"resolved")
			return GameContracts.success()
	return GameContracts.failure(&"unknown_dialogue")

func skip_tutorial() -> void:
	if GameState.data.is_empty():
		return
	GameState.data.get_or_add("tutorial", {})["skipped"] = true
	GameState.data["tutorial"]["guided"] = false
	_release_tutorial_pause()
	SignalBus.guide_dialogue_changed.emit(&"tutorial", &"skipped")

func reactivate_tutorial() -> void:
	if GameState.data.is_empty():
		return
	if GameState.data.get("tutorial", {}).get("completed", []).has("finish"):
		restart_tutorial()
	GameState.data.get_or_add("tutorial", {})["skipped"] = false
	GameState.data["tutorial"]["guided"] = true
	SettingsService.apply_settings({"show_tutorial": true})
	_pause_tutorial()
	complete_tutorial_step(&"welcome")
	_refresh_tutorial()
	SignalBus.guide_dialogue_changed.emit(&"tutorial", &"reactivated")

func observe_fact(_fact_type: StringName, _params: Dictionary = {}) -> void:
	_refresh_tutorial()

func complete_tutorial_step(id: StringName) -> void:
	var tutorial: Dictionary = GameState.data.get_or_add("tutorial", {})
	var completed: Array = tutorial.get_or_add("completed", [])
	if not completed.has(String(id)):
		completed.append(String(id))
	resolve(StringName("tutorial_%s" % id))

func get_display_notice() -> Dictionary:
	# Acknowledged hazards stay in history, but must not hide the next robot message.
	var best: Dictionary = {}
	var rank := 99
	var step := get_tutorial_step()
	for item in get_entries():
		if item.get("resolved", false) or item.get("acknowledged", false):
			continue
		if item.get("kind") == "tutorial":
			if GameState.data.get("tutorial", {}).get("skipped", false):
				continue
			if String(item.get("id", "")).begins_with("tutorial_") and (step.is_empty() or item["id"] != "tutorial_%s" % step["id"]):
				continue
		var next_rank := KINDS.find(StringName(item.get("kind", "")))
		if next_rank >= 0 and next_rank < rank:
			best = item
			rank = next_rank
	return best

func get_tutorial_step() -> Dictionary:
	if GameState.data.is_empty() or GameState.data.get("tutorial", {}).get("skipped", false):
		return {}
	var current := String(GameState.data.get("tutorial", {}).get("current", ""))
	var steps: Array = _tutorial_data().get("steps", [])
	for index in steps.size():
		if steps[index]["id"] == current:
			var result: Dictionary = steps[index].duplicate(true)
			result["index"] = index + 1
			result["total"] = steps.size()
			return result
	return {}

func recall_tutorial() -> void:
	if GameState.data.get("tutorial", {}).get("skipped", false):
		reactivate_tutorial()
		return
	_refresh_tutorial()
	var step := get_tutorial_step()
	if step.is_empty():
		return
	for item in GameState.data["dialogue"]["entries"]:
		if item.get("id") == "tutorial_%s" % step["id"]:
			item["acknowledged"] = false
	_pause_tutorial()
	SignalBus.guide_dialogue_changed.emit(&"tutorial", &"recalled")

func restart_tutorial() -> void:
	if GameState.data.is_empty():
		return
	_release_tutorial_pause()
	GameState.data["tutorial"] = {"completed": [], "skipped": false, "guided": false, "initialized": true}
	for item in GameState.data.get("dialogue", {}).get("entries", []):
		if String(item.get("id", "")).begins_with("tutorial_"):
			item["resolved"] = true
	SettingsService.apply_settings({"show_tutorial": true})
	_refresh_tutorial()

func tutorial_build_site(kind: StringName) -> Vector2i:
	var values: Array = _tutorial_data().get("build_sites", {}).get(String(kind), [15, 17])
	var preferred := Vector2i(int(values[0]), int(values[1]))
	if buildings == null:
		return preferred
	if buildings.validate_placement(GameContracts.PlacementRequest.new(kind, preferred)).ok:
		return preferred
	for radius in range(1, 9):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var cell := preferred + Vector2i(x, y)
				if buildings.validate_placement(GameContracts.PlacementRequest.new(kind, cell)).ok:
					return cell
	return preferred

func _tutorial_data() -> Dictionary:
	if _tutorial_definition.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json"))
		_tutorial_definition = parsed if parsed is Dictionary else {}
	return _tutorial_definition

func _refresh_tutorial() -> void:
	if _tutorial_busy or not GameState.is_running():
		return
	_tutorial_busy = true
	_ensure_state()
	var state: Dictionary = GameState.data.get_or_add("tutorial", {})
	if not state.get("initialized", false):
		state["initialized"] = true
		state["skipped"] = bool(state.get("skipped", false)) or not bool(SettingsService.get_settings().get("show_tutorial", true))
	state.get_or_add("completed", [])
	if state.get("skipped", false):
		_tutorial_busy = false
		return
	var previous := String(state.get("current", ""))
	var next_current := ""
	for step in _tutorial_data().get("steps", []):
		var id := String(step["id"])
		if state["completed"].has(id):
			continue
		if _tutorial_condition(String(step["condition"])):
			complete_tutorial_step(StringName(id))
			continue
		next_current = id
		state["current"] = id
		var body := String(step["body_key"])
		var target := String(step["focus_target"])
		var condition := String(step["condition"])
		if id == "day_night" and (_has_building("battery") or (buildings != null and buildings.ledger != null and buildings.ledger.get_amount(&"iron_plates") >= 8.0)):
			body = "onboarding.day_night_ready.body"
		if condition.begins_with("unlocked:") and not _has_building("laboratory"):
			body = "onboarding.no_lab.body"
			target = "ui:tutorial_laboratory"
		elif condition.begins_with("unlocked:") and not _enough_research_orders(condition.get_slice(":", 1)):
			body = "onboarding.reassign.body"
			target = "ui:workspace_laboratory"
		if id in ["tunnel", "laboratory", "solar_panel", "battery"] and buildings != null:
			if not buildings.ledger.can_afford(ConfigDB.balance["buildings"][id]["cost"]):
				body = "onboarding.no_budget.body"
				target = "ui:workspace_rocket"
		var existing: Dictionary = {}
		for item in GameState.data["dialogue"]["entries"]:
			if item.get("id") == "tutorial_%s" % id:
				existing = item
				break
		if existing.is_empty():
			add_fact(StringName("tutorial_%s" % id), &"tutorial", StringName(body), {}, StringName(target))
		else:
			var changed: bool = existing.get("message_key") != body or existing.get("focus_target") != target or existing.get("resolved", false)
			existing["message_key"] = body
			existing["focus_target"] = target
			existing["resolved"] = false
			if previous != id:
				existing["acknowledged"] = false
			if changed:
				SignalBus.guide_dialogue_changed.emit(StringName(id), &"updated")
		break
	state["current"] = next_current
	if String(state["current"]).is_empty():
		state["guided"] = false
		_release_tutorial_pause()
	if previous != state["current"]:
		if not String(state["current"]).is_empty() and state.get("guided", false):
			_pause_tutorial()
		SignalBus.guide_dialogue_changed.emit(&"tutorial", &"advanced")
	_tutorial_busy = false

func _has_building(kind: String) -> bool:
	for item in GameState.data.get("buildings", {}).get("instances", {}).values():
		if item.get("type") == kind and float(item.get("health", 0.0)) > 0.0:
			return true
	return false

func _enough_research_orders(tech: String) -> bool:
	var research: Dictionary = GameState.data.get("research", {})
	if research.get("unlocked", []).has(tech):
		return true
	if research.get("active") != tech:
		return false
	var hours := float(research.get("progress", 0.0))
	for task in GameState.data.get("crew", {}).get("tasks", {}).values():
		if task.get("task_type") == "research" and task.get("state") not in ["completed", "cancelled"]:
			hours += maxf(0.0, float(task.get("required_hours", 0.0)) - float(task.get("completed_hours", 0.0)))
	return hours + 0.0001 >= float(ConfigDB.balance["research"].get(tech, INF))

func _tutorial_condition(condition: String) -> bool:
	var research: Dictionary = GameState.data.get("research", {})
	var rocket: Dictionary = GameState.data.get("rockets", {}).get("plans", {}).get("rocket_1", {})
	if condition == "begin":
		return GameState.data.get("tutorial", {}).get("guided", false)
	if condition == "ack":
		return false
	if condition == "tunnel":
		var count := 0
		for item in GameState.data.get("buildings", {}).get("instances", {}).values():
			if item.get("type") == "tunnel":
				count += 1
		return count > 2 or _has_building("laboratory")
	if condition == "laboratory":
		return _has_building("laboratory")
	if condition.begins_with("building:"):
		return _has_building(condition.get_slice(":", 1))
	if condition.begins_with("unlocked:"):
		return research.get("unlocked", []).has(condition.get_slice(":", 1))
	if condition.begins_with("research:"):
		var tech := condition.get_slice(":", 1)
		return research.get("active") == tech or research.get("unlocked", []).has(tech)
	if condition.begins_with("workers:"):
		return _enough_research_orders(condition.get_slice(":", 1))
	match condition:
		"landing_zone": return not rocket.get("zone", []).is_empty()
		"manifest": return rocket.get("confirmed", false)
		"arrived": return rocket.get("landed", false)
		"rocket_processed": return rocket.get("disposition", "available") in ["salvaged", "exchanged"]
	return false

func _pause_tutorial() -> void:
	if not GameState.data.get("tutorial", {}).get("guided", false):
		return
	if not GameClock.get_snapshot().get("paused", false):
		GameState.data["tutorial"]["pause_owned"] = true
		_changing_pause = true
		GameClock.set_paused(true)
		_changing_pause = false

func _release_tutorial_pause() -> void:
	if GameState.data.get("tutorial", {}).get("pause_owned", false):
		GameState.data["tutorial"]["pause_owned"] = false
		GameClock.set_paused(false)

func _on_pause_changed(_paused: bool) -> void:
	if not _changing_pause and not GameState.data.is_empty():
		GameState.data.get_or_add("tutorial", {})["pause_owned"] = false

func _on_tutorial_tick(_delta: float) -> void:
	_refresh_tutorial()
	if GameState.data.get("tutorial", {}).get("skipped", false) or buildings == null:
		return
	var reactor := buildings.get_status(&"reactor_1")
	if reactor != null and float(reactor.modifiers.get("fuel_sols", 99.0)) <= 2.0:
		var key := &"onboarding.refuel.body" if buildings.ledger.get_amount(&"nuclear_core") >= 1.0 else &"onboarding.no_core.body"
		var existing: Dictionary = {}
		for item in GameState.data["dialogue"]["entries"]:
			if item.get("id") == "lesson_refuel":
				existing = item
				break
		if existing.is_empty():
			add_fact(&"lesson_refuel", &"operational", key, {}, &"reactor_1")
		elif not existing.get("resolved", false) and existing.get("message_key") != String(key):
			existing["message_key"] = String(key)
			SignalBus.guide_dialogue_changed.emit(&"lesson_refuel", &"updated")

func _on_tutorial_resources(delta: Dictionary, _reason: String) -> void:
	if delta.has("iron_plates") or delta.has("chips"):
		_refresh_tutorial()
	if delta.has("nuclear_core"):
		_on_tutorial_tick(0.0)

func _on_tutorial_crew(_id: StringName) -> void:
	_refresh_tutorial()

func _on_tutorial_rocket(_id: StringName, _phase: StringName) -> void:
	_refresh_tutorial()

func _on_tutorial_energy(_snapshot: GameContracts.EnergySnapshot) -> void:
	_refresh_tutorial()

func _ensure_state() -> void:
	GameState.data.get_or_add("dialogue", {})
	GameState.data["dialogue"].get_or_add("entries", [])

func _valid_focus(target: StringName) -> bool:
	var value := String(target)
	return value.begins_with("ui:") or value.begins_with("world:") or value.begins_with("crew_") or value.contains("_")

func _on_sol_started(sol: int) -> void:
	observe_fact(&"sol_started", {"sol": sol})

func _on_building_changed(id: StringName, change: StringName) -> void:
	if change == &"placed" and buildings != null:
		var status := buildings.get_status(id)
		if status != null:
			observe_fact(&"building_placed", {"building_id": String(status.type)})
	if change in [&"repaired", &"isolated"] and not _has_tunnel_leak():
		resolve(&"event_tunnel_breach_active")
	if change == &"isolated" and GameState.data.get("tutorial", {}).get("guided", false):
		add_fact(StringName("lesson_repair_%s" % id), &"critical", &"onboarding.repair.body", {}, id)
	if change == &"repaired":
		resolve(StringName("lesson_repair_%s" % id))
		if buildings != null:
			var status := buildings.get_status(id)
			if status != null and status.type == &"reactor" and float(status.modifiers.get("fuel_sols", 0.0)) > 2.0:
				resolve(&"lesson_refuel")
	_refresh_tutorial()

func _on_research_changed(id: StringName, change: StringName) -> void:
	if change == &"unlocked":
		observe_fact(&"research_completed", {"tech_id": String(id)})
		if id == &"satellite_scan" and not GameState.data.get("tutorial", {}).get("skipped", false):
			add_fact(&"lesson_scan", &"operational", &"onboarding.scan.body", {}, &"world:scan_sector")
	else:
		_refresh_tutorial()

func _on_event_changed(id: StringName, phase: StringName) -> void:
	if phase == &"ended":
		resolve(StringName("event_%s" % id))
		if id != &"tunnel_breach" or not _has_tunnel_leak():
			resolve(StringName("event_%s_active" % id))
		return
	if events == null:
		return
	for event in events.get_snapshot():
		if event.get("id") != String(id):
			continue
		var kind := String(event.get("type", ""))
		if phase == &"warning":
			var sols := maxi(0, int(event.get("start_sol", 0)) - int(GameState.data.get("clock", {}).get("sol", 1)))
			var key := "event.%s.warning" % kind
			var focus: StringName = &"ui:workspace_crew"
			var teaching: bool = GameState.data.get("tutorial", {}).get("guided", false) or GameState.data.get("tutorial", {}).get("completed", []).has("finish")
			if teaching and kind in ["dust_storm", "solar_flare"]:
				key = "onboarding.dust.body" if kind == "dust_storm" else "onboarding.flare.body"
				if kind == "dust_storm":
					focus = &"ui:workspace_energy"
					for building_id in GameState.data.get("buildings", {}).get("instances", {}):
						if GameState.data["buildings"]["instances"][building_id].get("type") == "solar_panel":
							focus = StringName(building_id)
							break
			add_fact(StringName("event_%s" % id), &"critical", StringName(key), {"sols": sols}, focus)
			observe_fact(&"event_warning", {"event_id": kind})
		elif phase == &"active":
			resolve(StringName("event_%s" % id))
			var focus := StringName(event.get("target_ids", [])[0]) if not event.get("target_ids", []).is_empty() else &"ui:workspace_crew"
			var key := "onboarding.breach.body" if kind == "tunnel_breach" and GameState.data.get("tutorial", {}).get("guided", false) else "event.%s.active" % kind
			add_fact(StringName("event_%s_active" % id), &"critical", StringName(key), {}, focus)
		if phase in [&"warning", &"active"]:
			_pause_tutorial()
		break

func _has_tunnel_leak() -> bool:
	if buildings == null or buildings.tunnel_network == null:
		return false
	return not buildings.tunnel_network.get_snapshot().get("leaks", []).is_empty()

func _localization() -> Node:
	return Engine.get_main_loop().root.get_node("LocalizationDB")

func _catalog() -> Node:
	return Engine.get_main_loop().root.get_node("NasaDataCatalog")
