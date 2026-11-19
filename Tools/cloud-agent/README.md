# Cloud Agent environment (Kohi backend)

Kohi's app is an iOS/SwiftUI target that only builds under Xcode on macOS, so it
cannot run in a Linux Cloud Agent VM. What *is* runnable here is the backend the
app talks to: the Postgres schema in `supabase/migrations` and the Deno edge
functions in `supabase/functions`. These scripts stand that backend up locally.

## Scripts

| Script | Lifecycle | Purpose |
| --- | --- | --- |
| `install.sh` | one-time install | Install Docker + `fuse-overlayfs` + the Supabase CLI, configure the daemon, and warm the Supabase image cache (also runs every migration once as a smoke test). |
| `dockerd-up.sh` | helper | Start `dockerd` and apply the two nested-container fixes (fuse-overlayfs storage driver, `bridge-nf-call-iptables=0` so containers on a bridge can reach each other). |
| `start.sh` | per boot | Start the daemon and run `supabase start`, applying all migrations. |

## What runs

`supabase start` brings up Postgres, PostgREST (REST API), GoTrue (Auth),
Storage, Studio, and Mailpit. `realtime` and `analytics` are disabled in
`supabase/config.toml` because the app does not use them and they add startup
contention under `fuse-overlayfs`.

Serve the edge functions with:

```sh
supabase functions serve --no-verify-jwt
```

The AI edge functions (`ask`, `card-vision`, `card-poster`, `field-extract`,
`recipe-adapt`, `suggested-correction`) call Google Gemini and need
`GEMINI_API_KEY` in the function environment to return model output; without it
they boot and return a `"... is not configured"` error, which is enough to
verify the runtime and request handling.

## Endpoints

- REST API: `http://127.0.0.1:54321/rest/v1`
- Auth: `http://127.0.0.1:54321/auth/v1`
- Edge functions: `http://127.0.0.1:54321/functions/v1`
- Studio: `http://127.0.0.1:54323`
