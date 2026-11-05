-- ============================================================
-- Langues de l'app : français, swahili, lingala, et maintenant anglais.
-- La langue du membre sert aussi aux SMS (code de connexion, rappels).
-- ============================================================

ALTER TABLE users DROP CONSTRAINT users_language_check;
ALTER TABLE users ADD CONSTRAINT users_language_check CHECK (language IN ('fr', 'sw', 'ln', 'en'));
