import Link from "next/link";
import { Icon, type IconName } from "@/components/icons";
import { api, CAN, currentStaff, inbox } from "@/lib/api";

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

type Tone = "warn" | "alert" | "info" | undefined;

function Stat({
  label,
  value,
  icon,
  tone,
  href,
}: {
  label: string;
  value: string | number;
  icon: IconName;
  tone?: Tone;
  /** Liste correspondante : la case devient un lien. */
  href?: string;
}) {
  const card = (
    <div className={`stat ${tone ?? ""}`}>
      <div className="stat-top">
        <span className="stat-icon">
          <Icon name={icon} size={18} />
        </span>
        <span className="label">{label}</span>
      </div>
      <div className="value">{value}</div>
    </div>
  );
  return href ? (
    <Link className="stat-link" href={href}>
      {card}
    </Link>
  ) : (
    card
  );
}

/** Orange dès qu'il y a quelque chose, rouge au-delà du seuil, neutre à zéro. */
function toneFor(n: number | null, alertAbove = Infinity): Tone {
  if (n === null || n <= 0) return undefined;
  return n > alertAbove ? "alert" : "warn";
}

function SectionTitle({ title, children }: { title: string; children?: React.ReactNode }) {
  return (
    <div className="section-title">
      <h2>{title}</h2>
      {children}
    </div>
  );
}

export default async function DashboardPage() {
  const [d, todo, staff] = await Promise.all([api<Dashboard>("/admin/dashboard"), inbox(), currentStaff()]);
  const c = todo.counts;
  const cases: { label: string; n: number; href: string; icon: IconName }[] = [
    { label: "Suivis en cours", n: c.followUps, href: "/support#suivis", icon: "note" },
    { label: "« PIN oublié » en attente", n: c.pinResetsPending, href: "/support#pin-oublie", icon: "lock" },
    { label: "PIN bloqués", n: c.pinLocked, href: "/support#pin-bloques", icon: "lock" },
    { label: "Litiges ouverts", n: c.disputesOpen, href: "/disputes", icon: "disputes" },
    { label: "SMS en échec", n: c.smsFailed, href: "/support#sms", icon: "sms" },
    { label: "Tontines suspendues", n: c.groupsSuspended, href: "/groups?status=suspended", icon: "pause" },
  ];
  const open = cases.filter((x) => x.n > 0);
  const confirmRate =
    d.contributions_declared_today === 0
      ? null
      : Math.round((d.contributions_confirmed_today / d.contributions_declared_today) * 100);
  const firstName = staff.fullName.split(/\s+/)[0];
  return (
    <>
      <section className="welcome">
        <div>
          <h1>Bonjour {firstName}</h1>
          <p>
            {c.total === 0
              ? "Rien à traiter : tout le monde avance."
              : `${c.total} cas attendent l'équipe aujourd'hui.`}
          </p>
        </div>
        <span className="pill">
          {d.groups_active} tontines en cours · {d.users_total} membres
        </span>
      </section>

      <section className="card todo">
        <div className="todo-head">
          <h2>À traiter</h2>
          <Link className="btn btn-secondary" href="/support">
            Tout voir
          </Link>
        </div>
        {open.length === 0 ? (
          <p className="todo-clear">Aucun membre bloqué, aucun litige ouvert, aucun SMS en échec.</p>
        ) : (
          <ul>
            {open.map((x) => (
              <li key={x.label}>
                <Link href={x.href}>
                  <span className="stat-icon">
                    <Icon name={x.icon} size={16} />
                  </span>
                  {x.label}
                  <span className="count">{x.n}</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>

      <SectionTitle title="Aujourd'hui" />
      <div className="grid">
        <Stat label="Paiements déclarés" value={d.contributions_declared_today} icon="receipt" />
        <Stat
          label={confirmRate === null ? "Paiements confirmés" : `Paiements confirmés (${confirmRate} %)`}
          value={d.contributions_confirmed_today}
          icon="check"
        />
      </div>

      <SectionTitle title="Retards (30 derniers jours)">
        {CAN.exportData.includes(staff.role) && (
          <a className="btn btn-secondary" href="/export?kind=late" download>
            Liste des retards (CSV)
          </a>
        )}
      </SectionTitle>
      <div className="grid">
        <Stat
          label="Taux de paiements en retard"
          value={d.late_rate_30d === null ? "—" : `${d.late_rate_30d} %`}
          icon="clock"
          tone={toneFor(d.late_rate_30d, 20)}
        />
        <Stat label="Paiements en retard" value={d.late_payments_30d} icon="clock" tone={toneFor(d.late_payments_30d)} />
      </div>

      <SectionTitle title="Tontines" />
      <div className="grid">
        <Stat label="En cours" value={d.groups_active} icon="groups" href="/groups?status=active" />
        <Stat label="En préparation" value={d.groups_draft} icon="calendar" tone="info" href="/groups?status=draft" />
        <Stat
          label="Suspendues"
          value={d.groups_suspended}
          icon="pause"
          tone={toneFor(d.groups_suspended)}
          href="/groups?status=suspended"
        />
        <Stat label="Terminées" value={d.groups_closed} icon="check" tone="info" href="/groups?status=closed" />
      </div>

      <SectionTitle title="Membres" />
      <div className="grid">
        <Stat label="Inscrits" value={d.users_total} icon="users" href="/users" />
        <Stat label="Nouveaux (7 jours)" value={d.users_new_7d} icon="users" tone="info" />
        <Stat label="Comptes bloqués" value={d.users_blocked} icon="lock" tone={toneFor(d.users_blocked)} />
        <Stat
          label="SMS en échec (7 jours)"
          value={d.notifications_failed_7d}
          icon="sms"
          tone={toneFor(d.notifications_failed_7d)}
          href="/support#sms"
        />
      </div>

      <p className="muted footnote">
        Pas de revenus affichés : la facturation est prévue en V2. Mchango ne détient, ne transfère et ne garantit aucun
        fonds.
      </p>
    </>
  );
}
