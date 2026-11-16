extends RefCounted

static var _data: Dictionary = {}
static var _credits: Dictionary = {}

static func load_data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/learning.json"))
		_credits = JSON.parse_string(FileAccess.get_file_as_string("res://data/credits.json"))
	return _data

static func building(type_id: String) -> Dictionary:
	var row: Dictionary = load_data().get("buildings", {}).get(type_id, {}).duplicate(true)
	if row.is_empty():
		return row
	for reference: Dictionary in _credits.get("references", []):
		if reference.get("buildings", []).has(type_id):
			row["sources"] = reference.get("sources", []).duplicate() + row.get("sources", [])
			row["limit_key"] = reference["limit_key"]
			break
	return row

static func event(kind: String) -> Dictionary:
	return load_data().get("events", {}).get(kind, {}).duplicate(true)

static func open_source(url: String) -> Error:
	for host in ["www.nasa.gov", "science.nasa.gov", "ntrs.nasa.gov", "technology.nasa.gov"]:
		if url.begins_with("https://%s/" % host):
			return OS.shell_open(url)
	return ERR_INVALID_PARAMETER
