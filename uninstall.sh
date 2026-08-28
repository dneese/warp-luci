#!/bin/sh
# WARP LuCI — полное удаление

echo "🗑️  Удаляю WARP LuCI..."

# Отключаем туннель если был создан
if uci -q get network.warp >/dev/null 2>&1; then
  echo "🔌 Отключаю туннель..."
  ifdown warp 2>/dev/null || true
  
  # Удаляем wireguard peers
  while uci -q delete network.@wireguard_warp[0] >/dev/null 2>&1; do :; done
  
  # Удаляем интерфейс
  uci -q delete network.warp 2>/dev/null || true
  
  # Удаляем firewall forwarding lan->warp
  uci show firewall 2>/dev/null | grep -q "forwarding" && {
    N=$(uci show firewall | grep -c '=forwarding')
    i=$((N-1))
    while [ "$i" -ge 0 ]; do
      FS=$(uci -q get firewall.@forwarding[$i].src 2>/dev/null)
      FD=$(uci -q get firewall.@forwarding[$i].dest 2>/dev/null)
      [ "$FS" = "lan" ] && [ "$FD" = "warp" ] && uci -q delete firewall.@forwarding[$i] 2>/dev/null || true
      i=$((i-1))
    done
  }
  
  # Удаляем firewall zone warp
  uci show firewall 2>/dev/null | grep -q "zone" && {
    Z=$(uci show firewall | grep -c '=zone')
    i=$((Z-1))
    while [ "$i" -ge 0 ]; do
      [ "$(uci -q get firewall.@zone[$i].name 2>/dev/null)" = "warp" ] && uci -q delete firewall.@zone[$i] 2>/dev/null || true
      i=$((i-1))
    done
  }
  
  uci commit network 2>/dev/null || true
  uci commit firewall 2>/dev/null || true
  /etc/init.d/network reload 2>/dev/null || true
fi

# Удаляем конфиг UCI
uci -q delete warp.config 2>/dev/null || true
uci commit warp 2>/dev/null || true

# Удаляем файлы приложения
echo "📂 Удаляю файлы..."
rm -f /usr/bin/warp-api.sh 2>/dev/null || true
rm -rf /www/luci-static/resources/view/warp 2>/dev/null || true
rm -f /usr/share/luci/menu.d/luci-app-warp.json 2>/dev/null || true
rm -f /usr/share/rpcd/acl.d/luci-app-warp.json 2>/dev/null || true
rm -rf /etc/warp 2>/dev/null || true

# Перезагружаем сервисы
echo "🔄 Перезагружаю сервисы..."
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
rm -f /tmp/luci-* 2>/dev/null || true

echo ""
echo "✅ ════════════════════════════════════════"
echo "✅ WARP LuCI полностью удален"
echo "✅ ════════════════════════════════════════"
echo "🔄 Обновите браузер (Ctrl+Shift+Del)"
