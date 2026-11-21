-- ============================================================
-- Objectifs d'épargne : ce que chaque membre compte faire de la mise qu'il recevra à son tour
-- (minerval, stock, toiture…). Un objectif par adhésion. Il est personnel : la table n'a pas de
-- colonne group_id, il est donc journalisé dans la chaîne du membre (« user:<uuid> »), pas dans
-- celle du groupe. Le membre peut choisir de le montrer au groupe (shared_with_group).
-- La progression est calculée à partir des cotisations confirmées : aucun solde n'est stocké.
-- ============================================================

CREATE TYPE goal_kind AS ENUM ('school', 'business', 'housing', 'health', 'family', 'equipment', 'other');

CREATE TABLE savings_goals (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    membership_id       UUID NOT NULL UNIQUE REFERENCES memberships(id),
    kind                goal_kind NOT NULL,
    label               VARCHAR(80) NOT NULL CHECK (length(btrim(label)) >= 2),
    target_amount_minor BIGINT CHECK (target_amount_minor > 0 AND target_amount_minor <= 1000000000000),
    target_date         DATE,
    shared_with_group   BOOLEAN NOT NULL DEFAULT FALSE,
    archived_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- L'objectif appartient au titulaire de l'adhésion, et à personne d'autre
CREATE OR REPLACE FUNCTION savings_goals_check_owner() RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.id = NEW.membership_id AND m.user_id = NEW.user_id) THEN
        RAISE EXCEPTION 'savings_goals : l''objectif appartient au titulaire de l''adhésion';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_savings_goals_owner BEFORE INSERT OR UPDATE ON savings_goals
    FOR EACH ROW EXECUTE FUNCTION savings_goals_check_owner();

CREATE TRIGGER trg_audit_savings_goals AFTER INSERT OR UPDATE ON savings_goals
    FOR EACH ROW EXECUTE FUNCTION audit_business_change();
CREATE TRIGGER trg_no_delete_savings_goals BEFORE DELETE ON savings_goals
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();

GRANT SELECT, INSERT, UPDATE ON savings_goals TO mchango_app;
