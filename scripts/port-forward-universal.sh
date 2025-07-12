#!/bin/bash

# Pastikan dijalankan sebagai root
if [ "$(id -u)" -ne 0 ]; then
  echo "Skrip ini harus dijalankan sebagai root. Coba 'su -c \"$0\"'."
  exit 1
fi

# Flush aturan lama untuk memulai dari awal
iptables -F
iptables -t nat -F

# Set policy default
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Aktifkan IP forwarding (penting untuk beberapa skenario)
echo 1 > /proc/sys/net/ipv4/ip_forward

# Deteksi interface utama yang aktif
interface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

# =================================================================
# ATURAN UNTUK TRAFFIC DARI LUAR (INTERNET -> SERVER ANDROID)
# Menggunakan chain PREROUTING
# =================================================================
echo "Menerapkan aturan untuk traffic dari LUAR (PREROUTING)..."
# ZIVPN: Port 6000-19999 -> 5667
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 6000:19999 -j DNAT --to-destination :5667

# Aturan lain jika diperlukan (contoh dari skrip asli Anda)
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 1:5999 -j DNAT --to-destination :3671
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 20000:65535 -j DNAT --to-destination :5666


# =================================================================
# ATURAN UNTUK TRAFFIC DARI DALAM (CLIENT ANDROID -> SERVER ANDROID)
# Menggunakan chain OUTPUT
# =================================================================
echo "Menerapkan aturan untuk traffic dari DALAM (OUTPUT)..."
# ZIVPN: Port 6000-19999 -> 5667
iptables -t nat -A OUTPUT -p udp --dport 6000:19999 -j DNAT --to-destination :5667

# Aturan lain jika diperlukan (harus sama dengan yang di PREROUTING)
iptables -t nat -A OUTPUT -p udp --dport 1:5999 -j DNAT --to-destination :3671
iptables -t nat -A OUTPUT -p udp --dport 20000:65535 -j DNAT --to-destination :5666


echo "Aturan iptables universal telah berhasil diterapkan."

# Jalankan skrip optimasi jika ada
if [ -f "optimize.sh" ]; then
    bash optimize.sh
fi
