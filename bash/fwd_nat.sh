#!/usr/bin/bash

TRUSTED_NIC=eno1

sudo sysctl -w net.ipv4.ip_forward=1


# No longer needed because firewalld abstracts the rules
#sudo iptables -t nat -A POSTROUTING -o $FWD_NIC -s 10.10.0.0/24 -j MASQUERADE

sudo firewall-cmd --zone=trusted --add-interface=$TRUSTED_NIC --permanent
sudo firewall-cmd --zone=trusted --add-forward --permanent
sudo firewall-cmd --zone=public --add-masquerade --permanent


sudo firewall-cmd --reload
