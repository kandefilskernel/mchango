-- ============================================================
-- Back-office de l'équipe : comptes, motifs des blocages et suspensions, décisions de litige.
-- Toute action de l'équipe est journalisée (acteur « staff »), dans la chaîne du groupe concerné
-- quand il y en a un : les membres voient ce que l'équipe a fait chez eux.
-- ============================================================

ALTER TABLE staff
    ADD COLUMN last_login_at       TIMESTAMPTZ,
    ADD COLUMN password_changed_at TIMESTAMPTZ;

ALTER TABLE users  ADD COLUMN blocked_reason   TEXT;
ALTER TABLE groups ADD COLUMN suspended_reason TEXT;

-- Le statut d'avant la suspension, pour réactiver sans se tromper (brouillon ou en cours)
ALTER TABLE groups ADD COLUMN status_before_suspension group_status;

ALTER TABLE disputes ADD COLUMN resolved_by_staff UUID REFERENCES staff(id);

-- Le rôle applicatif lit et met à jour les comptes de l'équipe (pas de suppression : désactivation)
GRANT SELECT, INSERT, UPDATE ON staff TO mchango_app;
