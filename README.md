# 🌐 WARP LuCI — Cloudflare WARP для OpenWrt

Простая веб-страница в роутере для лёгкой настройки Cloudflare WARP.

**Настройка в один клик:** статус, подключить, удалить, весь трафик, список, пинг, MTU.

## Возможности

- 📊 **Статус** — тунель активен / handshake / режим (весь трафик / PBR / idle), `warp: up/down`, проверка фактического маршрута
- ⚡️ **Подключить** — авто-регистрация через публичный API Cloudflare (`wireguard-tools`, ключи остаются на роутере, без передачи)
- 🗑 **Удалить WARP** — интерфейс `warp`, peer `wireguard_warp`, зона `warp`, ключи `/etc/warp/warp.reg`
- 🟢 **Весь трафик** — policy routing: таблица 100 + `ip rule` + исключение endpoint из туннеля, ⏸ **Остановить** — снимает все правила
- 📋 **PBR Список** — ручной список заблокированных IP/CIDR (список в blocked.list) → `nftables set + fwmark 0x1` → только они через WARP
- 🔄 **Автовосстановление** — после ребута/обрыва активный режим (весь трафик или список) поднимается сам
- 🩺 **Диагностика** — `warp-api.sh verify` показывает uci, wg, ip rule, таблицы и маршруты
- 📏 **MTU-тест** — перебор 1420/1400/1380/1280 с проверкой handshake, авто-возврат на лучший найденный
- 📡 **Пинг endpoint** — 6 endpoint'ов `engage.cloudflareclient.com` / `162.159.*.*` / `188.114.*.*`

**Без Telegram, без AI, без LuCI-зависимостей кроме базы.**

---

## 🚀 Установка

### ⚡ Одна строка в SSH (САМЫЙ ПРОСТОЙ)

```bash
wget -q -O - https://raw.githubusercontent.com/dneese/warp-luci/main/install-embedded.sh | sh
```

Или с curl:

```bash
curl -fsSL https://raw.githubusercontent.com/dneese/warp-luci/main/install-embedded.sh | sh
```

**Готово!** Откройте в браузере: `http://192.168.1.1/cgi-bin/luci/admin/services/warp`

---

## 📖 Использование

### Веб-интерфейс

После установки откройте в браузере:

```
http://192.168.1.1/cgi-bin/luci/admin/services/warp
```

Или через LuCI: **Services → WARP**

### CLI команды (SSH)

```bash
# Статус туннеля
warp-api.sh status

# Подключить WARP (авто-регистрация)
warp-api.sh connect

# Весь трафик через WARP
warp-api.sh mode_all

# Отключить маршрутизацию (туннель есть, но трафик не идет)
warp-api.sh mode_stop

# Удалить WARP (но оставить приложение)
warp-api.sh delete

# Тест MTU (автоматический подбор оптимального)
warp-api.sh mtu

# Пинг endpoint'ов Cloudflare
warp-api.sh ping
```

---

## 🗑️ Удаление

### ⚡ Одна строка

```bash
wget -q -O - https://raw.githubusercontent.com/dneese/warp-luci/main/uninstall.sh | sh
```

Или с curl:

```bash
curl -fsSL https://raw.githubusercontent.com/dneese/warp-luci/main/uninstall.sh | sh
```

**Удалится:**
- ✅ Веб-интерфейс LuCI
- ✅ Скрипт `warp-api.sh`
- ✅ Hotplug-скрипт автовосстановления
- ✅ Туннель Cloudflare WARP (если был создан)
- ✅ Все конфиги и ключи
- ✅ Firewall правила

После удаления обновите браузер.

---

## 🔧 Требования

- **ОС:** ImmortalWrt/OpenWrt 21.02+
- **Пакеты:** `curl` или `wget` (для загрузки)
- **Ядро:** `wireguard-tools`, `kmod-wireguard` (устанавливаются автоматически)
- **Firewall:** fw4 / nftables

---

## 🧭 Как это работает

Оба режима используют **policy routing**, а не `route_allowed_ips=1`.

```
table 100:  default dev warp          ← трафик уходит в туннель
            + connected-маршруты LAN/WAN (копия из main)
ip rule:    50:  to <endpoint CF> lookup main   ← endpoint ВНЕ туннеля
            100: lookup 100                    ← режим «весь трафик»
            100: fwmark 0x1 lookup 100         ← режим «список»
```

**Почему не `route_allowed_ips=1`:** netifd ставит `0.0.0.0/0 dev warp` в **main table**, и UDP-пакеты самого WireGuard к endpoint'у Cloudflare тоже попадают в туннель. Возникает петля → handshake = 0 → трафик не идёт через WARP. Правило `pref 50 → lookup main` эту петлю разрывает.

**Про connected-маршруты в таблице 100:** без них в режиме «весь трафик» пакеты к LAN-клиентам и к WAN-шлюзу ушли бы в туннель и сломали бы локалку.

**Активный режим** хранится в `/etc/warp/.mode`; после ребута его восстанавливает hotplug-скрипт `/etc/hotplug.d/iface/30-warp-pbr`. Допустимые значения — `all` и `pbr` (другие hotplug не восстановит).

**DNS в режиме «список»:** dnsmasq переключается на публичные резолверы (`1.1.1.1`, `8.8.8.8`). Локальный DNS провайдера отдаёт для заблокированных сайтов адреса, которых нет в `blocked.list` — они не метились fwmark и уходили напрямую, где их блокируют. Прежние настройки DNS сохраняются и возвращаются при `mode_stop` / `delete`.

**Нормализация блоклиста:** перед заливкой в `nft` список чистится — убираются дубликаты, строки с неверной маской (`213.79.65.32/19` → `213.79.64.0/19`), диапазоны, уже покрытые более широким, и IPv6 (set создан как `ipv4_addr`, поэтому nft не принимает IPv6-записи — PBR сейчас только для IPv4). Сколько записей nft принял и сколько отверг — видно в выводе, а не теряется молча.

---

## 🛠️ Решение проблем

### WARP создан, но handshake = 0

Проблема с MTU или блокировкой портов. Решение:

```bash
warp-api.sh mtu
```

Автоматически протестирует MTU 1420 → 1400 → 1380 → 1280.

### Всё логично, но трафик идёт мимо WARP

Сначала смотрите фактическое состояние, а не надписи в интерфейсе:

```bash
warp-api.sh verify
```

Ключевые строки:
- `ip route get 1.1.1.1` должен содержать `dev warp` (в режиме «весь трафик»)
- в режиме «список» маршрутизация включается меткой: `ip route get 8.8.8.8 mark 1` → `dev warp table 100`
- `ip route get <endpoint>` должен идти через **wan**, не через warp — иначе петля и handshake 0
- в режиме «список» `nft list chain inet fw4 prerouting` должен содержать `meta mark set`

### Сайты не открываются

1. **Проверьте статус:**
```bash
warp-api.sh status
```

2. **Убедитесь, что режим правильный:**
```bash
# Если нужен весь трафик через WARP:
warp-api.sh mode_all

# Если нужен только список IP через WARP:
warp-api.sh mode_pbr
```

3. **Проверьте доступность Cloudflare:**
   ```bash
   warp-api.sh ping
   ```

4. **Проверьте DNS.** Локальный резолвер провайдера может отдавать для заблокированных сайтов «свои» CDN-IP (например, `vk.com → 78.111.217.9`), которых нет в `blocked.list`. Такой адрес не метится fwmark и уходит напрямую, где его блокируют. В режиме PBR скрипт сам переключает dnsmasq на публичные резолверы (`1.1.1.1`, `8.8.8.8`) и возвращает прежние настройки при остановке:

   ```bash
   uci get dhcp.@dnsmasq[0].server     # должно быть: 1.1.1.1 8.8.8.8
   nslookup vk.com 192.168.1.1        # IP из 87.240.0.0/16, а не 78.111.x.x
   ```


### Много потерь пакетов

Используйте режим "Весь трафик":

```bash
warp-api.sh mode_all
```

### DNS не работает

Используйте публичный DNS (например, 8.8.8.8):

```bash
uci set network.lan.dns='8.8.8.8 8.8.4.4'
uci commit network
/etc/init.d/network restart
```

### LuCI показывает «TimeoutError» на долгой команде

Ошибка `Error: XHR request timed out` — это таймаут **браузера**: LuCI обрывает RPC-запрос через 20 секунд (`L.env.rpctimeout ?? 20` в `rpc.js`), а не rpcd. Поэтому увеличение `rpcd.@rpcd[0].timeout` не помогает — страница WARP сама поднимает свой лимит до 60 с, а долгие операции ускорены:

| Команда | Было | Стало |
|---|---|---|
| `mode_pbr` | ~19 с | ~7 с |
| `best_endpoint` | ~20+ с | зависит от пинга |

Если страницу открывали старой версией файлов — обновите `overview.js` (он кэшируется в браузере, сделайте жёсткий перезагрузку).

Для ручной установки без инсталятора:

```bash
uci set rpcd.@rpcd[0].timeout='120'
uci commit rpcd
/etc/init.d/rpcd restart
```

### Сайты открываются через раз

Проверьте, что записи реально попали в `nft`-set (часть списка может не приняться, если в нём мусор):

```bash
nft list set inet fw4 blocked_net | grep -c '/'
ip route get 213.79.65.1 mark 1      # должно быть "dev warp table 100"
```

Также проверьте, не включён ли в LuCI **Software flow offloading** — с ним уже установленные потоки обходят правило маркировки, и PBR работает нестабильно.

---

## 📁 Структура проекта

```
warp-luci/
├── files/
│   ├── usr/bin/warp-api.sh              # Основной бэкенд скрипт
│   ├── etc/hotplug.d/iface/
│   │   └── 30-warp-pbr                  # Восстановление режима после ребута
│   └── www/luci-static/resources/view/warp/
│       └── overview.js                  # Веб-интерфейс LuCI
├── install-embedded.sh                  # Установка (рекомендуется)
├── install.sh                           # Установка (то же самое, другой вход)
├── uninstall.sh                         # Однострочное удаление
├── blocked.list                         # Список заблокированных IP
└── README.md                            # Этот файл
```

> `install.sh` и `install-embedded.sh` делают одно и то же — оба скачивают
> `warp-api.sh` и hotplug-скрипт из репозитория. Раньше `install.sh` встраивал
> свою копию скрипта, из-за чего она разошлась с `files/` и получила те же баги,
> что и режим «весь трафик». Сейчас единственный источник правды — каталог `files/`.

> Установщик **не перезаписывает** `/etc/warp/.mode`, поэтому активный режим
> (весь трафик или список) переживает переустановку.

---

## 📊 Размер

- ~13K LuCI веб-интерфейс
- ~10K бэкенд скрипт
- Без дополнительных зависимостей

---

## 📝 Лицензия

MIT

---

## 🤝 Вклад

Баги, улучшения, вопросы — пишите в [Issues](https://github.com/dneese/warp-luci/issues).

---

## 📌 Быстрая справка

| Действие | Команда |
|----------|---------|
| **Установка** | `wget -q -O - https://raw.githubusercontent.com/dneese/warp-luci/main/install-embedded.sh \| sh` |
| **Удаление** | `wget -q -O - https://raw.githubusercontent.com/dneese/warp-luci/main/uninstall.sh \| sh` |
| **Статус** | `warp-api.sh status` |
| **Диагностика** | `warp-api.sh verify` |
| **Подключить** | `warp-api.sh connect` |
| **Весь трафик** | `warp-api.sh mode_all` |
| **Только список** | `warp-api.sh mode_pbr` |
| **Остановить** | `warp-api.sh mode_stop` |
| **Тест MTU** | `warp-api.sh mtu` |
| **Пинг** | `warp-api.sh ping` |
