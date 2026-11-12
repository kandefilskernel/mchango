import Link from "next/link";
import { Pager, pageFrom } from "@/components/pager";
import { api } from "@/lib/api";
import { amount, dateTime, frequencyLabels, groupCategory, groupStatus, statusBadge } from "@/lib/format";

interface GroupRow {
  id: string;
  name: string;
  category: string;
  status: string;
  currency: string;
  contributionAmountMinor: number;
  frequency: string;
  createdAt: string;
  members: number;
  president: string | null;
  openDisputes: number;
}

export default async function GroupsPage({ searchParams }: PageProps<"/groups">) {
  const sp = await searchParams;
  const q = String(sp.q ?? "");
  const status = String(sp.status ?? "");
  const category = String(sp.category ?? "");
  const page = pageFrom(sp.page);
  const groups = await api<GroupRow[]>(
    `/admin/groups?q=${encodeURIComponent(q)}&status=${encodeURIComponent(status)}&category=${encodeURIComponent(category)}&page=${page}`,
  );
  return (
    <>
      <div className="page-head">
        <div>
          <h1>Tontines</h1>
          <div className="muted">Les plus récentes d&apos;abord, 50 par page</div>
        </div>
        <form className="form-inline" method="get">
          <input name="q" defaultValue={q} placeholder="Nom de la tontine" aria-label="Rechercher" />
          <select name="status" defaultValue={status} aria-label="Statut">
            <option value="">Tous les statuts</option>
            {Object.entries(groupStatus).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
          <select name="category" defaultValue={category} aria-label="Catégorie">
            <option value="">Toutes les catégories</option>
            {Object.entries(groupCategory).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
          <button className="btn btn-primary">Filtrer</button>
        </form>
      </div>
      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Tontine</th>
              <th>Catégorie</th>
              <th>Président(e)</th>
              <th>Cotisation</th>
              <th>Membres</th>
              <th>Créée le</th>
              <th>Statut</th>
            </tr>
          </thead>
          <tbody>
            {groups.length === 0 && (
              <tr>
                <td colSpan={7} className="muted">
                  Aucune tontine ne correspond à ces filtres.
                </td>
              </tr>
            )}
            {groups.map((g) => (
              <tr key={g.id}>
                <td>
                  <Link href={`/groups/${g.id}`}>{g.name}</Link>
                  {g.openDisputes > 0 && (
                    <>
                      {" "}
                      <span className="badge badge-danger">{g.openDisputes} litige(s)</span>
                    </>
                  )}
                </td>
                <td>{groupCategory[g.category] ?? g.category}</td>
                <td>{g.president ?? "—"}</td>
                <td>
                  {amount(g.contributionAmountMinor, g.currency)} · {frequencyLabels[g.frequency] ?? g.frequency}
                </td>
                <td>{g.members}</td>
                <td>{dateTime(g.createdAt)}</td>
                <td>
                  <span className={`badge ${statusBadge(g.status)}`}>{groupStatus[g.status] ?? g.status}</span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pager path="/groups" params={{ q, status, category }} page={page} count={groups.length} />
    </>
  );
}
