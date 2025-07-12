---
title: My VPN Server
emoji: 🚀
colorFrom: blue
colorTo: green
sdk: docker
app_port: 7860
docker_args: "--user root --cap-add=NET_ADMIN --cap-add=SYS_NICE --sysctl net.ipv4.ip_forward=1 --sysctl net.core.rmem_max=16777216 --sysctl net.core.wmem_max=16777216 --sysctl net.core.netdev_max_backlog=5000 --sysctl net.core.somaxconn=65535 --sysctl vm.swappiness=1 --sysctl net.ipv4.tcp_fin_timeout=10 --sysctl net.ipv4.tcp_keepalive_time=60"
---
Mereka memanggil ku seorang pahlawan, karena aku menyelamatkan
mereka dari kehancuran.

Saturday, 12 July 2025
