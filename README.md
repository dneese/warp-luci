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

**Активный режим** хранится в `/etc/warp/.mode`; после ребута его восстанавливает hotplug-скрипт `/etc/hotplug.d/iface/30-warp-pbr`.

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

---

## 📁 Структура проекта

```
warp-luci/
├── files/
│   ├── usr/bin/warp-api.sh              # Основной бэкенд скрипт
│   └── www/luci-static/resources/view/warp/
│       └── overview.js                  # Веб-интерфейс LuCI
├── install-embedded.sh                  # Встроенная установка (рекомендуется)
├── uninstall.sh                         # Однострочное удаление
├── install.sh                           # Классическая установка
├── blocked.list                         # Список заблокированных IP (список в blocked.list)
└── README.md                            # Этот файл
```

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
