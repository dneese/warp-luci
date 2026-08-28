'use strict';
'require view';
'require form';
'require fs';
'require ui';

return view.extend({
  load: function() {
    return fs.exec('/usr/bin/warp-api.sh', ['status']).then(function(res) {
      return res.stdout || res.stderr || '';
    }).catch(function() { return '—'; });
  },
  render: function(status) {
    var m, s, o;
    m = new form.Map('warp', _('Cloudflare WARP'), _('Легка настройка Cloudflare WARP: статус, підключити, видалити, весь трафік, список, пінг, MTU.'));

    s = m.section(form.NamedSection, 'config', 'warp', _('WARP керування'));
    s.addremove = false;

    o = s.option(form.DummyValue, '_status', _('Статус'));
    o.rawhtml = true;
    o.cfgvalue = function() { return '<pre style="background:#f5f5f5;padding:8px;border-radius:6px">' + status.replace(/&/g,'&amp;').replace(/</g,'&lt;') + '</pre>'; };

    o = s.option(form.Button, '_connect');
    o.title = _('Підключити');
    o.inputtitle = _('⚡️ Підключити WARP');
    o.inputstyle = 'apply';
    o.onclick = function() {
      ui.showModal(_('WARP'), [ E('p', _('Реєстрація... ~10с')), E('p', {}, _('Не закривайте сторінку')) ]);
      return fs.exec('/usr/bin/warp-api.sh', ['connect']).then(function(res) {
        ui.hideModal();
        ui.addNotification(null, E('pre', res.stdout || res.stderr), 'info');
        window.location.reload();
      });
    };

    o = s.option(form.Button, '_delete');
    o.title = _('Видалити');
    o.inputtitle = _('🗑 Видалити WARP');
    o.inputstyle = 'remove';
    o.onclick = function() {
      if (!confirm(_('Видалити WARP повністю?'))) return;
      return fs.exec('/usr/bin/warp-api.sh', ['delete']).then(function(res) {
        ui.addNotification(null, E('pre', res.stdout), 'info');
        window.location.reload();
      });
    };

    o = s.option(form.Button, '_all');
    o.title = _('Весь трафік');
    o.inputtitle = _('🟢 Весь трафік через WARP');
    o.inputstyle = 'apply';
    o.onclick = function() { return fs.exec('/usr/bin/warp-api.sh', ['mode_all']).then(function(r){ ui.addNotification(null, E('pre', r.stdout), 'info'); }); };

    o = s.option(form.Button, '_stop');
    o.title = _('Зупинити');
    o.inputtitle = _('⏸ Зупинити (тунель є)');
    o.inputstyle = 'button';
    o.onclick = function() { return fs.exec('/usr/bin/warp-api.sh', ['mode_stop']).then(function(r){ ui.addNotification(null, E('pre', r.stdout), 'info'); }); };

    o = s.option(form.DummyValue, '_pbr');
    o.rawhtml = true;
    o.cfgvalue = function() {
      return '<div style="margin-top:12px"><b>📋 PBR Список (112 CIDR → WARP)</b><br><small>Тільки заблоковані IP через WARP, решта напряму</small></div>';
    };

    o = s.option(form.TextValue, 'blocked', _('Список (по одному CIDR/IP на рядок)'), _('Напр. 93.184.216.34 або 5.188.86.0/24. Застосувати — кнопка нижче.'));
    o.optional = true;
    o.rows = 6;
    o.load = function() { return fs.trimmed('/etc/tg-bot/blocked.list'); };
    o.write = function(_, val) { return fs.write('/etc/tg-bot/blocked.list', val.trim() + '\n'); };

    o = s.option(form.Button, '_pbr_apply');
    o.title = _('PBR Застосувати');
    o.inputtitle = _('🔄 Застосувати PBR');
    o.inputstyle = 'apply';
    o.onclick = function() { return fs.exec('/usr/bin/warp-api.sh', ['pbr_apply']).then(function(r){ ui.addNotification(null, E('pre', r.stdout), 'info'); }); };

    o = s.option(form.Button, '_mtu');
    o.title = _('MTU тест');
    o.inputtitle = _('📏 MTU-тест (1420/1400/1380/1280)');
    o.inputstyle = 'button';
    o.onclick = function() {
      ui.showModal(_('MTU'), [ E('p', _('Тестую ~1.5 хв, інтернет мигатиме...')) ]);
      return fs.exec('/usr/bin/warp-api.sh', ['mtu']).then(function(r){ ui.hideModal(); ui.addNotification(null, E('pre', r.stdout), 'info'); });
    };

    o = s.option(form.Button, '_ping');
    o.title = _('Пінг');
    o.inputtitle = _('📡 Пінг endpoint');
    o.inputstyle = 'button';
    o.onclick = function() { return fs.exec('/usr/bin/warp-api.sh', ['ping']).then(function(r){ ui.addNotification(null, E('pre', r.stdout), 'info'); }); };

    return m.render();
  }
});
