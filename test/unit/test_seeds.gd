extends GutTest

# Seed codes get read out loud and pasted around, so the round trip matters.


func test_a_code_is_four_characters() -> void:
	for value in [0, 1, 42, 9999, 1048575]:
		assert_eq(Seeds.code(value).length(), Seeds.LENGTH)


func test_a_code_survives_the_round_trip() -> void:
	for value in [0, 1, 42, 9999, 1048575]:
		assert_eq(Seeds.parse(Seeds.code(value)), value, "%d should come back unchanged" % value)


func test_parsing_forgives_how_people_type() -> void:
	assert_eq(Seeds.parse(" a7k2 "), Seeds.parse("A7K2"))


func test_the_alphabet_avoids_letters_that_look_like_digits() -> void:
	for confusing in ["I", "O", "0", "1"]:
		assert_eq(Seeds.ALPHABET.find(confusing), -1, "%s is too easy to misread" % confusing)


func test_mixing_is_deterministic() -> void:
	assert_eq(Seeds.mix("shapes", 1234, 1), Seeds.mix("shapes", 1234, 1))


func test_levels_and_games_do_not_collide() -> void:
	assert_ne(Seeds.mix("shapes", 1234, 1), Seeds.mix("shapes", 1234, 2), "levels should differ")
	assert_ne(Seeds.mix("shapes", 1234, 1), Seeds.mix("gridlock", 1234, 1), "games should differ")


func test_the_daily_is_stable_within_a_day() -> void:
	assert_eq(Seeds.daily("shapes"), Seeds.daily("shapes"))
