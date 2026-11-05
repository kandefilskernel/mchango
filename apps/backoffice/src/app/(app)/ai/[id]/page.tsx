import Link from "next/link";
import type { ReactNode } from "react";
import { api } from "@/lib/api";
import { dateTime } from "@/lib/format";
import {
  categoryLabels,
  riskBadge,
  riskLabels,
  ruleLabels,
  sentimentLabels,
  severityBadge,
  severityLabels,
} from "../labels";

interface Finding {
  severity: string;
  category: string;
  members: string[];
  explanation: string;
  evidence: string[];
  suggested_action: string;
}

interface Review {
  id: string;
  kind: "group" | "feedback";
  groupId: string | null;
  groupName: string | null;
  requestedBy: string;
  model: string;
  rules: { rule: string; severity: string; members: string[]; detail: string }[];
  result:
    | { summary: string; risk_level: string; findings: Finding[] }
    | {
        summary: string;
        sentiment: string;
        themes: { theme: string; count: number; examples: string[] }[];
        urgent: { ref: string; reason: string }[];
      }
    | null;
  error: string | null;
  usage: { inputTokens: number | null; outputTokens: number | null };
  members: Record<string, { membershipId: string; userId: string; fullName: string }>;
  feedback: Record<string, { id: string; userId: string; fullName: string; body: string }>;
  createdAt: string;
}

export default async function AiReviewPage({ params }: PageProps<"/ai/[id]">) {
  const { id } = await params;
  const r = await api<Review>(`/admin/ai/reviews/${id}`);

  /** Remet les vrais noms à la place des codes M1, M2… (les codes restent visibles, entre parenthèses). */
  const named = (text: string): ReactNode[] =>
    text.split(/\b(M\d+)\b/).map((part, i) => {
      const m = r.members[part];
      return m ? (
        <Link key={i} href={`/users/${m.userId}`}>
          {m.fullName} ({part})
        </Link>
      ) : (
        part
      );
    });

  const group = r.result && "findings" in r.result ? r.result : null;
  const feedback = r.result && "themes" in r.result ? r.result : null;

  return (
    <>
      <div className="page-head">
        <div>
          <Link href="/ai">← Analyse IA</Link>
          <h1>
            {r.kind === "group" ? (
              <>
                Analyse : <Link href={`/groups/${r.groupId}`}>{r.groupName}</Link>
              </>
            ) : (
              "Synthèse des avis des membres"
            )}
          </h1>
          <div className="muted">
            {dateTime(r.createdAt)} · demandée par {r.requestedBy} · {r.model}
            {r.usage.inputTokens !== null && ` · ${r.usage.inputTokens + (r.usage.outputTokens ?? 0)} jetons`}
          </div>
        </div>
        {group && <span className={`badge ${riskBadge(group.risk_level)}`}>{riskLabels[group.risk_level]}</span>}
        {feedback && <span className="badge badge-ok">{sentimentLabels[feedback.sentiment] ?? feedback.sentiment}</span>}
      </div>

      <p className="notice">
        Pistes à vérifier, pas des preuves. Avant toute mesure : appelez les personnes concernées, demandez la capture du
        SMS de l&apos;opérateur, et notez ce que vous constatez sur leur fiche.
      </p>

      {r.error && <p className="msg msg-error" style={{ marginBottom: 16 }}>{r.error}</p>}

      <div className="cols">
        <div>
          {r.result && (
            <section className="card">
              <h2>Résumé</h2>
              <p>{named(r.result.summary)}</p>
            </section>
          )}

          {group && (
            <section className="card">
              <div className="section-head">
                <h2>
                  Constats de l&apos;agent <span className="badge badge-ok">{group.findings.length}</span>
                </h2>
              </div>
              {group.findings.length === 0 ? (
                <p className="empty">Rien d&apos;anormal relevé.</p>
              ) : (
                group.findings.map((f, i) => (
                  <div key={i} style={{ borderTop: i ? "1px solid var(--line)" : undefined, padding: "12px 0" }}>
                    <p>
                      <span className={`badge ${severityBadge(f.severity)}`}>{severityLabels[f.severity] ?? f.severity}</span>{" "}
                      <strong>{categoryLabels[f.category] ?? f.category}</strong>
                      {f.members.length > 0 && <> · {named(f.members.join(", "))}</>}
                    </p>
                    <p>{named(f.explanation)}</p>
                    {f.evidence.length > 0 && (
                      <ul className="muted">
                        {f.evidence.map((e, j) => (
                          <li key={j}>{named(e)}</li>
                        ))}
                      </ul>
                    )}
                    <p>
                      <strong>Action proposée :</strong> {named(f.suggested_action)}
                    </p>
                  </div>
                ))
              )}
            </section>
          )}

          {feedback && (
            <>
              <section className="card">
                <div className="section-head">
                  <h2>
                    À traiter vite <span className={`badge ${feedback.urgent.length ? "badge-danger" : "badge-ok"}`}>{feedback.urgent.length}</span>
                  </h2>
                </div>
                {feedback.urgent.length === 0 ? (
                  <p className="empty">Aucun avis urgent.</p>
                ) : (
                  <table>
                    <tbody>
                      {feedback.urgent.map((u) => {
                        const f = r.feedback[u.ref];
                        return (
                          <tr key={u.ref}>
                            <td style={{ minWidth: 150 }}>
                              {f ? (
                                <Link href={`/users/${f.userId}`}>
                                  <strong>{f.fullName}</strong>
                                </Link>
                              ) : (
                                u.ref
                              )}
                            </td>
                            <td>
                              <strong>{u.reason}</strong>
                              {f && (
                                <>
                                  <br />
                                  <span className="muted">« {f.body} »</span>
                                </>
                              )}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                )}
              </section>
              <section className="card">
                <h2>Thèmes</h2>
                {feedback.themes.length === 0 ? (
                  <p className="empty">Pas de thème récurrent.</p>
                ) : (
                  <table>
                    <tbody>
                      {feedback.themes.map((t, i) => (
                        <tr key={i}>
                          <td>
                            <strong>{t.theme}</strong>
                            <ul className="muted">
                              {t.examples.map((e, j) => (
                                <li key={j}>{e}</li>
                              ))}
                            </ul>
                          </td>
                          <td>{t.count} avis</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </section>
            </>
          )}
        </div>

        <div>
          {r.kind === "group" && (
            <section className="card">
              <h2>Règles automatiques</h2>
              <p className="muted">Calculées sans IA, toujours disponibles.</p>
              {r.rules.length === 0 ? (
                <p className="empty">Aucun signal.</p>
              ) : (
                <ul>
                  {r.rules.map((s, i) => (
                    <li key={i} style={{ marginBottom: 8 }}>
                      <span className={`badge ${severityBadge(s.severity)}`}>{ruleLabels[s.rule] ?? s.rule}</span>
                      <br />
                      {named(s.detail)}
                    </li>
                  ))}
                </ul>
              )}
            </section>
          )}
          {Object.keys(r.members).length > 0 && (
            <section className="card">
              <h2>Codes des membres</h2>
              <table>
                <tbody>
                  {Object.entries(r.members).map(([code, m]) => (
                    <tr key={code}>
                      <td className="mono">{code}</td>
                      <td>
                        <Link href={`/users/${m.userId}`}>{m.fullName}</Link>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </section>
          )}
        </div>
      </div>
    </>
  );
}
