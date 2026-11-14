-- ============================================================
-- Tests des achats groupés : chaque bloc doit afficher OK, sinon le script s'arrête.
-- Lancement : voir db/README.md. Peut tourner seul ou après 004_category.sql.
-- Dure quelques secondes : le script attend la date de fin des offres de test.
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
    IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'ÉCHEC — %', p_label; END IF;
    RAISE NOTICE 'OK  %', p_label;
END;
$$ LANGUAGE plpgsql;

-- Identifiants : 1…01-05 utilisateurs, 21-22 boutiques, 31-32 employés, 41-42 groupes,
-- 61-62 offres, 71-73 partages, 81-85 commandes, 91 paiement.

-- ---------- Données de base (équipe) ----------
SET mchango.actor_type = 'system';

INSERT INTO users (id, phone, full_name, pin_hash) VALUES
    ('10000000-0000-0000-0000-000000000001', '+243810000001', 'Papa Nyota',   'x'),
    ('10000000-0000-0000-0000-000000000002', '+243810000002', 'Mama Kasongo', 'x'),
    ('10000000-0000-0000-0000-000000000003', '+243810000003', 'Grâce M.',     'x'),
    ('10000000-0000-0000-0000-000000000004', '+243810000004', 'Aline Nzambe', 'x'),
    ('10000000-0000-0000-0000-000000000005', '+243810000005', 'Joël',         'x');

INSERT INTO pickup_zones (id, city, commune) VALUES
    ('10000000-0000-0000-0000-000000000011', 'Kinshasa', 'Matete');

INSERT INTO merchants (id, name, zone_id, address, phone, status) VALUES
    ('10000000-0000-0000-0000-000000000021', 'Boutique Nyota', '10000000-0000-0000-0000-000000000011',
     'Av. Kinzazi 12', '+243810000001', 'active'),
    ('10000000-0000-0000-0000-000000000022', 'Chez Kasongo',   '10000000-0000-0000-0000-000000000011',
     'Av. Lumière 3',  '+243810000002', 'active');

INSERT INTO merchant_members (id, merchant_id, user_id, role) VALUES
    ('10000000-0000-0000-0000-000000000031', '10000000-0000-0000-0000-000000000021',
     '10000000-0000-0000-0000-000000000001', 'owner'),
    ('10000000-0000-0000-0000-000000000032', '10000000-0000-0000-0000-000000000022',
     '10000000-0000-0000-0000-000000000002', 'owner');

-- Deux groupes de tontine. Aline est membre des deux.
INSERT INTO groups (id, name, contribution_amount_minor, frequency, start_date, created_by) VALUES
    ('10000000-0000-0000-0000-000000000041', 'Les Solidaires', 50000, 'monthly', '2026-12-01',
     '10000000-0000-0000-0000-000000000003'),
    ('10000000-0000-0000-0000-000000000042', 'Voisins de Matete', 20000, 'weekly', '2026-12-01',
     '10000000-0000-0000-0000-000000000004');

INSERT INTO memberships (group_id, user_id, role, status) VALUES
    ('10000000-0000-0000-0000-000000000041', '10000000-0000-0000-0000-000000000003', 'president', 'active'),
    ('10000000-0000-0000-0000-000000000041', '10000000-0000-0000-0000-000000000004', 'member',    'active'),
    ('10000000-0000-0000-0000-000000000042', '10000000-0000-0000-0000-000000000004', 'president', 'active'),
    ('10000000-0000-0000-0000-000000000042', '10000000-0000-0000-0000-000000000005', 'member',    'active');

SET ROLE mchango_app;
SET mchango.actor_type = 'user';

-- ---------- Le commerçant crée ses offres ----------
SET mchango.actor_id = '10000000-0000-0000-0000-000000000001';

-- Offre 61 : riz, prix habituel 60 000 ; 5 sacs → 57 000 ; 8 sacs → 54 000
-- Offre 62 : huile, seuil de 10 bidons (ne sera pas atteint)
INSERT INTO offers (id, merchant_id, created_by_member_id, title, unit_label, regular_price_minor,
                    ends_at, pickup_window_hours) VALUES
    ('10000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000021',
     '10000000-0000-0000-0000-000000000031', 'Riz', 'sac de 25 kg', 60000,
     clock_timestamp() + interval '6 seconds', 72),
    ('10000000-0000-0000-0000-000000000062', '10000000-0000-0000-0000-000000000021',
     '10000000-0000-0000-0000-000000000031', 'Huile', 'bidon de 5 L', 20000,
     clock_timestamp() + interval '6 seconds', 48);

SELECT pg_temp.expect_error($$
    INSERT INTO offers (merchant_id, created_by_member_id, title, unit_label, regular_price_minor,
                        ends_at, pickup_window_hours)
    VALUES ('10000000-0000-0000-0000-000000000021', '10000000-0000-0000-0000-000000000032',
            'Sucre', 'sac', 1000, now() + interval '1 day', 72)
$$, 'offre créée par l''employé d''une autre boutique');

SELECT pg_temp.expect_error($$
    UPDATE offers SET status = 'open' WHERE id = '10000000-0000-0000-0000-000000000061'
$$, 'publication d''une offre sans palier');

SELECT pg_temp.expect_error($$
    INSERT INTO offer_tiers VALUES ('10000000-0000-0000-0000-000000000061', 5, 60000)
$$, 'palier sans réduction par rapport au prix habituel');

INSERT INTO offer_tiers (offer_id, min_quantity, unit_price_minor) VALUES
    ('10000000-0000-0000-0000-000000000061', 5, 57000),
    ('10000000-0000-0000-0000-000000000061', 8, 54000),
    ('10000000-0000-0000-0000-000000000062', 10, 18500);

UPDATE offers SET status = 'open'
WHERE id IN ('10000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000062');

SELECT pg_temp.expect_error($$
    UPDATE offer_tiers SET unit_price_minor = 59000
    WHERE offer_id = '10000000-0000-0000-0000-000000000061' AND min_quantity = 8
$$, 'palier modifié après publication');
SELECT pg_temp.expect_error($$
    UPDATE offers SET regular_price_minor = 90000 WHERE id = '10000000-0000-0000-0000-000000000061'
$$, 'prix habituel modifié après publication');
SELECT pg_temp.expect_error($$
    UPDATE offers SET ends_at = ends_at + interval '1 day' WHERE id = '10000000-0000-0000-0000-000000000061'
$$, 'date de fin repoussée après publication');

-- ---------- Inviter n'est pas commander ----------
SET mchango.actor_id = '10000000-0000-0000-0000-000000000003';   -- Grâce
INSERT INTO shares (id, offer_id, shared_by_user_id, channel, group_id) VALUES
    ('10000000-0000-0000-0000-000000000071', '10000000-0000-0000-0000-000000000061',
     '10000000-0000-0000-0000-000000000003', 'group', '10000000-0000-0000-0000-000000000041');

SET mchango.actor_id = '10000000-0000-0000-0000-000000000004';   -- Aline, invitée par Grâce, repartage
INSERT INTO shares (id, offer_id, parent_share_id, shared_by_user_id, channel, group_id, token_hash) VALUES
    ('10000000-0000-0000-0000-000000000072', '10000000-0000-0000-0000-000000000061',
     '10000000-0000-0000-0000-000000000071', '10000000-0000-0000-0000-000000000004',
     'group', '10000000-0000-0000-0000-000000000042', NULL),
    ('10000000-0000-0000-0000-000000000073', '10000000-0000-0000-0000-000000000061',
     '10000000-0000-0000-0000-000000000071', '10000000-0000-0000-0000-000000000004',
     'whatsapp', NULL, repeat('a', 64));

SELECT pg_temp.expect(
    (SELECT confirmed_units = 0 AND missing_units = 5 AND reached_unit_price_minor IS NULL
     FROM offer_progress WHERE offer_id = '10000000-0000-0000-0000-000000000061'),
    'trois partages, compteur toujours à 0 : une invitation n''est pas une commande');

SET mchango.actor_id = '10000000-0000-0000-0000-000000000005';   -- Joël n'est pas des Solidaires
SELECT pg_temp.expect_error($$
    INSERT INTO shares (offer_id, shared_by_user_id, channel, group_id)
    VALUES ('10000000-0000-0000-0000-000000000062', '10000000-0000-0000-0000-000000000005',
            'group', '10000000-0000-0000-0000-000000000041')
$$, 'offre proposée à un groupe dont on n''est pas membre');
SELECT pg_temp.expect_error($$
    INSERT INTO shares (offer_id, parent_share_id, shared_by_user_id, channel, token_hash)
    VALUES ('10000000-0000-0000-0000-000000000062', '10000000-0000-0000-0000-000000000071',
            '10000000-0000-0000-0000-000000000005', 'whatsapp', repeat('b', 64))
$$, 'origine d''invitation qui pointe vers une autre offre');

-- ---------- Chacun confirme lui-même sa quantité ----------
SET mchango.actor_id = '10000000-0000-0000-0000-000000000003';   -- Grâce
SELECT pg_temp.expect_error($$
    INSERT INTO orders (offer_id, merchant_id, buyer_user_id, quantity, pickup_name, offline_id)
    VALUES ('10000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000021',
            '10000000-0000-0000-0000-000000000004', 2, 'Aline Nzambe', gen_random_uuid())
$$, 'la présidente réserve au nom d''une autre membre');

INSERT INTO orders (id, offer_id, merchant_id, buyer_user_id, quantity, pickup_name, offline_id) VALUES
    ('10000000-0000-0000-0000-000000000081', '10000000-0000-0000-0000-000000000061',
     '10000000-0000-0000-0000-000000000021', '10000000-0000-0000-0000-000000000003',
     3, 'Grâce M.', gen_random_uuid());

SELECT pg_temp.expect_error($$
    INSERT INTO orders (offer_id, merchant_id, buyer_user_id, quantity, pickup_name, offline_id)
    VALUES ('10000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000021',
            '10000000-0000-0000-0000-000000000003', 1, 'Grâce M.', gen_random_uuid())
$$, 'deuxième commande active du même acheteur sur la même offre');

-- Aline a reçu l'offre dans ses deux groupes : elle commande une seule fois
SET mchango.actor_id = '10000000-0000-0000-0000-000000000004';
SELECT pg_temp.expect_error($$
    INSERT INTO orders (offer_id, merchant_id, buyer_user_id, quantity, pickup_name, offline_id)
    VALUES ('10000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000022',
            '10000000-0000-0000-0000-000000000004', 1, 'Aline Nzambe', gen_random_uuid())
$$, 'commande rattachée à une boutique qui ne vend pas l''offre');
INSERT INTO orders (id, offer_id, merchant_id, buyer_user_id, quantity, pickup_name, via_share_id, offline_id) VALUES
    ('10000000-0000-0000-0000-000000000082', '10000000-0000-0000-0000-000000000061',
     '10000000-0000-0000-0000-000000000021', '10000000-0000-0000-0000-000000000004',
     2, 'Aline Nzambe', '10000000-0000-0000-0000-000000000071', gen_random_uuid());

SELECT pg_temp.expect(
    (SELECT confirmed_units = 5 AND missing_units = 0 AND reached_unit_price_minor = 57000
     FROM offer_progress WHERE offer_id = '10000000-0000-0000-0000-000000000061'),
    'compteur = 5 sacs (3 + 2), premier palier atteint : 57 000');
SELECT pg_temp.expect(
    (SELECT confirmed_members FROM group_offer_proposals
     WHERE group_id = '10000000-0000-0000-0000-000000000041') = 2
    AND (SELECT confirmed_members FROM group_offer_proposals
         WHERE group_id = '10000000-0000-0000-0000-000000000042') = 1,
    'Aline visible dans ses deux groupes (2 et 1 membres confirmés), comptée une seule fois dans l''offre');

-- Joël réserve, annule, puis réserve de nouveau ; il réserve aussi un bidon d'huile
SET mchango.actor_id = '10000000-0000-0000-0000-000000000005';
INSERT INTO orders (id, offer_id, merchant_id, buyer_user_id, quantity, pickup_name, offline_id) VALUES
    ('10000000-0000-0000-0000-000000000083', '10000000-0000-0000-0000-000000000061',
     '10000000-0000-0000-0000-000000000021', '10000000-0000-0000-0000-000000000005',
     1, 'Joël', gen_random_uuid());
UPDATE orders SET status = 'cancelled' WHERE id = '10000000-0000-0000-0000-000000000083';
SELECT pg_temp.expect(
    (SELECT confirmed_units FROM offer_progress
     WHERE offer_id = '10000000-0000-0000-0000-000000000061') = 5,
    'une commande annulée ne compte plus');
INSERT INTO orders (id, offer_id, merchant_id, buyer_user_id, quantity, pickup_name, offline_id) VALUES
    ('10000000-0000-0000-0000-000000000084', '10000000-0000-0000-0000-000000000061',
     '10000000-0000-0000-0000-000000000021', '10000000-0000-0000-0000-000000000005',
     3, 'Joël', gen_random_uuid()),
    ('10000000-0000-0000-0000-000000000085', '10000000-0000-0000-0000-000000000062',
     '10000000-0000-0000-0000-000000000021', '10000000-0000-0000-0000-000000000005',
     1, 'Joël', gen_random_uuid());
SELECT pg_temp.expect(
    (SELECT confirmed_units = 8 AND reached_unit_price_minor = 54000
     FROM offer_progress WHERE offer_id = '10000000-0000-0000-0000-000000000061'),
    'nouvelle réservation après annulation : 8 sacs, second palier atteint : 54 000');

SELECT pg_temp.expect_error($$
    UPDATE orders SET status = 'ready', pickup_code = 'MC-0001'
    WHERE id = '10000000-0000-0000-0000-000000000084'
$$, 'commande prête avant la clôture de l''offre');

-- ---------- Clôture ----------
SET mchango.actor_id = '10000000-0000-0000-0000-000000000001';   -- le commerçant
SELECT pg_temp.expect_error($$
    UPDATE offers SET status = 'closed' WHERE id = '10000000-0000-0000-0000-000000000061'
$$, 'clôture avant la date de fin');

SELECT pg_sleep(greatest(0, extract(epoch FROM max(ends_at) - clock_timestamp()) + 0.2))
FROM offers WHERE id IN ('10000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000062');

SELECT pg_temp.expect_error($$
    INSERT INTO orders (offer_id, merchant_id, buyer_user_id, quantity, pickup_name, offline_id)
    VALUES ('10000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000021',
            '10000000-0000-0000-0000-000000000001', 1, 'Papa Nyota', gen_random_uuid())
$$, 'réservation après la date de fin');

SELECT pg_temp.expect_error($$
    UPDATE offers SET status = 'closed' WHERE id = '10000000-0000-0000-0000-000000000062'
$$, 'clôture d''une offre sous son seuil minimum');

-- Le commerçant tente d'imposer un autre prix : la base calcule le palier elle-même
UPDATE offers SET status = 'closed', final_unit_price_minor = 59999
WHERE id = '10000000-0000-0000-0000-000000000061';
SELECT pg_temp.expect(
    (SELECT final_unit_price_minor FROM offers WHERE id = '10000000-0000-0000-0000-000000000061') = 54000,
    'prix final = palier atteint (54 000), le prix fourni par l''appelant est ignoré');
UPDATE offers SET final_unit_price_minor = 59999 WHERE id = '10000000-0000-0000-0000-000000000061';
SELECT pg_temp.expect(
    (SELECT final_unit_price_minor FROM offers WHERE id = '10000000-0000-0000-0000-000000000061') = 54000,
    'prix final inchangé par une modification après la clôture');
SELECT pg_temp.expect_error($$
    UPDATE offers SET status = 'open' WHERE id = '10000000-0000-0000-0000-000000000061'
$$, 'réouverture d''une offre clôturée');

-- Offre sous le seuil : annulée, ses réservations aussi. Rien n'a été payé.
SET mchango.actor_type = 'system';
UPDATE offers SET status = 'cancelled' WHERE id = '10000000-0000-0000-0000-000000000062';
UPDATE orders SET status = 'cancelled' WHERE offer_id = '10000000-0000-0000-0000-000000000062';
SELECT pg_temp.expect(TRUE, 'offre sous le seuil annulée avec ses réservations');

-- Les commandes de l'offre clôturée reçoivent leur code de retrait
SELECT pg_temp.expect_error($$
    UPDATE orders SET status = 'ready' WHERE id = '10000000-0000-0000-0000-000000000081'
$$, 'commande prête sans code de retrait');
UPDATE orders SET status = 'ready', pickup_code = 'MC-4832' WHERE id = '10000000-0000-0000-0000-000000000081';
UPDATE orders SET status = 'ready', pickup_code = 'MC-4833' WHERE id = '10000000-0000-0000-0000-000000000082';
SELECT pg_temp.expect_error($$
    UPDATE orders SET status = 'ready', pickup_code = 'MC-4832' WHERE id = '10000000-0000-0000-0000-000000000084'
$$, 'même code de retrait pour deux commandes de la boutique');
UPDATE orders SET status = 'ready', pickup_code = 'MC-4834' WHERE id = '10000000-0000-0000-0000-000000000084';

SET mchango.actor_type = 'user';

-- ---------- Paiement : déclaré n'est pas vérifié ----------
SET mchango.actor_id = '10000000-0000-0000-0000-000000000003';   -- Grâce
SELECT pg_temp.expect_error($$
    UPDATE orders SET status = 'cancelled' WHERE id = '10000000-0000-0000-0000-000000000081'
$$, 'annulation d''une commande après la clôture');
SELECT pg_temp.expect_error($$
    INSERT INTO order_payments (order_id, merchant_id, amount_minor, method, declared_by_user_id)
    VALUES ('10000000-0000-0000-0000-000000000081', '10000000-0000-0000-0000-000000000021',
            150000, 'cash', '10000000-0000-0000-0000-000000000003')
$$, 'montant différent de quantité × prix final');
SELECT pg_temp.expect_error($$
    INSERT INTO order_payments (order_id, merchant_id, amount_minor, method, status, confirmed_by_member_id)
    VALUES ('10000000-0000-0000-0000-000000000081', '10000000-0000-0000-0000-000000000021',
            162000, 'cash', 'confirmed', '10000000-0000-0000-0000-000000000031')
$$, 'l''acheteuse confirme elle-même son paiement');

INSERT INTO order_payments (id, order_id, merchant_id, amount_minor, method, declared_by_user_id) VALUES
    ('10000000-0000-0000-0000-000000000091', '10000000-0000-0000-0000-000000000081',
     '10000000-0000-0000-0000-000000000021', 162000, 'cash', '10000000-0000-0000-0000-000000000003');
SELECT pg_temp.expect_error($$
    UPDATE orders SET status = 'paid' WHERE id = '10000000-0000-0000-0000-000000000081'
$$, 'commande « payée » sur simple déclaration de l''acheteuse');

SET mchango.actor_id = '10000000-0000-0000-0000-000000000002';   -- l'autre boutique
SELECT pg_temp.expect_error($$
    UPDATE order_payments SET status = 'confirmed', confirmed_by_member_id = '10000000-0000-0000-0000-000000000032'
    WHERE id = '10000000-0000-0000-0000-000000000091'
$$, 'paiement confirmé par une autre boutique');

SET mchango.actor_id = '10000000-0000-0000-0000-000000000001';   -- Boutique Nyota
SELECT pg_temp.expect_error($$
    INSERT INTO pickups (order_id, merchant_id, confirmed_by_member_id)
    VALUES ('10000000-0000-0000-0000-000000000081', '10000000-0000-0000-0000-000000000021',
            '10000000-0000-0000-0000-000000000031')
$$, 'retrait d''une commande non payée');

UPDATE order_payments SET status = 'confirmed', confirmed_by_member_id = '10000000-0000-0000-0000-000000000031'
WHERE id = '10000000-0000-0000-0000-000000000091';
UPDATE orders SET status = 'paid' WHERE id = '10000000-0000-0000-0000-000000000081';
SELECT pg_temp.expect(TRUE, 'paiement confirmé par le commerçant, commande payée');

SELECT pg_temp.expect_error($$
    UPDATE order_payments SET amount_minor = 1 WHERE id = '10000000-0000-0000-0000-000000000091'
$$, 'paiement confirmé modifié après coup');
SELECT pg_temp.expect_error($$
    INSERT INTO order_payments (order_id, merchant_id, amount_minor, method, status, confirmed_by_member_id)
    VALUES ('10000000-0000-0000-0000-000000000081', '10000000-0000-0000-0000-000000000021',
            162000, 'cash', 'confirmed', '10000000-0000-0000-0000-000000000031')
$$, 'second paiement sur une commande déjà payée');

-- ---------- Retrait ----------
SELECT pg_temp.expect_error($$
    UPDATE orders SET status = 'picked_up' WHERE id = '10000000-0000-0000-0000-000000000081'
$$, 'commande « retirée » sans retrait constaté');

INSERT INTO pickups (order_id, merchant_id, confirmed_by_member_id) VALUES
    ('10000000-0000-0000-0000-000000000081', '10000000-0000-0000-0000-000000000021',
     '10000000-0000-0000-0000-000000000031');
UPDATE orders SET status = 'picked_up' WHERE id = '10000000-0000-0000-0000-000000000081';
SELECT pg_temp.expect(TRUE, 'retrait constaté par le commerçant, commande retirée');

-- La boutique encaisse Aline directement au comptoir (sans déclaration préalable)
INSERT INTO order_payments (order_id, merchant_id, amount_minor, method, tx_reference, status, confirmed_by_member_id)
VALUES ('10000000-0000-0000-0000-000000000082', '10000000-0000-0000-0000-000000000021',
        108000, 'mpesa', 'QT77AB12CD', 'confirmed', '10000000-0000-0000-0000-000000000031');
UPDATE orders SET status = 'paid' WHERE id = '10000000-0000-0000-0000-000000000082';
SELECT pg_temp.expect(TRUE, 'paiement saisi et confirmé directement par la boutique');

SELECT pg_temp.expect_error($$
    UPDATE orders SET status = 'expired' WHERE id = '10000000-0000-0000-0000-000000000084'
$$, 'commande expirée avant la fin du délai de retrait');
SELECT pg_temp.expect_error($$
    UPDATE offers SET status = 'fulfilled' WHERE id = '10000000-0000-0000-0000-000000000061'
$$, 'offre terminée alors que des commandes sont en cours');

-- ---------- Rien ne s'efface ----------
SELECT pg_temp.expect_error($$ DELETE FROM orders $$,   'DELETE d''une commande');
SELECT pg_temp.expect_error($$ DELETE FROM offers $$,   'DELETE d''une offre');
SELECT pg_temp.expect_error($$ UPDATE pickups SET picked_up_at = now() $$, 'UPDATE d''un retrait');
SELECT pg_temp.expect_error($$ UPDATE shares SET group_id = NULL $$,       'UPDATE d''un partage');

RESET ROLE;

-- ---------- Journal ----------
SELECT pg_temp.expect(audit_verify_chain('offer:10000000-0000-0000-0000-000000000061') IS NULL,
                      'chaîne de l''offre 61 intacte');
SELECT pg_temp.expect(audit_verify_chain('offer:10000000-0000-0000-0000-000000000062') IS NULL,
                      'chaîne de l''offre 62 intacte');
SELECT pg_temp.expect(audit_verify_chain('group:10000000-0000-0000-0000-000000000041') IS NULL
                      AND audit_verify_chain('system') IS NULL,
                      'chaînes du groupe et « system » intactes');
SELECT pg_temp.expect(
    (SELECT count(*) FROM audit_log
     WHERE chain_id = 'offer:10000000-0000-0000-0000-000000000061') = 24,
    'offre 61 : 24 événements (offre ×4, paliers ×2, partages ×3, commandes ×11, paiements ×3, retrait ×1)');
SELECT pg_temp.expect(
    NOT EXISTS (SELECT FROM audit_log
                WHERE chain_id LIKE 'group:%'
                  AND split_part(action, '.', 1) IN ('offers', 'offer_tiers', 'shares', 'orders',
                                                     'order_payments', 'pickups')),
    'aucune commande ni aucun paiement dans la chaîne d''un groupe');
SELECT pg_temp.expect(
    (SELECT count(*) FROM audit_log
     WHERE chain_id = 'system' AND split_part(action, '.', 1) IN ('pickup_zones', 'merchants', 'merchant_members')
       AND payload::jsonb ->> 'id' LIKE '10000000-%') = 5,
    'zone, boutiques et employés posés par l''équipe : dans la chaîne de l''auteur (« system »)');

-- Simule un administrateur malveillant qui baisse le prix final dans le journal.
BEGIN;
ALTER TABLE audit_log DISABLE TRIGGER trg_audit_log_no_update;
UPDATE audit_log SET payload = replace(payload, '54000', '50000')
WHERE chain_id = 'offer:10000000-0000-0000-0000-000000000061' AND action = 'offers.update';
ALTER TABLE audit_log ENABLE TRIGGER trg_audit_log_no_update;
SELECT pg_temp.expect(audit_verify_chain('offer:10000000-0000-0000-0000-000000000061') IS NOT NULL,
                      'falsification du prix final détectée par audit_verify_chain');
ROLLBACK;
