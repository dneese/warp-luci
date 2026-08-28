#!/bin/sh
# warp-service installer — без бота, только веб-страничка WARP
# Запуск на роутере: sh install.sh
SRC="$(cd "$(dirname "$0")" && pwd)"
DIR="/www/luci-static/resources/view/warp"
echo "== WARP Service installer =="
mkdir -p /usr/bin /etc/tg-bot /www/luci-static/resources/view/warp /usr/share/luci/menu.d /usr/share/rpcd/acl.d
cp "$SRC/files/usr/bin/warp-api.sh" /usr/bin/warp-api.sh && chmod +x /usr/bin/warp-api.sh
cp "$SRC/files/www/luci-static/resources/view/warp/overview.js" /www/luci-static/resources/view/warp/overview.js
chmod 644 /www/luci-static/resources/view/warp/overview.js 2>/dev/null
chmod 755 /www/luci-static/resources/view/warp 2>/dev/null
# LuCI menu
mkdir -p /usr/share/luci/menu.d
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
touch /etc/config/warp 2>/dev/null
rm -f /tmp/luci-* 2>/dev/null
mkdir -p /usr/share/rpcd/acl.d
cat > /usr/share/rpcd/acl.d/luci-app-warp.json <<'EOF'
{
  "luci-app-warp": {
    "description": "WARP Service",
    "read": { "uci": ["warp"], "file": { "/usr/bin/warp-api.sh": ["exec"] } },
    "write": { "uci": ["warp"], "file": { "/etc/tg-bot/blocked.list": ["read","write"] } }
  }
}
EOF
# ACL + menu
chmod 644 /usr/share/luci/menu.d/luci-app-warp.json /usr/share/rpcd/acl.d/luci-app-warp.json 2>/dev/null
/etc/init.d/rpcd restart 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null
echo "Готово: LuCI → Services → WARP"
echo "Команды: warp-api.sh status|connect|delete|mode_all|mode_stop|pbr_list|mtu|ping"
# проверка
warp-api.sh status 2>&1 | head -n 20
