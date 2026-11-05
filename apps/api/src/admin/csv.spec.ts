import { toCsv } from './csv.js';

describe('toCsv', () => {
  it('BOM, séparateur « ; », guillemets échappés', () => {
    expect(toCsv(['a', 'b'], [['x;y', 'il a dit "oui"'], [1, null]])).toBe(
      '﻿a;b\r\n"x;y";"il a dit ""oui"""\r\n1;\r\n',
    );
  });

  it('neutralise les formules', () => {
    expect(toCsv(['n'], [['=HYPERLINK("x")'], ['+243'], ['-5'], ['@SUM']])).toBe(
      '﻿n\r\n"\'=HYPERLINK(""x"")"\r\n\'+243\r\n\'-5\r\n\'@SUM\r\n',
    );
  });
});
