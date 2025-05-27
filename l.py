from selenium import webdriver
from selenium.webdriver.common.by import By
import requests
import random
import time
import re
import os
from bs4 import BeautifulSoup
from typing import Optional
import pandas as pd

# To WKLEJAMY LINK
search_url = "https://www.linkedin.com/search/results/companies/?companyHqGeo=%5B%22106398853%22%5D&industryCompanyVertical=%5B%2227%22%5D&origin=FACETED_SEARCH&sid=PG)"


# Tu Możemy zmienić nazwę pliu 

base_name = "firmy_linkedin" #TU ZMIENIAMY NAZWĘ ZAPISANEGO PLIKU

counter = 0
while True:
    suffix = f"_{counter}" if counter else ""
    filename = f"{base_name}{suffix}.xlsx"
    if not os.path.exists(filename):
        break
    counter += 1

t = filename  # uaktualnienie zmiennej z nazwą pliku


# Konfiguracja przeglądarki z sesją logowania
options = webdriver.ChromeOptions()
options.add_argument("user-data-dir=C:\\Users\\DELL\\AppData\\Local\\Google\\Chrome\\User Data\\selenium_session")
driver = webdriver.Chrome(options=options)

# Otwórz wyszukiwanie firm
driver.get(search_url)
time.sleep(30) #Czas na zalogowanie

html_source = driver.page_source
soup = BeautifulSoup(html_source, "html.parser")

def sleep():
    """Lekkie, losowe opóźnienie 0.7-1.8 s"""
    time.sleep(random.uniform(0.7, 1.8))

def wstaw_fragment_do_linku(link: str, po_znaczniki: str, co_dokleic: str) -> str:
    if po_znaczniki not in link:
        raise ValueError(f"Nie znaleziono '{po_znaczniki}' w podanym linku.")
    return link.replace(po_znaczniki, po_znaczniki + co_dokleic)

def znajdz_email_i_telefon(html: str) -> tuple[Optional[str], Optional[str]]:
    # Usuwamy tagi HTML – żeby łatwiej wyciągnąć czysty tekst
    text_only = re.sub(r"<[^>]+>", " ", html)

    # Szukanie adresu e-mail
    email_pattern = r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"
    email_match = re.search(email_pattern, text_only)

    # Szukanie numeru telefonu (np. +48 123 456 789, 123-456-789 itp.)
    telefon_pattern = r"""
    (?:(?:\+48)?[\s\-]?)?            # +48 (opcjonalnie) + separator
    (?:\(?\d{2,3}\)?[\s\-]?)?        # kierunkowy (2–3 cyfry) w () lub bez
    (?:\d[\s\-\(\)]*){8,}\d          # ≥ 9 cyfr łącznie, z dowolnymi separatorami
"""
    telefon_match = re.search(telefon_pattern, text_only)

    email = email_match.group() if email_match else None
    telefon = telefon_match.group() if telefon_match else None

    return email, telefon

class Firma:
    def __init__(
        self,
        nazwa: str,
        linkedin:Optional[str] = None,
        branza: Optional[str] = None,
        email: Optional[str] = None,
        telefon: Optional[str] = None,
        lokalizacja: Optional[str] = None,
        strona_www: Optional[str] = None,
        wielkosc: Optional[str] = None
    ):
        self.nazwa = nazwa
        self.linkedin = linkedin
        self.branza = branza
        self.email = email
        self.telefon = telefon
        self.lokalizacja = lokalizacja
        self.strona_www = strona_www
        self.wielkosc = wielkosc
     
    def __str__(self):
        return f"Firma(nazwa={self.nazwa}, branża={self.branza}, telefon={self.telefon})"

def stworz_firme_z_html(url: str) -> Firma | None:

    driver.get(url)
    html = driver.page_source
    soup = BeautifulSoup(html, "html.parser")

    # Nazwa firmy
    h1 = soup.find("h1", class_="org-top-card-summary__title")
    if not h1:
        return None
    nazwa = h1.get_text(strip=True)

    linkedin = url

    # Strona www
    link_www = soup.find("a", href=lambda h: h and h.startswith("http") and "linkedin.com" not in h)
    strona_www = link_www["href"] if link_www else None

    # Telefon
    link_tel = soup.find("a", href=lambda h: h and h.startswith("tel:"))
    telefon = link_tel["href"].replace("tel:", "") if link_tel else None

    # Branża
    branza_tag = soup.find_all("dd", class_="mb4 t-black--light text-body-medium")
    branza = branza_tag[1].get_text(strip=True) if len(branza_tag) >= 2 else None

    # Wielkość firmy
    wielkosc_tag = soup.find("dd", class_="t-black--light text-body-medium mb1")
    wielkosc = wielkosc_tag.get_text(strip=True) if wielkosc_tag else None

    # Lokalizacja
    lokalizacja_tag = soup.find("p", class_="t-14 t-black--light t-normal break-words")
    lokalizacja = lokalizacja_tag.get_text(strip=True) if lokalizacja_tag else None

    if strona_www is not None:
        lista_stron = [(strona_www + "/kontakt"),strona_www]
        html = None
        for strona in lista_stron:
            try: 
                response = requests.get(strona, timeout=5,  verify=False)
                if response.status_code == 200:
                    driver.get(strona)
                    html = driver.page_source
                    break
            except requests.RequestException as e:
                print(f"⚠️ Błąd przy połączeniu z {strona_www}: {e}")
                pass

        # Jeśli mamy jakieś HTML, próbujemy wyciągnąć dane
        if html is not None:
            email, telefon = znajdz_email_i_telefon(html)
        else: 
            email = None
    else: 
        email = None


    return Firma(
        nazwa=nazwa,
        linkedin=linkedin,
        branza=branza,
        telefon=telefon,
        email=email,
        lokalizacja=lokalizacja,
        strona_www=strona_www,
        wielkosc=wielkosc
    )

def eksportuj_firmy_do_excel(firmy: list[Firma], nazwa_pliku: str = "firmy.xlsx"):
    dane = []
    for f in firmy:
        dane.append({
            "Nazwa": f.nazwa,
            "Branża": f.branza,
            "E-mail": f.email,
            "Telefon": f.telefon,
            "Lokalizacja": f.lokalizacja,
            "Strona WWW": f.strona_www,
            "Wielkość firmy": f.wielkosc
        })
    
    df = pd.DataFrame(dane)
    df.to_excel(nazwa_pliku, index=False)  # Możesz też użyć .to_csv(...)

    print(f"✅ Zapisano dane do pliku: {nazwa_pliku}")



company_links: set[str] =  set()
for a in soup.find_all("a", href=True):
    href = a["href"]
    if "linkedin.com/company/" in href:
        company_links.add(href + "about/")

x = 0
numer = 2

search_url = wstaw_fragment_do_linku(search_url,"FACETED_SEARCH","&page=")

def czy_brak_wynikow(html: str) -> bool:
    return "Brak wyników" in html


for x in range(2,1000):
    url = wstaw_fragment_do_linku(search_url, "page=", str(x))  
    driver.get(url)
    sleep()
    html_source = driver.page_source
    soup = BeautifulSoup(html_source, "html.parser")
    for a in soup.find_all("a", href=True):
            href = a["href"]
            if "linkedin.com/company/" in href and href not in company_links:
                company_links.add(href + "about/")
    if czy_brak_wynikow(html_source):
        break


dane_firm = []

for firma in company_links:
    w = stworz_firme_z_html(firma)
    dane_firm.append(w)

# Zamknij przeglądarkę
driver.quit()



eksportuj_firmy_do_excel(dane_firm,t)



# Zapisz dane do pliku Excel
#df = pd.DataFrame(companies)
#df.to_excel("linkedin_firmy_rozszerzone.xlsx", index=False)
#print("✅ Zapisano dane do 'linkedin_firmy_rozszerzone.xlsx'")
