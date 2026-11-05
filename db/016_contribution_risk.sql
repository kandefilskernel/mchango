-- ============================================================
-- Score de risque de chaque déclaration de paiement (couche 2 du contrôle anti-fraude).
-- Calculé une fois, à la déclaration ; ne se modifie pas. Vert / orange / rouge.
-- Volontairement HORS des chaînes de journal des groupes : le payeur ne doit pas apprendre
-- quelles règles l'ont signalé (il saurait les contourner). Seuls le bénéficiaire, le témoin
-- et l'équipe voient le niveau et ses raisons.
-- ============================================================

CREATE TABLE contribution_risk (
    contribution_id UUID PRIMARY KEY REFERENCES contributions(id),
    score           SMALLINT NOT NULL CHECK (score BETWEEN 0 AND 100),
    level           TEXT NOT NULL CHECK (level IN ('green', 'orange', 'red')),
    reasons         JSONB NOT NULL,          -- [{ "code": "...", "points": n }]
    sms_check       JSONB,                   -- ce que l'app du payeur a constaté sur le SMS collé (déclaratif)
    computed_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_contribution_risk_level ON contribution_risk (level, computed_at DESC) WHERE level <> 'green';

CREATE TRIGGER trg_no_delete_contribution_risk BEFORE DELETE ON contribution_risk
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();

GRANT SELECT, INSERT ON contribution_risk TO mchango_app;
