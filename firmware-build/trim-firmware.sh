#!/bin/sh
#
# 固件精简：移除 x86 上无意义/不需要的组件。
# 用法：./trim-firmware.sh /path/to/openwrt
#
set -eu

TOP="${1:-.}"
[ -d "$TOP" ] || { echo "目录不存在: $TOP" >&2; exit 1; }
cd "$TOP"

SYS_MOD="feeds/luci/modules/luci-mod-system"

# ---- LED 配置：菜单与视图一并移除（x86 无 LED 硬件）
if [ -d "$SYS_MOD" ]; then
	rm -f  "$SYS_MOD"/htdocs/luci-static/resources/view/system/leds.js
	rm -rf "$SYS_MOD"/htdocs/luci-static/resources/view/system/led-trigger
	MENU="$SYS_MOD/root/usr/share/luci/menu.d/luci-mod-system.json"
	if [ -f "$MENU" ]; then
		python3 -c '
import json, sys
p = sys.argv[1]
with open(p, encoding="utf-8") as f:
    d = json.load(f)
removed = d.pop("admin/system/leds", None) is not None
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent="\t")
print("  menu admin/system/leds removed:", removed)
' "$MENU"
	fi
	echo "  led view removed"
else
	echo "  未找到 $SYS_MOD，跳过 LED 清理" >&2
fi

echo "trim 完成"
