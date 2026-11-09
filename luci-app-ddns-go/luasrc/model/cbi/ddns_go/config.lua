-- Copyright (C) 2021-2026 sirpdboy <herboy2008@gmail.com>
-- Lua CBI adaptation for Lua-dispatching LuCI (LEDE / Lean)
-- Licensed under the MIT License

local sys        = require "luci.sys"
local http       = require "luci.http"
local dispatcher = require "luci.dispatcher"
local pcdata     = require "luci.util".pcdata

local STATE = "/tmp/ddns-go-luci.state"

local function version()
	local v = sys.exec("/usr/bin/ddns-go -v 2>/dev/null") or ""
	return v:match("(%d+%.%d+%.%d+[%w%.%-]*)") or ""
end

local function write_state(kind, text)
	local f = io.open(STATE, "w")
	if f then
		f:write(kind, "\n", text or "")
		f:close()
	end
end

local function read_state()
	local f = io.open(STATE, "r")
	if not f then
		return nil, nil
	end
	local data = f:read("*a") or ""
	f:close()
	return data:match("^(%S+)\n(.*)$")
end

local m, s, o

m = Map("ddns-go", translate("DDNS-GO 基础设置"),
	translate("对应 ddns-go 的启动参数。具体域名解析记录在「控制面板」里配置，保存在 " ..
		"/etc/ddns-go/ddns-go-config.yaml。"))

-- 保存后重启服务，让 ddns-go 重新读取参数
m.on_after_commit = function(self)
	sys.call("/etc/init.d/ddns-go restart >/dev/null 2>&1")
end

s = m:section(NamedSection, "config", "basic", translate("服务设置"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("启用"),
	translate("关闭时 /etc/init.d/ddns-go start 不会拉起进程。"))
o.default = "0"
o.rmempty = false

o = s:option(Value, "port", translate("面板端口"))
o.datatype = "port"
o.default = "9876"
o.rmempty = false
o.description = translate("ddns-go 自带 Web 面板的端口，「控制面板」页会内嵌这个地址。")

o = s:option(Value, "time", translate("更新间隔（秒）"))
o.datatype = "uinteger"
o.default = "300"
o.rmempty = false
o.description = translate("多久检查一次 IP 变化。填 0 表示不自动检查。")

o = s:option(Value, "ctimes", translate("服务商比对间隔"))
o.datatype = "uinteger"
o.default = "5"
o.description = translate("对应 -cacheTimes，两次调用服务商接口之间的最小间隔。")

o = s:option(ListValue, "dns", translate("DNS 解析服务器"))
o.default = "223.5.5.5"
o.rmempty = false
o:value("223.5.5.5", "阿里 DNS 223.5.5.5")
o:value("223.6.6.6", "阿里 DNS 223.6.6.6")
o:value("119.29.29.29", "腾讯 DNS 119.29.29.29")
o:value("1.1.1.1", "Cloudflare DNS 1.1.1.1")
o:value("8.8.8.8", "Google DNS 8.8.8.8")
o:value("8.8.4.4", "Google DNS 8.8.4.4")

o = s:option(ListValue, "skipverify", translate("跳过证书校验"))
o.default = "0"
o.rmempty = false
o:value("0", translate("否"))
o:value("1", translate("是"))

o = s:option(Flag, "noweb", translate("禁用 Web 服务"),
	translate("勾选后 ddns-go 不启动内置 Web 面板，「控制面板」页会显示为已禁用。"))
o.default = "0"
o.rmempty = false

o = s:option(Value, "delay", translate("延迟启动（秒）"))
o.datatype = "uinteger"
o.default = "60"
o.description = translate("开机后等待指定秒数再启动，避免网络还没就绪。")

o = s:option(Button, "_newpassword", translate("重置面板账号密码"))
o.inputtitle = translate("重置为 admin12345")
o.inputstyle = "apply"
o.description = translate("执行 ddns-go -resetPassword 并重启服务。重置后请立刻登录面板改掉默认密码。")
function o.write(self, section)
	local out = sys.exec("/usr/bin/ddns-go -resetPassword admin12345 -c " ..
		"/etc/ddns-go/ddns-go-config.yaml 2>&1") or ""
	sys.call("/etc/init.d/ddns-go restart >/dev/null 2>&1")
	write_state("reset", out ~= "" and out or translate("已完成，账号密码重置为 admin12345"))
	http.redirect(dispatcher.build_url("admin/services/ddns-go/config"))
end

o = s:option(Button, "_update", translate("检查更新"))
o.inputtitle = translate("检查")
o.inputstyle = "apply"
o.description = translate("执行 ddns-go -u：检查并下载新版本，会直接替换 /usr/bin/ddns-go（不经过 opkg）。")
function o.write(self, section)
	local before = version()
	local out = sys.exec("/usr/bin/ddns-go -u 2>&1") or ""
	local after = version()

	if after ~= "" and after ~= before then
		out = out .. "\n" .. string.format(translate("版本变化：%s → %s"), before, after)
	end

	write_state("update", out ~= "" and out or translate("命令没有输出"))
	http.redirect(dispatcher.build_url("admin/services/ddns-go/config"))
end

o = s:option(DummyValue, "_status", translate("版本与最近一次操作"))
o.rawhtml = true
o.cfgvalue = function(self, section)
	local ver = version()
	local kind, text = read_state()
	local html = {}

	if ver ~= "" then
		html[#html + 1] = string.format("<div>ddns-go：<strong>v%s</strong></div>", pcdata(ver))
	else
		html[#html + 1] = string.format("<div style=\"color:#c62828\">%s</div>",
			translate("未检测到 /usr/bin/ddns-go"))
	end

	if text and text ~= "" then
		local label = (kind == "update") and translate("最近一次检查更新：")
			or (kind == "reset") and translate("最近一次重置密码：") or nil

		if label then
			html[#html + 1] = string.format("<div style=\"margin-top:8px\">%s</div>", pcdata(label))
			html[#html + 1] = string.format(
				"<pre style=\"max-height:200px;overflow:auto;white-space:pre-wrap;word-break:break-all;" ..
				"font-size:12px;line-height:1.5;padding:8px;border-radius:4px;" ..
				"background:rgba(127,127,127,0.08)\">%s</pre>", pcdata(text))
		end
	end

	return table.concat(html, "\n")
end

return m
