class_name MartianWorld
extends Node3D

const BUILDING_MODELS := {
	"base": preload("res://assets/3D assests/3dmodels_markers/main_base.tscn"),
	"isru": preload("res://assets/3D assests/3dmodels_markers/isru.tscn"),
	"greenhouse": preload("res://assets/3D assests/3dmodels_markers/green_house.tscn"),
	"solar_panel": preload("res://assets/3D assests/nuevosmodelos3d/SolarPanel.glb"),
	"battery": preload("res://assets/3D assests/nuevosmodelos3d/Battery.glb"),
	"laboratory": preload("res://assets/3D assests/3dmodels_markers/laboratory.tscn"),
	"mine": preload("res://assets/3D assests/nuevosmodelos3d/Mine.glb"),
	"refinery": preload("res://assets/3D assests/3dmodels_markers/refinery.tscn"),
	"printer_3d": preload("res://assets/3D assests/3dmodels_markers/3d_printer.tscn"),
	"reactor": preload("res://assets/3D assests/nuevosmodelos3d/NuclearReactor.glb"),
	"landing_pad": preload("res://assets/3D assests/nuevosmodelos3d/LandingPad.glb")
}
const TUNNEL_STRAIGHT: PackedScene = preload("res://assets/3D assests/3dmodels_markers/tunnel_straight_2.tscn")
const TUNNEL_CORNER: PackedScene = preload("res://assets/3D assests/3dmodels_markers/tunnel_corner.tscn")
const TUNNEL_T: PackedScene = preload("res://assets/3D assests/3dmodels_markers/tunnel_intersection_t.tscn")
const TUNNEL_CROSS: PackedScene = preload("res://assets/3D assests/3dmodels_markers/tunnel_intersection.tscn")
const WEATHER_EFFECTS := preload("res://scenes/world/weather_effects.gd")
const CELL_SIZE := 2.0

signal target_selected(target_id: StringName)
signal placement_requested(request: GameContracts.PlacementRequest)

@onready var camera_rig: CameraRig = $CameraRig
@onready var preview: PlacementPreview = $PlacementPreview
@onready var terrain_root: Node3D = $Terrain
@onready var buildings_root: Node3D = $Buildings
var building_service: BuildingService
var grid_service: GridService
var selected_id: StringName = &""
var placement_type: StringName = &""
var placement_rotation_quarters := 0
var _last_visual_signature := ""
var _crew_visuals: Dictionary = {}
var _rocket_visuals: Dictionary = {}
var weather: WEATHER_EFFECTS

func _ready() -> void:
	# Each world owns its environment; temporary weather cannot leak to another instance.
	$WorldEnvironment.environment = $WorldEnvironment.environment.duplicate()
	# Filmic tonemapping adds highlight rolloff and midtone separation to the
	# low-poly habitat and regolith materials without changing their authored colors.
	$WorldEnvironment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var weather_layer := CanvasLayer.new()
	weather_layer.name = "WeatherLayer"
	weather_layer.layer = 0
	add_child(weather_layer)
	weather = WEATHER_EFFECTS.new()
	weather.name = "WeatherEffects"
	weather_layer.add_child(weather)
	visibility_changed.connect(_sync_weather)
	SignalBus.event_changed.connect(func(_id, _phase): _sync_weather())
	SignalBus.state_restored.connect(rebuild_from_state)
	SignalBus.building_changed.connect(_on_building_changed)
	SignalBus.energy_changed.connect(_on_energy_changed)
	SignalBus.research_changed.connect(_on_research_changed)
	SignalBus.crew_changed.connect(func(_id): _refresh_entities())
	SignalBus.rocket_changed.connect(func(_id, _change): _refresh_entities())
	SignalBus.tick_advanced.connect(func(_dt): _refresh_entities())
	rebuild_from_state()
	_sync_daylight()

func _process(_delta: float) -> void:
	_sync_weather()
	_sync_daylight()

func _sync_weather() -> void:
	if weather == null or camera_rig == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var region := camera_rig.map_view
	weather.sync_from_events(GameState.data.get("events", {}),
		Rect2(region.position * viewport_size, region.size * viewport_size), is_visible_in_tree())

func _sync_daylight() -> void:
	if not is_node_ready():
		return
	var phase := float(GameClock.get_cycle_snapshot()["phase"])
	var sunlight := clampf(sin(phase * TAU) * 5.0, 0.0, 1.0)
	var sun: DirectionalLight3D = $Sun
	# Keep enough fill light on the colony when the sun is below the horizon.
	sun.light_energy = lerpf(0.1, 0.252, sunlight)
	sun.light_color = Color("a9c5ef").lerp(Color("fff0d3"), sunlight)
	sun.rotation_degrees.x = -10.0 - 160.0 * minf(1.0, phase * 2.0) if phase < 0.5 else -45.0
	sun.shadow_enabled = sunlight > 0.1
	var environment: Environment = $WorldEnvironment.environment
	environment.background_color = Color("080f24").lerp(Color("503426"), sunlight)
	environment.ambient_light_color = Color("809fce").lerp(Color("d1d1e6"), sunlight)
	# Keep the colony readable at night, especially on dim displays; the blue
	# ambient fill is a gameplay aid, while the direct sun and shadows fade.
	environment.ambient_light_energy = lerpf(0.72, 0.48, sunlight)
	var dust := weather != null and weather.dust_active
	var flare := weather != null and weather.flare_active
	# A faint rusty haze softens the horizon in clear weather; dust storms deepen it.
	environment.fog_enabled = true
	environment.fog_density = 0.0006
	environment.fog_light_color = Color("796452").lerp(Color("b0804c"), sunlight)
	environment.fog_light_energy = lerpf(0.2, 0.4, sunlight)
	if dust:
		environment.fog_density = 0.008
		environment.fog_light_color = Color("796452").lerp(Color("b0804c"), sunlight)
		environment.fog_light_energy = lerpf(0.25, 0.55, sunlight)
		sun.light_energy *= 0.55
		environment.background_color = environment.background_color.lerp(Color("745037"), 0.5)
	if flare:
		sun.light_color = sun.light_color.lerp(Color("ffb579"), 0.55)
		environment.ambient_light_color = environment.ambient_light_color.lerp(Color("e8ac91"), 0.22)

func configure(buildings: BuildingService, grid: GridService) -> void:
	building_service = buildings
	grid_service = grid
	rebuild_from_state()

func rebuild_from_state() -> void:
	_sync_weather()
	if terrain_root == null or buildings_root == null:
		return
	_clear(terrain_root)
	_clear(buildings_root)
	if GameState.data.is_empty() or building_service == null or grid_service == null:
		return
	var sector_size := int(ConfigDB.balance["map"]["scan_sector_size"])
	var terrain_shader := Shader.new()
	terrain_shader.code = "shader_type spatial; render_mode diffuse_burley; uniform vec4 base_color : source_color; uniform float sector_size = 8.0; void fragment() { vec2 grid = UV * sector_size; float check = mod(floor(grid.x) + floor(grid.y), 2.0); float grain = fract(sin(dot(floor(grid * 6.0), vec2(12.9898, 78.233))) * 43758.5453); ALBEDO = base_color.rgb * mix(0.985, 1.015, check) * mix(0.98, 1.02, grain); ROUGHNESS = 1.0; }"
	var rock_mesh := SphereMesh.new()
	rock_mesh.radial_segments = 5
	rock_mesh.rings = 3
	var rock_material := StandardMaterial3D.new()
	rock_material.albedo_color = Color("8c5541")
	rock_material.roughness = 1.0
	rock_mesh.material = rock_material
	for key in GameState.data.get("world", {}).get("revealed", {}):
		var parts := String(key).split(",")
		if parts.size() != 2:
			continue
		var sector := Vector2i(int(parts[0]), int(parts[1]))
		var tile := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(sector_size * CELL_SIZE, 0.2, sector_size * CELL_SIZE)
		tile.mesh = mesh
		# Sector slabs meet at y=0, which is the shared construction surface.
		tile.position = Vector3((sector.x + 0.5) * sector_size * CELL_SIZE, -0.1,
			(sector.y + 0.5) * sector_size * CELL_SIZE)
		var mat := ShaderMaterial.new()
		mat.shader = terrain_shader
		# Deposits are marked at their actual cells below; tinting a whole sector
		# from its first cell creates a misleading, oversized resource patch.
		mat.set_shader_parameter("base_color", _terrain_color(&"sterile", sector))
		# The visible checker stays at one world meter even though build cells are 2 m.
		mat.set_shader_parameter("sector_size", float(sector_size) * CELL_SIZE)
		tile.material_override = mat
		terrain_root.add_child(tile)
		_add_sector_rocks(sector, sector_size, rock_mesh)
	_add_resource_nodes(sector_size)
	for id in GameState.data.get("buildings", {}).get("instances", {}):
		_add_building_visual(StringName(id))
	if not String(selected_id).is_empty() and building_service.get_status(selected_id) == null:
		selected_id = &""
		target_selected.emit(selected_id)
	_last_visual_signature = _visual_signature()
	_refresh_entities()

func _add_resource_nodes(sector_size: int) -> void:
	# Read the same revealed, per-cell terrain used by placement validation. This
	# keeps scanned deposits visible and prevents unrevealed patches from leaking.
	var node_root := Node3D.new()
	node_root.name = "ResourceNodes"
	terrain_root.add_child(node_root)
	var materials := {
		"aquifer": _resource_node_material(Color("555957")),
		"iron_regolith": _resource_node_material(Color("633f32"))
	}
	var pebble_mesh := SphereMesh.new()
	pebble_mesh.radial_segments = 6
	pebble_mesh.rings = 3
	for key in GameState.data.get("world", {}).get("revealed", {}):
		var parts := String(key).split(",")
		if parts.size() != 2:
			continue
		var sector := Vector2i(int(parts[0]), int(parts[1]))
		for y in range(sector.y * sector_size, (sector.y + 1) * sector_size):
			for x in range(sector.x * sector_size, (sector.x + 1) * sector_size):
				var terrain := grid_service.terrain_at(Vector2i(x, y))
				if not materials.has(String(terrain)):
					continue
				var random := RandomNumberGenerator.new()
				random.seed = absi(x * 73856093 ^ y * 19349663) + 1
				var marker := MeshInstance3D.new()
				marker.name = "%s_%d_%d" % [terrain, x, y]
				marker.mesh = pebble_mesh
				var width := random.randf_range(0.32, 0.52)
				marker.scale = Vector3(width, random.randf_range(0.09, 0.15), width * random.randf_range(0.65, 1.1))
				marker.position = Vector3((float(x) + random.randf_range(0.3, 0.7)) * CELL_SIZE,
					0.015, (float(y) + random.randf_range(0.3, 0.7)) * CELL_SIZE)
				marker.rotation.y = random.randf_range(0.0, TAU)
				marker.material_override = materials[String(terrain)]
				node_root.add_child(marker)

func _resource_node_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material

func _add_sector_rocks(sector: Vector2i, sector_size: int, rock_mesh: Mesh) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = absi(sector.x * 73856093 ^ sector.y * 19349663) + 1
	var instances: Dictionary = GameState.data.get("buildings", {}).get("instances", {})
	for index in 8:
		var cell := sector * sector_size + Vector2i(random.randi_range(0, sector_size - 1), random.randi_range(0, sector_size - 1))
		var occupied := false
		for item in instances.values():
			if grid_service._rect(item).grow(1).has_point(cell):
				occupied = true
				break
		if occupied:
			continue
		var rock := MeshInstance3D.new()
		rock.mesh = rock_mesh
		var width := random.randf_range(0.22, 0.48)
		rock.scale = Vector3(width, width * random.randf_range(0.35, 0.6), width * random.randf_range(0.65, 1.15))
		rock.position = Vector3((cell.x + random.randf_range(0.25, 0.75)) * CELL_SIZE,
			rock.scale.y * 0.35, (cell.y + random.randf_range(0.25, 0.75)) * CELL_SIZE)
		rock.rotation.y = random.randf_range(0.0, TAU)
		terrain_root.add_child(rock)

func _refresh_entities() -> void:
	if not is_node_ready():
		return
	var members: Dictionary = GameState.data.get("crew", {}).get("members", {})
	for id in _crew_visuals.keys():
		if not members.has(id):
			_crew_visuals[id].queue_free()
			_crew_visuals.erase(id)
	var index := 0
	for id in members:
		if not _crew_visuals.has(id):
			var visual: Node3D = preload("res://scenes/crew/astronaut.tscn").instantiate()
			add_child(visual)
			_crew_visuals[id] = visual
		var member: Dictionary = members[id]
		var task: Dictionary = GameState.data.get("crew", {}).get("tasks", {}).get(member.get("task_id", ""), {})
		var target: Dictionary = GameState.data.get("buildings", {}).get("instances", {}).get(task.get("target_id", "base_1"), {})
		var origin: Array = target.get("origin", [14, 14])
		_crew_visuals[id].position = Vector3((float(origin[0]) + 0.25 + (index % 2) * 0.5) * CELL_SIZE,
			1.0, (float(origin[1]) + 0.25 + (index / 2) * 0.5) * CELL_SIZE)
		_crew_visuals[id].set_crew_state(member)
		index += 1
	var plans: Dictionary = GameState.data.get("rockets", {}).get("plans", {})
	for id in _rocket_visuals.keys():
		if not plans.has(id):
			_rocket_visuals[id].queue_free()
			_rocket_visuals.erase(id)
	for id in plans:
		if not _rocket_visuals.has(id):
			var visual: Node3D = preload("res://scenes/rockets/rocket.tscn").instantiate()
			add_child(visual)
			_rocket_visuals[id] = visual
		var zone: Array = plans[id].get("zone", [])
		if zone.size() == 4:
			_rocket_visuals[id].position = Vector3((float(zone[0]) + float(zone[2]) * 0.5) * CELL_SIZE,
				0.0, (float(zone[1]) + float(zone[3]) * 0.5) * CELL_SIZE)
		_rocket_visuals[id].set_rocket_state(plans[id])

func focus_target(target_id: StringName) -> bool:
	var status := building_service.get_status(target_id) if building_service != null else null
	if status == null:
		return false
	var item: Dictionary = GameState.data["buildings"]["instances"][String(target_id)]
	var origin: Array = item["origin"]
	var size: Array = item["size"]
	camera_rig.focus_cell(Vector2i(int(origin[0]) + int(size[0]) / 2, int(origin[1]) + int(size[1]) / 2))
	selected_id = target_id
	target_selected.emit(target_id)
	return true

func begin_placement(type_id: StringName) -> void:
	placement_type = type_id
	placement_rotation_quarters = 0

func cancel_placement() -> void:
	placement_type = &""
	placement_rotation_quarters = 0
	preview.hide()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and not String(placement_type).is_empty():
		placement_rotation_quarters = (placement_rotation_quarters + 1) % 4
		_update_placement_preview(get_viewport().get_mouse_position())
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_rig.zoom_by(-3.0)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_rig.zoom_by(3.0)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_placement()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var cell := _screen_cell(event.position)
			if cell == Vector2i(-1, -1):
				return
			if not String(placement_type).is_empty():
				placement_requested.emit(GameContracts.PlacementRequest.new(placement_type, cell, placement_rotation_quarters))
			else:
				selected_id = _building_at(cell)
				target_selected.emit(selected_id)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and not String(placement_type).is_empty() and building_service != null:
		_update_placement_preview(event.position)

func _update_placement_preview(screen_position: Vector2) -> void:
	var cell := _screen_cell(screen_position)
	var definition := BuildingDefinition.from_balance(placement_type)
	if cell == Vector2i(-1, -1) or definition == null:
		preview.hide()
		return
	var request := GameContracts.PlacementRequest.new(placement_type, cell, placement_rotation_quarters)
	var quote := building_service.validate_placement(request)
	var offset_data: Array = quote.params.get("offset_m", [0.0, 0.0])
	var offset := Vector2(float(offset_data[0]), float(offset_data[1]))
	preview.show_at(cell, definition.footprint, quote.ok, placement_rotation_quarters, offset)

func _screen_cell(screen: Vector2) -> Vector2i:
	var camera: Camera3D = camera_rig.camera
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if absf(direction.y) < 0.00001:
		return Vector2i(-1, -1)
	var distance := -origin.y / direction.y
	if distance < 0.0:
		return Vector2i(-1, -1)
	var point := origin + direction * distance
	var cell := Vector2i(floori(point.x / CELL_SIZE), floori(point.z / CELL_SIZE))
	return cell if grid_service != null and grid_service.is_revealed(cell) else Vector2i(-1, -1)

func _building_at(cell: Vector2i) -> StringName:
	for id in GameState.data.get("buildings", {}).get("instances", {}):
		if grid_service._rect(GameState.data["buildings"]["instances"][id]).has_point(cell):
			return StringName(id)
	return &""

func _add_building_visual(id: StringName) -> void:
	var item: Dictionary = GameState.data["buildings"]["instances"][String(id)]
	var status := building_service.get_status(id)
	var origin: Array = item["origin"]
	var size: Array = item["size"]
	var building_type := String(item["type"])
	var packed_scene: PackedScene = BUILDING_MODELS.get(building_type)
	var rotation_y := 0.0
	var tunnel_model: Dictionary = {}
	if building_type == "tunnel":
		tunnel_model = _tunnel_model(item)
		packed_scene = tunnel_model["scene"] as PackedScene
		rotation_y = float(tunnel_model["rotation"])
	elif packed_scene != null and not packed_scene.resource_path.contains("nuevosmodelos3d"):
		rotation_y = float(posmod(int(item.get("rotation_quarters", 0)), 4)) * PI * 0.5
	if packed_scene != null:
		var model := packed_scene.instantiate() as Node3D
		if model != null:
			model.name = String(id)
			model.rotation.y = rotation_y
			buildings_root.add_child(model)
			if _fit_model_to_footprint(model, origin, size, building_type == "tunnel", item.get("offset_m", [0.0, 0.0])):
				if building_type == "tunnel":
					_add_tunnel_caps(model, tunnel_model, item)
				_apply_model_status(model, status, item)
				return
			model.queue_free()
	_add_fallback_building_visual(id, item, status, origin, size)

func _fit_model_to_footprint(model: Node3D, origin: Array, size: Array, tunnel: bool = false,
		offset_data: Variant = [0.0, 0.0]) -> bool:
	var bounds := _model_bounds(model)
	if bounds.size.x <= 0.001 or bounds.size.z <= 0.001:
		return false
	var offset := Vector2.ZERO
	if offset_data is Array and offset_data.size() >= 2:
		offset = Vector2(float(offset_data[0]), float(offset_data[1]))
	if tunnel:
		# Marker scenes author tunnel endpoints exactly one meter from their root;
		# a logical cell is two meters wide, so preserve the authored scale and frame.
		model.scale = Vector3.ONE
		model.position = Vector3((float(origin[0]) + 0.5) * CELL_SIZE + offset.x,
			0.006, (float(origin[1]) + 0.5) * CELL_SIZE + offset.y)
		return true
	if not model.find_children("*", "Marker3D", true, false).is_empty():
		# The marker wrappers define the physical connection points relative to a
		# model centered on its logical footprint. Keep that authored coordinate
		# frame intact so port-bearing assets meet tunnels at their marker locations.
		# Decorative mesh bounds can extend below the building's authored ground
		# plane, so place the wrapper origin on the terrain instead of grounding the
		# lowest decorative mesh.
		model.scale = Vector3.ONE
		model.position = Vector3((float(origin[0]) + float(size[0]) * 0.5) * CELL_SIZE + offset.x,
			0.006, (float(origin[1]) + float(size[1]) * 0.5) * CELL_SIZE + offset.y)
		return true
	var target_width := maxf(0.5, float(size[0]) * CELL_SIZE * 0.96)
	var target_depth := maxf(0.5, float(size[1]) * CELL_SIZE * 0.96)
	var scale_factor := minf(target_width / bounds.size.x, target_depth / bounds.size.z)
	if not is_finite(scale_factor) or scale_factor <= 0.0:
		return false
	model.scale = Vector3.ONE * scale_factor
	var local_center := Vector3(bounds.position.x + bounds.size.x * 0.5, 0.0,
		bounds.position.z + bounds.size.z * 0.5)
	var center_offset := model.transform.basis * local_center
	model.position = Vector3((float(origin[0]) + float(size[0]) * 0.5) * CELL_SIZE - center_offset.x,
		0.006 - _model_ground_y(model, bounds) * scale_factor,
		(float(origin[1]) + float(size[1]) * 0.5) * CELL_SIZE - center_offset.z)
	return true

func _model_ground_y(model: Node3D, bounds: AABB) -> float:
	if model.scene_file_path.ends_with("/LandingPad.glb"):
		# Its decorative rock extends below the platform. Anchor the platform itself,
		# rather than lifting the entire pad to place the bottom of that rock at ground.
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			if String(mesh.name).replace(".", "").replace("_", "") == "Cylinder009":
				var local: AABB = (model.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
				return local.position.y
	return bounds.position.y

func _model_bounds(model: Node3D) -> AABB:
	var combined := AABB()
	var has_point := false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var mesh_bounds := mesh_instance.get_aabb()
		for x in range(2):
			for y in range(2):
				for z in range(2):
					var corner := mesh_bounds.position + Vector3(
						mesh_bounds.size.x * float(x), mesh_bounds.size.y * float(y),
						mesh_bounds.size.z * float(z))
					var local_point := model.to_local(mesh_instance.to_global(corner))
					if has_point:
						combined = combined.expand(local_point)
					else:
						combined = AABB(local_point, Vector3.ZERO)
						has_point = true
	return combined

func _apply_model_status(model: Node3D, status: BuildingStatus, item: Dictionary) -> void:
	var tint := Color(0.0, 0.0, 0.0, 0.0)
	if status.condition == &"breached" or status.condition == &"destroyed" or item.get("crop") == "dead":
		tint = Color(0.85, 0.12, 0.08, 0.42)
	elif item.get("crop") == "wilting":
		tint = Color(0.9, 0.55, 0.08, 0.35)
	elif status.demand > 0.0 and not status.powered:
		tint = Color(0.015, 0.02, 0.04, 0.48)
	if tint.a <= 0.0:
		return
	var overlay := StandardMaterial3D.new()
	overlay.albedo_color = tint
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_overlay = overlay

func _tunnel_model(item: Dictionary) -> Dictionary:
	var connections := _tunnel_connections(item)
	var scene: PackedScene = TUNNEL_STRAIGHT
	if connections.size() >= 4:
		scene = TUNNEL_CROSS
	elif connections.size() == 3:
		scene = TUNNEL_T
	elif connections.size() == 2:
		if connections[0] + connections[1] == Vector2i.ZERO:
			scene = TUNNEL_STRAIGHT
		else:
			scene = TUNNEL_CORNER
	var base_directions := _scene_port_directions(scene)
	var turns := _tunnel_rotation_to_match(base_directions, connections)
	return {"scene": scene, "rotation": float(turns) * PI * 0.5, "ports": base_directions, "connections": connections}

func _scene_port_directions(scene: PackedScene) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var instance := scene.instantiate()
	for node in instance.find_children("*", "Marker3D", true, false):
		var marker := node as Marker3D
		var direction := Vector2i(roundi(marker.position.x), roundi(marker.position.z))
		if direction != Vector2i.ZERO and not result.has(direction):
			result.append(direction)
	instance.free()
	return result

func _add_tunnel_caps(model: Node3D, description: Dictionary, item: Dictionary) -> void:
	for port: Vector2i in description["ports"]:
		var rotated := model.basis * Vector3(port.x, 0.0, port.y)
		var direction := Vector2i(roundi(rotated.x), roundi(rotated.z))
		if description["connections"].has(direction) and not bool(item.get("isolated", false)):
			continue
		var cap := MeshInstance3D.new()
		cap.name = "SealedPort_%d_%d" % [port.x, port.y]
		var disk := CylinderMesh.new()
		disk.top_radius = 0.34
		disk.bottom_radius = 0.34
		disk.height = 0.025
		cap.mesh = disk
		cap.position = Vector3(port.x, 0.30, port.y)
		cap.rotation_degrees = Vector3(90.0, 0.0, 0.0) if port.x == 0 else Vector3(0.0, 0.0, 90.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("cf8f42") if bool(item.get("isolated", false)) else Color("708594")
		cap.material_override = material
		model.add_child(cap)

func _tunnel_connections(tunnel_item: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var instances: Dictionary = GameState.data.get("buildings", {}).get("instances", {})
	var origin_data: Array = tunnel_item["origin"]
	var origin := Vector2i(int(origin_data[0]), int(origin_data[1]))
	for direction in directions:
		var neighbor := origin + direction
		for id in instances:
			var item: Dictionary = instances[id]
			if not TunnelNetwork.has_tunnel_port(item):
				continue
			if grid_service._rect(item).has_point(neighbor) and TunnelNetwork.ports_meet(tunnel_item, origin, item, direction):
				result.append(direction)
				break
	return result

func _tunnel_rotation_to_match(base: Array[Vector2i], desired: Array[Vector2i]) -> int:
	if desired.is_empty():
		return 0
	for turns in range(4):
		var rotated: Array[Vector2i] = []
		for direction in base:
			var value := direction
			for _turn in range(turns):
				value = Vector2i(value.y, -value.x)
			rotated.append(value)
		var matches_all := true
		for wanted in desired:
			if not rotated.has(wanted):
				matches_all = false
				break
		if matches_all and rotated.size() >= desired.size():
			return turns
	return 0

func _add_fallback_building_visual(id: StringName, item: Dictionary, status: BuildingStatus,
		origin: Array, size: Array) -> void:
	var height := 0.25 if item["type"] in ["solar_panel", "tunnel", "landing_pad"] else (1.7 if item["type"] == "reactor" else 0.9)
	var visual := MeshInstance3D.new()
	visual.name = String(id)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(float(size[0]) * CELL_SIZE * 0.9, height, float(size[1]) * CELL_SIZE * 0.9)
	visual.mesh = mesh
	visual.position = Vector3((float(origin[0]) + float(size[0]) * 0.5) * CELL_SIZE,
		height * 0.5, (float(origin[1]) + float(size[1]) * 0.5) * CELL_SIZE)
	var material := StandardMaterial3D.new()
	material.albedo_color = _building_color(String(item["type"]))
	if status.condition == &"breached" or status.condition == &"destroyed" or item.get("crop") == "dead":
		material.albedo_color = Color(0.75, 0.12, 0.1)
	elif item.get("crop") == "wilting":
		material.albedo_color = Color(0.72, 0.52, 0.12)
	elif status.demand > 0.0 and not status.powered:
		material.albedo_color = material.albedo_color.darkened(0.55)
	visual.material_override = material
	buildings_root.add_child(visual)

func _building_color(kind: String) -> Color:
	match kind:
		"base": return Color(0.76, 0.82, 0.89)
		"isru": return Color(0.18, 0.65, 0.83)
		"greenhouse": return Color(0.25, 0.76, 0.38)
		"reactor": return Color(0.82, 0.68, 0.25)
		"solar_panel": return Color(0.13, 0.3, 0.7)
		"tunnel": return Color(0.55, 0.6, 0.64)
		"mine": return Color(0.52, 0.42, 0.33)
		"battery": return Color(0.3, 0.7, 0.74)
		_: return Color(0.68, 0.66, 0.61)

func _terrain_color(terrain: StringName, sector: Vector2i) -> Color:
	if terrain == &"aquifer":
		return Color(0.39, 0.36, 0.34)
	if terrain == &"iron_regolith":
		return Color(0.62, 0.43, 0.27)
	return Color(0.58, 0.29, 0.18)

func _visual_signature() -> String:
	if building_service == null or GameState.data.is_empty():
		return ""
	var chunks: Array[String] = []
	for id in GameState.data.get("buildings", {}).get("instances", {}):
		var status := building_service.get_status(StringName(id))
		chunks.append("%s:%s:%s:%s" % [id, status.powered, status.condition, status.modifiers.get("crop", "")])
	return "|".join(chunks)

func _on_energy_changed(_snapshot: GameContracts.EnergySnapshot) -> void:
	var signature := _visual_signature()
	if signature != _last_visual_signature:
		rebuild_from_state()

func _on_research_changed(_tech_id: StringName, change: StringName) -> void:
	if change == &"sector_revealed":
		rebuild_from_state()

func _on_building_changed(_id: StringName, _change: StringName) -> void:
	rebuild_from_state()

func _clear(root: Node3D) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()
