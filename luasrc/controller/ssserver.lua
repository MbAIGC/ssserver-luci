-- Copyright (C) 2026 ssserver-luci contributors
-- Licensed under GPL-3.0

module("luci.controller.ssserver", package.seeall)

function index()
	entry({"admin", "services", "ssserver"}, firstchild(), _("Shadowsocks 服务端"), 80).dependent = false

	entry({"admin", "services", "ssserver", "overview"},
		template("ssserver/overview"), _("运行概览"), 10).leaf = true

	entry({"admin", "services", "ssserver", "settings"},
		cbi("ssserver/settings"), _("服务器配置"), 20).leaf = true

	entry({"admin", "services", "ssserver", "advanced"},
		cbi("ssserver/advanced"), _("高级设置"), 30).leaf = true
end
