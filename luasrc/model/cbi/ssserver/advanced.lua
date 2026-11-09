-- Copyright (C) 2026 ssserver-luci contributors
-- Licensed under GPL-3.0

local sys = require "luci.sys"

local m, s, o

m = Map("ssserver", translate("高级设置"),
	translate("这些参数直接映射到 ssserver 的配置文件字段。不确定时保持默认；" ..
		"取值非法会被后端校验拦下，服务保持原状。"))

m.on_after_commit = function(self)
	sys.call("/etc/init.d/ssserver apply >/dev/null 2>&1")
end

s = m:section(NamedSection, "main", "ssserver", translate("性能与日志"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "no_delay", translate("TCP_NODELAY"),
	translate("关闭 Nagle 算法，降低小包延迟（对应 no_delay）。"))
o.default = "0"
o.rmempty = false

o = s:option(Value, "keep_alive", translate("TCP 保活（秒）"))
o.datatype = "uinteger"
o.default = "0"
o.placeholder = "0"
o.description = translate("对应 keep_alive：开启 SO_KEEPALIVE 并设置保活间隔。填 0 表示不设置。")

o = s:option(Value, "timeout", translate("连接超时（秒）"))
o.datatype = "uinteger"
o.rmempty = true
o.placeholder = translate("留空使用默认")
o.description = translate("对应 timeout：服务端 TCP 套接字超时。")

o = s:option(Value, "nofile", translate("文件描述符上限"))
o.datatype = "uinteger"
o.default = "10240"
o.placeholder = "10240"
o.description = translate("同时写入配置文件的 nofile 与 procd 的 limits，二者保持一致。")

o = s:option(ListValue, "log_level", translate("日志等级"))
o.rmempty = false
o.default = "default"
o:value("default", translate("跟随 ssserver 默认（不写 log 字段）"))
o:value("0", "0 · 最少")
o:value("1", "1 · 错误")
o:value("2", "2 · 警告")
o:value("3", "3 · 信息")
o:value("4", "4 · 最详细（调试用）")
o.description = translate("对应配置中的 log.level（数值）。不同版本的具体档位含义可能略有差异。")

return m
