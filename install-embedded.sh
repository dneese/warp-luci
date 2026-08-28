#!/bin/sh
# WARP LuCI — вбудована однорядкова установка прямо на роутері

set -e

echo "📦 WARP LuCI — установка..."

# Створюємо директорії
mkdir -p /usr/bin /etc/warp /www/luci-static/resources/view/warp /usr/share/luci/menu.d /usr/share/rpcd/acl.d

echo "⬇️  Завантажуємо warp-api.sh..."
curl -fsSL https://raw.githubusercontent.com/dneese/warp-luci/main/files/usr/bin/warp-api.sh -o /usr/bin/warp-api.sh 2>/dev/null || \
  wget -q -O /usr/bin/warp-api.sh https://raw.githubusercontent.com/dneese/warp-luci/main/files/usr/bin/warp-api.sh 2>/dev/null || \
  uclient-fetch -q -O /usr/bin/warp-api.sh https://raw.githubusercontent.com/dneese/warp-luci/main/files/usr/bin/warp-api.sh
chmod +x /usr/bin/warp-api.sh

echo "⬇️  Завантажуємо overview.js..."
curl -fsSL https://raw.githubusercontent.com/dneese/warp-luci/main/files/www/luci-static/resources/view/warp/overview.js -o /www/luci-static/resources/view/warp/overview.js 2>/dev/null || \
  wget -q -O /www/luci-static/resources/view/warp/overview.js https://raw.githubusercontent.com/dneese/warp-luci/main/files/www/luci-static/resources/view/warp/overview.js 2>/dev/null || \
  uclient-fetch -q -O /www/luci-static/resources/view/warp/overview.js https://raw.githubusercontent.com/dneese/warp-luci/main/files/www/luci-static/resources/view/warp/overview.js
chmod 644 /www/luci-static/resources/view/warp/overview.js 2>/dev/null
chmod 755 /www/luci-static/resources/view/warp 2>/dev/null

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

echo "⚙️  Ініціалізуємо конфіг..."
uci set warp.config=config 2>/dev/null || true
uci commit warp 2>/dev/null || true

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
echo "   http://192.168.1.1/cgi-bin/luci/admin/services/warp"
echo ""
echo "📍 Або в LuCI: Services → WARP"
echo ""
echo "📍 CLI команди:"
echo "   warp-api.sh status"
echo "   warp-api.sh connect"
echo ""

# set +e щоб status не зламав установку на свіжому роутері
set +e
warp-api.sh status 2>&1 | head -n 3
