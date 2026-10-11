class_name KgCombat
extends RefCounted
## Attack-vs-defense dice fight resolution (doc section 3). Board-agnostic:
## takes die sizes and rolls, returns an outcome Dictionary.
##
## Order of checks (see report for why):
##   1. Attacker natural 1 on d8+  -> fumble (action fails, nobody removed).
##   2. Attacker natural max on d8+ -> crit (always captures the defender).
##   3. attacker_total > defender_total -> attacker wins.
##   4. Otherwise defender wins (defender wins ties); attacker is removed.
## Crit and fumble use the NATURAL roll; win/lose uses natural + modifier.
## allow_crit = false is used for a crit's bonus action: a bonus action can
## never crit, so a natural max there is judged as a normal roll (no push,
## no further bonus). Fumbles still apply on bonus actions.

const RESULT_CRIT: String = "crit"
const RESULT_ATTACKER_WIN: String = "attacker_win"
const RESULT_DEFENDER_WIN: String = "defender_win"
const RESULT_FUMBLE: String = "fumble"


## Resolves one fight from known natural rolls. Returns {} on invalid input.
static func resolve(attacker_sides: int, defender_sides: int, attacker_natural: int,
		defender_natural: int, attacker_modifier: int = 0, defender_modifier: int = 0,
		allow_crit: bool = true) -> Dictionary:
	if not KgDice.is_valid_die(attacker_sides) or not KgDice.is_valid_die(defender_sides):
		push_error("KgCombat.resolve: invalid die d%d vs d%d" % [attacker_sides, defender_sides])
		return {}
	if attacker_natural < 1 or attacker_natural > attacker_sides \
			or defender_natural < 1 or defender_natural > defender_sides:
		push_error("KgCombat.resolve: roll out of range")
		return {}
	var attacker_total: int = attacker_natural + attacker_modifier
	var defender_total: int = defender_natural + defender_modifier
	var natural_crit: bool = KgDice.is_crit(attacker_sides, attacker_natural)
	var crit: bool = natural_crit and allow_crit
	var fumble: bool = KgDice.is_fumble(attacker_sides, attacker_natural)
	var result: String
	var tie: bool = false
	if fumble:
		result = RESULT_FUMBLE
	elif crit:
		result = RESULT_CRIT
	elif attacker_total > defender_total:
		result = RESULT_ATTACKER_WIN
	else:
		result = RESULT_DEFENDER_WIN
		tie = attacker_total == defender_total
	return {
		"attacker_sides": attacker_sides,
		"defender_sides": defender_sides,
		"attacker_natural": attacker_natural,
		"defender_natural": defender_natural,
		"attacker_modifier": attacker_modifier,
		"defender_modifier": defender_modifier,
		"attacker_total": attacker_total,
		"defender_total": defender_total,
		"result": result,
		"is_crit": crit,
		"crit_suppressed": natural_crit and not allow_crit,
		"is_fumble": fumble,
		"is_tie": tie,
		"defender_removed": result == RESULT_CRIT or result == RESULT_ATTACKER_WIN,
		"attacker_removed": result == RESULT_DEFENDER_WIN,
	}


## Rolls both dice with rng, then resolves.
static func roll_and_resolve(rng: RandomNumberGenerator, attacker_sides: int, defender_sides: int,
		attacker_modifier: int = 0, defender_modifier: int = 0, allow_crit: bool = true) -> Dictionary:
	var a: int = KgDice.roll(rng, attacker_sides)
	var d: int = KgDice.roll(rng, defender_sides)
	return resolve(attacker_sides, defender_sides, a, d, attacker_modifier, defender_modifier, allow_crit)


## Exact odds by enumerating every (attacker, defender) natural-roll pair.
## Counts are out of "total_outcomes" = attacker_sides * defender_sides.
## "attacker_capture" = crit + attacker_win (defender removed).
static func exact_odds(attacker_sides: int, defender_sides: int,
		attacker_modifier: int = 0, defender_modifier: int = 0, allow_crit: bool = true) -> Dictionary:
	var counts: Dictionary = _empty_counts()
	if not KgDice.is_valid_die(attacker_sides) or not KgDice.is_valid_die(defender_sides):
		push_error("KgCombat.exact_odds: invalid die")
		return {}
	for a in range(1, attacker_sides + 1):
		for d in range(1, defender_sides + 1):
			_tally(counts, resolve(attacker_sides, defender_sides, a, d, attacker_modifier, defender_modifier, allow_crit))
	return _finish(counts, attacker_sides * defender_sides)


## Monte Carlo estimate with the same output shape as exact_odds.
static func monte_carlo(rng: RandomNumberGenerator, attacker_sides: int, defender_sides: int,
		trials: int, attacker_modifier: int = 0, defender_modifier: int = 0, allow_crit: bool = true) -> Dictionary:
	var counts: Dictionary = _empty_counts()
	for i in range(trials):
		_tally(counts, roll_and_resolve(rng, attacker_sides, defender_sides, attacker_modifier, defender_modifier, allow_crit))
	return _finish(counts, trials)


static func _empty_counts() -> Dictionary:
	return {RESULT_CRIT: 0, RESULT_ATTACKER_WIN: 0, RESULT_DEFENDER_WIN: 0, RESULT_FUMBLE: 0, "tie": 0}


static func _tally(counts: Dictionary, outcome: Dictionary) -> void:
	var r: String = outcome["result"]
	counts[r] = int(counts[r]) + 1
	if bool(outcome["is_tie"]):
		counts["tie"] = int(counts["tie"]) + 1


static func _finish(counts: Dictionary, total: int) -> Dictionary:
	var capture: int = int(counts[RESULT_CRIT]) + int(counts[RESULT_ATTACKER_WIN])
	var t: float = float(total)
	return {
		"total_outcomes": total,
		"counts": counts,
		"attacker_capture_count": capture,
		"p_attacker_capture": capture / t,
		"p_crit": int(counts[RESULT_CRIT]) / t,
		"p_attacker_win_plain": int(counts[RESULT_ATTACKER_WIN]) / t,
		"p_defender_win": int(counts[RESULT_DEFENDER_WIN]) / t,
		"p_fumble": int(counts[RESULT_FUMBLE]) / t,
		"p_tie": int(counts["tie"]) / t,
	}
