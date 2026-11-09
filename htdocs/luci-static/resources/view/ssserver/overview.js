'use strict';
'require view';
'require fs';
'require poll';
'require ui';
'require uci';
'require rpc';

var INIT = '/etc/init.d/ssserver';
var LOGREAD = '/sbin/logread';

var callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: [ 'name' ],
	expect: { 'ssserver': {} }
});

function runInit(args) {
	return fs.exec(INIT, args || []).catch(function() {
		return { code: -1, stdout: '', stderr: '' };
	});
}

function fetchStatus() {
	return callServiceList('ssserver').then(function(res) {
		var instances = (res && res.instances) || {};
		var names = Object.keys(instances);
		var running = null;

		for (var i = 0; i < names.length; i++) {
			if (instances[names[i]] && instances[names[i]].running) {
				running = instances[names[i]];
				break;
			}
		}

		return {
			running: running != null,
			pid: running ? running.pid : null
		};
	}).catch(function() {
		return { running: false, pid: null };
	});
}

function fetchAutostart() {
	return runInit([ 'state' ]).then(function(res) {
		return String(res.stdout || '').trim() === 'enabled';
	});
}

function fetchLog() {
	var args = [ '-l', '400', '-e', 'ssserver' ];

	return fs.exec(LOGREAD, args).catch(function() {
		/* 部分固件把 busybox applet 放在 /bin 下 */
		return fs.exec('/bin/logread', args);
	}).then(function(res) {
		return String(res.stdout || '').trim();
	}).catch(function() {
		return null;
	});
}

function fetchConfig() {
	return uci.load('ssserver').then(function() {
		return {
			server: uci.get('ssserver', 'main', 'server') || '0.0.0.0',
			port: uci.get('ssserver', 'main', 'server_port') || '8388',
			method: uci.get('ssserver', 'main', 'method') || 'aes-256-gcm',
			mode: uci.get('ssserver', 'main', 'mode') || 'tcp_and_udp',
			password: uci.get('ssserver', 'main', 'password') || ''
		};
	}).catch(function() {
		return { server: '0.0.0.0', port: '8388', method: 'aes-256-gcm', mode: 'tcp_and_udp', password: '' };
	});
}

function fetchVersion() {
	return fs.exec('/usr/bin/ssserver', [ '--version' ]).then(function(res) {
		var out = String(res.stdout || res.stderr || '').trim();
		return out.split('\n')[0] || null;
	}).catch(function() {
		return null;
	});
}

function modeLabel(mode) {
	switch (mode) {
	case 'tcp_only':
		return _('仅 TCP');
	case 'udp_only':
		return _('仅 UDP');
	case 'tcp_and_udp':
		return _('TCP + UDP');
	}

	return mode || '-';
}

return view.extend({
	load: function() {
		return Promise.all([ fetchStatus(), fetchAutostart(), fetchLog(), fetchConfig(), fetchVersion() ]);
	},

	render: function(data) {
		var self = this;
		var nodes = this.nodes = {
			state: E('span', { 'style': 'font-weight:bold' }),
			pid: E('span', {}, [ '-' ]),
			listen: E('span', {}, [ '-' ]),
			mode: E('span', {}, [ '-' ]),
			method: E('span', {}, [ '-' ]),
			autostart: E('span', {}, [ '-' ]),
			version: E('span', {}, [ '-' ]),
			log: E('pre', {
				'style': 'max-height:420px;overflow:auto;white-space:pre-wrap;word-break:break-all;' +
					'font-size:12px;line-height:1.5;padding:8px;border-radius:4px;background:rgba(127,127,127,0.08)'
			}, [ _('加载中…') ])
		};

		var rows = [
			[ _('运行状态'), nodes.state ],
			[ _('进程 PID'), nodes.pid ],
			[ _('监听地址'), nodes.listen ],
			[ _('协议模式'), nodes.mode ],
			[ _('加密方式'), nodes.method ],
			[ _('服务端版本'), nodes.version ],
			[ _('开机自启'), nodes.autostart ]
		];

		var table = E('table', { 'class': 'table' }, rows.map(function(row) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '28%' }, [ row[0] ]),
				E('td', { 'class': 'td left' }, [ row[1] ])
			]);
		}));

		var actions = E('div', { 'class': 'cbi-page-actions' }, [
			E('button', {
				'class': 'cbi-button cbi-button-apply',
				'click': ui.createHandlerFn(this, function() {
					return self.runAction('start', _('启动'));
				})
			}, [ _('启动') ]),
			' ',
			E('button', {
				'class': 'cbi-button cbi-button-reset',
				'click': ui.createHandlerFn(this, function() {
					return self.runAction('stop', _('停止'));
				})
			}, [ _('停止') ]),
			' ',
			E('button', {
				'class': 'cbi-button cbi-button-action',
				'click': ui.createHandlerFn(this, function() {
					return self.runAction('apply', _('重启（校验失败自动回滚）'));
				})
			}, [ _('重启') ])
		]);

		var autostartBtn = E('button', {
			'class': 'cbi-button',
			'click': ui.createHandlerFn(this, function() {
				return self.toggleAutostart();
			})
		}, [ _('切换开机自启') ]);

		var refreshBtn = E('button', {
			'class': 'cbi-button cbi-button-action',
			'click': ui.createHandlerFn(this, function() {
				return self.refresh().then(function() {
					ui.addNotification(null, E('p', {}, [ _('已刷新') ]), 'info');
				});
			})
		}, [ _('刷新日志') ]);

		var root = E('div', {}, [
			E('h3', {}, [ _('服务状态') ]),
			table,
			E('p', { 'class': 'cbi-section-descr' }, [
				_('页面状态取自 procd/ubus 的实际进程状态，不是 UCI 里的开关值。')
			]),
			actions,
			E('h3', {}, [ _('最近日志') ]),
			E('p', { 'class': 'cbi-section-descr' }, [
				_('来源：系统 syslog（logger -t ssserver 以及 procd 捕获的 ssserver stderr）。密码等敏感内容已做脱敏。')
			]),
			nodes.log,
			E('div', { 'class': 'cbi-page-actions' }, [ refreshBtn, ' ', autostartBtn ]),
			E('p', { 'class': 'cbi-section-descr' }, [
				_('提示：本插件不修改防火墙。若外部无法连接，请自行放行上表显示的地址与端口（含 UDP）。')
			])
		]);

		this.update(data[0], data[1], data[2], data[3], data[4]);

		poll.add(function() {
			return self.refresh();
		}, 5);

		poll.start();

		return root;
	},

	update: function(status, autostart, logtext, cfg, version) {
		var nodes = this.nodes;
		if (!nodes)
			return;

		this.autostart = autostart;

		nodes.state.textContent = status.running ? _('运行中') : _('已停止');
		nodes.state.style.color = status.running ? '#2e7d32' : '#c62828';

		nodes.pid.textContent = status.pid != null ? String(status.pid) : '-';
		nodes.listen.textContent = '%s:%s'.format(cfg.server, cfg.port);
		nodes.mode.textContent = modeLabel(cfg.mode);
		nodes.method.textContent = cfg.method;
		nodes.autostart.textContent = autostart ? _('已启用') : _('未启用');
		nodes.version.textContent = version || _('未检测到 /usr/bin/ssserver');

		if (logtext === null || logtext === undefined) {
			nodes.log.textContent = _('无法读取日志（需要 logread 权限，或系统未启用 syslog）。');
			return;
		}

		var text = logtext;

		if (cfg.password && cfg.password.length >= 6)
			text = text.split(cfg.password).join('********');

		nodes.log.textContent = text.length ? text : _('（暂无日志）');
	},

	refresh: function() {
		var self = this;

		return Promise.all([ fetchStatus(), fetchAutostart(), fetchLog(), fetchConfig(), fetchVersion() ]).then(function(res) {
			self.update(res[0], res[1], res[2], res[3], res[4]);
		});
	},

	runAction: function(action, label) {
		var self = this;

		return runInit([ action ]).then(function(res) {
			var err = String(res.stderr || '').trim();

			if (res.code !== 0)
				throw new Error(err || _('命令返回码 %d').format(res.code));

			ui.addNotification(null, E('p', {}, [ _('操作成功：%s').format(label) ]), 'info');
		}).catch(function(err) {
			ui.addNotification(null, E('p', {}, [ _('操作失败：%s').format(err.message || err) ]), 'danger');
		}).then(function() {
			return self.refresh();
		});
	},

	toggleAutostart: function() {
		var self = this;
		var action = this.autostart ? 'disable' : 'enable';
		var label = this.autostart ? _('关闭开机自启') : _('开启开机自启');

		return runInit([ action ]).then(function(res) {
			if (res.code !== 0)
				throw new Error(String(res.stderr || '').trim() || _('命令返回码 %d').format(res.code));

			ui.addNotification(null, E('p', {}, [ _('已执行：%s').format(label) ]), 'info');
		}).catch(function(err) {
			ui.addNotification(null, E('p', {}, [ _('操作失败：%s').format(err.message || err) ]), 'danger');
		}).then(function() {
			return self.refresh();
		});
	}
});
