@icon("res://addons/farming_kit/icons/farm_crop.svg")
class_name FarmCrop
extends Resource
## Data for one crop type. Create one `.tres` per crop
## (right click in FileSystem → New Resource → FarmCrop).
##
## Growth works in days. Every day the crop is watered (or if it does not need
## water) it gains one day of growth. When it reaches [member grow_days] it shows
## the last texture in [member stage_textures] and can be harvested.

## Unique id, used for save/load and to identify the harvested item.
@export var id: StringName = &""
## Name shown to players.
@export var display_name: String = ""
## Optional icon for inventories, shops, or seed bags.
@export var icon: Texture2D

@export_group("Growth")
## Days of growth needed before the crop can be harvested.
@export_range(1, 365) var grow_days: int = 4
## One texture per visual stage, from seed to ripe. The last texture is the
## harvestable stage. Needs at least 2 textures.
@export var stage_textures: Array[Texture2D] = []
## Seasons in which this crop can be planted and grows. Leave empty to allow
## every season. Names must match [member FarmCalendar.season_names].
@export var seasons: PackedStringArray = PackedStringArray()
## If true the crop only grows on days it was watered.
@export var needs_water: bool = true
## If true the crop dies when the season changes to one it does not grow in.
@export var withers_out_of_season: bool = true

@export_group("Harvest")
## 0 = the crop is removed after harvest. Above 0 = the plant stays and is ready
## again after this many days (like tomatoes or berries).
@export_range(0, 365) var regrow_days: int = 0
## Minimum amount produced per harvest.
@export_range(1, 99) var yield_min: int = 1
## Maximum amount produced per harvest.
@export_range(1, 99) var yield_max: int = 1
## Chance (0..1) that the crop turns rare when it ripens.
@export_range(0.0, 1.0, 0.01) var rare_chance: float = 0.0

@export_group("Display")
## Offset of the sprite from the bottom-centre of the tile. Use it for tall crops.
@export var sprite_offset: Vector2 = Vector2.ZERO

## Free slot for your own data (price, item id, xp, ...).
@export var metadata: Dictionary = {}


## Index of the last stage (the harvestable one).
func ripe_stage() -> int:
	return maxi(stage_textures.size() - 1, 1)


## Visual stage for a number of grown days.
func stage_for_days(days_grown: int) -> int:
	if days_grown >= grow_days:
		return ripe_stage()
	var growing_stages := ripe_stage()  # stages before ripe
	return clampi(floori(days_grown * growing_stages / float(grow_days)), 0, growing_stages - 1)


## Texture for a stage, or null if none was assigned.
func texture_for_stage(stage: int) -> Texture2D:
	if stage_textures.is_empty():
		return null
	return stage_textures[clampi(stage, 0, stage_textures.size() - 1)]


## True if the crop can grow in the given season. Empty [member seasons] = all.
func grows_in(season: String) -> bool:
	return seasons.is_empty() or seasons.has(season)


## Random harvest amount between [member yield_min] and [member yield_max].
func roll_yield(rng: RandomNumberGenerator = null) -> int:
	var lo := mini(yield_min, yield_max)
	var hi := maxi(yield_min, yield_max)
	return rng.randi_range(lo, hi) if rng else randi_range(lo, hi)


## Returns a list of problems with this resource (empty = OK).
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if String(id).is_empty():
		problems.append("id is empty")
	if stage_textures.size() < 2:
		problems.append("stage_textures needs at least 2 textures")
	if regrow_days >= grow_days and regrow_days > 0:
		problems.append("regrow_days should be smaller than grow_days")
	return problems
