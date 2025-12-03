#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Pracuj.pl scraper z fallbackiem Selenium przy 403."""

FILTER_URL = "https://inzynieria.pracuj.pl/praca/kierownik%20projektu;kw/swarzedz;wp?rd=100&engSpec=electrical-and-electronic%2Cmechanical-manufacturing%2Cindustrial-and-management%2Cagricultural-and-biological"
PAGES      = 1
OUT_FILE   = "kierownik_projektu_swarzedz.xlsx"

import os, tempfile, time, random
from typing import List, Dict, Iterable
import requests
from bs4 import BeautifulSoup
import pandas as pd

HEAD = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "pl-PL,pl;q=0.9,en-US;q=0.8,en;q=0.7",
    "Cache-Control": "no-cache",
    "Pragma": "no-cache",
    "Referer": "https://www.pracuj.pl/",
    "Connection": "keep-alive",
    "Upgrade-Insecure-Requests": "1",
}
SESSION = requests.Session()
SESSION.headers.update(HEAD)

def sleep():
    time.sleep(random.uniform(0.6, 1.4))

_driver = None
def _init_driver():
    global _driver
    if _driver is not None:
        return _driver
    from selenium import webdriver
    from selenium.webdriver.chrome.service import Service
    from webdriver_manager.chrome import ChromeDriverManager
    options = webdriver.ChromeOptions()
    options.add_argument(f"user-data-dir={os.path.join(tempfile.gettempdir(), 'pracuj_sess')}")
    options.page_load_strategy = "eager"
    _driver = webdriver.Chrome(service=Service(ChromeDriverManager().install()), options=options)
    _driver.set_page_load_timeout(45)
    return _driver

def get_html_selenium(url: str) -> str:
    d = _init_driver()
    d.get(url)
    time.sleep(2.0)
    return d.page_source

def get_html(url: str) -> str:
    try:
        r = SESSION.get(url, timeout=25, allow_redirects=True)
        if r.status_code == 403 or "Access Denied" in r.text[:200]:
            raise requests.HTTPError("blocked")
        r.raise_for_status()
        sleep()
        return r.text
    except Exception:
        print(f"   -> Fallback Selenium: {url}")
        return get_html_selenium(url)

def get_soup(url: str) -> BeautifulSoup:
    html = get_html(url)
    return BeautifulSoup(html, "html.parser")

def list_page_url(base: str, page_no: int) -> str:
    if page_no <= 1: return base
    sep = "&" if "?" in base else "?"
    return f"{base}{sep}pn={page_no}"

def parse_listing_page(soup: BeautifulSoup) -> Iterable[Dict[str, str]]:
    """Zwraca tylko oferty z głównej sekcji, ignoruje 'Oferty rekomendowane dla Ciebie'."""
    # Znajdź główną sekcję ofert (zanim pojawi się 'section-recommended-offers')
    main_section = soup.find(attrs={'data-test': 'section-offers'})
    if not main_section:
        # fallback — jeśli struktura inna
        main_section = soup

    # Odetnij część poniżej 'section-recommended-offers'
    recommended = soup.find(attrs={'data-test': 'section-recommended-offers'})
    if recommended:
        # usuwamy wszystkie elementy po sekcji rekomendowanej
        for el in list(main_section.find_all_next()):
            if el == recommended:
                break

    for a in main_section.select('a[data-test="link-offer"][href]'):
        link = a['href']
        if link.startswith('/'):
            link = 'https://www.pracuj.pl' + link
        title = a.get('title') or a.get_text(" ", strip=True)

        tile = a
        for _ in range(5):
            if tile and tile.has_attr('data-test') and 'offer' in tile.get('data-test',''):
                break
            tile = tile.parent

        employer = ''
        name_el = a.find_next(attrs={'data-test': 'text-company-name'}) or \
                  (tile.select_one('[data-test="text-company-name"]') if tile else None)
        if name_el:
            employer = name_el.get_text(" ", strip=True)

        yield {"Stanowisko": title, "Link": link, "Pracodawca": employer}

def extract_section_items(soup: BeautifulSoup, header_text: str):
    header_map = {'Twój zakres obowiązków': ['section-responsibilities-header'],
                  'Nasze wymagania': ['section-requirements-header']}
    cands = []
    for dt in header_map.get(header_text, []):
        cands.extend(soup.select(f'[data-test="{dt}"]'))
    if not cands:
        for tag in soup.find_all(['h2','h3','div','span']):
            t = tag.get_text(" ", strip=True)
            if t and header_text.lower() in t.lower():
                cands.append(tag)
    items = []
    for h in cands:
        ptr = h; ul = None
        for _ in range(30):
            ptr = ptr.find_next()
            if ptr is None: break
            if ptr.name == 'ul':
                ul = ptr; break
        if not ul: continue
        for li in ul.find_all('li'):
            txt = li.get_text(" ", strip=True)
            if txt: items.append(txt)
        if items: break
    return items

def parse_offer_detail(url: str) -> Dict[str, str]:
    soup = get_soup(url)
    zakres = extract_section_items(soup, 'Twój zakres obowiązków')
    wymag = extract_section_items(soup, 'Nasze wymagania')
    return {'Zakres obowiązków': " | ".join(zakres),
            'Nasze wymagania':   " | ".join(wymag)}

def crawl() -> pd.DataFrame:
    rows: List[Dict[str, str]] = []
    for p in range(1, PAGES+1):
        url = list_page_url(FILTER_URL, p)
        print(f"📄 Strona {p}: {url}")
        soup = get_soup(url)
        offers = list(parse_listing_page(soup))
        print(f"   • ofert na liście: {len(offers)}")
        for off in offers:
            try:
                details = parse_offer_detail(off['Link'])
            except Exception as e:
                print("     ⚠️ błąd na ofercie:", off['Link'], e)
                details = {'Zakres obowiązków': '', 'Nasze wymagania': ''}
            off.update(details)
            rows.append(off)
    return pd.DataFrame(rows)

def main():
    df = crawl()
    if OUT_FILE.lower().endswith('.csv'):
        df.to_csv(OUT_FILE, index=False)
    else:
        df.to_excel(OUT_FILE, index=False)
    print(f"✅ Zapisano {len(df)} wierszy do {OUT_FILE}")
    global _driver
    try:
        if _driver is not None: _driver.quit()
    except Exception: pass

if __name__ == '__main__':
    main()
