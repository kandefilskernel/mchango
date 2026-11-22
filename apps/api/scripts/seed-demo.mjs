// Données de DÉMONSTRATION pour la base de développement locale (jamais en production).
// Crée des mamans, une tontine en cours avec des paiements, une tontine en préparation, un objectif,
// une boutique avec une offre d'achat groupé. Sert à regarder et à tester les écrans de l'app.
//
//   node scripts/seed-demo.mjs <url de l'API> <journal de l'API> <conteneur postgres>
//   ex. node scripts/seed-demo.mjs http://localhost:3000 /tmp/api.log mchango-dev-pg
//
// L'API doit tourner avec SMS_DRIVER=console : les codes SMS sont lus dans son journal.
// Comptes de test (numéros fictifs, réservés aux tests) — PIN commun : 482915
//   Maman Neema   +243990000001  présidente de « Likelemba ya Bamama »
//   Maman Furaha  +243990000002
//   Maman Zawadi  +243990000003
//   Papa Jean     +243990000004  employé de la boutique « Boutique Mama Kito »
import { execFileSync } from 'node:child_process';
import { generateKeyPairSync, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';

const [API = 'http://localhost:3000', LOG, PG = 'mchango-dev-pg'] = process.argv.slice(2);
if (!LOG) throw new Error('Donnez le chemin du journal de l\'API (les codes SMS y sont écrits).');
const PIN = '482915';

async function call(method, path, body, token) {
  const res = await fetch(API + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status} ${text}`);
  return data;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function lastCode(phone) {
  for (let i = 0; i < 20; i++) {
    const lines = readFileSync(LOG, 'utf8').split('\n').filter((l) => l.includes(`→ ${phone} :`) && /code est \d{6}/.test(l));
    const m = lines.at(-1)?.match(/code est (\d{6})/);
    if (m) return m[1];
    await sleep(250);
  }
  throw new Error(`Pas de code SMS pour ${phone} dans ${LOG}`);
}

/** Compte prêt à l'emploi : inscrit s'il n'existe pas, sinon relié à une nouvelle clé d'appareil. */
async function account(phone, fullName) {
  const { publicKey } = generateKeyPairSync('ed25519');
  const devicePublicKey = publicKey.export({ format: 'der', type: 'spki' }).subarray(12).toString('base64');
  const before = readFileSync(LOG, 'utf8').length;
  await call('POST', '/auth/otp/request', { phone });
  let code;
  for (let i = 0; i < 20 && !code; i++) {
    const fresh = readFileSync(LOG, 'utf8').slice(before);
    code = fresh.match(new RegExp(`→ \\${phone} : .*?code est (\\d{6})`))?.[1];
    if (!code) await sleep(250);
  }
  code ??= await lastCode(phone);
  const { otpToken, accountExists } = await call('POST', '/auth/otp/verify', { phone, code });
  const session = accountExists
    ? await call('POST', '/auth/devices', { otpToken, pin: PIN, devicePublicKey })
    : await call('POST', '/auth/register', { otpToken, fullName, pin: PIN, devicePublicKey, language: 'fr' });
  return { ...session, token: session.accessToken, fullName };
}

function sql(statement) {
  return execFileSync('docker', ['exec', '-i', PG, 'psql', '-U', 'postgres', '-d', 'mchango', '-tAq', '-v', 'ON_ERROR_STOP=1'], {
    input: `SET mchango.actor_type = 'system';\n${statement}`,
    encoding: 'utf8',
  }).trim();
}

const inDays = (d) => new Date(Date.now() + d * 86_400_000).toISOString().slice(0, 10);

const neema = await account('+243990000001', 'Maman Neema');
const furaha = await account('+243990000002', 'Maman Furaha');
const zawadi = await account('+243990000003', 'Maman Zawadi');
const jean = await account('+243990000004', 'Papa Jean');
console.log('comptes prêts');

// Tontine en cours : 4 membres, 20 000 FC par semaine
const g = await call('POST', '/groups', {
  name: 'Likelemba ya Bamama', currency: 'CDF', contributionAmountMinor: 20000, frequency: 'weekly',
  startDate: inDays(0), maxMembers: 10,
}, neema.token);
const { code } = await call('POST', `/groups/${g.id}/invitations`, {}, neema.token);
for (const m of [furaha, zawadi, jean]) await call('POST', '/groups/join', { code, acceptRules: true }, m.token);
const detail = await call('GET', `/groups/${g.id}`, undefined, neema.token);
const idOf = (m) => detail.members.find((x) => x.userId === m.userId).membershipId;
await call('PUT', `/groups/${g.id}/turn-order`, { membershipIds: [neema, furaha, zawadi, jean].map(idOf) }, neema.token);
const { terms } = await call('GET', `/groups/${g.id}`, undefined, neema.token);
for (const m of [neema, furaha, zawadi, jean]) await call('POST', `/groups/${g.id}/sign`, { termsHash: terms.hash }, m.token);
await call('POST', `/groups/${g.id}/start`, undefined, neema.token);
console.log('tontine démarrée');

// Tour 1 : Neema reçoit. Furaha a payé et c'est confirmé ; Zawadi a déclaré ; Jean pas encore.
const pay = (m, ref) => call('POST', `/groups/${g.id}/cycles/1/contributions`, {
  method: 'mpesa', txReference: ref, amountMinor: 20000, offlineId: randomUUID(),
}, m.token);
const furahaPaid = await pay(furaha, `MP${Date.now()}A1`);
await call('POST', `/contributions/${furahaPaid.id}/decisions`, {
  decision: 'confirm', riskAcknowledged: true, receivedTxReference: furahaPaid.txReference,
}, neema.token);
await pay(zawadi, `MP${Date.now()}B2`);
await call('PUT', `/groups/${g.id}/goal`, {
  kind: 'school', label: 'Minerval ya bana', targetAmountMinor: 60000, sharedWithGroup: true,
}, neema.token);
console.log('paiements et objectif');

// Tontine en préparation (Neema seule pour l'instant)
await call('POST', '/groups', {
  name: 'Tontine ya zando', currency: 'CDF', contributionAmountMinor: 5000, frequency: 'daily',
  startDate: inDays(3), maxMembers: 15,
}, neema.token);

// Boutique et offre d'achat groupé
const zoneId = sql(`INSERT INTO pickup_zones (city, commune) VALUES ('Lubumbashi', 'Kenya')
  ON CONFLICT (city, commune) DO UPDATE SET is_active = true RETURNING id;`).split('\n').at(-1);
const merchantId = sql(`INSERT INTO merchants (name, zone_id, address, phone, status)
  VALUES ('Boutique Mama Kito', '${zoneId}', 'Avenue Kasaï 12, marché Kenya', '+243990000099', 'active') RETURNING id;`).split('\n').at(-1);
sql(`INSERT INTO merchant_members (merchant_id, user_id, role) VALUES ('${merchantId}', '${jean.userId}', 'owner');`);
const offer = await call('POST', `/merchants/${merchantId}/offers`, {
  title: 'Farine de maïs', unitLabel: 'sac de 25 kg', currency: 'CDF', regularPriceMinor: 45000,
  endsAt: new Date(Date.now() + 5 * 86_400_000).toISOString(), pickupWindowHours: 72,
  tiers: [{ minQuantity: 1, unitPriceMinor: 42000 }, { minQuantity: 10, unitPriceMinor: 38000 }, { minQuantity: 25, unitPriceMinor: 35000 }],
}, jean.token);
await call('POST', `/merchants/${merchantId}/offers/${offer.id}/publish`, undefined, jean.token);
await call('POST', `/offers/${offer.id}/orders`, { quantity: 2, pickupName: 'Maman Neema', offlineId: randomUUID() }, neema.token);
await call('POST', `/offers/${offer.id}/orders`, { quantity: 3, pickupName: 'Maman Furaha', offlineId: randomUUID() }, furaha.token);
await call('POST', `/offers/${offer.id}/shares`, { channel: 'group', groupId: g.id }, neema.token);
console.log('boutique et offre publiées');
console.log('OK');
