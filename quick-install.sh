#!/bin/sh
# WARP LuCI — однострочная установка прямо на роутере

set -e

echo "📦 WARP LuCI — установка..."

# Скачиваем файлы напрямую с GitHub
DIR="/tmp/warp-luci-install"
mkdir -p "$DIR"

echo "⬇️  Скачиваем файлы..."

# Скачиваем install.sh
curl -fsSL https://raw.githubusercontent.com/dneese/warp-luci/main/install.sh -o "$DIR/install.sh" 2>/dev/null || \
  wget -q -O "$DIR/install.sh" https://raw.githubusercontent.com/dneese/warp-luci/main/install.sh 2>/dev/null || \
  uclient-fetch -q -O "$DIR/install.sh" https://raw.githubusercontent.com/dneese/warp-luci/main/install.sh 2>/dev/null

# Скачиваем warp-api.sh
mkdir -p "$DIR/files/usr/bin"
curl -fsSL https://raw.githubusercontent.com/dneese/warp-luci/main/files/usr/bin/warp-api.sh -o "$DIR/files/usr/bin/warp-api.sh" 2>/dev/null || \
  wget -q -O "$DIR/files/usr/bin/warp-api.sh" https://raw.githubusercontent.com/dneese/warp-luci/main/files/usr/bin/warp-api.sh 2>/dev/null || \
  uclient-fetch -q -O "$DIR/files/usr/bin/warp-api.sh" https://raw.githubusercontent.com/dneese/warp-luci/main/files/usr/bin/warp-api.sh 2>/dev/null

# Скачиваем overview.js
mkdir -p "$DIR/files/www/luci-static/resources/view/warp"
curl -fsSL https://raw.githubusercontent.com/dneese/warp-luci/main/files/www/luci-static/resources/view/warp/overview.js -o "$DIR/files/www/luci-static/resources/view/warp/overview.js" 2>/dev/null || \
  wget -q -O "$DIR/files/www/luci-static/resources/view/warp/overview.js" https://raw.githubusercontent.com/dneese/warp-luci/main/files/www/luci-static/resources/view/warp/overview.js 2>/dev/null || \
  uclient-fetch -q -O "$DIR/files/www/luci-static/resources/view/warp/overview.js" https://raw.githubusercontent.com/dneese/warp-luci/main/files/www/luci-static/resources/view/warp/overview.js 2>/dev/null

echo "✅ Файлы скачаны"

# Запускаем установку
cd "$DIR"
chmod +x install.sh
sh install.sh

echo "🎉 Готово!"
echo "Откройте в браузере: http://192.168.1.1/cgi-bin/luci/admin/services/warp"
echo "или перейдите в LuCI → Services → WARP"
