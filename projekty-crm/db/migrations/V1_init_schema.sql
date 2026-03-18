-- =====================================================================
-- V1_init_schema.sql (PostgreSQL)
-- Schemat danych CRM + Dokumenty + Audyt zmian
-- =====================================================================

-- Przydatne rozszerzenie (UUID, gen_random_uuid())
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =====================================================================
-- SCHEMA AUDYTOWA
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS audit;

-- Globalny log zmian (INSERT/UPDATE/DELETE) dla wszystkich tabel
CREATE TABLE IF NOT EXISTS audit.change_log (
  id_log        bigserial PRIMARY KEY,
  table_name    text NOT NULL,
  action        text NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  record_pk     jsonb NULL,        -- PK jako JSON (obsługuje też composite PK)
  old_data      jsonb NULL,
  new_data      jsonb NULL,
  changed_at    timestamptz NOT NULL DEFAULT now(),
  changed_by    text NULL DEFAULT current_setting('app.current_user', true),
  txid          bigint NOT NULL DEFAULT txid_current()
);

-- Funkcja: ustawianie updated_at (Postgres nie ma ON UPDATE CURRENT_TIMESTAMP)
CREATE OR REPLACE FUNCTION audit.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Funkcja: uniwersalny audyt (przyjmuje listę kolumn PK przez TG_ARGV)
CREATE OR REPLACE FUNCTION audit.log_change_any()
RETURNS trigger AS $$
DECLARE
  v_old jsonb;
  v_new jsonb;
  v_src jsonb;
  v_pk  jsonb := '{}'::jsonb;
  i     int;
  key   text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_old := to_jsonb(OLD);
    v_new := NULL;
    v_src := v_old;
  ELSIF TG_OP = 'UPDATE' THEN
    v_old := to_jsonb(OLD);
    v_new := to_jsonb(NEW);
    v_src := v_new;
  ELSE
    v_old := NULL;
    v_new := to_jsonb(NEW);
    v_src := v_new;
  END IF;

  -- Zbuduj record_pk z przekazanych nazw kolumn PK (może być 1 lub wiele)
  IF TG_NARGS > 0 THEN
    FOR i IN 0..TG_NARGS-1 LOOP
      key := TG_ARGV[i];
      v_pk := v_pk || jsonb_build_object(key, v_src -> key);
    END LOOP;
  END IF;

  INSERT INTO audit.change_log(table_name, action, record_pk, old_data, new_data, changed_by)
  VALUES (
    TG_TABLE_NAME,
    TG_OP,
    NULLIF(v_pk, '{}'::jsonb),
    v_old,
    v_new,
    current_setting('app.current_user', true)
  );

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- TABELA: uprawnienia (role biznesowe)
-- =====================================================================
CREATE TABLE uprawnienia (
  id_uprawnienia bigserial PRIMARY KEY,
  nazwa          text NOT NULL UNIQUE,    -- np. Administrator, Pani Prezes, Starsza Rekruterka, ...
  opis           text
);

-- =====================================================================
-- TABELA: pracownicy
-- =====================================================================
CREATE TABLE pracownicy (
  id_pracownika  bigserial PRIMARY KEY,
  imie_nazwisko  text NOT NULL,
  email          text NOT NULL,
  telefon        text,

  opis_zatrudnienia text,
  status         text NOT NULL DEFAULT 'aktywny'
                 CHECK (status IN ('aktywny','wstrzymany','zakonczony')),
  pensja         numeric(12,2),
  data_rozpoczecia date,

  id_uprawnienia bigint REFERENCES uprawnienia(id_uprawnienia) ON DELETE SET NULL,

  -- jeśli korzystasz z Directus/SSO: tu możesz trzymać ID użytkownika z panelu (opcjonalnie)
  directus_user_id uuid UNIQUE NULL,

  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

-- Unikalność email "bez względu na wielkość liter"
CREATE UNIQUE INDEX uq_pracownicy_email ON pracownicy (lower(email));

-- =====================================================================
-- TABELA: klienci
-- =====================================================================
CREATE TABLE klienci (
  id_klienta     bigserial PRIMARY KEY,

  nazwa          text NOT NULL,       -- opis firmy / nazwa
  nip            text UNIQUE,         -- NIP (tekst, bo czasem bywa z prefixami/spacjami)
  opis_firmy     text,

  osoba_kontaktowa text,
  email          text,
  telefon        text,

  data_zawarcia_wspolpracy date,
  komentarz      text,

  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

-- =====================================================================
-- TABELA: potencjalni_klienci (leady)
-- =====================================================================
CREATE TABLE potencjalni_klienci (
  id_potencjalnego bigserial PRIMARY KEY,

  nazwa          text NOT NULL,
  nip            text UNIQUE,
  opis_firmy     text,
  branza         text,
  osoba_kontaktowa text,
  linkedin       text,
  email          text,
  telefon        text,

  owner_id       bigint REFERENCES pracownicy(id_pracownika) ON DELETE SET NULL,

  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

-- =====================================================================
-- TABELA: projekty
-- =====================================================================
CREATE TABLE projekty (
  id_projektu    bigserial PRIMARY KEY,

  id_klienta     bigint NOT NULL REFERENCES klienci(id_klienta) ON DELETE RESTRICT,
  nazwa_projektu text NOT NULL,

  id_pm          bigint REFERENCES pracownicy(id_pracownika) ON DELETE SET NULL,

  status         text NOT NULL DEFAULT 'planowany'
                 CHECK (status IN ('planowany','aktywny','zakonczony','wstrzymany')),

  marza          numeric(5,2),   -- w %
  priorytet      smallint CHECK (priorytet BETWEEN 1 AND 5),

  data_rozpoczecia date,
  data_zakonczenia date,

  komentarz      text,

  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_projekty_klient_status ON projekty (id_klienta, status);

-- =====================================================================
-- TABELA: projekt_zespol (wiele-do-wielu)
-- =====================================================================
CREATE TABLE projekt_zespol (
  id_projektu   bigint NOT NULL REFERENCES projekty(id_projektu) ON DELETE CASCADE,
  id_pracownika bigint NOT NULL REFERENCES pracownicy(id_pracownika) ON DELETE CASCADE,
  rola_w_projekcie text,
  PRIMARY KEY (id_projektu, id_pracownika)
);

-- =====================================================================
-- TABELA: stanowiska
-- =====================================================================
CREATE TABLE stanowiska (
  id_stanowiska  bigserial PRIMARY KEY,
  id_projektu    bigint NOT NULL REFERENCES projekty(id_projektu) ON DELETE CASCADE,

  wymagania      text,
  zadania        text,

  tryb_pracy     text CHECK (tryb_pracy IN ('stacjonarna','zdalna','hybrydowa')),
  lokalizacja    text,

  preferowana_umowa text CHECK (preferowana_umowa IN ('uop','b2b','uz','ud')),
  opis_stanowiska text,

  link_do_oferty text,
  budzet_na_stanowisko numeric(12,2),

  komentarz      text,

  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_stanowiska_projekt ON stanowiska (id_projektu);

-- =====================================================================
-- TABELA: kandydaci
-- =====================================================================
CREATE TABLE kandydaci (
  id_kandydata   bigserial PRIMARY KEY,

  id_stanowiska  bigint NOT NULL REFERENCES stanowiska(id_stanowiska) ON DELETE CASCADE,
  id_projektu    bigint NOT NULL REFERENCES projekty(id_projektu) ON DELETE CASCADE,

  krotki_opis    text,
  -- CV: możesz trzymać albo link, albo UUID pliku z Directusa (lub oba)
  cv_url         text,
  cv_file_id     uuid,

  preferowana_umowa text CHECK (preferowana_umowa IN ('uop','b2b','uz','ud')),
  lokalizacja    text,
  wymagania_finansowe numeric(12,2),

  komentarz      text,

  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_kandydaci_stanowisko ON kandydaci (id_stanowiska);
CREATE INDEX idx_kandydaci_projekt ON kandydaci (id_projektu);

-- =====================================================================
-- TABELA: dzialania_wspierajace
-- =====================================================================
CREATE TABLE dzialania_wspierajace (
  id_dzialania   bigserial PRIMARY KEY,

  id_projektu    bigint NOT NULL REFERENCES projekty(id_projektu) ON DELETE CASCADE,
  id_pracownika  bigint REFERENCES pracownicy(id_pracownika) ON DELETE SET NULL,

  opis           text,
  aktywny        boolean NOT NULL DEFAULT true,

  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_dzialania_projekt ON dzialania_wspierajace (id_projektu);

-- =====================================================================
-- TABELA: dokumenty
-- =====================================================================
-- Dokument ma:
-- - opcjonalnie id_projektu (bez tabeli projekty_dokumenty)
-- - podmiot: pracownik/klient/inny/talent_it
-- - pdf_file_id: uuid (np. z Directusa) - bez FK (żeby migracja była niezależna od Directusa)
CREATE TABLE dokumenty (
  id_dokumentu   bigserial PRIMARY KEY,

  opis           text,

  id_projektu    bigint NULL REFERENCES projekty(id_projektu) ON DELETE SET NULL,

  typ_podmiotu   text NOT NULL CHECK (typ_podmiotu IN ('pracownik','klient','inny','talent_it')),

  id_pracownika  bigint NULL REFERENCES pracownicy(id_pracownika) ON DELETE SET NULL,
  id_klienta     bigint NULL REFERENCES klienci(id_klienta) ON DELETE SET NULL,

  nazwa_innego   text NULL,
  nazwa_talent_it text NULL,

  pdf_file_id    uuid NOT NULL,

  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),

  -- Spójność: dokładnie jeden wariant podmiotu
  CONSTRAINT ck_dokumenty_podmiot_spojnosc CHECK (
    (typ_podmiotu = 'pracownik' AND id_pracownika IS NOT NULL AND id_klienta IS NULL AND nazwa_innego IS NULL AND nazwa_talent_it IS NULL)
 OR (typ_podmiotu = 'klient'    AND id_klienta    IS NOT NULL AND id_pracownika IS NULL AND nazwa_innego IS NULL AND nazwa_talent_it IS NULL)
 OR (typ_podmiotu = 'inny'      AND nazwa_innego  IS NOT NULL AND id_pracownika IS NULL AND id_klienta IS NULL AND nazwa_talent_it IS NULL)
 OR (typ_podmiotu = 'talent_it' AND nazwa_talent_it IS NOT NULL AND id_pracownika IS NULL AND id_klienta IS NULL AND nazwa_innego IS NULL)
  )
);

CREATE INDEX idx_dokumenty_projekt ON dokumenty (id_projektu);
CREATE INDEX idx_dokumenty_typ ON dokumenty (typ_podmiotu);

-- =====================================================================
-- TABELA: dokument_strony (wiele stron dokumentu)
-- =====================================================================
CREATE TABLE dokument_strony (
  id_strony      bigserial PRIMARY KEY,
  id_dokumentu   bigint NOT NULL REFERENCES dokumenty(id_dokumentu) ON DELETE CASCADE,
  numer_strony   integer NOT NULL CHECK (numer_strony > 0),
  tresc          text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_dokument_strona UNIQUE (id_dokumentu, numer_strony)
);

CREATE INDEX idx_dokument_strony_dok ON dokument_strony (id_dokumentu);

-- =====================================================================
-- TRIGGERS: updated_at
-- =====================================================================
CREATE TRIGGER trg_set_updated_at_pracownicy
BEFORE UPDATE ON pracownicy
FOR EACH ROW EXECUTE FUNCTION audit.set_updated_at();

CREATE TRIGGER trg_set_updated_at_klienci
BEFORE UPDATE ON klienci
FOR EACH ROW EXECUTE FUNCTION audit.set_updated_at();

CREATE TRIGGER trg_set_updated_at_potencjalni_klienci
BEFORE UPDATE ON potencjalni_klienci
FOR EACH ROW EXECUTE FUNCTION audit.set_updated_at();

CREATE TRIGGER trg_set_updated_at_projekty
BEFORE UPDATE ON projekty
FOR EACH ROW EXECUTE FUNCTION audit.set_updated_at();

CREATE TRIGGER trg_set_updated_at_stanowiska
BEFORE UPDATE ON stanowiska
FOR EACH ROW EXECUTE FUNCTION audit.set_updated_at();

CREATE TRIGGER trg_set_updated_at_kandydaci
BEFORE UPDATE ON kandydaci
FOR EACH ROW EXECUTE FUNCTION audit.set_updated_at();

CREATE TRIGGER trg_set_updated_at_dzialania_wspierajace
BEFORE UPDATE ON dzialania_wspierajace
FOR EACH ROW EXECUTE FUNCTION audit.set_updated_at();

CREATE TRIGGER trg_set_updated_at_dokumenty
BEFORE UPDATE ON dokumenty
FOR EACH ROW EXECUTE FUNCTION audit.set_updated_at();

-- =====================================================================
-- TRIGGERS: AUDYT ZMIAN (INSERT/UPDATE/DELETE)
-- =====================================================================
CREATE TRIGGER trg_audit_uprawnienia
AFTER INSERT OR UPDATE OR DELETE ON uprawnienia
FOR EACH ROW EXECUTE FUNCTION audit.log_change_any('id_uprawnienia');

CREATE TRIGGER trg_audit_pracownicy
AFTER INSERT OR UPDATE OR DELETE ON pracownicy
FOR EACH ROW EXECUTE FUNCTION audit.log_change_any('id_pracownika');

CREATE TRIGGER trg_audit_klienci
AFTER INSERT OR UPDATE OR DELETE ON klienci
FOR EACH ROW EXECUTE FUNCTION audit.log_change_any('id_klienta');

CREATE TRIGGER trg_audit_potencjalni_klienci
AFTER INSERT OR UPDATE OR DELETE ON potencjalni_klienci
FOR EACH ROW EXECUTE FUNCTION audit.log_change_any('id_potencjalnego');

CREATE TRIGGER trg_audit_projekty
AFTER INSERT OR UPDATE OR DELETE ON projekty
FOR EACH ROW EXECUTE FUNCTION audit.log_change_any('id_projektu');

-- Composite PK -> przekazujemy oba klucze
CREATE TRIGGER trg_audit_projekt_zespol
AFTER INSERT OR UPDATE OR DELETE ON projekt_zespol
FOR EACH ROW EXECUTE FUNCTION audit.log_change_any('id_projektu','id_pracownika');

CREATE TRIGGER trg_audit_stanowiska
AFTER INSERT OR UPDATE OR DELETE ON stanowiska
FOR EACH ROW EXECUTE FUNCTION audit.log_change_any('id_stanowiska');

CREATE TRIGGER trg_audit_kandydaci
AFTER INSERT OR UPDATE OR DELETE ON kandydaci
FOR EACH ROW EXECUTE FUNCTION audit.log_change_any('id_kandydata');

CREATE TRIGGER trg_audit_dzialania_wspierajace
AFTER INSERT OR UPDATE OR DELETE ON dzialania_wspierajace
FOR EACH ROW EXECUTE FUNCTION audit.log_change_any('id_dzialania');

CREATE TRIGGER trg_audit_dokumenty
AFTER INSERT OR UPDATE OR DELETE ON dokumenty
FOR EACH ROW EXECUTE FUNCTION audit.log_change_any('id_dokumentu');

CREATE TRIGGER trg_audit_dokument_strony
AFTER INSERT OR UPDATE OR DELETE ON dokument_strony
FOR EACH ROW EXECUTE FUNCTION audit.log_change_any('id_strony');

-- =====================================================================
-- KONIEC V1
-- =====================================================================

wt., 10 lut 2026 o 18:17 mieszkolak12@wp.pl <mieszkolak12@wp.pl> napisał(a):

        Dnia 10 lutego 2026 17:59 mieszko < makowskimieszko6@gmail.com > napisał(a):
        # PostgreSQL
        POSTGRES_DB=crm
        POSTGRES_USER=app_user
        POSTGRES_PASSWORD=app_pass_str0ng
        POSTGRES_PORT=5432

        # Directus
        DIRECTUS_PORT=8055
        DIRECTUS_KEY=PASTE_32+_HEX
        DIRECTUS_SECRET=PASTE_32+_HEX
        ADMIN_EMAIL=admin@local.test
        ADMIN_PASSWORD=Admin#12345
        TZ=Europe/Warsaw




        services:
          postgres:
            image: postgres:16
            restart: unless-stopped
            env_file: .env
            environment:
              POSTGRES_DB: ${POSTGRES_DB}
              POSTGRES_USER: ${POSTGRES_USER}
              POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
              TZ: ${TZ}
            ports:
              - "127.0.0.1:${POSTGRES_PORT}:5432"
            volumes:
              - pg_data:/var/lib/postgresql/data
            healthcheck:
              test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
              interval: 10s
              timeout: 5s
              retries: 10

          directus:
            image: directus/directus:latest
            restart: unless-stopped
            env_file: .env
            depends_on:
              postgres:
                condition: service_healthy
            environment:
              KEY: ${DIRECTUS_KEY}
              SECRET: ${DIRECTUS_SECRET}
              DB_CLIENT: "pg"
              DB_HOST: "postgres"
              DB_PORT: "5432"
              DB_DATABASE: ${POSTGRES_DB}
              DB_USER: ${POSTGRES_USER}
              DB_PASSWORD: ${POSTGRES_PASSWORD}
              ADMIN_EMAIL: ${ADMIN_EMAIL}
              ADMIN_PASSWORD: ${ADMIN_PASSWORD}
              WEBSOCKETS_ENABLED: "true"
              TZ: ${TZ}
            ports:
              - "127.0.0.1:${DIRECTUS_PORT}:8055"
            volumes:
              - directus_uploads:/directus/uploads

          adminer: # opcjonalnie, obsługuje Postgres też
            image: adminer:latest
            restart: unless-stopped
            depends_on:
              - postgres
            ports:
              - "127.0.0.1:8080:8080"

        volumes:
          pg_data:
          directus_uploads:
