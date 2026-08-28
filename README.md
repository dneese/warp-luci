# 🌐 WARP LuCI — Cloudflare WARP для OpenWrt

Простая веб-страница в роутере для лёгкой настройки Cloudflare WARP.

**Настройка в один клик:** статус, подключить, удалить, весь трафик, список, пинг, MTU.

## Возможности

- 📊 **Статус** — тунель активен / handshake / режим (весь трафик / PBR / idle), `warp: up/down`
- ⚡️ **Подключить** — авто-регистрация через публичный API Cloudflare (`wireguard-tools`, ключи остаются на роутере, без перехвата трафика)
- 🗑 **Удалить WARP** — интерфейс `warp`, peer `wireguard_warp`, зона `warp`, ключи `/etc/tg-bot/warp.reg`
- 🟢 **Весь трафик** — `route_allowed_ips=1` + `firewall forwarding lan→warp`, ⏸ **Остановить** — `route_allowed_ips=0`
- 📋 **PBR Список** — ручной список заблокированных IP/CIDR (112 записей) → `nftables set + fwmark 0x1` → только они через WARP
- 📏 **MTU-тест** — перебор 1420/1400/1380/1280 с проверкой handshake, авто-возврат на 1280
- 📡 **Пинг endpoint** — 6 endpoint'ов `engage.cloudflareclient.com` / `162.159.*.*` / `188.114.*.*`

**Без Telegram, без AI, без LuCI-зависимостей кроме базы.**

## Установка

```sh
# 1. Залить на роутер (с телефона):
scp -r warp-luci root@192.168.1.2:/tmp/
ssh root@192.168.1.2 "sh /tmp/warp-luci/install.sh"

# 2. Или пакетом (сборка без SDK):
sh warp-luci/package/build.sh  # → warp-luci_1.0_all.ipk
scp warp-luci/*.ipk root@192.168.1.2:/tmp/
ssh root@192.168.1.2 "apk add --allow-untrusted /tmp/warp-luci_*.ipk || opkg install /tmp/*.ipk"
```

После: **LuCI → Services → WARP** (`http://192.168.1.2/cgi-bin/luci/admin/services/warp`).

Или CLI: `warp-api.sh status|connect|delete|mode_all|mode_stop|pbr_list|mtu|ping`.

## Требования

- ImmortalWrt/OpenWrt 21.02+ (`apk`/`opkg`), `curl`, `wireguard-tools` (ставится автоматом), `kmod-wireguard`

## Структура

```
warp-luci/
├── files/
│   ├── usr/bin/warp-api.sh
│   ├── www/luci-static/resources/view/warp/overview.js
│   ├── etc/config/warp
│   └── etc/init.d/warp-service
├── package/
│   ├── Makefile
│   └── build.sh
└── install.sh
```

## Размер

~13K LuCI + 8K бэкенд, без зависимостей.

## Лицензия

MIT
