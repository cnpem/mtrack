# Keycloak (OpenID Connect)

MTrack does not store credentials. Every login goes through Keycloak, using the
OpenID Connect **authorization code** flow with PKCE on a confidential client.
This document covers: running a Keycloak locally for development, the exact realm
configuration, how to test the flow, and what changes when the institutional
Keycloak is upgraded.

> Short version: the login is the browser being redirected to Keycloak and
> back. MTrack only ever sees a signed ID token, and turns it into a normal
> local session (`users_tokens`), which is why no LiveView or route guard had to
> change.

## Why a local container first

The institutional Keycloak is on 17.x; the current line is 26.8. Everything that
matters for this integration changed in between (Quarkus distribution, admin
bootstrap env vars, admin console, user profile defaults), so developing against
26 and later swapping the issuer is much cheaper than debugging a 17-vs-26
difference during the migration window.

The local container is **development only**: the realm, test users and client
secret are committed on purpose so anyone gets an identical login environment
with one command.

## 1. Start Keycloak

```bash
podman compose -f docker-compose.keycloak.yml up -d
podman compose -f docker-compose.keycloak.yml logs -f keycloak
```

Without a compose provider, the equivalent plain podman command:

```bash
podman run -d --name mtrack-keycloak -p 8080:8080 \
  -e KC_BOOTSTRAP_ADMIN_USERNAME=admin \
  -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin \
  -v "$PWD/priv/keycloak:/opt/keycloak/data/import:ro,Z" \
  quay.io/keycloak/keycloak:26.8 \
  start-dev --import-realm --health-enabled=true
```

Notes:

- `:Z` on the volume is required with podman + SELinux (Fedora/RHEL); without it
  the container cannot read the realm file.
- `start-dev` means plain HTTP and no clustering. Never use it in production.
- `--import-realm` reads `/opt/keycloak/data/import` **only for realms that do
  not exist yet**. After editing `priv/keycloak/mtrack-realm.json`, recreate the
  container so the import runs again:

  ```bash
  podman compose -f docker-compose.keycloak.yml down -v
  podman compose -f docker-compose.keycloak.yml up -d
  ```

### If the container is already running without the import

`--import-realm` only runs at startup. If the container came up without it (the
realm answers `404`), either recreate it with `down -v` + `up -d`, or import the
same JSON through the Admin API — no restart needed:

```bash
TOKEN=$(curl -s -d "client_id=admin-cli&username=admin&password=admin&grant_type=password" \
  http://localhost:8080/realms/master/protocol/openid-connect/token \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['access_token'])")

curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:8080/admin/realms \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data-binary @priv/keycloak/mtrack-realm.json
# 201 = created
```

Careful: `PUT /admin/realms/{realm}` with the body of a `GET` **replaces** the
realm snapshot, including clients — it will silently undo client changes made
after the `GET`. Edit the client (`PUT /admin/realms/{realm}/clients/{id}`)
instead.

Wait until the realm answers (usually 10–30 s on first boot, it has to build
the database):

```bash
curl -sf http://localhost:8080/realms/mtrack/.well-known/openid-configuration \
  | jq -r .issuer
# http://localhost:8080/realms/mtrack
```

- Admin console: <http://localhost:8080/admin> — `admin` / `admin`
- Realm: **mtrack**

## 2. What the realm already contains

`priv/keycloak/mtrack-realm.json`:

| Item | Value |
|---|---|
| Client ID | `mtrack-web` |
| Client secret | `mtrack-dev-secret` |
| Type | confidential, standard flow, PKCE `S256` |
| Redirect URIs | `http://localhost:4000/users/auth/keycloak/callback`, `http://127.0.0.1:4000/...` |
| Post-logout URIs | `http://localhost:4000/users/log-in`, `http://127.0.0.1:4000/users/log-in` |
| User 1 | `pesquisador` / `mtrack-dev-123` (`pesquisador@example.org`) |
| User 2 | `pesquisador2` / `mtrack-dev-123` (`pesquisador2@example.org`) |

Both users have **Email verified = ON**. That matters: MTrack only *links* an
incoming identity to a pre-existing local account when the e-mail claim is
verified. A user created by hand in the console is **not** verified by default —
that is the most common "login works in Keycloak but MTrack refuses" cause.

Two users, not one, so you can check data isolation: everything in MTrack is
scoped by `user_id`, so signing in as `pesquisador2` must show an empty
experiment list.

## 3. Run the app against it

```bash
export KEYCLOAK_ISSUER="http://localhost:8080/realms/mtrack"
export KEYCLOAK_CLIENT_ID="mtrack-web"
export KEYCLOAK_CLIENT_SECRET="mtrack-dev-secret"

mix phx.server
```

`redirect_uri` and `post_logout_redirect_uri` are derived from
`MouseTrackerWeb.Endpoint`, so nothing else is needed locally. Only change
`KEYCLOAK_CLIENT_AUTH_METHOD` (default `client_secret_basic`) if the client is
configured for `client_secret_post` or `client_secret_jwt` — see §8. Set
`KEYCLOAK_REDIRECT_URI` / `KEYCLOAK_POST_LOGOUT_REDIRECT_URI` explicitly only
when the public URL differs from the endpoint URL (proxy, custom hostname).

Open <http://localhost:4000>, click **Continue with Keycloak**, sign in as
`pesquisador`. You are back in MTrack, signed in.

### Signing in without Keycloak (UI work)

When the realm is unreachable, in `dev` only:

```
http://localhost:4000/dev/login?email=demo@locomo.dev
```

That route is mounted inside the `:dev_routes` block, which `config/prod.exs`
never enables, so it does not exist in a release.

## 4. Manual test script

Run these in order; each one isolates a layer, so a failure tells you where the
problem is.

| # | Action | Expected | If it fails |
|---|---|---|---|
| 1 | `curl -s $KEYCLOAK_ISSUER/.well-known/openid-configuration \| jq -r .issuer` | the exact issuer | realm name wrong, or `KC_HOSTNAME` misconfigured |
| 2 | Open `http://localhost:8080/realms/mtrack/account` and sign in | Keycloak account page | wrong user/password → check **Events** in the realm |
| 3 | `/users/log-in` → **Continue with Keycloak** | Keycloak login page | `Invalid parameter: redirect_uri` means the registered URI does not match byte for byte |
| 4 | Sign in | back on `/experiments` | check the app log for `OIDC login failed (...)` |
| 5 | Sign out, sign in again | no password prompt | expected: the Keycloak SSO session survived the app logout |
| 6 | Sign in as `pesquisador2` | empty experiment list | you are reusing the same local user |

Where to look when nothing obvious happens:

- **Realm → Events** (admin console): `LOGIN`, `LOGIN_ERROR`, `CODE_TO_TOKEN_ERROR`
  with reason codes. This is the fastest way to tell a Keycloak problem from an
  app problem.
- **MTrack log**: the controller logs `OIDC login failed (request|callback): <reason>`
  and never logs the code, the tokens or the client secret.

## 5. Automated tests

The suite never talks to a Keycloak. `MouseTracker.Auth.OIDCProvider` is the seam
(same pattern as `PythonPortBehaviour`): production uses
`MouseTracker.Auth.OIDC`, tests use `MouseTracker.Auth.OIDCProviderMock` (Mox).

| Layer | What it covers | Where |
|---|---|---|
| Session/app | everything *after* login: LiveViews, contexts, PubSub — with `user_fixture()` + `log_in_user()` | the rest of `test/` |
| OIDC contract | `state`/`nonce` handling, token exchange failures, provisioning, linking policy, logout | `test/mouse_tracker_web/controllers/oidc_controller_test.exs`, `test/mouse_tracker/accounts_oidc_test.exs` |
| Real realm | the flow against the running container | manual, see §4 |

```bash
mix test
```

Adding a test for a new callback behaviour means stubbing one function:

```elixir
expect(MouseTracker.Auth.OIDCProviderMock, :exchange_code, fn code, flow ->
  {:ok, %{sub: "abc", issuer: "https://kc/realms/mtrack",
          email: "x@example.org", email_verified: true}}
end)
```

## 6. Identity model

`users` gained three columns (migration `add_oidc_identity_to_users`):

| Column | Meaning |
|---|---|
| `idp_issuer` | the realm issuer, e.g. `https://auth/realms/mtrack` |
| `idp_sub` | the OIDC subject — opaque, stable, never reused |
| `idp_username` | `preferred_username`, for display/diagnostics only |

`unique_index(:users, [:idp_issuer, :idp_sub])` is the identity. Lookups are
**always** by `(issuer, sub)`, never by e-mail, because e-mail is mutable.

Provisioning rules (`MouseTracker.Accounts.provision_user_from_oidc/1`):

- unknown `sub` → create a user, `confirmed_at` set, no `hashed_password`
- known `sub` → reuse the row and refresh `name` / `email` / `idp_username`
- unknown `sub` but the e-mail already exists locally:
  - `email_verified: true` **and** the local row is not linked yet → link it
    (this is how pre-Keycloak accounts survive the migration)
  - otherwise → `{:error, :email_in_use}`; the e-mail is never used to take over
    an account
- no e-mail at all → `{:error, :missing_email}` (the column is `NOT NULL`)

## 7. When the institutional Keycloak is upgraded

Nothing in the code changes. Only the three environment variables:

```bash
KEYCLOAK_ISSUER=https://auth-hpc-lnbio.cnpem.br/realms/<realm>
KEYCLOAK_CLIENT_ID=<client id>       # mtrack-web unless the admins say otherwise
KEYCLOAK_CLIENT_SECRET=<from the console>
# only if the public URL differs from the endpoint URL:
# KEYCLOAK_REDIRECT_URI=https://mtrack.example.org/users/auth/keycloak/callback
# KEYCLOAK_POST_LOGOUT_REDIRECT_URI=https://mtrack.example.org/users/log-in
```

Checklist for that day:

1. The realm's discovery document returns the **public** HTTPS issuer
   (`jq -r .issuer`). If it returns an internal hostname, `KC_HOSTNAME` is wrong
   on the Keycloak side — do not "fix" it in MTrack.
2. The client has both the production redirect URI and, if you keep developing
   against it, the `http://localhost:4000` one.
3. The app server can reach the issuer (same hostname the browser uses).
4. Every user who is expected to keep their data has a **verified** e-mail that
   matches their existing MTrack account, so the first login links instead of
   creating a duplicate. Users can check with
   `SELECT id, email, idp_sub FROM users;` before and after.
5. Existing accounts that never log in again keep working data-wise, but cannot
   authenticate — the local password flow is gone by design.

### Differences that matter for 17 → 26

| Topic | 17.x | 26.x |
|---|---|---|
| Admin bootstrap | `KEYCLOAK_ADMIN` / `KEYCLOAK_ADMIN_PASSWORD` | `KC_BOOTSTRAP_ADMIN_USERNAME` / `..._PASSWORD` |
| Distribution | Quarkus (17 was the first) | Quarkus, different defaults |
| Admin console | old console | new `admin-ui` |
| User profile | first/last name optional | declarative profile, names **required** by default |
| `end_session_endpoint` | present | present (federated logout works on both) |

Only the first row affects the container command; the rest are console-only.

## 8. Troubleshooting

**`Invalid parameter: redirect_uri`** — the URI sent by the app is not in the
client's *Valid redirect URIs*. It must match exactly: same scheme, same host
(`localhost` ≠ `127.0.0.1`), no trailing slash.

**`401 {"error":"invalid_request","error_description":"Authentication failed."}`** —
the client authenticated with a method it is not configured for. `oidcc` picks
the first entry of the realm's `token_endpoint_auth_methods_supported`, which
Keycloak advertises as `private_key_jwt, client_secret_basic, client_secret_post,
tls_client_auth, client_secret_jwt` **for every client**, regardless of how this
one is configured. Left alone it negotiates `client_secret_jwt`, which a plain
`client-secret` client does not accept. MTrack therefore pins
`preferred_auth_methods` from `KEYCLOAK_CLIENT_AUTH_METHOD`
(default `client_secret_basic`). This shows up on the **PAR** or token endpoint,
not on the browser redirect.

**`Metadata load failed for issuer ... {:invalid_config_property, {:uri_https, :userinfo_endpoint}}`** —
`oidcc` refuses provider metadata whose endpoints are not HTTPS, and `start-dev`
advertises `http://localhost:8080/...`. MTrack enables `allow_unsafe_http`
automatically **only** when the configured issuer is itself plain HTTP; an
`https://` issuer keeps full validation. If you see this with an `https://`
issuer, the realm is publishing the wrong scheme (check `KC_HOSTNAME`).

**The application shuts down at boot with `Application mouse_tracker exited`** —
the provider worker crash-looped. Every `backoff_type` `oidcc` accepts is either
`:stop` (gives up immediately) or retries forever; an invalid atom raises
`FunctionClauseError` inside the worker, which the application supervisor then
restarts until it gives up and takes the app with it. `mix test
test/mouse_tracker/auth/config_test.exs` guards this.

**`OIDC login failed (callback): :state_mismatch`** — the browser came back
without the session cookie written by `/users/auth/keycloak`. Usually the app was
restarted mid-flow (which invalidates the session) or the user opened the callback
in another browser/tab. Just start over.

**`OIDC login failed (callback): {:token_exchange, ...}`** — the code was
rejected: expired, already used, PKCE verifier mismatch, or a wrong client
secret. Check realm **Events** → `CODE_TO_TOKEN_ERROR`.

**`Keycloak sign-in is not configured on this server`** — `KEYCLOAK_ISSUER`,
`KEYCLOAK_CLIENT_ID` or `KEYCLOAK_CLIENT_SECRET` is blank; the login screen lists
exactly which ones.

**Signing out signs you straight back in** — the Keycloak SSO session is still
alive. MTrack calls `end_session_endpoint` on logout; without an `id_token_hint`
Keycloak shows a confirmation page first. That is expected behaviour, not a bug.

**A deleted/renamed user in Keycloak keeps working in MTrack** — MTrack holds a
local session (`users_tokens`, 14 days with remember-me). Deleting the user in
Keycloak does not revoke it; delete the MTrack user or its tokens if you need
immediate revocation.
