import { changePassword } from "../../actions";
import { ActionForm } from "@/components/action-form";
import { currentStaff } from "@/lib/api";
import { roleLabels } from "@/lib/format";

export default async function AccountPage({ searchParams }: PageProps<"/account">) {
  const [{ first }, me] = await Promise.all([searchParams, currentStaff()]);
  return (
    <>
      <div className="page-head">
        <div>
          <h1>Mon compte</h1>
          <div className="muted">
            {me.fullName} · {me.email} · {roleLabels[me.role]}
          </div>
        </div>
      </div>
      {first && (
        <p className="notice">
          Première connexion : remplacez votre mot de passe provisoire par un mot de passe à vous.
        </p>
      )}
      <div className="card" style={{ maxWidth: 460 }}>
        <h2>Changer de mot de passe</h2>
        <ActionForm submitLabel="Changer le mot de passe" action={changePassword}>
          <label>
            Mot de passe actuel
            <input name="current" type="password" autoComplete="current-password" required />
          </label>
          <label>
            Nouveau mot de passe (12 caractères au moins, lettres et chiffres)
            <input name="next" type="password" autoComplete="new-password" required minLength={12} />
          </label>
          <label>
            Retapez le nouveau mot de passe
            <input name="confirm" type="password" autoComplete="new-password" required minLength={12} />
          </label>
        </ActionForm>
      </div>
    </>
  );
}
