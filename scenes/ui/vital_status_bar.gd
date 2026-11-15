class_name VitalStatusBar
extends HFlowContainer

var services: Dictionary = {}
var _labels: Dictionary = {}
var _cards: Dictionary = {}
var _refresh_queued := false

const STATUS_TINTS := {
	"water": Color("5b9fe0"),
	"food": Color("8fc878"),
	"pressure": Color("81c9b8"),
}

func _ready() -> void:
	for id in ["water", "food", "pressure"]:
		var card := PanelContainer.new()
		_cards[id] = card
		_apply_card_style(id, false)
		add_child(card)
		var label_node := UiHelpers.label("", 13)
		label_node.add_theme_font_size_override("font_size", 14)
		label_node.autowrap_mode = TextServer.AUTOWRAP_OFF
		label_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_labels[id] = label_node
		card.add_child(label_node)
		card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		card.custom_minimum_size.y = 32.0
	add_theme_constant_override("h_separation", 5)
	add_theme_constant_override("v_separation", 5)
	SignalBus.language_changed.connect(func(_code): refresh())
	SignalBus.resources_changed.connect(func(_delta, _reason): request_refresh())
	SignalBus.energy_changed.connect(func(_snapshot): request_refresh())
	SignalBus.crew_changed.connect(func(_id): request_refresh())
	SignalBus.sol_ended.connect(func(_sol): request_refresh())
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
	var local := get_tree().root.get_node("LocalizationDB")
	for id in ["water", "food"]:
		_labels[id].text = "%s %s" % [local.translate_key(StringName("resource.%s" % id)), String.num(float(inventory.get(id, 0.0)), 1).trim_suffix(".0")]
		_labels[id].tooltip_text = local.translate_key(&"ui.supply_tip")
	var support: Dictionary = services["life_support"].get_status() if services.has("life_support") else {}
	var leaking := float(support.get("oxygen_leak_per_sol", 0.0)) > 0.0
	_labels["pressure"].text = "%s %s" % [local.translate_key(&"hud.pressure"), "! " + local.translate_key(&"ui.warning") if leaking else local.translate_key(&"ui.normal")]
	_labels["pressure"].modulate = Color("ffd29a") if leaking else Color.WHITE
	_apply_card_style("pressure", leaking)

func _apply_card_style(id: String, warning: bool) -> void:
	if not _cards.has(id):
		return
	var accent: Color = Color("e6a85d") if warning else STATUS_TINTS.get(id, Color("93a9bd"))
	var style := StyleBoxFlat.new()
	style.bg_color = accent.darkened(0.78) if warning else Color("182b38")
	style.border_color = accent.darkened(0.25) if warning else accent.darkened(0.48)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	_cards[id].add_theme_stylebox_override("panel", style)

