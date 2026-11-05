"use client";

import { useActionState, type ReactNode } from "react";
import type { ActionState } from "@/app/actions";

/**
 * Formulaire relié à une action serveur : bouton désactivé pendant l'envoi, message de résultat,
 * confirmation explicite pour les actions lourdes de conséquences.
 */
export function ActionForm({
  action,
  submitLabel,
  children,
  confirm,
  tone = "primary",
  inline = false,
}: {
  action: (state: ActionState, form: FormData) => Promise<ActionState>;
  submitLabel: string;
  children?: ReactNode;
  confirm?: string;
  tone?: "primary" | "danger" | "secondary";
  inline?: boolean;
}) {
  const [state, formAction, pending] = useActionState(action, null);
  return (
    <form
      action={formAction}
      className={inline ? "form-inline" : "form"}
      onSubmit={(e) => {
        if (confirm && !window.confirm(confirm)) e.preventDefault();
      }}
    >
      {children}
      <button type="submit" className={`btn btn-${tone}`} disabled={pending}>
        {pending ? "…" : submitLabel}
      </button>
      {state?.error && <p className="msg msg-error">{state.error}</p>}
      {state?.ok && <p className="msg msg-ok">{state.ok}</p>}
      {state?.credentials && (
        <div className="credentials">
          <p>
            <strong>À transmettre en main propre, une seule fois.</strong> Ces informations ne seront plus affichées.
          </p>
          <dl>
            <dt>E-mail</dt>
            <dd>{state.credentials.email}</dd>
            <dt>Mot de passe provisoire</dt>
            <dd className="mono">{state.credentials.temporaryPassword}</dd>
            <dt>Secret double authentification</dt>
            <dd className="mono">{state.credentials.totpSecret}</dd>
          </dl>
          {/* eslint-disable-next-line @next/next/no-img-element -- image générée (data URL), pas un fichier */}
          <img src={state.credentials.qr} alt="QR code à scanner avec l'application d'authentification" width={220} height={220} />
          <p className="muted">À scanner avec Google Authenticator, Microsoft Authenticator ou équivalent.</p>
        </div>
      )}
    </form>
  );
}
