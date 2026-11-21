-- ============================================================
-- Catégorie « Travailleurs » : calendrier calé sur la paie (spec/categories.md §3.5).
-- Le président fixe un jour de paie (1 à 31 ; 31 = dernier jour du mois). Chaque échéance tombe ce
-- jour-là ; si c'est un dimanche ou un jour férié, elle est avancée (before) ou reportée (after),
-- selon la règle choisie à la création. Seulement pour une tontine mensuelle de travailleurs.
-- ============================================================

CREATE TYPE payday_shift AS ENUM ('before', 'after');

ALTER TABLE groups
    ADD COLUMN payday       SMALLINT CHECK (payday BETWEEN 1 AND 31),
    ADD COLUMN payday_shift payday_shift,
    ADD CONSTRAINT groups_payday_rules CHECK (
        (payday IS NULL AND payday_shift IS NULL)
        OR (payday IS NOT NULL AND payday_shift IS NOT NULL
            AND frequency = 'monthly' AND category = 'workers')
    );

-- Jours fériés à date fixe en RDC. Liste à faire valider (ordonnances en vigueur) avant le pilote ;
-- elle se corrige ici, sans toucher au code.
CREATE TABLE public_holidays (
    month SMALLINT NOT NULL CHECK (month BETWEEN 1 AND 12),
    day   SMALLINT NOT NULL CHECK (day BETWEEN 1 AND 31),
    label TEXT NOT NULL,
    PRIMARY KEY (month, day)
);

INSERT INTO public_holidays (month, day, label) VALUES
    (1, 1, 'Nouvel an'),
    (1, 4, 'Martyrs de l''indépendance'),
    (1, 16, 'Héros national Laurent-Désiré Kabila'),
    (1, 17, 'Héros national Patrice-Emery Lumumba'),
    (4, 6, 'Simon Kimbangu et conscience africaine'),
    (5, 1, 'Fête du travail'),
    (5, 17, 'Révolution et libération'),
    (6, 30, 'Indépendance'),
    (8, 1, 'Fête des parents'),
    (8, 2, 'Génocide congolais'),
    (12, 25, 'Noël');

CREATE OR REPLACE FUNCTION is_non_working_day(p_day DATE) RETURNS BOOLEAN AS $$
    SELECT extract(isodow FROM p_day) = 7
        OR EXISTS (SELECT 1 FROM public_holidays h
                   WHERE h.month = extract(month FROM p_day) AND h.day = extract(day FROM p_day));
$$ LANGUAGE sql STABLE;

-- Jour de paie effectif du mois de [p_month] : le jour voulu (ou le dernier jour du mois s'il est
-- plus court), puis décalé jusqu'à un jour ouvré.
CREATE OR REPLACE FUNCTION payday_in_month(p_month DATE, p_payday INT, p_shift payday_shift) RETURNS DATE AS $$
DECLARE
    v_first DATE := date_trunc('month', p_month)::date;
    v_last  INT  := extract(day FROM (v_first + interval '1 month' - interval '1 day'))::int;
    v_day   DATE := v_first + (least(p_payday, v_last) - 1);
    v_step  INT  := CASE p_shift WHEN 'before' THEN -1 ELSE 1 END;
BEGIN
    -- Au plus quelques jours fériés consécutifs (ex. 1er et 2 août + dimanche)
    FOR i IN 1..10 LOOP
        EXIT WHEN NOT is_non_working_day(v_day);
        v_day := v_day + v_step;
    END LOOP;
    RETURN v_day;
END;
$$ LANGUAGE plpgsql STABLE;

-- Échéance du tour n° (p_offset + 1) : le premier jour de paie à partir de la date de début, puis
-- un mois de plus par tour.
CREATE OR REPLACE FUNCTION payday_due_date(p_start DATE, p_offset INT, p_payday INT, p_shift payday_shift)
RETURNS DATE AS $$
DECLARE
    v_month DATE := date_trunc('month', p_start)::date;
BEGIN
    IF payday_in_month(v_month, p_payday, p_shift) < p_start THEN
        v_month := (v_month + interval '1 month')::date;
    END IF;
    RETURN payday_in_month((v_month + make_interval(months => p_offset))::date, p_payday, p_shift);
END;
$$ LANGUAGE plpgsql STABLE;

GRANT SELECT ON public_holidays TO mchango_app;
GRANT EXECUTE ON FUNCTION is_non_working_day(DATE), payday_in_month(DATE, INT, payday_shift),
    payday_due_date(DATE, INT, INT, payday_shift) TO mchango_app;
