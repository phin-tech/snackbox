class_name Scores
extends RefCounted

# Persistent bests, shared by every game. Stored as a ConfigFile in user://,
# which on macOS lands in ~/Library/Application Support/Godot/app_userdata/.
#
# Two flavours of record: submit_high for scores, submit_low for times, where
# smaller is better. Both return true when the value is a new best, so a game
# can say so on screen.

const DEFAULT_PATH := "user://scores.cfg"
const SECTION := "best"

# Overridable so tests don't write to the player's real file.
static var path := DEFAULT_PATH

static var _cache := {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_cache = {}
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return          # no file yet is normal on first run
	if not cf.has_section(SECTION):
		return
	for key in cf.get_section_keys(SECTION):
		_cache[key] = cf.get_value(SECTION, key)


static func _save() -> void:
	var cf := ConfigFile.new()
	for key in _cache:
		cf.set_value(SECTION, key, _cache[key])
	var err := cf.save(path)
	if err != OK:
		push_warning("could not save scores to %s (error %d)" % [path, err])


static func has(key: String) -> bool:
	_load()
	return _cache.has(key)


static func get_best(key: String, fallback := 0.0) -> float:
	_load()
	return float(_cache.get(key, fallback))


static func submit_high(key: String, value: float) -> bool:
	_load()
	if _cache.has(key) and float(_cache[key]) >= value:
		return false
	_cache[key] = value
	_save()
	return true


static func submit_low(key: String, value: float) -> bool:
	_load()
	if _cache.has(key) and float(_cache[key]) <= value:
		return false
	_cache[key] = value
	_save()
	return true


static func clear() -> void:
	_load()
	_cache = {}
	_save()


static func reload() -> void:
	# Drop the in-memory copy so the next read comes off disk.
	_loaded = false
	_cache = {}
