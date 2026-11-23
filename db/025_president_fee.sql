-- ============================================================
-- Part du président (spec/president-fee.md).
-- ============================================================
-- Le président peut recevoir un pourcentage de chaque mise, de 0 à 10 %, discuté avec les membres
-- et accepté par chacun en signant le règlement. Il est fixé avant le démarrage et ne change plus.
--
-- Qui paie : le bénéficiaire de chaque tour, sur la mise qu'il reçoit. Les autres membres paient
-- toujours le même montant. Au tour du président, il n'y a rien à payer.
-- Comme une cotisation : le bénéficiaire déclare avoir payé, le président confirme. Mchango ne
-- touche jamais cet argent ; il enregistre la déclaration et la confirmation.

-- En points de base : 100 = 1 %, 1000 = 10 % (plafond). 0 = pas de part du président.
ALTER TABLE groups
    ADD COLUMN president_fee_bps SMALLINT NOT NULL DEFAULT 0
        CHECK (president_fee_bps BETWEEN 0 AND 1000);

-- La part se fixe avant le démarrage : ensuite, elle fait partie du règlement signé
CREATE OR REPLACE FUNCTION groups_lock_president_fee() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status <> 'draft' THEN
        RAISE EXCEPTION 'part du président figée : le groupe a déjà démarré';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_groups_lock_president_fee
    BEFORE UPDATE OF president_fee_bps ON groups
    FOR EACH ROW WHEN (OLD.president_fee_bps IS DISTINCT FROM NEW.president_fee_bps)
    EXECUTE FUNCTION groups_lock_president_fee();

CREATE TYPE president_fee_status AS ENUM ('declared', 'confirmed', 'disputed', 'rejected');

CREATE TABLE president_fees (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id               UUID NOT NULL REFERENCES groups(id),
    cycle_id               UUID NOT NULL,
    payer_membership_id    UUID NOT NULL,   -- le bénéficiaire du tour
    receiver_membership_id UUID NOT NULL,   -- le président
    amount_minor           BIGINT NOT NULL CHECK (amount_minor > 0),
    method                 pay_method NOT NULL,
    tx_reference           VARCHAR(100),
    status                 president_fee_status NOT NULL DEFAULT 'declared',
    note                   TEXT,
    offline_id             UUID NOT NULL UNIQUE,   -- renvoyer la même déclaration ne crée pas de doublon
    declared_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_at             TIMESTAMPTZ,
    FOREIGN KEY (cycle_id, group_id)               REFERENCES cycles (id, group_id),
    FOREIGN KEY (payer_membership_id, group_id)    REFERENCES memberships (id, group_id),
    FOREIGN KEY (receiver_membership_id, group_id) REFERENCES memberships (id, group_id),
    CHECK (payer_membership_id <> receiver_membership_id),
    CHECK (method = 'cash' OR tx_reference IS NOT NULL),
    CHECK (tx_reference IS NULL OR tx_reference = upper(btrim(tx_reference))),
    CHECK ((status = 'declared') = (decided_at IS NULL))
);

-- Une seule part active par tour (on peut redéclarer après un rejet)
CREATE UNIQUE INDEX uq_president_fee_active ON president_fees (cycle_id) WHERE status <> 'rejected';

-- Un même numéro de transaction ne sert qu'une fois, cotisations et parts du président confondues
CREATE OR REPLACE FUNCTION president_fees_check_txref() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.tx_reference IS NOT NULL AND (
        EXISTS (SELECT 1 FROM contributions k
                WHERE k.method = NEW.method AND k.tx_reference = NEW.tx_reference AND k.status <> 'rejected')
        OR EXISTS (SELECT 1 FROM president_fees f
                   WHERE f.id <> NEW.id AND f.method = NEW.method AND f.tx_reference = NEW.tx_reference
                     AND f.status <> 'rejected')
    ) THEN
        RAISE EXCEPTION USING ERRCODE = 'unique_violation', CONSTRAINT = 'uq_president_fee_txref',
            MESSAGE = 'numéro de transaction déjà utilisé';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_president_fees_txref BEFORE INSERT ON president_fees
    FOR EACH ROW EXECUTE FUNCTION president_fees_check_txref();

-- Le payeur est le bénéficiaire du tour, le receveur le président du groupe, le montant celui du
-- règlement : la base le vérifie, pas seulement l'API.
CREATE OR REPLACE FUNCTION president_fees_check_parties() RETURNS TRIGGER AS $$
DECLARE
    v_beneficiary UUID;
    v_expected    BIGINT;
BEGIN
    SELECT c.beneficiary_membership_id,
           (g.contribution_amount_minor
              * ((SELECT count(*) FROM memberships m WHERE m.group_id = g.id AND m.status = 'active') - 1)
              * g.president_fee_bps) / 10000
      INTO v_beneficiary, v_expected
    FROM cycles c JOIN groups g ON g.id = c.group_id
    WHERE c.id = NEW.cycle_id;
    IF NEW.payer_membership_id <> v_beneficiary THEN
        RAISE EXCEPTION 'seul le bénéficiaire du tour paie la part du président';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.id = NEW.receiver_membership_id
                   AND m.role = 'president' AND m.status = 'active') THEN
        RAISE EXCEPTION 'la part du président va au président du groupe';
    END IF;
    IF NEW.amount_minor <> v_expected THEN
        RAISE EXCEPTION 'montant de la part du président : % attendu', v_expected;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_president_fees_parties BEFORE INSERT ON president_fees
    FOR EACH ROW EXECUTE FUNCTION president_fees_check_parties();

-- Une décision ne change plus ; seuls le statut, la note et la date de décision bougent
CREATE OR REPLACE FUNCTION president_fees_guard() RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.group_id, NEW.cycle_id, NEW.payer_membership_id, NEW.receiver_membership_id, NEW.amount_minor,
        NEW.method, NEW.tx_reference, NEW.offline_id, NEW.declared_at)
       IS DISTINCT FROM
       (OLD.group_id, OLD.cycle_id, OLD.payer_membership_id, OLD.receiver_membership_id, OLD.amount_minor,
        OLD.method, OLD.tx_reference, OLD.offline_id, OLD.declared_at) THEN
        RAISE EXCEPTION 'president_fees : seuls le statut et la décision changent';
    END IF;
    IF OLD.status IN ('confirmed', 'rejected') THEN
        RAISE EXCEPTION 'president_fees : une part confirmée ou rejetée ne change plus';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_president_fees_guard BEFORE UPDATE ON president_fees
    FOR EACH ROW EXECUTE FUNCTION president_fees_guard();

-- Journal du groupe ; pas de suppression
CREATE TRIGGER trg_audit_president_fees AFTER INSERT OR UPDATE ON president_fees
    FOR EACH ROW EXECUTE FUNCTION audit_business_change();
CREATE TRIGGER trg_no_delete_president_fees BEFORE DELETE ON president_fees
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();

GRANT SELECT, INSERT, UPDATE ON president_fees TO mchango_app;
