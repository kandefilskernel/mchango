-- ============================================================
-- Cash au MVP : le receveur confirme ET un témoin (autre membre du groupe) confirme.
-- ============================================================

ALTER TYPE decision_type ADD VALUE IF NOT EXISTS 'witness';

-- Le témoin est désigné par le payeur au moment de la déclaration.
ALTER TABLE contributions
    ADD COLUMN witness_membership_id UUID,
    ADD CONSTRAINT contributions_witness_same_group
        FOREIGN KEY (witness_membership_id, group_id) REFERENCES memberships (id, group_id),
    ADD CONSTRAINT contributions_cash_needs_witness
        CHECK (method <> 'cash' OR witness_membership_id IS NOT NULL),
    ADD CONSTRAINT contributions_witness_is_third_party
        CHECK (witness_membership_id IS NULL
               OR (witness_membership_id <> payer_membership_id
                   AND witness_membership_id <> receiver_membership_id));

-- Une même personne ne donne pas deux fois la même réponse sur une cotisation
CREATE UNIQUE INDEX uq_confirmations_once
    ON confirmations (contribution_id, confirmed_by, decision);

-- Qui peut répondre à une déclaration :
--   confirm  : seulement le receveur prévu ;
--   witness  : seulement le témoin désigné, et seulement pour le cash ;
--   dispute  : tout membre actif du groupe.
CREATE OR REPLACE FUNCTION confirmations_check_receiver() RETURNS TRIGGER AS $$
DECLARE
    c        contributions%ROWTYPE;
    v_status member_status;
    v_group  UUID;
BEGIN
    SELECT * INTO c FROM contributions WHERE id = NEW.contribution_id;
    SELECT status, group_id INTO v_status, v_group FROM memberships WHERE id = NEW.confirmed_by;

    IF v_group IS DISTINCT FROM c.group_id OR v_status <> 'active' THEN
        RAISE EXCEPTION 'seul un membre actif du groupe peut répondre à une cotisation';
    END IF;
    IF NEW.decision = 'confirm' AND NEW.confirmed_by <> c.receiver_membership_id THEN
        RAISE EXCEPTION 'seul le receveur de la cotisation peut la confirmer';
    END IF;
    IF NEW.decision = 'witness'
       AND (c.method <> 'cash' OR NEW.confirmed_by IS DISTINCT FROM c.witness_membership_id) THEN
        RAISE EXCEPTION 'seul le témoin désigné peut témoigner, et seulement pour du cash';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Une cotisation ne passe « confirmed » qu'avec les confirmations requises.
CREATE OR REPLACE FUNCTION contributions_check_confirmed() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'confirmed' AND OLD.status IS DISTINCT FROM 'confirmed' THEN
        IF NOT EXISTS (SELECT 1 FROM confirmations
                       WHERE contribution_id = NEW.id AND decision = 'confirm'
                         AND confirmed_by = NEW.receiver_membership_id) THEN
            RAISE EXCEPTION 'cotisation non confirmée par son receveur';
        END IF;
        IF NEW.method = 'cash' AND NOT EXISTS (
               SELECT 1 FROM confirmations
               WHERE contribution_id = NEW.id AND decision = 'witness'
                 AND confirmed_by = NEW.witness_membership_id) THEN
            RAISE EXCEPTION 'cotisation en espèces sans confirmation du témoin';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_contributions_check_confirmed
    BEFORE UPDATE OF status ON contributions
    FOR EACH ROW EXECUTE FUNCTION contributions_check_confirmed();

-- Pas de cotisation créée directement au statut confirmé
CREATE OR REPLACE FUNCTION contributions_check_initial_status() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status <> 'declared' THEN
        RAISE EXCEPTION 'une cotisation est créée au statut « declared »';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_contributions_initial_status
    BEFORE INSERT ON contributions
    FOR EACH ROW EXECUTE FUNCTION contributions_check_initial_status();
