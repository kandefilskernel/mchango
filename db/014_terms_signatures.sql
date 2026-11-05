-- ============================================================
-- Signature du règlement par chaque membre avant le démarrage d'une tontine.
-- Le règlement signé est résumé par une empreinte (terms_hash) du montant, de la devise, de la
-- fréquence, de la date de début et de l'ordre des tours (spec/groups.md). Si le président change
-- l'un d'eux, l'empreinte change : les anciennes signatures ne comptent plus, il faut re-signer.
-- Une signature ne se modifie ni ne se supprime (ajout seul, comme le journal).
-- ============================================================

CREATE TABLE group_terms_signatures (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id      UUID NOT NULL REFERENCES groups(id),
    membership_id UUID NOT NULL,
    terms_hash    CHAR(64) NOT NULL CHECK (terms_hash ~ '^[0-9a-f]{64}$'),
    device_id     UUID REFERENCES devices(id),
    signed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (membership_id, group_id) REFERENCES memberships (id, group_id),
    UNIQUE (group_id, membership_id, terms_hash)
);

CREATE TRIGGER trg_no_delete_terms_signatures BEFORE DELETE ON group_terms_signatures
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();

GRANT SELECT, INSERT ON group_terms_signatures TO mchango_app;
