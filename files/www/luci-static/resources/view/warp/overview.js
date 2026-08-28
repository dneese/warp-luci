'use strict';
'require view';
'require fs';
'require ui';

// Визначаємо поточний стан за stdout warp-api.sh status
function parseState(status) {
  if (/не налаштовано/i.test(status))      return 'disconnected';
  if (/Немає handshake/i.test(status))     return 'no_handshake';
  if (/тільки заблоков/i.test(status))     return 'pbr';
  if (/весь трафік/i.test(status))         return 'all';
  if (/не перехоплюється/i.test(status))   return 'stopped';
  if (/Тунель активний/i.test(status))     return 'stopped'; // є тунель але режим невідомий
  return 'disconnected';
}

return view.extend({

  // Кожні 5с автооновлення статусу після дії
  _pollTimer: null,

  load: function() {
    return fs.exec('/usr/bin/warp-api.sh', ['status']).then(function(r) {
      return r.stdout || r.stderr || '';
    }).catch(function() { return ''; });
  },

  render: function(status) {
    var self = this;
    var state = parseState(status);

    // ─── Кольорова схема ───────────────────────────────────────────────────
    var palette = {
      disconnected: { bg: '#f0f0f0', border: '#bbb',    icon: '☁️',  label: 'WARP вимкнено',         hint: 'Натисніть, щоб підключити та увімкнути доступ до заблокованих сайтів' },
      no_handshake: { bg: '#fff3cd', border: '#ffc107', icon: '⚠️',  label: 'Немає з\'єднання',      hint: 'Тунель є, але немає відповіді від Cloudflare. Спробуйте MTU або Endpoint.' },
      pbr:          { bg: '#d4edda', border: '#28a745', icon: '✅',  label: 'WARP: тільки список',   hint: 'Заблоковані сайти зі списку йдуть через WARP. Натисніть, щоб переключити.' },
      all:          { bg: '#cce5ff', border: '#007bff', icon: '🌐',  label: 'WARP: весь трафік',     hint: 'Весь інтернет-трафік іде через Cloudflare WARP. Натисніть, щоб переключити.' },
      stopped:      { bg: '#f8d7da', border: '#dc3545', icon: '⏸',  label: 'WARP зупинено',         hint: 'Тунель активний, але трафік не перенаправляється.' },
    };
    var p = palette[state] || palette.disconnected;

    // ─── Кореневий контейнер ───────────────────────────────────────────────
    var root = E('div', { style: 'max-width:520px;margin:0 auto;font-family:sans-serif' });

    // ─── Головна кнопка-статус ─────────────────────────────────────────────
    var mainCard = E('div', {
      id: 'warp-main-card',
      style: [
        'background:' + p.bg,
        'border:2px solid ' + p.border,
        'border-radius:16px',
        'padding:28px 24px 20px',
        'text-align:center',
        'margin-bottom:18px',
        'cursor:default',
        'transition:box-shadow .2s'
      ].join(';')
    });

    mainCard.appendChild(E('div', { style: 'font-size:52px;line-height:1;margin-bottom:10px' }, p.icon));
    mainCard.appendChild(E('div', { style: 'font-size:22px;font-weight:700;margin-bottom:6px;color:#222' }, p.label));
    mainCard.appendChild(E('div', { style: 'font-size:13px;color:#555;margin-bottom:18px' }, p.hint));

    // ─── Кнопки дій (залежать від стану) ──────────────────────────────────
    var btnRow = E('div', { style: 'display:flex;gap:10px;justify-content:center;flex-wrap:wrap' });

    function mkBtn(label, style, onclick) {
      var styles = {
        primary:  'background:#007bff;color:#fff;border:none;border-radius:10px;padding:11px 22px;font-size:15px;font-weight:600;cursor:pointer',
        success:  'background:#28a745;color:#fff;border:none;border-radius:10px;padding:11px 22px;font-size:15px;font-weight:600;cursor:pointer',
        warning:  'background:#ffc107;color:#333;border:none;border-radius:10px;padding:11px 22px;font-size:15px;font-weight:600;cursor:pointer',
        danger:   'background:#dc3545;color:#fff;border:none;border-radius:10px;padding:11px 22px;font-size:15px;font-weight:600;cursor:pointer',
        secondary:'background:#6c757d;color:#fff;border:none;border-radius:10px;padding:9px 18px;font-size:13px;cursor:pointer',
      };
      var btn = E('button', { style: styles[style] || styles.primary }, label);
      btn.addEventListener('click', onclick);
      return btn;
    }

    // helper: виконати команду + показати спінер + оновити
    function runCmd(args, loadingText) {
      var spinnerEl = document.getElementById('warp-spinner');
      if (spinnerEl) spinnerEl.style.display = 'block';
      return fs.exec('/usr/bin/warp-api.sh', args).then(function(r) {
        if (spinnerEl) spinnerEl.style.display = 'none';
        var out = (r.stdout || r.stderr || '').trim();
        if (out) ui.addNotification(null, E('pre', { style:'white-space:pre-wrap;font-size:13px' }, out), 'info');
        window.location.reload();
      }).catch(function(e) {
        if (spinnerEl) spinnerEl.style.display = 'none';
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    }

    if (state === 'disconnected') {
      // Єдина дія — підключити і одразу увімкнути PBR
      btnRow.appendChild(mkBtn('⚡ Підключити та увімкнути', 'primary', function() {
        var sp = document.getElementById('warp-spinner');
        if (sp) sp.style.display = 'block';
        var info = document.getElementById('warp-action-info');
        if (info) info.textContent = 'Реєстрація у Cloudflare... (~10с)';
        fs.exec('/usr/bin/warp-api.sh', ['connect']).then(function(r) {
          var out = (r.stdout || r.stderr || '').trim();
          if (info) info.textContent = 'Підключено! Активую маршрутизацію...';
          // Одразу вмикаємо PBR
          return fs.exec('/usr/bin/warp-api.sh', ['mode_pbr']);
        }).then(function() {
          if (sp) sp.style.display = 'none';
          window.location.reload();
        }).catch(function(e) {
          if (sp) sp.style.display = 'none';
          ui.addNotification(null, E('p', String(e)), 'danger');
        });
      }));
    } else if (state === 'no_handshake') {
      btnRow.appendChild(mkBtn('🔄 Перезапустити', 'warning', function() {
        runCmd(['connect']);
      }));
      btnRow.appendChild(mkBtn('📏 Підібрати MTU', 'secondary', function() {
        runCmd(['mtu']);
      }));
    } else if (state === 'pbr') {
      // Активний PBR — пропонуємо переключити або зупинити
      btnRow.appendChild(mkBtn('🌐 Весь трафік через WARP', 'primary', function() {
        runCmd(['mode_all']);
      }));
      btnRow.appendChild(mkBtn('⏸ Зупинити WARP', 'danger', function() {
        runCmd(['mode_stop']);
      }));
    } else if (state === 'all') {
      // Весь трафік — пропонуємо переключити на PBR або зупинити
      btnRow.appendChild(mkBtn('✅ Тільки список (PBR)', 'success', function() {
        runCmd(['mode_pbr']);
      }));
      btnRow.appendChild(mkBtn('⏸ Зупинити WARP', 'danger', function() {
        runCmd(['mode_stop']);
      }));
    } else if (state === 'stopped') {
      // Зупинено — пропонуємо увімкнути
      btnRow.appendChild(mkBtn('✅ Увімкнути (тільки список)', 'success', function() {
        runCmd(['mode_pbr']);
      }));
      btnRow.appendChild(mkBtn('🌐 Увімкнути (весь трафік)', 'primary', function() {
        runCmd(['mode_all']);
      }));
    }

    mainCard.appendChild(btnRow);

    // ─── Спінер + info рядок ──────────────────────────────────────────────
    var spinner = E('div', {
      id: 'warp-spinner',
      style: 'display:none;text-align:center;padding:8px;font-size:13px;color:#555'
    }, '⏳ Виконую, зачекайте...');
    mainCard.appendChild(spinner);
    var actionInfo = E('div', { id: 'warp-action-info', style: 'font-size:12px;color:#777;margin-top:4px;min-height:16px' }, '');
    mainCard.appendChild(actionInfo);

    root.appendChild(mainCard);

    // ─── Режим PBR: список сайтів ─────────────────────────────────────────
    var listSection = E('div', {
      style: 'background:#fff;border:1px solid #ddd;border-radius:12px;padding:18px 20px;margin-bottom:14px'
    });
    listSection.appendChild(E('div', { style: 'font-weight:700;font-size:15px;margin-bottom:4px' }, '📋 Список сайтів через WARP'));
    listSection.appendChild(E('div', { style: 'font-size:12px;color:#666;margin-bottom:12px' }, 'Тільки ці IP / домени йдуть через WARP. Решта — напряму.'));

    // Textarea зі списком
    var textarea = E('textarea', {
      id: 'warp-blocklist',
      style: 'width:100%;height:120px;font-family:monospace;font-size:12px;border:1px solid #ccc;border-radius:6px;padding:8px;box-sizing:border-box',
      placeholder: 'Напр: 93.184.216.34\n5.188.86.0/24'
    });
    fs.trimmed('/etc/warp/blocked.list').then(function(val) {
      textarea.value = val || '';
    });
    listSection.appendChild(textarea);

    var listBtns = E('div', { style: 'display:flex;gap:8px;margin-top:10px;flex-wrap:wrap' });

    // Зберегти список і одразу застосувати
    var saveBtn = E('button', {
      style: 'background:#28a745;color:#fff;border:none;border-radius:8px;padding:8px 18px;font-size:13px;font-weight:600;cursor:pointer'
    }, '💾 Зберегти та застосувати');
    saveBtn.addEventListener('click', function() {
      var val = textarea.value.trim();
      fs.write('/etc/warp/blocked.list', val + '\n').then(function() {
        return fs.exec('/usr/bin/warp-api.sh', ['pbr_apply']);
      }).then(function(r) {
        var out = (r.stdout || r.stderr || '').trim();
        ui.addNotification(null, E('pre', { style:'font-size:13px' }, out || 'Застосовано'), 'info');
      }).catch(function(e) {
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    });
    listBtns.appendChild(saveBtn);

    // Оновити з GitHub
    var updBtn = E('button', {
      style: 'background:#6c757d;color:#fff;border:none;border-radius:8px;padding:8px 14px;font-size:13px;cursor:pointer'
    }, '⬇️ Оновити з GitHub');
    updBtn.addEventListener('click', function() {
      updBtn.disabled = true;
      updBtn.textContent = '⏳ ...';
      fs.exec('/usr/bin/warp-api.sh', ['pbr_update']).then(function(r) {
        updBtn.disabled = false;
        updBtn.textContent = '⬇️ Оновити з GitHub';
        var out = (r.stdout || r.stderr || '').trim();
        ui.addNotification(null, E('pre', { style:'font-size:13px' }, out), 'info');
        fs.trimmed('/etc/warp/blocked.list').then(function(val) { textarea.value = val || ''; });
      }).catch(function(e) {
        updBtn.disabled = false;
        updBtn.textContent = '⬇️ Оновити з GitHub';
        ui.addNotification(null, E('p', String(e)), 'danger');
      });
    });
    listBtns.appendChild(updBtn);

    listSection.appendChild(listBtns);
    root.appendChild(listSection);

    // ─── Секція «Додатково» (схована) ────────────────────────────────────
    var advToggle = E('details', { style: 'margin-bottom:14px' });
    var advSum = E('summary', {
      style: 'cursor:pointer;font-size:13px;color:#555;padding:6px 10px;background:#f5f5f5;border-radius:8px;user-select:none'
    }, '⚙️ Додатково (MTU, Endpoint, Ping, Видалити)');
    advToggle.appendChild(advSum);

    var advBody = E('div', { style: 'padding:14px 4px 4px;display:flex;flex-direction:column;gap:10px' });

    function advBtn(label, args, dangerous) {
      var btn = E('button', {
        style: [
          dangerous ? 'background:#dc3545;color:#fff' : 'background:#f0f0f0;color:#333',
          'border:none;border-radius:8px;padding:9px 16px;font-size:13px;cursor:pointer;text-align:left;width:100%'
        ].join(';')
      }, label);
      var resultEl = E('pre', { style: 'margin:4px 0 0;font-size:11px;white-space:pre-wrap;color:#333;background:#f8f8f8;border-radius:6px;padding:6px;display:none' });
      btn.addEventListener('click', function() {
        btn.disabled = true;
        var origText = btn.textContent;
        btn.textContent = '⏳ ...';
        fs.exec('/usr/bin/warp-api.sh', args).then(function(r) {
          btn.disabled = false;
          btn.textContent = origText;
          var out = (r.stdout || r.stderr || '').trim();
          if (out) { resultEl.textContent = out; resultEl.style.display = 'block'; }
          if (args[0] === 'delete' || args[0] === 'connect') window.location.reload();
        }).catch(function(e) {
          btn.disabled = false;
          btn.textContent = origText;
          resultEl.textContent = String(e);
          resultEl.style.display = 'block';
        });
      });
      var wrap = E('div');
      wrap.appendChild(btn);
      wrap.appendChild(resultEl);
      return wrap;
    }

    advBody.appendChild(advBtn('📏 Підібрати MTU автоматично (~30с)', ['mtu']));
    advBody.appendChild(advBtn('📋 Показати лог MTU', ['mtu_result']));
    advBody.appendChild(advBtn('🌍 Знайти найшвидший Cloudflare endpoint (~20с)', ['best_endpoint']));
    advBody.appendChild(advBtn('📋 Показати лог Endpoint', ['endpoint_result']));
    advBody.appendChild(advBtn('📡 Пінг Cloudflare', ['ping']));
    advBody.appendChild(E('hr', { style: 'border:none;border-top:1px solid #eee;margin:6px 0' }));
    advBody.appendChild(advBtn('🗑 Видалити WARP повністю', ['delete'], true));

    advToggle.appendChild(advBody);
    root.appendChild(advToggle);

    // ─── Сирий статус (схований) ───────────────────────────────────────────
    if (status && status.trim()) {
      var rawToggle = E('details', { style: 'margin-bottom:4px' });
      rawToggle.appendChild(E('summary', {
        style: 'cursor:pointer;font-size:12px;color:#aaa;padding:4px 10px;user-select:none'
      }, 'Сирий статус'));
      rawToggle.appendChild(E('pre', {
        style: 'font-size:11px;white-space:pre-wrap;background:#f5f5f5;padding:8px;border-radius:6px;margin-top:4px'
      }, status.trim()));
      root.appendChild(rawToggle);
    }

    return root;
  }
});
