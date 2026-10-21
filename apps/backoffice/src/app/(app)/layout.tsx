import Link from "next/link";
import { logout } from "../actions";
import { Logo } from "@/components/logo";
import { CAN, currentStaff } from "@/lib/api";
import { roleLabels } from "@/lib/format";

export default async function AppLayout({ children }: LayoutProps<"/">) {
  // Sans session valide, api() renvoie vers /login
  const staff = await currentStaff();
  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <Logo size={36} />
          <div>
            Mchango
            <small>Back-office</small>
          </div>
        </div>
        <nav className="nav">
          <Link href="/">Tableau de bord</Link>
          <Link href="/users">Utilisateurs</Link>
          <Link href="/groups">Tontines</Link>
          <Link href="/disputes">Litiges</Link>
          <Link href="/audit">Audit</Link>
          {CAN.manageStaff.includes(staff.role) && <Link href="/staff">Équipe</Link>}
          <Link href="/account">Mon compte</Link>
        </nav>
        <div className="sidebar-footer">
          <div style={{ fontWeight: 700 }}>{staff.fullName}</div>
          <div style={{ opacity: 0.85 }}>{roleLabels[staff.role]}</div>
          <form action={logout}>
            <button className="btn btn-ghost">Se déconnecter</button>
          </form>
        </div>
      </aside>
      <main className="main">{children}</main>
    </div>
  );
}
