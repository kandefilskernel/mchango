import { LoginForm } from "./login-form";
import { Logo } from "@/components/logo";

export default async function LoginPage({ searchParams }: PageProps<"/login">) {
  const { expired } = await searchParams;
  return (
    <main className="login">
      <div className="card">
        <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 18 }}>
          <Logo size={44} />
          <div>
            <h1 style={{ fontSize: 22 }}>Mchango</h1>
            <div className="muted">Back-office · réservé à l&apos;équipe</div>
          </div>
        </div>
        {expired && <p className="notice">Votre session a expiré. Reconnectez-vous.</p>}
        <LoginForm />
        <p className="muted" style={{ fontSize: 13, marginTop: 18 }}>
          Le code à 6 chiffres vient de votre application d&apos;authentification (Google Authenticator,
          Microsoft Authenticator…). Toute action est inscrite dans le journal d&apos;audit.
        </p>
      </div>
    </main>
  );
}
