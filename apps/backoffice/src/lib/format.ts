export function amount(minor: number, currency: string): string {
  const group = (n: number) => n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  return currency === "USD"
    ? `${group(Math.floor(minor / 100))},${String(minor % 100).padStart(2, "0")} $`
    : `${group(minor)} FC`;
}

export function dateTime(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Intl.DateTimeFormat("fr-FR", {
    timeZone: "Africa/Lubumbashi",
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(iso));
}

export function date(isoDate: string | null | undefined): string {
  if (!isoDate) return "—";
  const [y, m, d] = isoDate.slice(0, 10).split("-");
  return `${d}/${m}/${y}`;
}

export const roleLabels: Record<string, string> = {
  super_admin: "Super administrateur",
  support: "Support",
  compliance: "Conformité",
  finance: "Finance",
  read_only: "Lecture seule",
};

export const groupStatus: Record<string, string> = {
  draft: "En préparation",
  active: "En cours",
  suspended: "Suspendue",
  closed: "Terminée",
};

/** Couleur de la pastille de statut d'une tontine. */
export const statusBadge = (s: string) =>
  s === "active" ? "badge-ok" : s === "suspended" ? "badge-danger" : s === "draft" ? "badge-warn" : "";

export const cycleStatus: Record<string, string> = {
  upcoming: "À venir",
  open: "En cours",
  completed: "Terminé",
  cancelled: "Annulé",
};

export const disputeStatus: Record<string, string> = {
  open: "Ouvert",
  resolved_confirmed: "Clos : confirmé",
  resolved_rejected: "Clos : rejeté",
  withdrawn: "Retiré",
};

export const memberRole: Record<string, string> = {
  president: "Président(e)",
  treasurer: "Trésorier(e)",
  member: "Membre",
};

export const methodLabels: Record<string, string> = {
  mpesa: "M-Pesa",
  airtel: "Airtel Money",
  orange: "Orange Money",
  cash: "Espèces",
  other: "Autre",
};

export const frequencyLabels: Record<string, string> = {
  daily: "Quotidienne",
  weekly: "Hebdomadaire",
  monthly: "Mensuelle",
};
