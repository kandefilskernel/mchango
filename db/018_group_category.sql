-- ============================================================
-- Catégorie de tontine : communautaire, organisation, travailleurs, religion (spec/categories.md).
-- Étape 1 (socle) : la catégorie est une étiquette de départ. Elle ne change encore aucune règle ;
-- les fonctions propres à chaque catégorie arrivent ensuite.
-- Elle ne se modifie jamais après la création, comme la devise : ce serait un autre groupe.
-- (Elle n'entre donc pas dans l'empreinte du règlement signé : elle ne peut pas changer.)
-- À la création, elle est journalisée avec le reste de la ligne (trigger audit_business_change).
-- ============================================================

CREATE TYPE group_category AS ENUM ('community', 'organization', 'workers', 'religion');

-- Les groupes existants deviennent « communautaire » : c'est la tontine telle qu'elle existe déjà
ALTER TABLE groups ADD COLUMN category group_category NOT NULL DEFAULT 'community';

CREATE INDEX idx_groups_category ON groups (category);

CREATE OR REPLACE FUNCTION forbid_category_change() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'groups.category : la catégorie ne se modifie pas après la création';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_groups_category_immutable
    BEFORE UPDATE OF category ON groups
    FOR EACH ROW WHEN (OLD.category IS DISTINCT FROM NEW.category)
    EXECUTE FUNCTION forbid_category_change();
