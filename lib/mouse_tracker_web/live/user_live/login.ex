defmodule MouseTrackerWeb.UserLive.Login do
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Accounts

  @input_class "w-full rounded-[8px] border border-[#e7e9ee] bg-white px-3 py-2.5 text-[14px] text-[#0f1729] placeholder:text-[#98a2b3] focus:border-[#CC5500] focus:outline-none"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :input_class, @input_class)

    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <h1 class="text-lg font-semibold text-[#0f1729]">Log in</h1>
        <p class="mt-1.5 text-sm text-[#667085]">
          <%= if @current_scope do %>
            You need to reauthenticate to perform sensitive actions on your account.
          <% else %>
            Don't have an account? <.link
              navigate={~p"/users/register"}
              class="font-semibold text-[#CC5500] hover:underline"
              phx-no-format
            >Sign up</.link> for an account now.
          <% end %>
        </p>
      </div>

      <div
        :if={local_mail_adapter?()}
        class="mt-6 flex items-start gap-2.5 rounded-[8px] border border-[#e7e9ee] bg-[#f3f4f6] p-3 text-sm text-[#344054]"
      >
        <.icon name="hero-information-circle" class="size-5 shrink-0 text-[#8a93a3]" />
        <div>
          <p>You are running the local mail adapter.</p>

          <p>
            To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
          </p>
        </div>
      </div>

      <.form
        :let={f}
        for={@form}
        id="login_form_magic"
        action={~p"/users/log-in"}
        phx-submit="submit_magic"
        class="mt-6 space-y-4"
      >
        <.input
          readonly={!!@current_scope}
          field={f[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
          phx-mounted={JS.focus()}
          class={@input_class}
        />
        <.button class="w-full rounded-[8px] bg-[#CC5500] px-4 py-2.5 text-[13px] font-semibold text-white hover:bg-[#b34a00]">
          Log in with email <span aria-hidden="true">→</span>
        </.button>
      </.form>

      <div class="my-6 flex items-center gap-3 text-[11px] font-medium uppercase tracking-wide text-[#98a2b3]">
        <span class="h-px flex-1 bg-[#e7e9ee]"></span>
        or <span class="h-px flex-1 bg-[#e7e9ee]"></span>
      </div>

      <.form
        :let={f}
        for={@form}
        id="login_form_password"
        action={~p"/users/log-in"}
        phx-submit="submit_password"
        phx-trigger-action={@trigger_submit}
        class="space-y-4"
      >
        <.input
          readonly={!!@current_scope}
          field={f[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
          class={@input_class}
        />
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          autocomplete="current-password"
          spellcheck="false"
          class={@input_class}
        />
        <.button
          class="w-full rounded-[8px] bg-[#CC5500] px-4 py-2.5 text-[13px] font-semibold text-white hover:bg-[#b34a00]"
          name={@form[:remember_me].name}
          value="true"
        >
          Log in and stay logged in <span aria-hidden="true">→</span>
        </.button>

        <.button class="mt-2 w-full rounded-[8px] border border-[#e7e9ee] bg-white px-4 py-2.5 text-[13px] font-semibold text-[#344054] hover:border-[#CC5500]">
          Log in only this time
        </.button>
      </.form>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:mouse_tracker, MouseTracker.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
