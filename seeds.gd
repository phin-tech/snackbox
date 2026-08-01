class_name Seeds
extends RefCounted

# Reproducible boards. Every generator draws from Godot's global RNG, so seeding
# it immediately before generating is enough to make a board repeatable - no
# need to thread an RNG object through each one.
#
# A run has one base seed. Each level mixes that with the game name and the
# level number, so level 3 of seed A7K2 is the same board for everyone, and two
# games sharing a seed still get different boards.
#
# The catch worth knowing: a seed only means the same thing while the generator
# is unchanged. Alter how a game builds its boards and old seeds will produce
# different ones, which is why the code carries a version.

const VERSION := 1
const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"    # no I, O, 0 or 1
const LENGTH := 4


static func code(value: int) -> String:
	# Four characters is 32^4, about a million boards - plenty to swap around,
	# short enough to read out loud.
	var n: int = absi(value) % int(pow(ALPHABET.length(), LENGTH))
	var out := ""
	for _i in LENGTH:
		out = ALPHABET[n % ALPHABET.length()] + out
		n /= ALPHABET.length()
	return out


static func parse(text: String) -> int:
	var clean := text.strip_edges().to_upper()
	var value := 0
	for i in clean.length():
		var at := ALPHABET.find(clean[i])
		if at == -1:
			continue
		value = value * ALPHABET.length() + at
	return value


static func daily(game: String) -> int:
	# One board a day per game, the same for everyone playing that day.
	var now := Time.get_datetime_dict_from_system()
	var stamp: String = "%04d-%02d-%02d/%s" % [now.year, now.month, now.day, game]
	return abs(hash(stamp)) % 1048576


static func mix(game: String, base: int, level: int) -> int:
	return abs(hash("%s/%d/%d/%d" % [game, VERSION, base, level]))


# Seed entry, shared by the games so typing a seed works the same everywhere.
class Entry:
	extends RefCounted

	const NOTHING := 0
	const CONSUMED := 1
	const APPLIED := 2

	var game := ""
	var base := 0
	var typing := false
	var buffer := ""

	func _init(game_id: String) -> void:
		game = game_id
		base = Seeds.daily(game_id)

	func label() -> String:
		if not typing:
			return Seeds.code(base)
		return buffer.rpad(Seeds.LENGTH, "_")

	func level_seed(level: int) -> int:
		return Seeds.mix(game, base, level)

	func handle_key(event: InputEventKey) -> int:
		var key := event.physical_keycode

		if not typing:
			if key == KEY_S:
				typing = true
				buffer = ""
				return CONSUMED
			return NOTHING

		match key:
			KEY_ESCAPE:
				typing = false
				buffer = ""
				return CONSUMED
			KEY_BACKSPACE:
				buffer = buffer.substr(0, max(buffer.length() - 1, 0))
				return CONSUMED
			KEY_ENTER, KEY_KP_ENTER:
				typing = false
				if buffer.is_empty():
					return CONSUMED
				base = Seeds.parse(buffer)
				buffer = ""
				return APPLIED

		# Only characters that appear in a seed code get through.
		var typed := char(event.unicode).to_upper()
		if typed.length() == 1 and Seeds.ALPHABET.find(typed) != -1 and buffer.length() < Seeds.LENGTH:
			buffer += typed
			if buffer.length() == Seeds.LENGTH:
				typing = false
				base = Seeds.parse(buffer)
				buffer = ""
				return APPLIED
		return CONSUMED
