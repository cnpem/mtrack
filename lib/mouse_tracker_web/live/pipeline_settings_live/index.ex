defmodule MouseTrackerWeb.PipelineSettingsLive.Index do
  @moduledoc """
  Pipeline settings (`/pipeline-settings`): per-user defaults for new
  calibrations (threshold/min area, used to prefill step 2 of the upload
  wizard — see `ExperimentLive.New.default_cal/1`), plus a resource library to
  rename or delete the reusable Calibration/ROI/Subject records. Until this
  screen, Calibration had no UI of its own at all (only created inline in the
  wizard), and ROI/Subject were only reachable from a specific video or
  experiment.

  Deleting a Calibration/Subject still attached to a video is blocked: both
  FKs are `on_delete: :nilify_all`, so the DB wouldn't reject the delete —
  it would silently null the video's reference, breaking things like Results'
  `group_by_calibration/1`. Same idea for ROI (`videos_rois`), stricter than
  `roi_locked?/1` (which only cares about done/processing videos, for the
  different purpose of freezing geometry edits in `RoiEdit`).
  """
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Accounts
  alias MouseTracker.Experiments

  @tabs [{"calibrations", "Calibrations"}, {"rois", "ROIs"}, {"subjects", "Subjects"}]

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    user = scope.user

    calibrations = Experiments.list_calibrations(scope)
    rois = Experiments.list_rois(scope)
    subjects = Experiments.list_subjects(scope)

    {:ok,
     socket
     |> assign(:page_title, "Pipeline settings")
     |> assign(:query, "")
     |> assign(:calibrations, calibrations)
     |> assign(:rois, rois)
     |> assign(:subjects, subjects)
     |> assign(
       :calibration_usage,
       usage_map(calibrations, &Experiments.count_videos_using_calibration/1)
     )
     |> assign(:roi_usage, usage_map(rois, &Experiments.count_videos_using_roi/1))
     |> assign(:subject_usage, usage_map(subjects, &Experiments.count_videos_using_subject/1))
     |> assign(:defaults_form, to_form(Accounts.change_user_pipeline_defaults(user)))}
  end

  defp usage_map(resources, count_fn), do: Map.new(resources, &{&1.id, count_fn.(&1)})

  @impl true
  def handle_params(params, _uri, socket) do
    tab =
      if params["tab"] in ~w(calibrations rois subjects), do: params["tab"], else: "calibrations"

    {:noreply, socket |> assign(:tab, tab) |> assign_derived()}
  end

  defp assign_derived(socket) do
    %{tab: tab, query: query} = socket.assigns
    q = query |> String.trim() |> String.downcase()

    resources =
      case tab do
        "calibrations" -> socket.assigns.calibrations
        "rois" -> socket.assigns.rois
        "subjects" -> socket.assigns.subjects
      end

    visible =
      Enum.filter(resources, fn r ->
        q == "" or String.contains?(String.downcase(r.name || ""), q)
      end)

    assign(socket, :visible, visible)
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/pipeline-settings?#{[tab: tab]}")}
  end

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> assign_derived()}
  end

  def handle_event("rename_calibration", %{"id" => id, "value" => name}, socket) do
    rename(
      socket,
      :calibrations,
      &Experiments.get_calibration!/2,
      &Experiments.update_calibration/3,
      id,
      name
    )
  end

  def handle_event("rename_roi", %{"id" => id, "value" => name}, socket) do
    rename(socket, :rois, &Experiments.get_roi!/2, &Experiments.update_roi/3, id, name)
  end

  def handle_event("rename_subject", %{"id" => id, "value" => name}, socket) do
    rename(
      socket,
      :subjects,
      &Experiments.get_subject!/2,
      &Experiments.update_subject/3,
      id,
      name
    )
  end

  def handle_event("update_subject_sex", %{"subject_id" => id, "value" => sex}, socket) do
    update_subject_field(socket, id, %{sex: normalize_blank(sex)})
  end

  def handle_event("update_subject_genotype", %{"id" => id, "value" => genotype}, socket) do
    update_subject_field(socket, id, %{genotype: normalize_blank(genotype)})
  end

  def handle_event("delete_calibration", %{"id" => id}, socket) do
    delete(
      socket,
      :calibrations,
      :calibration_usage,
      &Experiments.get_calibration!/2,
      &Experiments.delete_calibration/2,
      id,
      "Calibration"
    )
  end

  def handle_event("delete_roi", %{"id" => id}, socket) do
    delete(
      socket,
      :rois,
      :roi_usage,
      &Experiments.get_roi!/2,
      &Experiments.delete_roi/2,
      id,
      "ROI"
    )
  end

  def handle_event("delete_subject", %{"id" => id}, socket) do
    delete(
      socket,
      :subjects,
      :subject_usage,
      &Experiments.get_subject!/2,
      &Experiments.delete_subject/2,
      id,
      "Subject"
    )
  end

  def handle_event("duplicate_roi", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    roi = Experiments.get_roi!(scope, id)

    case Experiments.duplicate_roi(scope, roi) do
      {:ok, duplicate} ->
        socket =
          socket
          |> update(:rois, &(&1 ++ [duplicate]))
          |> update(:roi_usage, &Map.put(&1, duplicate.id, 0))
          |> assign_derived()
          |> put_flash(:info, "Duplicated as \"#{duplicate.name}\".")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not duplicate ROI.")}
    end
  end

  def handle_event("validate_defaults", %{"user" => params}, socket) do
    form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_pipeline_defaults(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :defaults_form, form)}
  end

  def handle_event("save_defaults", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_pipeline_defaults(user, params) do
      {:ok, updated_user} ->
        socket =
          socket
          |> assign(:defaults_form, to_form(Accounts.change_user_pipeline_defaults(updated_user)))
          |> put_flash(:info, "Pipeline defaults saved.")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :defaults_form, to_form(changeset, action: :insert))}
    end
  end

  defp rename(socket, assign_key, get_fn, update_fn, id, name) do
    scope = socket.assigns.current_scope
    resource = get_fn.(scope, id)

    case update_fn.(scope, resource, %{name: name}) do
      {:ok, updated} ->
        socket =
          socket
          |> update(assign_key, &replace(&1, updated))
          |> assign_derived()

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, rename_error(changeset))}
    end
  end

  defp replace(list, %{id: id} = updated),
    do: Enum.map(list, &if(&1.id == id, do: updated, else: &1))

  defp update_subject_field(socket, id, attrs) do
    scope = socket.assigns.current_scope
    subject = Experiments.get_subject!(scope, id)

    case Experiments.update_subject(scope, subject, attrs) do
      {:ok, updated} ->
        {:noreply, socket |> update(:subjects, &replace(&1, updated)) |> assign_derived()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update subject.")}
    end
  end

  defp normalize_blank(""), do: nil
  defp normalize_blank(value), do: value

  defp rename_error(changeset) do
    case changeset.errors[:name] do
      {msg, opts} -> "Name #{translate_error({msg, opts})}"
      nil -> "Could not rename."
    end
  end

  defp delete(socket, assign_key, usage_key, get_fn, delete_fn, id, label) do
    scope = socket.assigns.current_scope
    resource = get_fn.(scope, id)
    usage = Map.get(socket.assigns[usage_key], resource.id, 0)

    if usage > 0 do
      msg = "#{label} is attached to #{usage} video(s) — remove it from those videos first."
      {:noreply, put_flash(socket, :error, msg)}
    else
      {:ok, _} = delete_fn.(scope, resource)

      socket =
        socket
        |> update(assign_key, fn list -> Enum.reject(list, &(&1.id == resource.id)) end)
        |> update(usage_key, &Map.delete(&1, resource.id))
        |> assign_derived()
        |> put_flash(:info, "#{label} deleted.")

      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.locomo
      flash={@flash}
      current_scope={@current_scope}
      active={:settings}
      breadcrumb="Locomo"
      page_title="Pipeline settings"
    >
      <div class="mx-auto max-w-[1100px]">
        <div>
          <h1 class="text-[24px] font-bold text-[#0f1729]">Pipeline settings</h1>
          <p class="mt-1 text-[13px] text-[#667085]">
            Defaults for new calibrations, and a library to rename or clean up your reusable calibrations, ROIs and subjects.
          </p>
        </div>

        <.defaults_card form={@defaults_form} />

        <div class="mt-8 flex flex-wrap items-center justify-between gap-3">
          <div class="inline-flex items-center gap-1 rounded-[9px] border border-[#e7e9ee] bg-white p-1">
            <button
              :for={{value, label} <- tabs()}
              type="button"
              phx-click="switch_tab"
              phx-value-tab={value}
              class={[
                "rounded-[6px] px-3 py-1.5 text-[12.5px] font-medium transition-colors",
                @tab == value && "bg-[#0f1729] text-white",
                @tab != value && "text-[#667085] hover:text-[#0f1729]"
              ]}
            >
              {label}
            </button>
          </div>

          <.search_input id="pipeline-settings-search" query={@query} placeholder="Search by name" />
        </div>

        <.empty_state
          :if={@visible == []}
          class="mt-4"
          icon="hero-archive-box"
          title={if @query != "", do: "No matches", else: "No #{empty_noun(@tab)} yet"}
          subtitle={
            if @query != "",
              do: "Try a different search.",
              else:
                "Created from the upload wizard's step 2 (ROI & scale) and step 3 (review) — reuse them across experiments."
          }
        />

        <.calibration_table
          :if={@tab == "calibrations" and @visible != []}
          calibrations={@visible}
          usage={@calibration_usage}
        />
        <.roi_table :if={@tab == "rois" and @visible != []} rois={@visible} usage={@roi_usage} />
        <.subject_table
          :if={@tab == "subjects" and @visible != []}
          subjects={@visible}
          usage={@subject_usage}
        />
      </div>
    </Layouts.locomo>
    """
  end

  attr :form, :any, required: true

  defp defaults_card(assigns) do
    ~H"""
    <div class="mt-5 rounded-[13px] border border-[#e7e9ee] bg-white p-[18px] shadow-[0_1px_2px_rgba(16,24,40,.04)]">
      <h2 class="text-[15px] font-bold text-[#0f1729]">Pipeline defaults</h2>
      <p class="mt-1 text-[12.5px] text-[#667085]">
        Prefill threshold and min area on step 2 of the upload wizard. Leave a field blank to fall back to the built-in default (threshold 80, min area 250).
      </p>

      <.form
        for={@form}
        id="pipeline-defaults-form"
        phx-change="validate_defaults"
        phx-submit="save_defaults"
        class="mt-4 grid grid-cols-2 gap-3 sm:max-w-md"
      >
        <label class="block">
          <span class="text-[11px] text-[#667085]">Default threshold</span>
          <input
            type="number"
            name={@form[:default_threshold].name}
            value={@form[:default_threshold].value}
            class="mt-1 w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2.5 py-1.5 font-data text-[12.5px] text-[#0f1729] focus:border-[#CC5500] focus:outline-none"
          />
          <span
            :if={msg = field_error(@form[:default_threshold])}
            class="mt-1 block text-[11px] text-[#b42318]"
          >
            {msg}
          </span>
        </label>

        <label class="block">
          <span class="text-[11px] text-[#667085]">Default min area</span>
          <input
            type="number"
            name={@form[:default_min_area].name}
            value={@form[:default_min_area].value}
            class="mt-1 w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2.5 py-1.5 font-data text-[12.5px] text-[#0f1729] focus:border-[#CC5500] focus:outline-none"
          />
          <span
            :if={msg = field_error(@form[:default_min_area])}
            class="mt-1 block text-[11px] text-[#b42318]"
          >
            {msg}
          </span>
        </label>

        <div class="col-span-2">
          <button
            type="submit"
            class="inline-flex items-center gap-1.5 rounded-[8px] bg-[#CC5500] px-3.5 py-2 text-[12.5px] font-semibold text-white hover:bg-[#b34a00]"
          >
            Save defaults
          </button>
        </div>
      </.form>
    </div>
    """
  end

  attr :calibrations, :list, required: true
  attr :usage, :map, required: true

  defp calibration_table(assigns) do
    ~H"""
    <div class="mt-4 overflow-x-auto rounded-[13px] border border-[#e7e9ee] bg-white shadow-[0_1px_2px_rgba(16,24,40,.04)]">
      <table class="w-full min-w-[700px] text-left text-[12.5px]">
        <thead>
          <tr class="border-b border-[#f4f5f7] text-[10.5px] font-semibold uppercase tracking-wide text-[#98a2b3]">
            <th class="px-[18px] py-3">Name</th>
            <th class="px-3 py-3">px / 10cm</th>
            <th class="px-3 py-3">Threshold</th>
            <th class="px-3 py-3">Min area</th>
            <th class="px-3 py-3">Used in</th>
            <th class="px-[18px] py-3 text-right"></th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={cal <- @calibrations}
            class="border-b border-[#f4f5f7] last:border-0 hover:bg-[#fafbfc]"
          >
            <td class="px-[18px] py-3">
              <.rename_input event="rename_calibration" id={cal.id} name={cal.name} />
            </td>
            <td class="px-3 py-3 font-data text-[12px] text-[#344054]">{fmt(cal.px_per_10cm)}</td>
            <td class="px-3 py-3 font-data text-[12px] text-[#344054]">{cal.threshold}</td>
            <td class="px-3 py-3 font-data text-[12px] text-[#344054]">{cal.min_area}</td>
            <td class="px-3 py-3 font-data text-[12px] text-[#344054]">
              {usage_label(usage_count(@usage, cal.id))}
            </td>
            <td class="px-[18px] py-3 text-right">
              <.delete_button
                event="delete_calibration"
                id={cal.id}
                usage={usage_count(@usage, cal.id)}
                label="calibration"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :rois, :list, required: true
  attr :usage, :map, required: true

  defp roi_table(assigns) do
    ~H"""
    <div class="mt-4 overflow-x-auto rounded-[13px] border border-[#e7e9ee] bg-white shadow-[0_1px_2px_rgba(16,24,40,.04)]">
      <table class="w-full min-w-[600px] text-left text-[12.5px]">
        <thead>
          <tr class="border-b border-[#f4f5f7] text-[10.5px] font-semibold uppercase tracking-wide text-[#98a2b3]">
            <th class="px-[18px] py-3">Name</th>
            <th class="px-3 py-3">Shape</th>
            <th class="px-3 py-3">Used in</th>
            <th class="px-[18px] py-3 text-right"></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={roi <- @rois} class="border-b border-[#f4f5f7] last:border-0 hover:bg-[#fafbfc]">
            <td class="px-[18px] py-3">
              <.rename_input event="rename_roi" id={roi.id} name={roi.name} />
            </td>
            <td class="px-3 py-3 font-data text-[12px] capitalize text-[#344054]">{roi.shape}</td>
            <td class="px-3 py-3 font-data text-[12px] text-[#344054]">
              {usage_label(usage_count(@usage, roi.id))}
            </td>
            <td class="px-[18px] py-3 text-right">
              <div class="flex items-center justify-end gap-3">
                <button
                  type="button"
                  phx-click="duplicate_roi"
                  phx-value-id={roi.id}
                  class="text-[12px] font-medium text-[#475467] hover:text-[#0f1729]"
                >
                  Duplicate
                </button>
                <.delete_button
                  event="delete_roi"
                  id={roi.id}
                  usage={usage_count(@usage, roi.id)}
                  label="ROI"
                />
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :subjects, :list, required: true
  attr :usage, :map, required: true

  defp subject_table(assigns) do
    ~H"""
    <div class="mt-4 overflow-x-auto rounded-[13px] border border-[#e7e9ee] bg-white shadow-[0_1px_2px_rgba(16,24,40,.04)]">
      <table class="w-full min-w-[700px] text-left text-[12.5px]">
        <thead>
          <tr class="border-b border-[#f4f5f7] text-[10.5px] font-semibold uppercase tracking-wide text-[#98a2b3]">
            <th class="px-[18px] py-3">Name</th>
            <th class="px-3 py-3">Sex</th>
            <th class="px-3 py-3">Genotype</th>
            <th class="px-3 py-3">Used in</th>
            <th class="px-[18px] py-3 text-right"></th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={subject <- @subjects}
            class="border-b border-[#f4f5f7] last:border-0 hover:bg-[#fafbfc]"
          >
            <td class="px-[18px] py-3">
              <.rename_input event="rename_subject" id={subject.id} name={subject.name} />
            </td>
            <td class="px-3 py-3">
              <.sex_select id={subject.id} value={subject.sex} />
            </td>
            <td class="px-3 py-3">
              <.text_field_input
                event="update_subject_genotype"
                id={subject.id}
                value={subject.genotype}
              />
            </td>
            <td class="px-3 py-3 font-data text-[12px] text-[#344054]">
              {usage_label(usage_count(@usage, subject.id))}
            </td>
            <td class="px-[18px] py-3 text-right">
              <.delete_button
                event="delete_subject"
                id={subject.id}
                usage={usage_count(@usage, subject.id)}
                label="subject"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :event, :string, required: true
  attr :id, :integer, required: true
  attr :name, :string, required: true

  defp rename_input(assigns) do
    ~H"""
    <input
      type="text"
      name="value"
      value={@name}
      phx-blur={@event}
      phx-value-id={@id}
      class="w-full min-w-[140px] rounded-[6px] border border-transparent bg-transparent px-1.5 py-1 font-data text-[12.5px] font-medium text-[#0f1729] hover:border-[#e7e9ee] focus:border-[#CC5500] focus:bg-white focus:outline-none"
    />
    """
  end

  attr :event, :string, required: true
  attr :id, :integer, required: true
  attr :value, :string, default: nil

  defp text_field_input(assigns) do
    ~H"""
    <input
      type="text"
      name="value"
      value={@value}
      phx-blur={@event}
      phx-value-id={@id}
      placeholder="—"
      class="w-full min-w-[110px] rounded-[6px] border border-transparent bg-transparent px-1.5 py-1 font-data text-[12px] text-[#344054] hover:border-[#e7e9ee] focus:border-[#CC5500] focus:bg-white focus:outline-none"
    />
    """
  end

  attr :id, :integer, required: true
  attr :value, :string, default: nil

  defp sex_select(assigns) do
    ~H"""
    <form id={"subject-sex-#{@id}"} phx-change="update_subject_sex">
      <input type="hidden" name="subject_id" value={@id} />
      <select
        name="value"
        class="w-full min-w-[64px] rounded-[6px] border border-transparent bg-transparent px-1.5 py-1 font-data text-[12px] text-[#344054] hover:border-[#e7e9ee] focus:border-[#CC5500] focus:bg-white focus:outline-none"
      >
        <option value="" selected={@value in [nil, ""]}>—</option>
        <option value="M" selected={@value == "M"}>M</option>
        <option value="F" selected={@value == "F"}>F</option>
      </select>
    </form>
    """
  end

  attr :event, :string, required: true
  attr :id, :integer, required: true
  attr :usage, :integer, required: true
  attr :label, :string, required: true

  defp delete_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@usage == 0 && @event}
      phx-value-id={@id}
      disabled={@usage > 0}
      data-confirm={@usage == 0 && "Delete this #{@label}? This cannot be undone."}
      title={@usage > 0 && "Attached to #{@usage} video(s) — remove it from those videos first."}
      class={[
        "text-[12px] font-medium",
        @usage > 0 && "cursor-not-allowed text-[#cbd2dc]",
        @usage == 0 && "text-[#b42318] hover:text-[#912018]"
      ]}
    >
      Delete
    </button>
    """
  end

  defp empty_noun("calibrations"), do: "calibrations"
  defp empty_noun("rois"), do: "ROIs"
  defp empty_noun("subjects"), do: "subjects"

  defp tabs, do: @tabs

  defp usage_count(usage, id), do: Map.get(usage, id, 0)

  defp usage_label(0), do: "—"
  defp usage_label(1), do: "1 video"
  defp usage_label(n), do: "#{n} videos"

  defp field_error(%Phoenix.HTML.FormField{} = field) do
    if Phoenix.Component.used_input?(field) and field.errors != [] do
      field.errors |> Enum.map(&translate_error/1) |> Enum.join(", ")
    end
  end
end
