extends Control

const SECTION_COUNTS := [3, 6, 12]
const NOTABLES_PER_SECTION := [1, 2, 3]
const INNER_RADII := [100.0, 232.0, 368.0]
const OUTER_RADII := [228.0, 364.0, 520.0]
const LAYER_COUNTS := [
	[1, 3, 4, 4, 3, 2, 3], # 20 nodes x 3 = 60; longer four-step notable branches
	[1, 3, 4, 3, 4],    # 15 nodes x 6 = 90; 30 per main third
	[1, 3, 5, 3, 3]     # 15 nodes x 12 = 180; 60 per main third
]

var ring_rotations := [0.0, 0.0, 0.0]
var nodes: Array = []
var branches: Array[Vector2i] = []
var entries: Array = [[], [], []]
var exits: Array = [[], [], []]
var view_offset := Vector2.ZERO
var zoom := 1.0
var dragging_ring := -1
var panning := false
var last_mouse := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_build_tree()
	queue_redraw()

func _build_tree() -> void:
	nodes.clear()
	branches.clear()
	entries = [[], [], []]
	exits = [[], [], []]
	for ring in range(3):
		for section in range(int(SECTION_COUNTS[ring])):
			_build_section(ring, section)

func _build_section(ring: int, section: int) -> void:
	var section_width: float = TAU / float(SECTION_COUNTS[ring])
	var center_angle: float = section * section_width + section_width * 0.5
	var layers: Array = LAYER_COUNTS[ring]
	var section_layers: Array = []
	for layer_index in range(layers.size()):
		var layer_nodes: Array[int] = []
		var count: int = int(layers[layer_index])
		var radial_t: float = float(layer_index) / float(layers.size() - 1)
		for branch_index in range(count):
			var angular_offset := 0.0
			if count > 1:
				var spread := section_width * (0.20 + 0.22 * sin(radial_t * PI))
				if layer_index == layers.size() - 1 and ring < 2:
					spread = section_width * 0.25
				angular_offset = lerpf(-spread, spread, float(branch_index) / float(count - 1))
			var node_id := nodes.size()
			nodes.append({
				"ring": ring,
				"section": section,
				"layer": layer_index,
				"angle": center_angle + angular_offset,
				# Keep nodes inside their annulus instead of placing the first and last
				# layers directly on top of the circular borders.
				"radius": lerpf(INNER_RADII[ring] + 13.0, OUTER_RADII[ring] - 13.0, radial_t),
				"notable": false
			})
			layer_nodes.append(node_id)
		section_layers.append(layer_nodes)
	entries[ring].append(section_layers[0][0])
	for layer_index in range(1, section_layers.size()):
		var parents: Array = section_layers[layer_index - 1]
		var children: Array = section_layers[layer_index]
		if children.size() >= parents.size():
			# Expanding layers visibly fork every existing branch. Afterwards, ensure
			# every child belongs to at least one branch so no passive is isolated.
			for parent_index in range(parents.size()):
				var normalized := 0.5 if parents.size() == 1 else float(parent_index) / float(parents.size() - 1)
				var child_center := normalized * (children.size() - 1)
				var first_child := clampi(floori(child_center), 0, children.size() - 1)
				var second_child := clampi(ceili(child_center + 0.75), 0, children.size() - 1)
				branches.append(Vector2i(parents[parent_index], children[first_child]))
				if second_child != first_child:
					branches.append(Vector2i(parents[parent_index], children[second_child]))
			for child_index in range(children.size()):
				var child_id: int = int(children[child_index])
				var already_connected := branches.any(func(edge: Vector2i): return edge.y == child_id)
				if not already_connected:
					var normalized := 0.5 if children.size() == 1 else float(child_index) / float(children.size() - 1)
					var parent_index := clampi(roundi(normalized * (parents.size() - 1)), 0, parents.size() - 1)
					branches.append(Vector2i(parents[parent_index], child_id))
		else:
			# When branches converge, connect every previous node forward. Connecting
			# only from the children could leave an apparently usable passive as a
			# pointless dead end.
			for parent_index in range(parents.size()):
				var normalized := 0.5 if parents.size() == 1 else float(parent_index) / float(parents.size() - 1)
				var child_index := clampi(roundi(normalized * (children.size() - 1)), 0, children.size() - 1)
				branches.append(Vector2i(parents[parent_index], children[child_index]))
	# The outer ring is deliberately denser: neighbouring intermediate branches
	# are linked so it reads as a developed network rather than twelve sparse
	# fans. The terminal layer is excluded, keeping every notable as a true end.
	if ring == 2:
		for layer_index in range(1, section_layers.size() - 1):
			var layer_nodes: Array = section_layers[layer_index]
			for node_index in range(layer_nodes.size() - 1):
				branches.append(Vector2i(layer_nodes[node_index], layer_nodes[node_index + 1]))
		for layer_index in range(1, section_layers.size() - 1):
			var parents: Array = section_layers[layer_index - 1]
			var children: Array = section_layers[layer_index]
			if parents.size() > 1 and children.size() > 2:
				for child_index in range(1, children.size() - 1, 2):
					var alternate_parent := clampi(roundi(float(child_index - 1) * float(parents.size() - 1) / float(children.size() - 1)), 0, parents.size() - 1)
					var edge := Vector2i(parents[alternate_parent], children[child_index])
					if edge not in branches:
						branches.append(edge)
	_mark_terminal_nodes(section_layers, ring)

func _mark_terminal_nodes(section_layers: Array, ring: int) -> void:
	var terminal_layer: Array = section_layers[-1]
	var notable_count: int = int(NOTABLES_PER_SECTION[ring])
	var notable_positions: Array = []
	if notable_count == 1:
		notable_positions = [terminal_layer.size() / 2]
	elif notable_count == 2:
		notable_positions = [1, terminal_layer.size() - 2]
	else:
		notable_positions = [0, terminal_layer.size() / 2, terminal_layer.size() - 1]
	for terminal_index in range(terminal_layer.size()):
		var node_id: int = int(terminal_layer[terminal_index])
		if terminal_index in notable_positions:
			nodes[node_id].notable = true
		elif ring < 2:
			# Only ordinary terminal nodes can continue into the next ring. Notables
			# are always true leaves and therefore never act as gateways.
			exits[ring].append(node_id)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.014, 0.010, 0.014, 0.99))
	var center := size * 0.5 + view_offset
	_draw_ring_frames(center)
	_draw_internal_branches(center)
	_draw_inter_ring_bridges(center)
	_draw_nodes(center)
	_draw_center(center)
	_draw_help()

func _draw_ring_frames(center: Vector2) -> void:
	for ring in range(3):
		var inner: float = float(INNER_RADII[ring]) * zoom
		var outer: float = float(OUTER_RADII[ring]) * zoom
		draw_arc(center, inner, 0, TAU, 180, Color(0.22, 0.15, 0.08, 0.85), 3.0)
		draw_arc(center, outer, 0, TAU, 220, Color(0.44, 0.30, 0.12, 0.95), 4.0)
		for section in range(int(SECTION_COUNTS[ring])):
			var angle: float = float(ring_rotations[ring]) + section * TAU / float(SECTION_COUNTS[ring])
			var direction := Vector2(cos(angle), sin(angle))
			draw_line(center + direction * inner, center + direction * outer, Color(0.32, 0.22, 0.11, 0.72), 2.0)

func _draw_internal_branches(center: Vector2) -> void:
	for edge in branches:
		var from := _node_position(nodes[edge.x], center)
		var to := _node_position(nodes[edge.y], center)
		_draw_path(from, to, Color(0.46, 0.35, 0.21, 0.88), 2.2)

func _draw_inter_ring_bridges(center: Vector2) -> void:
	# Each section has two exits. They meet the two child sections of the next
	# ring only when both rings are in the same exact 120-degree rotation state.
	for ring in range(2):
		var parent_sections: int = int(SECTION_COUNTS[ring])
		for parent_section in range(parent_sections):
			for child_offset in range(2):
				var exit_index := parent_section * 2 + child_offset
				var child_section := parent_section * 2 + child_offset
				var from_id: int = int(exits[ring][exit_index])
				var to_id: int = int(entries[ring + 1][child_section])
				var from := _node_position(nodes[from_id], center)
				var to := _node_position(nodes[to_id], center)
				var aligned := _rings_aligned(ring, ring + 1)
				_draw_path(from, to, Color(0.82, 0.58, 0.22, 0.95) if aligned else Color(0.22, 0.18, 0.16, 0.38), 3.0 if aligned else 1.5)

func _draw_path(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var middle := (from + to) * 0.5
	var radial_direction := (middle - (size * 0.5 + view_offset)).normalized()
	var tangent := Vector2(-radial_direction.y, radial_direction.x)
	var bend := tangent * minf(12.0 * zoom, from.distance_to(to) * 0.12)
	var points := PackedVector2Array([from, middle + bend, to])
	draw_polyline(points, color, maxf(1.0, width * zoom), true)

func _rings_aligned(first: int, second: int) -> bool:
	return absf(angle_difference(float(ring_rotations[first]), float(ring_rotations[second]))) < 0.015

func _draw_nodes(center: Vector2) -> void:
	for node in nodes:
		var position := _node_position(node, center)
		var notable: bool = bool(node.notable)
		var radius := (9.0 if notable else 4.3) * clampf(zoom, 0.65, 1.35)
		if notable:
			draw_circle(position, radius + 5.0 * zoom, Color(0.16, 0.075, 0.025, 0.99))
			draw_arc(position, radius + 4.0 * zoom, 0, TAU, 28, Color("#e0aa3c"), maxf(2.0, 2.8 * zoom))
		draw_circle(position, radius, Color("#c08a2c") if notable else Color("#6f5129"))
		draw_arc(position, radius, 0, TAU, 18, Color("#f1ce69") if notable else Color("#a98245"), maxf(1.0, 1.5 * zoom))

func _draw_center(center: Vector2) -> void:
	draw_circle(center, 47.0 * zoom, Color(0.07, 0.032, 0.015, 1.0))
	draw_arc(center, 47.0 * zoom, 0, TAU, 48, Color("#d6a23b"), 4.0)
	for section in range(3):
		var angle := section * TAU / 3.0 + TAU / 6.0 + float(ring_rotations[0])
		var entry_id: int = int(entries[0][section])
		_draw_path(center + Vector2(cos(angle), sin(angle)) * 47.0 * zoom, _node_position(nodes[entry_id], center), Color(0.82, 0.58, 0.22, 0.95), 3.0)
	draw_circle(center, 12.0 * zoom, Color("#e6b849"))

func _draw_help() -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(30, 46), "PASSIVE TREE", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("#e3b64e"))
	draw_string(font, Vector2(30, 76), "Drag a ring to rotate · Right drag to move · Mouse wheel to zoom · P/Escape to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#baa47a"))
	draw_string(font, Vector2(30, size.y - 30), "330 passives · 51 notables · Rings rotate in exact 120° steps", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#c9ad73"))

func _node_position(node: Dictionary, center: Vector2) -> Vector2:
	var angle: float = float(node.angle) + float(ring_rotations[int(node.ring)])
	return center + Vector2(cos(angle), sin(angle)) * float(node.radius) * zoom

func _ring_at(screen_position: Vector2) -> int:
	var center := size * 0.5 + view_offset
	var distance := screen_position.distance_to(center) / zoom
	for ring in range(3):
		if distance >= float(INNER_RADII[ring]) - 10.0 and distance <= float(OUTER_RADII[ring]) + 10.0:
			return ring
	return -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom = clampf(zoom * 1.1, 0.55, 1.55)
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom = clampf(zoom / 1.1, 0.55, 1.55)
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging_ring = _ring_at(event.position)
			else:
				_snap_ring(dragging_ring)
				dragging_ring = -1
			last_mouse = event.position
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			panning = event.pressed
			last_mouse = event.position
			accept_event()
	elif event is InputEventMouseMotion:
		if dragging_ring >= 0:
			var center := size * 0.5 + view_offset
			var previous_angle: float = (last_mouse - center).angle()
			var current_angle: float = (event.position - center).angle()
			ring_rotations[dragging_ring] = float(ring_rotations[dragging_ring]) + wrapf(current_angle - previous_angle, -PI, PI)
			last_mouse = event.position
			queue_redraw()
			accept_event()
		elif panning:
			view_offset += event.relative
			last_mouse = event.position
			queue_redraw()
			accept_event()

func _snap_ring(ring: int) -> void:
	if ring < 0:
		return
	var step := TAU / 3.0
	var target := roundf(float(ring_rotations[ring]) / step) * step
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(value: float): ring_rotations[ring] = value; queue_redraw(), float(ring_rotations[ring]), target, 0.22)

func snap_rotations() -> void:
	for ring in range(3):
		var step := TAU / 3.0
		ring_rotations[ring] = roundf(float(ring_rotations[ring]) / step) * step
	queue_redraw()
