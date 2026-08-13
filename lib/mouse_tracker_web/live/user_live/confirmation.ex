defmodule MouseTrackerWeb.UserLive.Confirmation do
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <h1 class="text-lg font-semibold text-[#0f1729]">Welcome {@user.email}</h1>
      </div>

      <.form
        :if={!@user.confirmed_at}
        for={@form}
        id="confirmation_form"
        phx-mounted={JS.focus_first()}
        phx-submit="submit"
        action={~p"/users/log-in?_action=confirmed"}
        phx-trigger-action={@trigger_submit}
        class="mt-6"
      >
        <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
        <.button
          name={@form[:remember_me].name}
          value="true"
          phx-disable-with="Confirming..."
          class="w-full"
        >
          Confirm and stay logged in
        </.button>

        <.button variant="secondary_accent" phx-disable-with="Confirming..." class="mt-2 w-full">
          Confirm and log in only this time
        </.button>
      </.form>

      <.form
        :if={@user.confirmed_at}
        for={@form}
        id="login_form"
        phx-submit="submit"
        phx-mounted={JS.focus_first()}
        action={~p"/users/log-in"}
        phx-trigger-action={@trigger_submit}
        class="mt-6"
      >
        <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
        <%= if @current_scope do %>
          <.button phx-disable-with="Logging in..." class="w-full">
            Log in
          </.button>
        <% else %>
          <.button
            name={@form[:remember_me].name}
            value="true"
            phx-disable-with="Logging in..."
            class="w-full"
          >
            Keep me logged in on this device
          </.button>

          <.button variant="secondary_accent" phx-disable-with="Logging in..." class="mt-2 w-full">
            Log me in only this time
          </.button>
        <% end %>
      </.form>

      <p
        :if={!@user.confirmed_at}
        class="mt-6 rounded-[8px] border border-[#e7e9ee] bg-[#f3f4f6] p-3 text-sm text-[#344054]"
      >
        Tip: If you prefer passwords, you can enable them in the user settings.
      </p>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Magic link is invalid or it has expired.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
