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
    m = new form.Map('warp', _('Cloudflare WARP'), _(''));

    s = m.section(form.NamedSection, 'config', 'warp', _('WARP керування'));
    s.addremove = false;

    // --- Статус ---
    o = s.option(form.DummyValue, '_status', _('Статус'));
    o.rawhtml = true;
    o.cfgvalue = function() {
      return '<pre style="background:#f5f5f5;padding:8px;border-radius:6px;white-space:pre-wrap">'
        + status.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
        + '</pre>';
    };

    // --- Підключити ---
    o = s.option(form.Button, '_connect');
    o.title = _('Підключити');
    o.inputtitle = _('⚡️ Підключити WARP');
    o.inputstyle = 'apply';
    o.onclick = function() {
      ui.showModal(_('WARP'), [
        E('p', _('Реєстрація... ~10с')),
        E('p', {}, _('Не закривайте сторінку'))
      ]);
      return fs.exec('/usr/bin/warp-api.sh', ['connect']).then(function(res) {
        ui.hideModal();
        ui.addNotification(null, E('pre', res.stdout || res.stderr || '—'), 'info');
        window.location.reload();
      }).catch(function(e) {
        ui.hideModal();
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    };

    // --- Видалити ---
    o = s.option(form.Button, '_delete');
    o.title = _('Видалити');
    o.inputtitle = _('🗑 Видалити WARP');
    o.inputstyle = 'remove';
    o.onclick = function() {
      if (!confirm(_('Видалити WARP повністю?'))) return;
      return fs.exec('/usr/bin/warp-api.sh', ['delete']).then(function(res) {
        ui.addNotification(null, E('pre', res.stdout || res.stderr || '—'), 'info');
        window.location.reload();
      }).catch(function(e) {
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    };

    // --- Весь трафік ---
    o = s.option(form.Button, '_all');
    o.title = _('Режим: весь трафік');
    o.inputtitle = _('🟢 Весь трафік через WARP');
    o.inputstyle = 'apply';
    o.onclick = function() {
      return fs.exec('/usr/bin/warp-api.sh', ['mode_all']).then(function(r) {
        ui.addNotification(null, E('pre', r.stdout || r.stderr || '—'), 'info');
        window.location.reload();
      }).catch(function(e) {
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    };

    // --- Режим PBR ---
    o = s.option(form.Button, '_mode_pbr');
    o.title = _('Режим: тільки список');
    o.inputtitle = _('📋 Увімкнути PBR (тільки список IP)');
    o.inputstyle = 'apply';
    o.onclick = function() {
      ui.showModal(_('PBR'), [ E('p', _('Активую PBR маршрутизацію...')) ]);
      return fs.exec('/usr/bin/warp-api.sh', ['mode_pbr']).then(function(r) {
        ui.hideModal();
        ui.addNotification(null, E('pre', r.stdout || r.stderr || '—'), 'info');
        window.location.reload();
      }).catch(function(e) {
        ui.hideModal();
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    };

    // --- Зупинити ---
    o = s.option(form.Button, '_stop');
    o.title = _('Зупинити маршрутизацію');
    o.inputtitle = _('⏸ Зупинити (тунель є)');
    o.inputstyle = 'button';
    o.onclick = function() {
      return fs.exec('/usr/bin/warp-api.sh', ['mode_stop']).then(function(r) {
        ui.addNotification(null, E('pre', r.stdout || r.stderr || '—'), 'info');
        window.location.reload();
      }).catch(function(e) {
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    };

    // --- MTU тест (фоновий) ---
    o = s.option(form.Button, '_mtu');
    o.title = _('MTU тест');
    o.inputtitle = _('📏 Підібрати MTU автоматично');
    o.inputstyle = 'button';
    o.onclick = function() {
      ui.showModal(_('MTU тест'), [
        E('p', _('Запускаю тест у фоні (~30с)...')),
        E('p', {style:'color:#888'}, _('Оновіть сторінку через 35 секунд — результат з\'явиться у блоці Статус.'))
      ]);
      return fs.exec('/usr/bin/warp-api.sh', ['mtu']).then(function(r) {
        ui.hideModal();
        ui.addNotification(null, E('pre', r.stdout || r.stderr || '—'), 'info');
      }).catch(function(e) {
        ui.hideModal();
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    };

    // --- Результат MTU ---
    o = s.option(form.Button, '_mtu_result');
    o.title = _('Результат MTU');
    o.inputtitle = _('📋 Показати лог MTU тесту');
    o.inputstyle = 'button';
    o.onclick = function() {
      return fs.exec('/usr/bin/warp-api.sh', ['mtu_result']).then(function(r) {
        ui.addNotification(null, E('pre', r.stdout || r.stderr || '—'), 'info');
      }).catch(function(e) {
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    };

    // --- Найкращий endpoint (фоновий) ---
    o = s.option(form.Button, '_best_endpoint');
    o.title = _('Endpoint');
    o.inputtitle = _('🌍 Підібрати найшвидший endpoint');
    o.inputstyle = 'button';
    o.onclick = function() {
      ui.showModal(_('Endpoint'), [
        E('p', _('Пінгую 7 Cloudflare IP у фоні (~20с)...')),
        E('p', {style:'color:#888'}, _('Оновіть сторінку через 25 секунд — результат з\'явиться у блоці Статус.'))
      ]);
      return fs.exec('/usr/bin/warp-api.sh', ['best_endpoint']).then(function(r) {
        ui.hideModal();
        ui.addNotification(null, E('pre', r.stdout || r.stderr || '—'), 'info');
      }).catch(function(e) {
        ui.hideModal();
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    };

    // --- Результат endpoint ---
    o = s.option(form.Button, '_endpoint_result');
    o.title = _('Результат endpoint');
    o.inputtitle = _('📋 Показати лог вибору endpoint');
    o.inputstyle = 'button';
    o.onclick = function() {
      return fs.exec('/usr/bin/warp-api.sh', ['endpoint_result']).then(function(r) {
        ui.addNotification(null, E('pre', r.stdout || r.stderr || '—'), 'info');
      }).catch(function(e) {
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    };

    // --- Пінг endpoint ---
    o = s.option(form.Button, '_ping');
    o.title = _('Пінг Cloudflare');
    o.inputtitle = _('📡 Пінг endpoint\'ів');
    o.inputstyle = 'button';
    o.onclick = function() {
      return fs.exec('/usr/bin/warp-api.sh', ['ping']).then(function(r) {
        ui.addNotification(null, E('pre', r.stdout || r.stderr || '—'), 'info');
      }).catch(function(e) {
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    };

    // --- PBR секція ---
    o = s.option(form.DummyValue, '_pbr_header');
    o.rawhtml = true;
    o.cfgvalue = function() {
      return '<div style="margin-top:14px;border-top:1px solid #ddd;padding-top:10px">'
        + '<b>📋 PBR — список IP через WARP</b><br>'
        + '<small>Тільки ці адреси йдуть через WARP, решта — напряму</small></div>';
    };

    o = s.option(form.TextValue, 'blocked', _('Список (CIDR/IP, по одному на рядок)'),
      _('Напр. 93.184.216.34 або 5.188.86.0/24'));
    o.optional = true;
    o.rows = 8;
    o.load = function() { return fs.trimmed('/etc/warp/blocked.list'); };
    o.write = function(_, val) {
      return fs.write('/etc/warp/blocked.list', val.trim() + '\n');
    };

    o = s.option(form.Button, '_pbr_update');
    o.title = _('Оновити список');
    o.inputtitle = _('⬇️ Оновити з GitHub');
    o.inputstyle = 'button';
    o.onclick = function() {
      ui.showModal(_('PBR'), [ E('p', _('Завантажую список...')) ]);
      return fs.exec('/usr/bin/warp-api.sh', ['pbr_update']).then(function(r) {
        ui.hideModal();
        ui.addNotification(null, E('pre', r.stdout || r.stderr || '—'), 'info');
        window.location.reload();
      }).catch(function(e) {
        ui.hideModal();
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    };

    o = s.option(form.Button, '_pbr_apply');
    o.title = _('Застосувати правила PBR');
    o.inputtitle = _('🔄 Застосувати nftables правила');
    o.inputstyle = 'apply';
    o.onclick = function() {
      return fs.exec('/usr/bin/warp-api.sh', ['pbr_apply']).then(function(r) {
        ui.addNotification(null, E('pre', r.stdout || r.stderr || '—'), 'info');
      }).catch(function(e) {
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    };

    return m.render();
  }
});
