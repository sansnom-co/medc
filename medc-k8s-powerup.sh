#!/bin/bash
# MEDC — LXC k8s startup / power-up script

# Ensure IP forwarding
sysctl -w net.ipv4.ip_forward=1
# Ensure required kernel modules
modprobe br_netfilter
modprobe overlay

# Ensure NAT rules (in case iptables-persistent fails)
iptables -t nat -C POSTROUTING -s 10.0.3.0/24 -o eth0 -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s 10.0.3.0/24 -o eth0 -j MASQUERADE

iptables -C FORWARD -i lxcbr0 -j ACCEPT 2>/dev/null || \
    iptables -I FORWARD -i lxcbr0 -j ACCEPT

iptables -C FORWARD -o lxcbr0 -j ACCEPT 2>/dev/null || \
    iptables -I FORWARD -o lxcbr0 -j ACCEPT

# Wait for network
sleep 10

# Ensure containers are started
for container in k0rdent-mgmt k0s-child-master k0s-child-worker1 k0s-child-worker2; do
    if ! lxc-info -n $container --state | grep -q RUNNING; then
        echo "Starting $container"
        lxc-start -n $container
    fi
done

# Log status
lxc-ls -f > /var/log/lxc-k8s-status.log
