-- ============================================================
-- Rôle applicatif : l'API ne se connecte JAMAIS en propriétaire des tables.
-- Les migrations tournent avec un rôle propriétaire distinct ; l'API utilise un rôle
-- de connexion membre de mchango_app (mot de passe fourni par l'environnement, pas ici) :
--   CREATE ROLE mchango_api LOGIN PASSWORD '...' IN ROLE mchango_app;
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mchango_app') THEN
        CREATE ROLE mchango_app NOLOGIN;
    END IF;
END $$;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO mchango_app;

-- Tables métier : lecture, ajout, mise à jour. Pas de DELETE.
GRANT SELECT, INSERT, UPDATE ON
    users, devices, groups, invitations, memberships, cycles, contributions,
    confirmations, disputes, trust_scores, notifications, staff
TO mchango_app;

-- Journal : lecture et ajout seulement. Les têtes de chaîne ne sont accessibles
-- qu'aux triggers (SECURITY DEFINER), jamais directement.
GRANT SELECT, INSERT ON audit_log TO mchango_app;
GRANT USAGE ON SEQUENCE audit_log_id_seq TO mchango_app;
GRANT EXECUTE ON FUNCTION audit_verify_chain(TEXT) TO mchango_app;
