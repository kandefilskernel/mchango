import { dateTime } from "@/lib/format";

export interface AuditEventRow {
  seq: number;
  action: string;
  actorType: string;
  actorName: string | null;
  payload: string;
  hash: string;
  createdAt: string;
}

/** Libellés lisibles des événements du journal (les autres s'affichent tels quels). */
const labels: Record<string, string> = {
  "groups.insert": "Tontine créée",
  "groups.update": "Tontine modifiée",
  "memberships.insert": "Adhésion",
  "memberships.update": "Adhésion modifiée (ordre des tours…)",
  "group.invitation_created": "Code d'invitation créé",
  "group.turn_order_set": "Ordre des tours fixé",
  "cycles.insert": "Tour créé",
  "cycles.update": "Tour mis à jour",
  "contributions.insert": "Paiement déclaré",
  "contributions.update": "Paiement mis à jour",
  "confirmations.insert": "Réponse à une déclaration",
  "disputes.insert": "Litige ouvert",
  "disputes.update": "Litige mis à jour",
  "auth.user_registered": "Inscription d'un membre",
  "auth.device_linked": "Nouveau téléphone lié (code SMS + PIN)",
  "auth.pin_locked": "PIN bloqué après trop d'essais",
  "auth.pin_reset_requested": "Demande « PIN oublié »",
  "auth.pin_reset_completed": "Nouveau PIN actif",
  "auth.pin_reset_approved": "Nouveau PIN confirmé par un garant",
  "auth.pin_reset_rejected": "Demande de nouveau PIN refusée",
  "staff.group_suspended": "Suspendue par l'équipe",
  "staff.group_reactivated": "Réactivée par l'équipe",
  "staff.dispute_rejected": "Déclaration rejetée par l'équipe",
  "staff.dispute_note": "Avis de l'équipe sur un litige",
  "staff.login": "Connexion d'un membre de l'équipe",
  "staff.created": "Compte d'équipe créé",
  "staff.updated": "Compte d'équipe modifié",
  "staff.password_changed": "Mot de passe d'équipe changé",
  "staff.user_blocked": "Compte bloqué",
  "staff.user_unblocked": "Compte débloqué",
  "staff.device_revoked": "Appareil révoqué",
};

export function EventList({ events }: { events: AuditEventRow[] }) {
  if (events.length === 0) return <p className="muted">Aucun événement.</p>;
  return (
    <>
      {events.map((e) => (
        <div className="event" key={e.seq}>
          <span className="seq">#{e.seq}</span>
          <span>
            <strong>{labels[e.action] ?? e.action}</strong>
            {e.actorType === "staff" && (
              <>
                {" "}
                <span className="badge badge-warn">équipe</span>
              </>
            )}
            <br />
            <span className="muted">
              {e.actorName ?? (e.actorType === "system" ? "Système" : "—")} · {dateTime(e.createdAt)} ·{" "}
              <span className="mono">{e.hash.slice(0, 12)}…</span>
            </span>
          </span>
        </div>
      ))}
    </>
  );
}
