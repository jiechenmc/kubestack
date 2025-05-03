#!/usr/bin/bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o wlp3s0 -s 10.10.0.0/24 -j MASQUERADE
