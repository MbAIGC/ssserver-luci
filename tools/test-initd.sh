#!/bin/sh
#
# 不依赖 OpenWrt 环境的 init.d 逻辑自测：
# 桩掉 rc.common 提供的函数，直接验证「配置校验 + JSON 生成」。
#

set -e

cd "$(dirname "$0")/.."

logger() { :; }
extra_command() { :; }

# shellcheck disable=SC1091
. ./ssserver-luci/root/etc/init.d/ssserver

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

RUN_DIR="$TMPD"
JSON="$RUN_DIR/config.json"

pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; exit 1; }

expect_ok() {
	local name="$1"
	if validate_config; then pass "$name"; else fail "$name"; fi
}

expect_bad() {
	local name="$1"
	if validate_config; then fail "$name（本应被拒绝）"; else pass "$name"; fi
}

echo "== validate_config =="

SERVER='0.0.0.0'; PORT=8388; PASSWORD='correct-horse'; METHOD='aes-256-gcm'
MODE='tcp_and_udp'; TIMEOUT=''; NO_DELAY=0; KEEP_ALIVE=0; NOFILE=10240; LOG_LEVEL=''
expect_ok "正常配置"

PORT=0
expect_bad "端口 0"
PORT=70000
expect_bad "端口越界"
PORT=8388

PASSWORD=''
expect_bad "空密码"
PASSWORD='correct-horse'

METHOD='rc4-md5'
expect_bad "废弃算法 rc4-md5"
METHOD='aes-256-gcm'

MODE='both'
expect_bad "非法 mode"
MODE='tcp_and_udp'

LOG_LEVEL='9'
expect_bad "log_level 越界"
LOG_LEVEL=''

METHOD='2022-blake3-aes-256-gcm'
PASSWORD='short'
expect_bad "2022-aes-256 密钥长度不足"
PASSWORD='12345678901234567890123456789012345678901234'
expect_ok "2022-aes-256 44 字符密钥"

METHOD='2022-blake3-aes-128-gcm'
PASSWORD='123456789012345678901234'
expect_ok "2022-aes-128 24 字符密钥"

echo "== generate_json =="

METHOD='aes-256-gcm'
PASSWORD='p@ss"word\with\backslash'
TIMEOUT='7200'
NO_DELAY=1
KEEP_ALIVE=15
LOG_LEVEL='2'

generate_json || fail "生成配置失败"

[ -f "$JSON" ] || fail "配置未生成"
[ "$(stat -c '%a' "$JSON")" = "600" ] || fail "配置文件权限不是 600"
pass "文件权限 600"

python3 - "$JSON" <<'PY' || fail "生成的 JSON 不合法"
import json
import sys

with open(sys.argv[1], encoding='utf-8') as fh:
    cfg = json.load(fh)

assert cfg['server'] == '0.0.0.0', cfg
assert cfg['server_port'] == 8388, cfg
assert cfg['password'] == 'p@ss"word\\with\\backslash', cfg['password']
assert cfg['method'] == 'aes-256-gcm', cfg
assert cfg['mode'] == 'tcp_and_udp', cfg
assert cfg['timeout'] == 7200, cfg
assert cfg['no_delay'] is True, cfg
assert cfg['keep_alive'] == 15, cfg
assert cfg['nofile'] == 10240, cfg
assert cfg['log'] == {'level': 2}, cfg
PY
pass "JSON 字段与转义正确"

echo "== apply 回滚前置条件 =="
if [ -f "$TMPD/config.json.bak" ]; then
	fail "备份文件不应在首次生成时出现"
fi
pass "首次生成无残留备份"

echo "全部通过"
