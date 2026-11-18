extends Node2D
## Farming Kit demo. Everything game-specific (tools, inventory, UI) lives
## here; the farming itself is done by FarmField, FarmSprinkler, and the
## FarmCalendar autoload.
##
## Controls:
##   1-5          choose tool (hoe, water, seeds, harvest, sprinkler)
##   Q            next seed type
##   Left click   use tool on the cell under the mouse
##   Right click  smart action (till → plant → water → harvest)
##   N / Space    sleep (next day)
##   R            toggle rain for tomorrow
##   F5 / F9      save / load

enum Tool { HOE, WATER, SEEDS, HARVEST, SPRINKLER }

const TOOL_NAMES := ["Hoe", "Watering can", "Seeds", "Harvest", "Sprinkler"]
const SAVE_PATH := "user://farming_kit_demo.json"
const SPRINKLER_TEXTURE := preload("res://addons/farming_kit/examples/sprites/sprinkler.png")

@onready var field: FarmField = $FarmField
@onready var cursor: Sprite2D = $Cursor
@onready var hud_top: Label = $HUD/Top
@onready var hud_tools: Label = $HUD/Tools
@onready var hud_info: Label = $HUD/Info
@onready var hud_message: Label = $HUD/Message
@onready var hud_bag: Label = $HUD/Bag

var tool: Tool = Tool.HOE
var seed_index := 0
var rain_tomorrow := false
var bag := {}  # crop id -> {"normal": int, "rare": int}
var _message_time := 0.0


func _ready() -> void:
	FarmCalendar.days_per_season = 7  # short seasons so you can see them change
	FarmCalendar.day_started.connect(_on_day_started)
	FarmCalendar.season_changed.connect(func(s: String) -> void: _say("A new season begins: %s" % s.capitalize()))
	field.action_failed.connect(_on_action_failed)
	field.harvested.connect(_on_harvested)
	field.ripened.connect(func(_c: Vector2i, crop: FarmCrop, rare: bool) -> void:
		if rare:
			_say("Something special is growing... a rare %s!" % crop.display_name))
	field.withered.connect(func(_c: Vector2i, crop: FarmCrop) -> void: _say("%s withered (wrong season)." % crop.display_name))
	_say("Welcome! Right click does the right thing on every cell.")
	_refresh_hud()


func _process(delta: float) -> void:
	var cell := field.world_to_cell(get_global_mouse_position())
	cursor.visible = field.is_in_area(cell)
	cursor.global_position = field.cell_to_world(cell)
	hud_info.text = _describe(cell) if cursor.visible else ""
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			hud_message.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var cell := field.world_to_cell(get_global_mouse_position())
		if event.button_index == MOUSE_BUTTON_LEFT:
			_use_tool(tool, cell)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_smart_action(cell)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				tool = (event.keycode - KEY_1) as Tool
			KEY_Q:
				seed_index = (seed_index + 1) % field.crop_library.size()
				tool = Tool.SEEDS
			KEY_N, KEY_SPACE:
				FarmCalendar.next_day(rain_tomorrow)
			KEY_R:
				rain_tomorrow = not rain_tomorrow
			KEY_F5:
				_save()
			KEY_F9:
				_load()
		_refresh_hud()


func _use_tool(which: Tool, cell: Vector2i) -> void:
	match which:
		Tool.HOE:
			field.till(cell)
		Tool.WATER:
			field.water(cell)
		Tool.SEEDS:
			field.plant(cell, _selected_seed())
		Tool.HARVEST:
			field.harvest(cell)
		Tool.SPRINKLER:
			_place_sprinkler(cell)


## One button that picks the next useful step for the cell.
func _smart_action(cell: Vector2i) -> void:
	if not field.is_tilled(cell):
		field.till(cell)
	elif not field.has_crop(cell):
		field.plant(cell, _selected_seed())
	elif field.is_ripe(cell):
		field.harvest(cell)
	elif not field.is_watered(cell):
		field.water(cell)
	else:
		_say("Nothing to do here today.")


func _place_sprinkler(cell: Vector2i) -> void:
	if not field.is_in_area(cell) or field.is_tilled(cell):
		_say("Place sprinklers on untilled ground inside the field.")
		return
	for s in get_tree().get_nodes_in_group("demo_sprinklers"):
		if (s as FarmSprinkler).get_cell() == cell:
			return
	var sprinkler := FarmSprinkler.new()
	sprinkler.texture = SPRINKLER_TEXTURE
	sprinkler.add_to_group("demo_sprinklers")
	add_child(sprinkler)
	sprinkler.field = field
	sprinkler.global_position = field.cell_to_world(cell)
	_say("Sprinkler placed. It waters the 4 cells around it every morning.")


func _selected_seed() -> FarmCrop:
	return field.crop_library[seed_index]


func _on_day_started(_day: int) -> void:
	var ripe := field.get_ripe_cells().size()
	_say("Good morning!%s%s" % [" It rained, the field is wet." if FarmCalendar.raining else "", (" %d crop(s) ready to harvest." % ripe) if ripe > 0 else ""])
	_refresh_hud()


func _on_harvested(_cell: Vector2i, crop: FarmCrop, amount: int, rare: bool) -> void:
	var entry: Dictionary = bag.get(crop.id, {"normal": 0, "rare": 0})
	entry["rare" if rare else "normal"] += amount
	bag[crop.id] = entry
	_say("Harvested %d %s%s" % [amount, crop.display_name, " (RARE!)" if rare else ""])
	_refresh_hud()


func _on_action_failed(_cell: Vector2i, result: FarmField.Result) -> void:
	var text := {
		FarmField.Result.OUTSIDE_FIELD: "That's outside the field.",
		FarmField.Result.ALREADY_TILLED: "Already tilled.",
		FarmField.Result.NOT_TILLED: "Till the soil first (Hoe).",
		FarmField.Result.ALREADY_WATERED: "Already watered today.",
		FarmField.Result.OCCUPIED: "Something is already growing here.",
		FarmField.Result.EMPTY: "Nothing planted here.",
		FarmField.Result.WRONG_SEASON: "%s doesn't grow in %s." % [_selected_seed().display_name, FarmCalendar.season()],
		FarmField.Result.NOT_RIPE: "Not ready yet.",
		FarmField.Result.INVALID_CROP: "Invalid crop.",
	}
	_say(text.get(result, "Can't do that."))


func _describe(cell: Vector2i) -> String:
	var info := field.get_cell_info(cell)
	if not info["tilled"]:
		return "Grass"
	var text := "Soil (%s)" % ("wet" if info["watered"] else "dry")
	var crop: FarmCrop = info["crop"]
	if crop != null:
		if info["ripe"]:
			text += " · %s READY%s" % [crop.display_name, " ★ rare" if info["rare"] else ""]
		else:
			text += " · %s, %d day(s) left" % [crop.display_name, info["days_left"]]
	return text


func _refresh_hud() -> void:
	hud_top.text = "Day %d · %s (day %d/%d) · Year %d   |   Rain tomorrow: %s" % [
		FarmCalendar.day, FarmCalendar.season().capitalize(), FarmCalendar.day_of_season(),
		FarmCalendar.days_per_season, FarmCalendar.year(), "yes" if rain_tomorrow else "no"]
	var parts: PackedStringArray = []
	for i in TOOL_NAMES.size():
		var name: String = TOOL_NAMES[i]
		if i == Tool.SEEDS:
			name += ": " + _selected_seed().display_name
		parts.append(("[%d %s]" if i == tool else " %d %s ") % [i + 1, name])
	hud_tools.text = "  ".join(parts) + "\nQ next seed · Right click smart action · N sleep · R rain · F5/F9 save/load"
	var lines: PackedStringArray = ["Bag"]
	for crop in field.crop_library:
		var entry: Dictionary = bag.get(crop.id, {"normal": 0, "rare": 0})
		lines.append("%s: %d%s" % [crop.display_name, entry["normal"], (" + %d rare" % entry["rare"]) if entry["rare"] > 0 else ""])
	hud_bag.text = "\n".join(lines)


func _say(text: String) -> void:
	hud_message.text = text
	_message_time = 4.0


func _save() -> void:
	var sprinklers: Array = []
	for s in get_tree().get_nodes_in_group("demo_sprinklers"):
		var c := (s as FarmSprinkler).get_cell()
		sprinklers.append([c.x, c.y])
	var data := {"calendar": FarmCalendar.to_dict(), "field": field.to_dict(), "bag": bag, "sprinklers": sprinklers}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	_say("Game saved.")


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_say("No save file yet. Press F5 to save.")
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	FarmCalendar.from_dict(data.get("calendar", {}))
	field.from_dict(data.get("field", {}))
	bag = {}
	for key: String in data.get("bag", {}):
		bag[StringName(key)] = data["bag"][key]
	for s in get_tree().get_nodes_in_group("demo_sprinklers"):
		s.remove_from_group("demo_sprinklers")
		s.queue_free()
	for pair: Array in data.get("sprinklers", []):
		_place_sprinkler(Vector2i(int(pair[0]), int(pair[1])))
	_say("Game loaded.")
	_refresh_hud()
