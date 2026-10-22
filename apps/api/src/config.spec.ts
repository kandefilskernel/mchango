import { loadConfig } from './config.js';

const base = {
  DATABASE_URL: 'postgres://x',
  REDIS_URL: 'redis://x',
  JWT_SECRET: 'x'.repeat(32),
  OTP_PEPPER: 'y'.repeat(32),
  STAFF_JWT_SECRET: 'z'.repeat(32),
  STAFF_SECRET_KEY: Buffer.alloc(32, 1).toString('base64'),
};

describe('configuration', () => {
  it('le contournement 2FA de développement est désactivé par défaut', () => {
    expect(loadConfig({ ...base, NODE_ENV: 'development' }).STAFF_2FA_DEV_BYPASS).toBe('0');
  });

  it('il est accepté en développement', () => {
    expect(loadConfig({ ...base, NODE_ENV: 'development', STAFF_2FA_DEV_BYPASS: '1' }).STAFF_2FA_DEV_BYPASS).toBe('1');
  });

  it("l'API refuse de démarrer en production avec le contournement 2FA ou les SMS en console", () => {
    expect(() =>
      loadConfig({ ...base, NODE_ENV: 'production', SMS_DRIVER: 'console', STAFF_2FA_DEV_BYPASS: '1' }),
    ).toThrow();
    expect(() => loadConfig({ ...base, NODE_ENV: 'production', STAFF_2FA_DEV_BYPASS: '1' })).toThrow(/2FA|SMS/);
  });

  it('durée de session du back-office : 8 h par défaut, 24 h au plus, 12 h au plus en production', () => {
    expect(loadConfig({ ...base, NODE_ENV: 'development' }).STAFF_SESSION_HOURS).toBe(8);
    expect(loadConfig({ ...base, NODE_ENV: 'development', STAFF_SESSION_HOURS: '24' }).STAFF_SESSION_HOURS).toBe(24);
    expect(() => loadConfig({ ...base, NODE_ENV: 'development', STAFF_SESSION_HOURS: '48' })).toThrow();
    expect(() => loadConfig({ ...base, NODE_ENV: 'production', STAFF_SESSION_HOURS: '24' })).toThrow(/STAFF_SESSION_HOURS/);
  });

  it('refuse une clé de chiffrement qui ne fait pas 32 octets', () => {
    expect(() => loadConfig({ ...base, STAFF_SECRET_KEY: 'trop-court' })).toThrow(/STAFF_SECRET_KEY/);
  });
});
