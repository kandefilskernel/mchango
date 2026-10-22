import Link from "next/link";
import { api } from "@/lib/api";
import { dateTime, methodLabels } from "@/lib/format";

interface Person {
  userId: string;
  fullName: string;
  phone: string;
  count: number;
  lastAt: string;
}

interface Alerts {
  rules: Record<"pinResets" | "newDevices" | "rejected", { count: number; days: number }>;
  pinResets: Person[];
  newDevices: Person[];
  rejected: Person[];
  reusedTxReferences: {
    method: string;
    txReference: string;
    count: number;
    payers: string[];
    groups: string[];
    lastAt: string;
  }[];
}

function People({ title, hint, people, unit }: { title: string; hint: string; people: Person[]; unit: string }) {
  return (
    <section className="card">
      <div className="section-head">
        <h2>
          {title} <span className={`badge ${people.length > 0 ? "badge-warn" : "badge-ok"}`}>{people.length}</span>
        </h2>
        <p className="muted">{hint}</p>
      </div>
      {people.length === 0 ? (
        <p className="empty">Aucun signal.</p>
      ) : (
        <table>
          <tbody>
            {people.map((p) => (
              <tr key={p.userId}>
                <td>
                  <Link href={`/users/${p.userId}`}>
                    <strong>{p.fullName}</strong>
                  </Link>
                  <br />
                  <span className="mono">{p.phone}</span>
                </td>
                <td>
                  <strong>{p.count}</strong> {unit}
                </td>
                <td className="muted">dernier le {dateTime(p.lastAt)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}

export default async function AlertsPage() {
  const a = await api<Alerts>("/admin/alerts");
  const r = a.rules;
  return (
    <>
      <div className="page-head">
        <div>
          <h1>Alertes</h1>
          <div className="muted">
            Des signaux à vérifier, pas des preuves : rien n&apos;est bloqué automatiquement. Ouvrez la fiche, appelez la
            personne, notez ce que vous avez constaté.
          </div>
        </div>
      </div>

      <section className="card">
        <div className="section-head">
          <h2>
            ID de transaction utilisé plusieurs fois{" "}
            <span className={`badge ${a.reusedTxReferences.length > 0 ? "badge-danger" : "badge-ok"}`}>
              {a.reusedTxReferences.length}
            </span>
          </h2>
          <p className="muted">
            Le même ID M-Pesa, Airtel ou Orange déclaré deux fois (une déclaration rejetée puis reprise, par exemple).
            Comparez avec le relevé du bénéficiaire.
          </p>
        </div>
        {a.reusedTxReferences.length === 0 ? (
          <p className="empty">Aucun signal.</p>
        ) : (
          <table>
            <tbody>
              {a.reusedTxReferences.map((t) => (
                <tr key={`${t.method}-${t.txReference}`}>
                  <td>
                    <span className="mono">{t.txReference}</span>
                    <br />
                    <span className="muted">{methodLabels[t.method] ?? t.method}</span>
                  </td>
                  <td>
                    <strong>{t.count}</strong> déclarations
                  </td>
                  <td>
                    {t.payers.join(", ")}
                    <br />
                    <span className="muted">{t.groups.join(", ")}</span>
                  </td>
                  <td className="muted">dernière le {dateTime(t.lastAt)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <People
        title="« PIN oublié » répétés"
        hint={`${r.pinResets.count} demandes ou plus en ${r.pinResets.days} jours : possible vol de carte SIM.`}
        people={a.pinResets}
        unit="demandes"
      />
      <People
        title="Beaucoup de nouveaux téléphones"
        hint={`${r.newDevices.count} téléphones liés ou plus en ${r.newDevices.days} jours : compte partagé ou repris.`}
        people={a.newDevices}
        unit="téléphones"
      />
      <People
        title="Déclarations rejetées à répétition"
        hint={`${r.rejected.count} paiements rejetés ou plus en ${r.rejected.days} jours : déclarations sans paiement réel ?`}
        people={a.rejected}
        unit="rejets"
      />
    </>
  );
}
