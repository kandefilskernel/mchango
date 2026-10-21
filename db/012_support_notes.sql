-- ============================================================
-- Support : notes de suivi de l'équipe sur un membre (« appelé à 14 h, rappeler demain »),
-- pour ne pas traiter deux fois la même personne. Notes internes : jamais visibles des membres.
-- Une note ne se modifie ni ne se supprime ; on en ajoute une autre.
-- ============================================================

CREATE TABLE support_notes (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id),
    staff_id   UUID NOT NULL REFERENCES staff(id),
    body       TEXT NOT NULL CHECK (length(btrim(body)) BETWEEN 3 AND 2000),
    -- « à suivre » : la note apparaît dans la page « À traiter » jusqu'à ce qu'une note la clôture
    follow_up  BOOLEAN NOT NULL DEFAULT false,
    closes     UUID REFERENCES support_notes(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_support_notes_user ON support_notes (user_id, created_at DESC);
CREATE UNIQUE INDEX uq_support_notes_closes ON support_notes (closes) WHERE closes IS NOT NULL;

CREATE TRIGGER trg_no_delete_support_notes BEFORE DELETE ON support_notes
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();

GRANT SELECT, INSERT ON support_notes TO mchango_app;

-- Historique des SMS d'un membre (fiche membre du back-office)
CREATE INDEX idx_notifications_user_created ON notifications (user_id, created_at DESC);
