extends RefCounted
## Rules shared by the game scene, menu shell and save boundary.

enum Mode { CAMPAIGN, LANDING_PRACTICE }

static func is_landing_practice(mode: int) -> bool:
	return mode == Mode.LANDING_PRACTICE

static func allows_save(mode: int) -> bool:
	return mode == Mode.CAMPAIGN

static func starts_with_large_ils(mode: int) -> bool:
	return is_landing_practice(mode)

static func keeps_storms_clear(mode: int) -> bool:
	return is_landing_practice(mode)
