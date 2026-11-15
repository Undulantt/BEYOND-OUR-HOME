extends Node

const SCHEMA_VERSION := 1
var data: Dictionary = {}

func reset(seed_value: int) -> void:
	data = {
		"schema_version": SCHEMA_VERSION, "seed": seed_value,
		"rng_state": seed_value, "clock": {"sol": 1, "started_sol": 0,
			"elapsed": 0.0, "speed": 1.0, "paused": false},
		"inventory": {}, "ledger_entries": [], "power": {"stored": 0.0, "priorities": {}},
		"life_support": {"supply": {}, "shortages": {}}, "crew": {}, "buildings": {},
		"world": {}, "research": {}, "events": {}, "rockets": {},
		"reports": {}, "settings": {}, "dialogue": {},
		"tutorial": {}, "result": ""
	}

func to_dict() -> Dictionary:
	return data.duplicate(true)

func from_dict(value: Dictionary) -> void:
	data = value.duplicate(true)
	# Drop retired indicators when loading older saves.
	data.erase("autonomy")
	for member in data.get("crew", {}).get("members", {}).values():
		member.erase("morale")
		member.erase("break_remaining")

func is_running() -> bool:
	return data.has("clock") and data["clock"] is Dictionary and data.has("crew") and String(data.get("result", "")).is_empty()
