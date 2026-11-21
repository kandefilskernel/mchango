-- ============================================================
-- Attestation de régularité (spec/attestations.md) : un relevé des cotisations d'un membre, figé
-- à l'émission, qu'il peut montrer à une IMF, une coopec, un bailleur ou un employeur.
-- Le contenu (JSON) et son empreinte SHA-256 ne changent plus ; seul le retrait (revoked_at) est
-- possible. Quiconque a le code de vérification peut consulter l'attestation : c'est le membre qui
-- choisit de le donner. Ce n'est ni un score de crédit ni une garantie de Mchango.
-- Pas de colonne group_id : journal dans la chaîne du membre (« user:<uuid> »).
-- ============================================================

CREATE TABLE attestations (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(id),
    code         CHAR(10) NOT NULL UNIQUE CHECK (code ~ '^[2-9A-HJKMNP-TV-Z]{10}$'),
    content      TEXT NOT NULL CHECK (content IS JSON),
    content_hash CHAR(64) NOT NULL CHECK (content_hash = encode(digest(convert_to(content, 'UTF8'), 'sha256'), 'hex')),
    issued_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at   TIMESTAMPTZ NOT NULL,
    revoked_at   TIMESTAMPTZ,
    CHECK (expires_at > issued_at)
);

CREATE INDEX idx_attestations_user ON attestations (user_id, issued_at DESC);

-- Seul le retrait change une attestation, une seule fois
CREATE OR REPLACE FUNCTION attestations_guard() RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.id, NEW.user_id, NEW.code, NEW.content, NEW.content_hash, NEW.issued_at, NEW.expires_at)
       IS DISTINCT FROM
       (OLD.id, OLD.user_id, OLD.code, OLD.content, OLD.content_hash, OLD.issued_at, OLD.expires_at)
       OR OLD.revoked_at IS NOT NULL THEN
        RAISE EXCEPTION 'attestations : le contenu est figé, seul un retrait est possible';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_attestations_guard BEFORE UPDATE ON attestations
    FOR EACH ROW EXECUTE FUNCTION attestations_guard();

CREATE TRIGGER trg_audit_attestations AFTER INSERT OR UPDATE ON attestations
    FOR EACH ROW EXECUTE FUNCTION audit_business_change();
CREATE TRIGGER trg_no_delete_attestations BEFORE DELETE ON attestations
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();

GRANT SELECT, INSERT, UPDATE ON attestations TO mchango_app;
