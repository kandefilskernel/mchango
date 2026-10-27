import Link from "next/link";
import { addNote, blockUser, resendSms, revokeDevice, unblockUser, unlockPin } from "../../../actions";
import { ActionForm } from "@/components/action-form";
import { api, CAN, currentStaff } from "@/lib/api";
import { dateTime, groupStatus, memberRole, smsStatus, smsTemplate } from "@/lib/format";

interface UserDetail {
  id: string;
  fullName: string;
  phone: string;
  language: string;
  isBlocked: boolean;
  blockedReason: string | null;
  pinLockedUntil: string | null;
  createdAt: string;
  devices: { id: string; createdAt: string; lastSeenAt: string | null; revokedAt: string | null }[];
  memberships: { groupId: string; groupName: string; groupStatus: string; role: string; status: string }[];
  events: { seq: number; action: string; actorType: string; createdAt: string }[];
  sms: {
    id: string;
    template: string;
    status: string;
    error: string | null;
    createdAt: string;
    sentAt: string | null;
    isResend: boolean;
    resendable: boolean;
  }[];
  notes: {
    id: string;
    body: string;
    followUp: boolean;
    closes: string | null;
    closed: boolean;
    staff: string;
    createdAt: string;
  }[];
}

const eventLabels: Record<string, string> = {
  "auth.user_registered": "Inscription",
  "auth.device_linked": "Nouveau téléphone lié (code SMS + PIN)",
  "auth.pin_locked": "PIN bloqué après trop d'essais",
  "auth.pin_reset_requested": "Demande « PIN oublié »",
  "auth.pin_reset_completed": "Nouveau PIN actif",
  "staff.user_blocked": "Bloqué par l'équipe",
  "staff.user_unblocked": "Débloqué par l'équipe",
  "staff.device_revoked": "Appareil révoqué par l'équipe",
  "staff.pin_unlocked": "PIN débloqué par l'équipe",
  "staff.support_note": "Note de suivi de l'équipe",
  "staff.follow_up_closed": "Suivi clos par l'équipe",
  "staff.sms_resent": "Rappel SMS renvoyé par l'équipe",
};

export default async function UserPage({ params }: PageProps<"/users/[id]">) {
  const { id } = await params;
  const [u, staff] = await Promise.all([api<UserDetail>(`/admin/users/${id}`), currentStaff()]);
  const canBlock = CAN.blockUsers.includes(staff.role);
  const canSupport = CAN.supportMembers.includes(staff.role);
  const canUnlock = CAN.unlockPins.includes(staff.role);
  const openFollowUps = u.notes.filter((n) => n.followUp && !n.closed);
  return (
    <>
      <div className="page-head">
        <div>
          <Link href="/users">← Utilisateurs</Link>
          <h1>{u.fullName}</h1>
          <div className="mono">{u.phone}</div>
        </div>
        {u.isBlocked ? <span className="badge badge-danger">Bloqué</span> : <span className="badge badge-ok">Actif</span>}
      </div>

      <div className="cols">
        <div>
          <div className="card">
            <h2>Tontines</h2>
            <table>
              <tbody>
                {u.memberships.length === 0 && (
                  <tr>
                    <td className="muted">Aucune.</td>
                  </tr>
                )}
                {u.memberships.map((m) => (
                  <tr key={m.groupId}>
                    <td>
                      <Link href={`/groups/${m.groupId}`}>{m.groupName}</Link>
                    </td>
                    <td>{memberRole[m.role] ?? m.role}</td>
                    <td>
                      <span className="badge">{groupStatus[m.groupStatus] ?? m.groupStatus}</span>
                    </td>
                    <td>{m.status === "active" ? "" : <span className="badge badge-warn">{m.status}</span>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="card">
            <h2>Téléphones liés</h2>
            <table>
              <thead>
                <tr>
                  <th>Lié le</th>
                  <th>Dernière connexion</th>
                  <th>État</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {u.devices.map((d) => (
                  <tr key={d.id}>
                    <td>{dateTime(d.createdAt)}</td>
                    <td>{dateTime(d.lastSeenAt)}</td>
                    <td>
                      {d.revokedAt ? (
                        <span className="badge">Révoqué le {dateTime(d.revokedAt)}</span>
                      ) : (
                        <span className="badge badge-ok">Actif</span>
                      )}
                    </td>
                    <td>
                      {!d.revokedAt && canBlock && (
                        <ActionForm
                          inline
                          tone="secondary"
                          submitLabel="Révoquer"
                          confirm="Révoquer ce téléphone ? La personne devra se reconnecter avec un code SMS et son PIN."
                          action={revokeDevice.bind(null, u.id, d.id)}
                        />
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="card">
            <h2>SMS reçus (30 derniers)</h2>
            {u.sms.length === 0 ? (
              <p className="empty">Aucun SMS enregistré. Les codes de connexion ne sont pas conservés.</p>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>Date</th>
                    <th>Message</th>
                    <th>État</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {u.sms.map((s) => (
                    <tr key={s.id}>
                      <td>{dateTime(s.createdAt)}</td>
                      <td>
                        {smsTemplate[s.template] ?? s.template}
                        {s.isResend && <span className="muted"> · renvoi</span>}
                      </td>
                      <td>
                        <span
                          className={`badge ${s.status === "sent" ? "badge-ok" : s.status === "failed" ? "badge-danger" : ""}`}
                        >
                          {smsStatus[s.status] ?? s.status}
                        </span>
                        {s.error && <div className="muted">{s.error}</div>}
                      </td>
                      <td>
                        {s.resendable && canSupport && (
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
            )}
          </div>

          <div className="card">
            <h2>Historique du compte</h2>
            {u.events.map((e) => (
              <div className="event" key={e.seq}>
                <span className="seq">#{e.seq}</span>
                <span>
                  {eventLabels[e.action] ?? e.action} <span className="muted">· {dateTime(e.createdAt)}</span>
                </span>
              </div>
            ))}
          </div>
        </div>

        <div>
          <div className="card">
            <h2>Compte</h2>
            <p>
              Inscrit le {dateTime(u.createdAt)} · langue : {u.language}
            </p>
            {u.pinLockedUntil && new Date(u.pinLockedUntil) > new Date() && (
              <div className="notice">
                PIN bloqué jusqu&apos;au {dateTime(u.pinLockedUntil)}.
                {canUnlock && (
                  <ActionForm
                    inline
                    tone="secondary"
                    submitLabel="Débloquer le PIN"
                    confirm={`Débloquer le PIN de ${u.fullName} ? Faites-le seulement après lui avoir parlé.`}
                    action={unlockPin.bind(null, u.id)}
                  />
                )}
              </div>
            )}
            {u.isBlocked && u.blockedReason && (
              <p className="notice">
                <strong>Motif du blocage :</strong> {u.blockedReason}
              </p>
            )}
            {canBlock &&
              (u.isBlocked ? (
                <ActionForm submitLabel="Débloquer" tone="secondary" action={unblockUser.bind(null, u.id)} />
              ) : (
                <ActionForm
                  submitLabel="Bloquer le compte"
                  tone="danger"
                  confirm="Bloquer ce compte ? Ses sessions seront coupées immédiatement."
                  action={blockUser.bind(null, u.id)}
                >
                  <label>
                    Motif (obligatoire, inscrit au journal)
                    <textarea name="reason" required minLength={5} />
                  </label>
                </ActionForm>
              ))}
            {!canBlock && <p className="muted">Votre rôle ne permet pas de bloquer un compte.</p>}
          </div>

          <div className="card">
            <h2>Notes de suivi</h2>
            <p className="muted">Internes à l&apos;équipe, jamais visibles du membre. Une note ne se modifie pas.</p>
            {openFollowUps.map((n) => (
              <div className="note note-open" key={n.id}>
                <div>
                  <span className="badge badge-warn">À suivre</span> {n.body}
                </div>
                <div className="muted">
                  {n.staff} · {dateTime(n.createdAt)}
                </div>
                {canSupport && (
                  <ActionForm submitLabel="Clore le suivi" tone="secondary" action={addNote.bind(null, u.id, n.id)}>
                    <input name="body" required minLength={3} placeholder="Comment c'est réglé ?" aria-label="Clôture" />
                  </ActionForm>
                )}
              </div>
            ))}
            {canSupport && (
              <ActionForm submitLabel="Ajouter la note" action={addNote.bind(null, u.id, null)}>
                <label>
                  Nouvelle note
                  <textarea name="body" required minLength={3} placeholder="Ex. : appelé à 14 h, rappeler demain matin" />
                </label>
                <label className="check">
                  <input type="checkbox" name="followUp" /> À suivre (apparaît dans « À traiter »)
                </label>
              </ActionForm>
            )}
            {u.notes
              .filter((n) => !(n.followUp && !n.closed))
              .map((n) => (
                <div className="note" key={n.id}>
                  <div>
                    {n.closes && <span className="badge badge-ok">Clôture</span>}
                    {n.followUp && <span className="badge">Suivi clos</span>} {n.body}
                  </div>
                  <div className="muted">
                    {n.staff} · {dateTime(n.createdAt)}
                  </div>
                </div>
              ))}
          </div>
        </div>
      </div>
    </>
  );
}
