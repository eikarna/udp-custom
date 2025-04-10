#!/bin/bash
# Pastikan IP forwarding diaktifkan
echo 1 > /proc/sys/net/ipv4/ip_forward

interface=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)

# UDP CUSTOM: Tambahkan aturan iptables untuk melakukan port forwarding UDP ke port 3671
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 1:7299 -j DNAT --to-destination :3671

# ZIVPN: Tambahkan aturan iptables untuk melakukan port forwarding UDP ke port 5667
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 6000:19999 -j DNAT --to-destination :5667

# Tambahan untuk ZIVPN Server
ufw allow 6000:19999/udp
ufw allow 5667/udp
