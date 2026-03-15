# coturn-ansible

Ansible playbook for automated deployment of a coturn TURN/STUN server on Ubuntu 22.04 and 24.04 using Docker Compose.

## Table of Contents

- [What the Playbook Does](#what-the-playbook-does)
- [Project Structure](#project-structure)
- [Quick Start](#quick-start)
- [Server URLs](#server-urls)
- [Verification after Deployment](#verification-after-deployment)
- [Useful Commands](#useful-commands)
- [Admin CLI](#admin-cli)

---

## What the Playbook Does

1. **Docker** — checks if Docker is installed, installs it from the official repository if not
2. **Certbot** — installs certbot and obtains a certificate via `--standalone` (only when `cert_source: certbot`, port 80 must be free)
3. **Files** — creates `/opt/coturn/`, copies configuration files, generates `.env` with mode `0600`
4. **Firewall** — opens ports in ufw: `80` TCP (certbot only), `3478` UDP/TCP, `5349` TCP/UDP, relay port range UDP (only when ufw is active)
5. **Start** — runs `docker compose up -d`
6. **Cron** — sets up certificate renewal with a deploy-hook that restarts coturn only when the certificate is actually renewed

---

## Project Structure

```
ansible/
├── deploy.yml               — main playbook
├── inventory.ini            — server list
├── vars/
│   ├── main.yml             — all settings (IP, domain, ports, auth, logging)
│   ├── secrets.yml          — CLI password
│   └── users.yml            — TURN users and passwords
├── templates/
│   └── env.j2               — .env template for coturn container
└── files/
    ├── coturn.conf.template — coturn configuration template
    ├── docker-compose.yml   — Docker Compose service definition
    └── entrypoint.sh        — container entrypoint script
```

---

## Quick Start

### 1. Set the target server

Edit `inventory.ini`:

```ini
[turn_servers]
turn1 ansible_host=YOUR_SERVER_IP ansible_user=root ansible_ssh_private_key_file=~/.ssh/your_key
```

### 2. Configure settings

Edit `vars/main.yml`. Only two parameters at the top need to be changed — everything else is derived automatically:

```yaml
server_ip: "YOUR_SERVER_IP"
domain: "YOUR_DOMAIN"
```

**Certificate source** (`cert_source`):

- `certbot` — automatically obtain a Let's Encrypt certificate (port 80 must be free)
- `manual` — use an existing certificate (Let's Encrypt or purchased)

For `manual` mode, set the root directory and subdirectory containing `fullchain.pem` and `privkey.pem`:

```yaml
cert_source: "manual"
manual_cert_root: "/path/to/certs/root"
manual_cert_subdir: "YOUR_DOMAIN"
```

> Works with Let's Encrypt and purchased certificates.
> For purchased certificates: files must be named `fullchain.pem` and `privkey.pem`.
> Symlinks are allowed if their targets are also inside `manual_cert_root`.

**Authentication mode** (`auth_mode`):

- `password` — long-term credentials, recommended for production
- `noauth` — open relay without credentials, for testing only

### 3. Optional Settings

All optional settings are in `vars/main.yml`:

| Parameter | Default | Description |
|---|---|---|
| `min_port` | `49152` | Relay port range start. Each port = 1 concurrent TURN allocation |
| `max_port` | `49452` | Relay port range end. Total ports must be ≥ `total_quota` |
| `total_quota` | `100` | Max simultaneous TURN allocations across all users |
| `user_quota` | `20` | Max simultaneous TURN allocations per user |
| `max_bps` | `0` | Max bandwidth per allocation in bits/s. `0` = unlimited. Example: `1048576` = 1 Mbit/s |
| `mobility` | `false` | Allow clients to change IP mid-call (e.g. WiFi → 4G). `true` / `false` |
| `log_level` | `verbose` | Logging verbosity: `normal`, `verbose`, `Verbose` |

### 4. Add TURN Users

Edit `vars/users.yml`:

```yaml
turn_users:
  - username: "user1"
    password: "StrongPassword1!"
```

### 5. Set the CLI Password

Edit `vars/secrets.yml`:

```yaml
cli_password: "StrongCliPassword!"
```

### 6. Run the Deployment

```sh
ansible-playbook -i inventory.ini deploy.yml
```

---

## Server URLs

| Protocol | URL | Description |
|---|---|---|
| STUN | `stun:YOUR_DOMAIN:3478` | STUN only, no credentials required |
| TURN | `turn:YOUR_DOMAIN:3478` | TURN over UDP, fallback to TCP automatically |
| TURN UDP | `turn:YOUR_DOMAIN:3478?transport=udp` | TURN over UDP (explicit) |
| TURN TCP | `turn:YOUR_DOMAIN:3478?transport=tcp` | TURN over TCP (explicit) |
| TURNS TLS | `turns:YOUR_DOMAIN:5349` | TURN over TLS (encrypted) |

---

## Verification after Deployment

Test the TURN/STUN server using [Trickle ICE](https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/):

1. Enter the TURN URI: `turn:YOUR_DOMAIN:3478?transport=udp`
2. Enter TURN username and password from `vars/users.yml`
3. Click **Gather candidates**

If `relay` candidates appear — TURN is working correctly.

---

## Useful Commands

```sh
# View coturn logs
docker logs -f coturn-coturn-1

# Redeploy with Ansible
ansible-playbook -i inventory.ini deploy.yml
```

---

## Admin CLI

Connect to the coturn admin interface from the server:

```sh
nc 127.0.0.1 5766
```

Enter `cli_password` from `vars/secrets.yml` when prompted.

Available commands:

| Command | Description |
|---|---|
| `ps <username>` | Show active sessions for a user |
| `pc` | Print current configuration and allocation stats |
