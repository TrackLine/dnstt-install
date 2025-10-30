# 🛰️ DNSTT + SSH автоустановщик для VPS
**Автор:** [TrackLine](https://github.com/TrackLine)  
**Оригинальный проект:** [gharib-uk/dnstt](https://github.com/gharib-uk/dnstt)

Полностью автоматический установщик **DNSTT-сервера** с поддержкой **SSH через DNS-туннель** для клиента [**DarkTunnel (Android)**](https://play.google.com/store/apps/details?id=net.darktunnel.app&pcampaignid=web_share).  
Скрипт интерактивный, на русском, **автоматически генерирует ссылку** `darktunnel://…` для импорта профиля и содержит **режим удаления** (возврат VPS в исходное состояние).

---

## 🚀 Что делает скрипт
- Ставит **Go 1.22.x** (удаляется по желанию в режиме деинсталляции).
- Собирает `dnstt-server` из исходников (репозиторий см. выше).
- Генерирует ключи `server.key` и `server.pub`.
- Настраивает `iptables`: **редирект 53 → 5300** и открывает порты.
- Разрешает **вход по паролю** и **root‑вход** в SSH (создаётся отдельный drop‑in `sshd_config.d/99-dnstt.conf`).
- Создаёт и запускает **systemd‑сервис** `dnstt-server`.
- **Генерирует ссылку** вида `darktunnel://…` (формат экспорта DarkTunnel) и сохраняет её в `/root/darktunnel-uri.txt`.
- Имеет **режим удаления** `--uninstall`: очищает сервис/бинарник/ключи, сворачивает правила iptables, по желанию удаляет drop‑in SSH и Go.

---

## ⚙️ Требования
- VPS с **Ubuntu/Debian** и правами `root`.
- Делегированный **поддомен** (например `t.example.com`).
- На сервере должны быть **открыты порты 22 (SSH)** и **53 (UDP/TCP)** на фаерволе и у провайдера.

---

## 🌐 Настройка DNS (пример с Cloudflare)

Делегируйте поддомен на свой VPS. Пример записи:

| Тип | Имя | Значение | TTL |
|---|---|---|---|
| **NS** | `t` | `tns.example.com` | Auto |
| **A**  | `tns` | `IP вашего VPS` | Auto |

Итог: запросы к `*.t.example.com` придут прямо на ваш VPS, где работает `dnstt-server`.

---

## 🔧 Установка

```bash
sudo -i
apt update && apt install -y curl
curl -fsSL https://raw.githubusercontent.com/TrackLine/dnstt-install/main/dnstt-setup.sh -o /root/dnstt-setup.sh
chmod +x /root/dnstt-setup.sh
/root/dnstt-setup.sh
```

Скрипт спросит:
- Делегированную зону (например `t.example.com`).
- Внешний интерфейс (чаще всего `eth0`).
- Имя профиля для DarkTunnel.
- Установить/не менять пароль `root` (и/или ввести текущий для генерации ссылки).

В конце экран очистится и вы увидите цветной итог:
- параметры для клиента,
- **готовую ссылку для импорта** `darktunnel://…`,
- путь к файлу: `/root/darktunnel-uri.txt`.

---

## 📱 Импорт профиля в DarkTunnel

Вариант 1 — через ссылку:
1. Скопируйте вывод `darktunnel://…` на телефон (чат/почта/QR).
2. Откройте ссылку — DarkTunnel подхватит конфиг.

Вариант 2 — вручную (если нужно):
| Поле | Значение |
|---|---|
| **Tunnel Type** | SSH Through DNSTT |
| **Target** | `localhost:22@root:<ваш_пароль_root>` |
| **UDP DNS** | `1.1.1.1:53` *(или свой публичный резолвер)* |
| **Server name** | `t.example.com` |
| **Public key** | содержимое `server.pub` (скрипт выведет) |
| **Payload** | оставить пустым |

---

## 🧩 Как это работает (коротко)

DNSTT упаковывает трафик в DNS‑запросы, которые почти всегда разрешены в сети.  
Схема потока:

```
[DarkTunnel на Android] --DNS--> t.example.com (NS делегирован на VPS)
                               |
                               v
                       [DNSTT-сервер на VPS] -> SSH (127.0.0.1:22) -> Интернет
```

Снаружи трафик выглядит как обычный DNS.

---

## 🧠 Проверка и отладка

```bash
systemctl status dnstt-server
journalctl -u dnstt-server -f
ss -ulpn | grep 5300
iptables -t nat -L PREROUTING -n -v | grep ':53 '
tail -f /var/log/auth.log
```

Если не коннектится:
- Проверьте, что **порты 22 и 53 (UDP/TCP) открыты**.
- Убедитесь в корректном делегировании (`dig NS t.example.com +short`).
- Смотрите логи `dnstt-server` и `sshd`.

---

## 🧼 Удаление (возврат к исходному состоянию)

```bash
/root/dnstt-setup.sh --uninstall
# или
/root/dnstt-setup.sh -u
```

Что делает деинсталляция:
- Останавливает/удаляет сервис `dnstt-server`.
- Удаляет `/usr/local/bin/dnstt-server`, `/opt/dnstt`, `/etc/dnstt`.
- Удаляет редиректы/открытия портов (53/5300) из `iptables` и сохраняет правила.
- **Не** удаляет правило порта 22 без явного согласия (чтобы не потерять доступ).
- По желанию удаляет drop‑in `sshd_config.d/99-dnstt.conf` и установленный Go.

---

## ⚠️ Дисклеймер

Используйте DNSTT в рамках закона и политик провайдера. Проект предназначен для обеспечения приватности и работы в ограниченных сетях, а не для несанкционированных действий.

---

## ✨ Автор

**by [TrackLine](https://github.com/TrackLine)**  
🧰 скрипт: `dnstt-setup.sh`  
📦 лицензия: MIT  
🧩 основано на [gharib-uk/dnstt](https://github.com/gharib-uk/dnstt)
