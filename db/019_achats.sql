-- ============================================================
-- Achats groupés : boutiques, offres à paliers, commandes, paiements, retraits, partages.
-- Décisions : docs/plan-achats-groupes.md §8.
--
-- Les groupes restent ceux de la tontine : une offre peut y être proposée. Les rendre
-- possibles sans tontine (groupe d'achat seul) est une étape à part, qui touche aussi les
-- écrans et le règlement signé.
--
-- Le commerçant encaisse en boutique : toujours aucune table de solde ni de portefeuille.
-- Mchango enregistre des réservations, des paiements constatés par le commerçant et des
-- retraits ; il ne détient ni ne transfère l'argent des achats.
-- ============================================================

-- ---------- Types ----------
CREATE TYPE merchant_status      AS ENUM ('pending', 'active', 'suspended');
CREATE TYPE merchant_member_role AS ENUM ('owner', 'staff');
CREATE TYPE offer_status         AS ENUM ('draft', 'open', 'closed', 'cancelled', 'fulfilled');
CREATE TYPE order_status         AS ENUM ('reserved', 'ready', 'paid', 'picked_up', 'cancelled', 'expired');
CREATE TYPE payment_status       AS ENUM ('declared', 'confirmed', 'rejected');
CREATE TYPE share_channel        AS ENUM ('whatsapp', 'group');

-- ---------- Auteur déclaré ----------
-- Quand l'auteur de la transaction est un utilisateur, il doit être la personne attendue :
-- personne ne commande, ne confirme un paiement ou ne remet un produit au nom d'un autre.
-- Les auteurs 'staff' et 'system' (jobs de clôture, support) ne sont pas concernés.
CREATE FUNCTION require_actor(p_user_id UUID, p_what TEXT) RETURNS VOID AS $$
BEGIN
    IF current_setting('mchango.actor_type', true) = 'user'
       AND nullif(current_setting('mchango.actor_id', true), '')::uuid IS DISTINCT FROM p_user_id
    THEN
        RAISE EXCEPTION '% : l''auteur déclaré n''est pas la personne concernée', p_what;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

-- ---------- Zones de retrait et commerçants ----------
-- Liste fermée par commune, gérée par l'équipe.
CREATE TABLE pickup_zones (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city       VARCHAR(80) NOT NULL,
    commune    VARCHAR(80) NOT NULL,
    is_active  BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (city, commune)
);

CREATE TABLE merchants (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       VARCHAR(150) NOT NULL,
    zone_id    UUID NOT NULL REFERENCES pickup_zones(id),
    address    TEXT NOT NULL,
    phone      VARCHAR(16) NOT NULL CHECK (phone ~ '^\+[1-9][0-9]{7,14}$'),
    status     merchant_status NOT NULL DEFAULT 'pending',     -- activé par l'équipe
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Personnes autorisées à agir pour la boutique (créer une offre, encaisser, remettre)
CREATE TABLE merchant_members (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id),
    user_id     UUID NOT NULL REFERENCES users(id),
    role        merchant_member_role NOT NULL DEFAULT 'staff',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    removed_at  TIMESTAMPTZ,                                   -- pas de suppression : on retire
    UNIQUE (merchant_id, user_id),
    UNIQUE (id, merchant_id)         -- cible des clés composites : garantit « même boutique »
);

-- ---------- Offres ----------
CREATE TABLE offers (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id            UUID NOT NULL REFERENCES merchants(id),
    created_by_member_id   UUID NOT NULL,
    title                  VARCHAR(150) NOT NULL,
    description            TEXT,
    unit_label             VARCHAR(40) NOT NULL,               -- ex. « sac de 25 kg »
    image_url              TEXT,
    currency               currency_code NOT NULL DEFAULT 'CDF',
    regular_price_minor    BIGINT NOT NULL CHECK (regular_price_minor > 0),   -- prix habituel
    ends_at                TIMESTAMPTZ NOT NULL,
    -- Délai de retrait fixé par le commerçant, borné par l'équipe (bornes à confirmer)
    pickup_window_hours    INT NOT NULL CHECK (pickup_window_hours BETWEEN 24 AND 336),
    status                 offer_status NOT NULL DEFAULT 'draft',
    final_unit_price_minor BIGINT,                             -- calculé par la base à la clôture
    closed_at              TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, merchant_id),
    FOREIGN KEY (created_by_member_id, merchant_id) REFERENCES merchant_members (id, merchant_id),
    CHECK ((status IN ('closed', 'fulfilled')) = (final_unit_price_minor IS NOT NULL)),
    CHECK ((status IN ('closed', 'fulfilled')) = (closed_at IS NOT NULL))
);

-- Paliers : à partir de min_quantity unités confirmées, le prix unitaire est unit_price_minor.
-- Le plus petit min_quantity est le seuil minimum de l'offre.
CREATE TABLE offer_tiers (
    offer_id         UUID NOT NULL REFERENCES offers(id),
    min_quantity     INT NOT NULL CHECK (min_quantity > 0),
    unit_price_minor BIGINT NOT NULL CHECK (unit_price_minor > 0),
    PRIMARY KEY (offer_id, min_quantity)
);

-- ---------- Partages (invitations) ----------
-- Un partage n'est jamais une commande et ne modifie aucun compteur.
-- parent_share_id garde l'origine : qui a transmis l'offre à qui.
-- Un partage vers un groupe est la proposition visible dans « Achats proposés ».
CREATE TABLE shares (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    offer_id          UUID NOT NULL REFERENCES offers(id),
    parent_share_id   UUID,
    shared_by_user_id UUID REFERENCES users(id),               -- NULL : visiteur sans compte
    channel           share_channel NOT NULL,
    group_id          UUID REFERENCES groups(id),
    token_hash        CHAR(64) UNIQUE,                         -- SHA-256 du jeton du lien
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, offer_id),
    FOREIGN KEY (parent_share_id, offer_id) REFERENCES shares (id, offer_id),
    CHECK ((channel = 'group') = (group_id IS NOT NULL)),
    CHECK (channel <> 'group' OR shared_by_user_id IS NOT NULL),
    CHECK (channel = 'group' OR token_hash IS NOT NULL)
);

-- Une offre n'est proposée qu'une fois par groupe
CREATE UNIQUE INDEX uq_shares_offer_group ON shares (offer_id, group_id) WHERE group_id IS NOT NULL;

-- ---------- Commandes ----------
CREATE TABLE orders (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    offer_id      UUID NOT NULL,
    merchant_id   UUID NOT NULL,
    buyer_user_id UUID NOT NULL REFERENCES users(id),
    quantity      INT NOT NULL CHECK (quantity > 0),
    pickup_name   VARCHAR(150) NOT NULL,                       -- nom pour le retrait
    via_share_id  UUID,                                        -- origine de l'invitation, si connue
    status        order_status NOT NULL DEFAULT 'reserved',
    pickup_code   VARCHAR(12),                                 -- ex. MC-4832, attribué à la clôture
    offline_id    UUID NOT NULL UNIQUE,                        -- idempotence de la synchro hors ligne
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, merchant_id),
    FOREIGN KEY (offer_id, merchant_id) REFERENCES offers (id, merchant_id),
    FOREIGN KEY (via_share_id, offer_id) REFERENCES shares (id, offer_id),
    CHECK (status NOT IN ('ready', 'paid', 'picked_up') OR pickup_code IS NOT NULL)
);

-- Une seule commande active par acheteur et par offre : jamais comptée deux fois,
-- quel que soit le nombre de groupes ou de liens par lesquels l'offre est arrivée.
CREATE UNIQUE INDEX uq_orders_active_per_buyer
    ON orders (offer_id, buyer_user_id)
    WHERE status <> 'cancelled';

-- Un code de retrait désigne une seule commande en attente dans une boutique
CREATE UNIQUE INDEX uq_orders_pickup_code
    ON orders (merchant_id, pickup_code)
    WHERE status IN ('ready', 'paid');

-- ---------- Paiements (encaissés par le commerçant) ----------
-- L'acheteur peut déclarer ; seul un membre de la boutique confirme.
-- Un paiement déclaré n'est pas un paiement vérifié.
CREATE TABLE order_payments (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id               UUID NOT NULL,
    merchant_id            UUID NOT NULL,
    amount_minor           BIGINT NOT NULL CHECK (amount_minor > 0),
    method                 pay_method NOT NULL,
    tx_reference           VARCHAR(100),
    status                 payment_status NOT NULL DEFAULT 'declared',
    declared_by_user_id    UUID REFERENCES users(id),          -- NULL : saisi par la boutique
    confirmed_by_member_id UUID,
    confirmed_at           TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (order_id, merchant_id) REFERENCES orders (id, merchant_id),
    FOREIGN KEY (confirmed_by_member_id, merchant_id) REFERENCES merchant_members (id, merchant_id),
    CHECK ((status = 'confirmed') = (confirmed_at IS NOT NULL)),
    CHECK (status <> 'confirmed' OR confirmed_by_member_id IS NOT NULL),
    CHECK (status <> 'declared' OR declared_by_user_id IS NOT NULL),
    CHECK (method = 'cash' OR tx_reference IS NOT NULL),
    CHECK (tx_reference IS NULL OR tx_reference = upper(btrim(tx_reference)))
);

CREATE UNIQUE INDEX uq_order_payments_confirmed
    ON order_payments (order_id) WHERE status = 'confirmed';
CREATE UNIQUE INDEX uq_order_payments_txref
    ON order_payments (method, tx_reference)
    WHERE tx_reference IS NOT NULL AND status <> 'rejected';

-- ---------- Retraits ----------
CREATE TABLE pickups (
    order_id               UUID PRIMARY KEY,
    merchant_id            UUID NOT NULL,
    confirmed_by_member_id UUID NOT NULL,
    picked_up_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (order_id, merchant_id) REFERENCES orders (id, merchant_id),
    FOREIGN KEY (confirmed_by_member_id, merchant_id) REFERENCES merchant_members (id, merchant_id)
);

-- ============================================================
-- Règles métier portées par la base
-- ============================================================

-- ---------- Offres : cycle de vie et prix final ----------
-- draft → open → closed → fulfilled ; draft/open → cancelled.
-- Une fois ouverte, l'offre ne change plus : ni prix, ni date de fin, ni délai de retrait.
-- Le prix final est celui du palier atteint, calculé ici et nulle part ailleurs.
CREATE FUNCTION offers_guard() RETURNS TRIGGER AS $$
DECLARE
    v_units BIGINT;
    v_price BIGINT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'draft' THEN
            RAISE EXCEPTION 'une offre se crée en brouillon';
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.status <> 'draft' AND ROW(
           NEW.merchant_id, NEW.created_by_member_id, NEW.title, NEW.description, NEW.unit_label,
           NEW.image_url, NEW.currency, NEW.regular_price_minor, NEW.ends_at,
           NEW.pickup_window_hours, NEW.created_at
       ) IS DISTINCT FROM ROW(
           OLD.merchant_id, OLD.created_by_member_id, OLD.title, OLD.description, OLD.unit_label,
           OLD.image_url, OLD.currency, OLD.regular_price_minor, OLD.ends_at,
           OLD.pickup_window_hours, OLD.created_at
       )
    THEN
        RAISE EXCEPTION 'une offre publiée ne peut plus être modifiée';
    END IF;

    -- Seule la clôture fixe ces deux champs ; toute valeur fournie par l'appelant est ignorée
    NEW.final_unit_price_minor := OLD.final_unit_price_minor;
    NEW.closed_at              := OLD.closed_at;

    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    -- Sérialise avec les réservations concurrentes (voir orders_guard)
    PERFORM 1 FROM offers WHERE id = OLD.id FOR UPDATE;

    IF OLD.status = 'draft' AND NEW.status = 'open' THEN
        IF NEW.ends_at <= clock_timestamp() THEN
            RAISE EXCEPTION 'la date de fin est déjà passée';
        END IF;
        IF NOT EXISTS (SELECT FROM merchants WHERE id = NEW.merchant_id AND status = 'active') THEN
            RAISE EXCEPTION 'la boutique n''est pas active';
        END IF;
        IF NOT EXISTS (SELECT FROM offer_tiers WHERE offer_id = NEW.id) THEN
            RAISE EXCEPTION 'une offre doit avoir au moins un palier de prix';
        END IF;
        IF EXISTS (SELECT FROM offer_tiers a JOIN offer_tiers b
                       ON a.offer_id = b.offer_id AND a.min_quantity < b.min_quantity
                   WHERE a.offer_id = NEW.id AND a.unit_price_minor <= b.unit_price_minor) THEN
            RAISE EXCEPTION 'le prix doit baisser à chaque palier';
        END IF;

    ELSIF OLD.status IN ('draft', 'open') AND NEW.status = 'cancelled' THEN
        NULL;

    ELSIF OLD.status = 'open' AND NEW.status = 'closed' THEN
        IF clock_timestamp() < OLD.ends_at THEN
            RAISE EXCEPTION 'l''offre ne se clôture qu''à sa date de fin';
        END IF;
        SELECT coalesce(sum(quantity), 0) INTO v_units
        FROM orders WHERE offer_id = OLD.id AND status = 'reserved';
        SELECT unit_price_minor INTO v_price
        FROM offer_tiers WHERE offer_id = OLD.id AND min_quantity <= v_units
        ORDER BY min_quantity DESC LIMIT 1;
        IF v_price IS NULL THEN
            RAISE EXCEPTION 'seuil minimum non atteint (% unités) : l''offre doit être annulée', v_units;
        END IF;
        NEW.final_unit_price_minor := v_price;
        NEW.closed_at              := clock_timestamp();

    ELSIF OLD.status = 'closed' AND NEW.status = 'fulfilled' THEN
        IF EXISTS (SELECT FROM orders WHERE offer_id = OLD.id
                   AND status IN ('reserved', 'ready', 'paid')) THEN
            RAISE EXCEPTION 'des commandes sont encore en cours';
        END IF;

    ELSE
        RAISE EXCEPTION 'transition d''offre interdite : % → %', OLD.status, NEW.status;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_offers_guard
    BEFORE INSERT OR UPDATE ON offers
    FOR EACH ROW EXECUTE FUNCTION offers_guard();

-- Les paliers ne se définissent que sur un brouillon : le commerçant ne peut pas
-- changer les prix une fois que des acheteurs se sont engagés.
CREATE FUNCTION offer_tiers_guard() RETURNS TRIGGER AS $$
DECLARE
    v_offer offers%ROWTYPE;
BEGIN
    SELECT * INTO v_offer FROM offers WHERE id = NEW.offer_id FOR SHARE;
    IF v_offer.status <> 'draft' THEN
        RAISE EXCEPTION 'les paliers d''une offre publiée ne peuvent plus changer';
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.offer_id <> OLD.offer_id THEN
        RAISE EXCEPTION 'un palier ne change pas d''offre';
    END IF;
    IF NEW.unit_price_minor >= v_offer.regular_price_minor THEN
        RAISE EXCEPTION 'le prix d''un palier doit être inférieur au prix habituel';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_offer_tiers_guard
    BEFORE INSERT OR UPDATE ON offer_tiers
    FOR EACH ROW EXECUTE FUNCTION offer_tiers_guard();

-- ---------- Partages ----------
CREATE FUNCTION shares_guard() RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT FROM offers WHERE id = NEW.offer_id AND status = 'open') THEN
        RAISE EXCEPTION 'seule une offre ouverte peut être partagée';
    END IF;
    IF NEW.shared_by_user_id IS NOT NULL THEN
        PERFORM require_actor(NEW.shared_by_user_id, 'partage');
    END IF;
    IF NEW.channel = 'group' AND NOT EXISTS (
        SELECT FROM memberships
        WHERE group_id = NEW.group_id AND user_id = NEW.shared_by_user_id AND status = 'active'
    ) THEN
        RAISE EXCEPTION 'seul un membre actif peut proposer une offre à son groupe';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_shares_guard
    BEFORE INSERT ON shares
    FOR EACH ROW EXECUTE FUNCTION shares_guard();

-- ---------- Commandes : cycle de vie ----------
-- reserved → ready (offre clôturée) → paid (paiement confirmé) → picked_up (retrait constaté)
-- reserved → cancelled (tant que l'offre est ouverte, ou si elle est annulée)
-- ready → expired (délai de retrait dépassé)
CREATE FUNCTION orders_guard() RETURNS TRIGGER AS $$
DECLARE
    v_offer offers%ROWTYPE;
BEGIN
    -- FOR SHARE : une clôture concurrente attend la fin de cette réservation, et une
    -- réservation qui arrive pendant la clôture voit l'offre fermée. Aucune commande
    -- ne peut échapper au décompte qui fixe le prix.
    SELECT * INTO v_offer FROM offers WHERE id = NEW.offer_id FOR SHARE;

    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'reserved' OR NEW.pickup_code IS NOT NULL THEN
            RAISE EXCEPTION 'une commande commence par une réservation';
        END IF;
        IF v_offer.status <> 'open' OR clock_timestamp() >= v_offer.ends_at THEN
            RAISE EXCEPTION 'l''offre n''accepte plus de réservation';
        END IF;
        PERFORM require_actor(NEW.buyer_user_id, 'réservation');
        RETURN NEW;
    END IF;

    IF ROW(NEW.offer_id, NEW.merchant_id, NEW.buyer_user_id, NEW.via_share_id, NEW.offline_id,
           NEW.created_at)
       IS DISTINCT FROM
       ROW(OLD.offer_id, OLD.merchant_id, OLD.buyer_user_id, OLD.via_share_id, OLD.offline_id,
           OLD.created_at)
    THEN
        RAISE EXCEPTION 'ces champs d''une commande ne se modifient pas';
    END IF;

    IF NEW.quantity <> OLD.quantity OR NEW.pickup_name <> OLD.pickup_name THEN
        IF OLD.status <> 'reserved' OR NEW.status <> 'reserved'
           OR v_offer.status <> 'open' OR clock_timestamp() >= v_offer.ends_at THEN
            RAISE EXCEPTION 'la commande ne peut plus être modifiée';
        END IF;
        PERFORM require_actor(OLD.buyer_user_id, 'modification de commande');
    END IF;

    IF OLD.pickup_code IS NOT NULL AND NEW.pickup_code IS DISTINCT FROM OLD.pickup_code THEN
        RAISE EXCEPTION 'un code de retrait attribué ne change pas';
    END IF;

    IF NEW.status = OLD.status THEN
        IF NEW.pickup_code IS DISTINCT FROM OLD.pickup_code THEN
            RAISE EXCEPTION 'le code de retrait s''attribue au passage à « prêt »';
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.status = 'reserved' AND NEW.status = 'cancelled' THEN
        IF v_offer.status NOT IN ('open', 'cancelled') THEN
            RAISE EXCEPTION 'après la clôture, une réservation ne s''annule plus';
        END IF;

    ELSIF OLD.status = 'reserved' AND NEW.status = 'ready' THEN
        IF v_offer.status <> 'closed' THEN
            RAISE EXCEPTION 'la commande n''est prête qu''après la clôture de l''offre';
        END IF;

    ELSIF OLD.status = 'ready' AND NEW.status = 'paid' THEN
        IF NOT EXISTS (SELECT FROM order_payments
                       WHERE order_id = OLD.id AND status = 'confirmed') THEN
            RAISE EXCEPTION 'aucun paiement confirmé par le commerçant';
        END IF;

    ELSIF OLD.status = 'paid' AND NEW.status = 'picked_up' THEN
        IF NOT EXISTS (SELECT FROM pickups WHERE order_id = OLD.id) THEN
            RAISE EXCEPTION 'aucun retrait constaté par le commerçant';
        END IF;

    ELSIF OLD.status = 'ready' AND NEW.status = 'expired' THEN
        IF clock_timestamp() < v_offer.closed_at + make_interval(hours => v_offer.pickup_window_hours) THEN
            RAISE EXCEPTION 'le délai de retrait n''est pas encore écoulé';
        END IF;

    ELSE
        RAISE EXCEPTION 'transition de commande interdite : % → %', OLD.status, NEW.status;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orders_guard
    BEFORE INSERT OR UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION orders_guard();

-- ---------- Paiements ----------
CREATE FUNCTION order_payments_guard() RETURNS TRIGGER AS $$
DECLARE
    v_order  orders%ROWTYPE;
    v_price  BIGINT;
    v_member merchant_members%ROWTYPE;
BEGIN
    SELECT * INTO v_order FROM orders WHERE id = NEW.order_id FOR SHARE;

    IF TG_OP = 'INSERT' THEN
        IF v_order.status <> 'ready' THEN
            RAISE EXCEPTION 'un paiement ne s''enregistre que sur une commande prête';
        END IF;
        SELECT final_unit_price_minor INTO v_price FROM offers WHERE id = v_order.offer_id;
        IF NEW.amount_minor <> v_order.quantity * v_price THEN
            RAISE EXCEPTION 'montant attendu : % (quantité × prix final)', v_order.quantity * v_price;
        END IF;
        IF NEW.declared_by_user_id IS NOT NULL THEN
            IF NEW.declared_by_user_id <> v_order.buyer_user_id THEN
                RAISE EXCEPTION 'seul l''acheteur déclare le paiement de sa commande';
            END IF;
            -- Ne s'applique pas quand la boutique confirme plus tard une déclaration existante
            PERFORM require_actor(NEW.declared_by_user_id, 'déclaration de paiement');
        END IF;
    ELSE
        IF OLD.status <> 'declared' THEN
            RAISE EXCEPTION 'un paiement confirmé ou rejeté ne se modifie plus';
        END IF;
        IF ROW(NEW.order_id, NEW.merchant_id, NEW.amount_minor, NEW.method, NEW.tx_reference,
               NEW.declared_by_user_id, NEW.created_at)
           IS DISTINCT FROM
           ROW(OLD.order_id, OLD.merchant_id, OLD.amount_minor, OLD.method, OLD.tx_reference,
               OLD.declared_by_user_id, OLD.created_at)
        THEN
            RAISE EXCEPTION 'seule la décision du commerçant peut s''ajouter à un paiement déclaré';
        END IF;
    END IF;

    NEW.confirmed_at := NULL;
    IF NEW.status IN ('confirmed', 'rejected') THEN
        SELECT * INTO v_member FROM merchant_members WHERE id = NEW.confirmed_by_member_id;
        IF v_member.id IS NULL OR v_member.removed_at IS NOT NULL THEN
            RAISE EXCEPTION 'seul un membre actif de la boutique confirme ou rejette un paiement';
        END IF;
        PERFORM require_actor(v_member.user_id, 'décision sur un paiement');
        IF NEW.status = 'confirmed' THEN
            NEW.confirmed_at := clock_timestamp();
        END IF;
    ELSIF NEW.confirmed_by_member_id IS NOT NULL THEN
        RAISE EXCEPTION 'un paiement seulement déclaré n''a pas de confirmateur';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_payments_guard
    BEFORE INSERT OR UPDATE ON order_payments
    FOR EACH ROW EXECUTE FUNCTION order_payments_guard();

-- ---------- Retraits ----------
CREATE FUNCTION pickups_guard() RETURNS TRIGGER AS $$
DECLARE
    v_member merchant_members%ROWTYPE;
BEGIN
    PERFORM 1 FROM orders WHERE id = NEW.order_id AND status = 'paid' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'le retrait ne se constate que sur une commande payée';
    END IF;
    SELECT * INTO v_member FROM merchant_members WHERE id = NEW.confirmed_by_member_id;
    IF v_member.id IS NULL OR v_member.removed_at IS NOT NULL THEN
        RAISE EXCEPTION 'seul un membre actif de la boutique constate un retrait';
    END IF;
    PERFORM require_actor(v_member.user_id, 'retrait');
    NEW.picked_up_at := clock_timestamp();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pickups_guard
    BEFORE INSERT ON pickups
    FOR EACH ROW EXECUTE FUNCTION pickups_guard();

-- ============================================================
-- Compteurs calculés (jamais saisis, jamais incrémentés)
-- ============================================================

-- Avancement d'une offre : seules les commandes non annulées comptent.
CREATE VIEW offer_progress AS
SELECT o.id AS offer_id,
       q.units AS confirmed_units,
       t.threshold_units,
       greatest(t.threshold_units - q.units, 0) AS missing_units,
       (SELECT unit_price_minor FROM offer_tiers
        WHERE offer_id = o.id AND min_quantity <= q.units
        ORDER BY min_quantity DESC LIMIT 1) AS reached_unit_price_minor
FROM offers o
CROSS JOIN LATERAL (
    SELECT coalesce(sum(quantity), 0)::bigint AS units
    FROM orders WHERE offer_id = o.id AND status <> 'cancelled'
) q
CROSS JOIN LATERAL (
    SELECT min(min_quantity) AS threshold_units FROM offer_tiers WHERE offer_id = o.id
) t;

-- « Achats proposés » d'un groupe : combien de ses membres ont une commande sur l'offre.
-- La commande reste unique ; elle est seulement visible depuis chaque groupe de l'acheteur.
-- Volontairement aucun détail par membre : pas de liste des « sans réponse ».
CREATE VIEW group_offer_proposals AS
SELECT s.group_id,
       s.offer_id,
       s.id AS share_id,
       s.shared_by_user_id AS proposed_by_user_id,
       s.created_at AS proposed_at,
       (SELECT count(*) FROM memberships m
        JOIN orders ord ON ord.buyer_user_id = m.user_id
                       AND ord.offer_id = s.offer_id AND ord.status <> 'cancelled'
        WHERE m.group_id = s.group_id AND m.status = 'active') AS confirmed_members
FROM shares s
WHERE s.channel = 'group';

-- ============================================================
-- Journal : une chaîne par offre
-- ============================================================
-- Nouvelle chaîne 'offer:<uuid>' : l'offre, ses paliers, partages, commandes, paiements et
-- retraits. Les autres chaînes ne changent pas (017) : 'group:<uuid>', et hors groupe
-- 'user:<uuid>', 'staff' ou 'system' selon l'auteur (boutiques et zones y vont).
-- Le format du hash ne change pas (mchango-v1).
ALTER TABLE audit_log
    ADD COLUMN offer_id UUID REFERENCES offers(id),
    ADD CONSTRAINT audit_log_one_scope CHECK (group_id IS NULL OR offer_id IS NULL);

CREATE INDEX idx_audit_offer ON audit_log (offer_id, seq);

-- Reprend 017 à l'identique, avec l'offre en plus
CREATE OR REPLACE FUNCTION audit_log_set_hash() RETURNS TRIGGER
SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_seq  BIGINT;
    v_hash CHAR(64);
BEGIN
    NEW.chain_id := coalesce('offer:' || NEW.offer_id::text,
                             audit_chain_for(NEW.group_id, NEW.actor_type, NEW.actor_id));

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

-- Journalisation des tables d'achat. Fonction à part : audit_business_change() (001) reste
-- celle de la tontine, inchangée.
CREATE FUNCTION audit_purchase_change() RETURNS TRIGGER
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
    ELSIF TG_TABLE_NAME IN ('offer_tiers', 'shares', 'orders') THEN
        -- Un partage vers un groupe reste dans la chaîne de l'offre, pas dans celle du groupe
        v_offer_id := (v_row ->> 'offer_id')::uuid;
    ELSIF TG_TABLE_NAME IN ('order_payments', 'pickups') THEN
        SELECT offer_id INTO v_offer_id
        FROM orders WHERE id = (v_row ->> 'order_id')::uuid;
    END IF;
    -- pickup_zones, merchants, merchant_members : chaîne de l'auteur (offer_id NULL)

    INSERT INTO audit_log (group_id, offer_id, actor_type, actor_id, device_id, action, payload)
    VALUES (NULL, v_offer_id, v_actor_type, v_actor_id::uuid, v_device_id::uuid,
            TG_TABLE_NAME || '.' || lower(TG_OP), v_row::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_pickup_zones     AFTER INSERT OR UPDATE ON pickup_zones
    FOR EACH ROW EXECUTE FUNCTION audit_purchase_change();
CREATE TRIGGER trg_audit_merchants        AFTER INSERT OR UPDATE ON merchants
    FOR EACH ROW EXECUTE FUNCTION audit_purchase_change();
CREATE TRIGGER trg_audit_merchant_members AFTER INSERT OR UPDATE ON merchant_members
    FOR EACH ROW EXECUTE FUNCTION audit_purchase_change();
CREATE TRIGGER trg_audit_offers           AFTER INSERT OR UPDATE ON offers
    FOR EACH ROW EXECUTE FUNCTION audit_purchase_change();
CREATE TRIGGER trg_audit_offer_tiers      AFTER INSERT OR UPDATE ON offer_tiers
    FOR EACH ROW EXECUTE FUNCTION audit_purchase_change();
CREATE TRIGGER trg_audit_shares           AFTER INSERT OR UPDATE ON shares
    FOR EACH ROW EXECUTE FUNCTION audit_purchase_change();
CREATE TRIGGER trg_audit_orders           AFTER INSERT OR UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION audit_purchase_change();
CREATE TRIGGER trg_audit_order_payments   AFTER INSERT OR UPDATE ON order_payments
    FOR EACH ROW EXECUTE FUNCTION audit_purchase_change();
CREATE TRIGGER trg_audit_pickups          AFTER INSERT OR UPDATE ON pickups
    FOR EACH ROW EXECUTE FUNCTION audit_purchase_change();

-- Pas de suppression physique
CREATE TRIGGER trg_no_delete_pickup_zones     BEFORE DELETE ON pickup_zones
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_no_delete_merchants        BEFORE DELETE ON merchants
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_no_delete_merchant_members BEFORE DELETE ON merchant_members
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_no_delete_offers           BEFORE DELETE ON offers
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_no_delete_offer_tiers      BEFORE DELETE ON offer_tiers
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_no_delete_shares           BEFORE DELETE ON shares
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_no_delete_orders           BEFORE DELETE ON orders
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_no_delete_order_payments   BEFORE DELETE ON order_payments
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();
CREATE TRIGGER trg_no_delete_pickups          BEFORE DELETE ON pickups
    FOR EACH ROW EXECUTE FUNCTION forbid_delete();

-- ---------- Index utiles ----------
CREATE INDEX idx_merchants_zone       ON merchants (zone_id) WHERE status = 'active';
CREATE INDEX idx_merchant_members_usr ON merchant_members (user_id) WHERE removed_at IS NULL;
CREATE INDEX idx_offers_open          ON offers (merchant_id, ends_at) WHERE status = 'open';
CREATE INDEX idx_orders_offer         ON orders (offer_id, status);
CREATE INDEX idx_orders_buyer         ON orders (buyer_user_id, created_at);
CREATE INDEX idx_orders_merchant      ON orders (merchant_id, status);
CREATE INDEX idx_shares_group         ON shares (group_id) WHERE group_id IS NOT NULL;
CREATE INDEX idx_shares_parent        ON shares (parent_share_id);
CREATE INDEX idx_order_payments_order ON order_payments (order_id);

-- ---------- Droits du rôle applicatif ----------
-- Toujours pas de DELETE. Un partage et un retrait ne se modifient pas : pas d'UPDATE.
GRANT SELECT, INSERT, UPDATE ON
    pickup_zones, merchants, merchant_members, offers, offer_tiers, orders, order_payments
TO mchango_app;
GRANT SELECT, INSERT ON shares, pickups TO mchango_app;
GRANT SELECT ON offer_progress, group_offer_proposals TO mchango_app;
