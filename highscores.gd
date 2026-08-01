class_name HighScores
extends Node2D

# The tables, one game at a time. Left and right walk between them; each shows
# the names, what they scored, and the seed they did it on.

signal exit_to_menu

const TABLES := [
	{"key": "blockfall.marathon", "title": "BLOCKFALL", "sub": "MARATHON", "unit": "points"},
	{"key": "blockfall.sprint", "title": "BLOCKFALL", "sub": "SPRINT", "unit": "time"},
	{"key": "blockfall.ultra", "title": "BLOCKFALL", "sub": "ULTRA", "unit": "points"},
	{"key": "snake", "title": "SNAKE", "sub": "", "unit": "points"},
	{"key": "doubles", "title": "DOUBLES", "sub": "", "unit": "points"},
	{"key": "mondrian", "title": "MONDRIAN", "sub": "", "unit": "points"},
]

var page := 0


func pages() -> Array:
	return TABLES


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			page = wrapi(page + 1, 0, pages().size())
			queue_redraw()
		return

	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_ESCAPE, KEY_BACKSPACE:
			exit_to_menu.emit()
		KEY_LEFT, KEY_UP, KEY_A, KEY_W:
			page = wrapi(page - 1, 0, pages().size())
		KEY_RIGHT, KEY_DOWN, KEY_D, KEY_S, KEY_SPACE:
			page = wrapi(page + 1, 0, pages().size())
	queue_redraw()


func _draw() -> void:
	var w := Main.DESIGN_SIZE.x
	var all := pages()
	var info: Dictionary = all[page % all.size()]

	Blocks.tracked(self, Vector2(52, 96), "HIGH SCORES", 12, Blocks.INK_MID)
	Blocks.text(self, Vector2(50, 156), info.title, 44, Blocks.INK)
	if info.sub != "":
		Blocks.tracked(self, Vector2(52, 180), info.sub, 12, Blocks.RED)
	Blocks.rule(self, Vector2(52, 196), w - 104, Blocks.RED, 4.0)

	var rows := Scores.table(info.key)
	if rows.is_empty():
		Blocks.text(self, Vector2(52, 260), "Nothing here yet.", 20, Blocks.INK_MID)
		Blocks.tracked(self, Vector2(52, 292), "PLAY A ROUND AND PUT YOUR NAME TO IT", 11, Blocks.INK_FAINT)
	else:
		var y := 250.0
		for i in rows.size():
			var row: Dictionary = rows[i]
			Blocks.tracked(self, Vector2(52, y), "%02d" % (i + 1), 12, Blocks.RED)
			Blocks.text(self, Vector2(96, y + 3), str(row.name), 20, Blocks.INK)

			var value := str(int(row.score))
			if info.unit == "time":
				value = Blocks.format_time(float(row.score))
			var dims := Blocks.font().get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
			draw_string(Blocks.font(), Vector2(w - 60 - dims.x, y + 3), value,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Blocks.INK)

			if str(row.get("seed", "")) != "":
				Blocks.tracked(self, Vector2(w - 190, y), str(row.seed), 10, Blocks.INK_FAINT)
			y += 38

	Blocks.rule(self, Vector2(52, 648), w - 104, Blocks.INK, 1.0)
	Blocks.tracked(self, Vector2(52, 676), "TABLE %d OF %d" % [page + 1, all.size()], 11, Blocks.INK_MID)
	Blocks.tracked(self, Vector2(52, 712), "LEFT RIGHT OR CLICK  ANOTHER GAME", 11, Blocks.INK_FAINT)
	Blocks.tracked(self, Vector2(52, 730), "ESC  BACK", 11, Blocks.INK_FAINT)
