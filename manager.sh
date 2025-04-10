#!/bin/bash
# firewall_manager.sh - Manajemen firewall rules terpadu dengan iptables, ufw, dan firewalld
#
# Fitur:
#   - Validasi input yang lebih kompleks untuk aturan
#   - Logging setiap aksi ke /var/log/firewall_manager.log
#   - Integrasi dengan firewalld (jika aktif) secara langsung
#
# Usage:
#   sudo ./firewall_manager.sh {start|stop|status|list|add-rule|del-rule|backup|restore}
#
# Contoh:
#   sudo ./firewall_manager.sh start
#   sudo ./firewall_manager.sh add-rule udp 1000:2000 9999

set -euo pipefail
LOG_FILE="/var/log/firewall_manager.log"

# === Fungsi Logging ===
log_msg() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# === Fungsi Validasi ===
validate_protocol() {
    local protocol="$1"
    if [[ "$protocol" != "udp" && "$protocol" != "tcp" ]]; then
        log_msg "ERROR" "Protocol harus 'udp' atau 'tcp'. Diberikan: ${protocol}"
        exit 1
    fi
}

validate_port_range() {
    local port_range="$1"
    if ! [[ "$port_range" =~ ^[0-9]{1,5}(:[0-9]{1,5})?$ ]]; then
        log_msg "ERROR" "Format port range tidak valid: ${port_range}"
        exit 1
    fi
}

validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]{1,5}$ ]]; then
        log_msg "ERROR" "Format port tidak valid: ${port}"
        exit 1
    fi
    if (( port < 1 || port > 65535 )); then
        log_msg "ERROR" "Port harus berada di antara 1 dan 65535: ${port}"
        exit 1
    fi
}

# === Fungsi Helper ===
usage() {
    cat << EOF
Usage: $0 {start|stop|status|list|add-rule|del-rule|backup|restore}

Commands:
  start      : Enable IP forwarding dan pasang aturan default.
               (Default: UDP CUSTOM (1:7299->3671) dan ZIVPN (6000:19999->5667) + aturan ufw dan firewalld jika aktif)
  stop       : Flush aturan NAT dan disable IP forwarding.
  status     : Tampilkan status IP forwarding dan aturan firewall saat ini.
  list       : List aturan iptables (tabel NAT) dan status ufw.
  add-rule   : Tambah aturan kustom.
               Sintaks: $0 add-rule <protocol> <port_range> <destination_port>
               Contoh: $0 add-rule udp 1000:2000 9999
  del-rule   : Hapus aturan kustom.
               Sintaks: $0 del-rule <chain> <protocol> <port_range> <destination_port>
               Contoh: $0 del-rule PREROUTING udp 1000:2000 9999
  backup     : Backup aturan iptables NAT ke file backup.
  restore    : Restore aturan iptables NAT dari file backup.

EOF
    exit 1
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Jalankan script ini sebagai root." >&2
        exit 1
    fi
}

enable_ip_forwarding() {
    log_msg "INFO" "Mengaktifkan IP forwarding"
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
}

disable_ip_forwarding() {
    log_msg "INFO" "Menonaktifkan IP forwarding"
    sysctl -w net.ipv4.ip_forward=0 >/dev/null
}

get_default_interface() {
    local iface
    iface=$(ip route | awk '/default/ {print $5; exit}')
    echo "$iface"
}

is_firewalld_active() {
    if systemctl is-active --quiet firewalld; then
        return 0
    else
        return 1
    fi
}

# === Integrasi Firewalld ===
apply_firewalld_rule() {
    local action="$1"  # add or remove
    local rule="$2"
    # Contoh penggunaan:
    # firewall-cmd --permanent --direct --add-rule ipv4 nat PREROUTING 0 -i ${interface} -p udp --dport 1:7299 -j DNAT --to-destination :3671
    firewall-cmd --permanent --direct --"${action}"-rule ipv4 nat PREROUTING 0 ${rule}
}

reload_firewalld() {
    firewall-cmd --reload
}

# === Fungsi Aturan Default ===
apply_default_rules() {
    local interface
    interface=$(get_default_interface)
    if [[ -z "$interface" ]]; then
        log_msg "ERROR" "Interface default tidak ditemukan."
        exit 1
    fi
    log_msg "INFO" "Menggunakan interface: ${interface}"

    # UDP CUSTOM: Port forwarding UDP dari port 1 hingga 7299 ke port 3671
    iptables -t nat -A PREROUTING -i "${interface}" -p udp --dport 1:7299 -j DNAT --to-destination :3671
    log_msg "INFO" "Aturan iptables UDP CUSTOM diterapkan: 1:7299 -> 3671"

    # ZIVPN: Port forwarding UDP dari port 6000 hingga 19999 ke port 5667
    iptables -t nat -A PREROUTING -i "${interface}" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
    log_msg "INFO" "Aturan iptables ZIVPN diterapkan: 6000:19999 -> 5667"

    # UFW: izinkan port untuk ZIVPN
    ufw allow 6000:19999/udp && ufw allow 5667/udp
    log_msg "INFO" "Aturan UFW diterapkan untuk port 6000:19999/udp dan 5667/udp"

    # Integrasi firewalld jika aktif
    if is_firewalld_active; then
        log_msg "INFO" "firewalld terdeteksi. Menerapkan aturan ke firewalld..."
        # Aturan untuk UDP CUSTOM
        apply_firewalld_rule "add" "-i ${interface} -p udp --dport 1:7299 -j DNAT --to-destination :3671"
        # Aturan untuk ZIVPN
        apply_firewalld_rule "add" "-i ${interface} -p udp --dport 6000:19999 -j DNAT --to-destination :5667"
        reload_firewalld
        log_msg "INFO" "Aturan firewalld diterapkan dan reload"
    fi

    log_msg "INFO" "Aturan default berhasil diterapkan."
}

flush_firewall_rules() {
    log_msg "INFO" "Menghapus semua aturan di NAT table iptables..."
    iptables -t nat -F
    log_msg "INFO" "Aturan NAT table iptables telah dihapus."

    # Integrasi firewalld: Hapus aturan default jika firewalld aktif
    if is_firewalld_active; then
        local interface
        interface=$(get_default_interface)
        log_msg "INFO" "Menghapus aturan firewalld..."
        apply_firewalld_rule "remove" "-i ${interface} -p udp --dport 1:7299 -j DNAT --to-destination :3671"
        apply_firewalld_rule "remove" "-i ${interface} -p udp --dport 6000:19999 -j DNAT --to-destination :5667"
        reload_firewalld
        log_msg "INFO" "Aturan firewalld default dihapus."
    fi
}

list_firewall_rules() {
    echo "Aturan iptables (NAT table):"
    iptables -t nat -L -n -v
    echo
    echo "Status UFW:"
    ufw status verbose
}

backup_firewall_rules() {
    local backup_file="/root/iptables_nat_backup_$(date +%F).txt"
    iptables-save -t nat > "${backup_file}"
    log_msg "INFO" "Backup aturan NAT table iptables telah disimpan ke ${backup_file}"
}

restore_firewall_rules() {
    local backup_file="/root/iptables_nat_backup_$(date +%F).txt"
    if [ ! -f "${backup_file}" ]; then
        log_msg "ERROR" "File backup ${backup_file} tidak ditemukan."
        exit 1
    fi
    iptables-restore < "${backup_file}"
    log_msg "INFO" "Aturan NAT table iptables direstore dari ${backup_file}"
}

add_custom_rule() {
    # Ekspektasi: protocol, port_range, destination_port
    if [ $# -ne 3 ]; then
        echo "Usage: $0 add-rule <protocol> <port_range> <destination_port>"
        exit 1
    fi
    local protocol="$1"
    local port_range="$2"
    local dest_port="$3"

    validate_protocol "${protocol}"
    validate_port_range "${port_range}"
    validate_port "${dest_port}"

    local interface
    interface=$(get_default_interface)
    if [[ -z "$interface" ]]; then
        log_msg "ERROR" "Interface default tidak ditemukan."
        exit 1
    fi

    iptables -t nat -A PREROUTING -i "${interface}" -p "${protocol}" --dport "${port_range}" -j DNAT --to-destination :${dest_port}
    log_msg "INFO" "Aturan kustom iptables ditambahkan: ${protocol} ${port_range} -> ${dest_port} pada interface ${interface}"

    # Integrasi firewalld jika aktif
    if is_firewalld_active; then
        apply_firewalld_rule "add" "-i ${interface} -p ${protocol} --dport ${port_range} -j DNAT --to-destination :${dest_port}"
        reload_firewalld
        log_msg "INFO" "Aturan kustom firewalld ditambahkan: ${protocol} ${port_range} -> ${dest_port}"
    fi
}

delete_custom_rule() {
    # Ekspektasi: chain, protocol, port_range, destination_port
    if [ $# -ne 4 ]; then
        echo "Usage: $0 del-rule <chain> <protocol> <port_range> <destination_port>"
        exit 1
    fi
    local chain="$1"
    local protocol="$2"
    local port_range="$3"
    local dest_port="$4"

    validate_protocol "${protocol}"
    validate_port_range "${port_range}"
    validate_port "${dest_port}"

    local interface
    interface=$(get_default_interface)
    if [[ -z "$interface" ]]; then
        log_msg "ERROR" "Interface default tidak ditemukan."
        exit 1
    fi

    iptables -t nat -D "${chain}" -i "${interface}" -p "${protocol}" --dport "${port_range}" -j DNAT --to-destination :${dest_port}
    log_msg "INFO" "Aturan kustom iptables dihapus: ${chain} ${protocol} ${port_range} -> ${dest_port}"

    # Integrasi firewalld jika aktif
    if is_firewalld_active; then
        apply_firewalld_rule "remove" "-i ${interface} -p ${protocol} --dport ${port_range} -j DNAT --to-destination :${dest_port}"
        reload_firewalld
        log_msg "INFO" "Aturan kustom firewalld dihapus: ${chain} ${protocol} ${port_range} -> ${dest_port}"
    fi
}

# === Main Program ===
check_root

if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
shift

case "${COMMAND}" in
    start)
        enable_ip_forwarding
        apply_default_rules
        ;;
    stop)
        flush_firewall_rules
        disable_ip_forwarding
        ;;
    status)
        echo "Status IP forwarding:"
        sysctl net.ipv4.ip_forward
        echo
        list_firewall_rules
        ;;
    list)
        list_firewall_rules
        ;;
    add-rule)
        add_custom_rule "$@"
        ;;
    del-rule)
        delete_custom_rule "$@"
        ;;
    backup)
        backup_firewall_rules
        ;;
    restore)
        restore_firewall_rules
        ;;
    *)
        usage
        ;;
esac
