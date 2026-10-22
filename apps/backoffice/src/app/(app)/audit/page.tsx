import { verifyChain } from "../../actions";
import { ActionForm } from "@/components/action-form";
import { EventList, type AuditEventRow } from "@/components/event-list";
import { api, CAN, currentStaff } from "@/lib/api";
import { dateTime } from "@/lib/format";

interface StaffAction {
  chainId: string;
  seq: number;
  action: string;
  payload: string;
  createdAt: string;
  staff: string | null;
}

export default async function AuditPage({ searchParams }: PageProps<"/audit">) {
  const raw = String((await searchParams).chain ?? "global").trim();
  // Accepte « global », « group:<uuid> » ou un simple identifiant de tontine
  const chain = /^[0-9a-f-]{36}$/.test(raw) ? `group:${raw}` : raw;
  const [events, actions, staff] = await Promise.all([
    api<AuditEventRow[]>(`/admin/audit?chain=${encodeURIComponent(chain)}&limit=100`),
    api<StaffAction[]>("/admin/audit/staff"),
    currentStaff(),
  ]);
  return (
    <>
      <div className="page-head">
        <div>
          <h1>Audit</h1>
          <div className="muted">Journal en ajout seul, chaîné par hash : une modification casse la chaîne.</div>
        </div>
      </div>

      <div className="cols">
        <div>
          <div className="card">
            <div className="page-head" style={{ marginBottom: 8 }}>
              <h2 style={{ margin: 0 }}>Chaîne « {chain} » (100 derniers événements)</h2>
              <form className="form-inline" method="get">
                <input name="chain" defaultValue={chain} aria-label="Chaîne" placeholder="global ou identifiant de tontine" />
                <button className="btn btn-secondary">Afficher</button>
              </form>
            </div>
            <EventList events={events} />
          </div>
        </div>
        <div>
          <div className="card">
            <h2>Vérifier une chaîne</h2>
            <p className="muted">Recalcule tous les hash depuis le début. À faire en cas de doute ou avant un contrôle.</p>
            <ActionForm submitLabel="Vérifier l'intégrité" action={verifyChain}>
              <input type="hidden" name="chainId" value={chain} />
            </ActionForm>
          </div>
          {CAN.exportData.includes(staff.role) && (
            <div className="card">
              <h2>Exporter la chaîne</h2>
              <p className="muted">
                Tous les événements de « {chain} » avec leurs empreintes, pour un contrôle externe. L&apos;export est
                inscrit au journal.
              </p>
              <a className="btn btn-secondary" href={`/export?kind=audit&chain=${encodeURIComponent(chain)}`} download>
                Télécharger (CSV)
              </a>
            </div>
          )}
          <div className="card">
            <h2>Actions de l&apos;équipe</h2>
            {actions.slice(0, 40).map((a) => (
              <div className="event" key={`${a.chainId}-${a.seq}`}>
                <span className="seq">#{a.seq}</span>
                <span>
                  <strong>{a.action.replace("staff.", "")}</strong> <span className="muted">· {a.chainId}</span>
                  <br />
                  <span className="muted">
                    {a.staff ?? "—"} · {dateTime(a.createdAt)}
                  </span>
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </>
  );
}
