import Link from "next/link";
import { blockUser, revokeDevice, unblockUser } from "../../../actions";
import { ActionForm } from "@/components/action-form";
import { api, CAN, currentStaff } from "@/lib/api";
import { dateTime, groupStatus, memberRole } from "@/lib/format";

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
};

export default async function UserPage({ params }: PageProps<"/users/[id]">) {
  const { id } = await params;
  const [u, staff] = await Promise.all([api<UserDetail>(`/admin/users/${id}`), currentStaff()]);
  const canBlock = CAN.blockUsers.includes(staff.role);
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
            {u.pinLockedUntil && <p className="notice">PIN bloqué jusqu&apos;au {dateTime(u.pinLockedUntil)}.</p>}
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
        </div>
      </div>
    </>
  );
}
