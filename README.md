# 🌐 WARP LuCI — Cloudflare WARP для OpenWrt

Простая веб-страница в роутере для лёгкой настройки Cloudflare WARP.

**Настройка в один клик:** статус, подключить, удалить, весь трафик, список, пинг, MTU.

## Возможности

- 📊 **Статус** — тунель активен / handshake / режим (весь трафик / PBR / idle), `warp: up/down`
- ⚡️ **Подключить** — авто-регистрация через публичный API Cloudflare (`wireguard-tools`, ключи остаются на роутере, без передачи)
- 🗑 **Удалить WARP** — интерфейс `warp`, peer `wireguard_warp`, зона `warp`, ключи `/etc/warp/warp.reg`
- 🟢 **Весь трафик** — `route_allowed_ips=1` + `firewall forwarding lan→warp`, ⏸ **Остановить** — `route_allowed_ips=0`
- 📋 **PBR Список** — ручной список заблокированных IP/CIDR (112 записей) → `nftables set + fwmark 0x1` → только они через WARP
- 📏 **MTU-тест** — перебор 1420/1400/1380/1280 с проверкой handshake, авто-возврат на 1280
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

---

## 🛠️ Решение проблем

### WARP создан, но handshake = 0

Проблема с MTU или блокировкой портов. Решение:

```bash
warp-api.sh mtu
```

Автоматически протестирует MTU 1420 → 1400 → 1380 → 1280.

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
├── blocked.list                         # Список заблокированных IP (112 записей)
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
| **Подключить** | `warp-api.sh connect` |
| **Весь трафик** | `warp-api.sh mode_all` |
| **Тест MTU** | `warp-api.sh mtu` |
| **Пинг** | `warp-api.sh ping` |
