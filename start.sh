#!/bin/bash
set -m

echo "=== Memulai Web Server untuk IP Publik ==="
python3 -c '
import http.server
import socketserver
import json
import urllib.request
import os

PORT = 7860

def get_public_ip():
    """Fetches the public IP address from an external service."""
    # In Hugging Face, the SPACE_HOST variable gives the public URL.
    # We use external services to get the actual public IP address.
    urls = ["https://api.ipify.org?format=json", "https://ipinfo.io/json"]
    for url in urls:
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                if response.status == 200:
                    data = json.loads(response.read().decode("utf-8"))
                    if "ip" in data:
                        print(f"Successfully fetched IP from {url}")
                        return data["ip"]
        except Exception as e:
            print(f"Gagal mendapatkan IP dari {url}: {e}")
    
    print("Semua metode untuk mendapatkan IP publik gagal. Menggunakan fallback 127.0.0.1.")
    return "127.0.0.1" # Fallback IP

class IPHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        """Handles GET requests to the root path."""
        if self.path == "/":
            self.send_response(200)
            self.send_header("Content-type", "text/plain; charset=utf-8")
            self.end_headers()
            public_ip = get_public_ip()
            self.wfile.write(public_ip.encode("utf-8"))
        else:
            self.send_error(404, "File Not Found: " + self.path)

def run_server():
    """Starts the HTTP server."""
    with socketserver.TCPServer(("", PORT), IPHandler) as httpd:
        print(f"Server IP dimulai di http://0.0.0.0:{PORT}")
        httpd.serve_forever()

if __name__ == "__main__":
    run_server()
' &
WEBSERVER_PID=$!
echo "Web server IP berjalan di background dengan PID: $WEBSERVER_PID"


echo "=== Memulai Konfigurasi Server VPN ==="

# Get the directory where the script is located
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." &> /dev/null && pwd)

# Path to the ZIVPN binary
ZIVPN_BINARY="$PROJECT_ROOT/zivpn/udp-zivpn-linux-amd64"
ZIVPN_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
ZIVPN_DIR=$(dirname "$ZIVPN_BINARY")

# Check if the ZIVPN binary exists, and download if it does not
if [ ! -f "$ZIVPN_BINARY" ]; then
    echo "ZIVPN binary not found. Downloading..."
    # Ensure the directory exists
    mkdir -p "$ZIVPN_DIR"
    # Download the binary using wget or curl
    if command -v wget >/dev/null 2>&1; then
        wget -O "$ZIVPN_BINARY" "$ZIVPN_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -L -o "$ZIVPN_BINARY" "$ZIVPN_URL"
    else
        echo "Error: Neither wget nor curl is available to download the ZIVPN binary."
        exit 1
    fi
    # Make the binary executable
    if [ -f "$ZIVPN_BINARY" ]; then
        chmod +x "$ZIVPN_BINARY"
        echo "ZIVPN binary downloaded and made executable."
    else
        echo "Error: Failed to download ZIVPN binary."
        exit 1
    fi
else
    echo "ZIVPN binary already exists. Skipping download."
fi

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
echo "PID: webserver=$WEBSERVER_PID, badvpn=$BADVPN_PID, udp-custom=$UDP_CUSTOM_PID, zivpn=$ZIVPN_PID"

# 6. Tunggu sinyal keluar dan bersihkan
trap "echo 'Menutup layanan...'; kill $WEBSERVER_PID $BADVPN_PID $UDP_CUSTOM_PID $ZIVPN_PID; exit 0" SIGINT SIGTERM

# Tunggu semua proses background selesai
# fg %1 akan membawa proses pertama ke foreground, menjaga kontainer tetap berjalan
# dan memungkinkan trap untuk menangani sinyal dengan benar.
wait $WEBSERVER_PID
wait $BADVPN_PID
wait $UDP_CUSTOM_PID
wait $ZIVPN_PID