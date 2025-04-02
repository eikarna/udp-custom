#!/bin/bash
# Pastikan IP forwarding diaktifkan
echo 1 > /proc/sys/net/ipv4/ip_forward

# Tambahkan aturan iptables untuk melakukan port forwarding UDP ke port 50000
iptables -t nat -A PREROUTING -p udp --dport 1:65535 -j REDIRECT --to-port 50000
