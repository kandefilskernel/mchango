import Link from "next/link";
import { dateTime } from "@/lib/format";
import { riskBadge, riskLabels } from "./labels";

export interface ReviewRow {
  id: string;
  kind: "group" | "feedback";
  groupId: string | null;
  groupName: string | null;
  requestedBy: string;
  riskLevel: string | null;
  signals: number;
  error: string | null;
  createdAt: string;
}

/** Liste des analyses, avec leur niveau de risque. */
export function ReviewTable({ reviews }: { reviews: ReviewRow[] }) {
  if (reviews.length === 0) return <p className="empty">Aucune analyse pour l&apos;instant.</p>;
  return (
    <table>
      <tbody>
        {reviews.map((r) => (
          <tr key={r.id}>
            <td>
              <Link href={`/ai/${r.id}`}>
                <strong>{r.kind === "group" ? r.groupName : "Synthèse des avis"}</strong>
              </Link>
              <br />
              <span className="muted">
                {dateTime(r.createdAt)} · par {r.requestedBy}
              </span>
            </td>
            <td>
              {r.riskLevel ? (
                <span className={`badge ${riskBadge(r.riskLevel)}`}>{riskLabels[r.riskLevel] ?? r.riskLevel}</span>
              ) : r.error ? (
                <span className="badge badge-warn">Règles seules</span>
              ) : null}
            </td>
            <td className="muted">{r.kind === "group" ? `${r.signals} signal(s) des règles` : ""}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
