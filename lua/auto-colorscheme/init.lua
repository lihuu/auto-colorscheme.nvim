local M = {}

-- Default configuration
local config = {
	-- Operating mode: "auto" (follow system), "light" (force light), "dark" (force dark)
	mode = "auto",
	-- Polling interval in milliseconds
	interval = 2000,
	-- Colorscheme when dark mode is active
	darkScheme = "tokyonight",
	-- Colorscheme when light mode is active
	lightScheme = "dayfox",
	-- Show notification when switching
	notify = true,

	-- If system theme cannot be detected, notify once (only in auto mode)
	notify_on_unsupported = true,
}

-- Track current state to avoid redundant application
local current_theme_state = nil -- stores "light" or "dark"
local timer = nil
local warned_unsupported = false

-- macOS event watcher (prefer events over polling)
local fs_watcher = nil
local debounce_timer = nil

-- -----------------------------
-- Platform helpers
-- -----------------------------
local function is_mac()
	return vim.fn.has("macunix") == 1 or vim.fn.has("mac") == 1
end

local function is_win()
	return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

local function is_linux()
	return vim.fn.has("linux") == 1
end

-- -----------------------------
-- Async command runner (uv.spawn)
-- -----------------------------
local function spawn_capture(cmd, args, on_exit)
	local uv = vim.uv or vim.loop
	local stdout = uv.new_pipe(false)
	local stderr = uv.new_pipe(false)

	if not stdout or not stderr then
		on_exit(999, "", "failed to create pipes")
		return
	end

	local out_chunks, err_chunks = {}, {}

	local handle
	handle = uv.spawn(cmd, {
		args = args,
		stdio = { nil, stdout, stderr },
		verbatim = false,
		detached = false,
		hide = true,
	}, function(code, _)
		if stdout then
			stdout:read_stop()
			stdout:close()
		end
		if stderr then
			stderr:read_stop()
			stderr:close()
		end
		if handle and not handle:is_closing() then
			handle:close()
		end

		local out = table.concat(out_chunks)
		local err = table.concat(err_chunks)
		on_exit(code or 999, out, err)
	end)

	if not handle then
		-- spawn failed
		if stdout then
			stdout:close()
		end
		if stderr then
			stderr:close()
		end
		on_exit(999, "", "spawn failed: " .. tostring(cmd))
		return
	end

	uv.read_start(stdout, function(_, data)
		if data then
			table.insert(out_chunks, data)
		end
	end)
	uv.read_start(stderr, function(_, data)
		if data then
			table.insert(err_chunks, data)
		end
	end)
end
-- -----------------------------
-- Platform detectors
-- -----------------------------
-- macOS: defaults read -g AppleInterfaceStyle
local function detect_macos(cb)
	spawn_capture("defaults", { "read", "-g", "AppleInterfaceStyle" }, function(code, _, _)
		-- exit code 0 => dark (output usually "Dark")
		-- exit code 1 => light
		if code == 0 then
			cb("dark")
		elseif code == 1 then
			cb("light")
		else
			cb(nil)
		end
	end)
end

-- Windows: registry HKCU\...\Personalize\AppsUseLightTheme
-- 1 => light, 0 => dark
local function detect_windows(cb)
	-- Prefer pwsh, fallback to powershell
	local ps = nil
	if vim.fn.executable("pwsh") == 1 then
		ps = "pwsh"
	elseif vim.fn.executable("powershell") == 1 then
		ps = "powershell"
	end

	if ps then
		local script =
			"(Get-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize' -Name AppsUseLightTheme -ErrorAction SilentlyContinue).AppsUseLightTheme"
		spawn_capture(ps, { "-NoProfile", "-Command", script }, function(code, out, _)
			if code ~= 0 then
				cb(nil)
				return
			end
			local v = (out or ""):match("(%d+)")
			if v == "1" then
				cb("light")
			elseif v == "0" then
				cb("dark")
			else
				cb(nil)
			end
		end)
		return
	end

	-- Fallback: reg.exe query
	if vim.fn.executable("reg") == 1 then
		spawn_capture("reg", {
			"query",
			"HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
			"/v",
			"AppsUseLightTheme",
		}, function(code, out, _)
			if code ~= 0 then
				cb(nil)
				return
			end
			-- typical: AppsUseLightTheme    REG_DWORD    0x1
			local hex = (out or ""):match("0x(%x+)")
			if not hex then
				cb(nil)
				return
			end
			local n = tonumber(hex, 16)
			if n == 1 then
				cb("light")
			elseif n == 0 then
				cb("dark")
			else
				cb(nil)
			end
		end)
		return
	end

	cb(nil)
end

-- Linux (best-effort):
-- 1) GNOME: gsettings get org.gnome.desktop.interface color-scheme
--    => 'prefer-dark' / 'default'
-- 2) GNOME: gsettings get org.gnome.desktop.interface gtk-theme (contains "dark")
local function detect_linux(cb)
	if vim.fn.executable("gsettings") ~= 1 then
		cb(nil)
		return
	end

	-- Try GNOME 42+ color-scheme first
	spawn_capture("gsettings", { "get", "org.gnome.desktop.interface", "color-scheme" }, function(code, out, _)
		if code == 0 and out then
			local s = out:lower()
			if s:find("prefer%-dark", 1, true) then
				cb("dark")
				return
			elseif s:find("default", 1, true) or s:find("prefer%-light", 1, true) then
				cb("light")
				return
			end
		end

		-- Fallback to gtk-theme name
		spawn_capture("gsettings", { "get", "org.gnome.desktop.interface", "gtk-theme" }, function(code2, out2, _)
			if code2 ~= 0 or not out2 then
				cb(nil)
				return
			end
			-- out2 like: 'Adwaita-dark' or 'Yaru'
			local theme = out2:gsub("[\r\n]", ""):gsub("'", ""):lower()
			if theme:find("dark", 1, true) then
				cb("dark")
			else
				cb("light")
			end
		end)
	end)
end

-- -----------------------------
-- Theme application
-- -----------------------------
local function apply_theme(theme_type)
	if theme_type == current_theme_state then
		return
	end

	current_theme_state = theme_type

	vim.schedule(function()
		if theme_type == "dark" then
			vim.o.background = "dark"
			if config.darkScheme and config.darkScheme ~= "" then
				pcall(vim.cmd.colorscheme, config.darkScheme)
			end
			if config.notify then
				vim.notify("Theme switched: Dark mode", vim.log.levels.INFO, { title = "Auto Colorscheme" })
			end
		else
			vim.o.background = "light"
			if config.lightScheme and config.lightScheme ~= "" then
				pcall(vim.cmd.colorscheme, config.lightScheme)
			end
			if config.notify then
				vim.notify("Theme switched: Light mode", vim.log.levels.INFO, { title = "Auto Colorscheme" })
			end
		end
	end)
end

-- -----------------------------
-- Debounce helper
-- -----------------------------
local function debounce(fn, ms)
	local uv = vim.uv or vim.loop
	if debounce_timer then
		debounce_timer:stop()
		if not debounce_timer:is_closing() then
			debounce_timer:close()
		end
		debounce_timer = nil
	end

	debounce_timer = uv.new_timer()
	if not debounce_timer then
		-- If timer cannot be created, just run immediately.
		fn()
		return
	end

	debounce_timer:start(
		ms,
		0,
		vim.schedule_wrap(function()
			fn()
		end)
	)
end

-- -----------------------------
-- macOS watcher: listen to system preference changes
-- -----------------------------
local function stop_macos_watcher()
	if fs_watcher then
		pcall(function()
			fs_watcher:stop()
		end)
		if not fs_watcher:is_closing() then
			fs_watcher:close()
		end
		fs_watcher = nil
	end
end

-- -----------------------------
-- Unified system theme check
-- -----------------------------
local function check_system_theme()
	local function on_detected(theme)
		vim.schedule(function()
			if config.mode ~= "auto" then
				return
			end
			if theme == "dark" then
				apply_theme("dark")
				warned_unsupported = false
			elseif theme == "light" then
				apply_theme("light")
				warned_unsupported = false
			else
				if config.notify_on_unsupported and not warned_unsupported then
					warned_unsupported = true
					vim.notify(
						"Auto Colorscheme: system theme detection not supported or failed on this environment.",
						vim.log.levels.WARN,
						{ title = "Auto Colorscheme" }
					)
				end
			end
		end)
	end

	if is_mac() then
		detect_macos(on_detected)
	elseif is_win() then
		detect_windows(on_detected)
	elseif is_linux() then
		detect_linux(on_detected)
	else
		on_detected(nil)
	end
end

local function start_macos_watcher()
	stop_macos_watcher()

	local uv = vim.uv or vim.loop
	local home = vim.fn.expand("~")
	local path = home .. "/Library/Preferences/.GlobalPreferences.plist"

	-- If the file doesn't exist (rare), fall back to polling.
	if vim.fn.filereadable(path) ~= 1 then
		return false
	end

	fs_watcher = uv.new_fs_event()
	if not fs_watcher then
		return false
	end

	local ok = pcall(function()
		fs_watcher:start(path, {}, function(_, _)
			-- Changes can fire multiple times; debounce to avoid rapid colorscheme switches.
			debounce(check_system_theme, 150)
		end)
	end)

	if not ok then
		stop_macos_watcher()
		return false
	end

	-- Run once to sync immediately.
	check_system_theme()
	return true
end

-- -----------------------------
-- Timer control
-- -----------------------------
local function stop_timer()
	-- stop polling timer
	if timer then
		timer:stop()
		if not timer:is_closing() then
			timer:close()
		end
		timer = nil
	end

	-- stop macOS event watcher (if any)
	stop_macos_watcher()
end

local function start_timer()
	stop_timer()
	local uv = vim.uv or vim.loop
	timer = uv.new_timer()
	if timer == nil then
		vim.notify("Failed to create timer", vim.log.levels.ERROR, { title = "Auto Colorscheme" })
		return
	end

	timer:start(
		0,
		config.interval,
		vim.schedule_wrap(function()
			if config.mode == "auto" then
				check_system_theme()
			end
		end)
	)
end

local function start_auto_monitoring()
	-- Prefer event-driven watching on macOS, fall back to polling if unavailable.
	if is_mac() then
		local ok = start_macos_watcher()
		if ok then
			return
		end
	end

	-- Windows/Linux (and mac fallback) keep polling behavior.
	start_timer()
end

-- -----------------------------
-- Public API
-- -----------------------------
function M.set_mode(mode)
	if mode ~= "auto" and mode ~= "light" and mode ~= "dark" then
		vim.notify("Unsupported mode: " .. mode, vim.log.levels.ERROR, { title = "Auto Colorscheme" })
		return
	end

	config.mode = mode

	if mode == "auto" then
		start_auto_monitoring()
		vim.notify("Auto colorscheme switching enabled", vim.log.levels.INFO, { title = "Auto Colorscheme" })
	else
		stop_timer()
		apply_theme(mode)
	end
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})

	-- Create user command :AutoColorscheme [auto|light|dark]
	vim.api.nvim_create_user_command("AutoColorscheme", function(args)
		local arg = args.args
		if arg == "light" or arg == "dark" or arg == "auto" then
			M.set_mode(arg)
		else
			vim.notify(
				"Invalid argument. Use: AutoColorscheme [light | dark | auto]",
				vim.log.levels.ERROR,
				{ title = "Auto Colorscheme" }
			)
		end
	end, {
		nargs = 1,
		complete = function()
			return { "light", "dark", "auto" }
		end,
	})

	-- Initialize according to configured mode
	M.set_mode(config.mode)
end

return M
