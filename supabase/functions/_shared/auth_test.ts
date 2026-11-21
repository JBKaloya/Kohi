// deno test supabase/functions/_shared/

import { assertEquals } from "jsr:@std/assert@1";
import { bearer, requireUser, unverifiedClaims } from "./auth.ts";

const URL_ = "https://project.supabase.co";
const PUBLISHABLE = "sb_publishable_test";
const NOW = 1_800_000_000;

function base64url(value: unknown): string {
  return btoa(JSON.stringify(value)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** A JWT shaped like a Supabase session. The signature is not checked here: Auth checks it. */
function jwt(claims: Record<string, unknown>): string {
  return `${base64url({ alg: "ES256", typ: "JWT", kid: "k1" })}.${base64url(claims)}.c2lnbmF0dXJl`;
}

const session = (extra: Record<string, unknown> = {}) =>
  jwt({ sub: "user-1", role: "authenticated", aud: "authenticated", exp: NOW + 3600, ...extra });

function request(headers: Record<string, string>): Request {
  return new Request(`${URL_}/functions/v1/compare-summary`, { method: "POST", headers, body: "{}" });
}

type Call = { url: string; headers: Headers };

/** A stand-in for Auth that records what it was asked. */
function auth(reply: () => Response | Promise<Response>) {
  const calls: Call[] = [];
  const fetch = ((input: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(input), headers: new Headers(init?.headers) });
    return Promise.resolve(reply());
  }) as typeof globalThis.fetch;
  return { calls, fetch };
}

const env = (values: Record<string, string> = { SUPABASE_URL: URL_ }) => (name: string) => values[name];
const now = () => NOW;

async function status(result: Awaited<ReturnType<typeof requireUser>>): Promise<number> {
  if (result.ok) return 200;
  await result.response.body?.cancel();
  return result.response.status;
}

Deno.test("no Authorization header: 401 without asking Auth", async () => {
  const stub = auth(() => new Response("{}"));
  const result = await requireUser(request({ apikey: PUBLISHABLE }), { fetch: stub.fetch, env: env(), now });
  assertEquals(await status(result), 401);
  assertEquals(stub.calls.length, 0);
});

Deno.test("the publishable key as a bearer: 401 without asking Auth", async () => {
  const stub = auth(() => new Response("{}"));
  const result = await requireUser(
    request({ apikey: PUBLISHABLE, Authorization: `Bearer ${PUBLISHABLE}` }),
    { fetch: stub.fetch, env: env(), now },
  );
  assertEquals(await status(result), 401);
  assertEquals(stub.calls.length, 0);
});

Deno.test("a legacy anon key (role anon, no sub): 401 without asking Auth", async () => {
  const stub = auth(() => new Response("{}"));
  const anon = jwt({ role: "anon", iss: "supabase", exp: NOW + 3600 });
  const result = await requireUser(
    request({ apikey: anon, Authorization: `Bearer ${anon}` }),
    { fetch: stub.fetch, env: env(), now },
  );
  assertEquals(await status(result), 401);
  assertEquals(stub.calls.length, 0);
});

Deno.test("an anonymous user's token: 401 without asking Auth", async () => {
  const stub = auth(() => new Response("{}"));
  const result = await requireUser(
    request({ apikey: PUBLISHABLE, Authorization: `Bearer ${session({ is_anonymous: true })}` }),
    { fetch: stub.fetch, env: env(), now },
  );
  assertEquals(await status(result), 401);
  assertEquals(stub.calls.length, 0);
});

Deno.test("an expired session: 401 without asking Auth", async () => {
  const stub = auth(() => new Response("{}"));
  const result = await requireUser(
    request({ apikey: PUBLISHABLE, Authorization: `Bearer ${session({ exp: NOW - 1 })}` }),
    { fetch: stub.fetch, env: env(), now },
  );
  assertEquals(await status(result), 401);
  assertEquals(stub.calls.length, 0);
});

Deno.test("a session Auth accepts: through, with the user id", async () => {
  const token = session();
  const stub = auth(() => Response.json({ id: "user-1", is_anonymous: false }));
  const result = await requireUser(
    request({ apikey: PUBLISHABLE, Authorization: `Bearer ${token}` }),
    { fetch: stub.fetch, env: env({ SUPABASE_URL: `${URL_}/` }), now },
  );
  assertEquals(result.ok ? result.user : undefined, { id: "user-1" });
  assertEquals(stub.calls.length, 1);
  assertEquals(stub.calls[0].url, `${URL_}/auth/v1/user`);
  assertEquals(stub.calls[0].headers.get("Authorization"), `Bearer ${token}`);
  assertEquals(stub.calls[0].headers.get("apikey"), PUBLISHABLE);
});

Deno.test("without an apikey header, the project's anon key goes to Auth", async () => {
  const stub = auth(() => Response.json({ id: "user-1" }));
  const result = await requireUser(
    request({ Authorization: `Bearer ${session()}` }),
    { fetch: stub.fetch, env: env({ SUPABASE_URL: URL_, SUPABASE_ANON_KEY: "anon-from-env" }), now },
  );
  assertEquals(result.ok, true);
  assertEquals(stub.calls[0].headers.get("apikey"), "anon-from-env");
});

Deno.test("a forged session Auth refuses (403 bad_jwt): 401", async () => {
  const stub = auth(() => Response.json({ code: 403, error_code: "bad_jwt" }, { status: 403 }));
  const result = await requireUser(
    request({ apikey: PUBLISHABLE, Authorization: `Bearer ${session()}` }),
    { fetch: stub.fetch, env: env(), now },
  );
  assertEquals(await status(result), 401);
  assertEquals(stub.calls.length, 1);
});

Deno.test("a deleted user (Auth answers 401): 401", async () => {
  const stub = auth(() => Response.json({ code: 401 }, { status: 401 }));
  const result = await requireUser(
    request({ apikey: PUBLISHABLE, Authorization: `Bearer ${session()}` }),
    { fetch: stub.fetch, env: env(), now },
  );
  assertEquals(await status(result), 401);
});

Deno.test("Auth says the user is anonymous though the token did not: 401", async () => {
  const stub = auth(() => Response.json({ id: "user-1", is_anonymous: true }));
  const result = await requireUser(
    request({ apikey: PUBLISHABLE, Authorization: `Bearer ${session()}` }),
    { fetch: stub.fetch, env: env(), now },
  );
  assertEquals(await status(result), 401);
});

Deno.test("Auth down or unreachable: 503, never through", async () => {
  const down = auth(() => new Response("oops", { status: 502 }));
  assertEquals(
    await status(await requireUser(
      request({ apikey: PUBLISHABLE, Authorization: `Bearer ${session()}` }),
      { fetch: down.fetch, env: env(), now },
    )),
    503,
  );
  const unreachable = auth(() => Promise.reject(new TypeError("network")));
  assertEquals(
    await status(await requireUser(
      request({ apikey: PUBLISHABLE, Authorization: `Bearer ${session()}` }),
      { fetch: unreachable.fetch, env: env(), now },
    )),
    503,
  );
});

Deno.test("no SUPABASE_URL: 500, never through", async () => {
  const stub = auth(() => Response.json({ id: "user-1" }));
  const result = await requireUser(
    request({ apikey: PUBLISHABLE, Authorization: `Bearer ${session()}` }),
    { fetch: stub.fetch, env: env({}), now },
  );
  assertEquals(await status(result), 500);
  assertEquals(stub.calls.length, 0);
});

Deno.test("the refusal is JSON the app can read", async () => {
  const result = await requireUser(request({ apikey: PUBLISHABLE }), { env: env(), now });
  if (result.ok) throw new Error("let through");
  assertEquals(result.response.headers.get("Content-Type"), "application/json");
  assertEquals(await result.response.json(), { error: "sign in required" });
});

Deno.test("bearer reads the token, and nothing else", () => {
  const with_ = (value: string) => new Request(URL_, { headers: { Authorization: value } });
  assertEquals(bearer(with_("Bearer abc.def.ghi")), "abc.def.ghi");
  assertEquals(bearer(with_("bearer abc")), "abc");
  assertEquals(bearer(with_("Basic abc")), undefined);
  assertEquals(bearer(with_("Bearer ")), undefined);
  assertEquals(bearer(new Request(URL_)), undefined);
});

Deno.test("unverifiedClaims reads a JWT body and refuses what is not one", () => {
  assertEquals(unverifiedClaims(session())?.sub, "user-1");
  assertEquals(unverifiedClaims(PUBLISHABLE), undefined);
  assertEquals(unverifiedClaims("a.b.c"), undefined);
  assertEquals(unverifiedClaims(`x.${base64url([1, 2])}.y`), undefined);
  assertEquals(unverifiedClaims("a..c"), undefined);
});
