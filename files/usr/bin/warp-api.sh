#!/bin/sh
# warp-api.sh — бэкенд для LuCI Cloudflare WARP
# Вызов: warp-api.sh status|connect|delete|mode_all|mode_stop|pbr_list|pbr_add <IP>|pbr_del <N>|mtu|ping

DIR="/etc/warp"
WARP_REG="$DIR/warp.reg"
BLOCKED="$DIR/blocked.list"

warp_status() {
  if ! uci -q get network.warp >/dev/null 2>&1; then
    echo "📭 не налаштовано"
    return
  fi
  HS=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
  if [ -z "$HS" ] || [ "$HS" = "0" ]; then
    echo "🔴 Немає handshake"
  else
    echo "🟢 Тунель активний (hs=$HS)"
  fi
  # режим
  ALLOWED=$(uci -q get network.@wireguard_warp[0].route_allowed_ips 2>/dev/null)
  case "$ALLOWED" in
    "1"|"0.0.0.0/0"*) echo "режим: весь трафік через WARP" ;;
    "0") echo "режим: тунель є, трафік не перехоплюється" ;;
    *) echo "режим: PBR ($ALLOWED)" ;;
  esac
  ip addr show warp 2>/dev/null | grep -q "inet" && echo "warp: up" || echo "warp: down"
}

warp_connect() {
  # авто-регистрация через Cloudflare API
  command -v wg >/dev/null 2>&1 || { apk add wireguard-tools 2>/dev/null || opkg install wireguard-tools 2>/dev/null; }
  PRIV=$(wg genkey 2>/dev/null)
  PUB=$(echo "$PRIV" | wg pubkey 2>/dev/null)
  # Cloudflare API
  JSON=$(curl -s --max-time 10 -X POST https://api.cloudflareclient.com/v0a2158/reg -H "Content-Type: application/json" -d "{\"install_id\":\"\",\"tos\":\"$(date -u +%FT%T.000Z)\",\"key\":\"$PUB\",\"fcm_token\":\"\",\"type\":\"\",\"locale\":\"en-US\"}" 2>/dev/null)
  ID=$(echo "$JSON" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
  TOKEN=$(echo "$JSON" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  if [ -z "$ID" ]; then
    echo "❌ Реєстрація не вдалася (Cloudflare API)"
    echo "$JSON" | head -c 300
    return 1
  fi
  # конфиг warp
  mkdir -p "$DIR"
  umask 077; printf '%s\n%s\n%s\n' "$PRIV" "$ID" "$TOKEN" > "$WARP_REG"
  uci -q delete network.warp 2>/dev/null
  while uci -q delete network.@wireguard_warp[0] >/dev/null 2>&1; do :; done
  uci set network.warp=interface
  uci set network.warp.proto='wireguard'
  uci set network.warp.private_key="$PRIV"
  uci add_list network.warp.addresses="172.16.0.2/32"
  uci set network.warp.mtu='1280'
  uci add network wireguard_warp >/dev/null
  PEER=$(echo "$JSON" | grep -o '"public_key":"[^"]*"' | cut -d'"' -f4)
  [ -z "$PEER" ] && PEER="bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
  uci set network.@wireguard_warp[-1].public_key="$PEER"
  uci set network.@wireguard_warp[-1].endpoint_host='engage.cloudflareclient.com'
  uci set network.@wireguard_warp[-1].endpoint_port='2408'
  uci add_list network.@wireguard_warp[-1].allowed_ips='0.0.0.0/0'
  uci add_list network.@wireguard_warp[-1].allowed_ips='::/0'
  uci set network.@wireguard_warp[-1].persistent_keepalive='25'
  uci set network.@wireguard_warp[-1].route_allowed_ips='0'
  uci commit network
  # firewall zone warp
  if ! uci -q get firewall.warp >/dev/null 2>&1; then
    uci add firewall zone >/dev/null
    Z=$(uci show firewall | grep -c '=zone')
    Z=$((Z-1))
    uci set firewall.@zone[$Z].name='warp'
    uci set firewall.@zone[$Z].input='REJECT'
    uci set firewall.@zone[$Z].output='ACCEPT'
    uci set firewall.@zone[$Z].forward='REJECT'
    uci add_list firewall.@zone[$Z].network='warp'
    uci set firewall.@zone[$Z].masq='1'
    uci commit firewall
  fi
  ifup warp 2>/dev/null || /etc/init.d/network reload 2>/dev/null
  sleep 6
  HS=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
  if [ -n "$HS" ] && [ "$HS" != "0" ]; then
    echo "✅ WARP створено, handshake OK"
  else
    echo "⚠️ Тунель створено, але handshake поки 0 — спробуйте пізніше"
  fi
}

warp_delete() {
  ifdown warp 2>/dev/null
  while uci -q delete network.@wireguard_warp[0] >/dev/null 2>&1; do :; done
  uci -q delete network.warp 2>/dev/null
  # удалить forwarding lan->warp
  N=$(uci show firewall | grep -c '=forwarding')
  i=$((N-1)); while [ "$i" -ge 0 ]; do
    FS=$(uci -q get firewall.@forwarding[$i].src 2>/dev/null)
    FD=$(uci -q get firewall.@forwarding[$i].dest 2>/dev/null)
    [ "$FS" = "lan" ] && [ "$FD" = "warp" ] && uci -q delete firewall.@forwarding[$i] 2>/dev/null
    i=$((i-1))
  done
  Z=$(uci show firewall | grep -c '=zone')
  i=$((Z-1)); while [ "$i" -ge 0 ]; do
    [ "$(uci -q get firewall.@zone[$i].name 2>/dev/null)" = "warp" ] && uci -q delete firewall.@zone[$i] 2>/dev/null
    i=$((i-1))
  done
  uci commit network; uci commit firewall
  rm -f "$WARP_REG" "$DIR/.pbr_active"
  /etc/init.d/network reload 2>/dev/null
  echo "🗑 WARP видалено"
}

warp_mode_all() {
  uci set network.@wireguard_warp[0].route_allowed_ips='1'
  # forwarding lan->warp
  if ! uci show firewall | grep -q "src='lan'.*dest='warp'"; then
    uci add firewall forwarding >/dev/null
    uci set firewall.@forwarding[-1].src='lan'
    uci set firewall.@forwarding[-1].dest='warp'
    uci commit firewall
    /etc/init.d/firewall restart 2>/dev/null
  fi
  uci commit network
  /etc/init.d/network reload 2>/dev/null
  sleep 3
  # убрать PBR если был
  [ -f "$DIR/.pbr_active" ] && { eval "$(pbr_clear)"; rm -f "$DIR/.pbr_active"; }
  echo "🟢 Весь трафік через WARP"
}

warp_mode_stop() {
  uci set network.@wireguard_warp[0].route_allowed_ips='0'
  uci commit network
  /etc/init.d/network reload 2>/dev/null
  [ -f "$DIR/.pbr_active" ] && { eval "$(pbr_clear)"; rm -f "$DIR/.pbr_active"; }
  echo "⏸ Трафік не перехоплюється (тунель є)"
}

pbr_list() {
  if [ ! -f "$BLOCKED" ] || [ ! -s "$BLOCKED" ]; then
    echo "📋 Список порожній"
  else
    cat "$BLOCKED" | head -n 100
  fi
}

pbr_add() {
  IP="$1"
  case "$IP" in ''|*[!0-9./]*) echo "❌ Невірний формат"; return 1;; esac
  echo "$IP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/([0-9]|[12][0-9]|3[012]))?$' || { echo "❌ Невірний CIDR"; return 1; }
  echo "$IP" >> "$BLOCKED"
  echo "✅ Додано: $IP"
}

pbr_del() {
  N="$1"
  sed -i "${N}d" "$BLOCKED" 2>/dev/null && echo "✅ Видалено" || echo "❌ Немає такого"
}

pbr_update() {
  URL="https://raw.githubusercontent.com/dneese/warp-luci/main/blocked.list"
  mkdir -p "$DIR"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time 15 "$URL" -o "$BLOCKED.tmp" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$BLOCKED.tmp" "$URL" 2>/dev/null
  elif command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -qO "$BLOCKED.tmp" "$URL" 2>/dev/null
  else
    echo "❌ нема curl/wget/uclient-fetch"
    return 1
  fi
  if [ -s "$BLOCKED.tmp" ] && grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.' "$BLOCKED.tmp"; then
    mv "$BLOCKED.tmp" "$BLOCKED"
    CNT=$(wc -l < "$BLOCKED" | tr -d ' ')
    echo "✅ Список оновлено: $CNT записів з $URL"
  else
    rm -f "$BLOCKED.tmp"
    echo "❌ Не вдалося оновити (порожній або битий $URL)"
    return 1
  fi
}

pbr_apply() {
  echo "nft add set inet fw4 warp_block { type ipv4_addr\; flags interval\; }"
  echo "nft flush set inet fw4 warp_block"
  while IFS= read -r CIDR; do
    [ -z "$CIDR" ] && continue
    echo "nft add element inet fw4 warp_block { $CIDR }"
  done < "$BLOCKED"
  echo "nft add rule inet fw4 forward ip daddr @warp_block counter mark set 0x1"
  echo "ip rule add fwmark 0x1 table 100"
  echo "ip route add default dev warp table 100 2>/dev/null"
}

pbr_clear() {
  echo "nft flush set inet fw4 warp_block 2>/dev/null; nft delete set inet fw4 warp_block 2>/dev/null; ip rule del fwmark 0x1 table 100 2>/dev/null; ip route del default dev warp table 100 2>/dev/null"
}

warp_mtu_test() {
  echo "⏳ Тест MTU 1420/1400/1380/1280..."
  for MTU in 1420 1400 1380 1280; do
    uci set network.warp.mtu="$MTU"; uci commit network; /etc/init.d/network reload 2>/dev/null; sleep 6
    HS=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
    if [ -n "$HS" ] && [ "$HS" != "0" ]; then
      echo "✅ MTU $MTU: handshake OK"
    else
      echo "❌ MTU $MTU: no handshake"
    fi
  done
  uci set network.warp.mtu='1280'; uci commit network; /etc/init.d/network reload 2>/dev/null
}

warp_ping() {
  for EP in engage.cloudflareclient.com 162.159.192.1 162.159.193.1 188.114.96.1 188.114.97.1; do
    AVG=$(ping -c 3 -W 2 "$EP" 2>/dev/null | grep -o 'avg=[0-9.]*' | cut -d= -f2)
    [ -z "$AVG" ] && AVG="—"
    echo "$EP: $AVG ms"
  done
}

case "$1" in
  status) warp_status ;;
  connect) warp_connect ;;
  delete) warp_delete ;;
  mode_all) warp_mode_all ;;
  mode_stop) warp_mode_stop ;;
  pbr_list) pbr_list ;;
  pbr_add) pbr_add "$2" ;;
  pbr_del) pbr_del "$2" ;;
  pbr_update) pbr_update ;;
  pbr_apply) eval "$(pbr_apply)"; echo "✅ PBR застосовано" ;;
  pbr_clear) eval "$(pbr_clear)"; echo "✅ PBR очищено" ;;
  mtu) warp_mtu_test ;;
  ping) warp_ping ;;
  *) echo "usage: $0 status|connect|delete|mode_all|mode_stop|pbr_list|pbr_add <IP>|pbr_del <N>|pbr_update|pbr_apply|mtu|ping" ;;
esac
