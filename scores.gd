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
const TABLE_SECTION := "table"
const NAME_KEY := "last_name"
const TABLE_SIZE := 8
const NAME_MAX := 10

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
	# One writer for the whole file. Writing a single section used to wipe the
	# other, so remembering the player's name quietly destroyed their tables.
	var cf := ConfigFile.new()
	cf.load(path)        # keep sections this process hasn't loaded
	for key in _cache:
		cf.set_value(SECTION, key, _cache[key])
	for key in _tables:
		cf.set_value(TABLE_SECTION, key, _tables[key])
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


# --- Named tables ---------------------------------------------------------------
#
# A best on its own says little once several people share a machine, so each
# game also keeps a short table of named runs. Entries carry the seed they were
# set on, since a score only means something against the board it was played.

static var _tables := {}


static func _load_tables() -> void:
	_load()
	if not _tables.is_empty():
		return
	var cf := ConfigFile.new()
	if cf.load(path) != OK or not cf.has_section(TABLE_SECTION):
		return
	for key in cf.get_section_keys(TABLE_SECTION):
		_tables[key] = cf.get_value(TABLE_SECTION, key)


static func table(key: String) -> Array:
	_load_tables()
	return _tables.get(key, [])


static func qualifies(key: String, value: float, lower_is_better := false) -> bool:
	var rows := table(key)
	if rows.size() < TABLE_SIZE:
		return true
	var worst: float = float(rows[rows.size() - 1].score)
	return value < worst if lower_is_better else value > worst


static func submit_entry(key: String, who: String, value: float, seed_code := "",
		lower_is_better := false) -> int:
	# Returns the placing, counting from 1, or -1 if it didn't make the table.
	_load_tables()
	var name := who.strip_edges()
	if name.is_empty():
		name = "-"
	var rows: Array = _tables.get(key, []).duplicate()
	rows.append({"name": name.substr(0, NAME_MAX), "score": value, "seed": seed_code})
	rows.sort_custom(func(a, b):
		return float(a.score) < float(b.score) if lower_is_better else float(a.score) > float(b.score))
	if rows.size() > TABLE_SIZE:
		rows.resize(TABLE_SIZE)
	_tables[key] = rows

	remember_name(name)     # writes the whole file, tables included

	for i in rows.size():
		if rows[i].name == name.substr(0, NAME_MAX) and float(rows[i].score) == value:
			return i + 1
	return -1


static func last_name() -> String:
	_load()
	return str(_cache.get(NAME_KEY, ""))


static func remember_name(who: String) -> void:
	_load()
	_cache[NAME_KEY] = who
	_save()


# Typing a name, shared so it behaves the same in every game.
class NameEntry:
	extends RefCounted

	var active := false
	var buffer := ""
	var placing := -1
	var key := ""
	var lower_is_better := false

	func start(table_key: String, lower := false) -> void:
		active = true
		key = table_key
		lower_is_better = lower
		buffer = Scores.last_name()
		placing = -1

	func handle_key(event: InputEventKey, value: float, seed_code := "") -> bool:
		# True when the key was ours to deal with.
		if not active:
			return false
		match event.physical_keycode:
			KEY_ESCAPE:
				active = false
				return true
			KEY_BACKSPACE:
				buffer = buffer.substr(0, max(buffer.length() - 1, 0))
				return true
			KEY_ENTER, KEY_KP_ENTER:
				placing = Scores.submit_entry(key, buffer, value, seed_code, lower_is_better)
				active = false
				return true
		var typed := char(event.unicode)
		if typed.strip_edges() != "" and buffer.length() < Scores.NAME_MAX:
			buffer += typed.to_upper()
		return true

	func draw(ci: CanvasItem, width: float, title: String) -> void:
		if not active:
			return
		var top := 300.0
		ci.draw_rect(Rect2(0, top, width, 132), Blocks.PAPER)
		Blocks.rule(ci, Vector2(0, top), width, Blocks.RED, 4.0)
		Blocks.rule(ci, Vector2(0, top + 132), width, Blocks.INK, 1.0)
		Blocks.text(ci, Vector2(28, top + 46), title, 26, Blocks.INK)
		Blocks.tracked(ci, Vector2(28, top + 70), "TYPE YOUR NAME, ENTER TO SAVE", 11, Blocks.INK_MID)
		Blocks.text(ci, Vector2(28, top + 112), buffer + "_", 30, Blocks.RED)


static func clear() -> void:
	_load()
	_cache = {}
	_tables = {}
	# Start the file over: leaving the old sections in place would have them
	# read straight back in.
	var cf := ConfigFile.new()
	cf.save(path)


static func reload() -> void:
	# Drop the in-memory copy so the next read comes off disk.
	_loaded = false
	_cache = {}
	_tables = {}
