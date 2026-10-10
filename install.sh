#!/bin/sh
# WARP LuCI — классическая установка.
#
# Исторически этот скрипт встраивал warp-api.sh прямо в себя (heredoc),
# из-за чего со временем разошёлся с files/usr/bin/warp-api.sh и получил
# те же баги, что и «весь трафик» (route_allowed_ips=1 → петля маршрутизации).
#
# Теперь обе установки используют ОДИН источник правды — файлы в репозитории.

set -e

echo "📦 WARP LuCI — установка..."

REPO="dneese/warp-luci"
BRANCH="main"
BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"

mkdir -p /usr/bin /etc/warp /etc/hotplug.d/iface \
         /www/luci-static/resources/view/warp \
         /usr/share/luci/menu.d /usr/share/rpcd/acl.d

# ───────────────────────── загрузка файлов ─────────────────────────
# fetch <URL> <dst> <обязательный минимум байт>
fetch() {
  URL="$1"; DST="$2"; MINSZ="$3"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time 30 "$URL" -o "$DST" 2>/dev/null && :
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 30 -O "$DST" "$URL" 2>/dev/null && :
  elif command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -q -T 30 -O "$DST" "$URL" 2>/dev/null && :
  else
    echo "❌ Нет curl/wget/uclient-fetch — установите один из них" >&2
    return 1
  fi
  # Проверка: файл существует, не пустой и достаточно большой.
  # Без этого обрезанный/битый файл молча перезапишет рабочую версию.
  if [ ! -s "$DST" ] || [ "$(wc -c < "$DST")" -lt "$MINSZ" ]; then
    echo "❌ Загрузка не удалась или файл слишком мал: $URL" >&2
    rm -f "$DST"
    return 1
  fi
  return 0
}

echo "⬇️  Загружаю warp-api.sh..."
fetch "$BASE/files/usr/bin/warp-api.sh" /usr/bin/warp-api.sh 5000 || exit 1
chmod 755 /usr/bin/warp-api.sh

echo "⬇️  Загружаю hotplug (автовосстановление после перезагрузки)..."
fetch "$BASE/files/etc/hotplug.d/iface/30-warp-pbr" /etc/hotplug.d/iface/30-warp-pbr 500 || exit 1
chmod 755 /etc/hotplug.d/iface/30-warp-pbr

echo "⬇️  Загружаю overview.js..."
fetch "$BASE/files/www/luci-static/resources/view/warp/overview.js" \
      /www/luci-static/resources/view/warp/overview.js 1000 || exit 1
chmod 644 /www/luci-static/resources/view/warp/overview.js 2>/dev/null
chmod 755 /www/luci-static/resources/view/warp 2>/dev/null

echo "🔍 Проверяю скрипты..."
sh -n /usr/bin/warp-api.sh || { echo "❌ warp-api.sh: синтаксическая ошибка"; exit 1; }
sh -n /etc/hotplug.d/iface/30-warp-pbr || { echo "❌ hotplug: синтаксическая ошибка"; exit 1; }

# ───────────────────────── LuCI меню / ACL ─────────────────────────
echo "⚙️  Настраиваю LuCI меню..."
cat > /usr/share/luci/menu.d/luci-app-warp.json <<'EOF'
{
  "admin/services/warp": {
    "title": "WARP",
    "order": 45,
    "action": { "type": "view", "path": "warp/overview" },
    "depends": { "acl": ["luci-app-warp"] }
  }
}
EOF

echo "⚙️  Настраиваю ACL..."
cat > /usr/share/rpcd/acl.d/luci-app-warp.json <<'EOF'
{
  "luci-app-warp": {
    "description": "WARP Service",
    "read": { "uci": ["warp"], "file": { "/usr/bin/warp-api.sh": ["exec"] } },
    "write": { "uci": ["warp"], "file": { "/etc/warp/blocked.list": ["read","write"] } }
  }
}
EOF

chmod 644 /usr/share/luci/menu.d/luci-app-warp.json /usr/share/rpcd/acl.d/luci-app-warp.json 2>/dev/null

# ───────────────────────── инициализация ─────────────────────────
echo "⚙️  Инициализирую конфиг..."
uci set warp.config=config 2>/dev/null || true
uci commit warp 2>/dev/null || true

# Активный режим хранится здесь и восстанавливается hotplug-скриптом
if [ ! -f /etc/warp/.mode ]; then
  echo "list" > /etc/warp/.mode
fi

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
echo "   http://$(uci -q get network.lan.ipaddr || echo 192.168.1.1)/cgi-bin/luci/admin/services/warp"
echo ""
echo "📍 Или в LuCI: Services → WARP"
echo ""
echo "📍 CLI команды:"
echo "   warp-api.sh status      — текущий режим и состояние туннеля"
echo "   warp-api.sh verify      — полная диагностика маршрутов"
echo "   warp-api.sh connect     — подключить WARP"
echo "   warp-api.sh mode_all    — весь трафик через WARP"
echo "   warp-api.sh mode_pbr    — только список IP"
echo ""

set +e
warp-api.sh status 2>&1 | head -n 5