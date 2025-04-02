#!/bin/bash

# Optimasi buffer jaringan
echo "Mengatur buffer jaringan..."
sysctl -w net.core.rmem_max=16777216  # Maximum receive buffer
sysctl -w net.core.wmem_max=16777216  # Maximum send buffer
sysctl -w net.ipv4.udp_rmem_min=8192  # Minimum UDP receive buffer
sysctl -w net.ipv4.udp_wmem_min=8192  # Minimum UDP send buffer

# Mengatur backlog queue untuk UDP
echo "Mengatur backlog queue..."
sysctl -w net.core.netdev_max_backlog=5000  # Buffering pada NIC

# Mengatur MTU (Maximum Transmission Unit)
echo "Mengatur MTU untuk menghindari fragmentasi..."
ip link set dev eth0 mtu 9000  # Sesuaikan dengan interface yang digunakan

# Mengoptimalkan penggunaan TCP dan UDP buffers
sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216"  # Buffer TCP untuk receive
sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216"  # Buffer TCP untuk send

# Meningkatkan performa interrupt handling
echo "Meningkatkan performa interrupt handling..."
sysctl -w net.core.somaxconn=65535  # Meningkatkan kapasitas koneksi maksimal

# Mengaktifkan TCP offloading jika mendukung hardware
ethtool -K eth0 tso on  # Ganti eth0 dengan interface yang sesuai
ethtool -K eth0 gro on  # Ganti eth0 dengan interface yang sesuai

# Mengoptimalkan parameter system lainnya untuk latensi rendah
sysctl -w vm.swappiness=1  # Kurangi swap dan prioritaskan RAM
sysctl -w net.ipv4.tcp_fin_timeout=10  # Mempercepat penutupan koneksi TCP yang lama
sysctl -w net.ipv4.tcp_keepalive_time=60  # Percepat waktu keepalive

# Menerapkan konfigurasi
sysctl -p

# Mengatur prioritas untuk proses tunneling
# Atur agar aplikasi server tunneling berjalan dengan prioritas tinggi
renice -n -10 -p $(pgrep udp-custom)  # Ganti dengan PID server UDP
renice -n -10 -p $(pgrep badvpn-udpgw)  # Ganti dengan PID Server BadVPN
