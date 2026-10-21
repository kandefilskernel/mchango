import { redirect } from "next/navigation";
import { createStaff, updateStaff } from "../../actions";
import { ActionForm } from "@/components/action-form";
import { api, CAN, currentStaff, type StaffRole } from "@/lib/api";
import { dateTime, roleLabels } from "@/lib/format";

interface StaffRow {
  id: string;
  email: string;
  fullName: string;
  role: StaffRole;
  isActive: boolean;
  lastLoginAt: string | null;
  twoFactorEnrolled: boolean;
}

const rolesHelp: Record<StaffRole, string> = {
  super_admin: "Tout, y compris gérer l'équipe",
  support: "Lire, bloquer un compte, révoquer un téléphone",
  compliance: "Lire, bloquer, suspendre une tontine, trancher les litiges",
  finance: "Lire (numéros masqués)",
  read_only: "Lire (numéros masqués)",
};

export default async function StaffPage() {
  const me = await currentStaff();
  if (!CAN.manageStaff.includes(me.role)) redirect("/");
  const team = await api<StaffRow[]>("/admin/staff");
  return (
    <>
      <div className="page-head">
        <div>
          <h1>Équipe</h1>
          <div className="muted">Chaque compte a sa double authentification. Tout changement de rôle est journalisé.</div>
        </div>
      </div>
      <div className="cols">
        <div className="card">
          <table>
            <thead>
              <tr>
                <th>Personne</th>
                <th>Rôle</th>
                <th>Dernière connexion</th>
                <th>État</th>
              </tr>
            </thead>
            <tbody>
              {team.map((s) => (
                <tr key={s.id}>
                  <td>
                    <strong>{s.fullName}</strong>
                    <br />
                    <span className="muted">{s.email}</span>
                  </td>
                  <td>
                    {s.id === me.id ? (
                      roleLabels[s.role]
                    ) : (
                      <ActionForm inline tone="secondary" submitLabel="Changer" action={updateStaff.bind(null, s.id)}>
                        <select name="role" defaultValue={s.role} aria-label="Rôle">
                          {Object.entries(roleLabels).map(([k, v]) => (
                            <option key={k} value={k}>
                              {v}
                            </option>
                          ))}
                        </select>
                      </ActionForm>
                    )}
                  </td>
                  <td>
                    {dateTime(s.lastLoginAt)}
                    {!s.twoFactorEnrolled && (
                      <>
                        <br />
                        <span className="badge badge-warn">jamais connecté</span>
                      </>
                    )}
                  </td>
                  <td>
                    {s.id === me.id ? (
                      <span className="badge badge-ok">Vous</span>
                    ) : (
                      <ActionForm
                        inline
                        tone={s.isActive ? "danger" : "secondary"}
                        submitLabel={s.isActive ? "Désactiver" : "Réactiver"}
                        confirm={s.isActive ? `Désactiver ${s.fullName} ? Sa session est coupée immédiatement.` : undefined}
                        action={updateStaff.bind(null, s.id)}
                      >
                        <input type="hidden" name="isActive" value={String(!s.isActive)} />
                      </ActionForm>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="card">
          <h2>Ajouter une personne</h2>
          <ActionForm submitLabel="Créer le compte" action={createStaff}>
            <label>
              Nom
              <input name="fullName" required minLength={2} />
            </label>
            <label>
              E-mail
              <input name="email" type="email" required />
            </label>
            <label>
              Rôle
              <select name="role" defaultValue="read_only">
                {Object.entries(roleLabels).map(([k, v]) => (
                  <option key={k} value={k}>
                    {v} — {rolesHelp[k as StaffRole]}
                  </option>
                ))}
              </select>
            </label>
          </ActionForm>
          <p className="muted" style={{ fontSize: 13 }}>
            Le mot de passe provisoire et le QR code de double authentification s&apos;affichent une seule fois. À remettre
            en main propre ; la personne change son mot de passe à la première connexion.
          </p>
        </div>
      </div>
    </>
  );
}
