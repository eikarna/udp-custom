# ==================================================================================================
# Dockerfile untuk VPN Server (UDP Custom, ZIVPN, BadVPN)
# Target: Hugging Face Spaces
# ==================================================================================================

# Gunakan base image Ubuntu 22.04 dengan build tools, mirip dengan contoh
FROM buildpack-deps:22.04-curl

# Set variabel lingkungan
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Jakarta \
    # Tentukan direktori kerja aplikasi
    APP_HOME=/app

# Buat direktori aplikasi
WORKDIR ${APP_HOME}

# Instal dependensi yang diperlukan untuk skrip jaringan dan server
# - iptables: Untuk firewall dan NAT
# - iproute2: Menyediakan command 'ip' untuk routing
# - ethtool: Untuk optimasi network interface card (NIC)
# - procps: Menyediakan 'pgrep', 'pkill' (berguna untuk debugging)
# - taskset: Untuk mengikat proses ke core CPU (opsional, tapi ada di service asli)
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables \
    iproute2 \
    ethtool \
    procps \
    util-linux \
    && rm -rf /var/lib/apt/lists/*

# Salin semua file dari proyek ke dalam direktori kerja di container
COPY . .

# Berikan izin eksekusi ke semua biner dan skrip yang relevan
RUN chmod +x \
    ${APP_HOME}/scripts/*.sh \
    ${APP_HOME}/udpgw/badvpn-udpgw \
    ${APP_HOME}/udp_custom/udp-custom \
    ${APP_HOME}/zivpn/udp-zivpn-linux-amd64 \
    ${APP_HOME}/start.sh

# ==================================================================================================
# Port Exposure
# --------------------------------------------------------------------------------------------------
# Port-port berikut diekspos berdasarkan aturan iptables di 'port-forward.sh'.
# Karena Hugging Face Spaces mungkin memiliki batasan jumlah port,
# Anda mungkin perlu menyesuaikan ini. Namun, untuk fungsionalitas penuh,

# Port untuk UDP-Custom
EXPOSE 3671/udp
# Port untuk ZIVPN
EXPOSE 5667/udp
# Port untuk ZIVPN Legacy
EXPOSE 5666/udp
# Port untuk Prometheus Metrics dari ZIVPN
EXPOSE 8080/tcp

# Port Ranges (jika platform mendukung atau untuk penggunaan di luar HF Spaces)
# Sebaiknya definisikan port utama di atas, dan jika memungkinkan, gunakan range.
# Docker tidak secara teknis "mengekspos" range dengan cara ini, ini lebih untuk dokumentasi.
# Aturan iptables di dalam kontainer yang akan menangani traffic ini.
EXPOSE 1-5999/udp
EXPOSE 6000-19999/udp
EXPOSE 20000-65535/udp
# ==================================================================================================


# Tentukan entrypoint yang akan menjalankan skrip startup
ENTRYPOINT ["/app/start.sh"]

# ==================================================================================================
# CATATAN PENTING UNTUK DEPLOYMENT (Hugging Face Spaces & Docker)
# --------------------------------------------------------------------------------------------------
# Untuk menjalankan kontainer ini dengan benar, Anda HARUS memberikan kapabilitas kernel
# dan mengatur parameter sysctl.
#
# Contoh Perintah 'docker run':
# docker run -d --name my-vpn-server \
#   --cap-add=NET_ADMIN \
#   --cap-add=SYS_NICE \
#   --sysctl net.ipv4.ip_forward=1 \
#   --sysctl net.core.rmem_max=16777216 \
#   --sysctl net.core.wmem_max=16777216 \
#   -p 8080:8080/tcp \
#   -p 1000-5000:1000-5000/udp \
#   <nama-image-anda>
#
# Di Hugging Face Spaces, Anda perlu mengkonfigurasi ini di `README.md` (metadata).
# Contoh metadata di README.md:
# ---
# title: My VPN Server
# emoji: 🚀
# colorFrom: blue
# colorTo: green
# sdk: docker
# app_port: 8080
# docker_args: "--cap-add=NET_ADMIN --cap-add=SYS_NICE"
# ---
#
# Catatan: Hugging Face Spaces mungkin tidak mendukung semua flag --sysctl.
# Skrip start.sh mencoba mengaturnya, tetapi --cap-add=NET_ADMIN adalah yang paling krusial.
# ==================================================================================================
