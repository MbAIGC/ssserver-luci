# ssserver-luci

一个仓库，两个 OpenWrt LuCI 插件，都是 **Lua CBI** 实现，专门适配使用
**Lua 派发器**的 LuCI（LEDE / Lean / 带 `luci-compat` 的固件）。

| 插件 | 作用 | 版本 |
|---|---|---|
| [`ssserver-luci/`](ssserver-luci/) | 管理系统中已安装的 Shadowsocks Rust 服务端（`ssserver`） | 1.0.3 |
| [`luci-app-ddns-go/`](luci-app-ddns-go/) | DDNS-GO 的 LuCI 界面（控制面板 / 基础设置 / 日志） | 1.6.9 |

## 为什么是 Lua CBI

目标固件（LEDE / Lean 系）的 `/cgi-bin/luci` 由 Lua 派发器处理：

```sh
uci -q get uhttpd.main.ucode_prefix      # 空 → Lua 派发器
ls /www/luci-static/resources/luci.js    # 不存在 → 没有 JS 前端
```

而现在很多插件是 **ucode + JS** 形态（`menu.d/*.json` + `view/*.js`）：
Lua 派发器不读 `menu.d`，也没有 JS 加载器，装了只会「菜单里看不到」。
所以这里的页面全部写成 `luasrc/controller` + `luasrc/model/cbi` + `luasrc/view/*.htm`。

## 目录结构

一个插件一个文件夹：

```
.
├── ssserver-luci/                     # 插件一（包名 ssserver-luci）
│   ├── Makefile                       # 纯 package.mk，PKGARCH:=all
│   ├── root/
│   │   ├── etc/config/ssserver
│   │   ├── etc/init.d/ssserver        # procd：生成 JSON、校验、失败回滚
│   │   └── etc/uci-defaults/90-ssserver-luci
│   └── luasrc/
│       ├── controller/ssserver.lua
│       ├── model/cbi/ssserver/{settings,advanced}.lua
│       └── view/ssserver/overview.htm
├── luci-app-ddns-go/                  # 插件二（包名 luci-app-ddns-go）
│   ├── Makefile
│   ├── LICENSE                        # 该插件为 MIT（上游 sirpdboy）
│   ├── root/etc/uci-defaults/99-luci-ddns-go
│   └── luasrc/
│       ├── controller/ddns_go.lua
│       ├── model/cbi/ddns_go/config.lua
│       └── view/ddns_go/{panel,log}.htm
├── tools/lint.sh                      # shell / Lua / 模板检查
├── tools/test-initd.sh                # init.d 校验与 JSON 生成自测
└── .github/workflows/build.yml        # 一次构建两个 IPK
```

## 插件一：ssserver-luci

管理系统中**已安装**的 `ssserver`（不打包二进制，不碰防火墙）。

- 运行概览：状态 / PID / 监听 / 协议 / 算法 / 版本 / 开机自启 + 启停重启 + 日志
- 服务器配置：地址、端口、密码、算法、`mode`
- 高级设置：`no_delay`、`keep_alive`、`timeout`、`nofile`、`log_level`
- 保存即应用：先校验再重启，新配置起不来自动回滚

配置写入 `/etc/config/ssserver`，启动前生成 `/var/etc/ssserver/config.json`（tmpfs，权限 600，密码不进命令行）。
防火墙策略：**插件不创建、不修改、不删除任何防火墙规则**，端口需自行放行（TCP + UDP）。

## 插件二：luci-app-ddns-go

DDNS-GO 的界面，改造自 [sirpdboy/luci-app-ddns-go](https://github.com/sirpdboy/luci-app-ddns-go)。
上游是 ucode + JS 形态，本仓库把它整体换成 Lua。

- 控制面板：内嵌 ddns-go 自带 Web UI（未运行 / 禁用 Web / HTTPS 混合内容都有提示）
- 基础设置：启用、端口、更新间隔、比对间隔、DNS、跳过证书校验、禁用 Web、延迟启动；
  另有「重置面板密码」和「检查更新」，并显示当前版本与上次操作结果
- 日志：`logread` 过滤 ddns-go，可刷新 / 清空

依赖系统中的 `ddns-go` 包（上游 Release 里的 `ddns-go_*_x86_64.ipk`），本仓库不构建它。

## 构建

CI 用 24.10.5 的 x86-64 SDK，一次构建两个包（都是 `all` 架构，任意 24.10.x 可装）：

```sh
# 推送即构建；打 tag 自动发 Release
git tag v1.1.0 && git push origin master --tags
```

产物：

```
ssserver-luci_1.0.3-r1_all.ipk
luci-app-ddns-go_1.6.9-r1_all.ipk
```

本地检查：

```sh
sh tools/lint.sh        # shell / Lua / 模板语法
sh tools/test-initd.sh  # ssserver 的配置校验与 JSON 生成
```

## 安装

```sh
# 1) 前置：系统中已有 ssserver 与 ddns-go
opkg list-installed | grep -E 'ssserver|ddns-go'

# 2) 两个 LuCI 插件
opkg install ssserver-luci_1.0.3-r1_all.ipk
opkg install luci-app-ddns-go_1.6.9-r1_all.ipk
```

装完 postinst 会自动 `rm -f /tmp/luci-indexcache` + `rpcd restart` + `uhttpd reload`，
浏览器硬刷新即可看到 **服务 → Shadowsocks 服务端 / DDNS-GO**。

## 排错

| 现象 | 处理 |
|---|---|
| 菜单里看不到 | `ls /usr/lib/lua/luci/controller/`；`rm -f /tmp/luci-indexcache; /etc/init.d/uhttpd reload` |
| 页面 500 / 空白 | `logread \| tail -30` 看 Lua 报错 |
| opkg 提示 conffiles 冲突 | 正常：你的配置和包内默认值不同，旧配置保留，新默认放在 `-opkg` 后缀文件里，可删 |
| opkg 提示 `Command failed: Not found` | 正常：prerm 停一个没在跑的服务，ubus 返回 NOT_FOUND |

## 许可

仓库根目录为 GPL-3.0（源自 shadowproxy）；`luci-app-ddns-go/` 为 MIT（源自 sirpdboy），
各自目录下的 LICENSE 为准。
