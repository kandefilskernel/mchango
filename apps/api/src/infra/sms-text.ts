// Encodage des SMS : en GSM-7 (alphabet standard), un SMS fait 160 caractères. Un seul caractère
// hors de cet alphabet (ê, ç, « », ’…) fait passer TOUT le message en UCS-2 : 70 caractères par SMS,
// donc deux ou trois SMS facturés au lieu d'un.

const GSM7_BASIC =
  '@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?¡' +
  'ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà';
// Caractères de l'extension : ils comptent double
const GSM7_EXTENDED = '^{}\\[~]|€\f';

const REPLACEMENTS: Record<string, string> = {
  '«': '"', '»': '"', '“': '"', '”': '"', '’': "'", '‘': "'", '–': '-', '—': '-', '…': '...',
  ' ': ' ', ' ': ' ', 'â': 'a', 'ê': 'e', 'î': 'i', 'ô': 'o', 'û': 'u', 'ë': 'e',
  'ï': 'i', 'ç': 'c', 'Â': 'A', 'Ê': 'E', 'Î': 'I', 'Ô': 'O', 'Û': 'U', 'È': 'E', 'À': 'A',
  'Ù': 'U', 'Ë': 'E', 'Ï': 'I', 'œ': 'oe', 'Œ': 'OE',
};

// Découpage par point de code (pas par graphème) : c'est l'unité que regarde l'encodage SMS.
const chars = (text: string) => Array.from(text);

export function isGsm7(text: string): boolean {
  return chars(text).every((c) => GSM7_BASIC.includes(c) || GSM7_EXTENDED.includes(c));
}

/** Remplace les caractères courants hors GSM-7 (accents rares, guillemets, espaces insécables). */
export function toGsm7(text: string): string {
  // Guillemets français : « Kwetu » → "Kwetu" (sans les espaces intérieures)
  const quoted = text.replace(/«[\s  ]*/g, '"').replace(/[\s  ]*»/g, '"');
  return chars(quoted).map((c) => (GSM7_BASIC.includes(c) || GSM7_EXTENDED.includes(c) ? c : (REPLACEMENTS[c] ?? '?'))).join('');
}

/** Nombre de SMS facturés pour ce texte. */
export function smsSegments(text: string): number {
  if (isGsm7(text)) {
    const units = chars(text).reduce((n, c) => n + (GSM7_EXTENDED.includes(c) ? 2 : 1), 0);
    return units <= 160 ? 1 : Math.ceil(units / 153);
  }
  // UCS-2 compte des unités UTF-16 : un emoji en vaut deux (text.length les compte ainsi)
  const units = text.length;
  return units <= 70 ? 1 : Math.ceil(units / 67);
}
