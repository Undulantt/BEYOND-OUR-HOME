class_name RocketService
extends RefCounted

var ledger: ResourceLedger
var grid: GridService
var crew_service
var report

func rebuild_from_state() -> void:
	pass

func get_snapshot() -> Array[Dictionary]:
	_ensure_plans()
	var result: Array[Dictionary] = []
	for plan in GameState.data["rockets"]["plans"].values():
		result.append(plan.duplicate(true))
	return result

func quote_next_mass_limit() -> float:
	_ensure_plans()
	for id in ["rocket_1", "rocket_2", "rocket_3", "rocket_4"]:
		var plan: Dictionary = GameState.data["rockets"]["plans"][id]
		if not bool(plan["landed"]):
			return float(plan["mass_limit"])
	return 0.0

func validate_manifest(rocket_id: StringName, manifest: Dictionary) -> GameContracts.ValidationResult:
	var plan := _plan(rocket_id)
	if plan.is_empty() or bool(plan["landed"]) or bool(plan["confirmed"]):
		return GameContracts.failure(&"manifest_locked")
	var masses: Dictionary = ConfigDB.balance["rockets"]["cargo_mass"]
	var mass := 0.0
	for item in manifest:
		if not masses.has(item) or not (manifest[item] is int or manifest[item] is float):
			return GameContracts.failure(&"invalid_manifest_item")
		var count := float(manifest[item])
		if not is_finite(count) or count < 0.0 or not is_equal_approx(count, roundf(count)):
			return GameContracts.failure(&"invalid_manifest_count")
		if item == "astronaut_replacement" and count > 1.0:
			return GameContracts.failure(&"replacement_limit")
		mass += count * float(masses[item])
	if mass > float(plan["mass_limit"]) + 0.000001:
		return GameContracts.failure(&"manifest_overweight", {"mass": mass, "limit": plan["mass_limit"]})
	var result := GameContracts.success()
	result.params = {"mass": mass, "limit": plan["mass_limit"]}
	return result

func reserve_landing_zone(rocket_id: StringName, zone: Rect2i) -> GameContracts.ValidationResult:
	var plan := _plan(rocket_id)
	if plan.is_empty() or bool(plan["confirmed"]) or bool(plan["landed"]):
		return GameContracts.failure(&"zone_locked")
	var required := int(ConfigDB.balance["rockets"]["landing_zone_size"])
	if zone.size != Vector2i(required, required):
		return GameContracts.failure(&"invalid_landing_zone_size")
	if grid == null:
		return GameContracts.failure(&"missing_grid")
	if not plan["zone"].is_empty():
		return GameContracts.failure(&"zone_already_reserved")
	var result: GameContracts.ValidationResult = grid.reserve_zone(rocket_id, zone)
	if result.ok:
		plan["zone"] = [zone.position.x, zone.position.y, zone.size.x, zone.size.y]
		SignalBus.rocket_changed.emit(rocket_id, &"zone_reserved")
	return result

func confirm_manifest(rocket_id: StringName, manifest: Dictionary) -> GameContracts.ValidationResult:
	var plan := _plan(rocket_id)
	if plan.is_empty() or plan["zone"].is_empty():
		return GameContracts.failure(&"landing_zone_required")
	var result := validate_manifest(rocket_id, manifest)
	if not result.ok:
		return result
	plan["manifest"] = manifest.duplicate(true)
	plan["confirmed"] = true
	SignalBus.rocket_changed.emit(rocket_id, &"manifest_confirmed")
	return result

func trigger_arrival(rocket_id: StringName) -> GameContracts.ValidationResult:
	var plan := _plan(rocket_id)
	if plan.is_empty() or bool(plan["landed"]):
		return GameContracts.failure(&"arrival_already_processed")
	if not bool(plan["confirmed"]) or plan["zone"].is_empty():
		return GameContracts.failure(&"manifest_not_ready")
	if int(GameState.data["clock"]["sol"]) < int(plan["arrival_sol"]):
		return GameContracts.failure(&"arrival_too_early")
	var reservations: Dictionary = GameState.data.get("world", {}).get("reservations", {})
	if not reservations.has(String(rocket_id)) or reservations[String(rocket_id)] != plan["zone"]:
		return GameContracts.failure(&"landing_zone_invalid")
	if ledger == null:
		return GameContracts.failure(&"missing_ledger")
	plan["landed"] = true
	if not bool(plan["cargo_transferred"]):
		var cargo: Dictionary = plan["manifest"].duplicate(true)
		cargo.erase("astronaut_replacement")
		if not cargo.is_empty() and ledger != null:
			ledger.add(cargo, "cargo_%s" % rocket_id)
		plan["cargo_transferred"] = true
	SignalBus.rocket_changed.emit(rocket_id, &"landed")
	return GameContracts.success()

func on_sol_started(sol: int) -> void:
	_ensure_plans()
	for id in GameState.data["rockets"]["plans"]:
		var plan: Dictionary = GameState.data["rockets"]["plans"][id]
		if int(plan["arrival_sol"]) == sol and not bool(plan["landed"]):
			trigger_arrival(StringName(id))

func validate_salvage(rocket_id: StringName, crew_id: StringName) -> GameContracts.ValidationResult:
	var plan := _plan(rocket_id)
	if plan.is_empty() or not bool(plan["landed"]) or plan["disposition"] != "available":
		return GameContracts.failure(&"rocket_unavailable")
	var member: Dictionary = GameState.data.get("crew", {}).get("members", {}).get(String(crew_id), {})
	if member.is_empty() or not bool(member.get("alive", false)) or bool(member.get("shelter", false)):
		return GameContracts.failure(&"crew_unavailable")
	return GameContracts.success()

func salvage(rocket_id: StringName, crew_id: StringName) -> GameContracts.ValidationResult:
	var result := validate_salvage(rocket_id, crew_id)
	if not result.ok:
		return result
	if ledger == null:
		return GameContracts.failure(&"missing_ledger")
	var plan := _plan(rocket_id)
	plan["disposition"] = "salvaged"
	ledger.add(ConfigDB.balance["rockets"]["salvage"], "rocket_salvage_%s" % rocket_id)
	if grid != null:
		grid.release_zone(rocket_id)
	SignalBus.rocket_changed.emit(rocket_id, &"salvaged")
	return result

func validate_exchange(rocket_id: StringName, crew_id: StringName, profile_id: StringName) -> GameContracts.ValidationResult:
	var plan := _plan(rocket_id)
	if plan.is_empty() or not bool(plan["landed"]) or plan["disposition"] != "available":
		return GameContracts.failure(&"rocket_unavailable")
	if float(plan["manifest"].get("astronaut_replacement", 0.0)) < 1.0:
		return GameContracts.failure(&"replacement_not_manifested")
	if not Astronaut.profiles().has(String(profile_id)):
		return GameContracts.failure(&"unknown_profile")
	var member: Dictionary = GameState.data.get("crew", {}).get("members", {}).get(String(crew_id), {})
	if member.is_empty() or not bool(member.get("alive", false)):
		return GameContracts.failure(&"crew_unavailable")
	return GameContracts.success()

func exchange(rocket_id: StringName, crew_id: StringName, profile_id: StringName) -> GameContracts.ValidationResult:
	var result := validate_exchange(rocket_id, crew_id, profile_id)
	if not result.ok:
		return result
	if crew_service == null:
		return GameContracts.failure(&"missing_crew_service")
	var replacement: GameContracts.ValidationResult = crew_service.apply_replacement(crew_id, profile_id)
	if not replacement.ok:
		return replacement
	_plan(rocket_id)["disposition"] = "exchanged"
	if grid != null:
		grid.release_zone(rocket_id)
	SignalBus.rocket_changed.emit(rocket_id, &"exchanged")
	return result

func _plan(rocket_id: StringName) -> Dictionary:
	_ensure_plans()
	return GameState.data["rockets"]["plans"].get(String(rocket_id), {})

func _ensure_plans() -> void:
	var rockets: Dictionary = GameState.data.get("rockets", {})
	if rockets.has("plans"):
		return
	rockets["plans"] = {}
	var arrivals: Array = ConfigDB.balance["rockets"]["arrival_sols"]
	for index in arrivals.size():
		var id := "rocket_%d" % (index + 1)
		rockets["plans"][id] = {"id": id, "arrival_sol": int(arrivals[index]),
			"manifest": {}, "mass_limit": float(ConfigDB.balance["rockets"]["base_mass"]),
			"confirmed": false, "zone": [], "landed": false,
			"cargo_transferred": false, "disposition": "available"}
