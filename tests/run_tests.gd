extends SceneTree
## Run: godot --headless --path . --script res://tests/run_tests.gd

var _failed := 0
var _passed := 0


func _initialize() -> void:
	await process_frame
	_run()
	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)


func make_crop(id: String, grow: int, stages: int, seasons := PackedStringArray(), regrow := 0) -> FarmCrop:
	var crop := FarmCrop.new()
	crop.id = StringName(id)
	crop.grow_days = grow
	crop.regrow_days = regrow
	crop.seasons = seasons
	for i in stages:
		var img := Image.create(16, 16 + i, false, Image.FORMAT_RGBA8)
		crop.stage_textures.append(ImageTexture.create_from_image(img))
	return crop


func new_field() -> FarmField:
	var field := FarmField.new()
	field.area = Rect2i(0, 0, 5, 5)
	field.random_seed = 42
	root.add_child(field)
	return field


func _run() -> void:
	var cal = root.get_node("FarmCalendar")
	cal.reset()

	# --- FarmCrop
	var turnip := make_crop("turnip", 4, 4, PackedStringArray(["spring"]))
	ok(turnip.ripe_stage() == 3, "ripe stage")
	ok(turnip.stage_for_days(0) == 0, "stage day 0")
	ok(turnip.stage_for_days(2) == 1, "stage day 2")
	ok(turnip.stage_for_days(3) == 2, "stage day 3")
	ok(turnip.stage_for_days(4) == 3, "stage day 4 ripe")
	ok(turnip.stage_for_days(99) == 3, "stage clamps")
	ok(turnip.validate().is_empty(), "valid crop")
	ok(not FarmCrop.new().validate().is_empty(), "invalid crop detected")

	# --- Calendar
	ok(cal.season() == "spring" and cal.day_of_season() == 1 and cal.year() == 1, "calendar start")
	cal.day = 28
	cal.next_day()
	ok(cal.season() == "summer" and cal.day_of_season() == 1, "season rolls over")
	cal.day = 28 * 4
	cal.next_day()
	ok(cal.year() == 2 and cal.season() == "spring", "year rolls over")
	cal.reset()

	# --- Till / water / plant
	var field := new_field()
	var fails: Array = []
	field.action_failed.connect(func(c, r): fails.append(r))
	var c := Vector2i(1, 1)
	ok(not field.plant(c, turnip), "cannot plant untilled")
	ok(fails.back() == FarmField.Result.NOT_TILLED, "reason NOT_TILLED")
	ok(not field.till(Vector2i(9, 9)), "outside area")
	ok(fails.back() == FarmField.Result.OUTSIDE_FIELD, "reason OUTSIDE_FIELD")
	ok(field.till(c), "till")
	ok(not field.till(c), "till twice fails")
	ok(field.plant(c, turnip), "plant")
	ok(not field.plant(c, turnip), "plant twice fails")
	ok(fails.back() == FarmField.Result.OCCUPIED, "reason OCCUPIED")
	ok(field.water(c), "water")
	ok(not field.water(c), "water twice fails")

	# --- Growth needs water
	field.advance_day()  # watered yesterday -> grows (1 day)
	ok(field.get_cell_info(c)["days_grown"] == 1, "grew 1 day")
	ok(not field.is_watered(c), "soil dries")
	field.advance_day()  # not watered -> no growth
	ok(field.get_cell_info(c)["days_grown"] == 1, "no water no growth")
	ok(field.get_thirsty_cells().has(c), "thirsty list")
	var ripened := []
	field.ripened.connect(func(cell, crop, rare): ripened.append(cell))
	for i in 3:
		field.water(c)
		field.advance_day()
	ok(field.is_ripe(c), "ripe after 4 watered days")
	ok(ripened.size() == 1, "ripened signal once")
	ok(field.get_ripe_cells().has(c) and field.get_ripe_cells().size() == 1, "ripe list")

	# --- Harvest
	var res := field.harvest(c)
	ok(res.get("crop") == turnip and res.get("amount") == 1, "harvest result")
	ok(not field.has_crop(c) and field.is_tilled(c), "crop removed, soil stays")
	ok(field.harvest(c).is_empty(), "harvest empty fails")

	# --- Rain
	field.plant(c, turnip)
	field.advance_day(true)
	ok(field.is_watered(c), "rain waters soil")

	# --- Regrow
	var tomato := make_crop("tomato", 6, 4, PackedStringArray(), 2)
	var t := Vector2i(2, 2)
	field.till(t)
	field.plant(t, tomato)
	field.grow(t, 6)
	ok(field.is_ripe(t), "tomato ripe")
	field.harvest(t)
	ok(field.has_crop(t) and not field.is_ripe(t), "tomato stays after harvest")
	field.grow(t, 2)
	ok(field.is_ripe(t), "tomato ripe again after regrow_days")

	# --- Seasons
	var summer_only := make_crop("melon", 3, 3, PackedStringArray(["summer"]))
	var m := Vector2i(3, 3)
	field.till(m)
	ok(not field.plant(m, summer_only), "wrong season blocked")
	ok(fails.back() == FarmField.Result.WRONG_SEASON, "reason WRONG_SEASON")
	var withered := []
	field.withered.connect(func(cell, crop): withered.append(crop.id))
	cal.day = 28
	cal.next_day()  # -> summer, field follows calendar
	ok(withered.has(&"turnip"), "spring crop withers in summer")
	ok(field.plant(m, summer_only), "summer crop plants in summer")
	ok(field.has_crop(t), "all-season crop survives")
	cal.reset()

	# --- Rare harvest
	var gold := make_crop("gold", 2, 2)
	gold.rare_chance = 1.0
	var g := Vector2i(4, 4)
	field.till(g)
	field.plant(g, gold)
	field.grow(g, 2)
	ok(field.get_cell_info(g)["rare"] == true, "rare roll")
	ok(field.harvest(g)["rare"] == true, "rare harvest")

	# --- Sprinkler
	var f2 := new_field()
	var s := FarmSprinkler.new()
	f2.add_child(s)
	s.field = f2
	s.position = f2.cell_to_world(Vector2i(2, 2)) - f2.global_position
	ok(s.get_cell() == Vector2i(2, 2), "sprinkler cell")
	for cell in [Vector2i(2, 1), Vector2i(1, 2), Vector2i(4, 4)]:
		f2.till(cell)
	f2.advance_day()
	ok(f2.is_watered(Vector2i(2, 1)) and f2.is_watered(Vector2i(1, 2)), "sprinkler waters cross")
	ok(not f2.is_watered(Vector2i(4, 4)), "sprinkler range limited")
	s.pattern = FarmSprinkler.Pattern.BIG_SQUARE
	ok(s.get_target_cells().size() == 24, "big square 24 cells")

	# --- Soil revert
	s.pattern = FarmSprinkler.Pattern.CROSS
	f2.revert_empty_soil_days = 2
	f2.advance_day()
	f2.advance_day()
	ok(not f2.is_tilled(Vector2i(4, 4)), "empty dry soil reverts")

	# --- Save / load
	field.crop_library = [turnip, tomato, summer_only, gold]
	var saved := field.to_dict()
	var json := JSON.stringify(saved)
	var f3 := new_field()
	f3.crop_library = field.crop_library
	f3.from_dict(JSON.parse_string(json))
	ok(f3.get_tilled_cells().size() == field.get_tilled_cells().size(), "load restores soil")
	ok(f3.get_crop(t) == tomato and f3.get_cell_info(t)["days_grown"] == field.get_cell_info(t)["days_grown"], "load restores crop")
	ok(f3.is_ripe(t) == field.is_ripe(t), "load restores stage")
	var cal_saved: Dictionary = cal.to_dict()
	cal.next_day()
	cal.from_dict(cal_saved)
	ok(cal.day == 1, "calendar save/load")

	# --- World / cell conversion
	f3.position = Vector2(100, 50)
	ok(f3.world_to_cell(Vector2(100 + 16 * 2 + 3, 50 + 16 + 1)) == Vector2i(2, 1), "world_to_cell")
	ok(f3.cell_to_world(Vector2i(0, 0)) == Vector2(108, 58), "cell_to_world")
