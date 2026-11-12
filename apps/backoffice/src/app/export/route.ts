import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { API_URL, SESSION_COOKIE } from "@/lib/api";

/**
 * Téléchargement d'un export CSV : relaie l'appel à l'API avec le jeton de la session
 * (le navigateur ne voit jamais le jeton). L'API vérifie le rôle et journalise l'export.
 */
export async function GET(request: Request) {
  const token = (await cookies()).get(SESSION_COOKIE)?.value;
  if (!token) redirect("/login");
  const params = new URL(request.url).searchParams;
  const query = new URLSearchParams({ kind: params.get("kind") ?? "" });
  if (params.get("chain")) query.set("chain", params.get("chain")!);
  const res = await fetch(`${API_URL}/admin/export?${query}`, {
    headers: { Authorization: `Bearer ${token}` },
    cache: "no-store",
  }).catch(() => null);
  if (!res) return new Response("L'API Mchango ne répond pas.", { status: 502 });
  if (res.status === 401) redirect("/login?expired=1");
  if (!res.ok) {
    const body = await res.json().catch(() => null);
    return new Response(body?.message ?? "Export impossible.", {
      status: res.status,
      headers: { "Content-Type": "text/plain; charset=utf-8" },
    });
  }
  return new Response(res.body, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": res.headers.get("Content-Disposition") ?? 'attachment; filename="mchango.csv"',
      "Cache-Control": "no-store",
    },
  });
}
