--- @since 26.8.15
---
--- The preview pane, for a file git knows about: the whole file, with the
--- lines that changed carrying a background. The status letters in a listing
--- say a file changed; this says what changed, without a keypress.
---
--- That is `git diff` asked for the whole file as context. Asking for all of
--- it is the difference between a diff and a file with its changes marked, and
--- it is why the pane still reads as source rather than as a patch.
---
--- A file with no changes is handed to yazi's own previewer, so the two look
--- alike and nothing is lost by having this one in the way.

local M = {}

local DEFAULTS = {
	git = "git",
	delta = "delta",
	--- Context lines. Large enough to reach the end of any file worth reading
	--- in a pane; `git diff` clamps it to the file's length.
	context = 99999,
	--- Appended after the arguments below, so a caller can set the syntax theme
	--- and the colours of an added and a removed line.
	delta_args = {},
}

--- Reads what setup() stored. peek() runs in its own Lua state, where the
--- upvalues setup() assigned are not the ones it sees.
local config = ya.sync(function(this)
	return this.config or DEFAULTS
end)

--- @param key string Identifies the file, its content, the pane and git's state.
--- @param skip integer Lines already scrolled past.
--- @param limit integer Lines the pane can show.
--- @return boolean hit Whether the key matches what is held.
--- @return string|nil window The lines to draw, or nil when there is no diff.
--- @return integer total Lines held, for deciding a scroll has gone too far.
local cache_read = ya.sync(function(this, key, skip, limit)
	local held = this.cache
	if not held or held.key ~= key then
		return false, nil, 0
	end
	if not held.lines then
		return true, nil, 0
	end

	local window = {}
	for i = skip + 1, math.min(skip + limit, #held.lines) do
		window[#window + 1] = held.lines[i]
	end
	return true, table.concat(window, "\n"), #held.lines
end)

--- @param lines string[]|false The rendered diff, or false for "no diff here".
local cache_write = ya.sync(function(this, key, lines)
	this.cache = { key = key, lines = lines }
end)

--- Whether the terminal is showing a light background, for delta's --dark or
--- --light. Read on the UI thread because that is where yazi keeps it.
local terminal_is_light = ya.sync(function()
	local light = rt.term.light
	if type(light) == "function" then -- TODO: remove
		light = light()
	end
	return light and true or false
end)

--- The directory holding git's own state for `dir`, remembered per directory
--- so that the subprocess it costs is paid once rather than on every redraw.
--- Asking git rather than looking for a `.git` directory is what makes this
--- right inside a linked worktree, where `.git` is a file naming another path.
--- @return string|nil The absolute git dir, or nil outside a repository.
local git_dir_cached = ya.sync(function(this, dir, resolved)
	this.git_dirs = this.git_dirs or {}
	if resolved ~= nil then
		-- false is stored for "asked, and there is no repository", which has to
		-- be told apart from "not asked yet" or every redraw asks again.
		this.git_dirs[dir] = resolved
	end
	return this.git_dirs[dir]
end)

--- Columns a string takes up on screen, once its colour escapes are removed.
--- Lua counts codepoints and a terminal counts columns, and the two disagree
--- for the ranges below, which are drawn twice as wide.
--- @param s string
--- @return integer
local function display_width(s)
	s = s:gsub("\27%[[%d;]*%a", "")
	if not utf8 then
		return #s
	end

	local width = 0
	for _, cp in utf8.codes(s) do
		local wide = (cp >= 0x1100 and cp <= 0x115F)
			or (cp >= 0x2E80 and cp <= 0xA4CF)
			or (cp >= 0xAC00 and cp <= 0xD7A3)
			or (cp >= 0xF900 and cp <= 0xFAFF)
			or (cp >= 0xFE30 and cp <= 0xFE6F)
			or (cp >= 0xFF00 and cp <= 0xFF60)
			or (cp >= 0xFFE0 and cp <= 0xFFE6)
			or (cp >= 0x1F300 and cp <= 0x1FAFF)
		width = width + (wide and 2 or 1)
	end
	return width
end

--- delta colours the rest of a changed line by asking the terminal to erase to
--- the end of it. A preview pane is not a terminal and drops the request, so
--- the background would stop at the last character. Replace it with the spaces
--- it stands for.
--- @param line string
--- @param width integer Columns the pane is wide.
--- @return string
local function fill_to_width(line, width)
	if not line:find("\27%[0K") then
		return line
	end

	local pad = string.rep(" ", math.max(0, width - display_width(line)))
	return (line:gsub("\27%[0K", pad))
end

--- The absolute git dir for a directory, asking git the first time only.
--- @param dir string
--- @return string|nil
local function git_dir(dir, cfg)
	local held = git_dir_cached(dir)
	if held ~= nil then
		return held or nil
	end

	local output = Command(cfg.git)
		:cwd(dir)
		:arg({ "rev-parse", "--absolute-git-dir" })
		:stdout(Command.PIPED)
		:stderr(Command.NULL)
		:output()

	local resolved = false
	if output and output.status.success then
		resolved = output.stdout:gsub("[\r\n]+$", "")
	end
	git_dir_cached(dir, resolved)
	return resolved or nil
end

--- What the diff of this file depends on, as a string that changes whenever
--- any of it does.
---
--- The file's own timestamp is not enough. `git commit` and `git reset --soft`
--- both change what the file differs from while leaving the file alone, and a
--- preview keyed on the file would go on showing a diff that no longer exists.
--- git writes the index on the first and HEAD on the second, so their
--- timestamps stand in for git's state without asking git anything.
--- @return string
local function cache_key(job, dir, cfg)
	local stamp = ""
	local dir_of_git = git_dir(dir, cfg)
	if dir_of_git then
		for _, name in ipairs({ "index", "HEAD" }) do
			local cha = fs.cha(Url(dir_of_git):join(name))
			stamp = stamp .. "\0" .. tostring(cha and cha.mtime or "")
		end
	end

	return table.concat({
		tostring(job.file.url),
		tostring(job.file.cha.mtime),
		tostring(job.area.w),
		stamp,
	}, "\0")
end

--- Runs git and delta, and returns the rendered lines.
--- @return string[]|false The lines, or false when the file has no changes.
local function render(job, dir, cfg)
	local delta_args = {
		"--no-gitconfig",
		terminal_is_light() and "--light" or "--dark",
		"--paging=never",
		-- The file and hunk headers describe a patch. What is wanted here is
		-- the file, so both are dropped and the gutter is left to say where in
		-- it the reader is.
		"--file-style=omit",
		"--hunk-header-style=omit",
		"--line-numbers",
		"--line-numbers-left-format=",
		"--line-numbers-right-format={np:>4} ",
		"--width=" .. job.area.w,
	}
	for _, arg in ipairs(cfg.delta_args) do
		delta_args[#delta_args + 1] = arg
	end

	local quoted = {}
	for i, arg in ipairs(delta_args) do
		quoted[i] = ya.quote(arg)
	end

	-- An unborn HEAD has nothing to diff against, so fall back to the working
	-- tree alone rather than failing on `git diff HEAD`.
	--
	-- An untracked file has no old version either, so it is diffed against
	-- nothing and every line reads as added, which is what a new file is.
	-- --no-index labels the sides 1/ and 2/ rather than a/ and b/, and delta
	-- strips only the latter, so without the prefixes below the header would
	-- carry a stray "2/".
	local script = string.format(
		[[
		name=$(basename -- "$1")
		cd -- "$(dirname -- "$1")" || exit 0
		git=%s
		"$git" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
		base=$("$git" rev-parse --verify -q HEAD >/dev/null 2>&1 && echo HEAD || true)
		if "$git" ls-files --error-unmatch -- "$name" >/dev/null 2>&1; then
			"$git" diff -U%d ${base:+"$base"} -- "$name"
		else
			"$git" diff -U%d --no-index --src-prefix=a/ --dst-prefix=b/ \
				-- /dev/null "$name" || true
		fi | %s %s
	]],
		ya.quote(cfg.git),
		cfg.context,
		cfg.context,
		ya.quote(cfg.delta),
		table.concat(quoted, " ")
	)

	local output = Command("sh")
		:arg({ "-c", script, "sh", tostring(job.file.url) })
		:cwd(dir)
		:stdout(Command.PIPED)
		:stderr(Command.NULL)
		:output()

	if not output or output.stdout == "" then
		return false
	end

	local lines = {}
	for line in output.stdout:gmatch("[^\n]*") do
		lines[#lines + 1] = fill_to_width(line, job.area.w)
	end
	-- gmatch with an empty-capable pattern yields one trailing empty string.
	if lines[#lines] == "" then
		lines[#lines] = nil
	end
	return lines
end

function M:peek(job)
	local cfg = config()
	local dir = tostring(job.file.url.parent)
	local key = cache_key(job, dir, cfg)

	local hit, window, total = cache_read(key, job.skip, job.area.h)
	if not hit then
		local lines = render(job, dir, cfg)
		cache_write(key, lines)
		hit, window, total = cache_read(key, job.skip, job.area.h)
	end

	-- No changes: yazi's own previewer, rather than a worse copy of it.
	if not window then
		return require("code"):peek(job)
	end

	-- Scrolled past the end — walk back so the last screenful stays on screen.
	if job.skip > 0 and total <= job.skip then
		return ya.emit("peek", {
			math.max(0, total - job.area.h),
			only_if = job.file.url,
			upper_bound = true,
		})
	end

	ya.preview_widget(job, ui.Text.parse(window):area(job.area))
end

--- yazi's own previewer reads a wheel unit as a tenth of the pane. Handing
--- seek back to it is what keeps this scrolling like everything else in the
--- terminal.
function M:seek(job)
	require("code"):seek(job)
end

--- @param options table|nil `git`, `delta`, `context`, `delta_args`.
function M:setup(options)
	options = options or {}

	local cfg = {}
	for key, value in pairs(DEFAULTS) do
		cfg[key] = options[key] == nil and value or options[key]
	end
	self.config = cfg
end

return M
