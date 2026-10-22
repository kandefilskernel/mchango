-- ============================================================
-- Tests de db/006_turns_cycles.sql.
-- À lancer APRÈS 001_checks.sql et 002_cash_witness.sql, sur la même base.
--   groupe b1 (mode direct) : tour d1, bénéficiaire c1 ; c2, c3 membres.
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

SELECT pg_temp.expect_error($$
    INSERT INTO contributions (cycle_id, group_id, payer_membership_id, receiver_membership_id,
                               amount_minor, method, tx_reference, offline_id)
    VALUES ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1',
            '00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000c2',
            20000, 'mpesa', 'MP-PAS-AU-BENEFICIAIRE', gen_random_uuid())
$$, 'mode direct : paiement à quelqu''un d''autre que le bénéficiaire');

SELECT pg_temp.expect_error($$
    INSERT INTO cycles (group_id, cycle_number, due_date, beneficiary_membership_id)
    VALUES ('00000000-0000-0000-0000-0000000000b1', 2, '2026-11-09',
            '00000000-0000-0000-0000-0000000000c1')
$$, 'même bénéficiaire pour deux tours');

-- Tant que le groupe est en brouillon, l'ordre peut changer
UPDATE memberships SET turn_order = NULL WHERE group_id = '00000000-0000-0000-0000-0000000000b1';
UPDATE memberships SET turn_order = 3 WHERE id = '00000000-0000-0000-0000-0000000000c1';
SELECT pg_temp.expect(TRUE, 'ordre modifiable en brouillon');

UPDATE groups SET status = 'active' WHERE id = '00000000-0000-0000-0000-0000000000b1';
SELECT pg_temp.expect_error($$
    UPDATE memberships SET turn_order = 1 WHERE id = '00000000-0000-0000-0000-0000000000c1'
$$, 'ordre modifié après le démarrage');

SELECT pg_temp.expect_error($$
    UPDATE groups SET turn_order_mode = 'draw' WHERE id = '00000000-0000-0000-0000-0000000000b1'
$$, 'tirage déclaré sans graine publiée');

RESET ROLE;
SELECT pg_temp.expect(audit_verify_chain('group:00000000-0000-0000-0000-0000000000b1') IS NULL,
                      'chaîne du groupe b1 toujours intacte');
