import Link from "next/link";
import { approvePinReset, resendSms, unlockPin } from "../../actions";
import { ActionForm } from "@/components/action-form";
import { CAN, currentStaff, inbox } from "@/lib/api";
import { dateTime } from "@/lib/format";

function Section({ title, count, hint, children }: { title: string; count: number; hint: string; children: React.ReactNode }) {
  return (
    <section className="card">
      <div className="section-head">
        <h2>
          {title} <span className={`badge ${count > 0 ? "badge-danger" : "badge-ok"}`}>{count}</span>
        </h2>
        <p className="muted">{hint}</p>
      </div>
      {count === 0 ? <p className="empty">Rien à traiter ici.</p> : children}
    </section>
  );
}

export default async function SupportPage() {
  const [todo, staff] = await Promise.all([inbox(), currentStaff()]);
  const canUnlock = CAN.unlockPins.includes(staff.role);
  const canVerify = CAN.verifyIdentity.includes(staff.role);
  const canSupport = CAN.supportMembers.includes(staff.role);
  return (
    <>
      <div className="page-head">
        <div>
          <h1>À traiter</h1>
          <div className="muted">
            Les membres qui ont besoin de l&apos;équipe. Chaque action est inscrite au journal d&apos;audit.
          </div>
        </div>
        <span className={`badge ${todo.counts.total > 0 ? "badge-danger" : "badge-ok"}`} style={{ fontSize: 14 }}>
          {todo.counts.total === 0 ? "Tout est à jour" : `${todo.counts.total} cas en attente`}
        </span>
      </div>

      <Section
        title="Suivis en cours"
        count={todo.counts.followUps}
        hint="Notes « à suivre » de l'équipe. Clôturez-les depuis la fiche du membre une fois le problème réglé."
      >
        {todo.followUps.map((f) => (
          <div className="case" key={f.noteId}>
            <div>
              <Link href={`/users/${f.userId}`}>
                <strong>{f.fullName}</strong>
              </Link>
              <div>{f.body}</div>
              <div className="muted">
                {f.staff} · {dateTime(f.createdAt)}
              </div>
            </div>
            <Link className="btn btn-secondary" href={`/users/${f.userId}`}>
              Ouvrir la fiche
            </Link>
          </div>
        ))}
      </Section>

      <Section
        title="« PIN oublié » en attente"
        count={todo.counts.pinResetsPending}
        hint="Normalement, un garant de la tontine confirme dans l'app. Intervenez seulement si personne ne répond, et seulement après avoir vérifié l'identité."
      >
        {todo.pinResets.map((r) => (
          <div className="case" key={r.requestId}>
            <div>
              <Link href={`/users/${r.userId}`}>
                <strong>{r.fullName}</strong>
              </Link>{" "}
              <span className="mono">{r.phone}</span>
              <div className="muted">
                Demandé le {dateTime(r.createdAt)} · expire le {dateTime(r.expiresAt)}{" "}
                {r.waitingLong && <span className="badge badge-warn">sans réponse depuis plus de 24 h</span>}
              </div>
            </div>
            {canVerify ? (
              <ActionForm
                submitLabel="Valider le nouveau PIN"
                tone="danger"
                confirm={`Valider le nouveau PIN de ${r.fullName} ? Si quelqu'un a pris son numéro, cela lui donnerait le compte. Ses tontines verront cette validation.`}
                action={approvePinReset.bind(null, r.requestId)}
              >
                <label>
                  Vérification d&apos;identité effectuée (obligatoire, inscrite au journal)
                  <textarea
                    name="note"
                    required
                    minLength={15}
                    placeholder="Ex. : appel au numéro, la personne a décrit sa tontine, ses tours et le président"
                  />
                </label>
              </ActionForm>
            ) : (
              <p className="muted">Validation réservée à la conformité.</p>
            )}
          </div>
        ))}
      </Section>

      <Section
        title="PIN bloqués"
        count={todo.counts.pinLocked}
        hint="5 PIN faux bloquent le compte 30 minutes. Débloquez après avoir parlé à la personne au téléphone."
      >
        {todo.pinLocked.map((u) => (
          <div className="case" key={u.userId}>
            <div>
              <Link href={`/users/${u.userId}`}>
                <strong>{u.fullName}</strong>
              </Link>{" "}
              <span className="mono">{u.phone}</span>
              <div className="muted">Bloqué jusqu&apos;au {dateTime(u.lockedUntil)}</div>
            </div>
            {canUnlock && (
              <ActionForm
                inline
                tone="secondary"
                submitLabel="Débloquer le PIN"
                confirm={`Débloquer le PIN de ${u.fullName} ? Faites-le seulement après lui avoir parlé.`}
                action={unlockPin.bind(null, u.userId)}
              />
            )}
          </div>
        ))}
      </Section>

      <Section
        title="Litiges ouverts"
        count={todo.counts.disputesOpen}
        hint="Paiements contestés entre membres."
      >
        <Link className="btn btn-primary" href="/disputes">
          Ouvrir la file des litiges
        </Link>
      </Section>

      <Section
        title="SMS en échec (7 derniers jours)"
        count={todo.counts.smsFailed}
        hint="Rappels qui ne sont pas partis. Un rappel se renvoie une fois (3 renvois par membre et par jour au plus), seulement si le paiement n'est pas encore déclaré."
      >
        <table>
          <tbody>
            {todo.smsFailed.map((s) => (
              <tr key={s.id}>
                <td>
                  <Link href={`/users/${s.userId}`}>{s.fullName}</Link>
                  <br />
                  <span className="mono">{s.phone}</span>
                </td>
                <td>{s.template === "contribution_reminder" ? "Rappel de cotisation" : s.template}</td>
                <td className="muted">{s.error ?? "—"}</td>
                <td>{dateTime(s.createdAt)}</td>
                <td>
                  {canSupport && s.template === "contribution_reminder" && (
                    <ActionForm
                      inline
                      tone="secondary"
                      submitLabel="Renvoyer"
                      confirm="Renvoyer ce rappel ? Un SMS est facturé à chaque envoi."
                      action={resendSms.bind(null, s.id)}
                    />
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </Section>

      <Section title="Tontines suspendues" count={todo.counts.groupsSuspended} hint="À réactiver une fois le problème réglé.">
        {todo.groupsSuspended.map((g) => (
          <div className="case" key={g.id}>
            <div>
              <Link href={`/groups/${g.id}`}>
                <strong>{g.name}</strong>
              </Link>
              <div className="muted">{g.reason ?? "Sans motif"}</div>
            </div>
            <Link className="btn btn-secondary" href={`/groups/${g.id}`}>
              Ouvrir
            </Link>
          </div>
        ))}
      </Section>
    </>
  );
}
