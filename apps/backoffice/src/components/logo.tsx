/** Logo Mchango : cinq membres autour d'une pièce (même dessin que l'app mobile). */
export function Logo({ size = 36 }: { size?: number }) {
  const members = Array.from({ length: 5 }, (_, i) => {
    const a = -Math.PI / 2 + (i * 2 * Math.PI) / 5;
    return { x: 64 + 38 * Math.cos(a), y: 64 + 38 * Math.sin(a), x2: 64 + 22 * Math.cos(a), y2: 64 + 22 * Math.sin(a) };
  });
  return (
    <svg viewBox="0 0 128 128" width={size} height={size} aria-hidden="true">
      <circle cx="64" cy="64" r="64" fill="#0F5E43" />
      {members.map((m, i) => (
        <g key={i}>
          <circle cx={m.x} cy={m.y} r="11" fill="#fff" />
          <path d={`M ${m.x} ${m.y} L ${m.x2} ${m.y2}`} stroke="#fff" strokeWidth="5" strokeLinecap="round" opacity="0.6" />
        </g>
      ))}
      <circle cx="64" cy="64" r="17" fill="#F2B33D" stroke="#C98A1B" strokeWidth="3" />
      <circle cx="64" cy="64" r="8" fill="none" stroke="#C98A1B" strokeWidth="2.5" />
    </svg>
  );
}
