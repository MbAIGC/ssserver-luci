'use strict';
'require view';
'require form';
'require fs';
'require uci';
'require ui';

var INIT = '/etc/init.d/ssserver';

var METHODS = [
	[ 'aes-256-gcm',               'AEAD · AES-256-GCM（推荐）' ],
	[ 'aes-128-gcm',               'AEAD · AES-128-GCM' ],
	[ 'chacha20-ietf-poly1305',    'AEAD · ChaCha20-IETF-Poly1305（无 AES 加速时更快）' ],
	[ 'xchacha20-ietf-poly1305',   'AEAD · XChaCha20-IETF-Poly1305' ],
	[ '2022-blake3-aes-256-gcm',   '2022 · blake3-aes-256-gcm（需 44 字符 base64 密钥）' ],
	[ '2022-blake3-aes-128-gcm',   '2022 · blake3-aes-128-gcm（需 24 字符 base64 密钥）' ],
	[ '2022-blake3-chacha20-poly1305', '2022 · blake3-chacha20-poly1305（需 44 字符 base64 密钥）' ]
];

/*
 * 2022-blake3-* 使用固定长度的 base64 预共享密钥，而不是普通口令。
 * 这里提前拦下来，避免保存后才发现 ssserver 起不来。
 */
function checkPskLength(method, value) {
	if (method === '2022-blake3-aes-128-gcm' && value.length !== 24)
		return _('该加密方式需要 24 字符 base64 预共享密钥');
	if ((method === '2022-blake3-aes-256-gcm' || method === '2022-blake3-chacha20-poly1305') && value.length !== 44)
		return _('该加密方式需要 44 字符 base64 预共享密钥');
	return true;
}

return view.extend({
	load: function() {
		return uci.load('ssserver');
	},

	render: function() {
		var m, s, o;

		m = new form.Map('ssserver', _('Shadowsocks 服务端配置'),
			_('配置写入 /etc/config/ssserver；启动时生成 /var/etc/ssserver/config.json。' +
			  '「保存并应用」会先校验再重启，失败自动回滚到上一份可用配置。'));

		s = m.section(form.NamedSection, 'main', 'ssserver');
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Value, 'server', _('监听地址'));
		o.rmempty = false;
		o.placeholder = '0.0.0.0';
		o.description = _('0.0.0.0 只监听 IPv4；:: 同时监听 IPv6（双栈）；也可以填具体网卡地址或主机名。');
		o.validate = function(section_id, value) {
			if (!value)
				return _('监听地址不能为空');

			if (value === '0.0.0.0' || value === '::' || value === '*')
				return true;

			if (/^(\d{1,3}\.){3}\d{1,3}$/.test(value)) {
				var parts = value.split('.');
				for (var i = 0; i < parts.length; i++) {
					var n = +parts[i];
					if (n < 0 || n > 255 || String(n) !== parts[i])
						return _('IPv4 地址格式不正确');
				}
				return true;
			}

			if (value.indexOf(':') >= 0 && /^[0-9a-fA-F:.]+$/.test(value))
				return true;

			if (/^[a-zA-Z0-9._-]+$/.test(value))
				return true;

			return _('请填写 IP 地址或主机名');
		};

		o = s.option(form.Value, 'server_port', _('监听端口'));
		o.datatype = 'port';
		o.rmempty = false;
		o.placeholder = '8388';
		o.description = _('1-65535。TCP 与 UDP 使用同一端口。');

		o = s.option(form.Value, 'password', _('连接密码'));
		o.password = true;
		o.rmempty = false;
		o.description = _('保存后以明文存放在 /etc/config/ssserver（权限 600）。' +
			'使用 2022-blake3-* 时这里填 base64 预共享密钥。');
		o.validate = function(section_id, value) {
			if (!value)
				return _('密码不能为空');

			/* 取下拉框的实时值，而不是已保存的值：用户可能同一次编辑里改了加密方式 */
			var el = document.getElementById('cbid.ssserver.main.method');
			var method = el ? el.value : (uci.get('ssserver', 'main', 'method') || '');

			return checkPskLength(method, value);
		};

		o = s.option(form.ListValue, 'method', _('加密方式'));
		o.rmempty = false;
		for (var i = 0; i < METHODS.length; i++)
			o.value(METHODS[i][0], METHODS[i][1]);
		o.description = _('只有 AEAD / 2022 两类是安全的；列表外的旧算法（rc4-md5、aes-256-cfb 等）不再提供。' +
			'若目标设备编译时未启用 2022 特性，选 2022 会在启动阶段报错并回滚。');

		o = s.option(form.ListValue, 'mode', _('协议模式'));
		o.rmempty = false;
		o.value('tcp_only', _('仅 TCP'));
		o.value('tcp_and_udp', _('TCP + UDP'));
		o.value('udp_only', _('仅 UDP'));
		o.description = _('对应 ssserver 的 mode 字段。UDP 需要在客户端与服务端同时开启。');

		return m.render();
	},

	/*
	 * 覆盖默认的「保存并应用」：
	 *   1. 解析并暂存 UCI 变更
	 *   2. uci apply 提交（本服务未注册 reload 触发器，不会自动重启）
	 *   3. 显式执行 /etc/init.d/ssserver apply（校验 + 重启 + 失败回滚）
	 */
	handleSaveApply: function(ev, mode) {
		return this.handleSave(ev).then(function() {
			return uci.apply();
		}).then(function() {
			return fs.exec(INIT, [ 'apply' ]);
		}).then(function(res) {
			if (res.code !== 0)
				throw new Error(String(res.stderr || '').trim() || _('返回码 %d').format(res.code));

			ui.addNotification(null, E('p', {}, [ _('配置已保存并应用，服务运行正常。') ]), 'info');
		}).catch(function(err) {
			ui.addNotification(null, E('p', {}, [
				_('应用失败：%s').format(err.message || err),
				E('br'),
				_('已尝试回滚到上一份可用配置；详细原因见「运行概览」的日志。')
			]), 'danger');
		});
	}
});
