import { generateKeyPairSync, sign } from 'node:crypto';
import { challengeMessage, parseEd25519PublicKey, verifyDeviceSignature } from './device-key.js';

function newDeviceKey() {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  const raw = publicKey.export({ format: 'der', type: 'spki' }).subarray(12);
  return { publicKey: raw.toString('base64'), privateKey };
}

describe("clé de l'appareil", () => {
  const device = newDeviceKey();
  const message = challengeMessage('6f1c2a5e-0000-4000-8000-000000000001', 'nonce-abc');
  const signature = sign(null, Buffer.from(message), device.privateKey).toString('base64');

  it('accepte une clé brute de 32 octets en base64', () => {
    expect(parseEd25519PublicKey(device.publicKey)).not.toBeNull();
  });

  it.each([
    ['', 'vide'],
    [Buffer.alloc(31).toString('base64'), '31 octets'],
    [Buffer.alloc(33).toString('base64'), '33 octets'],
    ['pas du base64 !', 'texte'],
  ])('refuse %s (%s)', (key) => {
    expect(parseEd25519PublicKey(key)).toBeNull();
  });

  it('format du message signé', () => {
    expect(message).toBe('mchango-auth-v1\n6f1c2a5e-0000-4000-8000-000000000001\nnonce-abc');
  });

  it('vérifie une signature correcte', () => {
    expect(verifyDeviceSignature(device.publicKey, message, signature)).toBe(true);
  });

  it('refuse un autre message, une autre clé, une signature tronquée', () => {
    expect(verifyDeviceSignature(device.publicKey, message + 'x', signature)).toBe(false);
    expect(verifyDeviceSignature(newDeviceKey().publicKey, message, signature)).toBe(false);
    expect(verifyDeviceSignature(device.publicKey, message, signature.slice(0, 40))).toBe(false);
  });
});
