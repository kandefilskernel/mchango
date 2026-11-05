import { logout } from "../actions";
import { Icon } from "@/components/icons";
import { Logo } from "@/components/logo";
import { Nav, type NavSection } from "@/components/nav";
import { CAN, currentStaff, inbox } from "@/lib/api";
import { roleLabels } from "@/lib/format";
import { PUBLISHER } from "@/lib/brand";

const today = () =>
  new Intl.DateTimeFormat("fr-FR", { timeZone: "Africa/Lubumbashi", weekday: "long", day: "numeric", month: "long" }).format(
    new Date(),
  );

export default async function AppLayout({ children }: LayoutProps<"/">) {
  // Sans session valide, api() renvoie vers /login
  const [staff, todo] = await Promise.all([currentStaff(), inbox()]);
  const sections: NavSection[] = [
    {
      title: "Suivi",
      items: [
        { href: "/", label: "Tableau de bord", icon: "dashboard" },
        { href: "/support", label: "À traiter", icon: "inbox", badge: todo.counts.total },
        { href: "/disputes", label: "Litiges", icon: "disputes", badge: todo.counts.disputesOpen },
        { href: "/alerts", label: "Alertes", icon: "alert" },
        { href: "/ai", label: "Analyse IA", icon: "ai" },
      ],
    },
    {
      title: "Données",
      items: [
        { href: "/users", label: "Utilisateurs", icon: "users" },
        { href: "/groups", label: "Tontines", icon: "groups" },
        { href: "/audit", label: "Audit", icon: "audit" },
      ],
    },
    {
      title: "Administration",
      items: [
        ...(CAN.manageStaff.includes(staff.role) ? [{ href: "/staff", label: "Équipe", icon: "team" as const }] : []),
        { href: "/account", label: "Mon compte", icon: "account" },
      ],
    },
  ];
  const initials = staff.fullName
    .split(/\s+/)
    .map((w) => w[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();
  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <Logo size={36} />
          <div>
            Mchango
            <small>Back-office</small>
            <span className="by">par {PUBLISHER}</span>
          </div>
        </div>
        <Nav sections={sections} />
        <div className="sidebar-footer">
          <div className="who">
            <span className="avatar">{initials}</span>
            <div>
              <div style={{ fontWeight: 700 }}>{staff.fullName}</div>
              <div style={{ opacity: 0.7, fontSize: 12 }}>{roleLabels[staff.role]}</div>
            </div>
          </div>
          <form action={logout}>
            <button className="btn btn-ghost">Se déconnecter</button>
          </form>
        </div>
      </aside>
      <div className="content">
        <header className="topbar">
          <form className="search" action="/users" method="get" role="search">
            <Icon name="search" size={18} />
            <input name="q" placeholder="Rechercher un membre (nom ou numéro)…" aria-label="Rechercher un membre" />
          </form>
          <div className="topbar-meta">
            <Icon name="calendar" size={17} />
            <span style={{ textTransform: "capitalize" }}>{today()} · Lubumbashi</span>
            <span className="avatar" title={staff.fullName}>
              {initials}
            </span>
          </div>
        </header>
        <main className="main">
          {children}
          <footer className="app-footer">
            Mchango · par <strong>{PUBLISHER}</strong> · Mchango ne détient, ne transfère et ne garantit aucun fonds.
          </footer>
        </main>
      </div>
    </div>
  );
}
