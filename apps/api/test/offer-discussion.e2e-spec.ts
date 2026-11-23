import { randomInt, randomUUID } from 'node:crypto';
import pg from 'pg';
import { TEST_DB } from './global-setup.js';
import { TestApi, type TestSession } from './helpers.js';

// Achats groupés : voir la marchandise (photos) et en discuter sous l'offre.

const ADMIN_URL = (
  process.env.TEST_ADMIN_DATABASE_URL ?? 'postgres://postgres:postgres_dev@127.0.0.1:5432/postgres'
).replace(/\/[^/]*$/, `/${TEST_DB}`);

/** Plus petit JPEG valide (1 × 1 pixel). */
const TINY_JPEG = Buffer.from(
  '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=',
  'base64',
);

describe('Achats groupés : photos et discussion (e2e)', () => {
  let api: TestApi;
  let admin: pg.Client;
  const http = () => api.http();
  const auth = (s: TestSession) => ({ Authorization: `Bearer ${s.accessToken}` });

  let owner: TestSession;
  let buyer: TestSession;
  let stranger: TestSession;
  const zone = randomUUID();
  const shop = randomUUID();
  let offerId: string;

  beforeAll(async () => {
    api = await TestApi.start();
    owner = (await api.signUp(undefined, undefined, 'Papa Nyota Kabeya')).session;
    buyer = (await api.signUp(undefined, undefined, 'Maman Neema Kabila Mwamba')).session;
    stranger = (await api.signUp(undefined, undefined, 'Joël')).session;
    admin = new pg.Client({ connectionString: ADMIN_URL });
    await admin.connect();
    await admin.query(`SELECT set_config('mchango.actor_type', 'system', false)`);
    await admin.query(`INSERT INTO pickup_zones (id, city, commune) VALUES ($1, 'Lubumbashi', $2)`, [zone, `Kenya ${zone.slice(0, 8)}`]);
    await admin.query(
      `INSERT INTO merchants (id, name, zone_id, address, phone, status) VALUES ($1, 'Boutique Mama Kito', $2, 'Marché Kenya', $3, 'active')`,
      [shop, zone, `+2438${randomInt(10_000_000, 99_999_999)}`],
    );
    await admin.query(`INSERT INTO merchant_members (merchant_id, user_id, role) VALUES ($1, $2, 'owner')`, [shop, owner.userId]);

    const created = await http()
      .post(`/merchants/${shop}/offers`)
      .set(auth(owner))
      .send({
        title: 'Farine de maïs',
        unitLabel: 'sac de 25 kg',
        regularPriceMinor: 45000,
        endsAt: new Date(Date.now() + 3 * 86_400_000).toISOString(),
        pickupWindowHours: 72,
        tiers: [{ minQuantity: 1, unitPriceMinor: 42000 }],
      })
      .expect(201);
    offerId = created.body.id;
  });

  afterAll(async () => {
    await admin.end();
    await api.close();
  });

  it('la boutique ajoute des photos avant de publier ; tout le monde les voit, sans compte', async () => {
    // Seule la boutique de l'offre
    await http().post(`/merchants/${shop}/offers/${offerId}/photos`).set(auth(stranger)).set('Content-Type', 'image/jpeg').send(TINY_JPEG).expect(403);
    // Un faux JPEG est refusé : on regarde les octets, pas l'en-tête
    await http()
      .post(`/merchants/${shop}/offers/${offerId}/photos`)
      .set(auth(owner))
      .set('Content-Type', 'image/jpeg')
      .send(Buffer.from('pas une image du tout'))
      .expect(400);

    const added = await http()
      .post(`/merchants/${shop}/offers/${offerId}/photos`)
      .set(auth(owner))
      .set('Content-Type', 'image/jpeg')
      .send(TINY_JPEG)
      .expect(201);
    expect(added.body).toMatchObject({ position: 1, url: `/offers/${offerId}/photos/1` });

    await http().post(`/merchants/${shop}/offers/${offerId}/publish`).set(auth(owner)).expect(200);

    // Publiée : plus de nouvelle photo
    await http().post(`/merchants/${shop}/offers/${offerId}/photos`).set(auth(owner)).set('Content-Type', 'image/jpeg').send(TINY_JPEG).expect(409);

    // L'offre donne l'adresse de ses photos ; la photo se lit sans compte, telle qu'envoyée
    const offer = await http().get(`/offers/${offerId}`).expect(200);
    expect(offer.body.photos).toEqual([`/offers/${offerId}/photos/1`]);
    const photo = await http().get(`/offers/${offerId}/photos/1`).buffer(true).parse((res, cb) => {
      const chunks: Buffer[] = [];
      res.on('data', (c: Buffer) => chunks.push(c));
      res.on('end', () => cb(null, Buffer.concat(chunks)));
    }).expect(200);
    expect(photo.headers['content-type']).toBe('image/jpeg');
    expect(Buffer.compare(photo.body as Buffer, TINY_JPEG)).toBe(0);
    await http().get(`/offers/${offerId}/photos/2`).expect(404);
  });

  it('les membres discutent sous l’offre ; la boutique répond en son nom', async () => {
    await http().get(`/offers/${offerId}/messages`).expect(401);
    await http().post(`/offers/${offerId}/messages`).set(auth(buyer)).send({ body: '   ' }).expect(400);
    await http().post(`/offers/${offerId}/messages`).set(auth(buyer)).send({ body: 'Le sac est de quelle marque ?' }).expect(201);
    const reply = await http().post(`/offers/${offerId}/messages`).set(auth(owner)).send({ body: 'Minoterie du Katanga, fraîche.' }).expect(201);
    expect(reply.body.fromMerchant).toBe(true);

    const seenByBuyer = (await http().get(`/offers/${offerId}/messages`).set(auth(buyer)).expect(200)).body;
    expect(seenByBuyer).toHaveLength(2);
    expect(seenByBuyer[0]).toMatchObject({ authorName: 'Maman Neema', fromMerchant: false, mine: true, body: 'Le sac est de quelle marque ?' });
    expect(seenByBuyer[1]).toMatchObject({ authorName: 'Boutique Mama Kito', fromMerchant: true, mine: false });

    // Inscrit dans la chaîne de l'offre
    const { rows } = await api.db.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM audit_log WHERE chain_id = $1 AND action IN ('offer_messages.insert', 'offer_photos.insert')`,
      [`offer:${offerId}`],
    );
    expect(rows[0].n).toBe(3);

    // Pas plus de 10 messages en 10 minutes : déjà 1 envoyé, 9 de plus, le 11e est refusé
    for (let i = 0; i < 9; i++) {
      await http().post(`/offers/${offerId}/messages`).set(auth(buyer)).send({ body: `Question ${i}` }).expect(201);
    }
    await http().post(`/offers/${offerId}/messages`).set(auth(buyer)).send({ body: 'Encore une' }).expect(429);
  });

  it('pas de discussion sur une offre encore en brouillon', async () => {
    const draft = await http()
      .post(`/merchants/${shop}/offers`)
      .set(auth(owner))
      .send({
        title: 'Huile',
        unitLabel: 'bidon de 5 L',
        regularPriceMinor: 30000,
        endsAt: new Date(Date.now() + 3 * 86_400_000).toISOString(),
        pickupWindowHours: 72,
        tiers: [{ minQuantity: 1, unitPriceMinor: 28000 }],
      })
      .expect(201);
    await http().post(`/offers/${draft.body.id}/messages`).set(auth(stranger)).send({ body: 'Bonjour' }).expect(404);
  });
});
