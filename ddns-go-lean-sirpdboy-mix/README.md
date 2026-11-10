# ddns-go：Lean 二进制 + sirpdboy 界面

混搭方案：**后端用 Lean 的 `ddns-go`（版本更新），界面用 sirpdboy 的 JS 三页版**。

解决的原问题：Lean feed 自带的 `luci-app-ddns-go` 只做启停和状态显示，配置要靠 ddns-go 自己的 Web UI；
而 sirpdboy 的界面（控制面板 / 基础设置 / 日志）字段与 **sirpdboy 版 ddns-go** 配套，直接拿 Lean 的后端会出现
「改了端口不生效」这类问题。本目录把两边的差异对齐。

## 目录

| 路径 | 作用 |
|---|---|
| `ddns-go-files/ddns-go.init` | 覆盖 Lean `ddns-go` 包的 init（sirpdboy 版） |
| `ddns-go-files/ddns-go.conf` | 覆盖 Lean `ddns-go` 包的默认 UCI（`config basic 'config'`） |
| `luci-app-ddns-go/` | sirpdboy 的 LuCI 界面包（JS + rpcd ucode + po） |
| `apply.sh` | 把上面两部分打进 Lean 源码树，并做一致性校验 |

## 两套后端字段差异

| 用途 | Lean `ddns-go` | sirpdboy `ddns-go` | 本方案 |
|---|---|---|---|
| UCI section 类型 | `ddns-go` | `basic` | **`basic`** |
| 端口 | `listen '[::]:9876'` | `port '9876'` | `port` |
| 更新间隔 | `ttl` | `time` | `time` |
| 证书校验 | `insecure` | `skipverify` | `skipverify` |
| 服务商比对间隔 | — | `ctimes`（`-cacheTimes`） | `ctimes` |
| 延迟启动 | — | `delay` | `delay` |
| yaml 路径 | `/etc/ddns-go/config.yaml` | `/etc/ddns-go/ddns-go-config.yaml` | sirpdboy 路径 |

约定：**UCI 字段和 yaml 路径一律采用 sirpdboy 的**，因为界面里这两处是硬编码的；
二进制保持 Lean 的 `6.17.x`，它支持 `-l / -f / -cacheTimes / -dns / -noweb / -skipVerify` 全部参数。

## 使用

```bash
# 1. 准备好 Lean 源码树（含 feeds）
cd /path/to/lede
./scripts/feeds update -a
./scripts/feeds install -a

# 2. 打入混搭文件
/path/to/ddns-go-lean-sirpdboy-mix/apply.sh /path/to/lede

# 3. 选包
grep -E 'CONFIG_PACKAGE_(ddns-go|luci-app-ddns-go)=' .config   # 两个都要 =y

# 4. 编译
make package/ddns-go/clean package/luci-app-ddns-go/clean
make package/ddns-go/compile package/luci-app-ddns-go/compile V=s
```

`apply.sh` 会做三件事：

1. 用 `ddns-go-files/` 覆盖 `feeds/packages/net/ddns-go/files/`
2. 删掉 Lean feed 里的 `luci-app-ddns-go` 和 `luci-i18n-ddns-go-zh-cn`（避免同名覆盖）
3. 把 `luci-app-ddns-go/` 装到 `package/luci-app-ddns-go`

并校验「conf 的 section 类型 == 界面读的 section 类型」「界面硬编码的 yaml 路径 == init 里的路径」。

## 生效后的行为

- LuCI：服务 → DDNS-GO，三个页签（控制面板 / 基础设置 / 日志）
- 基础设置：启用、端口、更新间隔、服务商比对间隔、DNS、跳过证书校验、禁用 Web、延迟启动
- 控制面板：内嵌 `http://<host>:<port>` 的 ddns-go Web UI
- 服务名：`/etc/init.d/ddns-go`，开机自启由「启用」开关控制

## 注意

1. **不要同时启用 Lean 自带的界面**。同名包只能有一个，`apply.sh` 已删除 Lean 那份。
2. **旧配置不兼容**。如果设备上已有 `/etc/config/ddns-go` 且 section 是 `config ddns-go 'config'`，
   新 init 读不到，需要改成 `config basic 'config'`；yaml 也要从 `config.yaml` 改名为 `ddns-go-config.yaml`。
   全新刷机没有这个问题。
3. **`logger` 字段**在默认 conf 里存在但 init 未使用，填了不生效，无害。
4. **本方案依赖 JS LuCI**（`/www/luci-static/resources/luci.js` 存在）。
   如果是 18.06 那种纯 Lua LuCI，请改用仓库里的 Lua CBI 版 `luci-app-ddns-go`。

## 组件来源

- `luci-app-ddns-go/`：`sirpdboy/luci-app-ddns-go` @ main，版本 1.6.8，Apache-2.0
- `ddns-go-files/`：同上仓库 `ddns-go/files/`，Apache-2.0
- 二进制：`coolsnowwolf/packages` 的 `net/ddns-go`，版本随 Lean 源码
