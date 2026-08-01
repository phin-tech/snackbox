class_name Menu
extends Node2D

# Title screen. A shallow tree rather than one long list: categories at the top
# level, games inside them, and modes inside the games that have them. A game
# with a single mode launches straight from its row - a submenu holding one
# option is just an extra keypress.

signal chosen(id: String)

const TREE := [
	{
		"label": "Falling", "note": "Blocks, pills and tiles that come to you",
		"children": [
			{
				"label": "Blockfall", "note": "The classic, in three flavours",
				"children": [
					{"id": "marathon", "label": "Marathon", "note": "Endless. Speed climbs every 10 lines."},
					{"id": "sprint", "label": "Sprint", "note": "Clear 40 lines as fast as you can."},
					{"id": "ultra", "label": "Ultra", "note": "Score as much as possible in 2 minutes."},
				],
			},
			{"id": "pills", "label": "Pill Doctor", "note": "Match four to wipe out every virus."},
			{"id": "doubles", "label": "Doubles", "note": "Slide and merge your way to 2048."},
		],
	},
	{
		"label": "Puzzles", "note": "Take your time. Nothing is chasing you",
		"children": [
			{
				"label": "Linkup", "note": "Join every pair, fill every square",
				"children": [
					{"id": "linkup.easy", "label": "Easy", "note": "Small boards, few colours, long routes."},
					{"id": "linkup.normal", "label": "Normal", "note": "A fair fight."},
					{"id": "linkup.hard", "label": "Hard", "note": "Bigger boards, more colours, tighter fits."},
				],
			},
			{"id": "shapes", "label": "Shapes", "note": "Carve the grid into the rectangles it asks for."},
			{"id": "gridlock", "label": "Gridlock", "note": "Slide the cars, free the red one."},
			{"id": "decant", "label": "Decant", "note": "Pour until every tube is one colour."},
		],
	},
	{
		"label": "Arcade", "note": "Reflexes required",
		"children": [
			{"id": "snake", "label": "Snake", "note": "Eat, grow, don't bite yourself."},
			{"id": "mondrian", "label": "Mondrian", "note": "Paint the canvas, dodge the drifters."},
		],
	},
	{
		"label": "Cards", "note": "A deck and a table",
		"children": [
			{"id": "pyramid", "label": "Pyramid", "note": "Pair cards that add to 13."},
		],
	},
]

const LIST_TOP := 268.0
const ROW_H := 46.0

var path: Array[int] = []          # indices from the root down to here
var index := 0
var time := 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


# --- Tree walking ---------------------------------------------------------------

func items() -> Array:
	# The rows shown at the current depth.
	var level: Array = TREE
	for step in path:
		level = level[step].children
	return level


func breadcrumb() -> String:
	# At the root the wordmark above already says where you are, so name the
	# level instead of repeating it.
	if path.is_empty():
		return "ALL GAMES"
	var out := "SNACKBOX"
	var level: Array = TREE
	for step in path:
		out += "  /  " + String(level[step].label).to_upper()
		level = level[step].children
	return out


func _enter(row: int) -> void:
	var entry: Dictionary = items()[row]
	if entry.has("id"):
		chosen.emit(entry.id)
		return
	path.append(row)
	index = 0
	queue_redraw()


func _back() -> bool:
	if path.is_empty():
		return false
	index = path[path.size() - 1]
	path.remove_at(path.size() - 1)
	queue_redraw()
	return true


# --- Layout, shared by drawing and hit testing ----------------------------------

func layout() -> Array:
	var out := []
	var w := Main.DESIGN_SIZE.x
	for i in items().size():
		out.append({"i": i, "rect": Rect2(52, LIST_TOP + i * ROW_H - 26, w - 104, ROW_H - 6)})
	return out


func row_at(point: Vector2) -> int:
	for row in layout():
		if row.rect.has_point(point):
			return row.i
	return -1


# --- Input ----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hover := row_at(get_local_mouse_position())
		if hover != -1 and hover != index:
			index = hover
			queue_redraw()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_back()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var hit := row_at(get_local_mouse_position())
			if hit != -1:
				index = hit
				_enter(hit)
		return

	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	var count := items().size()
	match (event as InputEventKey).physical_keycode:
		KEY_UP, KEY_W:
			index = wrapi(index - 1, 0, count)
		KEY_DOWN, KEY_S:
			index = wrapi(index + 1, 0, count)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_RIGHT, KEY_D:
			_enter(index)
		KEY_ESCAPE, KEY_BACKSPACE, KEY_LEFT, KEY_A:
			_back()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			var want: int = (event as InputEventKey).physical_keycode - KEY_1
			if want < count:
				index = want
				_enter(want)
	queue_redraw()


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	var w := Main.DESIGN_SIZE.x

	Blocks.tracked(self, Vector2(52, 96), "CASUAL GAMES", 12, Blocks.INK_MID)
	Blocks.text(self, Vector2(50, 156), "SNACKBOX", 54, Blocks.INK)
	Blocks.rule(self, Vector2(52, 176), w - 104, Blocks.RED, 5.0)

	# Breadcrumb, so it's always clear how deep you are.
	Blocks.tracked(self, Vector2(52, 214), breadcrumb(), 11, Blocks.INK_FAINT)
	Blocks.rule(self, Vector2(52, 232), w - 104, Blocks.INK, 1.0)

	var rows := items()
	var geometry := layout()
	for i in rows.size():
		var entry: Dictionary = rows[i]
		var rect: Rect2 = geometry[i].rect
		var selected := i == index

		if selected:
			draw_rect(rect, Blocks.INK)

		var number: Color = Blocks.PAPER if selected else Blocks.RED
		var label: Color = Blocks.PAPER if selected else Blocks.INK
		Blocks.tracked(self, Vector2(rect.position.x + 10, rect.position.y + 27), "%02d" % (i + 1), 12, number)
		Blocks.text(self, Vector2(rect.position.x + 50, rect.position.y + 30), entry.label, 22, label)

		# A folder gets a marker, a game gets none, so the two read apart.
		if not entry.has("id"):
			var mark: Color = Blocks.PAPER if selected else Blocks.INK_FAINT
			Blocks.tracked(self, Vector2(rect.end.x - 30, rect.position.y + 27), ">", 14, mark)

	Blocks.rule(self, Vector2(52, 648), w - 104, Blocks.INK, 1.0)
	if index < rows.size():
		Blocks.text(self, Vector2(52, 676), rows[index].note, 14, Blocks.INK_MID)

	var opens: bool = index < rows.size() and not rows[index].has("id")
	Blocks.tracked(self, Vector2(52, 712),
		"CLICK OR ARROWS  CHOOSE        ENTER  " + ("OPEN" if opens else "PLAY"), 11, Blocks.INK_FAINT)
	if path.is_empty():
		Blocks.tracked(self, Vector2(52, 730), "ESC RETURNS HERE FROM ANY GAME", 11, Blocks.INK_FAINT)
	else:
		Blocks.tracked(self, Vector2(52, 730), "ESC  BACK", 11, Blocks.INK_FAINT)
