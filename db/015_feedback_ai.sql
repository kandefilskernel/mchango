-- ============================================================
-- Avis des membres et analyses de l'agent IA (aide à l'équipe, jamais de décision automatique).
-- ============================================================

-- Avis libre d'un membre, sur Mchango en général ou sur une de ses tontines
CREATE TABLE member_feedback (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id),
    group_id   UUID REFERENCES groups(id),
    rating     SMALLINT CHECK (rating BETWEEN 1 AND 5),
    body       TEXT NOT NULL CHECK (length(btrim(body)) BETWEEN 3 AND 2000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_member_feedback_created ON member_feedback (created_at DESC);
CREATE INDEX idx_member_feedback_group ON member_feedback (group_id, created_at DESC);

-- Résultat d'une analyse : ce qui a été envoyé (pseudonymisé), ce que l'agent a répondu.
-- Gardé pour relecture et audit ; ne se modifie pas.
CREATE TABLE ai_reviews (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kind          TEXT NOT NULL CHECK (kind IN ('group', 'feedback')),
    group_id      UUID REFERENCES groups(id),
    requested_by  UUID NOT NULL REFERENCES staff(id),
    model         TEXT NOT NULL,
    signals       JSONB NOT NULL,             -- anomalies détectées par règles (sans IA)
    result        JSONB,                      -- réponse structurée de l'agent, null si IA indisponible
    error         TEXT,
    input_tokens  INT,
    output_tokens INT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((kind = 'group') = (group_id IS NOT NULL))
);
CREATE INDEX idx_ai_reviews_created ON ai_reviews (created_at DESC);

CREATE TRIGGER trg_no_delete_member_feedback BEFORE DELETE ON member_feedback
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_no_delete_ai_reviews BEFORE DELETE ON ai_reviews
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();

GRANT SELECT, INSERT ON member_feedback, ai_reviews TO mchango_app;
