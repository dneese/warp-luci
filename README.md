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

## 🚀 Установка (однострочная)

### Вариант 1: Прямо на роутере (самый простой)

Подключитесь по SSH на роутер и выполните одну команду:

```bash
ssh root@192.168.1.1 "sh -c 'curl -fsSL https://raw.githubusercontent.com/dneese/warp-luci/main/quick-install.sh | sh'"
```

Или если curl не работает:

```bash
ssh root@192.168.1.1 "sh -c 'wget -q -O - https://raw.githubusercontent.com/dneese/warp-luci/main/quick-install.sh | sh'"
```

### Вариант 2: С локальной машины

```bash
# Скачайте репо
git clone https://github.com/dneese/warp-luci.git
cd warp-luci

# Скопируйте и установите
scp -r . root@192.168.1.1:/tmp/warp-luci/
ssh root@192.168.1.1 "sh /tmp/warp-luci/install.sh"
```

### Вариант 3: Пакетом (через APK/OPKG)

```bash
# На локальной машине
sh warp-luci/package/build.sh  # → warp-luci_1.0_all.ipk

# Скопируйте пакет на роутер
scp warp-luci/*.ipk root@192.168.1.1:/tmp/

# На роутере установите
ssh root@192.168.1.1 "apk add --allow-untrusted /tmp/warp-luci_*.ipk || opkg install /tmp/*.ipk"
```

## 📖 Использование

После установки откройте в браузере:

```
http://192.168.1.1/cgi-bin/luci/admin/services/warp
```

Или через LuCI: **Services → WARP**

### CLI команды

```bash
ssh root@192.168.1.1 "warp-api.sh status"      # Статус туннеля
ssh root@192.168.1.1 "warp-api.sh connect"     # Подключить WARP
ssh root@192.168.1.1 "warp-api.sh delete"      # Удалить WARP
ssh root@192.168.1.1 "warp-api.sh mode_all"    # Весь трафик через WARP
ssh root@192.168.1.1 "warp-api.sh mode_stop"   # Отключить маршрутизацию
ssh root@192.168.1.1 "warp-api.sh pbr_list"    # Список заблокированных IP
ssh root@192.168.1.1 "warp-api.sh pbr_add 87.240.0.0/13"  # Добавить IP в PBR
ssh root@192.168.1.1 "warp-api.sh pbr_del 1"   # Удалить строку из PBR
ssh root@192.168.1.1 "warp-api.sh pbr_update"  # Обновить список с GitHub
ssh root@192.168.1.1 "warp-api.sh pbr_apply"   # Применить PBR
ssh root@192.168.1.1 "warp-api.sh mtu"         # Тест MTU
ssh root@192.168.1.1 "warp-api.sh ping"        # Пинг endpoint'ов
```

## 🔧 Требования

- ImmortalWrt/OpenWrt 21.02+
- `curl` или `wget` или `uclient-fetch`
- `wireguard-tools` (устанавливается автоматически)
- `kmod-wireguard` (ядро, обычно предустановлено)

## 📁 Структура

```
warp-luci/
├── files/
│   ├── usr/bin/warp-api.sh              # Основной бэкенд скрипт
│   └── www/luci-static/resources/view/warp/
│       └── overview.js                  # Веб-интерфейс LuCI
├── quick-install.sh                     # Однострочная установка
├── install.sh                           # Классическая установка
├── package/
│   ├── Makefile                         # Сборка пакета
│   └── build.sh                         # Скрипт сборки
├── blocked.list                         # Список заблокированных IP (112 записей)
└── README.md                            # Этот файл
```

## 📊 Размер

- ~13K LuCI веб-интерфейс
- ~8K бэкенд скрипт
- Без дополнительных зависимостей

## 🛠️ Решение проблем

### WARP создан, но handshake = 0

Проблема с MTU или блокировкой портов. Решение:

```bash
ssh root@192.168.1.1 "warp-api.sh mtu"
```

Автоматически протестирует MTU 1420 → 1400 → 1380 → 1280.

### Сайты все еще не открываются

1. Убедитесь, что IP сайта добавлен в список PBR:
```bash
ssh root@192.168.1.1 "warp-api.sh pbr_list | grep 87.240"
```

2. Обновите список заблокированных IP:
```bash
ssh root@192.168.1.1 "warp-api.sh pbr_update"
ssh root@192.168.1.1 "warp-api.sh pbr_apply"
```

3. Проверьте DNS (иногда блокируется на уровне DNS):
```bash
ssh root@192.168.1.1 "nslookup vk.com 8.8.8.8"
```

### Много потерь пакетов

Используйте режим "Весь трафик", а не PBR:

```bash
ssh root@192.168.1.1 "warp-api.sh mode_all"
```

## 📝 Лицензия

MIT

## 🤝 Вклад

Баги, улучшения, вопросы — пишите в Issues.

---

**Быстрая установка:**
```bash
ssh root@192.168.1.1 "sh -c 'curl -fsSL https://raw.githubusercontent.com/dneese/warp-luci/main/quick-install.sh | sh'"
```
