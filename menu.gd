class_name Menu
extends Node2D

# Game picker. Entries are just data - adding a game means adding a row here
# and a case in main.gd.

signal chosen(id: String)

const ENTRIES := [
	{"header": "BLOCKFALL"},
	{"id": "marathon", "label": "Marathon", "desc": "Endless. Speed climbs every 10 lines."},
	{"id": "sprint", "label": "Sprint", "desc": "Clear 40 lines as fast as you can."},
	{"id": "ultra", "label": "Ultra", "desc": "Score as much as possible in 2 minutes."},
	{"header": "PILL DOCTOR"},
	{"id": "pills", "label": "Virus Clear", "desc": "Match 4 to wipe out every virus."},
	{"header": "LANDGRAB"},
	{"id": "landgrab", "label": "Claim", "desc": "Cut off territory, dodge the drifters."},
]

var index := 1
var time := 0.0


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


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_UP, KEY_W:
			index = _next_selectable(index, -1)
		KEY_DOWN, KEY_S:
			index = _next_selectable(index, 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			chosen.emit(ENTRIES[index].id)
		KEY_1:
			chosen.emit("marathon")
		KEY_2:
			chosen.emit("sprint")
		KEY_3:
			chosen.emit("ultra")
		KEY_4:
			chosen.emit("pills")
		KEY_5:
			chosen.emit("landgrab")


func _draw() -> void:
	var w := Main.DESIGN_SIZE.x

	Blocks.text_centered(self, w * 0.5, 120, "CASUAL GAMES", 20, Blocks.TEXT_DIM)
	Blocks.text_centered(self, w * 0.5, 176, "SNACKBOX", 52, Blocks.TEXT)
	draw_rect(Rect2(w * 0.5 - 90, 196, 180, 3), Blocks.ACCENT)

	var y := 268.0
	for i in ENTRIES.size():
		var e: Dictionary = ENTRIES[i]
		if e.has("header"):
			Blocks.text(self, Vector2(120, y), e.header, 14, Blocks.TEXT_FAINT)
			y += 30
			continue

		var selected := i == index
		var row := Rect2(104, y - 22, w - 208, 42)
		if selected:
			draw_rect(row, Color(0, 0.9, 1, 0.10))
			draw_rect(Rect2(row.position, Vector2(3, row.size.y)), Blocks.ACCENT)

		var label_color: Color = Blocks.TEXT if selected else Blocks.TEXT_DIM
		Blocks.text(self, Vector2(124, y), e.label, 22, label_color)
		if selected:
			Blocks.text(self, Vector2(124, y + 18), e.desc, 12, Blocks.TEXT_FAINT)
		y += 62

	Blocks.text_centered(self, w * 0.5, 690, "↑ ↓  choose        ENTER  play", 13, Blocks.TEXT_FAINT)
	Blocks.text_centered(self, w * 0.5, 712, "ESC returns here from any game", 13, Blocks.TEXT_FAINT)
