#!/bin/bash
# MEDC — LXC health-check script
#
# Deploy as /usr/local/bin/check-medc-health.sh and wire into cron, e.g.
#   @reboot sleep 60 && /usr/local/bin/check-medc-health.sh > /var/log/medc-health-boot.log 2>&1

echo "=== MEDC Health Check ==="
echo "Date: $(date)"
echo

# Check services
echo "=== Service Status ==="
systemctl is-active lxc-net || echo "WARNING: lxc-net not active"
systemctl is-active netfilter-persistent || echo "WARNING: netfilter-persistent not active"

# Check network
echo -e "\n=== Network Status ==="
ip addr show lxcbr0 | grep -q "10.0.3.1" && echo "Bridge IP: OK" || echo "Bridge IP: FAIL"

# Check IP forwarding
echo -e "\n=== IP Forwarding ==="
cat /proc/sys/net/ipv4/ip_forward

# Check NAT
echo -e "\n=== NAT Rules ==="
iptables -t nat -L POSTROUTING -n | grep -q "10.0.3.0/24" && echo "NAT: OK" || echo "NAT: MISSING"

# Check containers
echo -e "\n=== Container Status ==="
lxc-ls -f

# Check connectivity
echo -e "\n=== Connectivity Test ==="
for ip in 10.0.3.10 10.0.3.20 10.0.3.21 10.0.3.22; do
    ping -c 1 -W 1 $ip &>/dev/null && echo "$ip: OK" || echo "$ip: FAIL"
done

# Test internet from container
echo -e "\n=== Internet Access Test ==="
lxc-attach -n k0rdent-mgmt -- ping -c 1 8.8.8.8 &>/dev/null && echo "Internet: OK" || echo "Internet: FAIL"
