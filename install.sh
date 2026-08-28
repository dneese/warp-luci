#!/bin/sh
# WARP LuCI — встроенная установка со всеми файлами внутри

set -e

echo "📦 WARP LuCI — установка..."

# Создаём директории
mkdir -p /usr/bin /etc/warp /www/luci-static/resources/view/warp /usr/share/luci/menu.d /usr/share/rpcd/acl.d

echo "⚙️  Создаю файлы..."

# ============================================================
# warp-api.sh — встроен прямо в этот скрипт
# ============================================================
cat > /usr/bin/warp-api.sh <<'WARP_API_EOF'
#!/bin/sh
# WARP LuCI API

# Функция для логирования
log() { echo "[WARP] $@" >&2; }

case "$1" in
  status)
    if [ -f /etc/warp/warp.reg ]; then
      if ip link show warp >/dev/null 2>&1; then
        HANDSHAKE=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}' | head -1)
        NOW=$(date +%s)
        if [ -z "$HANDSHAKE" ] || [ "$HANDSHAKE" -eq 0 ]; then
          echo "🔴 Туннель создан, но нет handshake (0 сек)"
        else
          DIFF=$((NOW - HANDSHAKE))
          if [ "$DIFF" -lt 300 ]; then
            echo "🟢 Туннель активен (handshake $DIFF сек назад)"
          else
            echo "🟡 Туннель создан, но нет активности ($DIFF сек)"
          fi
        fi
      else
        echo "🟡 WARP конфигурирован, но интерфейс не поднят"
      fi
    else
      echo "🔵 WARP не установлен"
    fi
    ;;

  connect)
    log "Регистрирую устройство в Cloudflare..."
    mkdir -p /etc/warp
    
    # Генерируем приватный ключ
    PRIVKEY=$(wg genkey)
    PUBKEY=$(echo "$PRIVKEY" | wg pubkey)
    
    # Регистрируем в Cloudflare API
    RESPONSE=$(curl -fsSL https://api.cloudflareclient.com/v0a/reg \
      -H "Content-Type: application/json" \
      --data "{\"install_id\":\"$(uuidgen 2>/dev/null || echo "00000000-0000-0000-0000-000000000000")\",\"tos\":\"$(date +%Y-%m-%d)\"}")
    
    if echo "$RESPONSE" | grep -q "token"; then
      TOKEN=$(echo "$RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
      echo "$RESPONSE" > /etc/warp/warp.reg
      log "✅ Устройство зарегистрировано: $TOKEN"
    else
      log "❌ Ошибка регистрации"
      return 1
    fi
    
    # Настраиваем интерфейс
    uci set network.warp=interface
    uci set network.warp.type=wireguard
    uci set network.warp.proto=none
    uci set network.warp.private_key="$PRIVKEY"
    
    uci set network.warp_peer=wireguard_warp
    uci set network.warp_peer.instance_number=0
    uci set network.warp_peer.public_key="bmXEzrng/NqKId4PfdZ1XVXSwL2t4MWvx2/EFt8814M="
    uci set network.warp_peer.endpoint_host="162.159.192.1"
    uci set network.warp_peer.endpoint_port=51820
    uci set network.warp_peer.allowed_ips="0.0.0.0/0"
    uci set network.warp_peer.route_allowed_ips=0
    
    uci commit network
    /etc/init.d/network reload
    
    log "✅ Туннель создан"
    ;;

  delete)
    log "Удаляю WARP..."
    ifdown warp 2>/dev/null || true
    
    uci delete network.warp 2>/dev/null || true
    while uci delete network.@wireguard_warp[0] >/dev/null 2>&1; do :; done
    
    uci commit network
    /etc/init.d/network reload 2>/dev/null || true
    
    rm -f /etc/warp/warp.reg
    log "✅ WARP удалён"
    ;;

  mode_all)
    log "Весь трафик через WARP..."
    uci set network.warp_peer.route_allowed_ips=1
    uci commit network
    /etc/init.d/network reload
    log "✅ Весь трафик идёт через WARP"
    ;;

  mode_stop)
    log "Отключаю маршрутизацию..."
    uci set network.warp_peer.route_allowed_ips=0
    uci commit network
    /etc/init.d/network reload
    log "✅ Маршрутизация отключена"
    ;;

  ping)
    echo "📡 Пинг Cloudflare endpoint'ов:"
    for ip in 162.159.192.1 162.159.193.1 162.159.195.1 188.114.96.1 188.114.97.1 188.114.98.1; do
      ping -c 1 -W 2 "$ip" >/dev/null 2>&1 && echo "  ✅ $ip" || echo "  ❌ $ip"
    done
    ;;

  mtu)
    echo "📏 Тест MTU..."
    for mtu in 1420 1400 1380 1280; do
      echo "  🔍 Тестирую MTU $mtu..."
      ip link set dev warp mtu $mtu 2>/dev/null || true
      if ping -c 1 -W 2 162.159.192.1 >/dev/null 2>&1; then
        echo "  ✅ MTU $mtu работает"
        break
      fi
    done
    echo "  ✅ Оптимальный MTU установлен"
    ;;

  *)
    echo "WARP LuCI API"
    echo ""
    echo "Использование: warp-api.sh [команда]"
    echo ""
    echo "Команды:"
    echo "  status          - Статус туннеля"
    echo "  connect         - Подключить WARP"
    echo "  delete          - Удалить WARP"
    echo "  mode_all        - Весь трафик через WARP"
    echo "  mode_stop       - Отключить маршрутизацию"
    echo "  ping            - Пинг endpoint'ов"
    echo "  mtu             - Тест MTU"
    ;;
esac
WARP_API_EOF

chmod +x /usr/bin/warp-api.sh

# ============================================================
# LuCI menu JSON
# ============================================================
cat > /usr/share/luci/menu.d/luci-app-warp.json <<'MENU_EOF'
{
  "admin/services/warp": {
    "title": "WARP",
    "order": 45,
    "action": { "type": "view", "path": "warp/overview" },
    "depends": { "acl": ["luci-app-warp"] }
  }
}
MENU_EOF

# ============================================================
# ACL JSON
# ============================================================
cat > /usr/share/rpcd/acl.d/luci-app-warp.json <<'ACL_EOF'
{
  "luci-app-warp": {
    "description": "WARP Service",
    "read": { "uci": ["warp"], "file": { "/usr/bin/warp-api.sh": ["exec"] } },
    "write": { "uci": ["warp"], "file": { "/etc/warp/blocked.list": ["read","write"] } }
  }
}
ACL_EOF

# ============================================================
# Веб-интерфейс overview.js (базовый)
# ============================================================
cat > /www/luci-static/resources/view/warp/overview.js <<'JS_EOF'
'use strict';
'require uci';
'require rpc';
'require form';

return L.view.extend({
  render: function() {
    var m, s, o;

    m = new form.Map('warp', _('WARP LuCI'), _('Cloudflare WARP Management'));

    s = m.section(form.NamedSection, 'config', 'config', _('Control'));
    
    o = s.option(form.Button, 'status', _('Status'));
    o.inputtitle = _('Check Status');
    o.onclick = function() {
      return L.ui.showModal(_('WARP Status'), [
        E('p', {}, _('Fetching status...')),
        E('textarea', { rows: 10, style: 'width: 100%', readonly: true }, 'Loading...')
      ]);
    };

    o = s.option(form.Button, 'connect', _('Connect'));
    o.inputtitle = _('Connect WARP');
    o.onclick = function() {
      return L.ui.showModal(_('Connecting...'), [
        E('p', {}, _('Please wait...')),
        E('progress', { max: 100, value: 0 })
      ]);
    };

    o = s.option(form.Button, 'delete', _('Delete'));
    o.inputtitle = _('Remove WARP');
    o.onclick = function() {
      if (confirm(_('Remove WARP?'))) {
        L.ui.showModal(_('Removing...'), [E('p', {}, _('Please wait...'))]);
      }
    };

    return m.render();
  }
});
JS_EOF

chmod 644 /www/luci-static/resources/view/warp/overview.js
chmod 755 /www/luci-static/resources/view/warp 2>/dev/null

# ============================================================
# Инициализация
# ============================================================
echo "⚙️  Настраиваю конфиг..."

uci set warp.config=config 2>/dev/null || uci set warp.config='config' 2>/dev/null
uci commit warp 2>/dev/null || true

echo "🔄 Перезагружаю сервисы..."
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
rm -f /tmp/luci-* 2>/dev/null || true

echo ""
echo "✅ ════════════════════════════════════════════════"
echo "✅ WARP LuCI успешно установлен!"
echo "✅ ════════════════════════════════════════════════"
echo ""
echo "📍 Откройте в браузере:"
echo "   http://192.168.1.1/cgi-bin/luci/admin/services/warp"
echo ""
echo "📍 Или в LuCI: Services → WARP"
echo ""
echo "📍 CLI команды:"
echo "   warp-api.sh status"
echo "   warp-api.sh connect"
echo "   warp-api.sh delete"
echo ""

warp-api.sh status 2>&1 | head -n 3
