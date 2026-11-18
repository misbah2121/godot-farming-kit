@tool
@icon("res://addons/farming_kit/icons/farm_sprinkler.svg")
class_name FarmSprinkler
extends Node2D
## Waters nearby tilled soil at the start of every day.
## Place it anywhere; it works out its own cell from its position.

## Which cells around the sprinkler get water.
enum Pattern {
	CROSS, ## The 4 cells up, down, left, right.
	SQUARE, ## The 8 cells around it.
	BIG_SQUARE, ## The 24 cells in a 5x5 square.
}

## Emitted after watering, with the cells that got water.
signal sprayed(cells: Array[Vector2i])

## The field this sprinkler waters.
@export var field: FarmField:
	set(value):
		if field != null and not Engine.is_editor_hint() and field.day_processed.is_connected(spray):
			field.day_processed.disconnect(spray)
		field = value
		if is_inside_tree() and not Engine.is_editor_hint():
			_connect_field()
		queue_redraw()
@export var pattern: Pattern = Pattern.CROSS:
	set(value):
		pattern = value
		queue_redraw()
## Optional sprite. Without it a small round marker is drawn.
@export var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
## Show the watered area while editing the scene.
@export var show_range_in_editor: bool = true


func _ready() -> void:
	if not Engine.is_editor_hint():
		_connect_field()


## The cell this sprinkler stands on.
func get_cell() -> Vector2i:
	if field == null:
		return Vector2i.ZERO
	# Same maths as FarmField.world_to_cell, so it also works in the editor.
	var local := field.to_local(global_position)
	var size: Vector2i = field.tile_size
	return Vector2i(floori(local.x / size.x), floori(local.y / size.y))


## Cells covered by this sprinkler.
func get_target_cells() -> Array[Vector2i]:
	var center := get_cell()
	var result: Array[Vector2i] = []
	for offset in _offsets():
		result.append(center + offset)
	return result


## Waters the covered cells now. Called automatically every new day.
func spray() -> void:
	if field == null:
		return
	var wet: Array[Vector2i] = []
	for cell in get_target_cells():
		if field.can_water(cell) == FarmField.Result.OK:
			field.water(cell)
			wet.append(cell)
	sprayed.emit(wet)


func _connect_field() -> void:
	if field != null and not field.day_processed.is_connected(spray):
		field.day_processed.connect(spray)


func _offsets() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	match pattern:
		Pattern.CROSS:
			result.assign([Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT])
		Pattern.SQUARE, Pattern.BIG_SQUARE:
			var r := 1 if pattern == Pattern.SQUARE else 2
			for y in range(-r, r + 1):
				for x in range(-r, r + 1):
					if x != 0 or y != 0:
						result.append(Vector2i(x, y))
	return result


func _draw() -> void:
	if texture != null:
		draw_texture(texture, -texture.get_size() * 0.5)
	else:
		draw_circle(Vector2.ZERO, 4.0, Color(0.55, 0.6, 0.65))
		draw_circle(Vector2(0, -1), 2.0, Color(0.35, 0.65, 1.0))
	if Engine.is_editor_hint() and show_range_in_editor and field != null:
		var size := Vector2(field.tile_size)
		var center_local := to_local(field.to_global(Vector2(get_cell()) * size + size * 0.5))
		for offset in _offsets():
			var rect := Rect2(center_local + Vector2(offset) * size - size * 0.5, size)
			draw_rect(rect, Color(0.3, 0.6, 1.0, 0.18))
			draw_rect(rect, Color(0.3, 0.6, 1.0, 0.5), false, 1.0)
