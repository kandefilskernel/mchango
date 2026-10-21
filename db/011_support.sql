-- ============================================================
-- Support : « PIN oublié » validé par l'équipe quand aucun garant ne répond,
-- APRÈS vérification d'identité (motif obligatoire, journalisé).
-- ============================================================

ALTER TABLE pin_reset_requests
    ADD COLUMN decided_by_staff UUID REFERENCES staff(id),
    ADD COLUMN staff_note       TEXT,
    ADD CONSTRAINT pin_reset_single_decider CHECK (decided_by IS NULL OR decided_by_staff IS NULL);
