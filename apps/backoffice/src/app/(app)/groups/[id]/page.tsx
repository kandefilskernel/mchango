import Link from "next/link";
import { reactivateGroup, suspendGroup } from "../../../actions";
import { ActionForm } from "@/components/action-form";
import { EventList, type AuditEventRow } from "@/components/event-list";
import { api, CAN, currentStaff } from "@/lib/api";
import { amount, cycleStatus, date, dateTime, frequencyLabels, groupStatus, memberRole, statusBadge } from "@/lib/format";

interface GroupDetail {
  id: string;
  name: string;
  status: string;
  currency: string;
  contributionAmountMinor: number;
  frequency: string;
  startDate: string;
  turnOrderMode: string | null;
  drawSeed: string | null;
  suspendedReason: string | null;
  createdAt: string;
  members: { userId: string; fullName: string; phone: string; role: string; status: string; turnOrder: number | null }[];
  cycles: { cycleNumber: number; dueDate: string; status: string; beneficiary: string; confirmed: number; expected: number }[];
  chain: { chainId: string; intact: boolean; firstInvalidSeq: string | null };
  events: AuditEventRow[];
}

export default async function GroupPage({ params }: PageProps<"/groups/[id]">) {
  const { id } = await params;
  const [g, staff] = await Promise.all([api<GroupDetail>(`/admin/groups/${id}`), currentStaff()]);
  const canSuspend = CAN.suspendGroups.includes(staff.role);
  return (
    <>
      <div className="page-head">
        <div>
          <Link href="/groups">← Tontines</Link>
          <h1>{g.name}</h1>
          <div className="muted">
            {amount(g.contributionAmountMinor, g.currency)} · {frequencyLabels[g.frequency] ?? g.frequency} · premier tour le{" "}
            {date(g.startDate)} · créée le {dateTime(g.createdAt)}
          </div>
        </div>
        <span className={`badge ${statusBadge(g.status)}`}>{groupStatus[g.status] ?? g.status}</span>
      </div>

      {!g.chain.intact && (
        <p className="msg msg-error" style={{ marginBottom: 16 }}>
          Journal de cette tontine INCOHÉRENT à partir de l&apos;événement n°{g.chain.firstInvalidSeq}. À traiter en priorité.
        </p>
      )}

      <div className="cols">
        <div>
          <div className="card">
            <h2>Tours</h2>
            {g.cycles.length === 0 ? (
              <p className="muted">Pas encore démarrée.</p>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>Tour</th>
                    <th>Bénéficiaire</th>
                    <th>Échéance</th>
                    <th>Confirmés</th>
                    <th>Statut</th>
                  </tr>
                </thead>
                <tbody>
                  {g.cycles.map((c) => (
                    <tr key={c.cycleNumber}>
                      <td>{c.cycleNumber}</td>
                      <td>{c.beneficiary}</td>
                      <td>{date(c.dueDate)}</td>
                      <td>
                        {c.confirmed} / {c.expected}
                      </td>
                      <td>
                        <span className={`badge ${c.status === "completed" ? "badge-ok" : ""}`}>{cycleStatus[c.status] ?? c.status}</span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>

          <div className="card">
            <h2>Membres</h2>
            <table>
              <tbody>
                {g.members.map((m) => (
                  <tr key={m.userId}>
                    <td>{m.turnOrder ?? "—"}</td>
                    <td>
                      <Link href={`/users/${m.userId}`}>{m.fullName}</Link>
                    </td>
                    <td className="mono">{m.phone}</td>
                    <td>{memberRole[m.role] ?? m.role}</td>
                    <td>{m.status === "active" ? "" : <span className="badge badge-warn">{m.status}</span>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p className="muted" style={{ marginTop: 10 }}>
              Ordre des tours :{" "}
              {g.turnOrderMode === "draw"
                ? `tiré au sort (graine ${g.drawSeed?.slice(0, 16)}…)`
                : g.turnOrderMode === "chosen"
                  ? `choisi par le président${g.drawSeed ? " (un tirage avait eu lieu avant)" : ""}`
                  : "pas encore fixé"}
            </p>
          </div>

          <div className="card">
            <h2>Journal de la tontine (50 derniers événements)</h2>
            <p className="muted">
              Chaîne {g.chain.intact ? "intacte" : "INCOHÉRENTE"} · {g.chain.chainId}
            </p>
            <EventList events={g.events} />
          </div>
        </div>

        <div>
          <div className="card">
            <h2>Suspension</h2>
            {g.status === "suspended" && g.suspendedReason && (
              <p className="notice">
                <strong>Motif :</strong> {g.suspendedReason}
              </p>
            )}
            {!canSuspend && <p className="muted">Votre rôle ne permet pas de suspendre une tontine.</p>}
            {canSuspend && g.status === "suspended" && (
              <ActionForm submitLabel="Réactiver la tontine" tone="secondary" action={reactivateGroup.bind(null, g.id)} />
            )}
            {canSuspend && (g.status === "active" || g.status === "draft") && (
              <ActionForm
                submitLabel="Suspendre la tontine"
                tone="danger"
                confirm="Suspendre cette tontine ? Plus aucune déclaration ni rappel tant qu'elle est suspendue. Les membres verront la suspension dans leur historique."
                action={suspendGroup.bind(null, g.id)}
              >
                <label>
                  Motif (obligatoire, visible des membres)
                  <textarea name="reason" required minLength={5} />
                </label>
              </ActionForm>
            )}
          </div>
        </div>
      </div>
    </>
  );
}
