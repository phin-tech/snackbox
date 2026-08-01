class_name Blocks
extends RefCounted

# Shared palette and drawing primitives, in the International Typographic
# ("Swiss modern") manner: one ground, one ink, a single red accent, flat fills
# with no bevels or gradients, hairline rules, and uppercase labels set small
# and letter-spaced against large flush-left figures.
#
# PAPER/INK are named for their roles, not their values - the theme is dark, so
# PAPER is near-black and INK is bone. Swapping the six constants below flips
# the whole app; only each game's functional colours (piece and tile hues,
# which have to stay distinguishable) need touching separately.

const PAPER := Color("121316")           # ground
const PAPER_SUNK := Color("0b0c0e")      # recessed areas: boards, wells
const INK := Color("efede8")             # type and rules
const INK_MID := Color("9b9790")
const INK_FAINT := Color("5f5c57")
const RED := Color("ff3b30")             # the single accent

# Aliases kept so the games read the same way they did before the restyle.
const BG := PAPER_SUNK
const GRID_LINE := Color(1, 1, 1, 0.06)
const FRAME := INK
const TEXT := INK
const TEXT_DIM := INK_MID
const TEXT_FAINT := INK_FAINT
const ACCENT := RED

const TRACKING := 1.6                   # letter-spacing for small caps labels


# Inter, under the SIL Open Font License. The built-in fallback is a generic
# grotesque; Inter is the one this layout was designed around, and it carries
# tabular figures - digits of equal width - which stops every counter on screen
# twitching as its numbers change.
const REGULAR_PATH := "res://fonts/Inter-Regular.ttf"
const BOLD_PATH := "res://fonts/Inter-SemiBold.ttf"

static var _regular: Font = null
static var _bold: Font = null


static func _tabular(path: String) -> Font:
	var file := load(path)
	if file == null:
		return ThemeDB.fallback_font       # a missing font should not be fatal
	var variation := FontVariation.new()
	variation.base_font = file
	variation.opentype_features = {"tnum": 1}
	return variation


static func font() -> Font:
	if _regular == null:
		_regular = _tabular(REGULAR_PATH)
	return _regular


static func bold() -> Font:
	if _bold == null:
		_bold = _tabular(BOLD_PATH)
	return _bold


static func block(ci: CanvasItem, rect: Rect2, color: Color, alpha := 1.0) -> void:
	# Flat fill, hairline gap. No bevel: the shape carries the form.
	var c := color
	c.a *= alpha
	ci.draw_rect(rect.grow(-1), c)


static func outline(ci: CanvasItem, rect: Rect2, color := INK, width := 1.0) -> void:
	# Four filled bars rather than draw_rect's unfilled mode: its edges are
	# separate strokes and leave a notch where they meet at the corners.
	ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x, width)), color)
	ci.draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - width), Vector2(rect.size.x, width)), color)
	ci.draw_rect(Rect2(rect.position, Vector2(width, rect.size.y)), color)
	ci.draw_rect(Rect2(Vector2(rect.end.x - width, rect.position.y), Vector2(width, rect.size.y)), color)


static func rule(ci: CanvasItem, from: Vector2, length: float, color := INK, thickness := 1.0) -> void:
	ci.draw_rect(Rect2(from, Vector2(length, thickness)), color)


static func text(ci: CanvasItem, pos: Vector2, s: String, size := 16, color := INK) -> void:
	ci.draw_string(font(), pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func tracked(ci: CanvasItem, pos: Vector2, s: String, size := 12, color := INK_MID, track := TRACKING) -> float:
	# Letter-spaced caps. draw_string has no tracking, so step glyph by glyph.
	var f := font()
	var x := pos.x
	for i in s.length():
		var ch := s[i]
		f.draw_char(ci.get_canvas_item(), Vector2(x, pos.y), ch.unicode_at(0), size, color)
		x += f.get_char_size(ch.unicode_at(0), size).x + track
	return x - pos.x


static func text_centered(ci: CanvasItem, center_x: float, y: float, s: String, size := 16, color := INK) -> void:
	var w := font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(font(), Vector2(center_x - w * 0.5, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func stat(ci: CanvasItem, pos: Vector2, label: String, value: String, value_size := 30) -> void:
	# The Swiss unit: tiny tracked caps over a large figure, flush left.
	tracked(ci, pos, label, 11, INK_MID)
	ci.draw_string(bold(), pos + Vector2(0, value_size + 4), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, value_size, INK)


static func text_in(ci: CanvasItem, rect: Rect2, s: String, size := 20, color := INK) -> void:
	# Centre a string in a box. draw_string places text by its baseline, not its
	# top, so centring means working from the font's ascent and descent - doing
	# it by string height alone sits everything noticeably high.
	var f := font()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := rect.position.y + (rect.size.y + f.get_ascent(size) - f.get_descent(size)) * 0.5
	ci.draw_string(f, Vector2(rect.position.x + (rect.size.x - w) * 0.5, baseline),
		s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func panel(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, PAPER_SUNK)


static func banner(ci: CanvasItem, width: float, title: String, subtitle: String) -> void:
	var top := 296.0
	var h := 132.0
	ci.draw_rect(Rect2(0, top, width, h), PAPER)
	rule(ci, Vector2(0, top), width, RED, 4.0)
	rule(ci, Vector2(0, top + h), width, INK, 1.0)
	ci.draw_string(font(), Vector2(28, top + 62), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 42, INK)
	tracked(ci, Vector2(28, top + 96), subtitle.to_upper(), 12, INK_MID)


static func format_time(seconds: float) -> String:
	var total := maxf(seconds, 0.0)
	var m := int(total) / 60
	var s := int(total) % 60
	var cs := int(fmod(total, 1.0) * 100.0)
	return "%d:%02d.%02d" % [m, s, cs]
