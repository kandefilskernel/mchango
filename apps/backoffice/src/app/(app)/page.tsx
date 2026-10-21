import Link from "next/link";
import { api } from "@/lib/api";

interface Dashboard {
  users_total: number;
  users_new_7d: number;
  users_blocked: number;
  groups_draft: number;
  groups_active: number;
  groups_suspended: number;
  groups_closed: number;
  contributions_declared_today: number;
  contributions_confirmed_today: number;
  disputes_open: number;
  pin_resets_pending: number;
  notifications_failed_7d: number;
  late_payments_30d: number;
  late_rate_30d: number | null;
}

function Stat({ label, value, tone }: { label: string; value: string | number; tone?: "warn" | "alert" }) {
  return (
    <div className={`stat ${tone ?? ""}`}>
      <div className="value">{value}</div>
      <div className="label">{label}</div>
    </div>
  );
}

export default async function DashboardPage() {
  const d = await api<Dashboard>("/admin/dashboard");
  return (
    <>
      <div className="page-head">
        <div>
          <h1>Tableau de bord</h1>
          <div className="muted">Chiffres en direct, heure de Lubumbashi</div>
        </div>
      </div>

      <h2>Aujourd&apos;hui</h2>
      <div className="grid">
        <Stat label="Paiements déclarés" value={d.contributions_declared_today} />
        <Stat label="Paiements confirmés" value={d.contributions_confirmed_today} />
        <Stat label="Litiges ouverts" value={d.disputes_open} tone={d.disputes_open > 0 ? "alert" : undefined} />
        <Stat label="« PIN oublié » en attente" value={d.pin_resets_pending} tone={d.pin_resets_pending > 0 ? "warn" : undefined} />
      </div>

      <h2>Tontines</h2>
      <div className="grid">
        <Stat label="En cours" value={d.groups_active} />
        <Stat label="En préparation" value={d.groups_draft} />
        <Stat label="Suspendues" value={d.groups_suspended} tone={d.groups_suspended > 0 ? "warn" : undefined} />
        <Stat label="Terminées" value={d.groups_closed} />
      </div>

      <h2>Retards (30 derniers jours)</h2>
      <div className="grid">
        <Stat
          label="Taux de paiements en retard"
          value={d.late_rate_30d === null ? "—" : `${d.late_rate_30d} %`}
          tone={d.late_rate_30d !== null && d.late_rate_30d > 20 ? "alert" : undefined}
        />
        <Stat label="Paiements en retard" value={d.late_payments_30d} />
      </div>

      <h2>Utilisateurs</h2>
      <div className="grid">
        <Stat label="Inscrits" value={d.users_total} />
        <Stat label="Nouveaux (7 jours)" value={d.users_new_7d} />
        <Stat label="Comptes bloqués" value={d.users_blocked} />
        <Stat
          label="SMS en échec (7 jours)"
          value={d.notifications_failed_7d}
          tone={d.notifications_failed_7d > 0 ? "warn" : undefined}
        />
      </div>

      <p className="muted">
        Pas de revenus affichés : la facturation est prévue en V2. Mchango ne détient, ne transfère et ne garantit aucun
        fonds. <Link href="/disputes">Voir les litiges ouverts →</Link>
      </p>
    </>
  );
}
