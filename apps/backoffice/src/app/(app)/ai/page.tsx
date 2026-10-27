import Link from "next/link";
import { runAiReview } from "../../actions";
import { ActionForm } from "@/components/action-form";
import { api, CAN, currentStaff } from "@/lib/api";
import { dateTime } from "@/lib/format";
import { ReviewTable, type ReviewRow } from "./review-table";

interface Status {
  enabled: boolean;
  model: string;
  perDay: number;
}

interface Feedback {
  id: string;
  userId: string;
  fullName: string;
  groupId: string | null;
  groupName: string | null;
  rating: number | null;
  body: string;
  createdAt: string;
}

const stars = (n: number | null) => (n ? "★".repeat(n) + "☆".repeat(5 - n) : "—");

export default async function AiPage() {
  const [status, reviews, feedback, staff] = await Promise.all([
    api<Status>("/admin/ai/status"),
    api<ReviewRow[]>("/admin/ai/reviews"),
    api<Feedback[]>("/admin/ai/feedback"),
    currentStaff(),
  ]);
  const canRun = CAN.supportMembers.includes(staff.role);
  return (
    <>
      <div className="page-head">
        <div>
          <h1>Analyse IA</h1>
          <div className="muted">
            L&apos;agent lit les cotisations, les litiges et les avis des membres, et signale ce qui sort de l&apos;ordinaire.
            Ce sont des pistes à vérifier : il ne bloque, ne suspend et ne décide rien.
          </div>
        </div>
        <span className={`badge ${status.enabled ? "badge-ok" : "badge-warn"}`}>
          {status.enabled ? `Agent actif · ${status.model}` : "Agent non configuré : règles seules"}
        </span>
      </div>

      <p className="notice">
        <strong>Données envoyées à l&apos;agent :</strong> pseudonymisées. Les membres deviennent M1, M2…, les numéros de
        téléphone et les noms sont retirés des textes. Les vrais noms ne sont remis qu&apos;ici, pour vous. Au plus{" "}
        {status.perDay} analyses IA par jour (chacune est facturée).
      </p>

      <div className="cols">
        <div>
          <section className="card">
            <div className="section-head">
              <h2>Analyses récentes</h2>
              <p className="muted">
                Pour analyser une tontine, ouvrez sa fiche dans <Link href="/groups">Tontines</Link>, carte « Analyse IA ».
              </p>
            </div>
            <ReviewTable reviews={reviews} />
          </section>

          <section className="card">
            <div className="section-head">
              <h2>
                Avis des membres <span className="badge badge-ok">{feedback.length}</span>
              </h2>
              <p className="muted">Les 200 derniers, envoyés depuis l&apos;app (menu « Donner mon avis »).</p>
            </div>
            {feedback.length === 0 ? (
              <p className="empty">Aucun avis pour l&apos;instant.</p>
            ) : (
              <table>
                <tbody>
                  {feedback.map((f) => (
                    <tr key={f.id}>
                      <td style={{ minWidth: 160 }}>
                        <Link href={`/users/${f.userId}`}>
                          <strong>{f.fullName}</strong>
                        </Link>
                        <br />
                        <span className="muted">
                          {f.groupId ? <Link href={`/groups/${f.groupId}`}>{f.groupName}</Link> : "Mchango en général"}
                        </span>
                      </td>
                      <td>
                        <span aria-label={f.rating ? `${f.rating} sur 5` : "sans note"}>{stars(f.rating)}</span>
                        <br />
                        {f.body}
                      </td>
                      <td className="muted">{dateTime(f.createdAt)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </section>
        </div>

        <div>
          <section className="card">
            <h2>Synthèse des avis</h2>
            <p className="muted">
              Thèmes récurrents des 30 derniers jours, sentiment général, et avis à traiter vite (arnaque signalée,
              argent non reçu, compte piraté).
            </p>
            {canRun ? (
              <ActionForm submitLabel="Analyser les avis" action={runAiReview.bind(null, null)} />
            ) : (
              <p className="muted">Votre rôle permet de lire les analyses, pas d&apos;en lancer.</p>
            )}
          </section>
        </div>
      </div>
    </>
  );
}
