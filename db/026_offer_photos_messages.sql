-- ============================================================
-- Achats groupés : voir la marchandise, en discuter (spec/achats.md, « Photos et discussion »).
-- ============================================================
-- Quand une offre est envoyée au groupe, chacun voit des photos de la marchandise et peut poser
-- ses questions sous l'offre ; les employés de la boutique répondent, marqués « Boutique ».

-- ---------- Photos : jusqu'à 4 par offre, ajoutées par la boutique avant la publication ----------
-- Une offre publiée ne change plus (019) : ses photos non plus. Pas de journal de l'image elle-même
-- (trop lourde) : l'API inscrit son empreinte SHA-256 dans la chaîne de l'offre.
CREATE TABLE offer_photos (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    offer_id           UUID NOT NULL REFERENCES offers(id),
    position           SMALLINT NOT NULL CHECK (position BETWEEN 1 AND 4),
    content_type       VARCHAR(20) NOT NULL CHECK (content_type IN ('image/jpeg', 'image/png', 'image/webp')),
    bytes              BYTEA NOT NULL CHECK (octet_length(bytes) BETWEEN 1 AND 600000),
    sha256             CHAR(64) NOT NULL CHECK (sha256 = encode(digest(bytes, 'sha256'), 'hex')),
    added_by_member_id UUID NOT NULL REFERENCES merchant_members(id),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (offer_id, position)
);

CREATE OR REPLACE FUNCTION offer_photos_check() RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT status FROM offers WHERE id = NEW.offer_id) <> 'draft' THEN
        RAISE EXCEPTION 'offre publiée : ses photos ne changent plus';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM merchant_members mm JOIN offers o ON o.merchant_id = mm.merchant_id
                   WHERE mm.id = NEW.added_by_member_id AND o.id = NEW.offer_id AND mm.removed_at IS NULL) THEN
        RAISE EXCEPTION 'seule la boutique de l''offre ajoute des photos';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_offer_photos_check BEFORE INSERT ON offer_photos
    FOR EACH ROW EXECUTE FUNCTION offer_photos_check();
CREATE OR REPLACE FUNCTION offer_photos_immutable() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'offer_photos : une photo ne se modifie pas';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_offer_photos_immutable BEFORE UPDATE ON offer_photos
    FOR EACH ROW EXECUTE FUNCTION offer_photos_immutable();
CREATE TRIGGER trg_no_delete_offer_photos BEFORE DELETE ON offer_photos
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();

-- ---------- Discussion sous une offre ----------
-- Ajout seul. Un message d'un employé de la boutique de l'offre porte son identifiant d'employé :
-- l'app l'affiche « Boutique ». hidden_at servira à la modération par l'équipe.
CREATE TABLE offer_messages (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    offer_id           UUID NOT NULL REFERENCES offers(id),
    author_user_id     UUID NOT NULL REFERENCES users(id),
    merchant_member_id UUID REFERENCES merchant_members(id),
    body               VARCHAR(500) NOT NULL CHECK (length(btrim(body)) >= 1),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    hidden_at          TIMESTAMPTZ
);

CREATE INDEX idx_offer_messages_offer ON offer_messages (offer_id, created_at);

CREATE OR REPLACE FUNCTION offer_messages_check() RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT status FROM offers WHERE id = NEW.offer_id) = 'draft' THEN
        RAISE EXCEPTION 'offre pas encore publiée : pas de discussion';
    END IF;
    IF NEW.merchant_member_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM merchant_members mm JOIN offers o ON o.merchant_id = mm.merchant_id
        WHERE mm.id = NEW.merchant_member_id AND mm.user_id = NEW.author_user_id
          AND o.id = NEW.offer_id AND mm.removed_at IS NULL) THEN
        RAISE EXCEPTION 'seul un employé de la boutique de l''offre parle au nom de la boutique';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_offer_messages_check BEFORE INSERT ON offer_messages
    FOR EACH ROW EXECUTE FUNCTION offer_messages_check();

-- Seule la modération (hidden_at) peut changer, une seule fois
CREATE OR REPLACE FUNCTION offer_messages_guard() RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.id, NEW.offer_id, NEW.author_user_id, NEW.merchant_member_id, NEW.body, NEW.created_at)
       IS DISTINCT FROM
       (OLD.id, OLD.offer_id, OLD.author_user_id, OLD.merchant_member_id, OLD.body, OLD.created_at)
       OR OLD.hidden_at IS NOT NULL THEN
        RAISE EXCEPTION 'offer_messages : un message ne se modifie pas';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_offer_messages_guard BEFORE UPDATE ON offer_messages
    FOR EACH ROW EXECUTE FUNCTION offer_messages_guard();
CREATE TRIGGER trg_no_delete_offer_messages BEFORE DELETE ON offer_messages
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();

-- Reprend 019 à l'identique ; les messages vont dans la chaîne de leur offre
CREATE OR REPLACE FUNCTION audit_purchase_change() RETURNS TRIGGER
SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_actor_type TEXT := nullif(current_setting('mchango.actor_type', true), '');
    v_actor_id   TEXT := nullif(current_setting('mchango.actor_id', true), '');
    v_device_id  TEXT := nullif(current_setting('mchango.device_id', true), '');
    v_row        JSONB := to_jsonb(NEW);
    v_offer_id   UUID;
BEGIN
    IF v_actor_type IS NULL OR (v_actor_type <> 'system' AND v_actor_id IS NULL) THEN
        RAISE EXCEPTION 'auteur non déclaré (SET LOCAL mchango.actor_type / mchango.actor_id)';
    END IF;

    IF TG_TABLE_NAME = 'offers' THEN
        v_offer_id := (v_row ->> 'id')::uuid;
    ELSIF TG_TABLE_NAME IN ('offer_tiers', 'shares', 'orders', 'offer_messages') THEN
        v_offer_id := (v_row ->> 'offer_id')::uuid;
    ELSIF TG_TABLE_NAME IN ('order_payments', 'pickups') THEN
        SELECT offer_id INTO v_offer_id
        FROM orders WHERE id = (v_row ->> 'order_id')::uuid;
    END IF;

    INSERT INTO audit_log (group_id, offer_id, actor_type, actor_id, device_id, action, payload)
    VALUES (NULL, v_offer_id, v_actor_type, v_actor_id::uuid, v_device_id::uuid,
            TG_TABLE_NAME || '.' || lower(TG_OP), v_row::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_offer_messages AFTER INSERT OR UPDATE ON offer_messages
    FOR EACH ROW EXECUTE FUNCTION audit_purchase_change();

GRANT SELECT, INSERT ON offer_photos TO mchango_app;
GRANT SELECT, INSERT, UPDATE ON offer_messages TO mchango_app;
