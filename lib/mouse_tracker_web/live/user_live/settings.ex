defmodule MouseTrackerWeb.UserLive.Settings do
  use MouseTrackerWeb, :live_view

  on_mount {MouseTrackerWeb.UserAuth, :require_sudo_mode}

  alias MouseTracker.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.locomo
      flash={@flash}
      current_scope={@current_scope}
      active={:account}
      breadcrumb="Account"
      page_title="Settings"
    >
      <div class="mx-auto max-w-xl space-y-4">
        <div class="rounded-2xl border border-[#e7e9ee] bg-white p-7 shadow-sm">
          <div class="text-center">
            <.header>
              Account Settings
              <:subtitle>Manage your profile details</:subtitle>
            </.header>
          </div>

          <.form
            for={@profile_form}
            id="profile_form"
            phx-submit="update_profile"
            phx-change="validate_profile"
            class="space-y-4"
          >
            <.input field={@profile_form[:name]} type="text" label="Full name" required />
            <.input field={@profile_form[:institution]} type="text" label="Institution / Lab" />
            <.button variant="primary" phx-disable-with="Saving...">Save profile</.button>
          </.form>
        </div>

        <div class="rounded-2xl border border-[#e7e9ee] bg-white p-7 shadow-sm">
          <h2 class="text-sm font-semibold text-[#0f1729]">Email and password</h2>
          <p class="mt-2 text-sm text-[#667085]">
            MTrack signs you in through Keycloak, so your e-mail address, password and
            two-factor settings are managed there — not here.
          </p>

          <p class="mt-3 text-sm text-[#667085]">
            Signed in as <span class="font-medium text-[#344054]">{@current_scope.user.email}</span>.
          </p>

          <.link
            :if={@account_url}
            href={@account_url}
            class="mt-4 inline-flex items-center gap-1.5 rounded-[8px] border border-[#e7e9ee] px-3 py-2 text-sm font-semibold text-[#344054] hover:bg-[#f3f4f6]"
          >
            Open Keycloak account console <span aria-hidden="true">→</span>
          </.link>
        </div>
      </div>
    </Layouts.locomo>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:profile_form, to_form(Accounts.change_user_profile(user)))
      |> assign(:account_url, MouseTracker.Auth.account_url())

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_profile", params, socket) do
    %{"user" => user_params} = params

    profile_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_profile(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, profile_form: profile_form)}
  end

  def handle_event("update_profile", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    case Accounts.update_user_profile(user, user_params) do
      {:ok, _user} ->
        {:noreply, put_flash(socket, :info, "Profile updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, profile_form: to_form(changeset, action: :insert))}
    end
  end
end
