defmodule MouseTrackerWeb.UserLive.Registration do
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Accounts
  alias MouseTracker.Accounts.User

  @input_class "w-full rounded-[8px] border border-[#e7e9ee] bg-white px-3 py-2.5 text-[14px] text-[#0f1729] placeholder:text-[#98a2b3] focus:border-[#CC5500] focus:outline-none"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :input_class, @input_class)

    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <h1 class="text-lg font-semibold text-[#0f1729]">Register for an account</h1>
        <p class="mt-1.5 text-sm text-[#667085]">
          Already registered?
          <.link navigate={~p"/users/log-in"} class="font-semibold text-[#CC5500] hover:underline">
            Log in
          </.link>
          to your account now.
        </p>
      </div>

      <.form
        for={@form}
        id="registration_form"
        action={~p"/users/log-in"}
        method="post"
        phx-trigger-action={@trigger_submit}
        phx-submit="save"
        phx-change="validate"
        class="mt-6 space-y-4"
      >
        <.input
          field={@form[:name]}
          type="text"
          label="Full name"
          autocomplete="name"
          required
          phx-mounted={JS.focus()}
          class={@input_class}
        />
        <.input
          field={@form[:institution]}
          type="text"
          label="Institution / Lab (optional)"
          autocomplete="organization"
          class={@input_class}
        />
        <.input
          field={@form[:email]}
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
          autocomplete="new-password"
          required
          class={@input_class}
        />
        <.input
          field={@form[:password_confirmation]}
          type="password"
          label="Confirm password"
          autocomplete="new-password"
          class={@input_class}
        />
        <.button phx-disable-with="Creating account..." class="w-full">
          Create an account
        </.button>
      </.form>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: MouseTrackerWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset =
      Accounts.change_user_registration(%User{}, %{},
        validate_unique: false,
        hash_password: false
      )

    {:ok, socket |> assign_form(changeset) |> assign(trigger_submit: false)}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, _user} ->
        {:noreply, assign(socket, trigger_submit: true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      Accounts.change_user_registration(%User{}, user_params,
        validate_unique: false,
        hash_password: false
      )

    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
