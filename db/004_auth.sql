-- ============================================================
-- Authentification (itération 1, semaine 1)
--   OTP et défis de connexion : dans Redis (éphémères), pas en base.
--   PIN : vérifié par le serveur uniquement pour lier un nouvel appareil ;
--         verrouillage après plusieurs échecs.
-- ============================================================

ALTER TABLE users
    ADD COLUMN pin_failed_attempts SMALLINT NOT NULL DEFAULT 0 CHECK (pin_failed_attempts >= 0),
    ADD COLUMN pin_locked_until    TIMESTAMPTZ;

-- Une clé publique ne sert qu'à un seul appareil
ALTER TABLE devices
    ADD CONSTRAINT devices_public_key_unique UNIQUE (public_key);

-- MVP : un seul appareil actif par utilisateur (changer de téléphone révoque l'ancien)
CREATE UNIQUE INDEX uq_devices_one_active_per_user
    ON devices (user_id) WHERE revoked_at IS NULL;
