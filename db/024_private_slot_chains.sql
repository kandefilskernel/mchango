-- ============================================================
-- Travailleurs : confidentialité des cotisations jusque dans le journal (spec/categories.md §3.5).
-- ============================================================
-- Dans une tontine « Travailleurs », les collègues ne doivent pas voir qui a payé ni qui est en
-- retard. Jusqu'ici, chaque déclaration, confirmation et contestation entrait dans la chaîne du
-- groupe, que tous les membres lisent et vérifient.
--
-- Désormais, ces trois tables écrivent dans une chaîne PRIVÉE par « case de paiement » :
--     group:<groupe>:slot:<n° du tour>:<adhésion du payeur>
-- Elle ne contient que la cotisation d'un payeur pour un tour. L'API ne la montre qu'au payeur, au
-- bénéficiaire du tour, au témoin d'une remise en espèces et au président : exactement ceux qui
-- voient cette ligne dans l'app. Chacun d'eux peut vérifier la chaîne entière, comme celle du groupe
-- (même format de hash, mchango-v1).
--
-- La chaîne du groupe garde tout le reste (membres, tours, clôture d'un tour, échanges…) : elle
-- reste lisible et vérifiable par tous. Les événements déjà écrits ne bougent pas (ajout seul) :
-- seuls les nouveaux événements des tontines « Travailleurs » vont dans les chaînes privées.

-- Chaîne privée d'une cotisation, ou NULL si le groupe n'est pas « Travailleurs »
CREATE OR REPLACE FUNCTION audit_slot_chain(p_contribution_id UUID) RETURNS TEXT
SECURITY DEFINER SET search_path = public AS $$
    SELECT 'group:' || k.group_id || ':slot:' || c.cycle_number || ':' || k.payer_membership_id
    FROM contributions k
    JOIN cycles c ON c.id = k.cycle_id
    JOIN groups g ON g.id = k.group_id
    WHERE k.id = p_contribution_id AND g.category = 'workers';
$$ LANGUAGE sql STABLE;

-- Reprend 019 à l'identique ; accepte en plus une chaîne privée de cotisation, à condition qu'elle
-- appartienne bien au groupe de l'événement (une écriture ne peut pas viser la chaîne d'un autre).
CREATE OR REPLACE FUNCTION audit_log_set_hash() RETURNS TRIGGER
SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_seq  BIGINT;
    v_hash CHAR(64);
BEGIN
    IF NEW.chain_id IS NOT NULL AND NEW.group_id IS NOT NULL
       AND NEW.chain_id ~ ('^group:' || NEW.group_id::text
                           || ':slot:[1-9][0-9]*:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
        NULL; -- chaîne privée de cotisation, gardée telle quelle
    ELSE
        NEW.chain_id := coalesce('offer:' || NEW.offer_id::text,
                                 audit_chain_for(NEW.group_id, NEW.actor_type, NEW.actor_id));
    END IF;

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

-- Reprend 001 à l'identique ; les cotisations, confirmations et contestations d'une tontine
-- « Travailleurs » vont dans la chaîne privée de leur case de paiement.
CREATE OR REPLACE FUNCTION audit_business_change() RETURNS TRIGGER
SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_actor_type TEXT := nullif(current_setting('mchango.actor_type', true), '');
    v_actor_id   TEXT := nullif(current_setting('mchango.actor_id', true), '');
    v_device_id  TEXT := nullif(current_setting('mchango.device_id', true), '');
    v_row        JSONB := to_jsonb(NEW);   -- accès générique : les colonnes varient selon la table
    v_group_id   UUID;
    v_chain      TEXT;
BEGIN
    IF v_actor_type IS NULL OR (v_actor_type <> 'system' AND v_actor_id IS NULL) THEN
        RAISE EXCEPTION 'auteur non déclaré (SET LOCAL mchango.actor_type / mchango.actor_id)';
    END IF;

    IF TG_TABLE_NAME = 'groups' THEN
        v_group_id := (v_row ->> 'id')::uuid;
    ELSIF TG_TABLE_NAME IN ('confirmations', 'disputes') THEN
        SELECT group_id INTO v_group_id
        FROM contributions WHERE id = (v_row ->> 'contribution_id')::uuid;
        v_chain := audit_slot_chain((v_row ->> 'contribution_id')::uuid);
    ELSE
        v_group_id := (v_row ->> 'group_id')::uuid;
        IF TG_TABLE_NAME = 'contributions' THEN
            v_chain := audit_slot_chain((v_row ->> 'id')::uuid);
        END IF;
    END IF;

    INSERT INTO audit_log (chain_id, group_id, actor_type, actor_id, device_id, action, payload)
    VALUES (v_chain, v_group_id, v_actor_type, v_actor_id::uuid, v_device_id::uuid,
            TG_TABLE_NAME || '.' || lower(TG_OP), v_row::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Lister les chaînes privées d'un groupe sans parcourir tout le journal
CREATE INDEX idx_audit_log_slot_chains ON audit_log (group_id, chain_id) WHERE chain_id LIKE 'group:%:slot:%';
