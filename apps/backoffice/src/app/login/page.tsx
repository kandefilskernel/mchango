import { LoginForm } from "./login-form";
import { LoginHero } from "@/components/login-hero";
import { Logo } from "@/components/logo";

export default async function LoginPage({ searchParams }: PageProps<"/login">) {
  const { expired } = await searchParams;
  return (
    <main className="login">
      <div className="login-shell">
        <section className="login-hero">
          <div className="login-brand">
            <Logo size={38} />
            <span>Mchango</span>
          </div>
          <LoginHero />
          <h1>Chaque cotisation, vérifiable.</h1>
          <p>Les membres se paient entre eux ; Mchango garde la preuve.</p>
          <ul className="hero-points">
            <li>Aucun argent ne transite par Mchango</li>
            <li>Confirmé par le bénéficiaire</li>
            <li>Journal scellé</li>
          </ul>
        </section>

        <section className="login-panel">
          <span className="eyebrow">Back-office · équipe</span>
          <h2>Bon retour</h2>
          <p className="muted">Connectez-vous avec votre e-mail, votre mot de passe et votre code à 6 chiffres.</p>
          {expired && <p className="notice">Votre session a expiré. Reconnectez-vous.</p>}
          <LoginForm />
          <p className="login-foot">
            <span aria-hidden="true">🔒</span> Le code vient de votre application d&apos;authentification (Google
            Authenticator, Microsoft Authenticator…). Toute action est inscrite au journal d&apos;audit.
          </p>
        </section>
      </div>
    </main>
  );
}
