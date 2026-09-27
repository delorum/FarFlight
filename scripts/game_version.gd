extends RefCounted

const FALLBACK_VERSION := "0.0.0"

static var _worktree_dirty_cache := -1

static func base_version() -> String:
	var configured := str(ProjectSettings.get_setting("application/config/version", FALLBACK_VERSION)).strip_edges()
	return configured if is_valid(configured) else FALLBACK_VERSION

static func display_version() -> String:
	return "v%s%s" % [base_version(), "-dev" if worktree_is_dirty() else ""]

static func is_valid(version: String) -> bool:
	var parts := version.split(".")
	if parts.size() != 3 or parts[0] != "0":
		return false
	for part in parts:
		if part.is_empty() or not part.is_valid_int() or int(part) < 0 or str(int(part)) != part:
			return false
	return true

static func worktree_is_dirty() -> bool:
	if _worktree_dirty_cache >= 0:
		return _worktree_dirty_cache == 1
	_worktree_dirty_cache = 0
	# Exported builds have no repository to inspect. The development suffix is
	# only intended to distinguish local source-tree runs from committed builds.
	if OS.has_feature("web") or not OS.is_debug_build():
		return false
	var output: Array = []
	var project_directory := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var exit_code := OS.execute(
		"git",
		PackedStringArray(["-C", project_directory, "status", "--porcelain", "--untracked-files=normal"]),
		output,
		true
	)
	if exit_code == 0 and not "".join(output).strip_edges().is_empty():
		_worktree_dirty_cache = 1
	return _worktree_dirty_cache == 1
