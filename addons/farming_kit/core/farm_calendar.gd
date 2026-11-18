extends Node
## Autoload "FarmCalendar" (added automatically when the plugin is enabled).
##
## Keeps track of the day, season, and year. It does not run a clock by
## itself: call [method next_day] when your player sleeps, when a timer runs
## out, or whenever a new day should start. Every [FarmField] in the scene
## listens to [signal day_started] and grows its crops.

## Emitted at the start of every new day, after the date has changed.
signal day_started(day: int)
## Emitted when the season changes, before [signal day_started].
signal season_changed(season: String)

## Names of the seasons, in order. Change them to fit your game
## (for example ["dry", "rainy"] for a tropical setting).
@export var season_names: PackedStringArray = PackedStringArray(["spring", "summer", "autumn", "winter"])
## Length of one season in days.
@export_range(1, 365) var days_per_season: int = 28

## Current day, starting at 1 and counting forever.
var day: int = 1
## Set this before calling [method next_day] to water every field automatically.
var raining: bool = false


## Moves to the next day. Pass [param rain] = true to water all fields.
func next_day(rain: bool = false) -> void:
	var old_season := season()
	day += 1
	raining = rain
	if season() != old_season:
		season_changed.emit(season())
	day_started.emit(day)


## Index of the current season (0-based).
func season_index() -> int:
	if season_names.is_empty():
		return 0
	return floori((day - 1) / float(days_per_season)) % season_names.size()


## Name of the current season, for example "spring".
func season() -> String:
	if season_names.is_empty():
		return ""
	return season_names[season_index()]


## Day inside the current season, from 1 to [member days_per_season].
func day_of_season() -> int:
	return (day - 1) % days_per_season + 1


## Current year, starting at 1.
func year() -> int:
	var days_per_year := days_per_season * maxi(season_names.size(), 1)
	return floori((day - 1) / float(days_per_year)) + 1


## Goes back to day 1 of the first season.
func reset() -> void:
	day = 1
	raining = false


func to_dict() -> Dictionary:
	return {"day": day, "raining": raining}


func from_dict(data: Dictionary) -> void:
	day = maxi(int(data.get("day", 1)), 1)
	raining = bool(data.get("raining", false))
