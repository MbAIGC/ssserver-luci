# 构建产物

所有固件都通过 GitHub Actions 自动编译并发布到 Release，本地不再保留镜像。

## 当前版本

- Release：**LEDE-R26.11.10-20261110**
- 页面：https://github.com/MbAIGC/ssserver-luci/releases/tag/LEDE-R26.11.10-20261110
- 源码：`coolsnowwolf/lede@ff6b739d41cdc3767b266d777dfe8a87c89bff00`（master）
- 内核：**6.18 LTS**（构建时 6.18.62）
- 包数：521
- 镜像：`openwrt-x86-64-generic-squashfs-combined-efi.img.gz`（约 159 MB）
- SHA256：`9aa99a97f16b16663e0c5cf538df9fa938783f5ed258e8877fbadb1b3963ec8e`

已包含：

```text
kmod-wireguard / wireguard-tools / luci-proto-wireguard
ssserver-luci / shadowsocks-rust-ssserver
ddns-go / luci-app-ddns-go
luci-app-passwall / sing-box / luci-app-openclash
luci-app-turboacc + kmod-nft-offload
```

## 命名规则

```
LEDE-R<yy.m.d>-<yyyymmdd>
```

例：`LEDE-R26.11.10-20261110`
—— 版本取 Lean 的 `BUILD_DATE`（`TZ=Asia/Shanghai date +%y.%-m.%-d`），日期为编译当天。

## 自动发布

`.github/workflows/build-firmware-latest.yml` 在构建成功后会：

1. 收集镜像、`.sha256`、`manifest`、`.config`；
2. 用 `gh release create/upload` 发布，tag 与标题都是上述命名；
3. 同日重跑会 `--clobber` 覆盖同名 Release。

触发方式：

```bash
gh workflow run build-firmware-latest.yml --ref firmware-build-latest
```

或推送 `firmware-build-latest` 分支上相关文件。

## 历史版本

- `firmware-2026-10-11`：基于 `lede@27d57f45e`（2026-10-11 快照）反推构建，518 包。
  命名未按当前规则，保留作对照。

## 刷机

```bash
gunzip -c openwrt-x86-64-generic-squashfs-combined-efi.img.gz > fw.img
sudo dd if=fw.img of=/dev/sdX bs=4M status=progress conv=fsync
```

首次启动：LAN `192.168.1.253`，root 密码 `password`，串口 `ttylogin=0`。
登录后请立即改密码并设置 `ttylogin=1`。
