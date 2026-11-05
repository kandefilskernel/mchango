// Icônes du menu (traits simples, 20 px, couleur du texte).
const paths: Record<string, string> = {
  dashboard: "M3 13h8V3H3v10Zm0 8h8v-6H3v6Zm10 0h8V11h-8v10Zm0-18v6h8V3h-8Z",
  inbox: "M4 4h16v10h-5l-1.5 3h-3L9 14H4V4Zm0 10v6h16v-6",
  users: "M16 11a4 4 0 1 0-8 0 4 4 0 0 0 8 0ZM4 21a8 8 0 0 1 16 0",
  groups: "M12 3a3 3 0 1 1 0 6 3 3 0 0 1 0-6ZM5 9a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5Zm14 0a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5ZM7 21a5 5 0 0 1 10 0M1 20a4 4 0 0 1 5-3.9M23 20a4 4 0 0 0-5-3.9",
  disputes: "M12 3 2 20h20L12 3Zm0 6v5m0 3v.5",
  search: "M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14Zm9 16-4.2-4.2",
  receipt: "M6 3h12v18l-3-2-3 2-3-2-3 2V3Zm3 5h6M9 12h6",
  check: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm-4 9 3 3 5-6",
  clock: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm0 4v5l3 2",
  lock: "M6 11h12v10H6V11Zm2 0V8a4 4 0 0 1 8 0v3",
  sms: "M4 5h16v11H9l-5 4V5Zm4 5h8",
  pause: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm-2 6v6m4-6v6",
  note: "M5 4h14v12l-4 4H5V4Zm10 16v-4h4M8 9h8M8 13h5",
  calendar: "M4 6h16v15H4V6Zm0 5h16M8 3v5m8-5v5",
  ai: "M12 3l1.8 4.7 4.7 1.8-4.7 1.8L12 16l-1.8-4.7-4.7-1.8 4.7-1.8L12 3Zm7 11 .9 2.1 2.1.9-2.1.9L19 20l-.9-2.1-2.1-.9 2.1-.9L19 14Z",
  alert:"M12 3a6 6 0 0 0-6 6c0 6-2.5 8-2.5 8h17S18 15 18 9a6 6 0 0 0-6-6Zm-2 18a2.2 2.2 0 0 0 4 0",
  audit:"M12 2 4 5v6c0 5 3.5 9.3 8 11 4.5-1.7 8-6 8-11V5l-8-3Zm-3.5 10 2.5 2.5 4.5-5",
  team: "M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm14 10v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8",
  account: "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm7.4-3a7.4 7.4 0 0 0-.1-1.2l2-1.6-2-3.4-2.4 1a7 7 0 0 0-2-1.2L14.5 3h-5l-.4 2.6a7 7 0 0 0-2 1.2l-2.4-1-2 3.4 2 1.6a7.4 7.4 0 0 0 0 2.4l-2 1.6 2 3.4 2.4-1a7 7 0 0 0 2 1.2l.4 2.6h5l.4-2.6a7 7 0 0 0 2-1.2l2.4 1 2-3.4-2-1.6c.1-.4.1-.8.1-1.2Z",
};

export type IconName = keyof typeof paths;

export function Icon({ name, size = 20 }: { name: IconName; size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d={paths[name]} />
    </svg>
  );
}
