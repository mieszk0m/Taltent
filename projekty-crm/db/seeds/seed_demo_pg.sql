
-- seed_demo_pg.sql (PostgreSQL)
-- Minimal + demo. Zakłada pgcrypto (gen_random_uuid()) już jest (V1).

-- UPRAWNIENIA biznesowe (Twoje role z diagramu)
INSERT INTO uprawnienia(nazwa, opis) VALUES
('Administrator','Pełny dostęp'),
('Pani Prezes','Podgląd całości + decyzje'),
('Starsza Rekruterka','Prowadzi projekty i rekrutację'),
('Młodsza rekruterka','Rekrutacja bez finansów'),
('Zaczepkowicze','Podgląd i działania wspierające')
ON CONFLICT (nazwa) DO NOTHING;

-- PRACOWNICY (directus_user_id na razie NULL - podepniemy po utworzeniu userów w Directus)
INSERT INTO pracownicy(imie_nazwisko, email, telefon, status, id_uprawnienia)
VALUES
('Admin Lokalny','admin@local.test','+48 600 000 000','aktywny',(SELECT id_uprawnienia FROM uprawnienia WHERE nazwa='Administrator')),
('Prezes','prezes@local.test','+48 600 000 001','aktywny',(SELECT id_uprawnienia FROM uprawnienia WHERE nazwa='Pani Prezes')),
('Senior Rekruterka','senior@local.test','+48 600 000 002','aktywny',(SELECT id_uprawnienia FROM uprawnienia WHERE nazwa='Starsza Rekruterka')),
('Junior Rekruterka','junior@local.test','+48 600 000 003','aktywny',(SELECT id_uprawnienia FROM uprawnienia WHERE nazwa='Młodsza rekruterka')),
('Zaczepkowicz','zaczepki@local.test','+48 600 000 004','aktywny',(SELECT id_uprawnienia FROM uprawnienia WHERE nazwa='Zaczepkowicze'))
ON CONFLICT DO NOTHING;

-- KLIENCI
INSERT INTO klienci(nazwa, nip, opis_firmy, osoba_kontaktowa, email, telefon, data_zawarcia_wspolpracy, komentarz)
VALUES
('ABC Sp. z o.o.','1234567890','Software house','Ewa Kontakt','kontakt@abc.pl','+48 22 123 45 67','2025-01-10','Klient stały'),
('XYZ S.A.','9876543210','Produkcja','Adam Zakupy','zakupy@xyz.pl','+48 22 999 88 77','2025-06-01','Nowy klient')
ON CONFLICT DO NOTHING;

-- PROJEKTY (PM = Senior)
INSERT INTO projekty(id_klienta, nazwa_projektu, id_pm, status, marza, priorytet, data_rozpoczecia, komentarz)
SELECT
  k.id_klienta,
  v.nazwa_projektu,
  p.id_pracownika,
  v.status,
  v.marza,
  v.priorytet,
  v.data_rozpoczecia,
  v.komentarz
FROM (VALUES
  ('ABC Sp. z o.o.','Rekrutacja Backend','aktywny',25.50,4,'2025-10-01','Pilne'),
  ('XYZ S.A.','Rekrutacja Sales','planowany',18.00,3,'2025-11-01','Start za miesiąc')
) AS v(firma, nazwa_projektu, status, marza, priorytet, data_rozpoczecia, komentarz)
JOIN klienci k ON k.nazwa = v.firma
JOIN pracownicy p ON p.email = 'senior@local.test';

-- ZESPÓŁ projektu: dodaj Junior i Zaczepkowicza do 1 projektu
INSERT INTO projekt_zespol(id_projektu, id_pracownika, rola_w_projekcie)
SELECT pr.id_projektu, pa.id_pracownika, 'Rekruter'
FROM projekty pr
JOIN pracownicy pa ON pa.email='junior@local.test'
WHERE pr.nazwa_projektu='Rekrutacja Backend'
ON CONFLICT DO NOTHING;

INSERT INTO projekt_zespol(id_projektu, id_pracownika, rola_w_projekcie)
SELECT pr.id_projektu, pa.id_pracownika, 'Zaczepki'
FROM projekty pr
JOIN pracownicy pa ON pa.email='zaczepki@local.test'
WHERE pr.nazwa_projektu='Rekrutacja Backend'
ON CONFLICT DO NOTHING;

-- STANOWISKA
INSERT INTO stanowiska(id_projektu, wymagania, zadania, tryb_pracy, lokalizacja, preferowana_umowa, opis_stanowiska, link_do_oferty, budzet_na_stanowisko, komentarz)
SELECT pr.id_projektu,
       'Go/Java, 4+ lat, SQL','Budowa API, integracje','hybrydowa','Warszawa','b2b',
       'Backend Developer','https://example.com/oferta',25000,'Najważniejsze stanowisko'
FROM projekty pr
WHERE pr.nazwa_projektu='Rekrutacja Backend';

-- KANDYDACI (cv_file_id losowy UUID na demo)
INSERT INTO kandydaci(id_stanowiska, id_projektu, krotki_opis, cv_url, cv_file_id, preferowana_umowa, lokalizacja, wymagania_finansowe, komentarz)
SELECT s.id_stanowiska, s.id_projektu,
       '5 lat Go, microservices','', gen_random_uuid(),'b2b','Warszawa',22000,'Dobry profil'
FROM stanowiska s
JOIN projekty p ON p.id_projektu=s.id_projektu
WHERE p.nazwa_projektu='Rekrutacja Backend';

-- DOKUMENTY + STRONY (pdf_file_id losowy UUID na demo)
INSERT INTO dokumenty(opis, id_projektu, typ_podmiotu, id_pracownika, pdf_file_id)
SELECT 'Umowa ramowa', p.id_projektu, 'pracownik', pr.id_pracownika, gen_random_uuid()
FROM projekty p
JOIN pracownicy pr ON pr.email='senior@local.test'
WHERE p.nazwa_projektu='Rekrutacja Backend';

INSERT INTO dokument_strony(id_dokumentu, numer_strony, tresc)
SELECT d.id_dokumentu, 1, 'Strona 1: Warunki ogólne' FROM dokumenty d WHERE d.opis='Umowa ramowa';
INSERT INTO dokument_strony(id_dokumentu, numer_strony, tresc)
SELECT d.id_dokumentu, 2, 'Strona 2: Zakres usług' FROM dokumenty d WHERE d.opis='Umowa ramowa';

-- DZIAŁANIA WSPIERAJĄCE (np. zaczepki)
INSERT INTO dzialania_wspierajace(id_projektu, id_pracownika, opis, aktywny)
SELECT p.id_projektu, pr.id_pracownika, 'Wysłać 20 wiadomości na LinkedIn do kandydatów Go', true
FROM projekty p
JOIN pracownicy pr ON pr.email='zaczepki@local.test'
WHERE p.nazwa_projektu='Rekrutacja Backend';
