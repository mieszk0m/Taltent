-- V3_directus_bridge.sql (PostgreSQL)
-- Uruchamiaj po tym, jak Directus już wystartował (tabele directus_* istnieją)

-- 1) FK: pracownicy.directus_user_id -> directus_users.id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_name = 'fk_pracownicy_directus_user'
  ) THEN
    ALTER TABLE pracownicy
      ADD CONSTRAINT fk_pracownicy_directus_user
      FOREIGN KEY (directus_user_id) REFERENCES directus_users(id)
      ON DELETE SET NULL;
  END IF;
END $$;

-- 2) Widok: które projekty są dostępne dla danego użytkownika Directus
CREATE OR REPLACE VIEW vw_access_matrix AS
SELECT
  p.id_projektu,
  pr.directus_user_id
FROM projekty p
JOIN pracownicy pr ON pr.id_pracownika = p.id_pm
WHERE pr.directus_user_id IS NOT NULL

UNION

SELECT
  z.id_projektu,
  pr.directus_user_id
FROM projekt_zespol z
JOIN pracownicy pr ON pr.id_pracownika = z.id_pracownika
WHERE pr.directus_user_id IS NOT NULL;
