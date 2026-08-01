class_name Menu
extends Node2D

# Game picker. Entries are just data - adding a game means adding a row here
# and a case in main.gd.

signal chosen(id: String)

const ENTRIES := [
	# A header only earns its line when a game has more than one mode;
	# otherwise the row label is the game's name.
	{"header": "BLOCKFALL"},
	{"id": "marathon", "label": "Marathon", "desc": "Endless. Speed climbs every 10 lines."},
	{"id": "sprint", "label": "Sprint", "desc": "Clear 40 lines as fast as you can."},
	{"id": "ultra", "label": "Ultra", "desc": "Score as much as possible in 2 minutes."},
	{"header": "LINKUP"},
	{"id": "linkup.easy", "label": "Easy", "desc": "Small boards, few colours, long routes."},
	{"id": "linkup.normal", "label": "Normal", "desc": "Join every pair, fill every square."},
	{"id": "linkup.hard", "label": "Hard", "desc": "Bigger boards, more colours, tighter fits."},
	{"header": "AND THE REST"},
	{"id": "pills", "label": "Pill Doctor", "desc": "Match four to wipe out every virus."},
	{"id": "mondrian", "label": "Mondrian", "desc": "Paint the canvas, dodge the drifters."},
	{"id": "gridlock", "label": "Gridlock", "desc": "Slide the cars, free the red one."},
	{"id": "shapes", "label": "Shapes", "desc": "Carve the grid into the rectangles it asks for."},
	{"id": "snake", "label": "Snake", "desc": "Eat, grow, don't bite yourself."},
	{"id": "doubles", "label": "Doubles", "desc": "Slide and merge your way to 2048."},
	{"id": "pyramid", "label": "Pyramid", "desc": "Pair cards that add to 13."},
	{"id": "decant", "label": "Decant", "desc": "Pour until every tube is one colour."},
]

var index := 1
var time := 0.0

# Row geometry, shared by drawing and hit testing so they can't drift apart.
const LIST_TOP := 224.0
const ROW_H := 27.0
const HEADER_H := 24.0


func _ready() -> void:
	set_process(true)
	# Land on the first selectable row.
	index = _next_selectable(0, 1)


func _next_selectable(from: int, step: int) -> int:
	var i := from
	for _n in ENTRIES.size():
		i = wrapi(i + step, 0, ENTRIES.size())
		if ENTRIES[i].has("id"):
			return i
	return from


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func layout() -> Array:
	# [{i, rect}] for every playable row, in the order drawn.
	var out := []
	var w := Main.DESIGN_SIZE.x
	var y := LIST_TOP
	for i in ENTRIES.size():
		if ENTRIES[i].has("header"):
			y += HEADER_H
			continue
		out.append({"i": i, "rect": Rect2(32, y - 21, w - 64, ROW_H)})
		y += ROW_H
	return out


func row_at(point: Vector2) -> int:
	for row in layout():
		if row.rect.has_point(point):
			return row.i
	return -1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hover := row_at(get_local_mouse_position())
		if hover != -1 and hover != index:
			index = hover
			queue_redraw()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var hit := row_at(get_local_mouse_position())
			if hit != -1:
				index = hit
				queue_redraw()
				chosen.emit(ENTRIES[hit].id)
		return

	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_UP, KEY_W:
			index = _next_selectable(index, -1)
		KEY_DOWN, KEY_S:
			index = _next_selectable(index, 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			chosen.emit(ENTRIES[index].id)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			# Number keys pick the nth playable row, in the order shown.
			var want: int = (event as InputEventKey).physical_keycode - KEY_1
			var seen := 0
			for e in ENTRIES:
				if not e.has("id"):
					continue
				if seen == want:
					chosen.emit(e.id)
					return
				seen += 1


func _draw() -> void:
	var w := Main.DESIGN_SIZE.x

	# Masthead: small tracked caps over a large flush-left wordmark, then a
	# heavy red rule. Everything hangs off the same left margin.
	Blocks.tracked(self, Vector2(34, 96), "CASUAL GAMES", 12, Blocks.INK_MID)
	Blocks.text(self, Vector2(32, 156), "SNACKBOX", 54, Blocks.INK)
	Blocks.rule(self, Vector2(32, 176), w - 64, Blocks.RED, 5.0)

	var y := LIST_TOP
	var number := 0
	for i in ENTRIES.size():
		var e: Dictionary = ENTRIES[i]
		if e.has("header"):
			Blocks.rule(self, Vector2(32, y - 12), w - 64, Blocks.INK, 1.0)
			Blocks.tracked(self, Vector2(32, y + 4), e.header, 11, Blocks.INK_FAINT)
			y += HEADER_H
			continue

		number += 1
		var selected := i == index
		if selected:
			draw_rect(Rect2(32, y - 21, w - 64, ROW_H), Blocks.INK)

		var num_color: Color = Blocks.PAPER if selected else Blocks.RED
		var label_color: Color = Blocks.PAPER if selected else Blocks.INK
		Blocks.tracked(self, Vector2(40, y), "%02d" % number, 12, num_color)
		Blocks.text(self, Vector2(80, y), e.label, 20, label_color)
		y += ROW_H

	Blocks.rule(self, Vector2(32, 648), w - 64, Blocks.INK, 1.0)
	var current: Dictionary = ENTRIES[index]
	if current.has("desc"):
		Blocks.text(self, Vector2(32, 676), current.desc, 14, Blocks.INK_MID)
	Blocks.tracked(self, Vector2(32, 712), "CLICK OR ARROWS  CHOOSE", 11, Blocks.INK_FAINT)
	Blocks.tracked(self, Vector2(32, 730), "ENTER  PLAY        ESC  RETURNS HERE", 11, Blocks.INK_FAINT)
