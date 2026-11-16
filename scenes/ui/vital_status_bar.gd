class_name VitalStatusBar
extends HFlowContainer

const RESERVE_SOLS := 7.0
const STATUS_TINTS := {"water": Color("5b9fe0"), "food": Color("8fc878"),
	"energy": Color("e8bf65"), "oxygen": Color("8ccee4"), "pressure": Color("81c9b8")}
var services: Dictionary = {}
var _labels: Dictionary = {}
var _cards: Dictionary = {}
var _bars: Dictionary = {}
var _details: Dictionary = {}
var _refresh_queued := false

func _ready() -> void:
	for id in ["water", "food", "energy", "oxygen", "pressure"]:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(164 if id != "pressure" else 138, 62)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cards[id] = card
		add_child(card)
		_apply_card_style(id, false)
		var column := UiHelpers.column(card)
		column.add_theme_constant_override("separation", 3)
		var title := UiHelpers.label("", 15)
		title.add_theme_font_size_override("font_size", 16)
		_labels[id] = title
		column.add_child(title)
		if id != "pressure":
			var bar := ProgressBar.new()
			bar.name = "Reserve_" + id
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(145, 12)
			bar.mouse_filter = Control.MOUSE_FILTER_PASS
			var fill := StyleBoxFlat.new()
			fill.bg_color = STATUS_TINTS[id]
			fill.set_corner_radius_all(4)
			bar.add_theme_stylebox_override("fill", fill)
			var background := fill.duplicate() as StyleBoxFlat
			background.bg_color = Color("091520")
			bar.add_theme_stylebox_override("background", background)
			_bars[id] = bar
			column.add_child(bar)
		var detail := UiHelpers.label("", 13)
		detail.add_theme_font_size_override("font_size", 14)
		_details[id] = detail
		column.add_child(detail)
	add_theme_constant_override("h_separation", 6)
	add_theme_constant_override("v_separation", 5)
	SignalBus.language_changed.connect(func(_code): refresh())
	SignalBus.resources_changed.connect(func(_delta, _reason): request_refresh())
	SignalBus.energy_changed.connect(func(_snapshot): request_refresh())
	SignalBus.crew_changed.connect(func(_id): request_refresh())
	SignalBus.sol_ended.connect(func(_sol): request_refresh())
	SignalBus.state_restored.connect(request_refresh)
	refresh()

func configure(dependencies: Dictionary) -> void:
	services = dependencies
	refresh()

func request_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_deferred_refresh")

func _deferred_refresh() -> void:
	_refresh_queued = false
	refresh()

func refresh() -> void:
	if _labels.is_empty():
		return
	var inventory: Dictionary = services["ledger"].get_snapshot() if services.has("ledger") else {}
	var support: Dictionary = services["life_support"].get_status() if services.has("life_support") else {}
	var living := 0
	for member in GameState.data.get("crew", {}).get("members", {}).values():
		if member.get("alive", false):
			living += 1
	for id in ["water", "food", "oxygen"]:
		var amount := maxf(0.0, float(inventory.get(id, 0.0)))
		var rate := living * float(ConfigDB.balance["astronaut"].get("consumption_per_sol", {}).get(id, 1.0))
		if id == "oxygen": rate += maxf(0.0, float(support.get("oxygen_leak_per_sol", 0.0)))
		var sols := amount / rate if rate > 0.0 else 0.0
		_labels[id].text = ("! " if rate > 0.0 and sols < 1.0 else "") + "%s · %.1f" % [_tr(StringName("resource." + id)), amount]
		_bars[id].max_value = RESERVE_SOLS
		_bars[id].value = sols
		_details[id].text = _tr(&"hud.reserve_sols", {"sols": "%.1f" % sols}) if rate > 0.0 else "—"
		_cards[id].tooltip_text = _tr(&"hud.reserve_explanation", {"sols": int(RESERVE_SOLS)})
		_bars[id].tooltip_text = _cards[id].tooltip_text
		_apply_card_style(id, rate > 0.0 and sols < 1.0)
	if services.has("power"):
		var energy: GameContracts.EnergySnapshot = services["power"].get_snapshot()
		var allocated := 0.0
		for row: Dictionary in energy.by_building.values():
			allocated += float(row.get("allocated", 0.0))
		_bars["energy"].value = 100.0 * allocated / energy.demand if energy.demand > 0.0 else 100.0
		_labels["energy"].text = "%s · %.1f / %.1f" % [_tr(&"resource.energy"), energy.generation, energy.demand]
		_details["energy"].text = _tr(&"hud.energy_stored", {"stored": "%.1f" % energy.stored, "capacity": "%.0f" % energy.capacity})
		_cards["energy"].tooltip_text = _tr(&"hud.energy_explanation")
		_bars["energy"].tooltip_text = _cards["energy"].tooltip_text
		_apply_card_style("energy", allocated + 0.001 < energy.demand)
	var leaking := float(support.get("oxygen_leak_per_sol", 0.0)) > 0.0
	_labels["pressure"].text = _tr(&"hud.pressure")
	_details["pressure"].text = "! " + _tr(&"ui.warning") if leaking else _tr(&"ui.normal")
	_cards["pressure"].tooltip_text = _tr(&"hud.pressure_explanation")
	_apply_card_style("pressure", leaking)

func _apply_card_style(id: String, warning: bool) -> void:
	var card: PanelContainer = _cards[id]
	if card.has_meta("warning") and card.get_meta("warning") == warning:
		return
	card.set_meta("warning", warning)
	var accent: Color = Color("f2ae66") if warning else STATUS_TINTS[id]
	var style := StyleBoxFlat.new()
	style.bg_color = Color("4a2b22") if warning else Color("182b38")
	style.border_color = accent.darkened(0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", style)

func _tr(key: StringName, params: Dictionary = {}) -> String:
	return LocalizationDB.translate_key(key, params)
