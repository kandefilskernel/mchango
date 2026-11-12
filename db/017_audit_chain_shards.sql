-- ============================================================
-- Journal : la chaîne « global » est répartie, pour tenir la charge.
-- ============================================================
-- Chaque insertion verrouille la tête de sa chaîne (audit_chain_heads ... FOR UPDATE) : tous
-- les événements hors groupe (connexions, appareils, équipe…) passaient donc un par un sur la
-- même ligne. Avec plusieurs serveurs et beaucoup de connexions, c'était un goulot.
--
-- Désormais, hors groupe, la chaîne dépend de l'auteur :
--   'user:<uuid>'  événements d'un membre (une chaîne par membre : ils ne se bloquent plus) ;
--   'staff'        actions de l'équipe (peu nombreuses, gardées dans un seul ordre) ;
--   'system'       tâches automatiques.
-- Les groupes gardent 'group:<uuid>'. L'ancienne chaîne 'global' est close : elle reste
-- lisible et vérifiable telle quelle (aucun hash n'est recalculé), mais ne reçoit plus rien.

CREATE OR REPLACE FUNCTION audit_chain_for(p_group_id UUID, p_actor_type TEXT, p_actor_id UUID)
RETURNS TEXT AS $$
    SELECT CASE
        WHEN p_group_id IS NOT NULL THEN 'group:' || p_group_id::text
        WHEN p_actor_type = 'user' THEN 'user:' || p_actor_id::text
        WHEN p_actor_type = 'staff' THEN 'staff'
        ELSE 'system'
    END;
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION audit_log_set_hash() RETURNS TRIGGER
SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_seq  BIGINT;
    v_hash CHAR(64);
BEGIN
    NEW.chain_id := audit_chain_for(NEW.group_id, NEW.actor_type, NEW.actor_id);

    INSERT INTO audit_chain_heads (chain_id, last_seq, last_hash)
    VALUES (NEW.chain_id, 0, repeat('0', 64))
    ON CONFLICT (chain_id) DO NOTHING;

    SELECT last_seq, last_hash INTO v_seq, v_hash
    FROM audit_chain_heads WHERE chain_id = NEW.chain_id
    FOR UPDATE;

    NEW.seq        := v_seq + 1;
    NEW.prev_hash  := v_hash;
    NEW.created_at := date_trunc('milliseconds', clock_timestamp());
    NEW.hash       := audit_hash(NEW.chain_id, NEW.seq, NEW.prev_hash, NEW.actor_type,
                                 NEW.actor_id, NEW.device_id, NEW.action, NEW.created_at,
                                 NEW.payload, NEW.signature);

    UPDATE audit_chain_heads SET last_seq = NEW.seq, last_hash = NEW.hash
    WHERE chain_id = NEW.chain_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Fiche membre du back-office : les événements hors groupe qui le concernent (« user_id » du
-- payload), quelle que soit la chaîne, sans parcourir tout le journal.
CREATE INDEX idx_audit_log_payload_user ON audit_log ((payload::jsonb ->> 'user_id'))
    WHERE chain_id NOT LIKE 'group:%';
