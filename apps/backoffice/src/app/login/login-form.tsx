"use client";

import { useActionState } from "react";
import { login } from "../actions";

export function LoginForm() {
  const [state, action, pending] = useActionState(login, null);
  return (
    <form action={action} className="form">
      <label>
        E-mail
        <input name="email" type="email" autoComplete="username" required autoFocus />
      </label>
      <label>
        Mot de passe
        <input name="password" type="password" autoComplete="current-password" required />
      </label>
      <label>
        Code à 6 chiffres
        <input
          name="code"
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="\d{6}"
          maxLength={6}
          required
          style={{ letterSpacing: "0.3em", fontSize: 18 }}
        />
      </label>
      <button className="btn btn-primary" disabled={pending}>
        {pending ? "Connexion…" : "Se connecter"}
      </button>
      {state?.error && <p className="msg msg-error">{state.error}</p>}
    </form>
  );
}
