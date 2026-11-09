-- Copyright (C) 2021-2026 sirpdboy <herboy2008@gmail.com>
-- Lua CBI adaptation for Lua-dispatching LuCI (LEDE / Lean)
-- Licensed under the MIT License

module("luci.controller.ddns_go", package.seeall)

function index()
	entry({"admin", "services", "ddns-go"}, firstchild(), _("DDNS-GO"), 58).dependent = false

	entry({"admin", "services", "ddns-go", "panel"},
		template("ddns_go/panel"), _("控制面板"), 10).leaf = true

	entry({"admin", "services", "ddns-go", "config"},
		cbi("ddns_go/config"), _("基础设置"), 20).leaf = true

	entry({"admin", "services", "ddns-go", "log"},
		template("ddns_go/log"), _("日志"), 30).leaf = true
end
