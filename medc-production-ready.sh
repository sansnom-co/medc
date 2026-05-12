#!/bin/bash
# MEDC — Production-readiness hardening for the LXC-based lab
# Hardens and optimizes LXC containers for production k8s use

set -e

# Configuration
CONTAINERS="k0rdent-mgmt k0s-child-master k0s-child-worker1 k0s-child-worker2"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

function print_header() {
    echo -e "${GREEN}=== $1 ===${NC}"
}

function print_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

function print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

print_header "LXC Production Ready Setup for Kubernetes"
echo "This will configure:"
echo "  1. Time synchronization (chrony)"
echo "  2. Kernel parameters for k8s"
echo "  3. Resource limits"
echo "  4. Log rotation"
echo "  5. Backup scripts"
echo "  6. Maintenance scripts"
echo
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Step 1: Time Synchronization
print_header "Installing and configuring time synchronization"
for container in $CONTAINERS; do
    print_info "Configuring chrony in $container"
    lxc-attach -n $container -- bash -c "
        apt update
        apt install -y chrony
        systemctl enable chrony
        systemctl start chrony
        # Force initial sync
        chronyc makestep
    " || print_error "Failed to configure chrony in $container"
done

# Step 2: Kernel Parameters
print_header "Adding Kubernetes kernel parameters"
for container in $CONTAINERS; do
    print_info "Updating kernel parameters for $container"
    
    # Check if parameters already exist
    if grep -q "Kubernetes kernel requirements" /var/lib/lxc/$container/config; then
        print_info "Kernel parameters already configured for $container"
    else
        cat >> /var/lib/lxc/$container/config <<EOF

# Kubernetes kernel requirements
lxc.sysctl.net.bridge.bridge-nf-call-iptables = 1
lxc.sysctl.net.ipv4.ip_forward = 1
lxc.sysctl.net.bridge.bridge-nf-call-ip6tables = 1
lxc.sysctl.fs.inotify.max_user_instances = 524288
lxc.sysctl.fs.inotify.max_user_watches = 524288
EOF
        print_info "Kernel parameters added for $container"
    fi
done

# Step 3: Resource Limits
print_header "Setting container resource limits"
echo "Current system resources:"
echo "  CPUs: $(nproc)"
echo "  Memory: $(free -h | grep Mem | awk '{print $2}')"
echo
read -p "Apply resource limits? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    for container in $CONTAINERS; do
        if grep -q "Resource limits" /var/lib/lxc/$container/config; then
            print_info "Resource limits already configured for $container"
        else
            cat >> /var/lib/lxc/$container/config <<EOF

# Resource limits
lxc.cgroup2.memory.max = 4G
lxc.cgroup2.cpu.max = 200000 1000000
# This gives each container up to 2 CPUs (200000/1000000 = 20% × 10 cores = 2 cores)
EOF
            print_info "Resource limits set for $container"
        fi
    done
else
    print_info "Skipping resource limits"
fi

# Step 4: Log Rotation
print_header "Configuring log rotation"
cat > /etc/logrotate.d/lxc-containers <<EOF
/var/lib/lxc/*/rootfs/var/log/*.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    sharedscripts
}

/var/lib/lxc/*/rootfs/var/log/*/*.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    sharedscripts
}
EOF
print_info "Log rotation configured"

# Step 5: Create backup script
print_header "Creating backup script"
cat > /usr/local/bin/backup-lxc-containers.sh <<'SCRIPT'
#!/bin/bash
# LXC container backup script

BACKUP_DIR="/var/backups/lxc"
DATE=$(date +%Y%m%d-%H%M%S)
CONTAINERS="k0rdent-mgmt k0s-child-master k0s-child-worker1 k0s-child-worker2"

echo "=== LXC Container Backup ==="
echo "Backup directory: $BACKUP_DIR"
echo "Date: $DATE"

mkdir -p $BACKUP_DIR

for container in $CONTAINERS; do
    echo "Backing up $container..."
    if lxc-info -n $container --state | grep -q RUNNING; then
        # Create snapshot for running container
        lxc-snapshot -n $container -c "backup-$DATE"
        # Export snapshot
        tar -czf $BACKUP_DIR/${container}-${DATE}.tar.gz \
            -C /var/lib/lxc/$container/snaps/backup-$DATE .
        # Remove snapshot
        lxc-snapshot -n $container -d "backup-$DATE"
    else
        # Direct backup for stopped container
        tar -czf $BACKUP_DIR/${container}-${DATE}.tar.gz \
            -C /var/lib/lxc/$container .
    fi
done

# Keep only last 7 days
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "Backup complete!"
echo "Backups stored in: $BACKUP_DIR"
ls -lh $BACKUP_DIR/*.tar.gz
SCRIPT
chmod +x /usr/local/bin/backup-lxc-containers.sh
print_info "Backup script created at /usr/local/bin/backup-lxc-containers.sh"

# Step 6: Create maintenance script
print_header "Creating maintenance script"
cat > /usr/local/bin/maintain-lxc-containers.sh <<'SCRIPT'
#!/bin/bash
# LXC container maintenance script

CONTAINERS="k0rdent-mgmt k0s-child-master k0s-child-worker1 k0s-child-worker2"

echo "=== LXC Container Maintenance ==="
echo "Date: $(date)"

for container in $CONTAINERS; do
    echo "=== Maintaining $container ==="
    lxc-attach -n $container -- bash -c "
        # Update package lists
        apt update
        
        # Upgrade packages (safe upgrades only)
        apt upgrade -y
        
        # Clean up
        apt autoremove -y
        apt clean
        
        # Clear old logs
        find /var/log -type f -name '*.log' -mtime +30 -delete
        find /var/log -type f -name '*.gz' -mtime +30 -delete
        
        # Show disk usage
        echo 'Disk usage:'
        df -h /
    "
done

echo "Maintenance complete!"
SCRIPT
chmod +x /usr/local/bin/maintain-lxc-containers.sh
print_info "Maintenance script created at /usr/local/bin/maintain-lxc-containers.sh"

# Step 7: Update host kernel modules
print_header "Ensuring required kernel modules"
modprobe br_netfilter
modprobe overlay

# Make persistent
grep -q "br_netfilter" /etc/modules || echo "br_netfilter" >> /etc/modules
grep -q "overlay" /etc/modules || echo "overlay" >> /etc/modules

# Step 8: Disable swap in containers
print_header "Disabling swap in containers (required for k8s)"
for container in $CONTAINERS; do
    print_info "Disabling swap in $container"
    lxc-attach -n $container -- bash -c "
        swapoff -a
        # Comment out swap entries in fstab
        sed -i '/ swap / s/^/#/' /etc/fstab
    " || true
done

# Step 9: Restart containers to apply kernel parameters
print_header "Restarting containers to apply all changes"
read -p "Restart all containers now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    for container in $CONTAINERS; do
        print_info "Restarting $container..."
	lxc-stop -n $container && lxc-start -n $container || print_error "Failed to restart $container"
    done
    
    # Wait for containers to be ready
    print_info "Waiting for containers to be ready..."
    sleep 10
fi

print_header "MEDC production setup complete!"
echo
echo "Scripts created:"
echo "  - /usr/local/bin/backup-lxc-containers.sh"
echo "  - /usr/local/bin/maintain-lxc-containers.sh"
echo
echo "Cron job suggestions:"
echo "  # Daily backup at 2 AM"
echo "  0 2 * * * /usr/local/bin/backup-lxc-containers.sh > /var/log/lxc-backup.log 2>&1"
echo
echo "  # Weekly maintenance on Sunday at 3 AM"
echo "  0 3 * * 0 /usr/local/bin/maintain-lxc-containers.sh > /var/log/lxc-maintenance.log 2>&1"
echo
echo "Next steps:"
echo "  1. Run: sudo ./check-medc-health.sh"
echo "  2. If all checks pass, proceed with k0rdent/k0smotron installation"
