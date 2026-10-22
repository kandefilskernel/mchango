import Link from "next/link";
import { api } from "@/lib/api";
import { amount, dateTime, frequencyLabels, groupStatus, statusBadge } from "@/lib/format";

interface GroupRow {
  id: string;
  name: string;
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
  const groups = await api<GroupRow[]>(`/admin/groups?q=${encodeURIComponent(q)}&status=${encodeURIComponent(status)}`);
  return (
    <>
      <div className="page-head">
        <div>
          <h1>Tontines</h1>
          <div className="muted">Les 50 plus récentes correspondant à la recherche</div>
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
          <button className="btn btn-primary">Filtrer</button>
        </form>
      </div>
      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Tontine</th>
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
                <td colSpan={6} className="muted">
                  Aucun résultat.
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
    </>
  );
}
