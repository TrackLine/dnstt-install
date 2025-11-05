# 🛰️ DNSTT + SSH Auto-Installer for VPS

**Language:** [🇬🇧 English](README.md) | [🇷🇺 Русский](README.ru.md)

**Author:** [TrackLine](https://github.com/TrackLine)  
[**Say Thanks**](https://shalenkov.dev/about)

**Original Project:** [gharib-uk/dnstt](https://github.com/gharib-uk/dnstt)

Fully automatic installer for **DNSTT server** with **SSH over DNS tunnel** support for the [**DarkTunnel (Android)**](https://play.google.com/store/apps/details?id=net.darktunnel.app&pcampaignid=web_share) client.  
The script is interactive, **automatically generates** a `darktunnel://…` link for profile import and includes an **uninstall mode** (returns VPS to its original state).

---

## 🚀 What the Script Does
- Installs **Go 1.22.x** (can be removed during uninstall if desired).
- Builds `dnstt-server` from source (see repository above).
- Generates `server.key` and `server.pub` keys.
- Configures `iptables`: **redirect 53 → 5300** and opens ports.
- Enables **password authentication** and **root login** in SSH (creates a separate drop-in `sshd_config.d/99-dnstt.conf`).
- Creates and starts the **systemd service** `dnstt-server`.
- **Generates a link** in the format `darktunnel://…` (DarkTunnel export format) and saves it to `/root/darktunnel-uri.txt`.
- Has an **uninstall mode** `--uninstall`: cleans up service/binary/keys, removes iptables rules, optionally removes SSH drop-in and Go.

---

## ⚙️ Requirements
- VPS with **Ubuntu/Debian** and `root` privileges.
- A delegated **subdomain** (e.g., `t.example.com`).
- Ports **22 (SSH)** and **53 (UDP/TCP)** must be **open** on the firewall and with the provider.

---

## 🌐 DNS Configuration (Cloudflare Example)

Delegate a subdomain to your VPS. Example record:

| Type | Name | Value | TTL |
|---|---|---|---|
| **NS** | `t` | `tns.example.com` | Auto |
| **A**  | `tns` | `Your VPS IP` | Auto |

Result: requests to `*.t.example.com` will go directly to your VPS, where `dnstt-server` is running.

---

## 🔧 Installation

```bash
sudo -i
apt update && apt install -y curl
curl -fsSL https://dnstt.echo0.dev -o /root/dnstt-setup.sh
chmod +x /root/dnstt-setup.sh
/root/dnstt-setup.sh
```

The script will ask for:
- Delegated zone (e.g., `t.example.com`).
- External interface (usually `eth0`).
- Profile name for DarkTunnel.
- Set/keep `root` password (and/or enter current one for link generation).

At the end, the screen will clear and you'll see a colored summary:
- client parameters,
- **ready-to-import link** `darktunnel://…`,
- file path: `/root/darktunnel-uri.txt`.

---

## 📱 Importing Profile to DarkTunnel

Option 1 — via link:
1. Copy the `darktunnel://…` output to your phone (chat/email/QR) to clipboard.
2. Open DarkTunnel, click the button in the top right (three dots), Config -> Import -> Clipboard — DarkTunnel will pick up the config.

Option 2 — manually (if needed):
| Field | Value |
|---|---|
| **Tunnel Type** | SSH Through DNSTT |
| **Target** | `localhost:22@root:<your_root_password>` |
| **UDP DNS** | `1.1.1.1:53` *(or your public resolver)* |
| **Server name** | `t.example.com` |
| **Public key** | contents of `server.pub` (script will output) |
| **Payload** | leave empty |

---

## 🧩 How It Works (Brief)

DNSTT packages traffic into DNS queries, which are almost always allowed in networks.  
Flow diagram:

```
[DarkTunnel on Android] --DNS--> t.example.com (NS delegated to VPS)
                               |
                               v
                       [DNSTT-server on VPS] -> SSH (127.0.0.1:22) -> Internet
```

From the outside, traffic looks like regular DNS.

---

## 🧠 Testing and Debugging

```bash
systemctl status dnstt-server
journalctl -u dnstt-server -f
ss -ulpn | grep 5300
iptables -t nat -L PREROUTING -n -v | grep ':53 '
tail -f /var/log/auth.log
```

If it doesn't connect:
- Check that **ports 22 and 53 (UDP/TCP) are open**.
- Verify correct delegation (`dig NS t.example.com +short`).
- Check `dnstt-server` and `sshd` logs.

---

## 🧼 Uninstallation (Return to Original State)

```bash
/root/dnstt-setup.sh --uninstall
# or
/root/dnstt-setup.sh -u
```

What uninstallation does:
- Stops/removes the `dnstt-server` service.
- Removes `/usr/local/bin/dnstt-server`, `/opt/dnstt`, `/etc/dnstt`.
- Removes redirects/port openings (53/5300) from `iptables` and saves rules.
- **Does not** remove port 22 rule without explicit consent (to avoid losing access).
- Optionally removes drop-in `sshd_config.d/99-dnstt.conf` and installed Go.

---

## ⚠️ Disclaimer

Use DNSTT within the law and provider policies. The project is intended for privacy and working in restricted networks, not for unauthorized activities.

---

## ✨ Author

**by [TrackLine](https://github.com/TrackLine)**  
📦 license: MIT  
🧩 based on [gharib-uk/dnstt](https://github.com/gharib-uk/dnstt)
