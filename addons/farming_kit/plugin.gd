@tool
extends EditorPlugin
## Registers the FarmCalendar autoload when the plugin is enabled.

const AUTOLOAD_NAME := "FarmCalendar"
const AUTOLOAD_PATH := "res://addons/farming_kit/core/farm_calendar.gd"


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
