// Every AI function runs only for a signed-in person.
//
// The gateway is not the guard. Its JWT check refuses a forged token, but it
// lets any valid project key through, the publishable key included, as it
// always let the legacy anon JWT through: it proves the caller has the app,
// not that anyone signed in. On 21 Nov 2026 a call that carried only the
// publishable key ran, so anyone who pulled that key out of the app could
// spend the Gemini, OpenAI and ElevenLabs quota. So each function asks first.
//
// The bearer token is handed to Supabase Auth (`GET /auth/v1/user`), which
// checks the signature whatever key signed it, the expiry, and that the user
// still exists. That is one round trip inside the region, next to a model call
// that takes seconds. Cheap local checks run before it, so a missing header,
// the publishable key sent as a bearer, or an expired token never reach Auth.
//
// Anonymous users are refused too: anyone can mint one with the publishable
// key, so letting them in would reopen the hole the day anonymous sign-ins
// are switched on.
//
//   const auth = await requireUser(req);
//   if (!auth.ok) return auth.response;

export type AuthedUser = { id: string };

export type AuthResult =
  | { ok: true; user: AuthedUser }
  | { ok: false; response: Response };

export type AuthOptions = {
  /** Defaults to `globalThis.fetch`; injected by the tests. */
  fetch?: typeof fetch;
  /** Defaults to `Deno.env.get`; injected by the tests. */
  env?: (name: string) => string | undefined;
  /** Seconds since the epoch; injected by the tests. */
  now?: () => number;
};

function refuse(status: number, error: string): AuthResult {
  return {
    ok: false,
    response: new Response(JSON.stringify({ error }), {
      status,
      headers: { "Content-Type": "application/json" },
    }),
  };
}

/** The `Bearer` token of a request, if it has one. */
export function bearer(req: Request): string | undefined {
  const header = req.headers.get("Authorization") ?? "";
  const match = header.match(/^Bearer\s+(\S+)\s*$/i);
  return match?.[1];
}

/**
 * The claims of a JWT, read without checking the signature. Only for the
 * cheap refusals below; nothing is trusted on the strength of it.
 */
export function unverifiedClaims(token: string): Record<string, unknown> | undefined {
  const parts = token.split(".");
  if (parts.length !== 3 || parts.some((part) => !part)) return undefined;
  try {
    const base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
    const claims = JSON.parse(atob(padded));
    return claims && typeof claims === "object" && !Array.isArray(claims) ? claims : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Lets the request through only with the session of a real, signed-in user.
 * Refuses with 401 otherwise, and with 503 when Auth cannot be reached: a
 * check that fails open is no check.
 */
export async function requireUser(req: Request, options: AuthOptions = {}): Promise<AuthResult> {
  const env = options.env ?? ((name: string) => Deno.env.get(name));
  const doFetch = options.fetch ?? globalThis.fetch;
  const now = options.now ?? (() => Date.now() / 1000);

  const token = bearer(req);
  if (!token) return refuse(401, "sign in required");

  // A user session is a JWT for the `authenticated` role. The publishable key
  // is not a JWT at all, and a legacy anon or service key has no `sub`.
  const claims = unverifiedClaims(token);
  if (!claims || claims.role !== "authenticated" || typeof claims.sub !== "string") {
    return refuse(401, "sign in required");
  }
  if (claims.is_anonymous === true) return refuse(401, "sign in required");
  if (typeof claims.exp === "number" && claims.exp <= now()) {
    return refuse(401, "session expired");
  }

  const supabaseUrl = env("SUPABASE_URL");
  // The key Auth's gateway wants beside the token: the one the app sent, or
  // the project's own when a caller sent none. It identifies the project, it
  // proves nothing about the user.
  const apiKey = req.headers.get("apikey") ?? env("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !apiKey) return refuse(500, "function is not configured");

  let response: Response;
  try {
    response = await doFetch(`${supabaseUrl.replace(/\/+$/, "")}/auth/v1/user`, {
      headers: { apikey: apiKey, Authorization: `Bearer ${token}` },
    });
  } catch (error) {
    console.error(`auth check failed: ${error}`);
    return refuse(503, "could not check the session");
  }

  if (response.status >= 500) {
    await response.body?.cancel();
    console.error(`auth check failed: Auth returned ${response.status}`);
    return refuse(503, "could not check the session");
  }
  if (!response.ok) {
    await response.body?.cancel();
    return refuse(401, "sign in required");
  }

  let user: { id?: unknown; is_anonymous?: unknown };
  try {
    user = await response.json();
  } catch {
    return refuse(503, "could not check the session");
  }
  if (typeof user.id !== "string" || !user.id) return refuse(401, "sign in required");
  if (user.is_anonymous === true) return refuse(401, "sign in required");

  return { ok: true, user: { id: user.id } };
}
