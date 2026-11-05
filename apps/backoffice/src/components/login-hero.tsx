/**
 * Illustration de la page de connexion : six membres, téléphone en main, autour de la mise commune.
 * Les pièces tournent d'un membre à l'autre (la tontine), chaque paiement est confirmé et inscrit
 * au journal. Mchango ne touche pas l'argent : la pièce centrale est la mise des membres, pas un compte.
 */
const CX = 260;
const CY = 232;
const R = 150;

const people = [
  { skin: "#8D5524", cloth: "#D35400", print: "wax1", wrap: "#F2B33D" },
  { skin: "#5C3A21", cloth: "#2E86C1", print: null, wrap: null },
  { skin: "#A0662F", cloth: "#C0392B", print: "wax2", wrap: "#16A085" },
  { skin: "#6B3E26", cloth: "#F2B33D", print: null, wrap: null },
  { skin: "#C68642", cloth: "#8E44AD", print: "wax1", wrap: "#D35400" },
  { skin: "#7B4A2A", cloth: "#16A085", print: null, wrap: null },
];

function Person({ x, y, skin, cloth, print, wrap }: { x: number; y: number } & (typeof people)[number]) {
  return (
    <g>
      <ellipse cx={x} cy={y + 40} rx="26" ry="5" fill="#000" opacity="0.18" />
      <path d={`M ${x - 24} ${y + 40} Q ${x - 25} ${y + 12} ${x} ${y + 11} Q ${x + 25} ${y + 12} ${x + 24} ${y + 40} Z`} fill={cloth} />
      {print && (
        <path
          d={`M ${x - 24} ${y + 40} Q ${x - 25} ${y + 12} ${x} ${y + 11} Q ${x + 25} ${y + 12} ${x + 24} ${y + 40} Z`}
          fill={`url(#${print})`}
        />
      )}
      <rect x={x - 4} y={y + 4} width="8" height="9" rx="3" fill={skin} />
      <circle cx={x} cy={y - 4} r="13" fill={skin} />
      {wrap ? (
        <path d={`M ${x - 14} ${y - 6} Q ${x - 16} ${y - 26} ${x} ${y - 24} Q ${x + 18} ${y - 26} ${x + 14} ${y - 6} Q ${x} ${y - 13} ${x - 14} ${y - 6} Z`} fill={wrap} />
      ) : (
        <path d={`M ${x - 13} ${y - 7} Q ${x - 12} ${y - 19} ${x} ${y - 18} Q ${x + 12} ${y - 19} ${x + 13} ${y - 7} Q ${x} ${y - 12} ${x - 13} ${y - 7} Z`} fill="#1F2933" />
      )}
      {/* téléphone : l'écran s'allume quand un paiement est confirmé */}
      <rect x={x + 8} y={y + 16} width="11" height="18" rx="2.5" fill="#1F2933" />
      <rect className="screen" x={x + 9.5} y={y + 18} width="8" height="12" rx="1.2" fill="#7CF0B4" />
      <path d={`M ${x + 6} ${y + 30} Q ${x + 10} ${y + 34} ${x + 15} ${y + 31}`} stroke={skin} strokeWidth="4.5" fill="none" strokeLinecap="round" />
    </g>
  );
}

function Coin({ x, y, r = 9 }: { x: number; y: number; r?: number }) {
  return (
    <g>
      <circle cx={x} cy={y} r={r} fill="#F2B33D" stroke="#C98A1B" strokeWidth="2" />
      <circle cx={x} cy={y} r={r * 0.45} fill="none" stroke="#C98A1B" strokeWidth="1.5" />
    </g>
  );
}

export function LoginHero() {
  const seats = people.map((p, i) => {
    const a = -Math.PI / 2 + (i * 2 * Math.PI) / people.length;
    return { ...p, x: CX + R * Math.cos(a), y: CY + R * Math.sin(a) - 14, a };
  });
  return (
    <svg className="hero-art" viewBox="0 0 520 470" role="img" aria-labelledby="hero-title">
      <title id="hero-title">Six membres d&apos;une tontine, téléphone en main, autour de leur mise commune</title>
      <defs>
        <radialGradient id="glow" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="#F2B33D" stopOpacity="0.55" />
          <stop offset="60%" stopColor="#F2B33D" stopOpacity="0.08" />
          <stop offset="100%" stopColor="#F2B33D" stopOpacity="0" />
        </radialGradient>
        <pattern id="wax1" width="10" height="10" patternUnits="userSpaceOnUse">
          <circle cx="5" cy="5" r="2.2" fill="#fff" opacity="0.35" />
        </pattern>
        <pattern id="wax2" width="12" height="12" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
          <rect width="12" height="4" fill="#fff" opacity="0.25" />
        </pattern>
        <filter id="lift" x="-20%" y="-20%" width="140%" height="160%">
          <feDropShadow dx="0" dy="8" stdDeviation="9" floodColor="#062e20" floodOpacity="0.35" />
        </filter>
      </defs>

      {/* halo et anneau de la tontine */}
      <circle cx={CX} cy={CY} r="120" fill="url(#glow)" />
      <circle cx={CX} cy={CY} r={R} fill="none" stroke="#fff" strokeOpacity="0.18" strokeWidth="2" />
      {seats.map((s, i) => (
        <line
          key={`l${i}`}
          className="flow"
          x1={CX + (R - 30) * Math.cos(s.a)}
          y1={CY + (R - 30) * Math.sin(s.a)}
          x2={CX + 58 * Math.cos(s.a)}
          y2={CY + 58 * Math.sin(s.a)}
          stroke="#F2B33D"
          strokeOpacity="0.7"
          strokeWidth="2.5"
          strokeDasharray="2 9"
          strokeLinecap="round"
        />
      ))}

      {/* pièces qui passent de main en main */}
      <g className="orbit">
        {[0, 1, 2].map((k) => {
          const a = -Math.PI / 2 + Math.PI / 6 + (k * 2 * Math.PI) / 3;
          return <Coin key={k} x={CX + R * Math.cos(a)} y={CY + R * Math.sin(a)} r={8} />;
        })}
      </g>

      {/* la mise commune */}
      <g className="pot">
        <circle cx={CX} cy={CY} r="52" fill="#0B4A35" stroke="#F2B33D" strokeOpacity="0.5" strokeWidth="2" />
        <Coin x={CX - 16} y={CY + 14} r={17} />
        <Coin x={CX + 16} y={CY + 14} r={17} />
        <Coin x={CX} y={CY - 8} r={19} />
      </g>

      {seats.map((s, i) => (
        <Person key={i} {...s} />
      ))}

      {/* reçu de paiement confirmé */}
      <g className="float-a" filter="url(#lift)">
        <rect x="338" y="24" width="168" height="66" rx="14" fill="#fff" />
        <circle cx="362" cy="57" r="13" fill="#E3F1EA" />
        <path d="M 355 57 l 5 5 l 9 -10" stroke="#0F5E43" strokeWidth="3" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        <text x="383" y="51" fontSize="12.5" fontWeight="800" fill="#1F2933">Paiement confirmé</text>
        <text x="383" y="70" fontSize="11.5" fill="#5B6770">M-Pesa · 20 000 FC</text>
      </g>

      {/* journal chaîné */}
      <g className="float-b" filter="url(#lift)">
        <rect x="14" y="392" width="196" height="58" rx="14" fill="#fff" />
        {[0, 1, 2].map((k) => (
          <g key={k}>
            <rect x={30 + k * 22} y="410" width="16" height="22" rx="4" fill={k === 2 ? "#0F5E43" : "#E3F1EA"} />
            {k < 2 && <line x1={46 + k * 22} y1="421" x2={52 + k * 22} y2="421" stroke="#2E8B57" strokeWidth="2.5" />}
          </g>
        ))}
        <text x="104" y="417" fontSize="12.5" fontWeight="800" fill="#1F2933">Journal intact</text>
        <text x="104" y="435" fontSize="11" fill="#5B6770">chaque ligne scellée</text>
      </g>
    </svg>
  );
}
