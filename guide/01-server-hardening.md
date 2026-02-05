# 1. Server Hardening

[← Back to README](../README.md)

Secure your Ubuntu 24.04 server before installing any applications.

---

## 1.1 Create Admin User

Connect as root and create a non-root admin account:

```bash
adduser <your-username>
usermod -aG sudo <your-username>
```

**Verify before proceeding.** Open a second terminal:

```bash
ssh <your-username>@<server-ip>
sudo whoami  # Should output: root
```

---

## 1.2 Set Up SSH Key Authentication

From your **local machine**, copy your public key:

```bash
ssh-copy-id -i ~/.ssh/your-key.pub -o IdentitiesOnly=yes <your-username>@<server-ip>
```

If you hit "too many authentication failures":

```bash
ssh-copy-id -i ~/.ssh/your-key.pub -o IdentitiesOnly=yes -o PubkeyAuthentication=no <your-username>@<server-ip>
```

Alternative (manual, from root session on server):

```bash
mkdir -p /home/<your-username>/.ssh
nano /home/<your-username>/.ssh/authorized_keys
# Paste your public key, save

chown -R <your-username>:<your-username> /home/<your-username>/.ssh
chmod 700 /home/<your-username>/.ssh
chmod 600 /home/<your-username>/.ssh/authorized_keys
```

**Test:** SSH in with your key (no password prompt).

---

## 1.3 Lock Down SSH Daemon

Check for config overrides:

```bash
sudo ls -la /etc/ssh/sshd_config.d/
sudo cat /etc/ssh/sshd_config.d/*.conf
```

Remove or rename conflicting files. Prevent cloud-init from overwriting:

```bash
echo "ssh_pwauth: false" | sudo tee /etc/cloud/cloud.cfg.d/99-disable-ssh-password.cfg
```

Create hardening config:

```bash
sudo tee /etc/ssh/sshd_config.d/90-hardening.conf << 'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
EOF
```

Validate and apply:

```bash
sudo sshd -T | grep -E "(permitrootlogin|passwordauthentication|pubkeyauthentication)"
sudo systemctl reload ssh
```

**Test before closing your session:**

1. New terminal: `ssh <your-username>@<server-ip>` works
2. `ssh root@<server-ip>` is rejected

---

## 1.4 Install Fail2ban

```bash
sudo apt update
sudo apt install -y fail2ban
```

Create local configuration:

```bash
sudo tee /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = ssh
backend = systemd
maxretry = 5
findtime = 600
bantime = 3600
EOF
```

Start and enable:

```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
sudo fail2ban-client status sshd
```

---

## 1.5 Configure UFW Firewall

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable
sudo ufw status verbose
```

---

## 1.6 Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Authenticate via the URL provided, then verify:

```bash
tailscale status
tailscale ip -4
```

Note your Tailscale IP for later steps.

---

## 1.7 Restrict SSH to Tailscale Only

```bash
sudo ufw delete allow ssh
sudo ufw allow in on tailscale0 to any port 22
sudo ufw status verbose
```

**Critical: Test before closing your session.**

From your local machine (must be on your tailnet):

```bash
ssh <your-username>@<tailscale-ip>
```

Confirm public IP no longer accepts SSH:

```bash
ssh <your-username>@<public-ip>
# Should timeout or refuse
```

---

## Troubleshooting

### SSH shows "passwordauthentication yes" after config

Check all config sources:

```bash
sudo sshd -T | grep passwordauthentication
sudo cat /etc/ssh/sshd_config.d/*.conf
```

Files are processed alphabetically. Ensure no file overrides your `90-hardening.conf`.

### Locked out of server

If you lose SSH access:
- Use your hosting provider's console/VNC access
- Check UFW rules: `sudo ufw status`
- Verify Tailscale is running: `tailscale status`

### Fail2ban not starting

```bash
sudo journalctl -u fail2ban -n 50
sudo systemctl status fail2ban
```

---

## Checklist

| Item | Status |
|------|--------|
| Admin user created | ☐ |
| SSH key authentication works | ☐ |
| Password authentication disabled | ☐ |
| Root login disabled | ☐ |
| Fail2ban running | ☐ |
| UFW enabled | ☐ |
| Tailscale connected | ☐ |
| SSH restricted to Tailscale | ☐ |
| Public IP rejects SSH | ☐ |

---

[← Back to README](../README.md) | [Next: Docker Installation →](02-docker-installation.md)
