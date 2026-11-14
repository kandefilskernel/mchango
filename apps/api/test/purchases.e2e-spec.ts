import { randomInt, randomUUID } from 'node:crypto';
import pg from 'pg';
import { PurchaseLifecycleService } from '../src/purchases/lifecycle.service.js';
import { TEST_DB } from './global-setup.js';
import { TestApi, type TestSession } from './helpers.js';

// Parcours complet d'un achat groupé. Les boutiques et les zones n'ont pas encore d'écran
// d'administration : elles sont posées directement en base, comme le ferait l'équipe.

const ADMIN_URL = (
  process.env.TEST_ADMIN_DATABASE_URL ?? 'postgres://postgres:postgres_dev@127.0.0.1:5432/postgres'
).replace(/\/[^/]*$/, `/${TEST_DB}`);

const OFFER_SECONDS = 6;

describe('Achats groupés (e2e)', () => {
  let api: TestApi;
  let admin: pg.Client;
  let lifecycle: PurchaseLifecycleService;
  const http = () => api.http();
  const auth = (s: TestSession) => ({ Authorization: `Bearer ${s.accessToken}` });

  let owner: TestSession;
  let otherOwner: TestSession;
  let grace: TestSession;
  let aline: TestSession;
  let joel: TestSession;
  const zone = randomUUID();
  const shop = randomUUID();
  const otherShop = randomUUID();
  const group = randomUUID();

  let riceOffer: string;
  let oilOffer: string;
  let endsAt: number;
  let graceOrder: string;
  let alineOrder: string;
  let joelOrder: string;
  let shareToken: string;

  const offerBody = (title: string, threshold: number) => ({
    title,
    unitLabel: 'sac de 25 kg',
    regularPriceMinor: 60000,
    endsAt: new Date(endsAt).toISOString(),
    pickupWindowHours: 72,
    tiers: [
      { minQuantity: threshold, unitPriceMinor: 57000 },
      { minQuantity: threshold + 3, unitPriceMinor: 54000 },
    ],
  });

  beforeAll(async () => {
    api = await TestApi.start();
    lifecycle = api.app.get(PurchaseLifecycleService);
    owner = (await api.signUp(undefined, undefined, 'Papa Nyota')).session;
    otherOwner = (await api.signUp(undefined, undefined, 'Mama Kasongo')).session;
    grace = (await api.signUp(undefined, undefined, 'Grâce M.')).session;
    aline = (await api.signUp(undefined, undefined, 'Aline Nzambe')).session;
    joel = (await api.signUp(undefined, undefined, 'Joël')).session;

    admin = new pg.Client({ connectionString: ADMIN_URL });
    await admin.connect();
    await admin.query(`SELECT set_config('mchango.actor_type', 'system', false)`);
    await admin.query(`INSERT INTO pickup_zones (id, city, commune) VALUES ($1, 'Kinshasa', $2)`, [
      zone,
      `Matete ${zone.slice(0, 8)}`,
    ]);
    for (const [id, name, user] of [
      [shop, 'Boutique Nyota', owner.userId],
      [otherShop, 'Chez Kasongo', otherOwner.userId],
    ]) {
      await admin.query(
        `INSERT INTO merchants (id, name, zone_id, address, phone, status)
         VALUES ($1, $2, $3, 'Av. Kinzazi 12', $4, 'active')`,
        [id, name, zone, `+2438${randomInt(10_000_000, 99_999_999)}`],
      );
      await admin.query(`INSERT INTO merchant_members (merchant_id, user_id, role) VALUES ($1, $2, 'owner')`, [
        id,
        user,
      ]);
    }
    await admin.query(
      `INSERT INTO groups (id, name, contribution_amount_minor, frequency, start_date, created_by)
       VALUES ($1, 'Les Solidaires', 50000, 'monthly', current_date + 30, $2)`,
      [group, grace.userId],
    );
    for (const user of [grace, aline]) {
      await admin.query(`INSERT INTO memberships (group_id, user_id, status) VALUES ($1, $2, 'active')`, [
        group,
        user.userId,
      ]);
    }
  });

  afterAll(async () => {
    await admin.end();
    await api.close();
  });

  it('le commerçant crée et publie ses offres, pas un tiers', async () => {
    endsAt = Date.now() + OFFER_SECONDS * 1000;

    await http().post(`/merchants/${shop}/offers`).send(offerBody('Riz', 5)).expect(401);
    await http().post(`/merchants/${shop}/offers`).set(auth(otherOwner)).send(offerBody('Riz', 5)).expect(403);
    await http()
      .post(`/merchants/${shop}/offers`)
      .set(auth(owner))
      .send({ ...offerBody('Riz', 5), finalUnitPriceMinor: 1 })
      .expect(400);

    const rice = await http().post(`/merchants/${shop}/offers`).set(auth(owner)).send(offerBody('Riz', 5)).expect(201);
    riceOffer = rice.body.id;
    expect(rice.body).toMatchObject({ status: 'draft', regularPriceMinor: 60000 });
    expect(rice.body.tiers).toEqual([
      { minQuantity: 5, unitPriceMinor: 57000 },
      { minQuantity: 8, unitPriceMinor: 54000 },
    ]);

    // Un brouillon n'existe pas pour le public
    await http().get(`/offers/${riceOffer}`).expect(404);

    await http().post(`/merchants/${shop}/offers/${riceOffer}/publish`).set(auth(otherOwner)).expect(403);
    await http().post(`/merchants/${shop}/offers/${riceOffer}/publish`).set(auth(owner)).expect(200);

    const oil = await http().post(`/merchants/${shop}/offers`).set(auth(owner)).send(offerBody('Huile', 10)).expect(201);
    oilOffer = oil.body.id;
    await http().post(`/merchants/${shop}/offers/${oilOffer}/publish`).set(auth(owner)).expect(200);

    const mine = await http().get('/me/merchants').set(auth(owner)).expect(200);
    expect(mine.body).toEqual([expect.objectContaining({ id: shop, role: 'owner', city: 'Kinshasa' })]);
  });

  it('les offres se consultent sans compte', async () => {
    const list = await http().get(`/offers?zoneId=${zone}`).expect(200);
    expect(list.body.map((o: { id: string }) => o.id).sort()).toEqual([riceOffer, oilOffer].sort());
    const detail = await http().get(`/offers/${riceOffer}`).expect(200);
    expect(detail.body).toMatchObject({
      merchantName: 'Boutique Nyota',
      confirmedUnits: 0,
      thresholdUnits: 5,
      missingUnits: 5,
      reachedUnitPriceMinor: null,
    });
    await http().get('/offers?zoneId=nimporte').expect(400);
    await http().get('/offers/nimporte').expect(400);
  });

  it('réserver demande un compte ; inviter ne change pas le compteur', async () => {
    const body = { quantity: 3, pickupName: 'Grâce M.', offlineId: randomUUID() };
    await http().post(`/offers/${riceOffer}/orders`).send(body).expect(401);

    const first = await http().post(`/offers/${riceOffer}/orders`).set(auth(grace)).send(body).expect(201);
    graceOrder = first.body.id;
    expect(first.body).toMatchObject({ status: 'reserved', pickupCode: null, indicativeTotalMinor: null });

    // Rejouer la même requête (réseau instable) ne crée pas de seconde commande
    const replay = await http().post(`/offers/${riceOffer}/orders`).set(auth(grace)).send(body).expect(201);
    expect(replay.body.id).toBe(graceOrder);

    await http()
      .post(`/offers/${riceOffer}/orders`)
      .set(auth(grace))
      .send({ ...body, offlineId: randomUUID() })
      .expect(409);

    await http().post(`/offers/${riceOffer}/shares`).set(auth(grace)).send({ channel: 'group', groupId: group }).expect(201);
    // Joël n'est pas membre du groupe
    await http().post(`/offers/${riceOffer}/shares`).set(auth(joel)).send({ channel: 'group', groupId: group }).expect(409);
    const share = await http().post(`/offers/${riceOffer}/shares`).set(auth(grace)).send({ channel: 'whatsapp' }).expect(201);
    shareToken = share.body.token;

    const resolved = await http().get(`/shares/${shareToken}`).expect(200);
    expect(resolved.body.offerId).toBe(riceOffer);
    await http().get('/shares/jeton-inconnu-jeton-inconnu').expect(404);

    const detail = await http().get(`/offers/${riceOffer}`).expect(200);
    expect(detail.body.confirmedUnits).toBe(3);
  });

  it('une commande compte une fois ; le groupe voit ses membres confirmés', async () => {
    const order = await http()
      .post(`/offers/${riceOffer}/orders`)
      .set(auth(aline))
      .send({ quantity: 1, pickupName: 'Aline Nzambe', offlineId: randomUUID(), shareToken })
      .expect(201);
    alineOrder = order.body.id;

    // Aline passe de 1 à 2 sacs ; Grâce ne peut pas toucher à la commande d'Aline
    await http().patch(`/orders/${alineOrder}`).set(auth(grace)).send({ quantity: 9 }).expect(404);
    await http().patch(`/orders/${alineOrder}`).set(auth(aline)).send({ quantity: 2 }).expect(200);

    const detail = await http().get(`/offers/${riceOffer}`).expect(200);
    expect(detail.body).toMatchObject({ confirmedUnits: 5, missingUnits: 0, reachedUnitPriceMinor: 57000 });
    // La fiche publique ne révèle aucun acheteur
    expect(JSON.stringify(detail.body)).not.toContain('Aline');

    const proposals = await http().get(`/groups/${group}/proposals`).set(auth(aline)).expect(200);
    expect(proposals.body).toEqual([
      expect.objectContaining({ offerId: riceOffer, confirmedMembers: 2, proposedByName: 'Grâce M.' }),
    ]);
    await http().get(`/groups/${group}/proposals`).set(auth(joel)).expect(403);

    const viaShare = await admin.query('SELECT via_share_id IS NOT NULL AS tracked FROM orders WHERE id = $1', [
      alineOrder,
    ]);
    expect(viaShare.rows[0].tracked).toBe(true);

    const oil = await http()
      .post(`/offers/${oilOffer}/orders`)
      .set(auth(joel))
      .send({ quantity: 1, pickupName: 'Joël', offlineId: randomUUID() })
      .expect(201);
    joelOrder = oil.body.id;
  });

  it('à la date de fin : clôture au palier atteint, ou annulation sous le seuil', async () => {
    // Avant l'échéance, rien ne bouge
    expect(await lifecycle.runOnce()).toMatchObject({ closed: 0, cancelled: 0 });

    await new Promise((resolve) => setTimeout(resolve, Math.max(0, endsAt - Date.now()) + 300));
    await http()
      .post(`/offers/${riceOffer}/orders`)
      .set(auth(joel))
      .send({ quantity: 1, pickupName: 'Joël', offlineId: randomUUID() })
      .expect(409);

    expect(await lifecycle.runOnce()).toMatchObject({ closed: 1, cancelled: 1 });

    const rice = await http().get(`/offers/${riceOffer}`).expect(200);
    expect(rice.body).toMatchObject({ status: 'closed', finalUnitPriceMinor: 57000 });
    const oil = await http().get(`/offers/${oilOffer}`).expect(200);
    expect(oil.body).toMatchObject({ status: 'cancelled', finalUnitPriceMinor: null });

    const mine = await http().get('/me/orders').set(auth(grace)).expect(200);
    expect(mine.body).toHaveLength(1);
    expect(mine.body[0]).toMatchObject({
      id: graceOrder,
      status: 'ready',
      amountDueMinor: 171000,
      paymentStatus: null,
    });
    expect(mine.body[0].pickupCode).toMatch(/^MC-\d{4}$/);

    const joels = await http().get('/me/orders').set(auth(joel)).expect(200);
    expect(joels.body[0]).toMatchObject({ id: joelOrder, status: 'cancelled' });

    // Après la clôture, on ne se retire plus
    await http().post(`/orders/${graceOrder}/cancel`).set(auth(grace)).expect(409);
  }, 20_000);

  it('seule la boutique encaisse et remet ; déclarer ne suffit pas', async () => {
    await http().get(`/merchants/${shop}/orders`).set(auth(otherOwner)).expect(403);
    const queue = await http().get(`/merchants/${shop}/orders`).set(auth(owner)).expect(200);
    expect(queue.body).toHaveLength(2);
    const code = (id: string) => queue.body.find((o: { id: string }) => o.id === id).pickupCode as string;

    // Grâce déclare avoir payé : la commande reste « prête »
    const declared = await http().post(`/orders/${graceOrder}/payments`).set(auth(grace)).send({ method: 'cash' }).expect(201);
    expect(declared.body).toMatchObject({ status: 'ready', paymentStatus: 'declared' });

    // Ni l'acheteuse, ni une autre boutique ne peuvent confirmer
    await http().post(`/merchants/${shop}/orders/${graceOrder}/confirm-payment`).set(auth(grace)).expect(403);
    await http().post(`/merchants/${otherShop}/orders/${graceOrder}/confirm-payment`).set(auth(otherOwner)).expect(404);

    // Pas de remise avant paiement
    await http()
      .post(`/merchants/${shop}/orders/${graceOrder}/confirm-pickup`)
      .set(auth(owner))
      .send({ pickupCode: code(graceOrder) })
      .expect(409);

    const paid = await http().post(`/merchants/${shop}/orders/${graceOrder}/confirm-payment`).set(auth(owner)).expect(200);
    expect(paid.body).toMatchObject({ status: 'paid', paymentStatus: 'confirmed' });

    await http()
      .post(`/merchants/${shop}/orders/${graceOrder}/confirm-pickup`)
      .set(auth(owner))
      .send({ pickupCode: 'MC-XXXX' })
      .expect(422);
    const picked = await http()
      .post(`/merchants/${shop}/orders/${graceOrder}/confirm-pickup`)
      .set(auth(owner))
      .send({ pickupCode: code(graceOrder) })
      .expect(200);
    expect(picked.body.status).toBe('picked_up');

    // Aline paie au comptoir par mobile money : la boutique saisit et confirme
    await http()
      .post(`/merchants/${shop}/orders/${alineOrder}/confirm-payment`)
      .set(auth(owner))
      .send({ method: 'mpesa' })
      .expect(400);
    await http()
      .post(`/merchants/${shop}/orders/${alineOrder}/confirm-payment`)
      .set(auth(owner))
      .send({ method: 'mpesa', txReference: `qt${randomInt(1e9)}` })
      .expect(200);
    await http()
      .post(`/merchants/${shop}/orders/${alineOrder}/confirm-pickup`)
      .set(auth(owner))
      .send({ pickupCode: code(alineOrder) })
      .expect(200);

    // Le code ne s'affiche plus une fois le produit remis
    const mine = await http().get('/me/orders').set(auth(grace)).expect(200);
    expect(mine.body[0]).toMatchObject({ status: 'picked_up', pickupCode: null });

    expect(await lifecycle.runOnce()).toMatchObject({ fulfilled: 1 });
    const rice = await http().get(`/offers/${riceOffer}`).expect(200);
    expect(rice.body.status).toBe('fulfilled');
  });

  it('chaque écriture est au journal de l’offre, avec son véritable auteur', async () => {
    const chain = `offer:${riceOffer}`;
    const verified = await admin.query('SELECT audit_verify_chain($1) AS first_invalid', [chain]);
    expect(verified.rows[0].first_invalid).toBeNull();

    const authors = await admin.query(
      `SELECT action, actor_type, actor_id FROM audit_log
       WHERE chain_id = $1 AND action IN ('orders.insert', 'pickups.insert', 'offers.update')
       ORDER BY seq`,
      [chain],
    );
    const by = (action: string) => authors.rows.filter((row) => row.action === action);
    expect(by('orders.insert').map((row) => row.actor_id)).toEqual([grace.userId, aline.userId]);
    expect(by('pickups.insert').every((row) => row.actor_id === owner.userId)).toBe(true);
    // publication par le commerçant, puis clôture et fin par le système
    expect(by('offers.update').map((row) => row.actor_type)).toEqual(['user', 'system', 'system']);

    const inGroup = await admin.query(
      `SELECT count(*)::int AS n FROM audit_log WHERE chain_id = $1 AND action LIKE 'shares.%'`,
      [`group:${group}`],
    );
    expect(inGroup.rows[0].n).toBe(0);
  });
});
