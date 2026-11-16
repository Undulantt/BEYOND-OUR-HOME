class_name CrewService
extends RefCounted

var life_support
var rocket_service
var building_service
var ledger: ResourceLedger
var report
var scheduler := TaskScheduler.new()

func create_roster(profile_ids: Array[StringName]) -> GameContracts.ValidationResult:
	if profile_ids.size() != 4:
		return GameContracts.failure(&"four_profiles_required")
	var profiles := Astronaut.profiles()
	for profile_id in profile_ids:
		if not profiles.has(String(profile_id)):
			return GameContracts.failure(&"unknown_profile", {"profile_id": String(profile_id)})
	var members := {}
	for index in profile_ids.size():
		var id := StringName("crew_%d" % (index + 1))
		members[String(id)] = Astronaut.create(id, profile_ids[index])
	GameState.data["crew"] = {"members": members, "tasks": {}, "next_task_id": 1,
		"completed_work": [], "next_crew_id": 5}
	scheduler.building_service = building_service
	return GameContracts.success()

func rebuild_from_state() -> void:
	scheduler.building_service = building_service
	if building_service != null:
		for task in GameState.data.get("crew", {}).get("tasks", {}).values():
			if task.get("state") not in ["completed", "cancelled"] and building_service.get_status(StringName(task["target_id"])) == null:
				scheduler.cancel(StringName(task["id"]))

func get_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for member in GameState.data.get("crew", {}).get("members", {}).values():
		result.append(member.duplicate(true))
	return result

func get_task_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for task in GameState.data.get("crew", {}).get("tasks", {}).values():
		result.append(task.duplicate(true))
	return result

func validate_order(order: TaskOrder) -> GameContracts.ValidationResult:
	return scheduler.validate_order(order)

func issue_urgent_order(order: TaskOrder) -> GameContracts.ValidationResult:
	return scheduler.enqueue(order)

func cancel_task(task_id: StringName) -> GameContracts.ValidationResult:
	return scheduler.cancel(task_id)

func set_priority(crew_id: StringName, category: StringName, priority: int) -> GameContracts.ValidationResult:
	var member := _member(crew_id)
	if member.is_empty() or not TaskScheduler.CATEGORIES.has(category) or priority < 1 or priority > 4:
		return GameContracts.failure(&"invalid_priority")
	member["priorities"][String(category)] = priority
	SignalBus.crew_changed.emit(crew_id)
	return GameContracts.success()

func set_category_allowed(crew_id: StringName, category: StringName, allowed: bool) -> GameContracts.ValidationResult:
	var member := _member(crew_id)
	if member.is_empty() or not TaskScheduler.CATEGORIES.has(category):
		return GameContracts.failure(&"invalid_category")
	var forbidden: Array = member["forbidden_categories"]
	if allowed:
		forbidden.erase(String(category))
	elif not forbidden.has(String(category)):
		forbidden.append(String(category))
	SignalBus.crew_changed.emit(crew_id)
	return GameContracts.success()

func set_sleep_hours(crew_id: StringName, hours: float) -> GameContracts.ValidationResult:
	var member := _member(crew_id)
	if member.is_empty() or not is_finite(hours) or hours < 4.0 or hours > 16.0:
		return GameContracts.failure(&"invalid_sleep_hours")
	member["sleep_hours"] = hours
	SignalBus.crew_changed.emit(crew_id)
	return GameContracts.success()

func order_shelter(crew_id: StringName, shelter: bool = true) -> GameContracts.ValidationResult:
	var member := _member(crew_id)
	if member.is_empty() or not bool(member.get("alive", false)):
		return GameContracts.failure(&"crew_unavailable")
	if shelter and building_service != null:
		var habitat: BuildingStatus = building_service.get_status(&"base_1")
		if habitat == null or habitat.health <= 0.0:
			return GameContracts.failure(&"shelter_unavailable")
	member["shelter"] = shelter
	SignalBus.crew_changed.emit(crew_id)
	return GameContracts.success()

func get_exposure_context(crew_id: StringName) -> Dictionary:
	var member := _member(crew_id)
	var habitat: Dictionary = GameState.data.get("buildings", {}).get("instances", {}).get("base_1", {})
	var safe_habitat := not habitat.is_empty() and float(habitat.get("health", 0.0)) > 0.0
	if member.get("shelter", false) and safe_habitat:
		return {"location_id": "base_1", "exposure": "sheltered"}
	var task: Dictionary = GameState.data.get("crew", {}).get("tasks", {}).get(member.get("task_id", ""), {})
	if task.is_empty() or task.get("state") in ["completed", "cancelled"]:
		return {"location_id": "base_1", "exposure": "habitat" if safe_habitat else "eva"}
	var target := String(task.get("target_id", "base_1"))
	var outdoor: bool = task.get("category") == "emergency_eva" or task.get("task_type") in ["clean", "refuel"]
	var location: Dictionary = GameState.data.get("buildings", {}).get("instances", {}).get(target, {})
	if float(location.get("health", 0.0)) <= 0.0:
		outdoor = true
	return {"location_id": target, "exposure": "eva" if outdoor else "indoors"}

func _apply_exposure(crew_id: StringName, member: Dictionary, fraction: float) -> void:
	var context := get_exposure_context(crew_id)
	var flare := bool(GameState.data.get("events", {}).get("solar_flare_active", false))
	var rate := 0.0
	if context.exposure == "eva":
		rate = float(ConfigDB.balance["events"]["tunnel_breach"]["repair_dose"])
		if flare:
			rate *= float(ConfigDB.balance["events"]["solar_flare"]["eva_dose_multiplier"])
	elif context.exposure == "indoors" and flare:
		rate = float(ConfigDB.balance["events"]["solar_flare"].get("indoor_dose_per_sol", 4.0))
	var profile: Dictionary = Astronaut.profiles().get(String(member["profile_id"]), {})
	var added := rate * float(profile.get("drawback", {}).get("dose_multiplier", 1.0)) * fraction
	member["dose"] = float(member["dose"]) + added
	member["dose_today"] = float(member.get("dose_today", 0.0)) + added

func assign_eva_repair(crew_id: StringName, building_id: StringName, mode: StringName = &"seal") -> GameContracts.ValidationResult:
	var member := _member(crew_id)
	if member.is_empty() or not bool(member.get("alive", false)) or bool(member.get("shelter", false)):
		return GameContracts.failure(&"crew_unavailable")
	if not String(member.get("task_id", "")).is_empty() or member.get("forbidden_categories", []).has("emergency_eva"):
		return GameContracts.failure(&"crew_busy")
	if building_service == null:
		return GameContracts.failure(&"missing_building_service")
	var request: GameContracts.ValidationResult = building_service.request_repair(building_id, mode, crew_id)
	if not request.ok:
		return request
	var order := TaskOrder.new()
	order.id = StringName(request.params["task_id"])
	order.crew_id = crew_id
	order.category = &"emergency_eva"
	order.target_id = building_id
	order.task_type = &"repair"
	order.required_hours = float(request.params["work_hours"])
	var result := scheduler.enqueue(order)
	if not result.ok:
		building_service.cancel_pending_task(order.id)
	return result

func queue_research(crew_id: StringName, laboratory_id: StringName, work_hours: float) -> GameContracts.ValidationResult:
	var order := TaskOrder.new()
	order.crew_id = crew_id
	order.category = &"science_construction"
	order.target_id = laboratory_id
	order.task_type = &"research"
	order.required_hours = work_hours
	if building_service == null or building_service.get_status(laboratory_id) == null or building_service.get_status(laboratory_id).type != &"laboratory":
		return GameContracts.failure(&"invalid_laboratory")
	if building_service.power == null or not building_service.power.is_powered(laboratory_id):
		return GameContracts.failure(&"powered_laboratory_required")
	return scheduler.enqueue(order)

func assign_building_action(crew_id: StringName, building_id: StringName, action: StringName) -> GameContracts.ValidationResult:
	var member := _member(crew_id)
	if member.is_empty() or not bool(member.get("alive", false)) or not String(member.get("task_id", "")).is_empty():
		return GameContracts.failure(&"crew_unavailable")
	if bool(member.get("shelter", false)) or member.get("forbidden_categories", []).has("production"):
		return GameContracts.failure(&"category_forbidden")
	if building_service == null:
		return GameContracts.failure(&"missing_building_service")
	var request: GameContracts.ValidationResult = building_service.request_action_task(building_id, action, crew_id)
	if not request.ok or not request.params.has("task_id"):
		return request
	var order := TaskOrder.new()
	order.id = StringName(request.params["task_id"])
	order.crew_id = crew_id
	order.category = &"production"
	order.target_id = building_id
	order.task_type = action
	order.required_hours = float(request.params.get("work_hours", 0.0))
	var result := scheduler.enqueue(order)
	if not result.ok:
		building_service.cancel_pending_task(order.id)
	return result

func on_building_changed(building_id: StringName, change: StringName) -> void:
	if change != &"removed":
		return
	for task in GameState.data.get("crew", {}).get("tasks", {}).values():
		if task.get("target_id") == String(building_id) and task.get("state") not in ["completed", "cancelled"]:
			scheduler.cancel(StringName(task["id"]))

func consume_completed_work(category: StringName) -> Array[Dictionary]:
	return scheduler.consume_completed_work(category)

func use_medicine(crew_id: StringName) -> GameContracts.ValidationResult:
	var member := _member(crew_id)
	if member.is_empty() or not bool(member.get("alive", false)):
		return GameContracts.failure(&"crew_unavailable")
	if ledger == null or not ledger.spend({"medicine": 1.0}, "crew_medicine"):
		return GameContracts.failure(&"insufficient_resources")
	var profile: Dictionary = Astronaut.profiles().get(String(member["profile_id"]), {})
	var bonus := float(profile.get("benefit", {}).get("medicine_multiplier", 1.0))
	member["health"] = minf(100.0, float(member["health"]) + 20.0 * bonus)
	member["fatigue"] = maxf(0.0, float(member["fatigue"]) - 25.0 * bonus)
	SignalBus.crew_changed.emit(crew_id)
	return GameContracts.success()

func replace_with_rocket(rocket_id: StringName, crew_id: StringName, profile_id: StringName) -> GameContracts.ValidationResult:
	if rocket_service == null:
		return GameContracts.failure(&"missing_rocket_service")
	return rocket_service.exchange(rocket_id, crew_id, profile_id)

func apply_replacement(crew_id: StringName, profile_id: StringName) -> GameContracts.ValidationResult:
	var member := _member(crew_id)
	if member.is_empty() or not bool(member.get("alive", false)) or not Astronaut.profiles().has(String(profile_id)):
		return GameContracts.failure(&"invalid_replacement")
	var old_task := String(member.get("task_id", ""))
	if not old_task.is_empty():
		scheduler.cancel(StringName(old_task))
	var next_id := StringName("crew_%d" % int(GameState.data["crew"]["next_crew_id"]))
	GameState.data["crew"]["next_crew_id"] = int(GameState.data["crew"]["next_crew_id"]) + 1
	member["alive"] = false
	member["replaced_by"] = String(next_id)
	GameState.data["crew"]["members"][String(next_id)] = Astronaut.create(next_id, profile_id)
	SignalBus.crew_changed.emit(crew_id)
	SignalBus.crew_changed.emit(next_id)
	return GameContracts.success()

func step(delta_seconds: float) -> void:
	var fraction := delta_seconds / float(ConfigDB.balance["time"]["sol_seconds_x1"])
	var hours := fraction * float(ConfigDB.balance["astronaut"]["work_hours_per_sol"])
	for id in GameState.data.get("crew", {}).get("members", {}):
		var member: Dictionary = GameState.data["crew"]["members"][id]
		if not bool(member.get("alive", false)):
			continue
		var supply: Dictionary = life_support.get_crew_supply(StringName(id)) if life_support != null else {}
		var shortage := 0
		for resource in ["oxygen", "water", "food"]:
			if supply.get(resource, true) == false:
				shortage += 1
		if shortage > 0:
			member["health"] = maxf(0.0, float(member["health"]) - 12.0 * shortage * fraction)
		var task_id := String(member.get("task_id", ""))
		var task: Dictionary = GameState.data["crew"]["tasks"].get(task_id, {})
		# Exposure follows the person's location, even when an assigned task is
		# blocked or their daily work allowance is exhausted. Shelter moves them home.
		_apply_exposure(StringName(id), member, fraction)
		if not task.is_empty() and not bool(member.get("shelter", false)):
			var worked := float(member.get("worked_hours_today", 0.0))
			var max_work := minf(float(ConfigDB.balance["astronaut"]["work_hours_per_sol"]), 24.0 - float(member.get("sleep_hours", 8.0)))
			if worked < max_work:
				var profile: Dictionary = Astronaut.profiles().get(String(member["profile_id"]), {})
				var speed := float(profile.get("benefit", {}).get("work_multiplier", profile.get("drawback", {}).get("work_multiplier", 1.0)))
				if task.get("task_type") == "repair":
					speed *= float(profile.get("benefit", {}).get("repair_multiplier", profile.get("drawback", {}).get("repair_multiplier", 1.0)))
				if task.get("task_type") == "research":
					speed *= float(profile.get("benefit", {}).get("science_multiplier", profile.get("drawback", {}).get("science_multiplier", 1.0)))
				var effort := minf(hours, max_work - worked)
				var performed := scheduler.progress(StringName(id), effort * speed)
				effort = performed / speed if speed > 0.0 else 0.0
				member["worked_hours_today"] = worked + effort
				if performed > 0.0:
					member["fatigue"] = minf(100.0, float(member["fatigue"]) + 10.0 * fraction)
		member["sleep_hours_today"] = minf(float(member["sleep_hours"]), float(member.get("sleep_hours_today", 0.0)) + fraction * float(member["sleep_hours"]))
		member["fatigue"] = maxf(0.0, float(member["fatigue"]) - 8.0 * fraction)
		if float(member["dose"]) >= float(ConfigDB.balance["astronaut"]["radiation_limit"]):
			member["health"] = maxf(0.0, float(member["health"]) - 6.0 * fraction)
		if float(member["health"]) <= 0.0:
			member["alive"] = false
			if not String(member.get("task_id", "")).is_empty():
				scheduler.cancel(StringName(member["task_id"]))
			SignalBus.crew_changed.emit(StringName(id))

func on_sol_ended(sol: int) -> void:
	if report != null:
		for task in GameState.data.get("crew", {}).get("tasks", {}).values():
			if task.get("state") == "completed" and int(task.get("completed_sol", -1)) == sol:
				_record_fact("work_%s" % task["id"], String(task["target_id"]), sol,
					&"crew.work_completed", {"crew_id": task["crew_id"], "task_type": task["task_type"]},
					{"work_hours": float(task["completed_hours"])})
	for id in GameState.data.get("crew", {}).get("members", {}):
		var member: Dictionary = GameState.data["crew"]["members"][id]
		if not bool(member.get("alive", false)):
			continue
		if report != null and float(member.get("dose_today", 0.0)) > 0.0:
			_record_fact("dose_%s_%d" % [id, sol], id, sol, &"crew.radiation_exposure",
				{"crew_id": id}, {"dose": float(member["dose_today"])})
		if float(member.get("sleep_hours_today", 0.0)) + 0.001 < float(member.get("sleep_hours", 8.0)):
			member["fatigue"] = minf(100.0, float(member["fatigue"]) + 12.0)
		member["worked_hours_today"] = 0.0
		member["sleep_hours_today"] = 0.0
		member["dose_today"] = 0.0
		SignalBus.crew_changed.emit(StringName(id))

func _member(crew_id: StringName) -> Dictionary:
	return GameState.data.get("crew", {}).get("members", {}).get(String(crew_id), {})

func _record_fact(reason_id: String, target_id: String, sol: int, key: StringName, params: Dictionary, impact: Dictionary) -> void:
	report.record_fact({"reason_id": reason_id, "source_id": "", "target_id": target_id,
		"sol": sol, "sim_time": float(GameState.data["clock"]["elapsed"]),
		"message_key": String(key), "params": params, "impact": impact})
