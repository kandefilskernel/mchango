import "server-only";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

/** Adresse de l'API Mchango, vue depuis le serveur Next.js (jamais depuis le navigateur). */
export const API_URL = process.env.MCHANGO_API_URL ?? "http://localhost:3000";

/** Cookie de session de l'équipe : httpOnly (inaccessible au JavaScript du navigateur). */
export const SESSION_COOKIE = "mchango_staff";

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

function messageOf(body: unknown): string {
  if (body && typeof body === "object") {
    const b = body as { message?: unknown; errors?: { message?: string }[] };
    if (Array.isArray(b.errors) && b.errors[0]?.message) return b.errors[0].message;
    if (typeof b.message === "string") return b.message;
  }
  return "Erreur inattendue de l'API.";
}

/** Appel à l'API avec le jeton de la session. Session expirée → retour à la connexion. */
export async function api<T>(path: string, init: { method?: string; body?: unknown } = {}): Promise<T> {
  const token = (await cookies()).get(SESSION_COOKIE)?.value;
  if (!token) redirect("/login");
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, {
      method: init.method ?? "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        ...(init.body !== undefined ? { "Content-Type": "application/json" } : {}),
      },
      body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
      cache: "no-store",
    });
  } catch {
    throw new ApiError(0, "L'API Mchango ne répond pas. Est-elle démarrée ?");
  }
  const body = await res.json().catch(() => null);
  if (res.status === 401) redirect("/login?expired=1");
  if (!res.ok) throw new ApiError(res.status, messageOf(body));
  return body as T;
}

/** Connexion (sans jeton). */
export async function apiLogin(email: string, password: string, code: string) {
  const res = await fetch(`${API_URL}/admin/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, code }),
    cache: "no-store",
  }).catch(() => null);
  if (!res) throw new ApiError(0, "L'API Mchango ne répond pas. Est-elle démarrée ?");
  const body = await res.json().catch(() => null);
  if (!res.ok) throw new ApiError(res.status, messageOf(body));
  return body as { token: string; expiresIn: number; mustChangePassword: boolean; staff: Staff };
}

export type StaffRole = "super_admin" | "support" | "compliance" | "finance" | "read_only";

export interface Staff {
  id: string;
  email: string;
  fullName: string;
  role: StaffRole;
}

/** Mêmes règles que l'API (apps/api/src/admin/staff.guard.ts) : sert à n'afficher que les actions permises. */
export const CAN = {
  blockUsers: ["super_admin", "support", "compliance"] as StaffRole[],
  suspendGroups: ["super_admin", "compliance"] as StaffRole[],
  decideDisputes: ["super_admin", "compliance"] as StaffRole[],
  manageStaff: ["super_admin"] as StaffRole[],
};

export const currentStaff = () => api<Staff>("/admin/me");
