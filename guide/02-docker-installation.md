# 2. Docker Installation

[← Back to README](../README.md)

Install Docker CE and configure security to prevent container ports from being exposed publicly.

---

## 2.1 Install Docker CE

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker <your-username>
```

**Log out and back in** (or run `newgrp docker`) for group membership to take effect.

Verify:

```bash
docker --version
docker compose version
```

---

## 2.2 Configure Docker Daemon

Bind containers to localhost by default:

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "iptables": true,
  "ip": "127.0.0.1"
}
EOF

sudo systemctl restart docker
```

---

## 2.3 Configure DOCKER-USER Firewall Rules

Docker bypasses UFW by manipulating iptables directly. We need to add rules to the DOCKER-USER chain to block external access.

**Note:** `iptables-persistent` conflicts with UFW, so we use a systemd service instead.

Create the service:

```bash
sudo tee /etc/systemd/system/docker-firewall.service << 'EOF'
[Unit]
Description=Docker DOCKER-USER firewall rules
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/iptables -I DOCKER-USER -i eth0 -j DROP
ExecStart=/sbin/iptables -I DOCKER-USER -i eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT
ExecStart=/sbin/iptables -I DOCKER-USER -i tailscale0 -j ACCEPT

[Install]
WantedBy=multi-user.target
EOF
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable docker-firewall
sudo systemctl start docker-firewall
```

Verify:

```bash
sudo iptables -L DOCKER-USER -v -n
```

Expected output:

```
Chain DOCKER-USER (1 references)
 pkts bytes target     prot opt in     out     source               destination         
    0     0 ACCEPT     0    --  tailscale0 *       0.0.0.0/0            0.0.0.0/0           
    0     0 ACCEPT     0    --  eth0   *       0.0.0.0/0            0.0.0.0/0            state RELATED,ESTABLISHED
    0     0 DROP       0    --  eth0   *       0.0.0.0/0            0.0.0.0/0
```

---

## What These Rules Do

| Rule | Effect |
|------|--------|
| `ACCEPT tailscale0` | Allow all traffic from Tailscale interface |
| `ACCEPT eth0 ESTABLISHED,RELATED` | Allow responses to outbound connections |
| `DROP eth0` | Block all other inbound traffic from public interface |

This means:
- Containers can make outbound connections (pull images, API calls)
- Tailscale peers can reach containers
- Public internet cannot reach containers directly

---

## Troubleshooting

### Duplicate iptables rules

If you see duplicate rules in DOCKER-USER:

```bash
sudo iptables -F DOCKER-USER
sudo systemctl restart docker-firewall
sudo iptables -L DOCKER-USER -v -n
```

### Docker group not working

```bash
groups  # Should show 'docker'
```

If not, log out completely and log back in, or:

```bash
newgrp docker
```

### Container can't reach internet

Check that ESTABLISHED,RELATED rule exists:

```bash
sudo iptables -L DOCKER-USER -v -n | grep ESTABLISHED
```

If missing, restart the firewall service:

```bash
sudo systemctl restart docker-firewall
```

---

## Checklist

| Item | Status |
|------|--------|
| Docker installed | ☐ |
| Docker Compose available | ☐ |
| User in docker group | ☐ |
| daemon.json configured | ☐ |
| docker-firewall.service enabled | ☐ |
| DOCKER-USER rules verified | ☐ |

---

[← Back to README](../README.md) | [Previous: Server Hardening](01-server-hardening.md) | [Next: Repository Setup →](03-repository-setup.md)
