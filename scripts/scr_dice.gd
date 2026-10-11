class_name KgDice
extends RefCounted
## Dice rules from the Game Master Reference Document, section 3 (Core Mechanics).
## Pure static helpers: no board, no UI. All rolls go through a caller-supplied
## RandomNumberGenerator so results are seedable and reproducible.

## Die sizes used by the game (d4, d6, d8, d10, d12).
const VALID_SIDES: Array = [4, 6, 8, 10, 12]

## Smallest die that can crit or fumble. Doc: only d8, d10, d12 crit/fumble;
## d4 and d6 never do.
const CRIT_FUMBLE_MIN_SIDES: int = 8

## Default piece dice from the doc: Pawn d4; Knight and Bishop d6; Rook d8;
## Queen d10; King d12. The live game reads these from the ledger's
## "piece_stats"; this table is only used to build a fresh ledger.
const DEFAULT_PIECE_DIE_SIDES: Dictionary = {
	"pawn": 4,
	"knight": 6,
	"bishop": 6,
	"rook": 8,
	"queen": 10,
	"king": 12,
}


## True if sides is one of the game's dice.
static func is_valid_die(sides: int) -> bool:
	return VALID_SIDES.has(sides)


## True if a die of this size can crit (d8, d10, d12).
static func can_crit(sides: int) -> bool:
	return is_valid_die(sides) and sides >= CRIT_FUMBLE_MIN_SIDES


## True if a die of this size can fumble (d8, d10, d12).
static func can_fumble(sides: int) -> bool:
	return is_valid_die(sides) and sides >= CRIT_FUMBLE_MIN_SIDES


## Crit = natural max roll on a crit-capable die.
static func is_crit(sides: int, natural_roll: int) -> bool:
	return can_crit(sides) and natural_roll == sides


## Fumble = natural 1 on a fumble-capable die.
static func is_fumble(sides: int, natural_roll: int) -> bool:
	return can_fumble(sides) and natural_roll == 1


## Rolls one die: uniform integer in [1, sides].
static func roll(rng: RandomNumberGenerator, sides: int) -> int:
	if not is_valid_die(sides):
		push_error("KgDice.roll: invalid die d%d" % sides)
		return 0
	return rng.randi_range(1, sides)


## Builds a seeded RNG (use a fixed seed in tests for reproducible rolls).
static func make_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Next die size up (Promotion card: "upgrade a piece's die one size").
## d12 is the largest die, so d12 stays d12.
static func step_up(sides: int) -> int:
	var i: int = VALID_SIDES.find(sides)
	if i < 0:
		push_error("KgDice.step_up: invalid die d%d" % sides)
		return sides
	return int(VALID_SIDES[mini(i + 1, VALID_SIDES.size() - 1)])
