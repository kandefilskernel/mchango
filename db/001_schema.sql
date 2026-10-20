-- ============================================================
-- Mchango : schéma PostgreSQL (MVP) — v0.2
-- Basé sur tontine_schema.sql ; corrections expliquées dans docs/revue-schema.md
-- L'application ne détient aucun fonds : pas de table de solde ni de portefeuille.
-- Cible : PostgreSQL 16+
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------- Types ----------
CREATE TYPE group_type          AS ENUM ('formel', 'informel');
CREATE TYPE currency_code       AS ENUM ('CDF', 'USD');
CREATE TYPE frequency_type      AS ENUM ('daily', 'weekly', 'monthly', 'custom');
CREATE TYPE payout_mode_type    AS ENUM ('direct_to_beneficiary', 'treasurer');
CREATE TYPE group_status        AS ENUM ('draft', 'active', 'suspended', 'closed');
CREATE TYPE member_role         AS ENUM ('member', 'treasurer', 'president');
CREATE TYPE member_status       AS ENUM ('invited', 'active', 'left', 'removed');
CREATE TYPE cycle_status        AS ENUM ('upcoming', 'open', 'completed', 'cancelled');
CREATE TYPE pay_method          AS ENUM ('mpesa', 'airtel', 'orange', 'cash', 'other');
CREATE TYPE contribution_status AS ENUM ('declared', 'confirmed', 'disputed', 'rejected');
CREATE TYPE decision_type       AS ENUM ('confirm', 'dispute');
CREATE TYPE dispute_status      AS ENUM ('open', 'resolved_confirmed', 'resolved_rejected', 'withdrawn');
CREATE TYPE channel_type        AS ENUM ('sms', 'whatsapp', 'push');
CREATE TYPE notification_status AS ENUM ('queued', 'sent', 'failed');
CREATE TYPE staff_role          AS ENUM ('super_admin', 'support', 'compliance', 'finance', 'read_only');

-- ---------- Utilisateurs ----------
CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone         VARCHAR(16) NOT NULL UNIQUE
                  CHECK (phone ~ '^\+[1-9][0-9]{7,14}$'),        -- E.164, ex. +243970000000
    full_name     VARCHAR(150) NOT NULL,
    pin_hash      TEXT NOT NULL,                                -- argon2id, jamais un hash rapide
    language      VARCHAR(5) NOT NULL DEFAULT 'fr'
                  CHECK (language IN ('fr', 'sw', 'ln')),
    kyc_level     SMALLINT NOT NULL DEFAULT 0
                  CHECK (kyc_level BETWEEN 0 AND 2),            -- 0 téléphone, 1 identité, 2 vérifié
    is_blocked    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Appareils : liaison de compte, jeton push, clé publique pour signer les actions
CREATE TABLE devices (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id),
    public_key    TEXT NOT NULL,                                -- Ed25519, base64
    push_token    TEXT,
    platform      VARCHAR(10) NOT NULL DEFAULT 'android',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ,
    revoked_at    TIMESTAMPTZ
);

-- ---------- Groupes ----------
-- Montants en unités mineures entières (CDF : francs ; USD : cents).
-- Dart n'a pas de type décimal natif : un entier évite toute dérive en double.
CREATE TABLE groups (
    id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                       VARCHAR(150) NOT NULL,
    type                       group_type NOT NULL DEFAULT 'informel',
    currency                   currency_code NOT NULL DEFAULT 'CDF',
    contribution_amount_minor  BIGINT NOT NULL CHECK (contribution_amount_minor > 0),
    frequency                  frequency_type NOT NULL,
    payout_mode                payout_mode_type NOT NULL DEFAULT 'direct_to_beneficiary',
    late_penalty_rule          JSONB,                           -- V2 ; payée de membre à membre
    start_date                 DATE NOT NULL,
    status                     group_status NOT NULL DEFAULT 'draft',
    created_by                 UUID NOT NULL REFERENCES users(id),
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Invitations par numéro, y compris pour qui n'a pas encore de compte
CREATE TABLE invitations (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id      UUID NOT NULL REFERENCES groups(id),
    phone         VARCHAR(16) NOT NULL CHECK (phone ~ '^\+[1-9][0-9]{7,14}$'),
    invited_by    UUID NOT NULL REFERENCES users(id),
    token_hash    CHAR(64) NOT NULL UNIQUE,                     -- SHA-256 du jeton du lien
    expires_at    TIMESTAMPTZ NOT NULL,
    accepted_at   TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE memberships (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id          UUID NOT NULL REFERENCES groups(id),
    user_id           UUID NOT NULL REFERENCES users(id),
    role              member_role NOT NULL DEFAULT 'member',
    turn_order        INT CHECK (turn_order > 0),
    status            member_status NOT NULL DEFAULT 'invited',
    rules_accepted_at TIMESTAMPTZ,
    joined_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (group_id, user_id),
    UNIQUE (group_id, turn_order),
    UNIQUE (id, group_id)            -- cible des clés composites : garantit « même groupe »
);

-- ---------- Cycles (un cycle = un tour = un bénéficiaire) ----------
CREATE TABLE cycles (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id                  UUID NOT NULL REFERENCES groups(id),
    cycle_number              INT NOT NULL CHECK (cycle_number > 0),
    due_date                  DATE NOT NULL,
    beneficiary_membership_id UUID NOT NULL,
    status                    cycle_status NOT NULL DEFAULT 'upcoming',
    UNIQUE (group_id, cycle_number),
    UNIQUE (id, group_id),
    FOREIGN KEY (beneficiary_membership_id, group_id) REFERENCES memberships (id, group_id)
);

-- ---------- Cotisations ----------
CREATE TABLE contributions (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cycle_id               UUID NOT NULL,
    group_id               UUID NOT NULL,
    payer_membership_id    UUID NOT NULL,
    receiver_membership_id UUID NOT NULL,     -- bénéficiaire (mode direct) ou trésorier
    amount_minor           BIGINT NOT NULL CHECK (amount_minor > 0),
    method                 pay_method NOT NULL,
    tx_reference           VARCHAR(100),
    proof_url              TEXT,
    status                 contribution_status NOT NULL DEFAULT 'declared',
    is_late                BOOLEAN NOT NULL DEFAULT FALSE,     -- déclarée après l'échéance
    offline_id             UUID NOT NULL UNIQUE,              -- idempotence de la synchro hors ligne
    declared_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (cycle_id, group_id)               REFERENCES cycles (id, group_id),
    FOREIGN KEY (payer_membership_id, group_id)    REFERENCES memberships (id, group_id),
    FOREIGN KEY (receiver_membership_id, group_id) REFERENCES memberships (id, group_id),
    CHECK (payer_membership_id <> receiver_membership_id),
    -- Mobile money : référence obligatoire, normalisée (majuscules, sans espaces autour)
    CHECK (method = 'cash' OR tx_reference IS NOT NULL),
    CHECK (tx_reference IS NULL OR tx_reference = upper(btrim(tx_reference)))
);

-- Une seule cotisation active par membre et par tour (re-déclaration possible après rejet)
CREATE UNIQUE INDEX uq_contrib_active_per_payer
    ON contributions (cycle_id, payer_membership_id)
    WHERE status <> 'rejected';

-- Un même ID de transaction d'un opérateur ne peut servir qu'une fois, tous groupes confondus
CREATE UNIQUE INDEX uq_contrib_txref
    ON contributions (method, tx_reference)
    WHERE tx_reference IS NOT NULL AND status <> 'rejected';

CREATE TABLE confirmations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contribution_id UUID NOT NULL REFERENCES contributions(id),
    confirmed_by    UUID NOT NULL REFERENCES memberships(id),
    decision        decision_type NOT NULL,
    note            TEXT,
    confirmed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Double regard : seul le receveur prévu peut confirmer
CREATE OR REPLACE FUNCTION confirmations_check_receiver() RETURNS TRIGGER AS $$
DECLARE
    v_receiver UUID;
BEGIN
    SELECT receiver_membership_id INTO v_receiver
    FROM contributions WHERE id = NEW.contribution_id;
    IF NEW.decision = 'confirm' AND NEW.confirmed_by <> v_receiver THEN
        RAISE EXCEPTION 'seul le receveur de la cotisation peut la confirmer';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_confirmations_check_receiver
    BEFORE INSERT ON confirmations
    FOR EACH ROW EXECUTE FUNCTION confirmations_check_receiver();

-- ---------- Litiges ----------
CREATE TABLE disputes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contribution_id UUID NOT NULL REFERENCES contributions(id),
    opened_by       UUID NOT NULL REFERENCES memberships(id),
    reason          TEXT NOT NULL,
    status          dispute_status NOT NULL DEFAULT 'open',
    resolution_note TEXT,
    opened_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at     TIMESTAMPTZ
);

-- ---------- Score de confiance (V2 : ne pas calculer au MVP) ----------
CREATE TABLE trust_scores (
    user_id          UUID PRIMARY KEY REFERENCES users(id),
    score            SMALLINT NOT NULL DEFAULT 0 CHECK (score BETWEEN 0 AND 100),
    on_time_rate     NUMERIC(5,2) NOT NULL DEFAULT 0,
    cycles_completed INT NOT NULL DEFAULT 0,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- Notifications ----------
CREATE TABLE notifications (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id),
    channel    channel_type NOT NULL,
    template   VARCHAR(80) NOT NULL,
    payload    JSONB,
    status     notification_status NOT NULL DEFAULT 'queued',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent_at    TIMESTAMPTZ
);

-- ---------- Équipe interne (back-office) ----------
CREATE TABLE staff (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(200) NOT NULL UNIQUE,
    full_name       VARCHAR(150) NOT NULL,
    password_hash   TEXT NOT NULL,                  -- argon2id
    role            staff_role NOT NULL,
    totp_secret_enc TEXT,                           -- chiffré par l'application, jamais en clair
    totp_enabled_at TIMESTAMPTZ,                    -- l'API refuse toute action tant que NULL
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- Journal d'audit : ajout seul, une chaîne de hash par groupe
-- ============================================================
-- chain_id = 'group:<uuid>' pour un groupe, 'global' pour le reste (back-office, comptes).
-- Hash = SHA-256 de ces champs joints par '\n', dans cet ordre :
--   'mchango-v1', chain_id, seq, prev_hash, actor_type, actor_id, device_id,
--   action, created_at (UTC, 'YYYY-MM-DDTHH:MM:SS.mmmZ'), payload, signature
-- (valeurs NULL → chaîne vide). Le payload est hashé tel qu'il est stocké, octet pour octet :
-- un client Dart vérifie la chaîne sans reproduire la sérialisation JSON de PostgreSQL.

CREATE TABLE audit_chain_heads (
    chain_id   TEXT PRIMARY KEY,
    last_seq   BIGINT NOT NULL,
    last_hash  CHAR(64) NOT NULL
);

CREATE TABLE audit_log (
    id          BIGSERIAL PRIMARY KEY,
    chain_id    TEXT NOT NULL,
    seq         BIGINT NOT NULL,
    group_id    UUID REFERENCES groups(id),
    actor_type  VARCHAR(10) NOT NULL CHECK (actor_type IN ('user', 'staff', 'system')),
    actor_id    UUID,
    device_id   UUID REFERENCES devices(id),
    action      VARCHAR(80) NOT NULL,
    payload     TEXT NOT NULL CHECK (payload IS JSON AND position(E'\n' IN payload) = 0),
    signature   TEXT,                                -- Ed25519 de l'appareil (base64), si fourni
    prev_hash   CHAR(64) NOT NULL,
    hash        CHAR(64) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL,
    UNIQUE (chain_id, seq),
    CHECK (actor_type = 'system' OR actor_id IS NOT NULL)
);

CREATE OR REPLACE FUNCTION audit_hash(
    p_chain_id TEXT, p_seq BIGINT, p_prev_hash TEXT, p_actor_type TEXT, p_actor_id UUID,
    p_device_id UUID, p_action TEXT, p_created_at TIMESTAMPTZ, p_payload TEXT, p_signature TEXT
) RETURNS CHAR(64) AS $$
    SELECT encode(digest(convert_to(concat_ws(E'\n',
        'mchango-v1',
        p_chain_id,
        p_seq::text,
        p_prev_hash,
        p_actor_type,
        coalesce(p_actor_id::text, ''),
        coalesce(p_device_id::text, ''),
        p_action,
        to_char(p_created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        p_payload,
        coalesce(p_signature, '')
    ), 'UTF8'), 'sha256'), 'hex');
$$ LANGUAGE sql IMMUTABLE;

-- Chaînage sous verrou : deux insertions concurrentes dans un même groupe sont sérialisées,
-- la chaîne ne peut pas « fourcher ». Des groupes différents ne se bloquent pas entre eux.
CREATE OR REPLACE FUNCTION audit_log_set_hash() RETURNS TRIGGER
SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_seq  BIGINT;
    v_hash CHAR(64);
BEGIN
    NEW.chain_id := coalesce('group:' || NEW.group_id::text, 'global');

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

CREATE TRIGGER trg_audit_log_hash
    BEFORE INSERT ON audit_log
    FOR EACH ROW EXECUTE FUNCTION audit_log_set_hash();

CREATE OR REPLACE FUNCTION audit_log_immutable() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'audit_log est en ajout seul : modification interdite';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_log_no_update
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION audit_log_immutable();

-- Les triggers de ligne ne voient pas TRUNCATE : il faut un trigger d'instruction
CREATE TRIGGER trg_audit_log_no_truncate
    BEFORE TRUNCATE ON audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION audit_log_immutable();

-- Vérification d'une chaîne : renvoie le premier seq invalide, ou NULL si tout est intact.
-- Utilisée par le back-office (« vérifier la chaîne ») et par un job périodique.
CREATE OR REPLACE FUNCTION audit_verify_chain(p_chain_id TEXT) RETURNS BIGINT AS $$
DECLARE
    r          audit_log%ROWTYPE;
    v_prev     CHAR(64) := repeat('0', 64);
    v_expected BIGINT := 1;
BEGIN
    FOR r IN SELECT * FROM audit_log WHERE chain_id = p_chain_id ORDER BY seq LOOP
        IF r.seq <> v_expected OR r.prev_hash <> v_prev
           OR r.hash <> audit_hash(r.chain_id, r.seq, r.prev_hash, r.actor_type, r.actor_id,
                                   r.device_id, r.action, r.created_at, r.payload, r.signature)
        THEN
            RETURN v_expected;
        END IF;
        v_prev := r.hash;
        v_expected := v_expected + 1;
    END LOOP;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================
-- Journalisation automatique des tables métier
-- ============================================================
-- Aucune écriture métier ne peut échapper au journal : chaque INSERT/UPDATE est consigné
-- dans la même transaction. L'API déclare l'auteur au début de chaque transaction :
--   SET LOCAL mchango.actor_type = 'user';
--   SET LOCAL mchango.actor_id   = '<uuid>';
--   SET LOCAL mchango.device_id  = '<uuid>';   -- facultatif
-- Sans auteur déclaré, l'écriture est refusée.

CREATE OR REPLACE FUNCTION audit_business_change() RETURNS TRIGGER
SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_actor_type TEXT := nullif(current_setting('mchango.actor_type', true), '');
    v_actor_id   TEXT := nullif(current_setting('mchango.actor_id', true), '');
    v_device_id  TEXT := nullif(current_setting('mchango.device_id', true), '');
    v_row        JSONB := to_jsonb(NEW);   -- accès générique : les colonnes varient selon la table
    v_group_id   UUID;
BEGIN
    IF v_actor_type IS NULL OR (v_actor_type <> 'system' AND v_actor_id IS NULL) THEN
        RAISE EXCEPTION 'auteur non déclaré (SET LOCAL mchango.actor_type / mchango.actor_id)';
    END IF;

    IF TG_TABLE_NAME = 'groups' THEN
        v_group_id := (v_row ->> 'id')::uuid;
    ELSIF TG_TABLE_NAME IN ('confirmations', 'disputes') THEN
        SELECT group_id INTO v_group_id
        FROM contributions WHERE id = (v_row ->> 'contribution_id')::uuid;
    ELSE
        v_group_id := (v_row ->> 'group_id')::uuid;
    END IF;

    INSERT INTO audit_log (group_id, actor_type, actor_id, device_id, action, payload)
    VALUES (v_group_id, v_actor_type, v_actor_id::uuid, v_device_id::uuid,
            TG_TABLE_NAME || '.' || lower(TG_OP), v_row::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_groups        AFTER INSERT OR UPDATE ON groups
    FOR EACH ROW EXECUTE FUNCTION audit_business_change();
CREATE TRIGGER trg_audit_memberships   AFTER INSERT OR UPDATE ON memberships
    FOR EACH ROW EXECUTE FUNCTION audit_business_change();
CREATE TRIGGER trg_audit_cycles        AFTER INSERT OR UPDATE ON cycles
    FOR EACH ROW EXECUTE FUNCTION audit_business_change();
CREATE TRIGGER trg_audit_contributions AFTER INSERT OR UPDATE ON contributions
    FOR EACH ROW EXECUTE FUNCTION audit_business_change();
CREATE TRIGGER trg_audit_confirmations AFTER INSERT OR UPDATE ON confirmations
    FOR EACH ROW EXECUTE FUNCTION audit_business_change();
CREATE TRIGGER trg_audit_disputes      AFTER INSERT OR UPDATE ON disputes
    FOR EACH ROW EXECUTE FUNCTION audit_business_change();

-- Pas de suppression physique de l'historique métier : on clôture, on ne supprime pas
CREATE OR REPLACE FUNCTION forbid_delete() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION '% : suppression interdite, changer le statut à la place', TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_no_delete_groups        BEFORE DELETE ON groups
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_no_delete_memberships   BEFORE DELETE ON memberships
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_no_delete_cycles        BEFORE DELETE ON cycles
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_no_delete_contributions BEFORE DELETE ON contributions
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_no_delete_confirmations BEFORE DELETE ON confirmations
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_no_delete_disputes      BEFORE DELETE ON disputes
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();

-- ---------- Index utiles ----------
CREATE INDEX idx_devices_user          ON devices (user_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_invitations_phone     ON invitations (phone) WHERE accepted_at IS NULL;
CREATE INDEX idx_memberships_user      ON memberships (user_id);
CREATE INDEX idx_cycles_group_due      ON cycles (group_id, due_date);
CREATE INDEX idx_contrib_cycle         ON contributions (cycle_id);
CREATE INDEX idx_contrib_payer         ON contributions (payer_membership_id);
CREATE INDEX idx_contrib_receiver      ON contributions (receiver_membership_id, status);
CREATE INDEX idx_confirmations_contrib ON confirmations (contribution_id);
CREATE INDEX idx_disputes_open         ON disputes (contribution_id) WHERE status = 'open';
CREATE INDEX idx_audit_group           ON audit_log (group_id, seq);
CREATE INDEX idx_notifications_user    ON notifications (user_id, status);
