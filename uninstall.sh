#!/bin/sh
# WARP LuCI — полное удаление

echo "🗑️  Удаляю WARP LuCI..."

# Удаляем файлы
rm -f /usr/bin/warp-api.sh
rm -rf /www/luci-static/resources/view/warp
rm -f /usr/share/luci/menu.d/luci-app-warp.json
rm -f /usr/share/rpcd/acl.d/luci-app-warp.json
rm -rf /etc/warp

# Удаляем туннель если был создан
if uci -q get network.warp >/dev/null 2>&1; then
  echo "🔌 Отключаю туннель..."
  ifdown warp 2>/dev/null
  while uci -q delete network.@wireguard_warp[0] >/dev/null 2>&1; do :; done
  uci -q delete network.warp 2>/dev/null
  
  # Удаляем forwarding lan->warp
  N=$(uci show firewall | grep -c '=forwarding')
  i=$((N-1)); while [ "$i" -ge 0 ]; do
    FS=$(uci -q get firewall.@forwarding[$i].src 2>/dev/null)
    FD=$(uci -q get firewall.@forwarding[$i].dest 2>/dev/null)
    [ "$FS" = "lan" ] && [ "$FD" = "warp" ] && uci -q delete firewall.@forwarding[$i] 2>/dev/null
    i=$((i-1))
  done
  
  # Удаляем firewall zone
  Z=$(uci show firewall | grep -c '=zone')
  i=$((Z-1)); while [ "$i" -ge 0 ]; do
    [ "$(uci -q get firewall.@zone[$i].name 2>/dev/null)" = "warp" ] && uci -q delete firewall.@zone[$i] 2>/dev/null
    i=$((i-1))
  done
  
  uci commit network
  uci commit firewall
  /etc/init.d/network reload 2>/dev/null
fi

# Перезагружаем сервисы
/etc/init.d/rpcd restart 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null
rm -f /tmp/luci-* 2>/dev/null

echo "✅ WARP LuCI полностью удален"
echo "🔄 Перезагрузите браузер"
