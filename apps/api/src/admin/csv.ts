/**
 * CSV lisible par Excel (séparateur « ; », BOM UTF-8 pour les accents).
 * Les cellules qui commencent par = + - @ sont neutralisées : un nom de tontine
 * comme « =HYPERLINK(...) » ne doit pas devenir une formule chez la personne qui ouvre le fichier.
 */
export function toCsv(header: string[], rows: (string | number | null | undefined)[][]): string {
  const cell = (v: string | number | null | undefined) => {
    let s = v === null || v === undefined ? '' : String(v);
    if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
    return /[;"\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return '﻿' + [header, ...rows].map((r) => r.map(cell).join(';')).join('\r\n') + '\r\n';
}
