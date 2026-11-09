-- Copyright (C) 2026 ssserver-luci contributors
-- Licensed under GPL-3.0

local sys = require "luci.sys"
local http = require "luci.http"
local dispatcher = require "luci.dispatcher"

local m, s, o

m = Map("ssserver", translate("Shadowsocks 服务端配置"),
	translate("配置写入 /etc/config/ssserver，启动时生成 /var/etc/ssserver/config.json。" ..
		"保存后会先校验配置再重启服务，新配置起不来会自动回滚到上一份可用配置。"))

-- 保存并应用：校验 + 重启 + 失败回滚
m.on_after_commit = function(self)
	sys.call("/etc/init.d/ssserver apply >/dev/null 2>&1")
end

s = m:section(NamedSection, "main", "ssserver", translate("服务端"))
s.anonymous = true
s.addremove = false

o = s:option(Value, "server", translate("监听地址"))
o.rmempty = false
o.default = "0.0.0.0"
o.placeholder = "0.0.0.0"
o.description = translate("0.0.0.0 只监听 IPv4；:: 同时监听 IPv6（双栈）；也可填具体网卡地址或主机名。")
function o.validate(self, value)
	if not value or value == "" then
		return nil, translate("监听地址不能为空")
	end
	local a, b, c, d = value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if a then
		for _, v in ipairs({ a, b, c, d }) do
			if tonumber(v) > 255 then
				return nil, translate("IPv4 地址格式不正确")
			end
		end
		return value
	end
	if value == "0.0.0.0" or value == "::" or value == "*"
		or value:find(":", 1, true)
		or value:match("^[%w%._%-]+$") then
		return value
	end
	return nil, translate("请填写 IP 地址或主机名")
end

o = s:option(Value, "server_port", translate("监听端口"))
o.datatype = "port"
o.rmempty = false
o.default = "8388"
o.placeholder = "8388"
o.description = translate("1-65535。TCP 与 UDP 共用同一端口。")

o = s:option(Value, "password", translate("连接密码"))
o.password = true
o.rmempty = false
o.description = translate("使用 2022-blake3-* 时这里填 base64 预共享密钥" ..
	"（aes-128-gcm 需 24 字符，其余两个需 44 字符）。")

local btn = s:option(Button, "_genpw", translate("随机密码"))
btn.inputtitle = translate("生成")
btn.inputstyle = "apply"
function btn.write(self, section)
	local pw = sys.exec("head -c 64 /dev/urandom | md5sum | cut -c1-32")
	pw = (pw or ""):gsub("%s+", "")
	if pw ~= "" then
		self.map.uci:set("ssserver", section, "password", pw)
		self.map.uci:commit("ssserver")
	end
	http.redirect(dispatcher.build_url("admin/services/ssserver/settings"))
end

o = s:option(ListValue, "method", translate("加密方式"))
o.rmempty = false
o.default = "aes-256-gcm"
o:value("aes-256-gcm", "AEAD · AES-256-GCM（推荐）")
o:value("aes-128-gcm", "AEAD · AES-128-GCM")
o:value("chacha20-ietf-poly1305", "AEAD · ChaCha20-IETF-Poly1305")
o:value("xchacha20-ietf-poly1305", "AEAD · XChaCha20-IETF-Poly1305")
o:value("2022-blake3-aes-256-gcm", "2022 · blake3-aes-256-gcm（44 字符密钥）")
o:value("2022-blake3-aes-128-gcm", "2022 · blake3-aes-128-gcm（24 字符密钥）")
o:value("2022-blake3-chacha20-poly1305", "2022 · blake3-chacha20-poly1305（44 字符密钥）")
o.description = translate("只提供 AEAD 与 2022 两类安全算法；rc4-md5、*-cfb 等已废弃算法会被后端拒绝。" ..
	"2022 类需要设备上的 ssserver 编译时启用了 aead-cipher-2022。")

o = s:option(ListValue, "mode", translate("协议模式"))
o.rmempty = false
o.default = "tcp_and_udp"
o:value("tcp_and_udp", translate("TCP + UDP"))
o:value("tcp_only", translate("仅 TCP"))
o:value("udp_only", translate("仅 UDP"))
o.description = translate("对应 ssserver 的 mode 字段。UDP 需要客户端与服务端同时启用。")

o = s:option(DummyValue, "_note", translate("防火墙"))
o.rawhtml = true
o.cfgvalue = function(self, section)
	return translate("本插件不修改防火墙。若外部连不上，请自行在「网络 → 防火墙 → 通信规则」" ..
		"放行上面的地址与端口（TCP 和 UDP 都要）。")
end

return m
