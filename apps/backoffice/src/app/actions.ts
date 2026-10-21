"use server";

import { revalidatePath } from "next/cache";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import QRCode from "qrcode";
import { api, ApiError, apiLogin, SESSION_COOKIE } from "@/lib/api";

// Chaque action est un point d'entrée public : l'API vérifie elle-même la session et le rôle,
// et inscrit l'action dans le journal. Ici on ne fait que relayer et afficher le résultat.

export type ActionState = {
  ok?: string;
  error?: string;
  credentials?: { email: string; temporaryPassword: string; totpSecret: string; qr: string };
} | null;

async function run(fn: () => Promise<string | ActionState>): Promise<ActionState> {
  try {
    const result = await fn();
    revalidatePath("/", "layout");
    return typeof result === "string" ? { ok: result } : result;
  } catch (e) {
    // Les redirections (session expirée) ne sont pas des erreurs : on les laisse passer
    if (!(e instanceof ApiError)) throw e;
    return { error: e.message };
  }
}

const text = (form: FormData, name: string) => String(form.get(name) ?? "").trim();

export async function login(_: ActionState, form: FormData): Promise<ActionState> {
  let mustChange = false;
  try {
    const res = await apiLogin(text(form, "email"), String(form.get("password") ?? ""), text(form, "code"));
    (await cookies()).set(SESSION_COOKIE, res.token, {
      httpOnly: true,
      sameSite: "strict",
      secure: process.env.NODE_ENV === "production",
      path: "/",
      maxAge: res.expiresIn,
    });
    mustChange = res.mustChangePassword;
  } catch (e) {
    return { error: e instanceof ApiError ? e.message : "Connexion impossible." };
  }
  redirect(mustChange ? "/account?first=1" : "/");
}

export async function logout() {
  (await cookies()).delete(SESSION_COOKIE);
  redirect("/login");
}

export async function blockUser(userId: string, _: ActionState, form: FormData) {
  return run(async () => {
    await api(`/admin/users/${userId}/block`, { method: "POST", body: { reason: text(form, "reason") } });
    return "Compte bloqué : ses sessions sont coupées.";
  });
}

export async function unblockUser(userId: string) {
  return run(async () => {
    await api(`/admin/users/${userId}/unblock`, { method: "POST", body: {} });
    return "Compte débloqué.";
  });
}

export async function revokeDevice(userId: string, deviceId: string) {
  return run(async () => {
    await api(`/admin/users/${userId}/devices/${deviceId}/revoke`, { method: "POST", body: {} });
    return "Appareil révoqué.";
  });
}

export async function unlockPin(userId: string) {
  return run(async () => {
    await api(`/admin/users/${userId}/unlock-pin`, { method: "POST", body: {} });
    return "PIN débloqué : la personne peut réessayer tout de suite.";
  });
}

export async function approvePinReset(requestId: string, _: ActionState, form: FormData) {
  return run(async () => {
    await api(`/admin/pin-resets/${requestId}/approve`, { method: "POST", body: { note: text(form, "note") } });
    return "Nouveau PIN validé : la personne peut se connecter. Ses tontines voient cette validation dans leur journal.";
  });
}

export async function addNote(userId: string, closes: string | null, _: ActionState, form: FormData) {
  return run(async () => {
    await api(`/admin/users/${userId}/notes`, {
      method: "POST",
      body: { body: text(form, "body"), followUp: form.get("followUp") === "on", closes },
    });
    return closes ? "Suivi clos." : "Note ajoutée.";
  });
}

export async function resendSms(notificationId: string) {
  return run(async () => {
    const r = await api<{ status: "sent" | "failed" }>(`/admin/notifications/${notificationId}/resend`, {
      method: "POST",
      body: {},
    });
    if (r.status === "failed") return { error: "Nouvel échec d'envoi : vérifiez le numéro ou le fournisseur SMS." };
    return "Rappel renvoyé.";
  });
}

export async function suspendGroup(groupId: string, _: ActionState, form: FormData) {
  return run(async () => {
    await api(`/admin/groups/${groupId}/suspend`, { method: "POST", body: { reason: text(form, "reason") } });
    return "Tontine suspendue. Les membres le voient dans leur historique.";
  });
}

export async function reactivateGroup(groupId: string) {
  return run(async () => {
    await api(`/admin/groups/${groupId}/reactivate`, { method: "POST", body: {} });
    return "Tontine réactivée.";
  });
}

export async function decideDispute(disputeId: string, _: ActionState, form: FormData) {
  return run(async () => {
    const decision = text(form, "decision") === "reject" ? "reject" : "note";
    await api(`/admin/disputes/${disputeId}/decide`, { method: "POST", body: { decision, note: text(form, "note") } });
    return decision === "reject"
      ? "Déclaration rejetée : le payeur peut en faire une nouvelle."
      : "Avis ajouté au litige.";
  });
}

export async function verifyChain(_: ActionState, form: FormData) {
  return run(async () => {
    const r = await api<{ intact: boolean; events: number; firstInvalidSeq: string | null }>("/admin/audit/verify", {
      method: "POST",
      body: { chainId: text(form, "chainId") },
    });
    if (!r.intact) throw new ApiError(409, `Chaîne CASSÉE à partir de l'événement n°${r.firstInvalidSeq}. Alertez immédiatement.`);
    return `Chaîne intacte : ${r.events} événements vérifiés, aucun modifié ni supprimé.`;
  });
}

export async function createStaff(_: ActionState, form: FormData) {
  return run(async () => {
    const r = await api<{ email: string; temporaryPassword: string; totpSecret: string; otpauthUrl: string }>(
      "/admin/staff",
      { method: "POST", body: { email: text(form, "email"), fullName: text(form, "fullName"), role: text(form, "role") } },
    );
    return {
      ok: `Compte créé pour ${r.email}.`,
      credentials: {
        email: r.email,
        temporaryPassword: r.temporaryPassword,
        totpSecret: r.totpSecret,
        qr: await QRCode.toDataURL(r.otpauthUrl, { margin: 1, width: 220 }),
      },
    };
  });
}

export async function updateStaff(staffId: string, _: ActionState, form: FormData) {
  return run(async () => {
    const body: { role?: string; isActive?: boolean } = {};
    if (form.has("role")) body.role = text(form, "role");
    if (form.has("isActive")) body.isActive = text(form, "isActive") === "true";
    await api(`/admin/staff/${staffId}`, { method: "POST", body });
    return "Compte mis à jour.";
  });
}

export async function changePassword(_: ActionState, form: FormData) {
  return run(async () => {
    if (text(form, "next") !== text(form, "confirm")) throw new ApiError(400, "Les deux nouveaux mots de passe diffèrent.");
    await api("/admin/me/password", { method: "POST", body: { current: form.get("current"), next: form.get("next") } });
    return "Mot de passe changé.";
  });
}
