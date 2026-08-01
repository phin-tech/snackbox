extends ScoreSandbox

# The shared deck, and the two games built on it.


func before_each() -> void:
	use_sandbox()


func after_all() -> void:
	release_sandbox()


func test_a_deck_is_fifty_two_distinct_cards() -> void:
	var deck := Cards.fresh_deck()
	assert_eq(deck.size(), 52)
	var seen := {}
	for card in deck:
		seen[card] = true
	assert_eq(seen.size(), 52, "no card should appear twice")


func test_a_deck_covers_every_rank_and_suit() -> void:
	var ranks := {}
	var suits := {}
	for card in Cards.fresh_deck():
		ranks[Cards.rank_of(card)] = true
		suits[Cards.suit_of(card)] = true
	assert_eq(ranks.size(), 13)
	assert_eq(suits.size(), 4)


func test_red_is_diamonds_and_hearts() -> void:
	for card in Cards.fresh_deck():
		var expect: bool = Cards.suit_of(card) in [Cards.DIAMONDS, Cards.HEARTS]
		assert_eq(Cards.is_red(card), expect, "card %d has the wrong colour" % card)


func test_a_seeded_shuffle_repeats() -> void:
	assert_eq(Cards.shuffled_deck(1234), Cards.shuffled_deck(1234))
	assert_ne(Cards.shuffled_deck(1234), Cards.shuffled_deck(9999))


func test_a_shuffle_loses_nothing() -> void:
	var seen := {}
	for card in Cards.shuffled_deck(77):
		seen[card] = true
	assert_eq(seen.size(), 52)


# --- Pyramid --------------------------------------------------------------

func a_pyramid() -> Pyramid:
	var game: Pyramid = load("res://pyramid.tscn").instantiate()
	add_child_autofree(game)
	game.set_process(false)
	return game


func test_pyramid_deals_the_whole_deck() -> void:
	var game := a_pyramid()
	assert_eq(game.pyramid.size(), Pyramid.SLOTS)
	assert_eq(game.stock.size(), 52 - Pyramid.SLOTS)
	var seen := {}
	for card in game.pyramid + game.stock:
		seen[card] = true
	assert_eq(seen.size(), 52, "the deal should use every card once")


func test_pyramid_frees_a_card_only_when_both_above_it_are_gone() -> void:
	var game := a_pyramid()
	var parent := Pyramid.slot_index(Pyramid.ROWS - 2, 0)
	var left := Pyramid.slot_index(Pyramid.ROWS - 1, 0)
	var right := Pyramid.slot_index(Pyramid.ROWS - 1, 1)
	game.gone[left] = true
	assert_false(game.available(parent), "one card still resting on it")
	game.gone[right] = true
	assert_true(game.available(parent))


func test_pyramid_pairs_must_make_thirteen() -> void:
	var game := a_pyramid()
	for i in Pyramid.SLOTS:
		game.gone[i] = true
	var a := Pyramid.slot_index(Pyramid.ROWS - 1, 0)
	var b := Pyramid.slot_index(Pyramid.ROWS - 1, 1)
	game.gone[a] = false
	game.gone[b] = false

	game.pyramid[a] = 3        # four
	game.pyramid[b] = 4        # five, so nine
	game.picked = -1
	game.take_pyramid(a)
	game.take_pyramid(b)
	assert_false(game.gone[a], "nine is not thirteen")

	game.pyramid[b] = 8        # nine, so thirteen
	game.picked = -1
	game.take_pyramid(a)
	game.take_pyramid(b)
	assert_true(game.gone[a] and game.gone[b], "four and nine should clear together")


func test_pyramid_kings_go_alone() -> void:
	var game := a_pyramid()
	for i in Pyramid.SLOTS:
		game.gone[i] = true
	var k := Pyramid.slot_index(Pyramid.ROWS - 1, 2)
	game.gone[k] = false
	game.pyramid[k] = 12       # a king
	game.take_pyramid(k)
	assert_true(game.gone[k], "a king is thirteen on its own")


func test_pyramid_turning_the_stock_recycles_until_the_passes_run_out() -> void:
	var game := a_pyramid()
	while not game.stock.is_empty():
		game.deal()
	var waiting := game.waste.size()
	var passes := game.passes_left
	game.deal()
	assert_eq(game.stock.size(), waiting, "the waste should turn back over")
	assert_eq(game.passes_left, passes - 1, "and cost a pass")

	game.passes_left = 1
	while not game.stock.is_empty():
		game.deal()
	assert_false(game.deal(), "the last pass is the last pass")


# --- Decant ---------------------------------------------------------------

func a_decant() -> Decant:
	var game: Decant = load("res://decant.tscn").instantiate()
	add_child_autofree(game)
	game.set_process(false)
	return game


func test_decant_deals_full_tubes_of_every_colour() -> void:
	var game := a_decant()
	for level in [1, 5, 9]:
		game.level = level
		game._start_level()
		var counts := {}
		for tube in game.tubes:
			for unit in tube:
				counts[unit] = counts.get(unit, 0) + 1
		assert_eq(counts.size(), game.colour_count(), "level %d colour count" % level)
		for colour in counts:
			assert_eq(counts[colour], Decant.CAPACITY, "each colour should fill one tube")


func test_decant_never_deals_a_finished_or_unwinnable_board() -> void:
	var game := a_decant()
	for level in [1, 4, 7]:
		game.level = level
		game._start_level()
		assert_false(game.is_solved(), "level %d was dealt already sorted" % level)
		assert_true(game._solvable(game.tubes), "level %d cannot be finished" % level)


func test_decant_pours_only_onto_matching_colour_or_empty() -> void:
	var game := a_decant()
	game.tubes = [[0, 0, 1], [1, 1], [], [2, 2, 2, 2]] as Array
	assert_true(game.can_pour(0, 1), "onto the same colour")
	assert_false(game.can_pour(1, 3), "onto a different colour")
	assert_false(game.can_pour(3, 2), "a finished tube into an empty one achieves nothing")
	assert_false(game.can_pour(2, 0), "out of an empty tube")


func test_decant_moves_the_whole_run_or_as_much_as_fits() -> void:
	var game := a_decant()
	game.tubes = [[0, 0, 1, 1], [1], [], []] as Array
	game.pour(0, 1)
	assert_eq(game.tubes[0], [0, 0], "both matching units should leave")
	assert_eq(game.tubes[1], [1, 1, 1], "and arrive")

	game.tubes = [[0, 0, 0], [1, 0], [], []] as Array
	game.history = []
	game.pour(0, 1)
	assert_eq(game.tubes[1].size(), Decant.CAPACITY, "only what fits")
	assert_eq(game.tubes[0].size(), 1)


func test_decant_undo_puts_it_back() -> void:
	var game := a_decant()
	game.tubes = [[0, 0, 1, 1], [1], [], []] as Array
	game.history = []
	game.pour(0, 1)
	game.undo()
	assert_eq(game.tubes[0], [0, 0, 1, 1])
	assert_eq(game.tubes[1], [1])
