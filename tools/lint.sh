#!/bin/sh
#
# 本地/CI 通用静态检查，不需要 OpenWrt SDK。
#

set -e

cd "$(dirname "$0")/.."

PKGS="ssserver-luci luci-app-ddns-go"

echo "== shell 语法（uci-defaults） =="
for p in $PKGS; do
	for f in $(find "$p/root" -path '*/etc/uci-defaults/*' -type f | sort); do
		sh -n "$f"
		echo "ok  $f"
	done
done

echo "== init.d 语法 =="
for f in $(find . -path '*/root/etc/init.d/*' -type f | sort); do
	sh -n "$f"
	echo "ok  $f"
done

echo "== Lua 语法 =="
LUA_CHECK=""
if command -v luac5.1 >/dev/null 2>&1; then
	LUA_CHECK="luac5.1 -p"
elif command -v luac >/dev/null 2>&1; then
	LUA_CHECK="luac -p"
fi

if [ -n "$LUA_CHECK" ]; then
	for p in $PKGS; do
		for f in $(find "$p/luasrc" -name '*.lua' 2>/dev/null | sort); do
			$LUA_CHECK "$f"
			echo "ok  $f"
		done
	done
else
	echo "skip: 未安装 luac"
fi

echo "== 模板语法 =="
for p in $PKGS; do
	for f in $(find "$p/luasrc" -name '*.htm' 2>/dev/null | sort); do
		o=$(grep -o '<%' "$f" | wc -l)
		c=$(grep -o '%>' "$f" | wc -l)
		[ "$o" = "$c" ] || { echo "ERR $f: <% 与 %> 数量不匹配 ($o/$c)" >&2; exit 1; }
		echo "ok  $f ($o 个代码块)"
	done
done

echo "== 防火墙关键词检查（应无输出） =="
if grep -rnE '\b(iptables|ip6tables|nft|nftables|fw3|fw4|tproxy)\b' ssserver-luci/root ssserver-luci/luasrc 2>/dev/null; then
	echo "错误：检测到防火墙相关代码" >&2
	exit 1
fi

echo "全部检查通过"
