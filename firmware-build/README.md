# 固件构建配置（x86-64）

从镜像反推 + 增补插件的 Lean LEDE 构建脚手架。产物由 GitHub Actions 编译并自动发布到 Release，本地不保存镜像。

## 目录

| 文件 | 用途 |
|---|---|
| `config.turboacc` | **当前使用**：反推配置 + WireGuard + SS + DDNS + TurboACC |
| `config.buildinfo` | 早期配置（无 TurboACC） |
| `config.minimal` | 精简配置 |
| `config.full-packages` | 镜像全部包的最大化还原（易冲突） |
| `feeds-latest.conf` | **当前使用**：Lean 默认 feeds + Passwall |
| `feeds.conf` | 早期 feeds（Pin 到 2026-10-11 源码） |
| `local-packages/luci-app-turboacc/` | vendored TurboACC，已适配 firewall4/nftables |
| `examples/wireguard.network` | WireGuard UCI 示例（默认不启用） |
| `build.sh` | 本地构建脚本 |
| `references/` | 官方 24.10.5 x86_64 的 config.buildinfo / profiles.json |
| `BUILD-RESULT.md` | 当前产物、命名规则、刷机说明 |
| `KERNEL-TURBOACC-NOTES.md` | 内核选择与 TurboACC 适配说明 |

## 内核选择

Lean master 默认 `KERNEL_PATCHVER=6.18`，对应内核.org 当前 LTS（最新 6.18.62）。
6.12.116 同为 LTS，但已进入生命周期后段；6.18 对新硬件和网卡支持更好，故采用 6.18。

## TurboACC

`openwrt-25.12` 的 LuCI feed 不再提供 `luci-app-turboacc`，因此从
`coolsnowwolf/luci@master` vendored 到 `local-packages/`，并在构建时做三处适配：

- `include ../../luci.mk` → `include $(TOPDIR)/feeds/luci/luci.mk`
- `INCLUDE_OFFLOADING` 依赖 `kmod-ipt-offload` → `kmod-nft-offload`
- init 脚本 `xt_FLOWOFFLOAD` → `nft_flow_offload`

默认 `sw_flow=1`、`hw_flow=0`、`sfe_flow=0`、`fullcone_nat=0`、`bbr_cca=0`。
详见 [`KERNEL-TURBOACC-NOTES.md`](KERNEL-TURBOACC-NOTES.md)。

## 构建

```bash
gh workflow run build-firmware-latest.yml --ref firmware-build-latest
```

产物与 SHA256 见 [`BUILD-RESULT.md`](BUILD-RESULT.md)。

## 已知差异

- 使用 `firewall4`/`nftables`，不是原镜像的 firewall3/iptables；
- `miniupnpd` 为 `miniupnpd-nftables` 变体；
- BBR 默认关闭，需要时在内核配置打开 `CONFIG_TCP_CONG_BBR`；
- 版本串为 `r0-<sha>`（浅克隆导致 revision count 为 0），不影响功能；
- 首次启动会写入 root 密码 `password`、`ttylogin=0`，请立即修改。
