# OpenWrt x86-64 固件配置分析（2026-06-18 构建，94 MB）

- **分析对象**：`openwrt-x86-64-generic-squashfs-combined-efi.img.gz`
- **压缩大小**：94,101,030 字节
- **解压大小**：537,165,312 字节（512.28 MiB，1,049,151 个 512B 扇区）
- **SHA256（.gz）**：`338d940f95d73815168113d5edde81f4e8be76c675e9f5c4f47349f80acd1b33`
- **SHA256（解压 img）**：`cf8a3b7720d4f56b2f4768f742f21d20b1ad099b8010218c60f1bd74397aae0e`
- **分析日期**：2026-11-09
- **分析方式**：解压 → GPT/分区解析 → squashfs 解包 → 读取 `/etc/config`、`/etc/uci-defaults`、init 脚本、opkg 数据库、GRUB 配置。

> **重要：工作区还有另一个同名文件** `openwrt-x86-64-generic-squashfs-combined-efi.img (1).gz`（116 MB，2026-10-11 构建，kernel 6.18.55，451 个包），与本文件**不是同一个固件**。新构建的分析见 [`README-2026-10-11.md`](README-2026-10-11.md)。

> 说明：镜像内 `/etc/config/network` 与 `/etc/config/system` 不存在，属于“首次启动生成”的设计。下文的 LAN/WAN、主机名、时区等默认值，是按 `/bin/config_generate`、`/etc/board.d/*` 和 `/etc/uci-defaults/*` 推断出的**首次启动后**状态；未实际启动过该镜像。

---

## 0. 结论摘要

1. **这不是官方 OpenWrt 24.10.5 原版**，而是 **Lean LEDE（coolsnowwolf/lede）定制 x86-64 构建**：包元数据里有 `package/lean/default-settings`、`package/lean/luci-app-openclash`，TurboACC 维护者是 Lean；用户态仍是 **firewall3 + iptables**，不是 24.10 官方的 fw4/nftables；内核却是 **6.12.93**，LuCI 是 **26.159**。版本串 `24.10.5 / r7833-27ba2c2dd` 与内核、LuCI 年代明显不一致，首次启动还会被脚本改写成 `LEDE R26.05.20`。
2. **默认网络是“LAN 192.168.1.253/24 + WAN DHCP”**：通用 x86 机器上 LAN=eth0，WAN=eth1（存在时）；部分已知迷你主机型号会按 `/etc/board.d/02_network` 改成 WAN=eth0、LAN=eth1+。LAN DHCP 池为 `.100–.249`，租期 12h。
3. **默认 root 密码是 `password`**：镜像里的 `/etc/shadow` 目前是空密码，但首次启动的 `/etc/uci-defaults/99-default-settings` 会写入 `$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.`（已用 `openssl passwd -1 -salt V4UetPzk password` 验证匹配）。同时 `ttylogin=0`，**串口/本地 tty 直接给 root shell，不需要密码**。
4. **默认开启**：dropbear（22，仅 LAN，密码登录）、uhttpd（80/443，LuCI）、dnsmasq、odhcpd、NTP 服务端、SNMP（public/private community）、TurboACC（flow offload + FullCone NAT 高性能模式）。**默认关闭**：OpenClash、旧版 AdGuardHome、MIA、DDNS 示例。
5. **AdGuardHome 处于“双包 + 半配置”状态**：官方 `adguardhome` 包已安装且 `S19adguardhome` 启动项存在（其 init 没有 `enabled` 开关）；但镜像里没有 `/etc/adguardhome/adguardhome.yaml`，首次启动会进入 3000 端口初始化向导；同时旧版 `luci-app-adguardhome` 也装着，但它的 `binpath=/usr/bin/AdGuardHome/AdGuardHome` 与实际二进制 `/usr/bin/AdGuardHome` 不匹配，旧 LuCI 页面管不到官方服务。若在向导里把 DNS 设为 53，会和 dnsmasq 冲突。
6. **OpenClash 装了但不可直接用**：`enable=0`，`/etc/openclash/core/` 为空，缺 clash/meta 内核；首次启动只会生成随机 dashboard 密码和认证账号。启用前必须自行放入内核。
7. **软件源已经被“改坏”**：首次启动会把 `downloads.openwrt.org` 改成 `mirrors.tencent.com/lede`，删除 `check_signature`，并删掉 `helloworld` 子源；脚本里还保留了一条把 `snapshots` 替换成 `releases/18.06.9` 的旧规则，但当前 distfeeds 是 24.10.5 固定发布路径、不含 `snapshots`，所以这条规则实际不生效。原镜像里的 `helloworld`、`passwall`、`immortalwrtluci` 等子源在官方 24.10.5 路径下并不存在。**不建议在这个固件上直接 `opkg update && opkg upgrade`**。
8. **镜像尾部 GPT 备份表缺失**：`fdisk` 报 PMBR size mismatch、backup GPT corrupt；主 GPT 可用，能启动，但写入磁盘后建议用 `sgdisk -e` 修复，再按需扩容 p2。

---

## 1. 镜像与分区

### 1.1 分区表

| 分区 | 起始扇区 | 结束扇区 | 大小 | 类型 | 内容 |
|---|---:|---:|---:|---|---|
| p1 | 512 | 131583 | 64 MiB | Linux filesystem | FAT16，卷标 `kernel`，含 GRUB、`/boot/vmlinuz`、`/efi/boot/bootx64.efi` |
| p2 | 131584 | 1049087 | 448 MiB | Linux filesystem | SquashFS 根文件系统（仅前 82.66 MiB 有数据） |
| p128 | 34 | 511 | 239 KiB | BIOS boot | GRUB BIOS 引导 core |

- 磁盘标识：`A09FA0EE-8410-22EF-BC2D-11E18A98EF00`
- p2 PARTUUID：`a09fa0ee-8410-22ef-bc2d-11e18a98ef02`，与 GRUB 的 `root=PARTUUID=...` 对应。
- 混合引导：既有 `p128` 的 BIOS boot，也有 p1 里的 `EFI/BOOT/BOOTX64.EFI`（634,880 字节）。
- p1 为 FAT16，卷标 `kernel`，卷序列号 `1234-ABCD`；`/boot/vmlinuz` 6,407,168 字节；p1 剩余约 59.7 MiB。

### 1.2 SquashFS

```
SQUASHFS 4:0, xz, dictionary 256 KiB, x86 filter, block 256 KiB
Filesystem size: 86,679,707 bytes (82.66 MiB)
Inodes: 4351, fragments: 328, ids: 1
Creation time: 2026-06-18 02:00:17（镜像内时间）
```

解包后根文件系统约 **292 MiB**，共 **340 个已安装包**。

### 1.3 剩余空间与 overlay

- p2 总大小 448 MiB，SquashFS 只占 82.66 MiB，其后直到镜像末尾基本全是 0。
- 首次启动时，`fstools` 的 rootdisk 逻辑会在 p2 的剩余空间创建 `rootfs_data` overlay（ext4；libfstools 也支持 f2fs），可用空间约 **365 MiB**。
- 如果写入大于 512 MiB 的硬盘，p2 不会自动变大；建议**首次启动前**先扩容 p2，让 overlay 一次用满，避免启动后再折腾 loop/ext4 扩容。

### 1.4 gzip 尾部的 532 字节

`gunzip`/`gzip -t` 会提示 `trailing garbage ignored`，这不是文件损坏。末尾 532 字节是 **usign 签名 + ucert 证书**：

- 签名注释：`untrusted comment: signed by key 682ee5748b3abf0b`
- 证书注释：`untrusted comment: Local build key`
- 公钥与镜像内 `/etc/opkg/keys/682ee5748b3abf0b` 对应
- ucert 有效期：`2026-06-20` 至 `2027-06-20`（UTC）

因此 `gzip` 的警告可以忽略；真正校验应使用 `usign`/`ucert`。

### 1.5 GPT 备份表问题

`fdisk -l` 输出：

```
GPT PMBR size mismatch (1049119 != 1049150) will be corrected by write.
The backup GPT table is corrupt, but the primary appears OK, so that will be used.
The backup GPT table is not on the end of the device.
```

主 GPT 的 `alternate_lba = 1049120`，但实际文件有 1,049,151 个扇区（最后扇区 1,049,150）；LBA 1,049,120 处是 0，备份 GPT 实际不存在。主 GPT 和分区项有效，GRUB/内核仍可启动。写入磁盘后建议：

```bash
sudo sgdisk -e /dev/sdX     # 把备份 GPT 移到磁盘末尾
sudo sgdisk -v /dev/sdX     # 校验
```

---

## 2. 版本与构建来源

| 项目 | 值 |
|---|---|
| 发行标识 | OpenWrt 24.10.5 / r7833-27ba2c2dd / x86/64 |
| 构建后改写 | `DISTRIB_REVISION='R26.05.20'`、`DISTRIB_DESCRIPTION='LEDE '`、`OPENWRT_RELEASE="LEDE R26.05.20"` |
| 内核 | 6.12.93（`6.12.93 #0 SMP Wed Jun 17 18:00:17 2026`，构建机 `runner@runnervm08nci`） |
| C 库 | musl 1.2.5-4 |
| LuCI | `git-26.159.06565-3af75fc-1`（Lua 兼容层 `luci-compat`、`luci-lua-runtime`） |
| 防火墙 | firewall3 `2022-02-17-4cd7d4f3-3` + iptables 1.8.7（**无 fw4/nftables**） |
| 包管理 | opkg `2024-10-16-38eccbb1-1` |
| 内核包 | `6.12.93-1-bf2adb4870f24ab26d157cf0f6c3f61f` |
| 镜像签名 | usign key `682ee5748b3abf0b`（Local build key） |

### 2.1 为什么判断是 Lean LEDE

- `default-settings` 的 `Source:` 是 `package/lean/default-settings`；
- `luci-app-openclash` 的 `Source:` 是 `package/lean/luci-app-openclash`；
- `luci-app-turboacc` 的 `Maintainer:` 是 `Lean <coolsnowwolf@gmail.com>`；
- 使用 firewall3/iptables + `default-settings` 的 `99-default-settings` 典型脚本；
- `99-default-settings` 里仍保留“把 `snapshots` 源切到 18.06.9”的旧规则（当前路径不含 `snapshots`，不生效）以及“删除 mwan/upnp/ddns 状态页”等 Lean 旧构建遗留。

### 2.2 版本串为什么不可全信

- `base-files` 版本是 `125-r7833-27ba2c2dd`，`r7833` 是 18.06.9 时代的修订号；
- 但内核是 6.12.93、LuCI 是 26.159、包时间在 2026 年；
- `/etc/banner` 仍写 `OpenWrt 24.10.5, r7833-27ba2c2dd`，首次启动后 `/etc/openwrt_release` 又变成 `LEDE R26.05.20`；
- `/usr/lib/os-release` 的 `OPENWRT_BUILD_DATE="%B"` 是未展开的占位符。

结论：这是 **2026-06-17/18 由 CI 构建的 Lean LEDE 定制固件**，版本串是拼接/改写的，不能按官方 24.10.5 的包依赖和升级路径来对待。

---

## 3. 启动流程

### 3.1 GRUB

`/boot/grub/grub.cfg`：

```
serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1 --rtscts=off
terminal_input console serial; terminal_output console serial

set default="0"
set timeout="0"
search -l kernel -s root

menuentry "LEDE" {
    linux /boot/vmlinuz root=PARTUUID=a09fa0ee-8410-22ef-bc2d-11e18a98ef02 rootwait \
      console=tty0 console=ttyS0,115200n8 noinitrd swiotlb=65536
}
menuentry "LEDE (failsafe)" {
    linux /boot/vmlinuz failsafe=true root=PARTUUID=a09fa0ee-8410-22ef-bc2d-11e18a98ef02 rootwait \
      console=tty0 console=ttyS0,115200n8 noinitrd
}
```

- `timeout=0`：默认不显示菜单、直接启动 `LEDE`；`failsafe` 菜单项存在但正常开机时基本选不到，需要在串口下抢先按键/改 GRUB。
- 串口参数 115200 8N1，`console=tty0 console=ttyS0,115200n8`。
- `swiotlb=65536`（64 MiB）只在正常条目里，failsafe 条目没有。
- `rootwait` + `noinitrd`，根分区用 PARTUUID 定位。

### 3.2 控制台

`/etc/inittab`：

```
::sysinit:/etc/init.d/rcS S boot
::shutdown:/etc/init.d/rcS K shutdown
ttyS0::askfirst:/usr/libexec/login.sh
hvc0::askfirst:/usr/libexec/login.sh
tty1::askfirst:/usr/libexec/login.sh
```

`/usr/libexec/login.sh`：

```sh
[ "$(uci -q get system.@system[0].ttylogin)" = 1 ] || exec /bin/ash --login
exec /bin/login
```

而 `config_generate` 默认写入 `system.@system[0].ttylogin='0'`，`99-default-settings` 也不会改它。因此：

> **串口 ttyS0 / 本地 tty1 按回车后直接进入 root shell，不需要密码。**  
> root 密码只保护 SSH 和 LuCI。机柜/弱电箱物理安全需要考虑这一点。

### 3.3 首次启动的 uci-defaults

关键脚本 `/etc/uci-defaults/99-default-settings` 会做：

- 时区改为 `CST-8` / `Asia/Shanghai`；
- NTP 改为 `ntp1.aliyun.com`、`ntp.tencent.com`、`ntp.ntsc.ac.cn`、`time.apple.com`；
- 删除 mwan/upnp/ddns/minidlna 的 LuCI 状态页（部分应用并未安装，属于遗留清理）；
- 把 opkg 源域名改成 `mirrors.tencent.com/lede`；
- 删除 `/etc/opkg.conf` 的 `check_signature`；
- 尝试把含 `snapshots` 的 LuCI 源改成 `releases/18.06.9`；当前 distfeeds 是 24.10.5 固定发布路径，不含 `snapshots`，因此这条 sed 实际不生效；
- 写入 root 密码 MD5；
- 改写 `/etc/openwrt_release`、`/usr/lib/os-release` 为 `LEDE R26.05.20`；
- 给 dnsmasq 追加 `log-facility=/dev/null`（关闭 DNS 查询日志）；
- 删除 LuCI 缓存。

此外：

- `50-root-passwd` 读取 `/etc/board.json` 的 `credentials`；镜像内没有 board.json，首次启动 `board_detect` 生成的 board.json 也不含 `credentials`，因此跳过。
- `10-fstab` 首次启动用 `block detect` 生成 `/etc/config/fstab`。
- `12_network-generate-ula` 生成随机 ULA /48。
- `00_uhttpd_ubus` 设置 `uhttpd.main.ubus_prefix=/ubus`。
- `luci-openclash` 生成 OpenClash 随机 dashboard 密码、认证账号，并设置 firewall include。
- `xxx-coremark` 添加 `0 4 * * * /etc/coremark.sh`；`coremark.sh` 跑完会删除该 cron 行（一次性 CPU 跑分，不是永久任务）。

---

## 4. 网络配置（首次启动后的默认值）

### 4.1 接口

| 接口 | 设备 | 协议 | 默认地址/行为 | 备注 |
|---|---|---|---|---|
| loopback | lo | static | 127.0.0.1/8 | 标准 |
| lan | eth0（通用 x86） | static | **192.168.1.253/24** | `ip6assign 60`；DHCP 池 `.100–.249` |
| wan | eth1（存在时） | dhcp | 从上游获取 IPv4 | 无 PPPoE 默认配置 |
| wan6 | eth1 | dhcpv6 | 从上游获取 IPv6 | 依赖上游 RA/DHCPv6 |
| globals | — | — | `ula_prefix=auto` | 首次启动生成随机 /48 |

> 通用 x86 的 LAN 默认 IP 是 **192.168.1.253**，不是常见的 .1；failsafe 模式仍是 **192.168.1.1**（`/lib/preinit/00_preinit.conf` 的 `pi_ip`）。这两个地址不一致，排障时容易混淆。

### 4.2 已知机型的 LAN/WAN 映射

`/etc/board.d/02_network` 按 `board_name` 覆盖默认映射：

| board_name | LAN | WAN |
|---|---|---|
| brounion-r86s | eth1 eth2 | eth0 |
| cwwk-cw-mbx-ad12 | eth1–eth5 | eth0 |
| erying-i7-13850hx-wm790-nas-vpro-10g-lan-d5-mb | eth1 eth2 | eth0 |
| ikoolcore-r1 / r2-max / pear-inc-pearbox-1 | eth1–eth3 | eth0 |
| pc-engines-apu1/2/3 | eth1 eth2 | eth0 |
| roqos-roqos-core-rc10 | eth1 | eth0 |
| sophos-sg-105 / xg-105 | eth0 eth2 eth3 | eth1 |
| traverse-technologies-geos | eth0 eth1 | nas0（ATM） |
| xiaoma-m12 | eth1–eth6 | eth0 |
| 其他/通用 | eth0 | eth1（存在时） |

- 多 LAN 口机型会生成 `br-lan` 网桥；通用单口场景通常直接 `lan.ifname=eth0`。
- 若机型的 DMI 名称不在上表，默认就是 **eth0=LAN、eth1=WAN**；四口以上机器的 eth2/eth3 默认不参与网络，需要手动加。

### 4.3 DHCP / DNS

`/etc/config/dhcp` 关键项：

| 选项 | 值 | 含义 |
|---|---|---|
| `domain` / `local` | `lan` / `/lan/` | 本地域名 |
| `cachesize` | `8192` | dnsmasq 缓存条数 |
| `ednspacket_max` | `1232` | EDNS0 包大小，适配 PPPoE/VPN |
| `filter_aaaa` / `filter_a` | `0` / `0` | 不过滤 A/AAAA |
| `localservice` | `1` | 只服务本地子网 |
| `rebind_protection` | `1` | 防 DNS rebinding |
| `rebind_localhost` | `1` | 允许 localhost 反解 |
| `authoritative` | `1` | 本地权威 |
| `readethers` | `1` | 读取 `/etc/ethers` |
| `leasefile` | `/tmp/dhcp.leases` | 租约文件 |
| `resolvfile` | `/tmp/resolv.conf.d/resolv.conf.auto` | 上游 DNS |
| `dhcp lan` | `start 100, limit 150, leasetime 12h` | 池 `.100–.249`，12 小时 |
| `dhcp wan` | `ignore 1` | WAN 不提供 DHCP |

- DHCPv4 由 dnsmasq 提供；DHCPv6/RA 由 `odhcpd-ipv6only` 提供。
- 没有自定义上游 DNS；默认跟随 WAN 的 DNS。
- 首次启动后 `/etc/dnsmasq.conf` 追加 `log-facility=/dev/null`，DNS 查询日志被关闭。
- 若启用 AdGuardHome 并把 DNS 指到 53，需要同时处理 dnsmasq 的 53 占用。

### 4.4 IPv6

- LAN `ip6assign 60`，从 WAN 获取 PD；无 PD 时使用随机 ULA /48。
- `wan6` 为 DHCPv6；`odhcp6c` 已安装。
- `odhcpd-ipv6only` 提供 RA/DHCPv6。
- 防火墙放行 DHCPv6、MLD、ICMPv6；IPv6 转发开启。
- 没有 `disable_ipv6`；IPv6 默认是启用的。

### 4.5 无线

- 无 `/etc/config/wireless`。
- 包列表中没有 `kmod-cfg80211`/`kmod-mac80211` 等无线驱动。
- 该固件按**纯有线 x86 软路由**设计；USB 无线网卡也不在支持范围内。

---

## 5. 防火墙、NAT 与加速

`/etc/config/firewall` 基本是 OpenWrt 默认 fw3 配置：

| 区域 | input | output | forward | 其他 |
|---|---|---|---|---|
| defaults | ACCEPT | ACCEPT | REJECT | `synflood_protect=1`、`fullcone=0` |
| lan | ACCEPT | ACCEPT | ACCEPT | — |
| wan | REJECT | ACCEPT | REJECT | `masq=1`、`mtu_fix=1` |

- 仅一条 `lan → wan` forwarding。
- 标准放行：DHCP Renew、IPv4 Ping、IGMP、DHCPv6、MLD、ICMPv6、IPSec ESP/ISAKMP；UDP traceroute 规则默认关闭。
- 没有端口转发、没有 DMZ、没有自定义 `firewall.user` 规则。
- `firewall.user` 为空；`mia.include` 只是 `restart mia`，而 mia 默认关闭，等于 no-op。

### 5.1 TurboACC 运行时会改防火墙

`/etc/config/turboacc`：

| 选项 | 值 | 实际效果 |
|---|---|---|
| `sw_flow` | 1 | `firewall.@defaults[0].flow_offloading=1`（软件 flow offload） |
| `hw_flow` | 1 | `flow_offloading_hw=1`；x86 一般无硬件 offload，等于无效/被忽略 |
| `sfe_flow` | 1 | 因 `sw_flow=1`，不会加载 Shortcut-FE |
| `fullcone_nat` | **2** | `firewall.@defaults[0].fullcone=2`，即 LuCI 里的 **High Performing Mode** |
| `hw_wed` | 0 | 不启用 WED |
| `bbr_cca` | 0 | 启动时执行 `sysctl -w net.ipv4.tcp_congestion_control=cubic` |
| `dns_caching` | 0 | 不启动 pdnsd/dnsforwarder/dnsproxy |

注意两点：

1. `/etc/config/firewall` 里写的是 `fullcone=0`，但 `S90turboacc` 启动时会改成 **2**；所以**运行时实际是 FullCone NAT 高性能模式**。
2. `/etc/sysctl.d/12-tcp-bbr.conf` 写了 `net.ipv4.tcp_congestion_control=bbr`，但 `S90turboacc` 随后又设回 `cubic`；**最终生效的是 cubic，不是 BBR**。想用 BBR 应把 `turboacc.config.bbr_cca` 设为 1，或去掉冲突项。

FullCone NAT 会放宽 NAT 过滤，对游戏/联机有好处，但会降低“未主动发起连接的外部主机无法直连内网”的保护；不需要时应设回 0。

Flow offload 会让首包之后的转发绕过部分 iptables 规则；如果后续要加 QoS、流量统计或复杂防火墙规则，建议先关掉 `sw_flow`。

---

## 6. 服务、端口与默认状态

| 服务 | rc.d | 默认 | 监听/端口 | 说明 |
|---|---|---|---|---|
| dropbear | S19 | 开 | 22/tcp，仅 LAN | `PasswordAuth=on`、`RootPasswordAuth=on`；无 authorized_keys |
| uhttpd | S50 | 开 | 80/tcp、443/tcp，所有接口 | LuCI；`redirect_https=0`；自签证书首次启动生成 |
| dnsmasq | S19 | 开 | 53/tcp+udp，所有接口 | DHCPv4 + DNS；WAN 侧被防火墙拒绝 |
| odhcpd | S35 | 开 | 547/udp、546/udp，LAN | DHCPv6/RA |
| firewall | S19 | 开 | — | fw3/iptables |
| network | S20 | 开 | — | netifd |
| snmpd | S99 | 开 | 161/udp（v4+v6） | `public` 只读、`private` 仅 localhost 读写；LAN 可访问 |
| NTP（busybox ntpd） | S98 | 开 | 123/udp | `enable_server=1`，LAN 可作 NTP 服务器 |
| TurboACC | S90 | 开 | — | 启动时改 firewall 选项并重启 dnsmasq/firewall |
| cron | S50 | 开 | — | 初始无 crontab，首次启动后 coremark 任务短暂存在 |
| ddns | S95 | 开（但无任务） | — | 示例服务 `enabled` 默认 0，不会更新 |
| AdGuardHome（官方） | S19 | 开 | 3000/tcp（首次向导） | 无 `/etc/adguardhome/adguardhome.yaml`；init 无 `enabled` 开关 |
| AdGuardHome（旧版） | S95 | 关 | — | `AdGuardHome.AdGuardHome.enabled=0`；binpath 不匹配 |
| OpenClash | S99 | 关 | 启用后 7890–7895、7874、9090 | `enable=0`；core 为空 |
| MIA | S30 | 关 | — | `mia.basic.enable=0` |
| packet_steering | S25 | 开（无效） | — | 需要 `network.@globals[0].packet_steering=1`，未设置，脚本直接退出 |
| lm-sensors | S28 | 开 | — | 传感器工具 |
| autocore | S99 | 开 | — | CPU 信息/跑分展示 |
| gpio_switch / led | S94/S96 | 开 | — | x86 一般无实际 GPIO/LED |

### 6.1 端口暴露面（默认防火墙下）

- **LAN 侧**：22、80、443、53、67/68、123、161、3000（AdGuardHome 向导）、546/547。
- **WAN 侧**：默认 input REJECT，只放行 DHCP Renew、IPv4 Ping、IGMP、DHCPv6、MLD、ICMPv6、IPSec ESP/ISAKMP；没有端口转发。
- 如果后续加端口转发/放行 161 或 3000，要注意 SNMP public community 和 AdGuardHome 初始化向导都是无认证/弱认证入口。

---

## 7. 账号、密钥与证书

### 7.1 root 密码

- 当前 `/etc/shadow`：`root:::0:99999:7:::`（空密码）。
- 首次启动 `99-default-settings` 会替换为：
  ```
  root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.:0:0:99999:7:::
  ```
- 已验证该 MD5-crypt 对应明文 **`password`**。
- 这是典型的第三方固件默认密码；**首次登录后必须改**，并且建议不要继续使用 MD5-crypt。

### 7.2 SSH

- `/etc/config/dropbear`：`Port=22`、`Interface=lan`、`PasswordAuth=on`、`RootPasswordAuth=on`。
- 没有 `/root/.ssh/authorized_keys`。
- `/etc/dropbear/dropbear_{rsa,ed25519}_host_key` 是 0 字节占位，首次启动由 dropbear 生成。
- 结论：LAN 内可用 `root/password` SSH；WAN 侧被防火墙挡住；没有强制公钥。

### 7.3 LuCI / uhttpd

- `/etc/config/rpcd`：`login.username=root`、`login.password=$p$root`（用系统密码）。
- `/etc/config/uhttpd`：HTTP 80、HTTPS 443、`redirect_https=0`；`rfc1918_filter=1`；`max_requests=3`；`max_connections=100`；会话 3600 秒。
- `/etc/uhttpd.crt`、`/etc/uhttpd.key` 镜像内不存在，首次启动用 OpenSSL 生成（EC P-256、730 天、CN=OpenWrt、C=ZZ）。`px5g` 未安装，但 `openssl-util` 在，`/etc/init.d/uhttpd` 会走 OpenSSL 分支。
- 由于 `redirect_https=0`，LuCI 默认可以用明文 HTTP 登录；LAN 内抓包可见密码。建议改为强制 HTTPS，或至少限制管理网段。

### 7.4 SNMP

- `snmpd` 默认 `enabled=1`。
- `com2sec public default public`：任意来源只读，community=`public`。
- `com2sec private localhost private`：仅 localhost 读写，community=`private`。
- `sysName=HeartOfGold`、`sysLocation=office`、`sysContact=bofh@example.com` 是软件包默认值，不是用户配置。
- 默认防火墙挡住 WAN，但 LAN 内任何人都能读 SNMP；如果不需要监控，建议关闭。

### 7.5 其他密钥/证书

- 镜像内没有 Wi-Fi PSK、VPN 私钥、代理订阅、DDNS 真实账号；DDNS 只有 `your_username/your_password` 占位。
- OpenClash 的 dashboard 密码/认证账号是首次启动随机生成，不在镜像里。
- `/etc/opkg/keys/` 有两个构建公钥：`682ee5748b3abf0b`（与镜像签名对应）和 `b5043e70f9a75cde`。
- `uhttpd` 证书、dropbear host key 都是首次启动生成，`sysupgrade` 会保留（keep.d）。

---

## 8. 已安装软件与功能

完整列表见 [`packages.txt`](packages.txt)，共 340 个包。关键组件：

| 类别 | 包/版本 | 说明 |
|---|---|---|
| 基础 | base-files 125-r7833、busybox 1.36.1、musl 1.2.5、procd 2023-06-25、netifd 2021-06-04 | 版本混搭明显 |
| 防火墙 | firewall 2022-02-17、iptables/ip6tables 1.8.7、ipset 7.21 | fw3，不是 fw4 |
| DNS/DHCP | dnsmasq-full 2.91、odhcpd-ipv6only 2026-06-14、odhcp6c | 标准 |
| 代理 | luci-app-openclash 0.47.099、ruby 3.3.6、kmod-tun、iptables-mod-tproxy | **core 为空** |
| 去广告 DNS | adguardhome 0.107.74、luci-app-adguardhome 1.8-11 | **双包/路径冲突** |
| 加速 | luci-app-turboacc git-26.159、pdnsd-alt、kmod-tcp-bbr、kmod-ipt-offload、fullconenat | flow offload + FullCone 2 |
| 监控 | snmpd 5.9.1、lm-sensors 3.6.0、htop、coremark、autocore-x86 | SNMP 默认开 |
| 存储/工具 | e2fsprogs、mkf2fs、cfdisk、partx-utils、block-mount、pciutils、ethtool、curl、wget-ssl、unzip、bash | 维护用 |
| 网卡驱动 | e1000/e1000e/igb/igc/ixgbe/atlantic/bnx2/bnx2x/mlx4/mlx5/vmxnet3/r8125-rss/r8126-rss/r8168 等 | 迷你主机/服务器网卡覆盖较全 |
| 显卡/固件 | i915-firmware、amdgpu-firmware、intel-microcode、amd64-microcode | HDMI 控制台/CPU 微码 |
| 启动 | grub2 2.12、grub2-efi、grub2-bios-setup | 双启动 |
| 语言 | luci-i18n-base-zh-cn、luci-i18n-*-zh-cn | 中文界面可用 |

### 8.1 本镜像（2026-06-18，94 MB）里**没有**的东西

- **没有** `ssserver-luci`、`shadowsocks-libev`、`shadowsocks-rust`、`xray`、`v2ray`、`passwall`/`ssr-plus`；
  - 注意：**2026-10-11 的 116 MB 新构建有** `shadowsocks-rust-ssserver`、`passwall_server`、`sing-box`，见 [`README-2026-10-11.md`](README-2026-10-11.md)。
- **没有** `luci-app-ddns-go`；只有 `ddns-scripts`，连 `luci-app-ddns` 也没有，DDNS 只能 CLI；
- **没有** Docker、Samba、Transmission、MiniDLNA、UPnP；
- **没有** 无线驱动/无线配置；
- **没有** WireGuard/OpenVPN 服务端。

因此，如果你的目标是“在这个固件上跑 SS 服务 + LuCI 管理”，当前镜像只提供了基础 OpenWrt 用户态和 OpenClash 客户端，**需要自行安装 `ssserver-luci` 和对应的 shadowsocks 服务端包**；并且要先解决 opkg 源/签名问题，不能直接依赖 `opkg update`。

### 8.2 OpenClash 细节

- `/etc/openclash/core/` 为空，`/etc/openclash/clash` 不存在。
- 已带 `GeoSite.dat`（10.5 MB）、`Country.mmdb`（205 KB）、`china_ip_route.ipset`、`china_ip6_route.ipset`。
- 默认 `enable=0`；首次启动 `luci-openclash` 会：
  - 设置 `core_version=linux-amd64-v1`；
  - 生成随机 `dashboard_password`；
  - 创建 `authentication` 用户 `Clash` + 随机密码；
  - 设置 `disable_quic_go_gso=1`（内核 > 6.6）；
  - 添加 firewall include `/var/etc/openclash.include`。
- 启用前需要自己放入 meta/clash 内核，否则服务起不来。

### 8.3 AdGuardHome 细节

- 官方 `adguardhome`：
  - 二进制 `/usr/bin/AdGuardHome`（34.5 MB）；
  - 配置 `/etc/adguardhome/adguardhome.yaml` **不存在**；
  - init `PROG=/usr/bin/AdGuardHome`，无 `enabled` 开关，`S19adguardhome` 已启用；
  - 首次启动会创建 `/etc/adguardhome`、`/var/lib/adguardhome`，以 `adguardhome` 用户运行，进入 3000 端口初始化向导。
- 旧版 `luci-app-adguardhome`：
  - `/etc/config/AdGuardHome` 里 `enabled=0`；
  - `binpath=/usr/bin/AdGuardHome/AdGuardHome`，但实际是 `/usr/bin/AdGuardHome` 文件，路径不匹配；
  - 旧 init `/etc/init.d/AdGuardHome` 默认不启动。
- 结果：**两个 AdGuardHome 实现并存，但都不是“配好可用”的状态**；官方服务会在 3000 端口开向导，旧 LuCI 页面管不到它。若在向导里把 DNS 设为 53，会与 dnsmasq 冲突（dnsmasq 先启动并占用 53）。

---

## 9. 软件源与升级风险

### 9.1 当前 distfeeds

```
src/gz openwrt_core https://downloads.openwrt.org/releases/24.10.5/targets/x86/64/packages
src/gz openwrt_base https://downloads.openwrt.org/releases/24.10.5/packages/x86_64/base
src/gz openwrt_helloworld .../packages/x86_64/helloworld
src/gz openwrt_immortalwrtluci .../packages/x86_64/immortalwrtluci
src/gz openwrt_immortalwrtpackages .../packages/x86_64/immortalwrtpackages
src/gz openwrt_luci .../packages/x86_64/luci
src/gz openwrt_packages .../packages/x86_64/packages
src/gz openwrt_passwall .../packages/x86_64/passwall
src/gz openwrt_passwall_packages .../packages/x86_64/passwall_packages
src/gz openwrt_routing .../packages/x86_64/routing
src/gz openwrt_telephony .../packages/x86_64/telephony
```

问题：

1. `helloworld`、`immortalwrtluci`、`immortalwrtpackages`、`passwall`、`passwall_packages` 不是官方 24.10.5 的标准子源，`opkg update` 会 404。
2. 首次启动把域名改成 `mirrors.tencent.com/lede`，但路径仍是 `releases/24.10.5/...`，该镜像未必有这个目录。
3. 首次启动脚本里有一条把 `snapshots` 替换为 `releases/18.06.9` 的旧规则；当前 distfeeds 是 24.10.5 固定路径、不含 `snapshots`，所以实际不生效，但说明脚本是跨版本遗留，不能按表面配置推断。
4. 删除 `check_signature` 后，opkg 不再校验包签名。

**建议**：除非你明确知道要装什么，否则不要在这个固件上做 `opkg update && opkg upgrade`；升级 LuCI/base-files 极可能把系统弄坏。需要装包时，优先使用与 `kernel 6.12.93`、musl 1.2.5 匹配的 Lean LEDE 同源包，或自己重新构建。

### 9.2 sysupgrade 保留项

`/etc/sysupgrade.conf` 为空（只有注释），但各包的 `keep.d` 会保留：

- `/etc/config/`、`/etc/config/network`、`/etc/config/system`、`/etc/dropbear/`、`/etc/profile.d`
- `/etc/adguardhome/adguardhome.yaml`
- `/etc/openclash/`
- `/etc/uhttpd.crt`、`/etc/uhttpd.key`
- `/etc/crontabs/`、`/etc/opkg/keys/`、`/etc/ppp/ip*` 等

---

## 10. 风险与建议

### 10.1 高优先级

| 风险 | 说明 | 建议 |
|---|---|---|
| 弱默认密码 | 首次启动后 root/password；MD5-crypt | 首次登录立即 `passwd`，使用强密码；不要暴露 SSH 到 WAN |
| 串口免密 root | `ttylogin=0`，ttyS0/tty1 直接 root shell | 有物理安全需求时 `uci set system.@system[0].ttylogin='1'` 并 `uci commit system` |
| opkg 签名关闭 + 源错配 | 首次启动删除 `check_signature`，域名改为 Tencent 镜像；脚本还含 18.06.9 旧改源规则（当前不生效） | 不要直接 upgrade；需要装包时手动修正 feed 并恢复签名校验 |
| AdGuardHome 双包/向导暴露 | 官方服务在 LAN 3000 开无认证向导；旧 LuCI 路径不匹配 | 不用就 `disable` 官方服务并移除旧 `luci-app-adguardhome`；要用就统一用官方包并手工配置 |
| GPT 备份缺失 | 写盘后 `fdisk` 会警告 | 写盘后 `sgdisk -e` 修复；大于 512MB 的盘先扩容 p2 |

### 10.2 中优先级

| 风险 | 说明 | 建议 |
|---|---|---|
| FullCone NAT 高性能模式 | `fullcone=2` 放宽 NAT 过滤 | 不需要 gaming/联机时 `uci set turboacc.config.fullcone_nat='0'`，或 `uci set firewall.@defaults[0].fullcone='0'` 并停用 TurboACC 的覆盖 |
| HTTP 管理 | `redirect_https=0`，LuCI 可明文登录 | `uci set uhttpd.main.redirect_https='1'`，重启 uhttpd；或仅限管理 VLAN |
| SNMP public | 默认开，community=public 只读 | 不用就 `uci set snmpd.general.enabled='0'`，`/etc/init.d/snmpd disable`；要用就改 community/限制来源 |
| BBR 配置冲突 | sysctl.d 设 bbr，TurboACC 又设 cubic | 想用 BBR 就 `turboacc.config.bbr_cca=1`，或删掉冲突项 |
| 版本/源混搭 | 24.10.5 标识 + 6.12.93 + 旧 18.06.9 改源规则 | 生产环境建议用官方 24.10.5 或与内核/用户态匹配的 Lean 构建 |
| 旧 Argon 主题 | 1.8.4 与 LuCI 26.159 可能有 UI 兼容问题 | 如遇白屏/样式错乱，`uci set luci.main.mediaurlbase='/luci-static/bootstrap'` 回退 |

### 10.3 低优先级

| 项 | 说明 |
|---|---|
| coremark cron | 首次启动添加 `0 4 * * *`，跑完自动删除；只影响一次凌晨负载 |
| packet_steering | 未设置 UCI 开关，服务实际空转 |
| DDNS | 脚本和阿里云 / DNSPod provider 在，但没有 LuCI，也没有启用的服务 |
| OpenClash 无 core | 启用前必须补 `/etc/openclash/core/`，否则起不来 |
| 无 Wi-Fi | 纯有线设计；USB 无线网卡也不支持 |
| NTP 服务端 | `enable_server=1`，LAN 123/udp 可被查询；不需要可关 |
| `luci-app-accesscontrol`/`filetransfer` | 装了但未配置；filetransfer 提供 LuCI 上传入口，注意权限 |

### 10.4 如果目标是“SS 服务 + LuCI”

当前镜像**不含** `ssserver-luci`/`shadowsocks-libev`。可行路径：

1. 先修 opkg：把 `distfeeds.conf` 改回与 Lean LEDE 同源、与 6.12.93 匹配的 feed，恢复 `check_signature`；
2. 安装 `shadowsocks-libev`（或 `shadowsocks-rust`）+ `ssserver-luci` 及其依赖；
3. 在防火墙放行 SS 端口（默认 WAN input REJECT，需要新建 traffic rule）；
4. 如果同时用 OpenClash，注意 7890–7895/7874/9090 与 SS 端口、DNS 53 的冲突；
5. 不要在未验证的情况下直接 `opkg upgrade` 基础包。

---

## 11. 关键文件索引

本目录保留了分析时抽取的关键配置，便于对照：

- [`grub.cfg`](grub.cfg) — GRUB 菜单/内核 cmdline
- [`configs/`](configs/) — `dhcp`、`firewall`、`dropbear`、`uhttpd`、`luci`、`rpcd`、`snmpd`、`ddns`、`openclash`、`adguardhome`、`AdGuardHome`、`turboacc`、`mia`、`ucitrack`、`openssl`
- [`uci-defaults/`](uci-defaults/) — `99-default-settings`、`luci-openclash`、`adguardhome`、`xxx-coremark`、`50-root-passwd`
- [`board.d/`](board.d/) — `02_network`、`99-default_network`
- [`packages.txt`](packages.txt) — 340 个已安装包清单
- [`image-info.txt`](image-info.txt) — 分区表、SquashFS 信息、SHA256

### 11.1 快速核对命令

```sh
# 解压并查看分区
gunzip -c openwrt-x86-64-generic-squashfs-combined-efi.img.gz > fw.img
fdisk -l fw.img

# 查看 SquashFS
unsquashfs -offset $((131584*512)) -s fw.img   # 注意 offset 要放在 -s 前面
dd if=fw.img of=p2.sqfs bs=512 skip=131584 count=917504
unsquashfs -s p2.sqfs
unsquashfs -d rootfs p2.sqfs

# 验证默认密码
openssl passwd -1 -salt V4UetPzk password
# 输出应为 $1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.
```

---

## 12. 一句话总结

**（本文分析的是 94 MB / 2026-06-18 构建）这是一个 2026 年 CI 构建的 Lean LEDE x86-64 定制固件：默认 LAN 192.168.1.253、WAN DHCP，root/password，串口免密，firewall3 + TurboACC FullCone 2，装了 OpenClash 和 AdGuardHome 但都没有配好；软件源/版本串混搭，不适合直接 opkg 升级，生产使用前应改密码、关串口免密、修正 AGH 双包、修复 GPT 并按需扩容。**
