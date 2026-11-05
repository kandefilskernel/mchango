-- ============================================================
-- Semaine 2 : ordre des tours, génération des cycles, cotisations
-- MVP : un groupe = une rotation (N membres → N cycles). Une nouvelle rotation
-- se fera en créant un nouveau groupe.
-- ============================================================

ALTER TABLE groups
    ADD COLUMN turn_order_mode   VARCHAR(10) CHECK (turn_order_mode IN ('chosen', 'draw')),
    ADD COLUMN draw_seed         CHAR(64),   -- graine publiée : chacun peut refaire le tirage
    ADD COLUMN draw_members_hash CHAR(64),   -- membres au moment du tirage
    ADD COLUMN started_at        TIMESTAMPTZ,
    ADD CONSTRAINT groups_draw_has_seed
        CHECK (turn_order_mode IS DISTINCT FROM 'draw'
               OR (draw_seed IS NOT NULL AND draw_members_hash IS NOT NULL));

-- Un membre n'est bénéficiaire qu'une fois par rotation
CREATE UNIQUE INDEX uq_cycles_beneficiary ON cycles (group_id, beneficiary_membership_id);

-- L'ordre des tours est figé dès que le groupe a démarré
CREATE OR REPLACE FUNCTION memberships_lock_turn_order() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.turn_order IS DISTINCT FROM OLD.turn_order
       AND (SELECT status FROM groups WHERE id = NEW.group_id) <> 'draft' THEN
        RAISE EXCEPTION 'ordre des tours figé : le groupe a déjà démarré';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_memberships_lock_turn_order
    BEFORE UPDATE OF turn_order ON memberships
    FOR EACH ROW EXECUTE FUNCTION memberships_lock_turn_order();

-- Mode direct : on paie le bénéficiaire du tour, pas quelqu'un d'autre
CREATE OR REPLACE FUNCTION contributions_check_receiver() RETURNS TRIGGER AS $$
DECLARE
    v_mode        payout_mode_type;
    v_beneficiary UUID;
BEGIN
    SELECT g.payout_mode, c.beneficiary_membership_id INTO v_mode, v_beneficiary
    FROM cycles c JOIN groups g ON g.id = c.group_id
    WHERE c.id = NEW.cycle_id;
    IF v_mode = 'direct_to_beneficiary' AND NEW.receiver_membership_id <> v_beneficiary THEN
        RAISE EXCEPTION 'en mode direct, le receveur est le bénéficiaire du tour';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_contributions_check_receiver
    BEFORE INSERT ON contributions
    FOR EACH ROW EXECUTE FUNCTION contributions_check_receiver();

CREATE INDEX idx_contrib_cycle_status ON contributions (cycle_id, status);
