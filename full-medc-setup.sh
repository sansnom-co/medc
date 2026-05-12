#!/bin/bash
# MEDC — Complete LXC Setup Script for k0rdent + k0smotron
# Run as: sudo ./full-medc-setup.sh

set -e  # Exit on error

# Configuration
CONTAINERS="k0rdent-mgmt k0s-child-master k0s-child-worker1 k0s-child-worker2"
declare -A CONTAINER_IPS=(
    ["k0rdent-mgmt"]="10.0.3.10"
    ["k0s-child-master"]="10.0.3.20"
    ["k0s-child-worker1"]="10.0.3.21"
    ["k0s-child-worker2"]="10.0.3.22"
)
ROOT_PASS="123robot"
ROBOT_PASS="123robot"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function print_header() {
    echo -e "${GREEN}=== $1 ===${NC}"
}

function print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

function print_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

# Main menu
echo "=== LXC Kubernetes Environment Setup ==="
echo "This script will set up 4 LXC containers for k0rdent/k0smotron"
echo
echo "Select operation:"
echo "1) Full setup (prerequisites, containers, users, SSH)"
echo "2) Prerequisites only"
echo "3) Create containers only"
echo "4) Configure users and SSH only"
echo "5) Test setup"
echo "q) Quit"
echo
read -p "Choice [1-5,q]: " -n 1 -r
echo

case $REPLY in
    1) FULL_SETUP=true ;;
    2) PREREQ_ONLY=true ;;
    3) CONTAINERS_ONLY=true ;;
    4) USERS_ONLY=true ;;
    5) TEST_ONLY=true ;;
    q|Q) exit 0 ;;
    *) print_error "Invalid choice"; exit 1 ;;
esac

# Function: Install prerequisites
function install_prerequisites() {
    print_header "Installing prerequisites"
    apt update
    apt install -y lxc lxc-templates bridge-utils dnsmasq-base iptables sshpass
    
    print_header "Configuring LXC networking"
    cat > /etc/default/lxc-net <<EOF
USE_LXC_BRIDGE="true"
LXC_BRIDGE="lxcbr0"
LXC_ADDR="10.0.3.1"
LXC_NETMASK="255.255.255.0"
LXC_NETWORK="10.0.3.0/24"
LXC_DHCP_RANGE="10.0.3.200,10.0.3.254"
LXC_DHCP_MAX="55"
LXC_DOMAIN="lxc.local"
LXC_DHCP_CONFILE="/etc/lxc/dnsmasq.d/hosts.conf"
EOF

    # Create helper scripts
    print_header "Creating helper scripts"
    
    # Container creation script
    cat > /usr/local/bin/create-k8s-lxc.sh <<'SCRIPT'
#!/bin/bash
NAME=$1
lxc-create -n $NAME -t download -- -d debian -r trixie -a arm64
cat << EOF | tee -a /var/lib/lxc/$NAME/config
# Kubernetes requirements
lxc.apparmor.profile = unconfined
lxc.cap.drop =
lxc.mount.auto = proc:rw sys:rw cgroup:rw
EOF
echo "Created $NAME with Debian Trixie ARM64"
SCRIPT
    chmod +x /usr/local/bin/create-k8s-lxc.sh

    # Network test script
    cat > /usr/local/bin/test-lxc-network.sh <<'SCRIPT'
#!/bin/bash
echo "=== LXC Network Test ==="
echo "Bridge Status:"
ip addr show lxcbr0
echo -e "\nContainers:"
lxc-ls -f
echo -e "\nDNS Resolution Test:"
for host in k0rdent-mgmt k0s-child-master k0s-child-worker1 k0s-child-worker2; do
    echo -n "$host: "
    getent hosts $host.lxc.local | awk '{print $1}'
done
echo -e "\nConnectivity Test:"
for ip in 10.0.3.10 10.0.3.20 10.0.3.21 10.0.3.22; do
    ping -c 1 -W 1 $ip &>/dev/null && echo "$ip: OK" || echo "$ip: FAIL"
done
SCRIPT
    chmod +x /usr/local/bin/test-lxc-network.sh

    # Set up networking
    mkdir -p /etc/lxc/dnsmasq.d
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -w net.ipv4.ip_forward=1
    
    # NAT rules
    iptables -t nat -A POSTROUTING -s 10.0.3.0/24 -o eth0 -j MASQUERADE
    iptables -I FORWARD -i lxcbr0 -j ACCEPT
    iptables -I FORWARD -o lxcbr0 -j ACCEPT
    
    # Add host entries
    print_header "Adding host entries"
    grep -q "LXC containers" /etc/hosts || {
        echo "# LXC containers" >> /etc/hosts
        echo "10.0.3.10 k0rdent-mgmt.lxc.local k0rdent-mgmt" >> /etc/hosts
        echo "10.0.3.20 k0s-child-master.lxc.local k0s-child-master" >> /etc/hosts
        echo "10.0.3.21 k0s-child-worker1.lxc.local k0s-child-worker1" >> /etc/hosts
        echo "10.0.3.22 k0s-child-worker2.lxc.local k0s-child-worker2" >> /etc/hosts
    }
}

# Function: Create containers
function create_containers() {
    print_header "Creating containers"
    
    for container in $CONTAINERS; do
        if lxc-info -n $container &>/dev/null; then
            print_info "$container already exists, skipping"
        else
            print_info "Creating $container..."
            /usr/local/bin/create-k8s-lxc.sh $container
        fi
    done
    
    # Start containers to get MACs
    print_header "Starting containers for MAC discovery"
    systemctl restart lxc-net
    
    for container in $CONTAINERS; do
        lxc-start -n $container || true
    done
    
    sleep 5
    
    # Configure DHCP
    print_header "Configuring DHCP reservations"
    cat > /etc/lxc/dnsmasq.d/hosts.conf <<EOF
# Expand hosts
expand-hosts
domain=lxc.local

# Static DHCP reservations
EOF
    
    for container in $CONTAINERS; do
        if lxc-info -n $container --state | grep -q RUNNING; then
            MAC=$(lxc-attach -n $container -- cat /sys/class/net/eth0/address 2>/dev/null || echo "unknown")
            IP="${CONTAINER_IPS[$container]}"
            echo "dhcp-host=$MAC,$IP,$container" >> /etc/lxc/dnsmasq.d/hosts.conf
            print_info "$container: MAC=$MAC, IP=$IP"
        fi
    done
    
    # Add host records
    echo "" >> /etc/lxc/dnsmasq.d/hosts.conf
    echo "# Static hosts" >> /etc/lxc/dnsmasq.d/hosts.conf
    for container in $CONTAINERS; do
        IP="${CONTAINER_IPS[$container]}"
        echo "host-record=$container.lxc.local,$container,$IP" >> /etc/lxc/dnsmasq.d/hosts.conf
    done
    
    # Restart for clean IPs
    print_header "Restarting containers with static IPs"
    for container in $CONTAINERS; do
        lxc-stop -n $container || true
    done
    
    systemctl stop lxc-net
    rm -f /var/lib/misc/dnsmasq.lxcbr0.leases*
    systemctl start lxc-net
    
    for container in $CONTAINERS; do
        lxc-start -n $container
    done
    
    sleep 10
    lxc-ls -f
}

# Function: Configure users and SSH
function configure_users_ssh() {
    print_header "Configuring users and SSH in containers"
    
    for container in $CONTAINERS; do
        if ! lxc-info -n $container --state | grep -q RUNNING; then
            print_error "$container not running, skipping"
            continue
        fi
        
        print_info "Configuring $container..."
        lxc-attach -n $container -- bash -c "
            # Update system
            apt update
            apt install -y openssh-server sudo
            
            # Set root password
            echo 'root:$ROOT_PASS' | chpasswd
            
            # Create robot user
            id robot &>/dev/null || useradd -m -s /bin/bash robot
            echo 'robot:$ROBOT_PASS' | chpasswd
            usermod -aG sudo robot
            
            # Configure sudoers
            echo 'robot ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/robot
            chmod 440 /etc/sudoers.d/robot
            
            # Configure SSH for password auth
            cat > /etc/ssh/sshd_config.d/10-lxc.conf <<SSHEOF
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
SSHEOF
            
            # Enable and restart SSH
            systemctl enable ssh
            systemctl restart ssh
            
            # Set hostname
            hostnamectl set-hostname $container
            
            echo 'Configuration complete'
        "
    done
}

# Function: Test setup
function test_setup() {
    print_header "Testing LXC Setup"
    
    # Network test
    /usr/local/bin/test-lxc-network.sh
    
    # SSH test
    print_header "Testing SSH access"
    for container in $CONTAINERS; do
        IP="${CONTAINER_IPS[$container]}"
        echo -n "Testing robot@$container ($IP): "
        sshpass -p "$ROBOT_PASS" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no robot@$IP hostname && echo "OK" || echo "FAILED"
        
        echo -n "Testing root@$container ($IP): "
        sshpass -p "$ROOT_PASS" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$IP hostname && echo "OK" || echo "FAILED"
    done
}

# Execute based on choice
if [ "$FULL_SETUP" = true ]; then
    install_prerequisites
    create_containers
    configure_users_ssh
    test_setup
elif [ "$PREREQ_ONLY" = true ]; then
    install_prerequisites
elif [ "$CONTAINERS_ONLY" = true ]; then
    create_containers
elif [ "$USERS_ONLY" = true ]; then
    configure_users_ssh
    test_setup
elif [ "$TEST_ONLY" = true ]; then
    test_setup
fi

print_header "Setup Complete!"
echo "Container access:"
echo "  ssh robot@10.0.3.10  # k0rdent-mgmt"
echo "  ssh robot@10.0.3.20  # k0s-child-master"
echo "  ssh robot@10.0.3.21  # k0s-child-worker1"
echo "  ssh robot@10.0.3.22  # k0s-child-worker2"
echo
echo "Passwords:"
echo "  root: $ROOT_PASS"
echo "  robot: $ROBOT_PASS"
