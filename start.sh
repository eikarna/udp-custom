#!/bin/bash
set -m

echo "=== Memulai Web Server Flask untuk IP Publik ==="
# Skrip Flask dijalankan di background. Port 7860 adalah default untuk HF Spaces.
python3 -c '
from flask import Flask, Response
import urllib.request
import json
import os

app = Flask(__name__)
PORT = int(os.environ.get("PORT", 7860))

def get_public_ip():
    """Fetches the public IP address from an external service."""
    urls = ["https://api.ipify.org?format=json", "https://ipinfo.io/json", "https://httpbin.org/ip"]
    for url in urls:
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                if response.status == 200:
                    data = json.loads(response.read().decode("utf-8"))
                    # Handle different JSON responses
                    ip = data.get("ip") or data.get("origin")
                    if ip:
                        print(f"Successfully fetched IP from {url}")
                        return ip
        except Exception as e:
            print(f"Gagal mendapatkan IP dari {url}: {e}")
    
    print("Semua metode untuk mendapatkan IP publik gagal. Menggunakan fallback 127.0.0.1.")
    return "127.0.0.1" # Fallback IP

@app.route("/")
def get_ip_route():
    """Handles GET requests to the root path."""
    public_ip = get_public_ip()
    return Response(public_ip, mimetype="text/plain")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
' &
WEBSERVER_PID=$!
echo "Web server Flask berjalan di background dengan PID: $WEBSERVER_PID"
sleep 5 # Beri waktu sejenak untuk server Flask memulai

echo "=== Memulai Konfigurasi Server VPN ==="

# 1. Mengaktifkan IP Forwarding & Optimasi Kernel (sysctl)
# Perintah ini memerlukan hak akses root, jadi kita gunakan sudo.
# Flag --cap-add=NET_ADMIN diperlukan saat menjalankan container.
echo "Mengaktifkan IP forwarding dan optimasi kernel..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.core.rmem_max=16777216
sudo sysctl -w net.core.wmem_max=16777216
sudo sysctl -w net.core.netdev_max_backlog=5000
sudo sysctl -w net.core.somaxconn=65535
sudo sysctl -w vm.swappiness=1
# Nonaktifkan pesan error jika file tidak ada
sudo sysctl -w -e net.ipv4.tcp_fin_timeout=10
sudo sysctl -w -e net.ipv4.tcp_keepalive_time=60

# 2. Menemukan interface jaringan utama
# Ini harus dijalankan di dalam container saat runtime.
INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
if [ -z "$INTERFACE" ]; then
    echo "ERROR: Tidak dapat menemukan interface jaringan default. Menggunakan 'eth0'."
    INTERFACE="eth0"
fi
echo "Menggunakan interface: $INTERFACE"

# 3. Mengatur MTU & Offloading
# Memerlukan ethtool dan hak akses root (sudo).
echo "Mengatur MTU dan offloading pada interface $INTERFACE..."
sudo ip link set dev "$INTERFACE" mtu 9000
sudo ethtool -K "$INTERFACE" tso on gso on gro on || echo "Peringatan: ethtool tidak dapat mengatur offloading."

# 4. Mengatur Aturan Firewall (iptables)
echo "Membersihkan aturan iptables sebelumnya..."
sudo iptables -F
sudo iptables -t nat -F

echo "Menerapkan aturan port forwarding..."
# UDP CUSTOM -> :3671
sudo iptables -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 1:5999 -j DNAT --to-destination :3671
# ZIVPN -> :5667
sudo iptables -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
# ZIVPN Legacy -> :5666 (Asumsi port ini masih diperlukan)
sudo iptables -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 20000:65535 -j DNAT --to-destination :5666

echo "Aturan iptables berhasil diterapkan."
sudo iptables -t nat -L -n

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
./udp-zivpn-linux-amd64 server -c config.json
# ZIVPN_PID=$!

# echo "=== Semua layanan telah dimulai ==="
# echo "PID: webserver=$WEBSERVER_PID, badvpn=$BADVPN_PID, udp-custom=$UDP_CUSTOM_PID, zivpn=$ZIVPN_PID"

# 6. Tunggu sinyal keluar dan bersihkan
# trap "echo 'Menutup layanan...'; kill $WEBSERVER_PID $BADVPN_PID $UDP_CUSTOM_PID $ZIVPN_PID; exit 0" SIGINT SIGTERM

# Tunggu semua proses background selesai. Ini menjaga container tetap berjalan.
# wait $WEBSERVER_PID
