local M = {}

-- 默认配置
local config = {
	-- 运行模式: "auto" (跟随系统), "light" (强制浅色), "dark" (强制深色)
	mode = "auto",
	-- 检测频率（毫秒）
	interval = 2000,
	-- 深色模式下的配色方案
	darkScheme = "tokyonight",
	-- 浅色模式下的配色方案
	lightScheme = "dayfox",
	-- 是否在切换时打印通知
	notify = true,
}

-- 保存当前状态，避免重复设置
local current_theme_state = nil -- 记录实际应用的 "light" 或 "dark"
local timer = nil

-- 检查当前操作系统是否为 macOS
local function is_mac()
	return vim.fn.has("macunix") == 1 or vim.fn.has("mac") == 1
end

-- 应用具体的主题设置
local function apply_theme(theme_type)
	-- 如果当前已经应用了该状态，则跳过（防抖）
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
				vim.notify("主题已切换: 深色模式", vim.log.levels.INFO, { title = "Mac Auto Theme" })
			end
		else
			vim.o.background = "light"
			if config.lightScheme and config.lightScheme ~= "" then
				pcall(vim.cmd.colorscheme, config.lightScheme)
			end
			if config.notify then
				vim.notify("主题已切换: 浅色模式", vim.log.levels.INFO, { title = "Mac Auto Theme" })
			end
		end
	end)
end

-- 执行系统命令检查主题 (仅供 auto 模式使用)
local function check_system_theme()
	local uv = vim.uv or vim.loop
	local stdout = uv.new_pipe(false)
	local stderr = uv.new_pipe(false)

	-- 'defaults read -g AppleInterfaceStyle'
	-- 退出码 0 + 输出 "Dark" => 深色
	-- 退出码 1 => 浅色
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
			-- 再次确认当前模式是否仍为 auto，防止异步回调时用户已切换模式
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

-- 停止定时器
local function stop_timer()
	if timer then
		timer:stop()
		if not timer:is_closing() then
			timer:close()
		end
		timer = nil
	end
end

-- 启动定时器 (仅 auto 模式)
local function start_timer()
	stop_timer() -- 先清除旧的
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

-- 切换模式的核心逻辑
function M.set_mode(mode)
	if mode ~= "auto" and mode ~= "light" and mode ~= "dark" then
		vim.notify("不支持的模式: " .. mode, vim.log.levels.ERROR)
		return
	end

	config.mode = mode

	if mode == "auto" then
		-- 启动自动检测
		start_timer()
		vim.notify("已启用自动主题切换 (Auto Mode)", vim.log.levels.INFO, { title = "Mac Auto Theme" })
	else
		-- 停止检测，强制应用
		stop_timer()
		apply_theme(mode)
	end
end

-- 启动插件
function M.setup(opts)
	-- 合并用户配置
	config = vim.tbl_deep_extend("force", config, opts or {})

	-- 1. 非 Mac 系统直接退出，不做任何操作
	--    这样 LazyVim 的默认配置就会生效，本插件如同不存在
	if not is_mac() then
		return
	end

	-- 2. 创建用户命令 :MacTheme [auto|light|dark]
	vim.api.nvim_create_user_command("MacTheme", function(args)
		local arg = args.args
		if arg == "light" or arg == "dark" or arg == "auto" then
			M.set_mode(arg)
		else
			vim.notify("参数错误，请使用: MacTheme [light | dark | auto]", vim.log.levels.ERROR)
		end
	end, {
		nargs = 1,
		complete = function(ArgLead, CmdLine, CursorPos)
			return { "light", "dark", "auto" }
		end,
	})

	-- 3. 根据配置初始化模式
	M.set_mode(config.mode)
end

return M
