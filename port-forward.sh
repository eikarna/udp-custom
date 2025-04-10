#!/bin/bash

# Flush all
iptables -F
iptables -t nat -F

# Set policy default untuk masing-masing chain
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Pastikan IP forwarding diaktifkan
echo 1 > /proc/sys/net/ipv4/ip_forward

interface=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)

# Tambahkan rule untuk mengizinkan paket UDP dengan destination port 50000 pada chain INPUT
iptables -A INPUT -p udp --dport 3671 -j ACCEPT

# UDP CUSTOM: Tambahkan aturan iptables untuk melakukan port forwarding UDP ke port 3671
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 1:21 -j DNAT --to-destination :3671 # 22: (SSH Port)
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 23:52 -j DNAT --to-destination :3671 # 53: (DNS Port)
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 54:3670 -j DNAT --to-destination :3671 # 3671: (Itself/UDP CUSTOM)
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 3672:5665 -j DNAT --to-destination :3671 # 5666 & 5667: (UDP ZIVPN)
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 5668:5999 -j DNAT --to-destination :3671

# ZIVPN: Tambahkan aturan iptables untuk melakukan port forwarding UDP ke port 5667
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 6000:7299 -j DNAT --to-destination :5667 # 7300: (BadVPN UDPGW)
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 7301:19131 -j DNAT --to-destination :5667 # 19132: (Minecraft Server)
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 19133:19999 -j DNAT --to-destination :5667 # End

# ZIVPN Legacy (Old): Tambahkan aturan iptables untuk melakukan port forwarding UDP ke port 5666
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 20000:25564 -j DNAT --to-destination :5666 # 25565: (Minecraft Server)
iptables -t nat -A PREROUTING -i ${interface} -p udp --dport 25566:65535 -j DNAT --to-destination :5666 # End
