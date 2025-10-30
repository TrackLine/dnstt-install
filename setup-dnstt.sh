#!/usr/bin/env bash
# DNSTT + SSH автоустановщик (интерактивный)
# by TrackLine — https://github.com/TrackLine
set -euo pipefail

### ---------- функции утилиты ----------
ce() { echo -e "$*"; }
die() { ce "\n[ОШИБКА] $*\n"; exit 1; }
ask() { # $1=prompt  $2=default  -> echo answer
  local p="$1" d="${2:-}" a
  if [[ -n "$d" ]]; then
    read -r -p "$(printf "%s [%s]: " "$p" "$d")" a || true
    echo "${a:-$d}"
  else
    read -r -p "$(printf "%s: " "$p")" a || true
    echo "$a"
  fi
}
ask_secret() { # $1=prompt
  local a
  read -r -s -p "$(printf "%s: " "$1")" a || true
  echo
  echo "$a"
}

require_root() { [[ $EUID -eq 0 ]] || die "Запустите скрипт от root (sudo -i)"; }
cmd_exists() { command -v "$1" >/dev/null 2>&1; }

detect_iface() {
  ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

### ---------- старт ----------
require_root
ce "\n=============================================="
ce "  DNSTT сервер: автоустановка (интерактивно)"
ce "  by TrackLine — https://github.com/TrackLine"
ce "==============================================\n"

# 1) Сбор входных данных
DEFAULT_GO="1.22.6"
GO_VER="$(ask 'Версия Go для установки' "$DEFAULT_GO")"
[[ -z "$GO_VER" ]] && GO_VER="$DEFAULT_GO"

ZONE=""
while [[ -z "$ZONE" ]]; do
  ZONE="$(ask 'Укажи делегированный поддомен (зона для DNSTT), напр. t.example.com' '')"
done

DETECTED_IF="$(detect_iface)"
EXT_IF="$(ask 'Внешний сетевой интерфейс (для редиректа 53→5300)' "${DETECTED_IF:-eth0}")"
[[ -z "$EXT_IF" ]] && die "Не удалось определить интерфейс — укажи вручную."

SET_ROOT_PASS="$(ask 'Задать/сменить пароль root? (yes/no)' 'yes')"
ROOT_PASS=""
if [[ "$SET_ROOT_PASS" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then
  while [[ -z "$ROOT_PASS" ]]; do
    ROOT_PASS="$(ask_secret 'Новый пароль root')"
    [[ -z "$ROOT_PASS" ]] && ce "Пароль не может быть пустым."
  done
fi

ce "\nСводка параметров:"
ce "  Зона (server name):  $ZONE"
ce "  Внешний интерфейс:   $EXT_IF"
ce "  Версия Go:           $GO_VER"
ce "  Пароль root менять:  $SET_ROOT_PASS"
read -r -p $'\nПродолжить установку? [Enter=Да / Ctrl+C=Отмена] ' _

### ---------- 2) Базовые пакеты ----------
ce "\n[1/8] Установка базовых пакетов..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl git ca-certificates build-essential pkg-config \
                   iptables-persistent lsof

### ---------- 3) Установка Go ----------
ce "\n[2/8] Установка Go ${GO_VER}..."
rm -rf /usr/local/go || true
curl -fsSLo /tmp/go.tgz "https://go.dev/dl/go${GO_VER}.linux-amd64.tar.gz" \
  || die "Не получилось скачать Go ${GO_VER}"
tar -C /usr/local -xzf /tmp/go.tgz
echo 'export PATH=/usr/local/go/bin:$PATH' >/etc/profile.d/go.sh
# shellcheck source=/dev/null
source /etc/profile.d/go.sh
go version || die "Go не установлен корректно"

### ---------- 4) Сборка dnstt-server ----------
ce "\n[3/8] Сборка dnstt-server..."
install -d /opt/dnstt
if [[ ! -d /opt/dnstt/.git ]]; then
  git clone https://github.com/gharib-uk/dnstt.git /opt/dnstt
else
  git -C /opt/dnstt pull --ff-only
fi
cd /opt/dnstt/dnstt-server
go clean -modcache
go build -o /usr/local/bin/dnstt-server
chmod 755 /usr/local/bin/dnstt-server
command -v dnstt-server >/dev/null || die "dnstt-server не собрался"

### ---------- 5) Ключи DNSTT ----------
ce "\n[4/8] Генерация ключей сервера..."
install -d -m 700 /etc/dnstt
if [[ ! -f /etc/dnstt/server.key || ! -f /etc/dnstt/server.pub ]]; then
  dnstt-server -gen-key -privkey-file /etc/dnstt/server.key -pubkey-file /etc/dnstt/server.pub
  chmod 600 /etc/dnstt/server.key
fi
PUBKEY="$(tr -d '\n\r' </etc/dnstt/server.pub)"

### ---------- 6) SSH: разрешить пароль и root-вход ----------
ce "\n[5/8] Настройка sshd: разрешение входа по паролю и root..."
install -d /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-dnstt.conf <<'EOF'
PasswordAuthentication yes
PermitRootLogin yes
ChallengeResponseAuthentication no
UsePAM yes
EOF
systemctl reload ssh || systemctl restart ssh || true

if [[ -n "$ROOT_PASS" ]]; then
  echo "root:${ROOT_PASS}" | chpasswd
  ce "  Пароль root установлен."
fi

### ---------- 7) iptables: редирект 53→5300, открыть 5300 ----------
ce "\n[6/8] Настройка iptables (редирект 53→5300 на интерфейсе ${EXT_IF})..."
# Разрешим доступ к 5300 (на всякий случай TCP и UDP)
iptables -I INPUT -p udp --dport 5300 -j ACCEPT || true
iptables -I INPUT -p tcp --dport 5300 -j ACCEPT || true
# Редирект входящих DNS-пакетов на 5300
iptables -t nat -I PREROUTING -i "$EXT_IF" -p udp --dport 53 -j REDIRECT --to-ports 5300 || true
iptables -t nat -I PREROUTING -i "$EXT_IF" -p tcp --dport 53 -j REDIRECT --to-ports 5300 || true
# Сохранить правила
netfilter-persistent save >/dev/null 2>&1 || iptables-save >/etc/iptables/rules.v4

### ---------- 8) systemd-сервис ----------
ce "\n[7/8] Создание systemd-сервиса dnstt-server (:5300 → SSH 127.0.0.1:22)..."
cat >/etc/systemd/system/dnstt-server.service <<EOF
[Unit]
Description=DNSTT Server (by TrackLine)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/dnstt-server -udp :5300 -privkey-file /etc/dnstt/server.key ${ZONE} 127.0.0.1:22
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now dnstt-server
sleep 1
systemctl --no-pager --full status dnstt-server | sed -n '1,20p' || true

### ---------- 9) Финальный вывод и подсказки ----------
SERVER_IPv4="$(ip -4 addr show "$EXT_IF" | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"
[[ -z "$SERVER_IPv4" ]] && SERVER_IPv4="<IP_сервера>"

ce "\n[8/8] Готово! DNSTT-сервер запущен."
ce "Проверь, что внешний DNS идёт на сервер (редирект 53→5300 активен)."
ce "Ключи: /etc/dnstt/server.key (секрет), /etc/dnstt/server.pub (публичный)\n"

ce "================= ВВОД В DarkTunnel ================="
ce " Tunnel Type  :  SSH Through DNSTT"
ce " target       :  localhost:22@root:<ТВОЙ_ПАРОЛЬ_ROOT>"
ce "               (у тебя сейчас: ${ROOT_PASS:-'<не меняли>'})"
ce " udp dns      :  1.1.1.1:53    (или 8.8.8.8:53)"
ce " server name  :  ${ZONE}"
ce " public key   :  ${PUBKEY}"
ce " payload      :  (оставить ПУСТЫМ)"
ce "=====================================================\n"

ce "Памятка:"
ce "  • Проверка прослушки:  ss -ulpn | grep 5300"
ce "  • Логи сервиса:       journalctl -u dnstt-server -f"
ce "  • Проверка редиректа: iptables -t nat -L PREROUTING -n -v | grep ':53 '"
ce "  • SSH локально:       ssh root@127.0.0.1   (пароль: ты указал выше)"
ce "  • Если Android не включает VPN — проверь, что payload пустой.\n"

ce "by TrackLine — https://github.com/TrackLine"