#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMPLATE_PATH="${SCRIPT_DIR}/incus-init.yaml.tmpl"
readonly MEDC_DIR="/etc/medc"
readonly MODULES_FILE="/etc/modules-load.d/medc.conf"
readonly SYSCTL_FILE="/etc/sysctl.d/99-medc.conf"

STORAGE_DRIVER=""
POOL_NAME="medc"
POOL_SIZE="100GiB"
ASSUME_YES="${MEDC_ASSUME_YES:-0}"

usage() {
    cat <<'EOF'
Usage: medc-host-prereqs.sh [options]

Install host prerequisites for MEDC v1 and render /etc/medc/incus-init.yaml.

Options:
  --storage-driver <driver>  Storage driver for Incus preseed.
                             Supported: btrfs, dir, zfs, lvm, lvm-thin
  --pool-name <name>         Incus storage pool name (default: medc)
  --pool-size <size>         Storage pool size for preseed (default: 100GiB)
  --yes                      Non-interactive mode (same as MEDC_ASSUME_YES=1)
  -h, --help                 Show this help text

Examples:
  sudo ./host/medc-host-prereqs.sh
  sudo ./host/medc-host-prereqs.sh --storage-driver dir --yes
EOF
}

log() {
    printf '[medc-host-prereqs] %s\n' "$*"
}

fail() {
    printf '[medc-host-prereqs] ERROR: %s\n' "$*" >&2
    exit 1
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        fail "run as root (use sudo)"
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --storage-driver)
                [[ $# -ge 2 ]] || fail "--storage-driver requires a value"
                STORAGE_DRIVER="$2"
                shift 2
                ;;
            --pool-name)
                [[ $# -ge 2 ]] || fail "--pool-name requires a value"
                POOL_NAME="$2"
                shift 2
                ;;
            --pool-size)
                [[ $# -ge 2 ]] || fail "--pool-size requires a value"
                POOL_SIZE="$2"
                shift 2
                ;;
            --yes)
                ASSUME_YES=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                fail "unknown argument: $1"
                ;;
        esac
    done
}

validate_storage_driver() {
    case "$1" in
        btrfs|dir|zfs|lvm|lvm-thin) return 0 ;;
        *) fail "unsupported storage driver: $1" ;;
    esac
}

choose_storage_driver() {
    if [[ -n "${STORAGE_DRIVER}" ]]; then
        validate_storage_driver "${STORAGE_DRIVER}"
        return 0
    fi

    if [[ "${ASSUME_YES}" == "1" ]]; then
        STORAGE_DRIVER="btrfs"
        log "non-interactive mode: defaulting storage driver to btrfs"
        return 0
    fi

    log "preferred storage driver is btrfs; fallback is dir"
    printf 'Storage driver [btrfs/dir/zfs/lvm/lvm-thin] (default: btrfs): '
    read -r STORAGE_DRIVER
    STORAGE_DRIVER="${STORAGE_DRIVER:-btrfs}"
    validate_storage_driver "${STORAGE_DRIVER}"
}

install_packages() {
    log "installing required packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y incus tailscale iptables-persistent
}

configure_kernel_modules() {
    log "configuring kernel modules"
    modprobe br_netfilter
    modprobe overlay

    install -d -m 0755 /etc/modules-load.d
    cat > "${MODULES_FILE}" <<'EOF'
br_netfilter
overlay
EOF
}

configure_sysctls() {
    log "configuring sysctls"
    sysctl -w net.ipv4.ip_forward=1 >/dev/null

    install -d -m 0755 /etc/sysctl.d
    cat > "${SYSCTL_FILE}" <<'EOF'
net.ipv4.ip_forward=1
EOF
    sysctl --system >/dev/null
}

render_incus_preseed() {
    [[ -f "${TEMPLATE_PATH}" ]] || fail "template not found: ${TEMPLATE_PATH}"
    install -d -m 0755 "${MEDC_DIR}"

    log "rendering incus preseed to ${MEDC_DIR}/incus-init.yaml"
    sed \
        -e "s|__MEDC_STORAGE_POOL_NAME__|${POOL_NAME}|g" \
        -e "s|__MEDC_STORAGE_DRIVER__|${STORAGE_DRIVER}|g" \
        -e "s|__MEDC_STORAGE_POOL_SIZE__|${POOL_SIZE}|g" \
        "${TEMPLATE_PATH}" > "${MEDC_DIR}/incus-init.yaml"

    chmod 0644 "${MEDC_DIR}/incus-init.yaml"
}

main() {
    parse_args "$@"
    require_root
    choose_storage_driver

    install_packages
    configure_kernel_modules
    configure_sysctls
    render_incus_preseed

    log "done"
    log "next: incus admin init --preseed < /etc/medc/incus-init.yaml"
}

main "$@"
