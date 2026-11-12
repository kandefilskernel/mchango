-- ============================================================
-- Tests de db/018_group_category.sql.
-- À lancer APRÈS 003_turns_cycles.sql, sur la même base (groupe b1).
-- ============================================================
\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned

CREATE FUNCTION pg_temp.expect_error(p_sql TEXT, p_label TEXT) RETURNS VOID AS $$
DECLARE
    v_refused BOOLEAN := FALSE;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_refused := TRUE;
        RAISE NOTICE 'OK  refusé — % (%)', p_label, SQLERRM;
    END;
    IF NOT v_refused THEN
        RAISE EXCEPTION 'ÉCHEC — accepté à tort : %', p_label;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION pg_temp.expect(p_cond BOOLEAN, p_label TEXT) RETURNS VOID AS $$
BEGIN
    IF NOT p_cond THEN RAISE EXCEPTION 'ÉCHEC — %', p_label; END IF;
    RAISE NOTICE 'OK  %', p_label;
END;
$$ LANGUAGE plpgsql;

SET ROLE mchango_app;
SET mchango.actor_type = 'system';

SELECT pg_temp.expect(
    (SELECT category FROM groups WHERE id = '00000000-0000-0000-0000-0000000000b1') = 'community',
    'un groupe créé sans catégorie est « communautaire »');

SELECT pg_temp.expect_error($$
    UPDATE groups SET category = 'religion' WHERE id = '00000000-0000-0000-0000-0000000000b1'
$$, 'catégorie modifiée après la création');

-- Réécrire la même valeur n'est pas un changement
UPDATE groups SET category = 'community' WHERE id = '00000000-0000-0000-0000-0000000000b1';
SELECT pg_temp.expect(TRUE, 'même catégorie réécrite : accepté');

SELECT pg_temp.expect_error($$
    UPDATE groups SET category = 'banque' WHERE id = '00000000-0000-0000-0000-0000000000b1'
$$, 'catégorie inconnue');

RESET ROLE;
SELECT pg_temp.expect(audit_verify_chain('group:00000000-0000-0000-0000-0000000000b1') IS NULL,
                      'chaîne du groupe b1 toujours intacte');
