# 最新 Lean 源码 + 内核 + TurboACC 构建说明

## 源码与内核选择

- 源码：`coolsnowwolf/lede@ff6b739d41cdc3767b266d777dfe8a87c89bff00`（2026-11-08 master）
- Lean 默认内核：`KERNEL_PATCHVER=6.18`
- 内核.org 当前 LTS（2026-11-06）：
  - `6.18.62`（LTS）
  - `6.12.116`（LTS）
  - `6.6.162`（LTS）

选择 **6.18 LTS**：

1. 是 Lean master 的默认内核，target 适配最完整；
2. 是当前仍在维护的 LTS，安全更新持续；
3. 对较新的 x86 迷你主机/网卡支持更好；
4. 6.12 LTS 仍可作为老硬件/保守方案，但已进入生命周期后段。

本次构建不强制改 kernel 版本，使用源码 `target/linux/x86/Makefile` 的默认 `6.18`。

## TurboACC

`openwrt-25.12` 的 LuCI feed 已不再提供 `luci-app-turboacc`；这里从
`coolsnowwolf/luci@master` 的 `applications/luci-app-turboacc` 取源码，
vendored 到 `local-packages/luci-app-turboacc`，构建时复制进 `package/`。

为适配 firewall4/nftables 做了最小修改：

- Makefile：
  - `PKG_RELEASE` 固定为 `1`（避免 `COMMITCOUNT` 未定义）
  - `include ../../luci.mk` → `include $(TOPDIR)/feeds/luci/luci.mk`
  - `INCLUDE_OFFLOADING` 依赖从 `kmod-ipt-offload` 改为 `kmod-nft-offload`
  - 去掉 `kmod-tcp-bbr` 依赖（最新源码没有对应 kmod 包，内核默认也未开 BBR）
- init 脚本：
  - `xt_FLOWOFFLOAD.ko` → `nft_flow_offload.ko`
  - `xt_FLOWOFFLOAD` 状态检查改为 `nft_flow_offload`
- 默认配置：
  - `sw_flow=1`、`hw_flow=0`、`sfe_flow=0`
  - `fullcone_nat=0`（fw4 下 fullcone 依赖额外 nft 模块，先关闭）
  - `bbr_cca=0`、`dns_caching=0`
- 关闭 PDNSD / DNSForwarder / DNSProxy / Shortcut-FE，避免引入当前 feed 缺失的依赖。

## 运行限制

- TurboACC 的 LuCI 页面和 flow offload 开关可以装出来；
- fw4 下 `fullcone`/`iptables` 状态检查不是完全等价，部分状态可能显示不准；
- 若需要 BBR，需要在源码内核配置里打开 `CONFIG_TCP_CONG_BBR` 或补回 `kmod-tcp-bbr`；
- 首次刷机后不要默认开启 fullcone，先确认 `fw4`/`nft` 规则正常。

## 构建

Workflow：`.github/workflows/build-firmware-latest.yml`
分支：`firmware-build-latest`
配置：`config.turboacc`
Feeds：`feeds-latest.conf`
