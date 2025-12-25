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
}

-- Track current state to avoid redundant application
local current_theme_state = nil -- stores "light" or "dark"
local timer = nil

-- Check whether the current OS is macOS
local function is_mac()
	return vim.fn.has("macunix") == 1 or vim.fn.has("mac") == 1
end

-- Apply the concrete theme settings
local function apply_theme(theme_type)
	-- Skip if already applied (debounce)
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

-- Run system command to check theme (auto mode only)
local function check_system_theme()
	local uv = vim.uv or vim.loop
	local stdout = uv.new_pipe(false)
	local stderr = uv.new_pipe(false)

	-- 'defaults read -g AppleInterfaceStyle'
	-- exit code 0 + output "Dark" => dark
	-- exit code 1 => light
	local handle, pid = uv.spawn("defaults", {
		args = { "read", "-g", "AppleInterfaceStyle" },
		stdio = { nil, stdout, stderr },
	}, function(code, signal)
		stdout:read_stop()
		stderr:read_stop()
		stdout:close()
		stderr:close()

		local is_dark = (code == 0)

		vim.schedule(function()
			-- Guard: ensure mode is still auto before applying
			if config.mode == "auto" then
				if is_dark then
					apply_theme("dark")
				else
					apply_theme("light")
				end
			end
		end)
	end)

	if handle then
		uv.read_start(stdout, function(err, data) end)
		uv.read_start(stderr, function(err, data) end)
	end
end

-- Stop the timer
local function stop_timer()
	if timer then
		timer:stop()
		if not timer:is_closing() then
			timer:close()
		end
		timer = nil
	end
end

-- Start the timer (auto mode only)
local function start_timer()
	stop_timer() -- clear any existing timer
	local uv = vim.uv or vim.loop
	timer = uv.new_timer()
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

-- Core logic to change mode
function M.set_mode(mode)
	if mode ~= "auto" and mode ~= "light" and mode ~= "dark" then
		vim.notify("Unsupported mode: " .. mode, vim.log.levels.ERROR, { title = "Auto Colorscheme" })
		return
	end

	config.mode = mode

	if mode == "auto" then
		-- Start automatic detection
		start_timer()
		vim.notify("Auto colorscheme switching enabled", vim.log.levels.INFO, { title = "Auto Colorscheme" })
	else
		-- Stop detection and force apply
		stop_timer()
		apply_theme(mode)
	end
end

-- Plugin entrypoint
function M.setup(opts)
	-- Merge user configuration
	config = vim.tbl_deep_extend("force", config, opts or {})

	-- 1. Exit early on non-macOS so other setups stay untouched
	if not is_mac() then
		return
	end

	-- 2. Create user command :AutoColorscheme [auto|light|dark]
	vim.api.nvim_create_user_command("AutoColorscheme", function(args)
		local arg = args.args
		if arg == "light" or arg == "dark" or arg == "auto" then
			M.set_mode(arg)
		else
			vim.notify("Invalid argument. Use: AutoColorscheme [light | dark | auto]", vim.log.levels.ERROR, { title = "Auto Colorscheme" })
		end
	end, {
		nargs = 1,
		complete = function()
			return { "light", "dark", "auto" }
		end,
	})

	-- 3. Initialize according to configured mode
	M.set_mode(config.mode)
end

return M
