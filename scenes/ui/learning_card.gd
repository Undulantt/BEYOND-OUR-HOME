extends PanelContainer

signal controls_requested(id: StringName)
const CATALOG := preload("res://scenes/ui/learning_catalog.gd")
var services: Dictionary = {}
var target_id := &""
var event_kind := ""
var _column: VBoxContainer

func _ready() -> void:
	_column = UiHelpers.column(self)
	SignalBus.language_changed.connect(func(_code): refresh())
	SignalBus.event_changed.connect(func(_id, _phase):
		if visible and not event_kind.is_empty(): refresh())
	SignalBus.building_changed.connect(func(id, change):
		if id == target_id and change == &"removed": refresh())

func show_building(id: StringName) -> void:
	target_id = id
	event_kind = ""
	refresh()

func show_event(kind: String) -> void:
	event_kind = kind
	target_id = &""
	refresh()

func refresh() -> void:
	if _column == null:
		return
	UiHelpers.clear(_column)
	var row: Dictionary
	if not event_kind.is_empty():
		var chooser := OptionButton.new()
		for kind in ["dust_storm", "solar_flare", "tunnel_breach"]:
			chooser.add_item(_tr(StringName("learning.event." + kind + ".title")))
			chooser.set_item_metadata(chooser.item_count - 1, kind)
			if kind == event_kind: chooser.select(chooser.item_count - 1)
		chooser.fit_to_longest_item = false
		chooser.item_selected.connect(func(index): show_event(String(chooser.get_item_metadata(index))))
		_column.add_child(chooser)
		row = CATALOG.event(event_kind)
		_text(_tr(StringName(row.get("title_key", "ui.none"))), 22)
		_section(&"learning.why", row.get("why_key", ""))
		_section(&"learning.consequence", row.get("consequence_key", ""))
		_section(&"learning.response", row.get("response_key", ""))
	else:
		if not services.has("building"):
			return
		var status: BuildingStatus = services["building"].get_status(target_id)
		if status == null:
			_text(_tr(&"learning.removed"))
			return
		row = CATALOG.building(String(status.type))
		_text(_tr(StringName("building." + String(status.type))), 22)
		_section(&"learning.purpose", row.get("purpose_key", ""))
		_section(&"learning.curiosity", row.get("curiosity_key", ""))
		_column.add_child(UiHelpers.button(_tr(&"learning.controls"), func(): controls_requested.emit(target_id), true))
	_section(&"learning.adaptation", row.get("limit_key", ""))
	_text(_tr(&"learning.sources"), 18)
	for source: Dictionary in row.get("sources", []):
		_text(String(source.get("provider", "NASA")) + " · " + String(source["title"]), 15)
		var link := UiHelpers.button(_tr(&"credits.open_source"), func(): CATALOG.open_source(String(source["url"])))
		link.tooltip_text = String(source["url"])
		link.set_meta("source_url", source["url"])
		_column.add_child(link)

func _section(heading: StringName, key: String) -> void:
	if key.is_empty(): return
	_text(_tr(heading), 18)
	_text(_tr(StringName(key)), 17)

func _text(value: String, font_size: int = 17) -> void:
	_column.add_child(UiHelpers.label(value, font_size))

func _tr(key: StringName) -> String:
	return LocalizationDB.translate_key(key)
