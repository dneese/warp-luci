#!/bin/sh
# WARP LuCI — вбудована однорядкова установка прямо на роутері

set -e

REPO="dneese/warp-luci"
BRANCH="main"
BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"

echo "📦 WARP LuCI — установка..."

mkdir -p /usr/bin /etc/warp /etc/hotplug.d/iface \
         /www/luci-static/resources/view/warp \
         /usr/share/luci/menu.d /usr/share/rpcd/acl.d

# ───────────────────────── завантаження файлів ─────────────────────────
# fetch <URL> <dst> <обов'язковий_мінімум_байт>
fetch() {
  URL="$1"; DST="$2"; MINSZ="$3"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time 30 "$URL" -o "$DST" 2>/dev/null && :
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 30 -O "$DST" "$URL" 2>/dev/null && :
  elif command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -q -T 30 -O "$DST" "$URL" 2>/dev/null && :
  else
    echo "❌ Немає curl/wget/uclient-fetch — встановіть один із них" >&2
    return 1
  fi
  # Перевірка: файл існує, не порожній і має хоча б $MINSZ байт.
  # Без цього truncated/битий файл непомітно перезапише робочу версію.
  if [ ! -s "$DST" ] || [ "$(wc -c < "$DST")" -lt "$MINSZ" ]; then
    echo "❌ Завантаження невдале або файл замалий: $URL" >&2
    rm -f "$DST"
    return 1
  fi
  return 0
}

echo "⬇️  Завантажуємо warp-api.sh..."
fetch "$BASE/files/usr/bin/warp-api.sh" /usr/bin/warp-api.sh 5000 || exit 1
chmod 755 /usr/bin/warp-api.sh

echo "⬇️  Завантажуємо hotplug (автовосстановлення після ребуту)..."
fetch "$BASE/files/etc/hotplug.d/iface/30-warp-pbr" /etc/hotplug.d/iface/30-warp-pbr 500 || exit 1
chmod 755 /etc/hotplug.d/iface/30-warp-pbr

echo "⬇️  Завантажуємо overview.js..."
fetch "$BASE/files/www/luci-static/resources/view/warp/overview.js" \
      /www/luci-static/resources/view/warp/overview.js 1000 || exit 1
chmod 644 /www/luci-static/resources/view/warp/overview.js 2>/dev/null
chmod 755 /www/luci-static/resources/view/warp 2>/dev/null

# ───────────────────────── перевірка синтаксису ─────────────────────────
echo "🔍 Перевіряємо скрипти..."
sh -n /usr/bin/warp-api.sh || { echo "❌ warp-api.sh: синтаксична помилка"; exit 1; }
sh -n /etc/hotplug.d/iface/30-warp-pbr || { echo "❌ hotplug: синтаксична помилка"; exit 1; }

# ───────────────────────── LuCI меню / ACL ─────────────────────────
echo "⚙️  Налаштовуємо LuCI меню..."
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

echo "⚙️  Налаштовуємо ACL..."
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

# ───────────────────────── ініціалізація ─────────────────────────
echo "⚙️  Ініціалізуємо конфіг..."
uci set warp.config=config 2>/dev/null || true
uci commit warp 2>/dev/null || true

# Активний режим зберігається тут і відновлюється hotplug-скриптом
if [ ! -f /etc/warp/.mode ]; then
  # ставимо типовий режим — список (безпечніше за весь трафік)
  echo "list" > /etc/warp/.mode
fi

echo "🔄 Перезавантажуємо сервіси..."
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
rm -f /tmp/luci-* 2>/dev/null || true

echo ""
echo "✅ ════════════════════════════════════════════════"
echo "✅ WARP LuCI успішно встановлено!"
echo "✅ ════════════════════════════════════════════════"
echo ""
echo "📍 Відкрийте в браузері:"
echo "   http://$(uci -q get network.lan.ipaddr || echo 192.168.1.1)/cgi-bin/luci/admin/services/warp"
echo ""
echo "📍 Або в LuCI: Services → WARP"
echo ""
echo "📍 CLI команди:"
echo "   warp-api.sh status      — поточний режим і стан тунелю"
echo "   warp-api.sh verify      — повна діагностика маршрутів"
echo "   warp-api.sh connect     — підключити WARP"
echo "   warp-api.sh mode_all    — весь трафік через WARP"
echo "   warp-api.sh mode_pbr    — тільки список IP"
echo ""

# set +e щоб status не зламав установку на свіжому роутері
set +e
warp-api.sh status 2>&1 | head -n 5