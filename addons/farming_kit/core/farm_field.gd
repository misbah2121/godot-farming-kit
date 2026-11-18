@icon("res://addons/farming_kit/icons/farm_field.svg")
class_name FarmField
extends Node2D
## A grid of farmland. Handles tilling, watering, planting, growth, harvest,
## and save/load. It draws the soil and the crop sprites by itself, so it works
## with any tileset, or with no tileset at all.
##
## Cells are grid coordinates in this node's local space:
## cell (0, 0) starts at this node's position, each cell is [member tile_size].
## Use [method world_to_cell] to convert a mouse or player position.
##
## Every action returns true or false. When it fails, [signal action_failed]
## tells you why, so you can show your own message in any language.

## Why an action failed.
enum Result {
	OK,
	OUTSIDE_FIELD, ## The cell is outside [member area].
	ALREADY_TILLED, ## Trying to till soil that is already tilled.
	NOT_TILLED, ## The action needs tilled soil.
	ALREADY_WATERED, ## The soil is already wet today.
	OCCUPIED, ## There is already a crop here.
	EMPTY, ## There is no crop here.
	WRONG_SEASON, ## The crop does not grow in the current season.
	NOT_RIPE, ## The crop is not ready to harvest yet.
	INVALID_CROP, ## The FarmCrop is null or has no textures.
}

signal tilled(cell: Vector2i)
signal untilled(cell: Vector2i)
signal watered(cell: Vector2i)
signal planted(cell: Vector2i, crop: FarmCrop)
## A crop moved to a new visual stage.
signal grew(cell: Vector2i, crop: FarmCrop, stage: int)
## A crop became ready to harvest. [param rare] is true for rare harvests.
signal ripened(cell: Vector2i, crop: FarmCrop, rare: bool)
signal harvested(cell: Vector2i, crop: FarmCrop, amount: int, rare: bool)
## A crop died because the season changed.
signal withered(cell: Vector2i, crop: FarmCrop)
## Emitted at the end of [method advance_day], after the soil dried.
## Sprinklers water here, so their water counts for the new day.
signal day_processed
signal action_failed(cell: Vector2i, result: Result)

## Size of one cell in pixels.
@export var tile_size: Vector2i = Vector2i(16, 16)
## Cells that can be farmed. A size of 0 means any cell.
@export var area: Rect2i = Rect2i(0, 0, 8, 6)
## Connect to the FarmCalendar autoload and grow every new day.
@export var follow_calendar: bool = true
## Every crop that can appear in this field. Needed to load saved games.
@export var crop_library: Array[FarmCrop] = []
## Tilled soil without a crop turns back to normal ground after this many dry
## days. 0 = never.
@export_range(0, 365) var revert_empty_soil_days: int = 0
## Fixed random seed for rare harvests and yields (0 = random every run).
@export var random_seed: int = 0

@export_group("Soil Look")
## Draw the tilled soil. Turn off if you paint soil on your own TileMap
## (listen to the tilled/watered signals instead).
@export var draw_soil: bool = true
@export var dry_soil_texture: Texture2D
@export var wet_soil_texture: Texture2D
@export var dry_soil_color: Color = Color(0.55, 0.38, 0.24)
@export var wet_soil_color: Color = Color(0.36, 0.23, 0.14)
## Colour multiplier for rare crops.
@export var rare_modulate: Color = Color(1.3, 1.2, 0.55)

## Overrides the season (useful for tests or games without a calendar).
## Empty = use FarmCalendar, or treat every season as valid if there is none.
var season_override: String = ""


class Plot:
	var watered: bool = false
	var crop: FarmCrop = null
	var days_grown: int = 0
	var stage: int = 0
	var rare: bool = false
	var rare_rolled: bool = false
	var dry_days: int = 0
	var sprite: Sprite2D = null


var _plots: Dictionary = {}  # Vector2i -> Plot
var _crops_root: Node2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	_crops_root = Node2D.new()
	_crops_root.name = "Crops"
	_crops_root.y_sort_enabled = true
	add_child(_crops_root, false, Node.INTERNAL_MODE_FRONT)
	var calendar = _calendar()
	if follow_calendar and calendar != null:
		calendar.day_started.connect(_on_calendar_day_started)


# ---------------------------------------------------------------------------
# Coordinates
# ---------------------------------------------------------------------------

## Cell under a global position (mouse, player, ...).
func world_to_cell(global_pos: Vector2) -> Vector2i:
	var local := to_local(global_pos)
	return Vector2i(floori(local.x / tile_size.x), floori(local.y / tile_size.y))


## Global position of the centre of a cell.
func cell_to_world(cell: Vector2i) -> Vector2:
	return to_global(Vector2(cell * tile_size) + Vector2(tile_size) * 0.5)


## True if the cell is inside [member area].
func is_in_area(cell: Vector2i) -> bool:
	return area.size == Vector2i.ZERO or area.has_point(cell)


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func is_tilled(cell: Vector2i) -> bool:
	return _plots.has(cell)


func is_watered(cell: Vector2i) -> bool:
	return _plots.has(cell) and (_plots[cell] as Plot).watered


func has_crop(cell: Vector2i) -> bool:
	return _plots.has(cell) and (_plots[cell] as Plot).crop != null


func get_crop(cell: Vector2i) -> FarmCrop:
	return (_plots[cell] as Plot).crop if _plots.has(cell) else null


func is_ripe(cell: Vector2i) -> bool:
	if not has_crop(cell):
		return false
	var plot: Plot = _plots[cell]
	return plot.stage >= plot.crop.ripe_stage()


## Everything about a cell, handy for UI tooltips.
## Keys: tilled, watered, crop, stage, days_grown, days_left, ripe, rare.
func get_cell_info(cell: Vector2i) -> Dictionary:
	if not _plots.has(cell):
		return {"tilled": false}
	var plot: Plot = _plots[cell]
	var info := {"tilled": true, "watered": plot.watered, "crop": plot.crop}
	if plot.crop != null:
		info["stage"] = plot.stage
		info["days_grown"] = plot.days_grown
		info["days_left"] = maxi(plot.crop.grow_days - plot.days_grown, 0)
		info["ripe"] = is_ripe(cell)
		info["rare"] = plot.rare
	return info


## All tilled cells.
func get_tilled_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_plots.keys())
	return result


## Cells with a crop that is ready to harvest.
func get_ripe_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in _plots:
		if is_ripe(cell):
			result.append(cell)
	return result


## Cells with a growing crop that still needs water today.
func get_thirsty_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in _plots:
		var plot: Plot = _plots[cell]
		if plot.crop != null and plot.crop.needs_water and not plot.watered and not is_ripe(cell):
			result.append(cell)
	return result


## Current season used for planting and growth.
func current_season() -> String:
	if not season_override.is_empty():
		return season_override
	var calendar = _calendar()
	return calendar.season() if calendar != null else ""


# ---------------------------------------------------------------------------
# Checks (no side effects)
# ---------------------------------------------------------------------------

func can_till(cell: Vector2i) -> Result:
	if not is_in_area(cell):
		return Result.OUTSIDE_FIELD
	if _plots.has(cell):
		return Result.ALREADY_TILLED
	return Result.OK


func can_water(cell: Vector2i) -> Result:
	if not _plots.has(cell):
		return Result.NOT_TILLED
	if (_plots[cell] as Plot).watered:
		return Result.ALREADY_WATERED
	return Result.OK


func can_plant(cell: Vector2i, crop: FarmCrop) -> Result:
	if crop == null or crop.stage_textures.is_empty():
		return Result.INVALID_CROP
	if not _plots.has(cell):
		return Result.NOT_TILLED
	if (_plots[cell] as Plot).crop != null:
		return Result.OCCUPIED
	var season := current_season()
	if not season.is_empty() and not crop.grows_in(season):
		return Result.WRONG_SEASON
	return Result.OK


func can_harvest(cell: Vector2i) -> Result:
	if not has_crop(cell):
		return Result.EMPTY
	if not is_ripe(cell):
		return Result.NOT_RIPE
	return Result.OK


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

## Turns ground into farmland.
func till(cell: Vector2i) -> bool:
	if not _check(cell, can_till(cell)):
		return false
	_plots[cell] = Plot.new()
	tilled.emit(cell)
	queue_redraw()
	return true


## Turns farmland back into ground. Fails if a crop is still there.
func untill(cell: Vector2i) -> bool:
	if not _plots.has(cell):
		return _check(cell, Result.NOT_TILLED)
	if has_crop(cell):
		return _check(cell, Result.OCCUPIED)
	_plots.erase(cell)
	untilled.emit(cell)
	queue_redraw()
	return true


## Waters tilled soil for today.
func water(cell: Vector2i) -> bool:
	if not _check(cell, can_water(cell)):
		return false
	_set_watered(cell)
	return true


## Waters every tilled cell (rain).
func water_all() -> void:
	for cell: Vector2i in _plots:
		if not (_plots[cell] as Plot).watered:
			_set_watered(cell)


## Plants a crop on tilled soil.
func plant(cell: Vector2i, crop: FarmCrop) -> bool:
	if not _check(cell, can_plant(cell, crop)):
		return false
	var plot: Plot = _plots[cell]
	plot.crop = crop
	plot.days_grown = 0
	plot.stage = 0
	plot.rare = false
	plot.rare_rolled = false
	plot.dry_days = 0
	_spawn_sprite(cell, plot)
	planted.emit(cell, crop)
	return true


## Harvests a ripe crop. Returns {crop, amount, rare} or an empty dictionary.
## Crops with regrow_days stay in the ground and ripen again later.
func harvest(cell: Vector2i) -> Dictionary:
	if not _check(cell, can_harvest(cell)):
		return {}
	var plot: Plot = _plots[cell]
	var crop := plot.crop
	var amount := crop.roll_yield(_rng)
	var rare := plot.rare
	if crop.regrow_days > 0:
		plot.days_grown = crop.grow_days - crop.regrow_days
		plot.stage = crop.stage_for_days(plot.days_grown)
		plot.rare = false
		plot.rare_rolled = false
		_update_sprite(plot)
	else:
		_remove_crop(plot)
	harvested.emit(cell, crop, amount, rare)
	return {"crop": crop, "amount": amount, "rare": rare}


## Removes a crop without harvesting it (shovel, scythe, axe).
func remove_crop(cell: Vector2i) -> bool:
	if not has_crop(cell):
		return _check(cell, Result.EMPTY)
	_remove_crop(_plots[cell])
	return true


## Instantly grows a crop by some days (fertilizer, cheats, tests).
func grow(cell: Vector2i, days: int = 1) -> bool:
	if not has_crop(cell):
		return _check(cell, Result.EMPTY)
	for i in days:
		_grow_one_day(cell, _plots[cell])
	return true


## Removes all farmland and crops.
func clear() -> void:
	for cell: Vector2i in _plots:
		var plot: Plot = _plots[cell]
		if plot.sprite != null:
			plot.sprite.queue_free()
	_plots.clear()
	queue_redraw()


# ---------------------------------------------------------------------------
# Days
# ---------------------------------------------------------------------------

## Runs one new day: crops wither (wrong season) or grow (if watered),
## then the soil dries. Called automatically by FarmCalendar when
## [member follow_calendar] is on.
func advance_day(rain: bool = false) -> void:
	var season := current_season()
	for cell: Vector2i in _plots.keys():
		var plot: Plot = _plots[cell]
		if plot.crop != null:
			if plot.crop.withers_out_of_season and not season.is_empty() and not plot.crop.grows_in(season):
				var dead := plot.crop
				_remove_crop(plot)
				withered.emit(cell, dead)
			elif plot.watered or not plot.crop.needs_water:
				_grow_one_day(cell, plot)
		elif revert_empty_soil_days > 0:
			plot.dry_days = 0 if plot.watered else plot.dry_days + 1
			if plot.dry_days >= revert_empty_soil_days:
				_plots.erase(cell)
				untilled.emit(cell)
				continue
		plot.watered = false
	if rain:
		water_all()
	queue_redraw()
	day_processed.emit()


func _on_calendar_day_started(_day: int) -> void:
	var calendar = _calendar()
	advance_day(calendar.raining if calendar != null else false)


func _grow_one_day(cell: Vector2i, plot: Plot) -> void:
	if plot.stage >= plot.crop.ripe_stage():
		return
	plot.days_grown += 1
	var new_stage := plot.crop.stage_for_days(plot.days_grown)
	if new_stage == plot.stage:
		return
	plot.stage = new_stage
	if plot.stage >= plot.crop.ripe_stage() and not plot.rare_rolled:
		plot.rare_rolled = true
		plot.rare = _rng.randf() < plot.crop.rare_chance
	_update_sprite(plot)
	grew.emit(cell, plot.crop, plot.stage)
	if plot.stage >= plot.crop.ripe_stage():
		ripened.emit(cell, plot.crop, plot.rare)


# ---------------------------------------------------------------------------
# Save / load
# ---------------------------------------------------------------------------

## Field state as plain data (safe for JSON or ConfigFile).
func to_dict() -> Dictionary:
	var cells: Array = []
	for cell: Vector2i in _plots:
		var plot: Plot = _plots[cell]
		var entry := {"x": cell.x, "y": cell.y, "watered": plot.watered, "dry_days": plot.dry_days}
		if plot.crop != null:
			entry["crop"] = String(plot.crop.id)
			entry["days"] = plot.days_grown
			entry["rare"] = plot.rare
			entry["rare_rolled"] = plot.rare_rolled
		cells.append(entry)
	return {"version": 1, "cells": cells}


## Restores a state made by [method to_dict]. Crops are found by id in
## [member crop_library]; unknown ids are skipped (the soil stays tilled).
func from_dict(data: Dictionary) -> void:
	clear()
	var library := {}
	for crop in crop_library:
		if crop != null:
			library[crop.id] = crop
	for entry: Dictionary in data.get("cells", []):
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var plot := Plot.new()
		plot.watered = bool(entry.get("watered", false))
		plot.dry_days = int(entry.get("dry_days", 0))
		_plots[cell] = plot
		var crop_id := StringName(entry.get("crop", ""))
		if library.has(crop_id):
			plot.crop = library[crop_id]
			plot.days_grown = int(entry.get("days", 0))
			plot.stage = plot.crop.stage_for_days(plot.days_grown)
			plot.rare = bool(entry.get("rare", false))
			plot.rare_rolled = bool(entry.get("rare_rolled", plot.rare))
			_spawn_sprite(cell, plot)
	queue_redraw()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not draw_soil:
		return
	for cell: Vector2i in _plots:
		var plot: Plot = _plots[cell]
		var rect := Rect2(Vector2(cell * tile_size), Vector2(tile_size))
		var texture := wet_soil_texture if plot.watered else dry_soil_texture
		if texture != null:
			draw_texture_rect(texture, rect, false)
		else:
			draw_rect(rect, wet_soil_color if plot.watered else dry_soil_color)


func _spawn_sprite(cell: Vector2i, plot: Plot) -> void:
	if plot.sprite != null:
		plot.sprite.queue_free()
	var sprite := Sprite2D.new()
	sprite.centered = true
	# Bottom-centre of the tile, so tall crops grow upwards and y-sort correctly.
	sprite.position = Vector2(cell * tile_size) + Vector2(tile_size.x * 0.5, tile_size.y)
	_crops_root.add_child(sprite)
	plot.sprite = sprite
	_update_sprite(plot)


func _update_sprite(plot: Plot) -> void:
	if plot.sprite == null or plot.crop == null:
		return
	var texture := plot.crop.texture_for_stage(plot.stage)
	plot.sprite.texture = texture
	var height := texture.get_height() if texture != null else 0
	plot.sprite.offset = Vector2(0, -height * 0.5) + plot.crop.sprite_offset
	plot.sprite.self_modulate = rare_modulate if plot.rare else Color.WHITE


func _remove_crop(plot: Plot) -> void:
	if plot.sprite != null:
		plot.sprite.queue_free()
	plot.sprite = null
	plot.crop = null
	plot.days_grown = 0
	plot.stage = 0
	plot.rare = false
	plot.rare_rolled = false


func _set_watered(cell: Vector2i) -> void:
	var plot: Plot = _plots[cell]
	plot.watered = true
	plot.dry_days = 0
	watered.emit(cell)
	queue_redraw()


func _check(cell: Vector2i, result: Result) -> bool:
	if result == Result.OK:
		return true
	action_failed.emit(cell, result)
	return false


func _calendar() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null(^"FarmCalendar")
