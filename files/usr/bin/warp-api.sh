#!/bin/sh
# warp-api.sh — бекенд для LuCI Cloudflare WARP (виправлена версія)
#
# Ключова зміна: режим "весь трафік" більше НЕ використовує route_allowed_ips=1.
# Натомість — policy routing (таблиця 100 + ip rule), так само, як режим PBR,
# тільки без fwmark. Це усуває петлю маршрутизації, через яку handshake
# падав у 0 при route_allowed_ips=1.
#
# Виклик: warp-api.sh status|connect|delete|mode_all|mode_stop|mode_pbr|
#   pbr_list|pbr_add <IP>|pbr_del <N>|pbr_add_domain <domain>|pbr_del_domain <domain>|
#   pbr_update|pbr_apply|pbr_clear|verify|mtu|mtu_result|ping|best_endpoint|endpoint_result

DIR="/etc/warp"
WARP_REG="$DIR/warp.reg"
BLOCKED="$DIR/blocked.list"
DOMAINS="$DIR/domains.list"
MTU_LOG="$DIR/mtu.log"
ENDPOINT_LOG="$DIR/endpoint.log"
MODE_FILE="$DIR/.mode"
LOCK="$DIR/.lock"

TBL=100           # таблиця маршrutів WARP
RULE_ALL=100      # pref для "весь трафік"
RULE_EP=50        # pref для виключення endpoint'а з тунелю
MARK=0x1          # fwmark для PBR

ENDPOINT_CANDIDATES="162.159.192.1 162.159.193.1 162.159.195.1 188.114.96.1 188.114.97.1 188.114.98.1 188.114.99.1"

# ─────────────────────────── довідники ───────────────────────────

peer_opt() {
  # peer_opt <key> — прочитати опцію з wireguard peer, з fallback на стару секцію
  V=$(uci -q get network.@wireguard_warp[0].$1 2>/dev/null)
  [ -z "$V" ] && V=$(uci -q get network.warp_peer.$1 2>/dev/null)
  echo "$V"
}

peer_set() {
  # peer_set <key> <value>
  if uci -q get network.@wireguard_warp[0] >/dev/null 2>&1; then
    uci set network.@wireguard_warp[0].$1="$2"
  else
    uci set network.warp_peer.$1="$2"
  fi
}

ep_ip() {
  # Розв'язати endpoint_host у IPv4 (якщо це домен)
  H=$(peer_opt endpoint_host)
  [ -z "$H" ] && { echo ""; return; }
  case "$H" in
    *[!0-9.]*) ;;
    *) echo "$H"; return ;;
  esac
  IPS=$(nslookup "$H" 2>/dev/null | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | grep -v '^127\.')
  for IP in $IPS; do
    # відкидаємо приватні — Cloudflare endpoint завжди публічний
    case "$IP" in
      10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) continue ;;
    esac
    echo "$IP"; return
  done
  echo "$IPS" | tr ' ' '\n' | head -1
}

wan_dev() {
  D=$(ip route show default 2>/dev/null | awk '/^default/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
  [ -z "$D" ] && D=$(ubus call network.wan status 2>/dev/null | grep -o '"l3_device": *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"$//')
  echo "$D"
}

# ─────────────────────── керування маршрутами ───────────────────────

del_pref() {
  # Видалити ip rule за конкретним pref (надійніше, ніж "ip rule del pref X")
  P="$1"
  H=$(ip rule show 2>/dev/null | grep -E "^${P}:" | head -1 | sed -n 's/^\([0-9]*\):.*/\1/p')
  [ -n "$H" ] && ip rule del "$H" 2>/dev/null && return 0
  ip rule del pref "$P" 2>/dev/null
}

routes_reset() {
  # Зняти ВСІ правила WARP і очистити таблицю 100.
  # Викликається безпечно (idempotent) при будь-якому перемиканні режиму.
  del_pref "$RULE_ALL"
  del_pref "$RULE_EP"
  ip rule del fwmark $MARK 2>/dev/null
  ip route flush table $TBL 2>/dev/null
  nft flush set inet fw4 blocked_net 2>/dev/null
}

routes_apply() {
  # $1 = "all" (без fwmark) | "pbr" (з fwmark)
  MODE="$1"

  del_pref "$RULE_ALL"
  del_pref "$RULE_EP"
  ip rule del fwmark $MARK 2>/dev/null

  ip link show warp >/dev/null 2>&1 || {
    echo "❌ Інтерфейс warp не піднято. Спочатку: warp-api.sh connect"
    return 1
  }

  EP=$(ep_ip)
  WAN=$(wan_dev)

  # 1. Копіюємо connected-маршрути (scope link) з main у таблицю 100.
  #    Без цього в режимі "all" пакети до LAN-клєнтів і до WAN-шлюзу
  #    пішли б у тунель і зламали б локалку.
  ip route show table main scope link 2>/dev/null | while read -r _r; do
    ip route add $_r table $TBL 2>/dev/null
  done

  # 2. Дефолт у таблиці 100 через тунель
  ip route replace default dev warp table $TBL 2>/dev/null || {
    echo "❌ Не вдалося створити default dev warp table $TBL"
    return 1
  }

  # 3. КРИТИЧНО: endpoint Cloudflare мусить йти поза тунелем, інакше
  #    UDP-пакети самого WireGuard замикаються самі на себе (handshake = 0).
  if [ -n "$EP" ]; then
    ip rule add pref $RULE_EP to "$EP" lookup main 2>/dev/null \
      && echo "🔁 endpoint $EP → поза тунелем (pref $RULE_EP)"
  else
    echo "⚠️ Не вдалося розв'язати endpoint_host — перевірте DNS"
  fi

  # 4. Правило маршрутизації
  if [ "$MODE" = "all" ]; then
    ip rule add pref $RULE_ALL lookup $TBL 2>/dev/null \
      || { echo "❌ не вдалося додати ip rule pref $RULE_ALL lookup $TBL"; return 1; }
  else
    ip rule add pref $RULE_ALL fwmark $MARK lookup $TBL 2>/dev/null \
      || { echo "❌ не вдалося додати ip rule fwmark"; return 1; }
  fi

  echo "$MODE" > "$MODE_FILE"
  return 0
}

# ─────────────────────────── firewall ───────────────────────────

fw_ensure_zone() {
  if uci -q get firewall.warp >/dev/null 2>&1 || uci show firewall 2>/dev/null | grep -q "name='warp'"; then
    # оновити налаштування наявної зони (без індексної арифметики)
    Z=$(uci show firewall 2>/dev/null | grep "name='warp'" | head -1 | cut -d= -f1 | cut -d. -f2)
    [ -n "$Z" ] || return 0
    uci set firewall.$Z.input='REJECT'
    uci set firewall.$Z.output='ACCEPT'
    uci set firewall.$Z.forward='REJECT'
    uci set firewall.$Z.masq='1'
    uci set firewall.$Z.mtu_fix='1'
    uci -q del_list firewall.$Z.network='warp' 2>/dev/null
    uci add_list firewall.$Z.network='warp'
    uci commit firewall
    return 0
  fi
  S=$(uci add firewall zone)
  [ -z "$S" ] && { echo "❌ не вдалося створити firewall zone"; return 1; }
  uci set firewall.$S.name='warp'
  uci set firewall.$S.input='REJECT'
  uci set firewall.$S.output='ACCEPT'
  uci set firewall.$S.forward='REJECT'
  uci set firewall.$S.masq='1'
  uci set firewall.$S.mtu_fix='1'
  uci add_list firewall.$S.network='warp'
  uci commit firewall
}

fw_ensure_forwarding() {
  # Точкова перевірка src=lan AND dest=warp (не grep по всьому конфігу)
  if uci show firewall 2>/dev/null | grep -q "dest='warp'"; then
    return 0
  fi
  S=$(uci add firewall forwarding)
  [ -z "$S" ] && { echo "❌ не вдалося створити firewall forwarding"; return 1; }
  uci set firewall.$S.src='lan'
  uci set firewall.$S.dest='warp'
  uci commit firewall
  echo "➕ додано forwarding lan→warp"
}

fw_apply() {
  fw_ensure_zone || return 1
  fw_ensure_forwarding || return 1
  /etc/init.d/firewall reload 2>/dev/null
}

# ─────────────────────────── статус ───────────────────────────

detect_mode() {
  # Реальна перевірка через ip rule, а не через значення uci
  if ip rule show 2>/dev/null | grep -qE "^${RULE_ALL}:.*fwmark"; then
    echo pbr
  elif ip rule show 2>/dev/null | grep -qE "^${RULE_ALL}:"; then
    echo all
  else
    echo none
  fi
}

warp_status() {
  if ! uci -q get network.warp >/dev/null 2>&1; then
    echo "📭 не налаштовано"
    return
  fi
  EP=$(peer_opt endpoint_host)
  [ -n "$EP" ] && echo "endpoint: $EP"
  HS=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
  if [ -z "$HS" ] || [ "$HS" = "0" ]; then
    echo "🔴 Немає handshake"
  else
    NOW=$(date +%s)
    echo "🟢 Тунель активний (hs=$((NOW-HS)) с тому)"
  fi

  M=$(detect_mode)
  case "$M" in
    all)
      echo "режим: весь трафік через WARP"
      ;;
    pbr)
      CNT=$(nft list set inet fw4 blocked_net 2>/dev/null | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | wc -l | tr -d ' ')
      echo "режим: тільки заблоковані через WARP (PBR, ${CNT:-0} записів)"
      ;;
    none)
      echo "режим: трафік не перехоплюється (тунель є)"
      ;;
  esac

  ip addr show warp 2>/dev/null | grep -q "inet" && echo "warp: up" || echo "warp: down"

  # коротка перевірка реальної маршрутизації
  if [ "$M" != "none" ]; then
    R=$(ip route get 1.1.1.1 2>/dev/null | head -1)
    case "$R" in
      *"dev warp"*) echo "маршрут 1.1.1.1: через warp ✓" ;;
      *) echo "маршрут 1.1.1.1: НЕ через warp ✗ ($R)" ;;
    esac
  fi

  if [ -f "$MTU_LOG" ]; then
    echo "--- MTU лог ---"; cat "$MTU_LOG"
  fi
  if [ -f "$ENDPOINT_LOG" ]; then
    echo "--- Endpoint лог ---"; cat "$ENDPOINT_LOG"
  fi
}

warp_verify() {
  echo "=== Діагностика WARP ==="
  echo "--- uci peer ---"
  uci show network 2>/dev/null | grep -E 'wireguard|warp_peer|endpoint_host|allowed_ips|route_allowed_ips|addresses' | sed 's/^/  /'
  echo "--- інтерфейс warp ---"
  ip addr show warp 2>&1 | sed 's/^/  /'
  echo "--- wg show ---"
  wg show warp 2>&1 | sed 's/^/  /'
  echo "--- ip rule ---"
  ip rule show 2>&1 | sed 's/^/  /'
  echo "--- ip route table $TBL ---"
  ip route show table $TBL 2>&1 | sed 's/^/  /'
  echo "--- маршрут 1.1.1.1 ---"
  ip route get 1.1.1.1 2>&1 | sed 's/^/  /'
  echo "--- endpoint ($(ep_ip)) ---"
  E=$(ep_ip)
  [ -n "$E" ] && ip route get "$E" 2>&1 | sed 's/^/  /'
  echo "--- nft set ---"
  nft list set inet fw4 blocked_net 2>&1 | head -20 | sed 's/^/  /'
  echo "--- firewall zone warp ---"
  uci show firewall 2>/dev/null | grep -E "name='warp'|dest='warp'|='warp'" | sed 's/^/  /'
  echo "=== кінець ==="
}

# ─────────────────────────── дії ───────────────────────────

warp_connect() {
  command -v wg >/dev/null 2>&1 || { apk add wireguard-tools 2>/dev/null || opkg install wireguard-tools 2>/dev/null; }
  PRIV=$(wg genkey 2>/dev/null)
  PUB=$(echo "$PRIV" | wg pubkey 2>/dev/null)
  JSON=$(curl -s --max-time 10 -X POST https://api.cloudflareclient.com/v0a2158/reg \
    -H "Content-Type: application/json" \
    -d "{\"install_id\":\"\",\"tos\":\"$(date -u +%FT%T.000Z)\",\"key\":\"$PUB\"}")
  ID=$(echo "$JSON" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
  TOKEN=$(echo "$JSON" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  if [ -z "$ID" ]; then
    echo "❌ Реєстрація не вдалася (Cloudflare API)"
    echo "$JSON" | head -c 300
    return 1
  fi
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
  uci set network.@wireguard_warp[-1].endpoint_host='162.159.192.1'
  uci set network.@wireguard_warp[-1].endpoint_port='2408'
  uci add_list network.@wireguard_warp[-1].allowed_ips='0.0.0.0/0'
  uci add_list network.@wireguard_warp[-1].allowed_ips='::/0'
  uci set network.@wireguard_warp[-1].persistent_keepalive='25'
  # КРИТИЧНО: route_allowed_ips ЗАВЖДИ 0. Маршрутизація — через policy routing.
  uci set network.@wireguard_warp[-1].route_allowed_ips='0'
  uci commit network
  fw_apply
  ifup warp 2>/dev/null || /etc/init.d/network reload 2>/dev/null
  sleep 6
  HS=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
  if [ -n "$HS" ] && [ "$HS" != "0" ]; then
    echo "✅ WARP створено, handshake OK"
  else
    echo "⚠️ Тунель створено, але handshake поки 0 — спробуйте warp-api.sh mtu"
  fi
}

warp_delete() {
  ifdown warp 2>/dev/null
  routes_reset
  rm -f "$MODE_FILE"
  while uci -q delete network.@wireguard_warp[0] >/dev/null 2>&1; do :; done
  uci -q delete network.warp 2>/dev/null
  while uci -q delete network.warp_peer >/dev/null 2>&1; do :; done
  N=$(uci show firewall 2>/dev/null | grep -c '=forwarding')
  i=$((N-1)); while [ "$i" -ge 0 ]; do
    FS=$(uci -q get firewall.@forwarding[$i].src 2>/dev/null)
    FD=$(uci -q get firewall.@forwarding[$i].dest 2>/dev/null)
    [ "$FS" = "lan" ] && [ "$FD" = "warp" ] && uci -q delete firewall.@forwarding[$i] 2>/dev/null
    i=$((i-1))
  done
  Z=$(uci show firewall 2>/dev/null | grep -c '=zone')
  i=$((Z-1)); while [ "$i" -ge 0 ]; do
    [ "$(uci -q get firewall.@zone[$i].name 2>/dev/null)" = "warp" ] && uci -q delete firewall.@zone[$i] 2>/dev/null
    i=$((i-1))
  done
  uci commit network; uci commit firewall
  rm -f "$WARP_REG" "$DIR/.pbr_active" "$MTU_LOG" "$ENDPOINT_LOG"
  /etc/init.d/network reload 2>/dev/null
  /etc/init.d/firewall restart 2>/dev/null
  echo "🗑 WARP видалено"
}

warp_mode_all() {
  if ! uci -q get network.warp >/dev/null 2>&1; then
    echo "❌ WARP не налаштовано. Спочатку: warp-api.sh connect"; return 1
  fi
  mkdir -p "$DIR"; date +%s > "$LOCK"
  # Знімаємо PBR-правила повністю (без перевірки .pbr_active — надійніше)
  pbr_clear >/dev/null 2>&1

  peer_set route_allowed_ips '0'
  uci commit network

  fw_apply || { rm -f "$LOCK"; return 1; }

  # НЕ робимо ifup warp тут: ifup провокує hotplug, який змагається
  # за перемикання режиму. Інтерфейс і так уже піднятий (інакше routes_apply впаде).
  ip link show warp >/dev/null 2>&1 || ifup warp 2>/dev/null
  sleep 1

  routes_apply all || { rm -f "$LOCK"; return 1; }

  # Жорстка перевірка: правило маршрутизації реально стоїть?
  sleep 2
  if ! ip rule show 2>/dev/null | grep -qE "^${RULE_ALL}:.*lookup ${TBL}\$"; then
    rm -f "$LOCK"
    echo "❌ ip rule pref $RULE_ALL lookup $TBL не встановлено — перемикання не вдалося"
    ip rule show | sed 's/^/   /'
    return 1
  fi

  HS=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
  R=$(ip route get 1.1.1.1 2>/dev/null | head -1)
  rm -f "$LOCK"
  if [ -n "$HS" ] && [ "$HS" != "0" ]; then
    case "$R" in
      *"dev warp"*) echo "🟢 Весь трафік через WARP (handshake OK, маршрут через warp)" ;;
      *) echo "⚠️ Handshake OK, але маршрут 1.1.1.1 НЕ через warp: $R" ;;
    esac
  else
    echo "❌ Handshake = 0. Дивіться warp-api.sh verify"
  fi
}

warp_mode_stop() {
  if ! uci -q get network.warp >/dev/null 2>&1; then
    echo "❌ WARP не налаштовано. Спочатку: warp-api.sh connect"; return 1
  fi
  mkdir -p "$DIR"; date +%s > "$LOCK"
  peer_set route_allowed_ips '0'
  uci commit network
  pbr_clear >/dev/null 2>&1
  del_pref "$RULE_ALL"
  del_pref "$RULE_EP"
  ip route flush table $TBL 2>/dev/null
  rm -f "$MODE_FILE" "$DIR/.pbr_active" "$LOCK"
  echo "⏸ Трафік не перехоплюється (тунель є)"
}

warp_mode_pbr() {
  if ! uci -q get network.warp >/dev/null 2>&1; then
    echo "❌ WARP не налаштовано. Спочатку: warp-api.sh connect"; return 1
  fi
  mkdir -p "$DIR"; date +%s > "$LOCK"
  peer_set route_allowed_ips '0'
  uci commit network
  ip link show warp >/dev/null 2>&1 || ifup warp 2>/dev/null
  sleep 3
  # fw_apply робить firewall reload — він зтирає nft set та правила.
  # Тому спершу застосовуємо PBR, а після reload обов'язково resync-имо.
  pbr_apply
  RC=$?
  fw_apply || { rm -f "$LOCK"; return 1; }
  sleep 2
  # firewall reload міг знести nft-правила — відновлюємо
  _pbr_resync && echo "✅ PBR відновлено після firewall reload"
  rm -f "$LOCK"
  return $RC
}

pbr_list() {
  echo "=== IP-діапазони (blocked.list) ==="
  if [ ! -f "$BLOCKED" ] || [ ! -s "$BLOCKED" ]; then
    echo "(порожньо)"
  else
    cat "$BLOCKED" | head -n 100
  fi
  echo ""
  echo "=== Домени (domains.list) ==="
  if [ ! -f "$DOMAINS" ] || [ ! -s "$DOMAINS" ]; then
    echo "(порожньо)"
  else
    cat "$DOMAINS"
  fi
}

pbr_add() {
  IP="$1"
  case "$IP" in ''|*[!0-9./]*) echo "❌ Невірний формат"; return 1;; esac
  echo "$IP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/([0-9]|[12][0-9]|3[012]))?$' || { echo "❌ Невірний CIDR"; return 1; }
  grep -qxF "$IP" "$BLOCKED" 2>/dev/null && { echo "ℹ️ Вже є: $IP"; return 0; }
  echo "$IP" >> "$BLOCKED"
  echo "✅ Додано: $IP"
}

pbr_add_domain() {
  DOMAIN="$1"
  [ -z "$DOMAIN" ] && { echo "❌ Вкажіть домен, наприклад: warp-api.sh pbr_add_domain vk.com"; return 1; }
  echo "$DOMAIN" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?(\.[a-zA-Z]{2,})$' || { echo "❌ Невірний домен: $DOMAIN"; return 1; }
  mkdir -p "$DIR"
  IPS=$(nslookup "$DOMAIN" 2>/dev/null | awk '/^Address [0-9]+:/{print $3}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
  [ -z "$IPS" ] && IPS=$(nslookup "$DOMAIN" 2>/dev/null | grep 'Address:' | tail -n +2 | awk '{print $2}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
  if [ -z "$IPS" ]; then
    echo "❌ Не вдалося резолвити $DOMAIN"
    return 1
  fi
  ADDED=0
  for IP in $IPS; do
    grep -qxF "$IP" "$BLOCKED" 2>/dev/null && continue
    echo "$IP" >> "$BLOCKED"
    ADDED=$((ADDED+1))
  done
  grep -qxF "$DOMAIN" "$DOMAINS" 2>/dev/null || echo "$DOMAIN" >> "$DOMAINS"
  echo "✅ $DOMAIN → додано $ADDED IP ($(echo $IPS | wc -w) всього)"
  echo "$IPS" | tr ' ' '\n' | sed 's/^/   /'
  if nft list set inet fw4 blocked_net >/dev/null 2>&1; then
    for IP in $IPS; do
      nft add element inet fw4 blocked_net "{ $IP }" 2>/dev/null
    done
    echo "🔄 Додано до активного PBR set"
  fi
}

pbr_del_domain() {
  DOMAIN="$1"
  [ -z "$DOMAIN" ] && { echo "❌ Вкажіть домен"; return 1; }
  if [ ! -f "$DOMAINS" ] || ! grep -qxF "$DOMAIN" "$DOMAINS" 2>/dev/null; then
    echo "❌ Домен не знайдено: $DOMAIN"
    return 1
  fi
  grep -vxF "$DOMAIN" "$DOMAINS" > "$DOMAINS.tmp" && mv "$DOMAINS.tmp" "$DOMAINS"
  echo "✅ Видалено домен: $DOMAIN"
  echo "ℹ️ IP цього домену залишаються в blocked.list. Оновіть список вручну якщо потрібно."
}

pbr_del() {
  N="$1"
  case "$N" in ''|*[!0-9]*) echo "❌ Номер має бути число"; return 1;; esac
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
    echo "✅ Список оновлено: $CNT записів"
  else
    rm -f "$BLOCKED.tmp"
    echo "❌ Не вдалося оновити список"
    return 1
  fi
}

_pbr_resolve_domains() {
  [ -f "$DOMAINS" ] && [ -s "$DOMAINS" ] || return 0
  RESOLVED=0
  while IFS= read -r DOMAIN; do
    [ -z "$DOMAIN" ] && continue
    IPS=$(nslookup "$DOMAIN" 2>/dev/null | awk '/^Address [0-9]+:/{print $3}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
    [ -z "$IPS" ] && IPS=$(nslookup "$DOMAIN" 2>/dev/null | grep 'Address:' | tail -n +2 | awk '{print $2}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
    for IP in $IPS; do
      nft add element inet fw4 blocked_net "{ $IP }" 2>/dev/null
      RESOLVED=$((RESOLVED+1))
    done
  done < "$DOMAINS"
  [ "$RESOLVED" -gt 0 ] && echo "🌐 Домени: додано $RESOLVED IP з domains.list"
}

pbr_apply() {
  if [ ! -s "$BLOCKED" ] && [ ! -s "$DOMAINS" ]; then
    echo "PBR: blocked.list та domains.list порожні"
    return 1
  fi
  nft add set inet fw4 blocked_net '{ type ipv4_addr; flags interval; }' 2>/dev/null
  nft flush set inet fw4 blocked_net 2>/dev/null
  if [ -s "$BLOCKED" ]; then
    while IFS= read -r CIDR; do
      [ -n "$CIDR" ] && nft add element inet fw4 blocked_net "{ $CIDR }" 2>/dev/null
    done < "$BLOCKED"
  fi
  _pbr_resolve_domains

  # маршрутизація через policy routing (НЕ route_allowed_ips)
  ip link show warp >/dev/null 2>&1 || ifup warp 2>/dev/null
  sleep 1
  routes_apply pbr || { rm -f "$LOCK"; return 1; }

  # --- nft-правила ставимо ОСТАНІМІ ---
  # firewall reload (з fw_apply або hotplug) стирає set/правила, тому
  # вставляти їх після нього — інакше вони зникнуть після ребуту.
  _pbr_nft_rules

  touch "$DIR/.pbr_active"
  CNT=$(wc -l < "$BLOCKED" 2>/dev/null || echo 0)
  echo "PBR: застосовано ($CNT IP-записів)"

  # Перевірка: set + обидва правила мають бути на місці
  nft list set inet fw4 blocked_net >/dev/null 2>&1 || { echo "⚠️ nft set не створено"; return 1; }
  _pbr_nft_verify
}

# Вставляє правила маркування (prerouting) та приймання (forward),
# попередньо прибираючи старі. Кожна команда — з перевіркою.
_pbr_nft_rules() {
  for CHAIN in prerouting forward; do
    while true; do
      H=$(nft -a list chain inet fw4 $CHAIN 2>/dev/null | grep 'blocked_net' | head -1 | sed -n 's/.*handle \([0-9]*\).*/\1/p')
      [ -z "$H" ] && break
      nft delete rule inet fw4 $CHAIN handle "$H" 2>/dev/null || break
    done
  done
  nft insert rule inet fw4 prerouting ip daddr @blocked_net meta mark set $MARK 2>/dev/null
  nft insert rule inet fw4 forward ip daddr @blocked_net accept 2>/dev/null
}

# Перезастосувати set + правила, якщо firewall їх знесе
_pbr_resync() {
  _pbr_nft_verify || {
    nft add set inet fw4 blocked_net '{ type ipv4_addr; flags interval; }' 2>/dev/null
    nft flush set inet fw4 blocked_net 2>/dev/null
    [ -s "$BLOCKED" ] && while IFS= read -r CIDR; do
      [ -n "$CIDR" ] && nft add element inet fw4 blocked_net "{ $CIDR }" 2>/dev/null
    done < "$BLOCKED"
    _pbr_resolve_domains >/dev/null 2>&1
    _pbr_nft_rules
    sleep 1
    _pbr_nft_verify
  }
}

_pbr_nft_verify() {
  nft list set inet fw4 blocked_net >/dev/null 2>&1 || return 1
  # nft друкує mark як 0x00000001 — перевіряємо за змістом, не за форматом
  nft list chain inet fw4 prerouting 2>/dev/null | grep 'blocked_net' | grep -q 'meta mark set' || return 1
  nft list chain inet fw4 forward    2>/dev/null | grep -q 'blocked_net' || return 1
  return 0
}

pbr_clear() {
  nft flush set inet fw4 blocked_net 2>/dev/null
  nft delete set inet fw4 blocked_net 2>/dev/null
  for CHAIN in prerouting forward; do
    while true; do
      H=$(nft -a list chain inet fw4 $CHAIN 2>/dev/null | grep 'blocked_net' | head -1 | sed -n 's/.*handle \([0-9]*\).*/\1/p')
      [ -z "$H" ] && break
      nft delete rule inet fw4 $CHAIN handle "$H" 2>/dev/null
    done
  done
  ip rule del fwmark $MARK 2>/dev/null
  del_pref "$RULE_ALL"
  ip route flush table $TBL 2>/dev/null
  rm -f "$DIR/.pbr_active"
  echo "PBR: правила прибрано"
}

# ─────────────────────────── MTU / endpoint / ping ───────────────────────────

_mtu_run() {
  mkdir -p "$DIR"
  echo "⏳ Запущено: $(date)" > "$MTU_LOG"
  BEST=""
  for MTU in 1420 1400 1380 1280; do
    uci set network.warp.mtu="$MTU"
    uci commit network
    ip link set mtu "$MTU" dev warp 2>/dev/null || true
    ip link show warp 2>/dev/null | grep -q 'DOWN' && ifup warp 2>/dev/null || true
    sleep 5
    HS=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
    if [ -n "$HS" ] && [ "$HS" != "0" ]; then
      echo "✅ MTU $MTU: handshake OK" >> "$MTU_LOG"
      [ -z "$BEST" ] && BEST="$MTU"
    else
      echo "❌ MTU $MTU: no handshake" >> "$MTU_LOG"
    fi
  done
  FINAL="${BEST:-1280}"
  uci set network.warp.mtu="$FINAL"
  uci commit network
  ip link set mtu "$FINAL" dev warp 2>/dev/null || true
  echo "📏 Фінальний MTU: $FINAL" >> "$MTU_LOG"
  echo "✅ Готово: $(date)" >> "$MTU_LOG"
}

warp_mtu_test() {
  if ! uci -q get network.warp >/dev/null 2>&1; then
    echo "❌ WARP не налаштовано. Спочатку підключіть: warp-api.sh connect"
    return 1
  fi
  if [ -f "$MTU_LOG" ] && grep -q '⏳ Запущено' "$MTU_LOG" && ! grep -q '✅ Готово' "$MTU_LOG"; then
    echo "⏳ Тест MTU вже виконується, зачекайте ~30с"
    cat "$MTU_LOG"
    return 0
  fi
  ( _mtu_run ) &
  echo "⏳ MTU тест запущено у фоні (~30с)"
}

warp_mtu_result() {
  if [ ! -f "$MTU_LOG" ]; then
    echo "(лог MTU тесту відсутній — запустіть: warp-api.sh mtu)"
    return
  fi
  cat "$MTU_LOG"
}

warp_ping() {
  for EP in engage.cloudflareclient.com $ENDPOINT_CANDIDATES; do
    RESULT=$(ping -c 3 -W 2 "$EP" 2>/dev/null)
    AVG=$(echo "$RESULT" | grep -oE '[0-9]+/[0-9]+/[0-9]+' | cut -d/ -f2)
    [ -z "$AVG" ] && AVG=$(echo "$RESULT" | grep -oE '[0-9]+\.[0-9]+/[0-9]+\.[0-9]+/[0-9]+\.[0-9]+' | cut -d/ -f2)
    [ -z "$AVG" ] && AVG="—"
    echo "$EP: ${AVG} ms"
  done
}

_endpoint_run() {
  mkdir -p "$DIR"
  echo "⏳ Запущено: $(date)" > "$ENDPOINT_LOG"
  BEST_IP=""
  BEST_AVG=99999
  for IP in $ENDPOINT_CANDIDATES; do
    RESULT=$(ping -c 3 -W 2 "$IP" 2>/dev/null)
    AVG=$(echo "$RESULT" | grep -oE '[0-9]+\.[0-9]+/[0-9]+\.[0-9]+/[0-9]+\.[0-9]+' | cut -d/ -f2)
    [ -z "$AVG" ] && AVG=$(echo "$RESULT" | grep -oE '[0-9]+/[0-9]+/[0-9]+' | cut -d/ -f2)
    if [ -z "$AVG" ]; then
      echo "❌ $IP: немає відгуку" >> "$ENDPOINT_LOG"
      continue
    fi
    echo "📡 $IP: ${AVG} ms" >> "$ENDPOINT_LOG"
    IS_BETTER=$(awk -v a="$AVG" -v b="$BEST_AVG" 'BEGIN{print (a<b)?1:0}')
    if [ "$IS_BETTER" = "1" ]; then
      BEST_AVG="$AVG"
      BEST_IP="$IP"
    fi
  done
  if [ -z "$BEST_IP" ]; then
    echo "❌ Жоден endpoint не відповів — залишаю поточний" >> "$ENDPOINT_LOG"
    echo "✅ Готово: $(date)" >> "$ENDPOINT_LOG"
    return 1
  fi
  PREV_EP=$(peer_opt endpoint_host)
  peer_set endpoint_host "$BEST_IP"
  uci commit network
  ifdown warp 2>/dev/null
  sleep 1
  ifup warp 2>/dev/null
  sleep 5
  HS=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
  echo "🏆 Обрано: $BEST_IP (${BEST_AVG} ms)" >> "$ENDPOINT_LOG"
  if [ -n "$HS" ] && [ "$HS" != "0" ]; then
    echo "✅ Handshake OK з новим endpoint" >> "$ENDPOINT_LOG"
  else
    echo "⚠️ Handshake відсутній — повертаю попередній endpoint: ${PREV_EP:-engage.cloudflareclient.com}" >> "$ENDPOINT_LOG"
    peer_set endpoint_host "${PREV_EP:-engage.cloudflareclient.com}"
    uci commit network
    ifdown warp 2>/dev/null; sleep 1; ifup warp 2>/dev/null
  fi
  # перезастосувати активний режим із новим endpoint
  [ -f "$MODE_FILE" ] && { M=$(cat "$MODE_FILE"); routes_apply "$M" >/dev/null 2>&1; }
  echo "✅ Готово: $(date)" >> "$ENDPOINT_LOG"
}

warp_best_endpoint() {
  if ! uci -q get network.warp >/dev/null 2>&1; then
    echo "❌ WARP не налаштовано. Спочатку: warp-api.sh connect"
    return 1
  fi
  if [ -f "$ENDPOINT_LOG" ] && grep -q '⏳ Запущено' "$ENDPOINT_LOG" && ! grep -q '✅ Готово' "$ENDPOINT_LOG"; then
    echo "⏳ Вибір endpoint вже виконується, зачекайте ~20с"
    cat "$ENDPOINT_LOG"
    return 0
  fi
  ( _endpoint_run ) &
  echo "⏳ Пошук найшвидшого endpoint запущено у фоні (~20с)"
}

warp_endpoint_result() {
  if [ ! -f "$ENDPOINT_LOG" ]; then
    echo "(лог вибору endpoint відсутній — запустіть: warp-api.sh best_endpoint)"
    return
  fi
  cat "$ENDPOINT_LOG"
}

case "$1" in
  status)          warp_status ;;
  verify)          warp_verify ;;
  connect)         warp_connect ;;
  delete)          warp_delete ;;
  mode_all)        warp_mode_all ;;
  mode_stop)       warp_mode_stop ;;
  mode_pbr)        warp_mode_pbr ;;
  pbr_list)        pbr_list ;;
  pbr_add)         pbr_add "$2" ;;
  pbr_del)         pbr_del "$2" ;;
  pbr_add_domain)  pbr_add_domain "$2" ;;
  pbr_del_domain)  pbr_del_domain "$2" ;;
  pbr_update)      pbr_update ;;
  pbr_apply)       pbr_apply ;;
  pbr_clear)       pbr_clear ;;
  mtu)             warp_mtu_test ;;
  mtu_result)      warp_mtu_result ;;
  ping)            warp_ping ;;
  best_endpoint)   warp_best_endpoint ;;
  endpoint_result) warp_endpoint_result ;;
  *) echo "usage: $0 status|verify|connect|delete|mode_all|mode_stop|mode_pbr|pbr_list|pbr_add <IP>|pbr_del <N>|pbr_add_domain <domain>|pbr_del_domain <domain>|pbr_update|pbr_apply|pbr_clear|mtu|mtu_result|ping|best_endpoint|endpoint_result" ;;
esac