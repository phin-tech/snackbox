class_name Pyramid
extends Node2D

# Pyramid solitaire. Clear the pyramid by pairing cards that add to 13, where
# ace is 1 and king is 13 - so a king goes on its own. A card can only be taken
# once both cards resting on it are gone.
#
# The first card game, and the first landscape screen: it reports its own design
# size and the shell resizes the window to match.

signal exit_to_menu

const DESIGN := Vector2(820, 620)

const ROWS := 7
const SLOTS := 28                 # 1 + 2 + ... + 7
const PASSES := 3                 # times through the stock

const CARD := Vector2(60, 84)
const STEP_X := 64.0
const STEP_Y := 34.0              # rows overlap; only the index needs to show
const TOP := Vector2(410, 100)    # apex centre

const STOCK_AT := Vector2(110, 420)
const WASTE_AT := Vector2(200, 420)

var deck: Array[int] = []
var pyramid: Array[int] = []      # 28 cards, laid out row by row
var gone: Array[bool] = []        # removed from the pyramid
var stock: Array[int] = []
var waste: Array[int] = []
var passes_left := PASSES

var picked := -1                  # pyramid slot, or -1
var picked_waste := false
var message := ""
var message_timer := 0.0
var won := false
var deals := 0


func design_size() -> Vector2:
	return DESIGN


func _ready() -> void:
	new_game()


func new_game() -> void:
	deck = Cards.shuffled_deck()
	pyramid = deck.slice(0, SLOTS)
	stock = deck.slice(SLOTS)
	waste = []
	gone = []
	for i in SLOTS:
		gone.append(false)
	passes_left = PASSES
	picked = -1
	picked_waste = false
	won = false
	message = ""
	deals = 0
	queue_redraw()


# --- Pyramid shape --------------------------------------------------------------

static func slot_index(row: int, col: int) -> int:
	return row * (row + 1) / 2 + col


static func row_of(slot: int) -> int:
	var row := 0
	while slot_index(row + 1, 0) <= slot:
		row += 1
	return row


func available(slot: int) -> bool:
	if slot < 0 or slot >= SLOTS or gone[slot]:
		return false
	var row := row_of(slot)
	if row == ROWS - 1:
		return true
	var col := slot - slot_index(row, 0)
	# Both cards resting on this one must be gone.
	return gone[slot_index(row + 1, col)] and gone[slot_index(row + 1, col + 1)]


func value_of(card: int) -> int:
	return Cards.rank_of(card) + 1        # ace 1 .. king 13


func cards_left() -> int:
	var n := 0
	for g in gone:
		if not g:
			n += 1
	return n


# --- Moves ---------------------------------------------------------------------

func _say(text: String) -> void:
	message = text
	message_timer = 1.8


func _clear_pick() -> void:
	picked = -1
	picked_waste = false


func take_pyramid(slot: int) -> bool:
	# A king clears on its own.
	if not available(slot):
		return false
	if value_of(pyramid[slot]) == 13:
		gone[slot] = true
		_clear_pick()
		_check_won()
		return true

	if picked_waste:
		return pair_with_waste(slot)
	if picked == -1:
		picked = slot
		return true
	if picked == slot:
		_clear_pick()
		return true

	if value_of(pyramid[picked]) + value_of(pyramid[slot]) == 13:
		gone[picked] = true
		gone[slot] = true
		_clear_pick()
		_check_won()
		return true

	_say("THAT PAIR DOESN'T MAKE 13")
	picked = slot
	return false


func pair_with_waste(slot: int) -> bool:
	if waste.is_empty() or not available(slot):
		return false
	var top: int = waste[waste.size() - 1]
	if value_of(top) + value_of(pyramid[slot]) != 13:
		_say("THAT PAIR DOESN'T MAKE 13")
		return false
	gone[slot] = true
	waste.remove_at(waste.size() - 1)
	_clear_pick()
	_check_won()
	return true


func take_waste() -> bool:
	if waste.is_empty():
		return false
	var top: int = waste[waste.size() - 1]
	if value_of(top) == 13:
		waste.remove_at(waste.size() - 1)
		_clear_pick()
		return true
	if picked != -1:
		return pair_with_waste(picked)
	picked_waste = not picked_waste
	return true


func deal() -> bool:
	_clear_pick()
	if not stock.is_empty():
		waste.append(stock.pop_back())
		deals += 1
		return true
	# Out of stock: turn the waste back over, if there's a pass left.
	if passes_left <= 1 or waste.is_empty():
		_say("NO PASSES LEFT")
		return false
	passes_left -= 1
	while not waste.is_empty():
		stock.append(waste.pop_back())
	return true


func has_moves() -> bool:
	if not stock.is_empty() or passes_left > 1:
		return true

	var open: Array[int] = []
	for i in SLOTS:
		if available(i):
			open.append(value_of(pyramid[i]))
	if not waste.is_empty():
		open.append(value_of(waste[waste.size() - 1]))

	for i in open.size():
		if open[i] == 13:
			return true
		for j in range(i + 1, open.size()):
			if open[i] + open[j] == 13:
				return true
	return false


func _check_won() -> void:
	if cards_left() > 0:
		return
	won = true
	# Fewest cards left is the natural record here, so a win is a perfect zero.
	Scores.submit_low("pyramid", 0)


# --- Input ----------------------------------------------------------------------

func slot_rect(slot: int) -> Rect2:
	var row := row_of(slot)
	var col := slot - slot_index(row, 0)
	var x: float = TOP.x - row * STEP_X * 0.5 + col * STEP_X - CARD.x * 0.5
	var y: float = TOP.y + row * STEP_Y
	return Rect2(Vector2(x, y), CARD)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		var at := get_local_mouse_position()

		if Rect2(STOCK_AT, CARD).has_point(at):
			deal()
			queue_redraw()
			return
		if not waste.is_empty() and Rect2(WASTE_AT, CARD).has_point(at):
			take_waste()
			queue_redraw()
			return

		# Front to back, so the card on top of a stack wins the click.
		for slot in range(SLOTS - 1, -1, -1):
			if gone[slot]:
				continue
			if slot_rect(slot).has_point(at):
				take_pyramid(slot)
				queue_redraw()
				return
		_clear_pick()
		queue_redraw()
		return

	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_ESCAPE:
			exit_to_menu.emit()
		KEY_R:
			new_game()
		KEY_SPACE:
			if won or not has_moves():
				new_game()
			else:
				deal()
			queue_redraw()
		KEY_ENTER, KEY_KP_ENTER:
			new_game()


func _process(delta: float) -> void:
	if message_timer > 0.0:
		message_timer = maxf(message_timer - delta, 0.0)
		if message_timer == 0.0:
			message = ""
			queue_redraw()


# --- Drawing --------------------------------------------------------------------

func _draw() -> void:
	# Top row first: each lower row overlaps the bottom of the row above, which
	# is what leaves every index visible while still showing what rests on what.
	for row in ROWS:
		for col in range(row + 1):
			var slot := slot_index(row, col)
			if gone[slot]:
				continue
			var rect := slot_rect(slot)
			var open := available(slot)
			Cards.draw_card(self, rect, pyramid[slot], true, not open)
			if slot == picked:
				Cards.highlight(self, rect)

	# Stock
	if stock.is_empty():
		Cards.draw_empty(self, Rect2(STOCK_AT, CARD), "TURN" if passes_left > 1 else "DONE")
	else:
		Cards.draw_back(self, Rect2(STOCK_AT, CARD))

	# Waste, a few fanned so you can see what just came off
	if waste.is_empty():
		Cards.draw_empty(self, Rect2(WASTE_AT, CARD))
	else:
		var show: int = min(waste.size(), 3)
		for i in show:
			var card: int = waste[waste.size() - show + i]
			var rect := Rect2(WASTE_AT + Vector2(i * 20.0, 0), CARD)
			Cards.draw_face(self, rect, card)
			if i == show - 1 and picked_waste:
				Cards.highlight(self, rect)

	_draw_hud()

	if won:
		Blocks.banner(self, DESIGN.x, "PYRAMID CLEARED", "SPACE TO DEAL AGAIN")
	elif not has_moves():
		Blocks.banner(self, DESIGN.x, "NO MOVES LEFT", "%d CARDS SHORT        SPACE TO DEAL AGAIN" % cards_left())


func _draw_hud() -> void:
	Blocks.text(self, Vector2(40, 56), "PYRAMID", 34, Blocks.INK)
	Blocks.rule(self, Vector2(40, 70), DESIGN.x - 80, Blocks.RED, 3.0)

	Blocks.stat(self, Vector2(500, 420), "LEFT", str(cards_left()), 26)
	Blocks.stat(self, Vector2(590, 420), "STOCK", str(stock.size()), 26)
	Blocks.stat(self, Vector2(690, 420), "PASS", "%d/%d" % [PASSES - passes_left + 1, PASSES], 26)
	if Scores.has("pyramid"):
		Blocks.stat(self, Vector2(500, 490), "BEST", "%d LEFT" % int(Scores.get_best("pyramid")), 26)

	if message != "":
		Blocks.tracked(self, Vector2(40, 96), message, 11, Blocks.RED)

	var cy := 556.0
	for line in [
		"PAIR CARDS THAT ADD TO 13 - ACE IS 1, KING GOES ALONE",
		"A CARD IS ONLY FREE ONCE BOTH CARDS RESTING ON IT ARE GONE",
		"CLICK THE STOCK TO TURN        R  NEW DEAL        ESC  MENU",
	]:
		Blocks.tracked(self, Vector2(40, cy), line, 10, Blocks.INK_FAINT)
		cy += 16
