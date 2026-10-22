import Link from "next/link";
import { decideDispute } from "../../actions";
import { ActionForm } from "@/components/action-form";
import { api, CAN, currentStaff } from "@/lib/api";
import { amount, dateTime, disputeStatus, methodLabels } from "@/lib/format";

interface Dispute {
  id: string;
  status: string;
  reason: string;
  resolutionNote: string | null;
  openedAt: string;
  resolvedAt: string | null;
  openedBy: string;
  contribution: {
    id: string;
    status: string;
    amountMinor: number;
    currency: string;
    method: string;
    txReference: string | null;
    declaredAt: string;
  };
  group: { id: string; name: string; cycleNumber: number };
  payer: { fullName: string; phone: string };
  receiver: { fullName: string; phone: string };
}

export default async function DisputesPage({ searchParams }: PageProps<"/disputes">) {
  const status = String((await searchParams).status ?? "open");
  const [disputes, staff] = await Promise.all([
    api<Dispute[]>(`/admin/disputes?status=${encodeURIComponent(status === "all" ? "" : status)}`),
    currentStaff(),
  ]);
  const canDecide = CAN.decideDisputes.includes(staff.role);
  return (
    <>
      <div className="page-head">
        <div>
          <h1>Litiges</h1>
          <div className="muted">Contestations de paiements déclarés</div>
        </div>
        <form className="form-inline" method="get">
          <select name="status" defaultValue={status} aria-label="Statut">
            <option value="open">Ouverts</option>
            <option value="resolved_rejected">Clos : rejetés</option>
            <option value="resolved_confirmed">Clos : confirmés</option>
            <option value="all">Tous</option>
          </select>
          <button className="btn btn-primary">Filtrer</button>
          {CAN.exportData.includes(staff.role) && (
            <a className="btn btn-secondary" href="/export?kind=disputes" download>
              Exporter tous les litiges (CSV)
            </a>
          )}
        </form>
      </div>

      <p className="notice">
        L&apos;équipe ne voit pas l&apos;argent : elle ne peut <strong>jamais confirmer</strong> un paiement à la place du
        bénéficiaire. Elle peut <strong>rejeter</strong> une déclaration (le payeur devra en refaire une avec un vrai ID de
        transaction) ou <strong>ajouter un avis</strong>. Chaque décision est visible des membres dans le journal de la
        tontine.
      </p>

      {disputes.length === 0 && <div className="card muted">Aucun litige.</div>}
      {disputes.map((d) => (
        <div className="card" key={d.id}>
          <div className="page-head" style={{ marginBottom: 10 }}>
            <div>
              <h2 style={{ marginBottom: 2 }}>
                {d.payer.fullName} → {d.receiver.fullName} · {amount(d.contribution.amountMinor, d.contribution.currency)}
              </h2>
              <div className="muted">
                <Link href={`/groups/${d.group.id}`}>{d.group.name}</Link> · tour {d.group.cycleNumber} · déclaré le{" "}
                {dateTime(d.contribution.declaredAt)}
              </div>
            </div>
            <span className={`badge ${d.status === "open" ? "badge-danger" : "badge-ok"}`}>
              {disputeStatus[d.status] ?? d.status}
            </span>
          </div>
          <div className="cols">
            <div>
              <table>
                <tbody>
                  <tr>
                    <th>Contestation</th>
                    <td>
                      « {d.reason} » <span className="muted">— {d.openedBy}, le {dateTime(d.openedAt)}</span>
                    </td>
                  </tr>
                  <tr>
                    <th>Paiement</th>
                    <td>
                      {methodLabels[d.contribution.method] ?? d.contribution.method}
                      {d.contribution.txReference && (
                        <>
                          {" "}
                          · ID <span className="mono">{d.contribution.txReference}</span>
                        </>
                      )}
                    </td>
                  </tr>
                  <tr>
                    <th>Payeur</th>
                    <td>
                      {d.payer.fullName} · <span className="mono">{d.payer.phone}</span>
                    </td>
                  </tr>
                  <tr>
                    <th>Bénéficiaire</th>
                    <td>
                      {d.receiver.fullName} · <span className="mono">{d.receiver.phone}</span>
                    </td>
                  </tr>
                  {d.resolutionNote && (
                    <tr>
                      <th>Avis de l&apos;équipe</th>
                      <td>{d.resolutionNote}</td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
            <div>
              {d.status === "open" && canDecide && (
                <ActionForm
                  submitLabel="Enregistrer la décision"
                  confirm="Enregistrer cette décision ? Elle sera visible des membres de la tontine."
                  action={decideDispute.bind(null, d.id)}
                >
                  <label>
                    Décision
                    <select name="decision" defaultValue="note">
                      <option value="note">Ajouter un avis (le litige reste ouvert)</option>
                      <option value="reject">Rejeter la déclaration</option>
                    </select>
                  </label>
                  <label>
                    Explication (obligatoire, visible des membres)
                    <textarea name="note" required minLength={5} />
                  </label>
                </ActionForm>
              )}
              {d.status === "open" && !canDecide && <p className="muted">Votre rôle ne permet pas de trancher.</p>}
            </div>
          </div>
        </div>
      ))}
    </>
  );
}
