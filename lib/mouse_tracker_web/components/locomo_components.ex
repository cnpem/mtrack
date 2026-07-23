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
  series across chronological sessions. Per-point hover uses a native SVG
  `<title>`; hovering anywhere else over the plot area snaps to the nearest
  session and shows a small tooltip listing every series' value at that
  session, via a JS hook (`TrendChartHover`,
  `assets/js/hooks/trend_chart_hover.js`) that draws a vertical guide line and
  positions an HTML tooltip from a `data-sessions` JSON blob — no charting
  library, the hook only reads `data-*` attributes on the wrapping element.
  Each series is `%{label:, color:, points:}`, with `points` already sorted
  chronologically (x-ascending) and pre-filtered for nil values.

  The X axis aligns by *index within each series* (1st session next to 1st
  session, 2nd next to 2nd...), not by calendar date — series may have
  different lengths (e.g. comparing subjects with a different number of
  sessions); a shorter series' polyline simply stops early instead of
  stretching to fill the width, which would misalign it against the others.
  """
  attr :id, :string, required: true
  attr :series, :list, required: true
  attr :unit, :string, default: nil
  attr :width, :integer, default: 720
  attr :height, :integer, default: 220

  def trend_chart(assigns) do
    assigns = assign(assigns, :chart, build_chart(assigns.series, assigns.width, assigns.height))

    ~H"""
    <div
      id={@id}
      phx-hook="TrendChartHover"
      class="relative"
      data-width={@width}
      data-height={@height}
      data-pad-left={@chart.pad_left}
      data-pad-right={@chart.pad_right}
      data-pad-top={@chart.pad_top}
      data-pad-bottom={@chart.pad_bottom}
      data-unit={@unit}
      data-sessions={Jason.encode!(@chart.sessions)}
    >
      <svg viewBox={"0 0 #{@width} #{@height}"} class="w-full" role="img">
        <g :for={tick <- @chart.y_ticks}>
          <line
            x1={@chart.pad_left}
            y1={tick.y}
            x2={@width - @chart.pad_right}
            y2={tick.y}
            stroke="#f4f5f7"
            stroke-width="1"
          />
          <text
            x={@chart.pad_left - 6}
            y={tick.y + 3}
            text-anchor="end"
            font-size="10"
            fill="#98a2b3"
          >
            {tick.label}
          </text>
        </g>

        <text :if={@unit} x={@chart.pad_left} y="11" font-size="10" fill="#98a2b3">{@unit}</text>

        <line
          x1={@chart.pad_left}
          y1={@chart.pad_top}
          x2={@chart.pad_left}
          y2={@height - @chart.pad_bottom}
          stroke="#e7e9ee"
          stroke-width="1"
        />
        <line
          x1={@chart.pad_left}
          y1={@height - @chart.pad_bottom}
          x2={@width - @chart.pad_right}
          y2={@height - @chart.pad_bottom}
          stroke="#e7e9ee"
          stroke-width="1"
        />

        <text
          :for={tick <- @chart.x_ticks}
          x={tick.x}
          y={@height - @chart.pad_bottom + 14}
          text-anchor="middle"
          font-size="10"
          fill="#98a2b3"
        >
          {tick.label}
        </text>

        <g :for={s <- @chart.series}>
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
    </div>
    """
  end

  @y_tick_count 4
  @max_x_labels 6

  defp build_chart(series, w, h) do
    all_values = series |> Enum.flat_map(& &1.points) |> Enum.map(& &1.value)
    {min_v, max_v} = if all_values == [], do: {0, 1}, else: Enum.min_max(all_values)
    # Flat values (or a single point) would divide by zero — draw a
    # mid-height line instead.
    range = if max_v == min_v, do: 1, else: max_v - min_v

    pad_left = 34
    pad_right = 10
    pad_top = 16
    pad_bottom = 22

    # Every series shares the same X divisor (the longest one) so session
    # index `i` lands at the same X regardless of which series it belongs
    # to — using each series' own point count would misalign them whenever
    # they have different lengths.
    n_max = series |> Enum.map(&length(&1.points)) |> Enum.max(fn -> 1 end)

    to_x = fn i ->
      if n_max <= 1, do: w / 2, else: pad_left + i / (n_max - 1) * (w - pad_left - pad_right)
    end

    to_y = fn value ->
      h - pad_bottom - (value - min_v) / range * (h - pad_top - pad_bottom)
    end

    plotted =
      Enum.map(series, fn s ->
        coords =
          s.points
          |> Enum.with_index()
          |> Enum.map(fn {p, i} ->
            %{x: Float.round(to_x.(i), 1), y: Float.round(to_y.(p.value), 1)}
          end)

        Map.put(s, :coords, coords)
      end)

    decimals = tick_decimals(range)

    %{
      series: plotted,
      pad_left: pad_left,
      pad_right: pad_right,
      pad_top: pad_top,
      pad_bottom: pad_bottom,
      min: min_v * 1.0,
      max: max_v * 1.0,
      decimals: decimals,
      y_ticks: y_ticks(min_v, max_v, decimals, to_y),
      x_ticks: x_ticks(n_max, to_x),
      sessions: sessions(series, n_max, to_x)
    }
  end

  # One entry per session index, carrying every series' value at that index
  # (skipping series that don't have a point there — they may be shorter),
  # for the hover crosshair's multi-series tooltip.
  defp sessions(series, n_max, to_x) do
    for i <- 0..(n_max - 1) do
      entries =
        for s <- series, i < length(s.points) do
          p = Enum.at(s.points, i)
          %{label: s.label, color: s.color, point_label: p.label, value: to_string(p.value)}
        end

      %{x: Float.round(to_x.(i), 1), entries: entries}
    end
  end

  # Just enough decimals to stay legible for narrow ranges (e.g. thigmotaxis
  # fractions) without cluttering wide ones (e.g. distance in cm).
  defp tick_decimals(range) do
    cond do
      range == 0 -> 0
      range >= 100 -> 0
      range >= 10 -> 1
      true -> 2
    end
  end

  # `@y_tick_count` evenly-spaced values from min to max (min/max always
  # included).
  defp y_ticks(min_v, max_v, decimals, to_y) do
    range = max_v - min_v

    for i <- 0..(@y_tick_count - 1) do
      value = if range == 0, do: min_v, else: min_v + i / (@y_tick_count - 1) * range

      %{
        y: Float.round(to_y.(value), 1),
        label: :erlang.float_to_binary(value * 1.0, decimals: decimals)
      }
    end
  end

  # Session-index labels (1-based) under each plotted point, thinned out to
  # at most `@max_x_labels` so they don't overlap when there are many sessions.
  defp x_ticks(n_max, to_x) when n_max > 0 do
    step = max(1, ceil(n_max / @max_x_labels))

    indices =
      0
      |> Stream.iterate(&(&1 + step))
      |> Enum.take_while(&(&1 < n_max))

    indices = if List.last(indices) == n_max - 1, do: indices, else: indices ++ [n_max - 1]

    Enum.map(indices, &%{x: Float.round(to_x.(&1), 1), label: to_string(&1 + 1)})
  end

  defp x_ticks(_n_max, _to_x), do: []
end
