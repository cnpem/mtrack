# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mouse_tracker, :scopes,
  user: [
    default: true,
    module: MouseTracker.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: MouseTracker.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :mouse_tracker,
  ecto_repos: [MouseTracker.Repo],
  generators: [timestamp_type: :utc_datetime]

# Keycloak / OpenID Connect — the only production login path.
#
# The `nil`s here are deliberate: a deployment that forgets to set the
# environment variables should fail loudly on the login screen ("Keycloak is not
# configured") instead of redirecting the user to a half-built authorization URL
# or, worse, booting with a hard-coded realm. `config/runtime.exs` fills these
# from the environment.
#
# `redirect_uri` / `post_logout_redirect_uri` are derived from the endpoint URL
# when left nil, which is correct for dev and for any deployment whose public
# URL matches the endpoint URL. Set them explicitly behind a proxy that rewrites
# host/scheme.
config :mouse_tracker, :oidc,
  issuer: nil,
  client_id: nil,
  client_secret: nil,
  scopes: "openid profile email",
  # Must match the client's "Client authentication" setting in Keycloak. Do not
  # leave this to oidcc's auto-negotiation: the realm advertises
  # private_key_jwt/client_secret_jwt for *every* client, so auto-negotiation
  # picks a method this confidential client is not configured for and every
  # request fails with 401 "Authentication failed.".
  client_auth_method: "client_secret_basic",
  redirect_uri: nil,
  post_logout_redirect_uri: nil,
  provider_name: MouseTracker.Auth.OIDC.ProviderConfiguration

# Which `MouseTracker.Auth.OIDCProvider` implementation to use. Swapped for a
# Mox mock in config/test.exs, so `mix test` never talks to an identity provider.
config :mouse_tracker, :oidc_provider, MouseTracker.Auth.OIDC

# Configure the endpoint
config :mouse_tracker, MouseTrackerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MouseTrackerWeb.ErrorHTML, json: MouseTrackerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MouseTracker.PubSub,
  live_view: [signing_salt: "jvqeM5Vw"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :mouse_tracker, MouseTracker.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  mouse_tracker: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  mouse_tracker: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :mouse_tracker, Oban,
  engine: Oban.Engines.Basic,
  repo: MouseTracker.Repo,
  queues: [video_processing: 4, maintenance: 1],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"@daily", MouseTracker.Workers.OrphanUploadCleanupWorker}
     ]}
  ]

config :mouse_tracker, :orphan_upload_max_age_hours, 24

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
