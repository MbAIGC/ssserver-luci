#!/bin/sh
#
# 让源码优先从 OpenWrt 官方镜像下载。
#
# 背景：Lean 的 scripts/download.pl 已把 sources.openwrt.org 配成镜像，但放在
# 列表**末尾**（push），而主循环是 shift 按顺序试。于是每个包都先等
# sourceware.org / ftp.gnu.org 这类慢源超时（20s × 5 次重试），几百个包累加
# 起来能把 6 小时的 job 上限耗光。
#
# 本脚本把可用镜像 unshift 到列表开头，改为「镜像优先、原始源兜底」。
#
# 用法：./speed-up-download.sh /path/to/openwrt
#
set -eu

TOP="${1:-.}"
DL="$TOP/scripts/download.pl"
[ -f "$DL" ] || { echo "找不到 $DL" >&2; exit 1; }

python3 - "$DL" <<'EOF'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    src = f.read()

old = """push @mirrors, 'https://sources.cdn.openwrt.org';
push @mirrors, 'https://sources.openwrt.org';"""
new = """unshift @mirrors, 'https://sources.openwrt.org';
unshift @mirrors, 'https://sources.cdn.openwrt.org';"""

if "unshift @mirrors, 'https://sources.cdn.openwrt.org'" in src:
    print("  已经是镜像优先，跳过")
elif old in src:
    with open(path, "w", encoding="utf-8") as f:
        f.write(src.replace(old, new, 1))
    print("  download.pl 已改为镜像优先：sources.cdn.openwrt.org → sources.openwrt.org → 原始源")
else:
    print("  !! 未找到目标片段，download.pl 结构可能已变", file=sys.stderr)
    sys.exit(1)
EOF

# 顺手清掉一个已知 404 的镜像，省一次无谓尝试
if grep -q "mirror2.openwrt.org/sources" "$DL"; then
	sed -i "/push @mirrors, 'https:\/\/mirror2.openwrt.org\/sources';/d" "$DL"
	echo "  已移除失效镜像 mirror2.openwrt.org"
fi

echo "  验证："
grep -nE "unshift @mirrors|push @mirrors, 'https://sources" "$DL" | head -5
