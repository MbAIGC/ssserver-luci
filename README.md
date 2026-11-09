# ssserver-luci

LuCI 界面，用来管理**系统里已经装好**的 [shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust)
服务端（`ssserver`）。

本仓库派生自 [9566618/shadowproxy](https://github.com/9566618/shadowproxy)（GPLv3），
在其 LuCI 页面骨架与打包方式上做了大幅精简：

| 项 | 上游 | 本仓库 |
|---|---|---|
| 角色 | 路由器当**客户端**（sslocal + TProxy） | 路由器当**服务端**（ssserver） |
| 二进制 | 仓库内置 8 个架构的 `sslocal`（>50MB） | 不打包任何二进制，依赖系统已装的 ssserver |
| 包架构 | 每个架构一个 IPK | `PKGARCH:=all`，一个 IPK 通吃 |
| 防火墙 | 写 nftables 表、改 ip rule、改 dnsmasq | **完全不碰** |
| DNS / ACL / TProxy | 有 | 已全部移除 |

## 它能做什么

- 查看服务运行状态（取 procd/ubus 的真实进程状态，不是读 UCI 开关）
- 配置监听地址、端口、密码、加密方式、`mode`（TCP/UDP）
- 启动、停止、重启
- 开机自启开关
- 查看日志（syslog，密码自动脱敏）
- 保存与"保存并应用"分离；应用失败自动回滚到上一份可用配置

## 它不做什么

- 不创建、不修改、不删除任何防火墙规则
- 不执行 `iptables` / `ip6tables` / `nft`
- 不做 DNS 分流、TProxy、ACL、多节点、负载均衡
- 不打包、不升级 `ssserver` 二进制

> **装了连不上？** 那通常是防火墙没放行。请在「运行概览」看到实际监听地址和端口后，
> 自行在 *网络 → 防火墙 → 通信规则* 放行（TCP 和 UDP 都要）。插件不会替你做这件事。

## 目录结构

```
ssserver-luci/
├── Makefile                                  # OpenWrt 包定义（PKGARCH:=all）
├── root/
│   ├── etc/config/ssserver                   # UCI 默认配置（权限 600）
│   ├── etc/init.d/ssserver                   # procd 服务：生成 JSON、校验、回滚
│   ├── etc/uci-defaults/90-ssserver-luci     # 首次安装生成随机密码
│   └── usr/share/
│       ├── luci/menu.d/ssserver-luci.json    # 菜单
│       └── rpcd/acl.d/ssserver-luci.json     # 浏览器侧权限
├── htdocs/luci-static/resources/view/ssserver/
│   ├── overview.js                           # 运行概览
│   ├── settings.js                           # 服务器配置
│   └── advanced.js                           # 高级设置
├── tools/
│   ├── lint.sh                               # 语法检查 + 防火墙关键词检查
│   └── test-initd.sh                         # init.d 校验/JSON 生成自测
└── .github/workflows/build.yml               # 用 OpenWrt 24.10.5 SDK 出 IPK
```

## 前置条件

目标设备上必须已有 `ssserver`：

```sh
opkg list-installed | grep -i shadowsocks
command -v ssserver          # 期望 /usr/bin/ssserver
ssserver --version
```

官方 `openwrt/packages` 的 24.10 分支里没有这个包，通常来自 ImmortalWrt 系 feed
（包名 `shadowsocks-rust-ssserver`）。装好后本插件直接复用，**不会**覆盖它。

## 安装

### 方式一：GitHub Actions 产物（推荐）

每次 push 会并行跑两个 job，因为不同固件的包管理器不一样：

| 固件 | 产物 | 安装 |
|---|---|---|
| 24.10.x（opkg） | `ssserver-luci_1.0.0-r1_all.ipk` | `opkg install /tmp/*.ipk` |
| snapshot（apk） | `ssserver-luci-1.0.0-r1.apk` | `apk add --allow-untrusted /tmp/*.apk` |

判断方法：设备上 `command -v apk` 有输出就是 snapshot，`command -v opkg` 有输出就是 24.10。

```sh
scp ssserver-luci_* root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'opkg install /tmp/ssserver-luci_*.ipk'       # 或
ssh root@192.168.1.1 'apk add --allow-untrusted /tmp/ssserver-luci-*.apk'
```

APK 是自己打的、没有 OpenWrt 官方签名，所以必须带 `--allow-untrusted`
（或先把本机公钥加进 `/etc/apk/keys`）。

给 tag 打 `v*`（如 `git tag v1.0.0 && git push --tags`）会自动创建 Release 并同时附带两种包。

### 方式二：手动拷贝（不用编译）

包是纯脚本，直接覆盖文件即可：

```sh
scp -r root/*   root@192.168.1.1:/
scp -r htdocs/* root@192.168.1.1:/www/
ssh root@192.168.1.1 '
    /etc/uci-defaults/90-ssserver-luci
    chmod 600 /etc/config/ssserver
    rm -rf /tmp/luci-indexcache.* /tmp/luci-modulecache
    /etc/init.d/rpcd reload
'
```

手动拷贝不会写入 opkg 的 conffiles 记录，后续升级请重复上述步骤。

### 安装后

浏览器 **服务 → Shadowsocks 服务端**。首次安装会自动生成 32 位随机密码，
在「服务器配置」里点密码框右侧的眼睛或直接 `uci get ssserver.main.password` 查看。

## 命令行

```sh
/etc/init.d/ssserver start      # 校验配置后启动
/etc/init.d/ssserver stop
/etc/init.d/ssserver status     # running <pid> / stopped
/etc/init.d/ssserver state      # enabled / disabled（开机自启）
/etc/init.d/ssserver apply      # 校验 + 重启，失败自动回滚
/etc/init.d/ssserver enable     # 开机自启
/etc/init.d/ssserver disable
/etc/init.d/ssserver reload     # 等同 apply
```

## 配置项

`/etc/config/ssserver`：

| UCI 选项 | 对应 JSON 字段 | 说明 |
|---|---|---|
| `server` | `server` | 监听地址。`0.0.0.0` 仅 IPv4，`::` 双栈 |
| `server_port` | `server_port` | 1-65535，TCP/UDP 共用 |
| `password` | `password` | 普通口令；2022 类算法填 base64 PSK |
| `method` | `method` | 加密方式，见下 |
| `mode` | `mode` | `tcp_only` / `tcp_and_udp` / `udp_only` |
| `timeout` | `timeout` | 留空则不写该字段 |
| `no_delay` | `no_delay` | `1` → `true` |
| `keep_alive` | `keep_alive` | 秒，`0` 则不写该字段 |
| `nofile` | `nofile` | 同时用于 procd `limits` |
| `log_level` | `log.level` | `default` 表示不写 `log` 字段；也可填 0-4 |

支持的 `method`（前端列表与 init.d 白名单保持一致）：

```
aes-256-gcm  aes-128-gcm  chacha20-ietf-poly1305  xchacha20-ietf-poly1305
2022-blake3-aes-256-gcm  2022-blake3-aes-128-gcm  2022-blake3-chacha20-poly1305
```

- `rc4-md5`、`table`、`*-cfb` 等已废弃算法**不在列表内**，后端会拒绝。
- `2022-blake3-aes-128-gcm` 需要 24 字符 base64 密钥；另外两个 2022 算法需要 44 字符。
- 2022 算法要求设备上的 ssserver 编译时启用了 `aead-cipher-2022`；未启用会在启动阶段报错并回滚。

## 运行机制

1. `start_service` 读 UCI → 校验 → 生成 `/var/etc/ssserver/config.json`（临时文件 + 原子替换，权限 600）
2. `procd` 拉起 `ssserver -c /var/etc/ssserver/config.json`，密码不经命令行，`ps` 里看不到
3. `apply` 流程：校验 UCI → 生成新 JSON → 备份旧 JSON → 重启 → 等 2 秒探活 → 失败则还原旧 JSON 再重启
4. 配置目录在 tmpfs（`/var/etc`），重启后自动重建，不写 flash

## 日志

```sh
logread -e ssserver            # 插件日志 + ssserver stderr
```

插件日志用 `logger -t ssserver`，级别 `daemon.info` / `daemon.err`。
「运行概览」页面会在展示前把 UCI 里的密码替换成 `********`。

## 卸载

```sh
/etc/init.d/ssserver stop
/etc/init.d/ssserver disable
opkg remove ssserver-luci
```

`/etc/config/ssserver` 声明为 conffile，卸载后保留（删不删由你决定）。
卸载不会触碰防火墙，也不会动 `ssserver` 二进制。

## 从上游 shadowproxy 迁移

**不要直接原地升级**。上游包的 `stop_service` 才会清理它自己创建的
`inet shadowproxy-mangle` nft 表和 dnsmasq 里的 `127.0.0.1#5300`，
而它没有 `prerm`，opkg 升级/卸载不会调用 stop，残留会直接让路由器 DNS 失效。

正确顺序：

```sh
# 1) 先停旧服务，让它自己清理 nft 表和 dnsmasq
/etc/init.d/shadowproxy stop
/etc/init.d/shadowproxy disable

# 2) 确认残留已清（应当没有 shadowproxy-mangle）
nft list tables | grep shadowproxy

# 3) 卸载旧包
opkg remove shadowproxy

# 4) 再装本包
opkg install /tmp/ssserver-luci_*_all.ipk
```

第 1 步的 `stop` 是**你手动执行**的，不属于本插件行为。

## 排错

| 现象 | 处理 |
|---|---|
| 菜单里看不到 | `ls /usr/share/luci/menu.d/ssserver-luci.json`；`rm -rf /tmp/luci-*; /etc/init.d/rpcd reload` |
| 按钮报 501 / 权限错误 | ACL 没生效：`/etc/init.d/rpcd reload`，必要时重启 uhttpd |
| 点应用后服务没起来 | `logread -e ssserver` 看 `应用失败` / `回滚` 记录；常见原因是端口被占或算法不被支持 |
| 客户端连不上但服务是"运行中" | 防火墙/端口映射没放行，或 `server` 监听在回环地址 |
| 日志空白 | 系统没启用 syslog，或 `logread` 权限不足 |

## 开发

```sh
sh tools/lint.sh        # shell/JSON/JS 语法 + 防火墙关键词检查
sh tools/test-initd.sh  # 配置校验与 JSON 生成自测（无需 OpenWrt）
```

CI 有两条流水线：

- `ipk`：24.10.5 的 x86-64 SDK → `ssserver-luci_1.0.0-r1_all.ipk`
- `apk`：snapshot 的 x86-64 SDK（URL 每次从下载站目录里解析）→ `ssserver-luci-1.0.0-r1.apk`

包都是 `all` 架构，与 SDK 的 target 无关，x86_64/arm 设备都能装。如需换 SDK 版本，改 `.github/workflows/build.yml` 里的
`SDK_VERSION` / `SDK_URL` 两处；换了 SDK 记得同步改缓存 key，否则会命中旧 tarball。

workflow 里已内置两道保险：

1. `tools/lint.sh`：shell / JSON / JS 语法 + 防火墙关键词检查
2. 构建后解包 IPK 校验 8 个文件是否都在，缺一个就失败

首次在 GitHub 上跑如果卡在 `make defconfig`，多半是 SDK 版本与缓存不匹配，
删掉 cache 重跑即可。

## 许可证

GPL-3.0，见 [LICENSE](LICENSE)。本仓库是上游 GPLv3 项目的衍生作品。
