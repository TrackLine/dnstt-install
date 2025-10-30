# 🛰️ DNSTT + SSH автоустановщик для VPS  
Полностью автоматический установщик **DNSTT-сервера** с поддержкой  
**SSH через DNS-туннель** для клиента **DarkTunnel (Android)**.  
Основано на оригинальном проекте [dnstt](https://github.com/gharib-uk/dnstt).

---

## 🚀 Что делает скрипт
- Устанавливает **Go 1.22.x**  
- Собирает `dnstt-server` из исходников [gharib-uk/dnstt](https://github.com/gharib-uk/dnstt)  
- Настраивает `iptables` (редирект DNS-порта `53 → 5300`)  
- Разрешает вход **по паролю** и **под root** в SSH  
- Создаёт **systemd-сервис**  
- Выводит готовые настройки для клиента на Android [**DarkTunnel**](https://play.google.com/store/apps/details?id=net.darktunnel.app&hl=en)

---

## 🧩 Принцип работы DNSTT

**DNSTT (DNS Tunnel Transport)** — это способ передавать интернет-трафик через DNS-запросы.  
Работает даже там, где обычные соединения заблокированы,  
так как DNS обычно разрешён в любой сети.

Схема взаимодействия:

```
[DarkTunnel на Android]
        │
        ▼
   (DNS-запросы к 1.1.1.1)
        │
        ▼
   t.example.com (делегированный поддомен)
        │
        ▼
[DNSTT-сервер на VPS] ──► SSH (localhost:22) ──► Интернет
```

Таким образом, весь трафик с телефона проходит через SSH, а наружу выглядит как обычный DNS.

---

## ⚙️ Требования
- Любой Linux VPS (Ubuntu/Debian рекомендуется)  
- Права `root`  
- Делегированный **поддомен** (например, `t.example.com`)  
- На сервере должны быть **открыты порты 22 (SSH)** и **53 (UDP/TCP)**  
  — это обязательно, чтобы DarkTunnel мог подключиться к твоему серверу.

---

## 🌐 Настройка DNS

Чтобы DNS-запросы доходили до твоего сервера, нужно делегировать поддомен.  
Пример для домена, обслуживаемого Cloudflare:

| Тип | Имя | Значение | TTL |
|------|------|-----------|------|
| **NS** | `t` | `tns.example.com` | Auto |
| **A** | `tns` | `IP твоего VPS` | Auto |

Теперь все запросы к `*.t.example.com` будут идти напрямую на твой VPS,  
где запущен `dnstt-server`.

---

## 🔧 Установка

```bash
sudo -i
apt update && apt install -y curl
curl -fsSL https://raw.githubusercontent.com/TrackLine/dnstt-install/main/setup-dnstt.sh -o /root/setup-dnstt.sh
chmod +x /root/setup-dnstt.sh
/root/setup-dnstt.sh
```

Скрипт задаст вопросы:
- Делегированная DNS-зона (например `t.example.com`)
- Внешний интерфейс (обычно `eth0`)
- Установить пароль root

После завершения скрипт выведет готовые поля для **DarkTunnel**.

---

## 📱 Настройка клиента DarkTunnel

| Поле | Значение |
|------|-----------|
| **Tunnel Type** | SSH Through DNSTT |
| **Target** | `localhost:22@root:<пароль>` |
| **UDP DNS** | `1.1.1.1:53` |
| **Server name** | `t.example.com` |
| **Public key** | `<выведенный скриптом ключ>` |
| **Payload** | оставить **пустым** |

После подключения появится иконка VPN 🔑 — значит, туннель активен.  
Проверить IP можно на [https://ipinfo.io](https://ipinfo.io).

---

## 🧠 Проверка и отладка

```bash
systemctl status dnstt-server
journalctl -u dnstt-server -f
ss -ulpn | grep 5300
iptables -t nat -L PREROUTING -n -v | grep 53
tail -f /var/log/auth.log
```

Если туннель не работает:
- Убедись, что **порты 22 и 53 открыты** в фаерволе и у провайдера VPS.  
- Проверь, что делегирование DNS настроено правильно (`dig NS t.example.com +short`).

---

## ⚠️ Важно

Используйте DNSTT только в рамках закона и правил провайдера.  
Инструмент создан для обхода сетевых ограничений и обеспечения приватности,  
а не для несанкционированного доступа.

---

## ✨ Автор

**by [TrackLine](https://github.com/TrackLine)**  
🛠️ скрипт: `setup-dnstt.sh`  
📦 лицензия: MIT  
💬 для вопросов и предложений — GitHub Issues  
🧩 основано на оригинальном проекте [dnstt](https://github.com/gharib-uk/dnstt)
