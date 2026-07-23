defmodule MouseTrackerWeb.LocomoComponents do
  @moduledoc """
  Small presentational components shared across the Locomo domain screens
  (Experiments list/detail, Processing, Results). Pure Tailwind, matching the
  design handoff tokens — see CLAUDE.md Sprint 3.
  """
  use Phoenix.Component

  import MouseTrackerWeb.CoreComponents, only: [icon: 1]

  @doc """
  A status pill for a video or an experiment's aggregate status.

  Accepts `"done" | "processing" | "pending" | "error"`.
  """
  attr :status, :string, required: true

  def status_pill(%{status: "done"} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1.5 rounded-[20px] bg-[#fbeee4] px-2.5 py-1 text-[11.5px] font-semibold text-[#b34a00]">
      <span class="size-1.5 rounded-full bg-[#CC5500]"></span> Done
    </span>
    """
  end

  def status_pill(%{status: "processing"} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1.5 rounded-[20px] bg-[#eef1f4] px-2.5 py-1 text-[11.5px] font-semibold text-[#475467]">
      <span class="size-3 rounded-full border-[1.5px] border-[#475467] border-t-transparent locomo-spin"></span>
      Processing
    </span>
    """
  end

  def status_pill(%{status: "error"} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1.5 rounded-[20px] bg-[#fdecec] px-2.5 py-1 text-[11.5px] font-semibold text-[#b42318]">
      <span class="size-1.5 rounded-full bg-[#d92d20]"></span> Error
    </span>
    """
  end

  def status_pill(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1.5 rounded-[20px] bg-[#f2f4f7] px-2.5 py-1 text-[11.5px] font-semibold text-[#667085]">
      <span class="size-1.5 rounded-full bg-[#98a2b3]"></span> Pending
    </span>
    """
  end

  @doc "A large stat card (label + big mono value + optional unit/sub)."
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :unit, :string, default: nil
  attr :sub, :string, default: nil

  def stat_card(assigns) do
    ~H"""
    <div class="rounded-[13px] border border-[#e7e9ee] bg-white p-[18px] shadow-[0_1px_2px_rgba(16,24,40,.04)]">
      <div class="text-[10.5px] font-semibold uppercase tracking-wide text-[#8a93a3]">
        {@label}
      </div>
      
      <div class="mt-2 flex items-baseline gap-1">
        <span class="font-data text-[32px] font-semibold leading-none text-[#0f1729]">{@value}</span>
        <span :if={@unit} class="font-data text-[13px] text-[#98a2b3]">{@unit}</span>
      </div>
      
      <div :if={@sub} class="mt-1.5 text-[11.5px] text-[#8a93a3]">{@sub}</div>
    </div>
    """
  end

  @doc "A small round tile with an icon, used to head list rows."
  attr :icon, :string, default: "hero-beaker"
  attr :class, :string, default: ""

  def icon_tile(assigns) do
    ~H"""
    <div class={[
      "flex size-10 shrink-0 items-center justify-center rounded-[10px] bg-[#f2f4f7] text-[#667085]",
      @class
    ]}>
      <.icon name={@icon} class="size-5" />
    </div>
    """
  end

  @doc "A deterministic color for a subject dot, hashed from the subject id."
  def subject_color(id) when is_integer(id) do
    palette = ~w(#2563eb #059669 #CC5500 #7c3aed #db2777 #0891b2 #ca8a04 #4f46e5)
    Enum.at(palette, rem(id, length(palette)))
  end

  def subject_color(_), do: "#98a2b3"

  @doc """
  Hand-rolled inline-SVG line+dot chart overlaying one or more metric trend
  series across chronological sessions. No JS — hover tooltips use a native
  SVG `<title>` per point. Each series is `%{label:, color:, points:}`, with
  `points` already sorted chronologically (x-ascending) and pre-filtered for
  nil values.

  The X axis aligns by *index within each series* (1st session next to 1st
  session, 2nd next to 2nd...), not by calendar date — series may have
  different lengths (e.g. comparing subjects with a different number of
  sessions); a shorter series' polyline simply stops early instead of
  stretching to fill the width, which would misalign it against the others.
  """
  attr :series, :list, required: true
  attr :unit, :string, default: nil
  attr :width, :integer, default: 720
  attr :height, :integer, default: 220

  def trend_chart(assigns) do
    assigns =
      assign(assigns, :plotted, chart_series(assigns.series, assigns.width, assigns.height))

    ~H"""
    <svg viewBox={"0 0 #{@width} #{@height}"} class="w-full" role="img">
      <g :for={s <- @plotted}>
        <polyline
          :if={length(s.coords) > 1}
          points={Enum.map_join(s.coords, " ", fn c -> "#{c.x},#{c.y}" end)}
          fill="none"
          stroke={s.color}
          stroke-width="2"
        />
        <circle :for={{c, p} <- Enum.zip(s.coords, s.points)} cx={c.x} cy={c.y} r="4" fill={s.color}>
          <title>{s.label} — {p.label}: {p.value}{@unit && " #{@unit}"}</title>
        </circle>
      </g>
    </svg>
    """
  end

  defp chart_series(series, w, h) do
    all_values = series |> Enum.flat_map(& &1.points) |> Enum.map(& &1.value)
    {min_v, max_v} = if all_values == [], do: {0, 1}, else: Enum.min_max(all_values)
    # Flat values (or a single point) would divide by zero — draw a
    # mid-height line instead.
    range = if max_v == min_v, do: 1, else: max_v - min_v
    pad = 24
    # Every series shares the same X divisor (the longest one) so session
    # index `i` lands at the same X regardless of which series it belongs
    # to — using each series' own point count would misalign them whenever
    # they have different lengths.
    n_max = series |> Enum.map(&length(&1.points)) |> Enum.max(fn -> 1 end)

    Enum.map(series, fn s ->
      coords =
        s.points
        |> Enum.with_index()
        |> Enum.map(fn {p, i} ->
          x = if n_max == 1, do: w / 2, else: pad + i / (n_max - 1) * (w - 2 * pad)
          y = h - pad - (p.value - min_v) / range * (h - 2 * pad)
          %{x: Float.round(x, 1), y: Float.round(y, 1)}
        end)

      Map.put(s, :coords, coords)
    end)
  end
end
