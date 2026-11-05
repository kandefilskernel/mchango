-- ============================================================
-- « PIN oublié » : le code SMS ne suffit pas (vol de carte SIM). Un garant de la tontine
-- (président, ou autre membre si le demandeur est président) doit confirmer.
-- Sans tontine en préparation ou en cours, rien à protéger : le code SMS suffit.
-- ============================================================

CREATE TYPE pin_reset_status AS ENUM ('pending', 'completed', 'rejected', 'cancelled');

CREATE TABLE pin_reset_requests (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            UUID NOT NULL REFERENCES users(id),
    new_pin_hash       TEXT NOT NULL,                -- argon2id, choisi par le demandeur
    device_public_key  TEXT NOT NULL,                -- clé du téléphone qui sera lié
    status             pin_reset_status NOT NULL DEFAULT 'pending',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at         TIMESTAMPTZ NOT NULL,
    decided_by         UUID REFERENCES users(id),    -- garant qui a confirmé ou refusé
    decided_at         TIMESTAMPTZ,
    device_id          UUID REFERENCES devices(id),  -- appareil lié une fois la demande acceptée
    CHECK (decided_by IS NULL OR decided_by <> user_id),
    CHECK ((status = 'completed') = (device_id IS NOT NULL))
);

-- Une seule demande en attente par utilisateur
CREATE UNIQUE INDEX uq_pin_reset_pending ON pin_reset_requests (user_id) WHERE status = 'pending';

GRANT SELECT, INSERT, UPDATE ON pin_reset_requests TO mchango_app;
