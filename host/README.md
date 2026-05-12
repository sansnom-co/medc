# `host/` — PR3 host prerequisites

`medc-host-prereqs.sh` prepares a Debian host for MEDC v1 by:

- installing `incus`, `tailscale`, and `iptables-persistent`
- loading and persisting `br_netfilter` and `overlay`
- setting and persisting `net.ipv4.ip_forward=1`
- rendering `/etc/medc/incus-init.yaml` from `incus-init.yaml.tmpl`

## Usage

```bash
sudo ./host/medc-host-prereqs.sh
sudo incus admin init --preseed < /etc/medc/incus-init.yaml
```

## Preflight (recommended)

Run this before PR3 validation on a fresh host:

```bash
set -euo pipefail

# OS + privileges
uname -a
cat /etc/os-release
sudo -v

# Network + package manager basics
ip -4 route show default
apt-cache policy incus tailscale iptables-persistent | sed -n '1,20p'

# Disk + memory headroom
df -h /
free -h

# Required local files exist on checked-out branch
test -f host/medc-host-prereqs.sh
test -f host/incus-init.yaml.tmpl
```

If any check fails, fix host prerequisites before running
`medc-host-prereqs.sh`.

Non-interactive driver selection:

```bash
sudo ./host/medc-host-prereqs.sh --storage-driver dir --yes
```

## Template variables

`incus-init.yaml.tmpl` is rendered by replacing:

- `__MEDC_STORAGE_POOL_NAME__`
- `__MEDC_STORAGE_DRIVER__`
- `__MEDC_STORAGE_POOL_SIZE__`

PR3 only prepares host prerequisites and preseed material. Instance
orchestration is implemented in subsequent phases.
