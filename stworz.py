import requests
import random
import time
import re
import os
from bs4 import BeautifulSoup
import pandas as pd

BASE = "https://panoramafirm.pl/terminal/wielkopolska" #TU ZMIENIAMY ADRES WITRYNY
PAGE = BASE + "/firmy,{}.html"
HEAD = {"User-Agent": "Mozilla/5.0"}
x = "panorama_terminale_wielkopolska" #TU ZMIENIAMY NAZWĘ ZAPISANEGO PLIKU
counter = 0

while True:
    suffix = f"_{counter}" if counter else ""
    filename = f"{base_name}{suffix}.xlsx"
    if not os.path.exists(filename):
        break
    counter += 1

x = filename  # uaktualnienie zmiennej z nazwą pliku

# ────────────────────────── helpers ──────────────────────────
def sleep():
    """Lekkie, losowe opóźnienie 0.7-1.8 s"""
    time.sleep(random.uniform(0.7, 1.8))

def get_soup(url):
    rsp = requests.get(url, headers=HEAD, timeout=20)
    soup = BeautifulSoup(rsp.text, "html.parser")
    sleep()                               # <── opóźnienie po każdym żądaniu
    return soup

# ────────────────────────── listing ──────────────────────────
def company_links(page_no: int):
    url = BASE if page_no == 1 else PAGE.format(page_no)
    print("📄 Listing:", url)
    soup = get_soup(url)
    for a in soup.select("li.company-item a.company-name"):
        href = a["href"]
        if href.startswith("http"):
            yield href
        else:
            yield "https://panoramafirm.pl" + href


# ────────────────────────── detail page ──────────────────────
def parse_detail(url: str) -> dict:
    soup = get_soup(url)

    name = soup.select_one("h1").get_text(strip=True)
    address_el = soup.select_one(".address, address")
    address = address_el.get_text(" ", strip=True) if address_el else ""

    phone = email = www = ""

    for row in soup.select(".contact-item"):
        label_el = row.select_one(".font-weight-bold")          # lewa kolumna
        value_el = row.select_one(".align-self-center")         # prawa kolumna
        if not label_el or not value_el:
            continue

        label = label_el.get_text(strip=True).lower()

        # WWW
        if "www" in label or "strona" in label:
            a = value_el.select_one("a[href]")
            if a:
                www = a["href"].strip()

        # Telefon
        # Telefon
        elif "telefon" in label:
            a = value_el.select_one("a")
            phone = ""
            if a:
                # 1. Oryginalny skrócony numer (np. "(34) 32...")
                short_text = a.get_text(strip=True)

                # 2. Jeśli jest data-original-title (pełny) — użyj od razu
                full_from_attr = a.get("data-original-title", "").strip()
                if full_from_attr and not full_from_attr.endswith("..."):
                    phone = full_from_attr

                # 3. Jeśli skrócone (z `...`) — szukaj pełnego w całym HTML
                elif "..." in short_text:
                    prefix = short_text.replace("...", "").strip()

                    # Używamy pełnego tekstu HTML i szukamy dopasowania prefiksu + dalsze cyfry
                    html_text = soup.get_text(" ", strip=True)

                    # przykład: znajdź "(34) 32" + maks. 10 znaków kontynuacji
                    pattern = re.escape(prefix) + r"[ \d\-\)]{2,10}"
                    match = re.search(pattern, html_text)

                    if match:
                        phone = match.group(0).strip()
                    else:
                        phone = prefix  # fallback: tylko dostępny początek

                # 4. Jeśli nie ma `...` — użyj bez zmian
                else:
                    phone = short_text


            

        # Email
        elif "email" in label:
            a = value_el.select_one("a")
            if a:
                email = (a.get("data-company-email") or a.get_text()).strip()

    return {
        "Nazwa firmy": name,
        "Telefon":     phone,
        "Email":       email,
        "Strona www":  www,
        "Lokalizacja": address,
        "Źródło":      url,
    }

# ────────────────────────── main crawl ───────────────────────
records, MAX_PAGES = [], 5                     # ← zmień liczbę stron jeśli chcesz

for page in range(1, MAX_PAGES + 1):
    for link in company_links(page):
        try:
            rec = parse_detail(link)
            records.append(rec)
        except Exception as e:
            print("⚠️ Błąd przy", link, "→", e)

df = pd.DataFrame(records)
df.to_excel(x, index=False)
print(f"✅ Zebrano {len(df)} firm – " + x)
