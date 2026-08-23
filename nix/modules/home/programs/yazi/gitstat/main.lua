--- @since 26.8.15
---
--- How much the working tree differs from HEAD, in the header: the number of
--- files, and the lines added and removed. githead counts files by their state
--- — staged, unstaged, untracked — and never says how large the change is,
--- which is the number that decides whether a branch is still one commit.
---
--- Untracked files are not counted. `git diff` has nothing to compare them
--- against, and reading every one of them to count its lines would make moving
--- between directories cost as much as the files in them.

--- Runs on the UI thread, so it may touch `cx` and ask for a redraw.
--- @param cwd string The directory the numbers were gathered in.
--- @param stat table|nil `{ files, insertions, deletions }`, or nil for none.
local save = ya.sync(function(this, cwd, stat)
	-- A directory left before its `git diff` returned would otherwise write its
	-- numbers over the ones for the directory now shown.
	if cx.active.current.cwd == Url(cwd) then
		this.stat = stat
		ui.render()
	end
end)

return {
	--- @param options table|nil `changed_color`, `added_color`, `removed_color`.
	setup = function(this, options)
		options = options or {}

		local changed_color = options.changed_color or "darkgray"
		local added_color = options.added_color or "green"
		local removed_color = options.removed_color or "red"

		function Header:gitstat()
			local stat = this.stat
			if not stat then
				return ui.Line({})
			end

			local spans = {
				ui.Span(" " .. stat.files .. " changed"):fg(changed_color),
			}
			-- A deletion-only change reads as "-2" with no "+0" beside it, and the
			-- other way round; a zero carries nothing the absence does not.
			if stat.insertions > 0 then
				table.insert(spans, ui.Span(" +" .. stat.insertions):fg(added_color))
			end
			if stat.deletions > 0 then
				table.insert(spans, ui.Span(" -" .. stat.deletions):fg(removed_color))
			end

			return ui.Line(spans)
		end

		-- 2100 puts this after githead's block, which sits at 2000.
		Header:children_add(Header.gitstat, 2100, Header.LEFT)

		local callback = function()
			ya.emit("plugin", {
				this._id,
				ya.quote(tostring(cx.active.current.cwd), true),
			})
		end

		-- The same events githead listens for. Editing a file outside yazi is not
		-- among them, so the numbers are as fresh as the last move.
		ps.sub("cd", callback)
		ps.sub("rename", callback)
		ps.sub("bulk", callback)
		ps.sub("move", callback)
		ps.sub("trash", callback)
		ps.sub("delete", callback)
		ps.sub("tab", callback)
	end,

	entry = function(_, job)
		local args = job.args or job
		local cwd = args[1]

		-- Inside .git the numbers describe a repository the listing is not showing.
		if cwd:match("%.git[/\\]") or cwd:match("%.git$") then
			return save(cwd, nil)
		end

		local output = Command("git")
			:arg({ "diff", "--shortstat", "HEAD" })
			:cwd(cwd)
			-- --shortstat is prose, and it is parsed below; a translated git would
			-- otherwise report nothing rather than the wrong thing.
			:env(
				"LANGUAGE",
				"en_US.UTF-8"
			)
			:stdout(Command.PIPED)
			:output()

		-- Not a repository, or a repository without a commit yet.
		if not output or not output.status.success then
			return save(cwd, nil)
		end

		-- " 4 files changed, 215 insertions(+), 2 deletions(-)", with the clauses
		-- for zero omitted and the nouns singular at one.
		local line = output.stdout
		local files = tonumber(line:match("(%d+) files? changed")) or 0
		if files == 0 then
			return save(cwd, nil)
		end

		save(cwd, {
			files = files,
			insertions = tonumber(line:match("(%d+) insertions?%(%+%)")) or 0,
			deletions = tonumber(line:match("(%d+) deletions?%(%-%)")) or 0,
		})
	end,
}
