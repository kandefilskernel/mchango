import { logout } from "../actions";
import { Logo } from "@/components/logo";
import { Nav, type NavItem } from "@/components/nav";
import { CAN, currentStaff, inbox } from "@/lib/api";
import { roleLabels } from "@/lib/format";

export default async function AppLayout({ children }: LayoutProps<"/">) {
  // Sans session valide, api() renvoie vers /login
  const [staff, todo] = await Promise.all([currentStaff(), inbox()]);
  const items: NavItem[] = [
    { href: "/", label: "Tableau de bord", icon: "dashboard" },
    { href: "/support", label: "À traiter", icon: "inbox", badge: todo.counts.total },
    { href: "/users", label: "Utilisateurs", icon: "users" },
    { href: "/groups", label: "Tontines", icon: "groups" },
    { href: "/disputes", label: "Litiges", icon: "disputes", badge: todo.counts.disputesOpen },
    { href: "/audit", label: "Audit", icon: "audit" },
    ...(CAN.manageStaff.includes(staff.role) ? [{ href: "/staff", label: "Équipe", icon: "team" } as NavItem] : []),
    { href: "/account", label: "Mon compte", icon: "account" },
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
          <Logo size={38} />
          <div>
            Mchango
            <small>Back-office</small>
          </div>
        </div>
        <Nav items={items} />
        <div className="sidebar-footer">
          <div className="who">
            <span className="avatar">{initials}</span>
            <div>
              <div style={{ fontWeight: 700 }}>{staff.fullName}</div>
              <div style={{ opacity: 0.8, fontSize: 12 }}>{roleLabels[staff.role]}</div>
            </div>
          </div>
          <form action={logout}>
            <button className="btn btn-ghost">Se déconnecter</button>
          </form>
        </div>
      </aside>
      <main className="main">{children}</main>
    </div>
  );
}
