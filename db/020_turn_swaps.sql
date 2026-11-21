-- ============================================================
-- Échange de tour entre deux membres, après le démarrage (spec/swaps.md).
-- Un membre en urgence (deuil, minerval, loyer) propose à un autre d'échanger leurs tours.
-- L'échange n'a lieu que si l'autre accepte. Les dates des tours ne bougent pas : seuls les
-- bénéficiaires des deux tours sont échangés. Le montant et le calendrier des autres membres ne
-- changent pas ; chacun voit l'échange dans le journal du groupe.
-- Mchango ne touche toujours aucun argent : on échange qui reçoit, pas des fonds.
-- ============================================================

-- L'échange inverse deux bénéficiaires dans une même instruction : l'unicité doit être vérifiée
-- en fin de transaction, pas ligne par ligne (un index unique ne peut pas être différé).
DROP INDEX uq_cycles_beneficiary;
ALTER TABLE cycles ADD CONSTRAINT uq_cycles_beneficiary
    UNIQUE (group_id, beneficiary_membership_id) DEFERRABLE INITIALLY IMMEDIATE;

CREATE TYPE swap_status AS ENUM ('pending', 'accepted', 'declined', 'cancelled');

CREATE TABLE turn_swaps (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id                UUID NOT NULL REFERENCES groups(id),
    requester_membership_id UUID NOT NULL,
    target_membership_id    UUID NOT NULL,
    -- Tours au moment de la demande : si l'un d'eux a changé entre-temps, l'échange est refusé
    requester_cycle_number  INT NOT NULL,
    target_cycle_number     INT NOT NULL,
    reason                  VARCHAR(200),
    status                  swap_status NOT NULL DEFAULT 'pending',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at              TIMESTAMPTZ NOT NULL DEFAULT now() + interval '72 hours',
    decided_at              TIMESTAMPTZ,
    FOREIGN KEY (requester_membership_id, group_id) REFERENCES memberships (id, group_id),
    FOREIGN KEY (target_membership_id, group_id)    REFERENCES memberships (id, group_id),
    FOREIGN KEY (group_id, requester_cycle_number)  REFERENCES cycles (group_id, cycle_number),
    FOREIGN KEY (group_id, target_cycle_number)     REFERENCES cycles (group_id, cycle_number),
    CHECK (requester_membership_id <> target_membership_id),
    CHECK (requester_cycle_number <> target_cycle_number),
    CHECK ((status = 'pending') = (decided_at IS NULL))
);

-- Une seule demande en attente par demandeur et par groupe
CREATE UNIQUE INDEX uq_turn_swaps_pending ON turn_swaps (group_id, requester_membership_id)
    WHERE status = 'pending';
CREATE INDEX idx_turn_swaps_group ON turn_swaps (group_id, created_at DESC);

-- Une demande ne change que de statut, une seule fois (pending → décision)
CREATE OR REPLACE FUNCTION turn_swaps_guard() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status <> 'pending' THEN
        RAISE EXCEPTION 'turn_swaps : une demande décidée ne change plus';
    END IF;
    IF (NEW.group_id, NEW.requester_membership_id, NEW.target_membership_id, NEW.requester_cycle_number,
        NEW.target_cycle_number, NEW.reason, NEW.created_at, NEW.expires_at)
       IS DISTINCT FROM
       (OLD.group_id, OLD.requester_membership_id, OLD.target_membership_id, OLD.requester_cycle_number,
        OLD.target_cycle_number, OLD.reason, OLD.created_at, OLD.expires_at) THEN
        RAISE EXCEPTION 'turn_swaps : seuls le statut et la date de décision changent';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_turn_swaps_guard BEFORE UPDATE ON turn_swaps
    FOR EACH ROW EXECUTE FUNCTION turn_swaps_guard();

-- Le bénéficiaire d'un tour ne change que par un échange accepté dans la même transaction, et
-- seulement tant que personne n'a déclaré de paiement pour ce tour (sinon, l'argent est déjà parti
-- vers l'ancien bénéficiaire).
CREATE OR REPLACE FUNCTION cycles_guard_beneficiary() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status NOT IN ('open', 'upcoming') THEN
        RAISE EXCEPTION 'tour % clos : son bénéficiaire ne change plus', OLD.cycle_number;
    END IF;
    IF EXISTS (SELECT 1 FROM contributions k WHERE k.cycle_id = OLD.id AND k.status <> 'rejected') THEN
        RAISE EXCEPTION 'tour % : des paiements sont déjà déclarés, le bénéficiaire ne change plus', OLD.cycle_number;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM turn_swaps s
        WHERE s.group_id = OLD.group_id AND s.status = 'accepted' AND s.decided_at = now()
          AND OLD.cycle_number IN (s.requester_cycle_number, s.target_cycle_number)
    ) THEN
        RAISE EXCEPTION 'tour % : le bénéficiaire ne change que par un échange accepté', OLD.cycle_number;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_cycles_guard_beneficiary
    BEFORE UPDATE OF beneficiary_membership_id ON cycles
    FOR EACH ROW WHEN (OLD.beneficiary_membership_id IS DISTINCT FROM NEW.beneficiary_membership_id)
    EXECUTE FUNCTION cycles_guard_beneficiary();

-- Journal du groupe (colonne group_id) ; pas de suppression
CREATE TRIGGER trg_audit_turn_swaps AFTER INSERT OR UPDATE ON turn_swaps
    FOR EACH ROW EXECUTE FUNCTION audit_business_change();
CREATE TRIGGER trg_no_delete_turn_swaps BEFORE DELETE ON turn_swaps
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();

GRANT SELECT, INSERT, UPDATE ON turn_swaps TO mchango_app;
