-- ============================================================
-- Invitations par code (itération 1, semaine 1)
-- Le président crée un code à partager (WhatsApp, oral) ; on rejoint en le saisissant.
-- Un code n'est pas lié à un numéro : `phone` devient facultatif.
-- ============================================================

ALTER TABLE invitations
    ALTER COLUMN phone DROP NOT NULL,
    ADD COLUMN max_uses   INT CHECK (max_uses IS NULL OR max_uses > 0),
    ADD COLUMN uses       INT NOT NULL DEFAULT 0 CHECK (uses >= 0),
    ADD COLUMN revoked_at TIMESTAMPTZ,
    ADD CONSTRAINT invitations_uses_within_max CHECK (max_uses IS NULL OR uses <= max_uses);

-- Taille maximale d'un groupe, fixée à la création
ALTER TABLE groups
    ADD COLUMN max_members INT NOT NULL DEFAULT 30 CHECK (max_members BETWEEN 2 AND 100);

CREATE INDEX idx_invitations_group ON invitations (group_id) WHERE revoked_at IS NULL;
