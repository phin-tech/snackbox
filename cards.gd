class_name Cards
extends RefCounted

# Shared basics for card games: the deck model, and drawing a card.
#
# A card is a plain int, 0..51, which keeps piles cheap to copy, compare and
# serialise. rank_of() and suit_of() unpack it. Everything here is stateless -
# each game owns its own piles and rules.
#
#   suit: 0 clubs, 1 diamonds, 2 hearts, 3 spades
#   rank: 0 ace .. 12 king

const NONE := -1

const CLUBS := 0
const DIAMONDS := 1
const HEARTS := 2
const SPADES := 3

const RANK_NAMES := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const SUIT_PIPS := ["♣", "♦", "♥", "♠"]

# Faces are paper with ink figures; red suits take the accent.
const FACE := Color("efede8")
const FACE_DIM := Color("8f8c85")     # for cards that can't be moved yet
const BACK := Color("2d6fc0")
const BACK_LINE := Color("1d4f8f")
const INK := Color("14161a")
const RED := Color("d0021b")
const EDGE := Color("0b0c0e")

const CORNER := 6.0


static func rank_of(card: int) -> int:
	return card % 13


static func suit_of(card: int) -> int:
	return card / 13


static func is_red(card: int) -> bool:
	var s := suit_of(card)
	return s == DIAMONDS or s == HEARTS


static func rank_name(card: int) -> String:
	return RANK_NAMES[rank_of(card)]


static func suit_pip(card: int) -> String:
	return SUIT_PIPS[suit_of(card)]


static func name_of(card: int) -> String:
	return rank_name(card) + suit_pip(card)


static func fresh_deck() -> Array[int]:
	var deck: Array[int] = []
	for i in 52:
		deck.append(i)
	return deck


static func shuffled_deck(rng_seed := -1) -> Array[int]:
	# A seed makes a deal reproducible, which is what tests and "replay this
	# hand" both need.
	var deck := fresh_deck()
	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	return deck


# --- Drawing ------------------------------------------------------------------

static func draw_back(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, BACK)
	ci.draw_rect(rect, EDGE, false, 1.0)
	# A simple lattice, drawn rather than textured.
	var inset := rect.grow(-6)
	ci.draw_rect(inset, BACK_LINE, false, 1.0)
	var step := 9.0
	var x := inset.position.x
	while x < inset.end.x:
		ci.draw_line(Vector2(x, inset.position.y), Vector2(x, inset.end.y), BACK_LINE, 1.0)
		x += step


static func draw_face(ci: CanvasItem, rect: Rect2, card: int, dim := false) -> void:
	var ink: Color = RED if is_red(card) else INK
	ci.draw_rect(rect, FACE_DIM if dim else FACE)
	ci.draw_rect(rect, EDGE, false, 1.0)

	var font := Blocks.font()
	var label := rank_name(card)
	var pip := suit_pip(card)
	var size := int(clampf(rect.size.x * 0.30, 11.0, 26.0))

	# Index in the top-left, repeated upside down is overkill at this size, so
	# the bottom-right just gets the pip.
	ci.draw_string(font, rect.position + Vector2(6, size + 4), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
	ci.draw_string(font, rect.position + Vector2(6, size * 2 + 2), pip,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)

	# One large pip in the middle carries the suit at a glance.
	Blocks.text_in(ci, rect, pip, int(rect.size.x * 0.52), ink)


static func draw_card(ci: CanvasItem, rect: Rect2, card: int, face_up: bool, dim := false) -> void:
	if face_up:
		draw_face(ci, rect, card, dim)
	else:
		draw_back(ci, rect)


static func draw_empty(ci: CanvasItem, rect: Rect2, label := "") -> void:
	# An empty pile still needs to read as a place a card can go.
	ci.draw_rect(rect, Color(1, 1, 1, 0.04))
	ci.draw_rect(rect, Blocks.INK_FAINT, false, 1.0)
	if label != "":
		Blocks.text_in(ci, rect, label, 14, Blocks.INK_FAINT)


static func highlight(ci: CanvasItem, rect: Rect2, color := Blocks.ACCENT) -> void:
	ci.draw_rect(rect.grow(2), color, false, 2.0)


# --- Layout -------------------------------------------------------------------

static func stack_rect(origin: Vector2, card_size: Vector2, index: int, spacing: float,
		vertical := true) -> Rect2:
	# Position of the nth card in a fanned pile.
	var offset := Vector2(0, index * spacing) if vertical else Vector2(index * spacing, 0)
	return Rect2(origin + offset, card_size)


static func top_card(pile: Array) -> int:
	return pile[pile.size() - 1] if not pile.is_empty() else NONE
