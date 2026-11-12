-- ============================================================
-- Tests du schéma : chaque bloc doit afficher OK, sinon le script s'arrête.
-- Lancement : voir db/README.md
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

-- ---------- Données de base ----------
SET mchango.actor_type = 'system';

INSERT INTO users (id, phone, full_name, pin_hash) VALUES
    ('00000000-0000-0000-0000-0000000000a1', '+243970000001', 'Mama Furaha', 'x'),
    ('00000000-0000-0000-0000-0000000000a2', '+243970000002', 'Papa Jean',   'x'),
    ('00000000-0000-0000-0000-0000000000a3', '+243970000003', 'Mama Neema',  'x');

INSERT INTO groups (id, name, contribution_amount_minor, frequency, start_date, created_by) VALUES
    ('00000000-0000-0000-0000-0000000000b1', 'Likelemba Kenya', 20000, 'weekly', '2026-11-02',
     '00000000-0000-0000-0000-0000000000a1'),
    ('00000000-0000-0000-0000-0000000000b2', 'Muziki Ruashi',   10000, 'weekly', '2026-11-02',
     '00000000-0000-0000-0000-0000000000a2');

INSERT INTO memberships (id, group_id, user_id, role, turn_order, status) VALUES
    ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b1',
     '00000000-0000-0000-0000-0000000000a1', 'president', 1, 'active'),
    ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000b1',
     '00000000-0000-0000-0000-0000000000a2', 'member', 2, 'active'),
    ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000b1',
     '00000000-0000-0000-0000-0000000000a3', 'member', 3, 'active'),
    ('00000000-0000-0000-0000-0000000000c4', '00000000-0000-0000-0000-0000000000b2',
     '00000000-0000-0000-0000-0000000000a1', 'member', 1, 'active'),
    ('00000000-0000-0000-0000-0000000000c5', '00000000-0000-0000-0000-0000000000b2',
     '00000000-0000-0000-0000-0000000000a2', 'president', 2, 'active');

-- Tour 1 du groupe b1 : bénéficiaire Mama Furaha (c1)
INSERT INTO cycles (id, group_id, cycle_number, due_date, beneficiary_membership_id) VALUES
    ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1', 1,
     '2026-11-02', '00000000-0000-0000-0000-0000000000c1'),
    ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000b2', 1,
     '2026-11-02', '00000000-0000-0000-0000-0000000000c5');

SET ROLE mchango_app;
SET mchango.actor_type = 'user';
SET mchango.actor_id   = '00000000-0000-0000-0000-0000000000a2';

-- ---------- Cotisation déclarée puis confirmée ----------
INSERT INTO contributions (id, cycle_id, group_id, payer_membership_id, receiver_membership_id,
                           amount_minor, method, tx_reference, offline_id) VALUES
    ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000d1',
     '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c2',
     '00000000-0000-0000-0000-0000000000c1', 20000, 'mpesa', 'RK45TX9QPL', gen_random_uuid());

SELECT pg_temp.expect_error($$
    INSERT INTO confirmations (contribution_id, confirmed_by, decision)
    VALUES ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c3', 'confirm')
$$, 'confirmation par un membre qui n''est pas le receveur');

SET mchango.actor_id = '00000000-0000-0000-0000-0000000000a1';
INSERT INTO confirmations (contribution_id, confirmed_by, decision)
VALUES ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'confirm');
UPDATE contributions SET status = 'confirmed' WHERE id = '00000000-0000-0000-0000-0000000000e1';
SELECT pg_temp.expect(TRUE, 'confirmation par le receveur acceptée');

-- ---------- Règles anti-fraude ----------
SELECT pg_temp.expect_error($$
    INSERT INTO contributions (cycle_id, group_id, payer_membership_id, receiver_membership_id,
                               amount_minor, method, tx_reference, offline_id)
    VALUES ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000b2',
            '00000000-0000-0000-0000-0000000000c4', '00000000-0000-0000-0000-0000000000c5',
            10000, 'mpesa', 'RK45TX9QPL', gen_random_uuid())
$$, 'même ID de transaction réutilisé dans un autre groupe');

SELECT pg_temp.expect_error($$
    INSERT INTO contributions (cycle_id, group_id, payer_membership_id, receiver_membership_id,
                               amount_minor, method, tx_reference, offline_id)
    VALUES ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1',
            '00000000-0000-0000-0000-0000000000c4', '00000000-0000-0000-0000-0000000000c1',
            20000, 'orange', 'OM-AUTRE-GROUPE', gen_random_uuid())
$$, 'payeur membre d''un autre groupe');

SELECT pg_temp.expect_error($$
    INSERT INTO contributions (cycle_id, group_id, payer_membership_id, receiver_membership_id,
                               amount_minor, method, tx_reference, offline_id)
    VALUES ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1',
            '00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000c1',
            20000, 'airtel', NULL, gen_random_uuid())
$$, 'mobile money sans ID de transaction');

SELECT pg_temp.expect_error($$
    INSERT INTO contributions (cycle_id, group_id, payer_membership_id, receiver_membership_id,
                               amount_minor, method, tx_reference, offline_id)
    VALUES ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1',
            '00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000c1',
            20000, 'airtel', 'AM-DEUXIEME', gen_random_uuid())
$$, 'deuxième cotisation active du même membre pour le même tour');

-- ---------- Journal en ajout seul ----------
SELECT pg_temp.expect_error($$ UPDATE audit_log SET payload = '{}' $$, 'UPDATE du journal (rôle app)');
SELECT pg_temp.expect_error($$ DELETE FROM audit_log $$,               'DELETE du journal (rôle app)');
SELECT pg_temp.expect_error($$ TRUNCATE audit_log $$,                  'TRUNCATE du journal (rôle app)');
SELECT pg_temp.expect_error($$ UPDATE audit_chain_heads SET last_seq = 0 $$, 'accès direct aux têtes de chaîne');
SELECT pg_temp.expect_error($$ DELETE FROM contributions $$,           'DELETE d''une cotisation');

RESET mchango.actor_id;
SET mchango.actor_type = '';
SELECT pg_temp.expect_error($$
    UPDATE groups SET status = 'active' WHERE id = '00000000-0000-0000-0000-0000000000b1'
$$, 'écriture métier sans auteur déclaré');

RESET ROLE;

-- Même le propriétaire bute sur les triggers (il devrait les désactiver explicitement)
SELECT pg_temp.expect_error($$ UPDATE audit_log SET payload = '{}' $$, 'UPDATE du journal (propriétaire)');
SELECT pg_temp.expect_error($$ TRUNCATE audit_log $$,                  'TRUNCATE du journal (propriétaire)');

-- ---------- Chaînage ----------
SELECT pg_temp.expect(
    (SELECT count(*) FROM audit_log WHERE chain_id = 'group:00000000-0000-0000-0000-0000000000b1') = 8,
    'groupe b1 : 8 événements (groupe, 3 adhésions, tour, déclaration, confirmation, statut)');
SELECT pg_temp.expect(audit_verify_chain('group:00000000-0000-0000-0000-0000000000b1') IS NULL,
                      'chaîne du groupe b1 intacte');
SELECT pg_temp.expect(audit_verify_chain('group:00000000-0000-0000-0000-0000000000b2') IS NULL,
                      'chaîne du groupe b2 intacte');
SELECT pg_temp.expect(
    (SELECT seq FROM audit_log WHERE chain_id = 'group:00000000-0000-0000-0000-0000000000b2'
     ORDER BY seq LIMIT 1) = 1,
    'chaque groupe a sa propre chaîne, qui commence à 1');

-- ---------- Détection d'une falsification ----------
-- Simule un administrateur malveillant qui contourne les triggers.
BEGIN;
ALTER TABLE audit_log DISABLE TRIGGER trg_audit_log_no_update;
UPDATE audit_log SET payload = replace(payload, '20000', '2000')
WHERE chain_id = 'group:00000000-0000-0000-0000-0000000000b1' AND action = 'contributions.insert';
ALTER TABLE audit_log ENABLE TRIGGER trg_audit_log_no_update;
SELECT pg_temp.expect(audit_verify_chain('group:00000000-0000-0000-0000-0000000000b1') IS NOT NULL,
                      'falsification d''un montant détectée par audit_verify_chain');
ROLLBACK;
