# 2026-10-11 固件反推构建配置（x86-64 + WireGuard）

本目录是“从镜像反推 + 加入 WireGuard”的构建配置。它不是原厂 `.config` 的逐字节还原，而是**可复现构建脚手架**：包清单来自镜像，目标/镜像参数来自镜像分区结构，隐藏的 `CONFIG_*` 只能按 Lean LEDE 默认值补齐。

## 1. 已确认的源码版本

镜像里的 `DISTRIB_REVISION='r8181-27d57f45e'` 与内核构建时间 `Sun Oct 11 05:45:45 2026` 精确对应：

- 仓库：`https://github.com/coolsnowwolf/lede`
- 提交：`27d57f45e01459e0d498efbf44532bfe0dfc1d40`
- 提交时间：`2026-10-11T05:45:45Z`
- 提交说明：`ath10k-ct: fix fortify build error on Linux 6.6`

因此构建时必须固定到该提交，否则内核/包版本会漂移。

## 2. 文件说明

| 文件 | 用途 |
|---|---|
| `config.buildinfo` | **推荐**构建配置：286 个顶层包 + 本地插件 + WireGuard；依赖由 `make defconfig` 自动补 |
| `config.full-packages` | 镜像全部 451 个包（去掉 `kernel/libc` 等工具链项）的最大化还原；更慢，且可能因包冲突失败 |
| `feeds.conf` | Lean 默认 feeds（`packages/luci/routing/telephony/helloworld`）+ `passwall/passwall_packages` |
| `packages-top-level.txt` | `config.buildinfo` 的包选择清单 |
| `packages-full.txt` | `config.full-packages` 的包选择清单 |
| `examples/wireguard.network` | WireGuard UCI 示例（默认不启用） |
| `build.sh` | 本地构建脚本（需要 >=30GB 磁盘、4GB+ 内存） |
| `references/` | 官方 24.10.5 x86_64 的 `config.buildinfo` / `profiles.json`，仅作目标参数参考 |

## 3. 反推依据

- 目标：`x86/64 Generic`，squashfs combined EFI。
- p1 = 64 MiB（内核/FAT），p2 = 1 GiB（squashfs + overlay）。
- 镜像为 **EFI-only**：GPT 没有 BIOS boot 分区，因此配置里 `CONFIG_GRUB_EFI_IMAGES=y`、`CONFIG_GRUB_IMAGES` 关闭。
- 版本串：`24.10.5 r8181-27d57f45e`；首次启动的 `99-default-settings` 会改成 `LEDE R26.10.11`。
- 包清单：来自镜像 `/usr/lib/opkg/status`（451 个），版本见 `../firmware-analysis/packages-2026-10-11.txt`。
- 镜像 feeds：`packages/luci/routing/telephony/helloworld` + `passwall/passwall_packages`。
- 隐藏的 `CONFIG_*`（crypto、netfilter、kernel 细节）无法从编译产物完整还原，按 Lean 默认值处理；如果构建出的包集合与镜像不一致，以 `packages-2026-10-11.txt` 为准做差异补齐。

## 4. 加入 WireGuard

配置里追加了：

```text
CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_kmod-udptunnel4=y
CONFIG_PACKAGE_kmod-udptunnel6=y
CONFIG_PACKAGE_wireguard-tools=y
CONFIG_PACKAGE_luci-proto-wireguard=y
CONFIG_PACKAGE_luci-i18n-wireguard-zh-cn=y   # 可选，feed 没有就删
```

并显式打开了 sing-box 的 WireGuard 编译开关（Passwall 的用户态 WireGuard 需要）：

```text
CONFIG_SING_BOX_BUILD_WIREGUARD=y
CONFIG_SING_BOX_BUILD_GVISOR=y
CONFIG_SING_BOX_BUILD_QUIC=y
CONFIG_SING_BOX_BUILD_UTLS=y
CONFIG_SING_BOX_BUILD_TAILSCALE=y
CONFIG_SING_BOX_BUILD_CLASH_API=y
CONFIG_SING_BOX_BUILD_ACME=y
```

构建后应能同时使用两套 WireGuard：

1. **内核 WireGuard**：`wg` + LuCI 网络 → 接口 → 协议 `WireGuard`；
2. **Passwall + sing-box 用户态 WireGuard**：Passwall 节点类型 `sing-box`、协议 `WireGuard`（`wireguard_system_interface=0`）。

> 注意：`kmod-wireguard` 必须和构建出的内核完全同版本；不要拿 24.10.5 官方 ipk 直接装到 6.18.55 内核上。

## 5. GitHub Actions 编译

工作流：`.github/workflows/build-firmware.yml`

- 触发方式：推送到 `firmware-build` 分支，或 Actions 页面手动 `Run workflow`。
- 固定源码提交 `27d57f45e...`，不是 `master` 最新。
- 自动释放 runner 磁盘、安装依赖、拉取 feeds、加入本地插件、`make defconfig`、`make download`、`make -j$(nproc)`。
- 产物：`openwrt-x86-64-generic-squashfs-combined-efi.img.gz`、`.sha256`、`.manifest`、实际 `.config`/`diffconfig`。
- 运行时间：4 核 runner 首次完整编译通常 2–5 小时；工作流超时 350 分钟。

触发示例：

```bash
git checkout -b firmware-build
git add .github/workflows/build-firmware.yml firmware-build
git commit -m "build: reconstruct 2026-10-11 firmware + wireguard"
git push -u origin firmware-build
```

或：

```bash
gh workflow run build-firmware.yml --ref firmware-build
gh run list --workflow build-firmware.yml --limit 5
gh run watch <run-id>
```

## 6. 本地构建

```bash
cd firmware-build
REPO_URL=https://github.com/coolsnowwolf/lede.git \
SOURCE_COMMIT=27d57f45e01459e0d498efbf44532bfe0dfc1d40 \
./build.sh
```

要求：Linux x86_64、>=30GB 空闲磁盘、4GB+ 内存、能访问 GitHub。构建完成后镜像在：

```text
lede/bin/targets/x86/64/openwrt-x86-64-generic-squashfs-combined-efi.img.gz
```

## 7. 构建后验证

```bash
# 镜像内包集合
unsquashfs -cat .../openwrt-x86-64-generic-squashfs-combined-efi.img.gz 2>/dev/null || true

# 启动后
opkg list-installed | grep -E 'wireguard|ssserver|passwall|sing-box|ddns-go'
wg --version
uci show network | grep -i wireguard
```

LuCI 检查：

- 网络 → 接口 → 添加新接口 → 协议里应有 `WireGuard`；
- Passwall → 节点/服务端 → 类型 `sing-box` → 协议里应有 `WireGuard`。

## 8. 已知限制

1. **不是原始 `.config`**：镜像不携带 `.config/config.buildinfo`，隐藏的 `CONFIG_*` 无法逐项还原。
2. **feed 会漂移**：`feeds.conf` 用分支（如 `luci;openwrt-25.12`），不是 2026-10-11 的 feed 提交；包版本可能比镜像新（例如 sing-box 1.14.4 vs 镜像 1.14.3）。要完全一致，需要把各 feed 也 pin 到 2026-10-11 附近的提交。
3. **包选择可能被 `make defconfig` 调整**：不可用的包会被丢弃；以构建产物里的 `.manifest` 和 `packages-2026-10-11.txt` 对比。
4. **镜像本身的安全问题不会自动修复**：默认 `root/password`、串口 `ttylogin=0`、opkg 签名关闭、FullCone NAT 2、ttyd 默认开等仍然存在，构建后请按 `../firmware-analysis/README-2026-10-11.md` 的建议处理。
5. **EFI-only**：不要用于老 BIOS 机器。
