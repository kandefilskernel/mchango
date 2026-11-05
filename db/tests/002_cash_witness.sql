-- ============================================================
-- Tests du cash avec témoin (db/003_cash_witness.sql).
-- À lancer APRÈS 001_checks.sql, sur la même base : réutilise ses données.
--   groupe b1 : c1 bénéficiaire du tour d1, c2 et c3 membres.
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
SET mchango.actor_type = 'user';
SET mchango.actor_id   = '00000000-0000-0000-0000-0000000000a3';

-- ---------- Déclaration ----------
SELECT pg_temp.expect_error($$
    INSERT INTO contributions (cycle_id, group_id, payer_membership_id, receiver_membership_id,
                               amount_minor, method, offline_id)
    VALUES ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1',
            '00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000c1',
            20000, 'cash', gen_random_uuid())
$$, 'cash sans témoin désigné');

SELECT pg_temp.expect_error($$
    INSERT INTO contributions (cycle_id, group_id, payer_membership_id, receiver_membership_id,
                               witness_membership_id, amount_minor, method, offline_id)
    VALUES ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1',
            '00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000c1',
            '00000000-0000-0000-0000-0000000000c3', 20000, 'cash', gen_random_uuid())
$$, 'le payeur se désigne lui-même témoin');

SELECT pg_temp.expect_error($$
    INSERT INTO contributions (cycle_id, group_id, payer_membership_id, receiver_membership_id,
                               witness_membership_id, amount_minor, method, offline_id)
    VALUES ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1',
            '00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000c1',
            '00000000-0000-0000-0000-0000000000c4', 20000, 'cash', gen_random_uuid())
$$, 'témoin membre d''un autre groupe');

SELECT pg_temp.expect_error($$
    INSERT INTO contributions (cycle_id, group_id, payer_membership_id, receiver_membership_id,
                               witness_membership_id, amount_minor, method, status, offline_id)
    VALUES ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1',
            '00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000c1',
            '00000000-0000-0000-0000-0000000000c2', 20000, 'cash', 'confirmed', gen_random_uuid())
$$, 'cotisation créée directement « confirmed »');

-- Mama Neema (c3) paie en espèces à Mama Furaha (c1), devant Papa Jean (c2)
INSERT INTO contributions (id, cycle_id, group_id, payer_membership_id, receiver_membership_id,
                           witness_membership_id, amount_minor, method, offline_id)
VALUES ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000d1',
        '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c3',
        '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000c2',
        20000, 'cash', gen_random_uuid());
SELECT pg_temp.expect(TRUE, 'cash déclaré avec un témoin tiers');

-- ---------- Confirmations ----------
SELECT pg_temp.expect_error($$
    UPDATE contributions SET status = 'confirmed' WHERE id = '00000000-0000-0000-0000-0000000000f1'
$$, 'passage à « confirmed » sans aucune confirmation');

SELECT pg_temp.expect_error($$
    INSERT INTO confirmations (contribution_id, confirmed_by, decision)
    VALUES ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000c3', 'witness')
$$, 'le payeur témoigne pour lui-même');

SELECT pg_temp.expect_error($$
    INSERT INTO confirmations (contribution_id, confirmed_by, decision)
    VALUES ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c3', 'witness')
$$, 'témoignage sur une cotisation mobile money');

SELECT pg_temp.expect_error($$
    INSERT INTO confirmations (contribution_id, confirmed_by, decision)
    VALUES ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000c4', 'dispute')
$$, 'contestation par quelqu''un d''un autre groupe');

INSERT INTO confirmations (contribution_id, confirmed_by, decision)
VALUES ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000c1', 'confirm');

SELECT pg_temp.expect_error($$
    UPDATE contributions SET status = 'confirmed' WHERE id = '00000000-0000-0000-0000-0000000000f1'
$$, 'cash confirmé par le receveur mais pas encore par le témoin');

SELECT pg_temp.expect_error($$
    INSERT INTO confirmations (contribution_id, confirmed_by, decision)
    VALUES ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000c1', 'confirm')
$$, 'même confirmation envoyée deux fois');

INSERT INTO confirmations (contribution_id, confirmed_by, decision)
VALUES ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000c2', 'witness');
UPDATE contributions SET status = 'confirmed' WHERE id = '00000000-0000-0000-0000-0000000000f1';
SELECT pg_temp.expect(
    (SELECT status FROM contributions WHERE id = '00000000-0000-0000-0000-0000000000f1') = 'confirmed',
    'cash confirmé après receveur + témoin');

RESET ROLE;
SELECT pg_temp.expect(audit_verify_chain('group:00000000-0000-0000-0000-0000000000b1') IS NULL,
                      'chaîne du groupe b1 toujours intacte');
