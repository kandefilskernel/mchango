import Link from "next/link";
import { api } from "@/lib/api";
import { dateTime } from "@/lib/format";

interface UserRow {
  id: string;
  fullName: string;
  phone: string;
  isBlocked: boolean;
  createdAt: string;
  groups: number;
}

export default async function UsersPage({ searchParams }: PageProps<"/users">) {
  const q = String((await searchParams).q ?? "");
  const users = await api<UserRow[]>(`/admin/users?q=${encodeURIComponent(q)}`);
  return (
    <>
      <div className="page-head">
        <div>
          <h1>Utilisateurs</h1>
          <div className="muted">Recherche par nom ou par numéro (au moins 4 chiffres)</div>
        </div>
        <form className="form-inline" method="get">
          <input name="q" defaultValue={q} placeholder="Nom ou numéro" aria-label="Rechercher" />
          <button className="btn btn-primary">Rechercher</button>
        </form>
      </div>
      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Nom</th>
              <th>Téléphone</th>
              <th>Tontines</th>
              <th>Inscrit le</th>
              <th>État</th>
            </tr>
          </thead>
          <tbody>
            {users.length === 0 && (
              <tr>
                <td colSpan={5} className="muted">
                  Aucun résultat.
                </td>
              </tr>
            )}
            {users.map((u) => (
              <tr key={u.id}>
                <td>
                  <Link href={`/users/${u.id}`}>{u.fullName}</Link>
                </td>
                <td className="mono">{u.phone}</td>
                <td>{u.groups}</td>
                <td>{dateTime(u.createdAt)}</td>
                <td>
                  {u.isBlocked ? <span className="badge badge-danger">Bloqué</span> : <span className="badge badge-ok">Actif</span>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
