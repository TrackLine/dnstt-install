#!/usr/bin/env bash
# DNSTT + SSH автоустановщик (интерактивный) с генерацией darktunnel:// URI
# и режимом удаления.
# by TrackLine — https://github.com/TrackLine
set -euo pipefail

# ---------- цвета ----------
BOLD="\033[1m"; DIM="\033[2m"; RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"

# ---------- утилиты ----------
ce() { echo -e "$*"; }
die() { ce "\n${RED}[ОШИБКА]${RESET} $*\n"; exit 1; }
ask() { local p="$1" d="${2:-}" a; if [[ -n "$d" ]]; then read -r -p "$(printf "%s [%s]: " "$p" "$d")" a || true; echo "${a:-$d}"; else read -r -p "$(printf "%s: " "$p")" a || true; echo "$a"; fi; }

# скрытый ввод: подтверждение уводим в STDERR, чтобы не попадало в переменную
ask_secret_show() {
  local prompt="$1" val
  read -r -s -p "$(printf "%s: " "$prompt")" val || true
  echo >&2               # перевод строки в stderr
  echo "Введено: $val" >&2
  echo >&2
  printf '%s\n' "$val"   # только значение уходит в stdout (забирать через командную подстановку)
}

require_root() { [[ $EUID -eq 0 ]] || die "Запустите скрипт от root (sudo -i)"; }
detect_iface() { ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'; }
cmd_exists() { command -v "$1" >/dev/null 2>&1; }

# ---------- iptables ----------
iptables_add_rules() {
  local EXT_IF="$1"
  iptables -C INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 5300 -j ACCEPT
  iptables -C INPUT -p tcp --dport 5300 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 5300 -j ACCEPT
  iptables -C INPUT -p udp --dport 53   -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 53 -j ACCEPT
  iptables -C INPUT -p tcp --dport 53   -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 53 -j ACCEPT
  iptables -C INPUT -p tcp --dport 22   -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 22 -j ACCEPT
  iptables -t nat -C PREROUTING -i "$EXT_IF" -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || iptables -t nat -I PREROUTING -i "$EXT_IF" -p udp --dport 53 -j REDIRECT --to-ports 5300
  iptables -t nat -C PREROUTING -i "$EXT_IF" -p tcp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || iptables -t nat -I PREROUTING -i "$EXT_IF" -p tcp --dport 53 -j REDIRECT --to-ports 5300
}
iptables_del_rule() { if iptables "$@" -C 2>/dev/null; then iptables "$@" -D; fi; }
iptables_del_nat_rule() { if iptables -t nat "$@" -C 2>/dev/null; then iptables -t nat "$@" -D; fi; }
iptables_remove_rules() {
  local EXT_IF="$1"
  iptables_del_rule -I INPUT -p udp --dport 5300 -j ACCEPT || true
  iptables_del_rule -I INPUT -p tcp --dport 5300 -j ACCEPT || true
  iptables_del_rule -I INPUT -p udp --dport 53   -j ACCEPT || true
  iptables_del_rule -I INPUT -p tcp --dport 53   -j ACCEPT || true
  iptables_del_nat_rule -I PREROUTING -i "$EXT_IF" -p udp --dport 53 -j REDIRECT --to-ports 5300 || true
  iptables_del_nat_rule -I PREROUTING -i "$EXT_IF" -p tcp --dport 53 -j REDIRECT --to-ports 5300 || true
}
save_iptables() {
  if cmd_exists netfilter-persistent; then netfilter-persistent save >/dev/null 2>&1 || true
  else iptables-save >/etc/iptables/rules.v4 2>/dev/null || true
  fi
}

# ---------- удаление ----------
uninstall_all() {
  require_root
  ce "\n${YELLOW}[UNINSTALL]${RESET} Начинаю удаление DNSTT и очистку системы…"
  local EXT_IF_UN; EXT_IF_UN="$(detect_iface)"; EXT_IF_UN="${EXT_IF_UN:-eth0}"

  if systemctl is-enabled --quiet dnstt-server 2>/dev/null || systemctl is-active --quiet dnstt-server 2>/dev/null; then
    systemctl stop dnstt-server || true
    systemctl disable dnstt-server || true
  fi
  rm -f /etc/systemd/system/dnstt-server.service
  systemctl daemon-reload || true

  rm -f /usr/local/bin/dnstt-server
  rm -rf /opt/dnstt
  rm -rf /etc/dnstt
  rm -f /root/darktunnel-uri.txt

  if [[ -f /etc/ssh/sshd_config.d/99-dnstt.conf ]]; then
    local DEL_SSH; DEL_SSH="$(ask 'Удалить файл /etc/ssh/sshd_config.d/99-dnstt.conf? (yes/no)' 'no')"
    if [[ "$DEL_SSH" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then
      rm -f /etc/ssh/sshd_config.d/99-dnstt.conf
      systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null || true
    fi
  fi

  iptables_remove_rules "$EXT_IF_UN"
  local DEL_22; DEL_22="$(ask 'Удалить правило открытия порта 22 (SSH)? (ОПАСНО) (yes/no)' 'no')"
  if [[ "$DEL_22" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then iptables_del_rule -I INPUT -p tcp --dport 22 -j ACCEPT || true; fi
  save_iptables

  if [[ -d /usr/local/go ]]; then
    local DEL_GO; DEL_GO="$(ask 'Удалить установленный Go из /usr/local/go? (yes/no)' 'no')"
    [[ "$DEL_GO" =~ ^([Yy][Ee][Ss]|[Yy])$ ]] && { rm -rf /usr/local/go; rm -f /etc/profile.d/go.sh; }
  fi

  clear
  ce "${GREEN}${BOLD}Удаление завершено.${RESET}\n"
  ce "${DIM}by TrackLine — https://github.com/TrackLine${RESET}"
  exit 0
}

# ---------- аргументы ----------
if [[ "${1:-}" =~ ^(-u|--uninstall)$ ]]; then uninstall_all; fi

# ---------- установка ----------
require_root
ce "\n${BOLD}=============================================="
ce "  DNSTT сервер: автоустановка (интерактивно)"
ce "  by TrackLine — https://github.com/TrackLine"
ce "==============================================${RESET}\n"

DEFAULT_GO="1.22.6"
GO_VER="$(ask 'Версия Go для установки' "$DEFAULT_GO")"; [[ -z "$GO_VER" ]] && GO_VER="$DEFAULT_GO"

ZONE=""; while [[ -z "$ZONE" ]]; do ZONE="$(ask 'Делегированная DNS-зона (server name), напр. t.example.com' '')"; done

DETECTED_IF="$(detect_iface)"; EXT_IF="$(ask 'Внешний сетевой интерфейс для редиректа 53→5300' "${DETECTED_IF:-eth0}")"
[[ -z "$EXT_IF" ]] && die "Не удалось определить интерфейс — укажи вручную."

PROFILE_NAME="$(ask 'Имя профиля в DarkTunnel' 'Default')"

SET_ROOT_PASS="$(ask 'Задать/сменить пароль root сейчас? (yes/no)' 'yes')"
ROOT_PASS=""
if [[ "$SET_ROOT_PASS" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then
  while [[ -z "$ROOT_PASS" ]]; do
    ROOT_PASS="$(ask_secret_show 'Новый пароль root')"
    [[ -z "$ROOT_PASS" ]] && ce "Пароль не может быть пустым."
  done
fi

PASS_FOR_URI="$ROOT_PASS"
if [[ -z "$PASS_FOR_URI" ]]; then
  PASS_FOR_URI="$(ask_secret_show 'Текущий пароль root (для ссылки DarkTunnel; можно оставить пустым)')"
fi
[[ -z "$PASS_FOR_URI" ]] && PASS_FOR_URI=""

UDP_DNS="$(ask 'Публичный резолвер (подсказка для README/клиента)' '1.1.1.1:53')"

ce "\nСводка параметров:"
ce "  Зона (server name):  ${CYAN}${ZONE}${RESET}"
ce "  Внешний интерфейс:   ${CYAN}${EXT_IF}${RESET}"
ce "  Версия Go:           ${CYAN}${GO_VER}${RESET}"
ce "  Имя профиля:         ${CYAN}${PROFILE_NAME}${RESET}"
ce "  Изменять пароль root:${CYAN} ${SET_ROOT_PASS}${RESET}"
read -r -p $'\nНажмите Enter для продолжения (Ctrl+C — отмена) ' _

# 1) Пакеты
ce "\n${YELLOW}[1/9]${RESET} Установка базовых пакетов…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl git ca-certificates build-essential pkg-config iptables-persistent lsof python3

# 2) Go
ce "\n${YELLOW}[2/9]${RESET} Установка Go ${GO_VER}…"
rm -rf /usr/local/go || true
curl -fsSLo /tmp/go.tgz "https://go.dev/dl/go${GO_VER}.linux-amd64.tar.gz" || die "Не получилось скачать Go ${GO_VER}"
tar -C /usr/local -xzf /tmp/go.tgz
echo 'export PATH=/usr/local/go/bin:$PATH' >/etc/profile.d/go.sh
# shellcheck disable=SC1091
source /etc/profile.d/go.sh
go version >/dev/null || die "Go не установлен корректно"

# 3) dnstt
ce "\n${YELLOW}[3/9]${RESET} Сборка dnstt-server… (оригинал: https://github.com/gharib-uk/dnstt)"
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

# 4) ключи
ce "\n${YELLOW}[4/9]${RESET} Генерация ключей сервера…"
install -d -m 700 /etc/dnstt
if [[ ! -f /etc/dnstt/server.key || ! -f /etc/dnstt/server.pub ]]; then
  dnstt-server -gen-key -privkey-file /etc/dnstt/server.key -pubkey-file /etc/dnstt/server.pub
  chmod 600 /etc/dnstt/server.key
fi
PUBKEY="$(tr -d '\n\r' </etc/dnstt/server.pub)"

# 5) ssh
ce "\n${YELLOW}[5/9]${RESET} Настройка sshd (разрешаем пароль и root-вход)…"
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

# 6) iptables
ce "\n${YELLOW}[6/9]${RESET} Настройка iptables (53→5300 на интерфейсе ${EXT_IF})…"
iptables_add_rules "$EXT_IF"
save_iptables

# 7) systemd
ce "\n${YELLOW}[7/9]${RESET} Создание systemd-сервиса dnstt-server (:5300 → 127.0.0.1:22)…"
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

# 8) DarkTunnel URI — через env (безопасно) + САНИТИЗАЦИЯ
ce "\n${YELLOW}[8/9]${RESET} Генерация конфигурации DarkTunnel (URI)…"
command -v python3 >/dev/null 2>&1 || die "Нужен python3"
# санитизация (убрать \r \n и управляющие символы)
clean_str() { printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037\177' | tr -d '\r\n'; }
ZONE="$(clean_str "$ZONE")"
PROFILE_NAME="$(clean_str "$PROFILE_NAME")"
PASS_FOR_URI="$(clean_str "$PASS_FOR_URI")"
PUBKEY="$(tr -d '\n\r' </etc/dnstt/server.pub | tr -d '\000-\010\013\014\016-\037\177')"

URI="$(
  ZONE_ENV="$ZONE" PUBKEY_ENV="$PUBKEY" PROFILE_ENV="$PROFILE_NAME" PASS_ENV="$PASS_FOR_URI" \
  python3 - <<'PY'
import os, json, base64
cfg = {
  "type": "SSH",
  "name": os.environ.get("PROFILE_ENV","Default"),
  "sshTunnelConfig": {
    "sshConfig": {"username": "root", "password": os.environ.get("PASS_ENV","")},
    "injectConfig": {"mode": "DNSTT",
                     "dnsttServerName": os.environ["ZONE_ENV"],
                     "dnsttPublicKey": os.environ["PUBKEY_ENV"],
                     "payload": ""}
  },
  "sshDnsttTunnelConfig": {
    "sshConfig": {"username": "root", "password": os.environ.get("PASS_ENV","")},
    "dnsttConfig": {"serverName": os.environ["ZONE_ENV"], "publicKey": os.environ["PUBKEY_ENV"]}
  }
}
raw = json.dumps(cfg, ensure_ascii=False).encode("utf-8")
b64url = base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")
print("darktunnel://" + b64url)
PY
)"
echo "$URI" > /root/darktunnel-uri.txt

# 9) финал
clear
SERVER_IPv4="$(ip -4 addr show "$EXT_IF" | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"
[[ -z "$SERVER_IPv4" ]] && SERVER_IPv4="<IP_сервера>"

ce "${GREEN}${BOLD}Готово! DNSTT-сервер установлен и запущен.${RESET}\n"
ce "${BOLD}Важные напоминания:${RESET}"
ce "  • Откройте порты ${BOLD}22 (SSH) и 53 (UDP/TCP)${RESET} в панели провайдера и фаерволе."
ce "  • Делегируйте поддомен (NS) на VPS для зоны: ${CYAN}${ZONE}${RESET}."
ce "  • dnstt-server слушает: ${CYAN}:5300${RESET}; редирект: ${CYAN}53 → 5300${RESET} на ${CYAN}${EXT_IF}${RESET}."
ce "  • Оригинальный проект DNSTT: ${CYAN}https://github.com/gharib-uk/dnstt${RESET}\n"

ce "${BOLD}Подсказки по проверке:${RESET}"
ce "  ss -ulpn | grep 5300"
ce "  iptables -t nat -L PREROUTING -n -v | grep ':53 '"
ce "  systemctl status dnstt-server"
ce "  journalctl -u dnstt-server -f\n"

ce "${BOLD}Параметры для DarkTunnel:${RESET}"
ce "  Tunnel Type : ${CYAN}SSH Through DNSTT${RESET}"
ce "  Target      : ${CYAN}localhost:22@root:<твой_пароль_root>${RESET}"
ce "  UDP DNS     : ${CYAN}${UDP_DNS}${RESET}"
ce "  Server name : ${CYAN}${ZONE}${RESET}"
ce "  Public key  : ${CYAN}${PUBKEY}${RESET}"
ce "  Payload     : ${CYAN}<пусто>${RESET}\n"

ce "${BOLD}Готовая ссылка для импорта (darktunnel://):${RESET}"
ce "${CYAN}${URI}${RESET}\n"
ce "Сохранено в файл: ${CYAN}/root/darktunnel-uri.txt${RESET}\n"
ce "${DIM}by TrackLine — https://github.com/TrackLine${RESET}"