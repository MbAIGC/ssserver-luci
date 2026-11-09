'use strict';
'require view';
'require form';
'require fs';
'require uci';
'require ui';

var INIT = '/etc/init.d/ssserver';

return view.extend({
	load: function() {
		return uci.load('ssserver');
	},

	render: function() {
		var m, s, o;

		m = new form.Map('ssserver', _('高级设置'),
			_('这些参数直接映射到 ssserver 配置文件字段。不确定时保持默认，错误的取值范围会被后端校验拦下。'));

		s = m.section(form.NamedSection, 'main', 'ssserver');
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'no_delay', _('TCP_NODELAY'),
			_('关闭 Nagle 算法，降低小包延迟（对交互和视频分片有帮助）。'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'keep_alive', _('TCP 保活（秒）'));
		o.datatype = 'uinteger';
		o.placeholder = '0';
		o.description = _('对应 keep_alive：开启 SO_KEEPALIVE 并设置保活间隔。填 0 表示不设置。');
		o.validate = function(section_id, value) {
			if (!value)
				return true;
			if (!/^\d+$/.test(value))
				return _('必须是非负整数');
			return true;
		};

		o = s.option(form.Value, 'timeout', _('连接超时（秒）'));
		o.datatype = 'uinteger';
		o.rmempty = true;
		o.placeholder = _('留空则使用 ssserver 默认');
		o.description = _('对应 timeout：服务端 TCP 套接字超时。');

		o = s.option(form.Value, 'nofile', _('文件描述符上限'));
		o.datatype = 'uinteger';
		o.placeholder = '10240';
		o.description = _('同时写入配置文件的 nofile 与 procd 的 limits，二者保持一致。');

		o = s.option(form.ListValue, 'log_level', _('日志等级'));
		o.rmempty = false;
		o.value('default', _('跟随 ssserver 默认（不写 log 字段）'));
		o.value('0', '0 · 最少');
		o.value('1', '1 · 错误');
		o.value('2', '2 · 警告');
		o.value('3', '3 · 信息');
		o.value('4', '4 · 最详细（调试用）');
		o.description = _('对应配置中的 log.level（数值）。不同版本的具体档位含义可能略有差异，' +
			'若日志级别不符合预期，可直接改 /etc/config/ssserver 中的 log_level。');

		return m.render();
	},

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
