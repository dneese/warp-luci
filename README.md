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

### ⚡ Способ 1: Одна строка в SSH (САМЫЙ ПРОСТОЙ)

Подключитесь по SSH к роутеру и выполните:

```bash
ssh root@192.168.1.1 "curl -fsSL https://raw.githubusercontent.com/dneese/warp-luci/main/install-embedded.sh | sh"
```

Если `curl` не работает, используйте `wget`:

```bash
ssh root@192.168.1.1 "wget -q -O - https://raw.githubusercontent.com/dneese/warp-luci/main/install-embedded.sh | sh"
```

**Готово! Откройте в браузере:** `http://192.168.1.1/cgi-bin/luci/admin/services/warp`

---

### 📋 Способ 2: Через git (если нужны исходники)

На локальной машине:

```bash
# Скачайте репо
git clone https://github.com/dneese/warp-luci.git
cd warp-luci

# Скопируйте на роутер
scp -r . root@192.168.1.1:/tmp/warp-luci/

# Установите
ssh root@192.168.1.1 "sh /tmp/warp-luci/install-embedded.sh"
```

---

### 📦 Способ 3: Пакетом через APK (для продвинутых)

```bash
# На локальной машине постройте пакет
sh warp-luci/package/build.sh  # → warp-luci_1.0_all.ipk

# Скопируйте пакет
scp warp-luci/*.ipk root@192.168.1.1:/tmp/

# На роутере установите
ssh root@192.168.1.1 "apk add --allow-untrusted /tmp/warp-luci_*.ipk"
```

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
ssh root@192.168.1.1 "warp-api.sh status"

# Подключить WARP (авто-регистрация)
ssh root@192.168.1.1 "warp-api.sh connect"

# Весь трафик через WARP
ssh root@192.168.1.1 "warp-api.sh mode_all"

# Отключить маршрутизацию (туннель есть, но трафик не идет)
ssh root@192.168.1.1 "warp-api.sh mode_stop"

# Удалить WARP (но оставить приложение)
ssh root@192.168.1.1 "warp-api.sh delete"

# Список заблокированных IP/CIDR (для PBR)
ssh root@192.168.1.1 "warp-api.sh pbr_list"

# Добавить IP в список PBR
ssh root@192.168.1.1 "warp-api.sh pbr_add 87.240.0.0/13"

# Удалить строку из PBR (по номеру)
ssh root@192.168.1.1 "warp-api.sh pbr_del 1"

# Обновить список с GitHub
ssh root@192.168.1.1 "warp-api.sh pbr_update"

# Применить PBR (только эти IP через WARP)
ssh root@192.168.1.1 "warp-api.sh pbr_apply"

# Очистить PBR правила
ssh root@192.168.1.1 "warp-api.sh pbr_clear"

# Тест MTU (автоматический подбор оптимального)
ssh root@192.168.1.1 "warp-api.sh mtu"

# Пинг endpoint'ов Cloudflare
ssh root@192.168.1.1 "warp-api.sh ping"
```

---

## 🗑️ Удаление

### ⚡ Одна строка (САМЫЙ ПРОСТОЙ СПОСОБ)

```bash
ssh root@192.168.1.1 "curl -fsSL https://raw.githubusercontent.com/dneese/warp-luci/main/uninstall.sh | sh"
```

Или с `wget`:

```bash
ssh root@192.168.1.1 "wget -q -O - https://raw.githubusercontent.com/dneese/warp-luci/main/uninstall.sh | sh"
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
ssh root@192.168.1.1 "warp-api.sh mtu"
```

Автоматически протестирует MTU 1420 → 1400 → 1380 → 1280.

### Сайты не открываются

1. **Проверьте статус:**
```bash
ssh root@192.168.1.1 "warp-api.sh status"
```

2. **Убедитесь, что режим правильный:**
```bash
# Если нужен весь трафик через WARP:
ssh root@192.168.1.1 "warp-api.sh mode_all"

# Если нужен только список IP через WARP:
ssh root@192.168.1.1 "warp-api.sh pbr_update && warp-api.sh pbr_apply"
```

3. **Проверьте доступность Cloudflare:**
```bash
ssh root@192.168.1.1 "warp-api.sh ping"
```

### Много потерь пакетов

Используйте режим "Весь трафик":

```bash
ssh root@192.168.1.1 "warp-api.sh mode_all"
```

### DNS не работает

Используйте публичный DNS (например, 8.8.8.8):

```bash
ssh root@192.168.1.1 "uci set network.lan.dns='8.8.8.8 8.8.4.4' && uci commit network && /etc/init.d/network restart"
```

---

## 📁 Структура проекта

```
warp-luci/
├── files/
│   ├── usr/bin/warp-api.sh              # Основной бэкенд скрипт
│   └── www/luci-static/resources/view/warp/
│       └── overview.js                  # Веб-интерфейс LuCI
├── install-embedded.sh                  # Однострочная установка
├── uninstall.sh                         # Однострочное удаление
├── install.sh                           # Классическая установка
├── package/
│   ├── Makefile                         # Сборка пакета
│   └── build.sh                         # Скрипт сборки
├── blocked.list                         # Список заблокированных IP (112 записей)
└── README.md                            # Этот файл
```

---

## 📊 Размер

- ~13K LuCI веб-интерфейс
- ~8K бэкенд скрипт
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
| **Установка** | `ssh root@192.168.1.1 "curl -fsSL https://raw.githubusercontent.com/dneese/warp-luci/main/install-embedded.sh \| sh"` |
| **Удаление** | `ssh root@192.168.1.1 "curl -fsSL https://raw.githubusercontent.com/dneese/warp-luci/main/uninstall.sh \| sh"` |
| **Статус** | `ssh root@192.168.1.1 "warp-api.sh status"` |
| **Подключить** | `ssh root@192.168.1.1 "warp-api.sh connect"` |
| **Весь трафик** | `ssh root@192.168.1.1 "warp-api.sh mode_all"` |
| **Список IP** | `ssh root@192.168.1.1 "warp-api.sh pbr_list"` |
| **Тест MTU** | `ssh root@192.168.1.1 "warp-api.sh mtu"` |
