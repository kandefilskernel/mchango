-- Produit les événements de référence, calculés par PostgreSQL (source de vérité).
-- À exécuter sur une base vide où db/001_schema.sql est chargé. Sortie : un objet JSON.
\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned

SET mchango.actor_type = 'system';

INSERT INTO users (id, phone, full_name, pin_hash) VALUES
    ('11111111-1111-4111-8111-111111111111', '+243970000001', 'Mama Furaha', 'x'),
    ('22222222-2222-4222-8222-222222222222', '+243970000002', 'Papa Jean',   'x');
INSERT INTO devices (id, user_id, public_key) VALUES
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '22222222-2222-4222-8222-222222222222', 'cHVibGljLWtleQ==');
INSERT INTO staff (id, email, full_name, password_hash, role) VALUES
    ('55555555-5555-4555-8555-555555555555', 'support@mchango.test', 'Support', 'x', 'support');

-- Un vrai groupe : ses événements viennent des triggers métier (payload = to_jsonb(ligne))
INSERT INTO groups (id, name, contribution_amount_minor, frequency, start_date, created_by) VALUES
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Likelemba Kenya', 20000, 'weekly', '2026-11-02',
     '11111111-1111-4111-8111-111111111111');

-- Cas limites insérés directement dans le journal du groupe
INSERT INTO audit_log (group_id, actor_type, actor_id, device_id, action, payload, signature) VALUES
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'user', '22222222-2222-4222-8222-222222222222',
     'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'test.unicode',
     '{"note":"Cotisation reçue — asante sana, matondo 🙏","montant":20000}', NULL),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'user', '22222222-2222-4222-8222-222222222222',
     'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'test.signature',
     '{"tx":"RK45TX9QPL"}', 'c2lnbmF0dXJlLWVkMjU1MTk='),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'staff', '55555555-5555-4555-8555-555555555555',
     NULL, 'test.echappements',
     '{"q":"guillemet \" barre \\ tab \t fin", "espaces" :  [1, 2]}', NULL),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'system', NULL, NULL, 'test.payload_vide', '{}', NULL);

-- Chaîne globale (hors groupe)
INSERT INTO audit_log (group_id, actor_type, actor_id, action, payload) VALUES
    (NULL, 'staff', '55555555-5555-4555-8555-555555555555', 'staff.login', '{"ip":"203.0.113.7"}');

SELECT json_build_object(
    'format', 'mchango-v1',
    'genesis_prev_hash', repeat('0', 64),
    'chains', (
        SELECT json_agg(json_build_object('chain_id', c.chain_id, 'events', c.events) ORDER BY c.chain_id)
        FROM (
            SELECT chain_id, json_agg(json_build_object(
                'chain_id',   chain_id,
                'seq',        seq,
                'prev_hash',  prev_hash,
                'actor_type', actor_type,
                'actor_id',   actor_id,
                'device_id',  device_id,
                'action',     action,
                'created_at', to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
                'payload',    payload,
                'signature',  signature,
                'hash',       hash
            ) ORDER BY seq) AS events
            FROM audit_log GROUP BY chain_id
        ) c
    )
);
