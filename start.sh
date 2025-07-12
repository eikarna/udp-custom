#!/bin/bash
set -m

echo "=== Memulai Konfigurasi Server VPN ==="

# 1. Mengaktifkan IP Forwarding & Optimasi Kernel (sysctl)
# Opsi ini sebaiknya diatur saat menjalankan kontainer dengan flag --sysctl
# Namun, kita tetap menjalankannya di sini untuk memastikan.
echo "Mengaktifkan IP forwarding dan optimasi kernel..."
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216
sysctl -w net.core.netdev_max_backlog=5000
sysctl -w net.core.somaxconn=65535
sysctl -w vm.swappiness=1
# Nonaktifkan pesan error jika file tidak ada
sysctl -w -e net.ipv4.tcp_fin_timeout=10
sysctl -w -e net.ipv4.tcp_keepalive_time=60

# 2. Menemukan interface jaringan utama
INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
if [ -z "$INTERFACE" ]; then
    echo "ERROR: Tidak dapat menemukan interface jaringan default. Menggunakan 'eth0'."
    INTERFACE="eth0"
fi
echo "Menggunakan interface: $INTERFACE"

# 3. Mengatur MTU & Offloading
# Memerlukan ethtool
echo "Mengatur MTU dan offloading pada interface $INTERFACE..."
ip link set dev "$INTERFACE" mtu 9000
ethtool -K "$INTERFACE" tso on gso on gro on || echo "Peringatan: ethtool tidak dapat mengatur offloading."

# 4. Mengatur Aturan Firewall (iptables)
echo "Membersihkan aturan iptables sebelumnya..."
iptables -F
iptables -t nat -F

echo "Menerapkan aturan port forwarding..."
# UDP CUSTOM -> :3671
iptables -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 1:5999 -j DNAT --to-destination :3671
# ZIVPN -> :5667
iptables -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
# ZIVPN Legacy -> :5666 (Asumsi port ini masih diperlukan)
iptables -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 20000:65535 -j DNAT --to-destination :5666

echo "Aturan iptables berhasil diterapkan."
iptables -t nat -L -n

# 5. Menjalankan Layanan VPN di Background

# badvpn-udpgw
echo "Menjalankan badvpn-udpgw..."
cd /app/udpgw
./badvpn-udpgw --listen-addr 127.0.0.1:7300 --udp-mtu 9000 &
BADVPN_PID=$!

# udp-custom
echo "Menjalankan udp-custom..."
cd /app/udp_custom
./udp-custom server &
UDP_CUSTOM_PID=$!

# zivpn
echo "Menjalankan zivpn..."
cd /app/zivpn
./udp-zivpn-linux-amd64 server -c config.json &
ZIVPN_PID=$!

echo "=== Semua layanan telah dimulai ==="
echo "PID: badvpn=$BADVPN_PID, udp-custom=$UDP_CUSTOM_PID, zivpn=$ZIVPN_PID"

# 6. Tunggu sinyal keluar dan bersihkan
trap "echo 'Menutup layanan...'; kill $BADVPN_PID $UDP_CUSTOM_PID $ZIVPN_PID; exit 0" SIGINT SIGTERM

# Tunggu semua proses background selesai
# fg %1 akan membawa proses pertama ke foreground, menjaga kontainer tetap berjalan
# dan memungkinkan trap untuk menangani sinyal dengan benar.
wait $BADVPN_PID
wait $UDP_CUSTOM_PID
wait $ZIVPN_PID
