#!/bin/sh
#
# 本地/CI 通用的静态检查：不依赖 OpenWrt SDK。
#

set -e

cd "$(dirname "$0")/.."

echo "== shell 语法 =="
for f in root/etc/init.d/ssserver root/etc/uci-defaults/90-ssserver-luci; do
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
	for f in $(find luasrc -name '*.lua' | sort); do
		$LUA_CHECK "$f"
		echo "ok  $f"
	done
else
	echo "skip: 未安装 luac"
fi

echo "== 模板语法 =="
for f in $(find luasrc -name '*.htm' | sort); do
	# 至少保证 <% 与 %> 成对
	o=$(grep -o '<%' "$f" | wc -l)
	c=$(grep -o '%>' "$f" | wc -l)
	[ "$o" = "$c" ] || { echo "ERR $f: <% 与 %> 数量不匹配 ($o/$c)" >&2; exit 1; }
	echo "ok  $f ($o 个代码块)"
done

echo "== JSON 语法 =="
if ls root/usr/share/**/*.json >/dev/null 2>&1; then
	python3 - <<'PY'
import glob
import json
import sys

bad = 0
for f in sorted(glob.glob('root/usr/share/**/*.json', recursive=True)):
    try:
        with open(f, encoding='utf-8') as fh:
            json.load(fh)
        print('ok  ' + f)
    except Exception as exc:
        bad = 1
        print('ERR ' + f + ': ' + str(exc))
sys.exit(bad)
PY
else
	echo "skip: 没有 JSON 文件"
fi

echo "== 防火墙关键词检查（应无输出） =="
if grep -rnE '\b(iptables|ip6tables|nft|nftables|fw3|fw4|tproxy)\b' root/ luasrc/ 2>/dev/null; then
	echo "错误：检测到防火墙相关代码" >&2
	exit 1
fi

echo "全部检查通过"
