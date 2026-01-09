#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Pracuj.pl – automatycznie, bez Selenium (HTTP only).

Zasady:
- bardzo wolne tempo (długie przerwy),
- jeśli pojawi się 403 / "Access Denied" / captcha -> STOP (bez obchodzenia).
"""

FILTER_URL = "https://www.pracuj.pl/praca/in%C5%BCynier;kw/zielona%20gora;wp?rd=100&et=4%2C18%2C19%2C5%2C20&sc=0&ws=0"
PAGES      = 1
OUT_FILE   = "pracuj_http_slow.xlsx"

import time, random
from typing import List, Dict, Iterable, Optional

import requests
from bs4 import BeautifulSoup
import pandas as pd

SESSION = requests.Session()
SESSION.headers.update({
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:115.0) Gecko/20100101 Firefox/115.0",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "pl-PL,pl;q=0.9,en-US;q=0.8,en;q=0.7",
    "Referer": "https://www.pracuj.pl/",
    "Connection": "keep-alive",
    "Upgrade-Insecure-Requests": "1",
})

def human_pause(a: float, b: float):
    time.sleep(random.uniform(a, b))

def is_block_page(text: str) -> bool:
    head = text[:2000].lower()
    return (
        "access denied" in head
        or "verify you are human" in head
        or "potwierdź, że jesteś człowiekiem" in head
        or "cloudflare" in head
        or "attention required" in head
    )

def fetch(url: str) -> str:
    # długi „czas myślenia” przed każdym żądaniem
    human_pause(6, 15)
    r = SESSION.get(url, timeout=30, allow_redirects=True)
    if r.status_code == 403 or is_block_page(r.text):
        raise RuntimeError(f"BLOCK/403 na {url} (status={r.status_code}). Zatrzymuję program.")
    r.raise_for_status()
    return r.text

def list_page_url(base: str, page_no: int) -> str:
    if page_no <= 1:
        return base
    sep = "&" if "?" in base else "?"
    return f"{base}{sep}pn={page_no}"

def parse_listing(html: str) -> List[Dict[str, str]]:
    soup = BeautifulSoup(html, "html.parser")

    # ignoruj rekomendowane
    recommended = soup.find(attrs={"data-test": "section-recommended-offers"})
    if recommended:
        for a in recommended.select('a[data-test="link-offer"][href]'):
            a.decompose()

    offers = []
    for a in soup.select('a[data-test="link-offer"][href]'):
        link = a["href"]
        if link.startswith("/"):
            link = "https://www.pracuj.pl" + link

        title = a.get("title") or a.get_text(" ", strip=True)

        company = ""
        c = a.find_next(attrs={"data-test": "text-company-name"})
        if c:
            company = c.get_text(" ", strip=True)

        offers.append({"Stanowisko": title, "Link": link, "Pracodawca": company})
    return offers

def extract_section_items(soup: BeautifulSoup, header_text: str) -> List[str]:
    # tekstowo (mniej zależne od data-test)
    cands = []
    for tag in soup.find_all(["h2","h3","div","span"]):
        t = tag.get_text(" ", strip=True)
        if t and header_text.lower() in t.lower():
            cands.append(tag)

    items: List[str] = []
    for h in cands:
        ul = h.find_next("ul")
        if not ul:
            continue
        for li in ul.find_all("li"):
            txt = li.get_text(" ", strip=True)
            if txt:
                items.append(txt)
        if items:
            break
    return items

def parse_offer(html: str) -> Dict[str, str]:
    soup = BeautifulSoup(html, "html.parser")
    zakres = extract_section_items(soup, "Twój zakres obowiązków")
    wymag = extract_section_items(soup, "Nasze wymagania")
    return {
        "Zakres obowiązków": " | ".join(zakres),
        "Nasze wymagania": " | ".join(wymag)
    }

def main():
    rows: List[Dict[str, str]] = []

    for p in range(1, PAGES + 1):
        page_url = list_page_url(FILTER_URL, p)
        print(f"📄 Listing {p}: {page_url}")
        listing_html = fetch(page_url)

        # „czytanie listy”
        human_pause(10, 25)

        offers = parse_listing(listing_html)
        print(f"   • ofert: {len(offers)}")

        for i, off in enumerate(offers, start=1):
            print(f"   → ({i}/{len(offers)}) {off['Stanowisko']} | {off['Pracodawca']}")
            offer_html = fetch(off["Link"])

            # „czytanie oferty”
            human_pause(12, 35)

            details = parse_offer(offer_html)
            off.update(details)
            rows.append(off)

            # czasem dłuższa przerwa
            if random.random() < 0.12:
                print("🕓 dłuższa przerwa...")
                human_pause(60, 120)

    df = pd.DataFrame(rows)
    if OUT_FILE.lower().endswith(".csv"):
        df.to_csv(OUT_FILE, index=False)
    else:
        df.to_excel(OUT_FILE, index=False)
    print(f"✅ Zapisano {len(df)} wierszy do {OUT_FILE}")

if __name__ == "__main__":
    main()
