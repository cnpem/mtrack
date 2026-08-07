defmodule MouseTrackerWeb.LocomoComponents do
  @moduledoc """
  Small presentational components shared across the Locomo domain screens
  (Experiments list/detail, Processing, Results). Pure Tailwind, matching the
  design handoff tokens — see CLAUDE.md Sprint 3.
  """
  use Phoenix.Component

  import MouseTrackerWeb.CoreComponents, only: [icon: 1]
  import MouseTrackerWeb.Formatters, only: [stat_fmt: 1, fmt: 1]

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

  @doc """
  One `stat_card` per entry in `fields`, each formatted with `stat_fmt/1` from
  a subject metric aggregate (`Experiments.Reporting.subject_metric_aggregate/1`'s
  `:metrics` map) — the "mean ± SD" stat-card grid hand-rolled independently on
  the Results "Por subject" tab and the Datasets library's per-subject preview.
  Callers keep their own metric subset/order (Results shows all 7; Datasets'
  preview shows a smaller 4-metric summary) via `fields`, a list of
  `%{key:, label:, unit:, sub:}` (`unit`/`sub` optional).
  """
  attr :metrics, :map, required: true
  attr :fields, :list, required: true
  attr :class, :string, default: "grid grid-cols-2 gap-4 lg:grid-cols-4"

  def metric_stat_cards(assigns) do
    ~H"""
    <div class={@class}>
      <.stat_card
        :for={field <- @fields}
        label={field.label}
        value={stat_fmt(Map.fetch!(@metrics, field.key))}
        unit={field[:unit]}
        sub={field[:sub]}
      />
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
  A deterministic color for a subject `group`, hashed from the label — a
  muted/dark palette that reads as distinct from the brighter `subject_color/1`
  dots. `nil`/blank (no group) is neutral gray.
  """
  def group_color(name) when name in [nil, ""], do: "#98a2b3"

  def group_color(name) do
    palette = ~w(#111827 #92400e #065f46 #5b21b6 #9d174d)
    Enum.at(palette, :erlang.phash2(name, length(palette)))
  end

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

  @doc """
  Hand-rolled inline-SVG box plot: one box per category along the X axis, the
  metric on Y. Each box draws Tukey whiskers, the interquartile box (translucent
  fill in the category color), a **solid median line**, a **dashed mean line**,
  outlier circles, and the underlying data points jittered on top (points with a
  `:label` also get a small text label + `<title>` tooltip — the "named dots" of
  the per-group view). No charting library and no JS hook: tooltips are native
  SVG `<title>`.

  `categories` is `[%{label:, color:, box:, points:}]` where `box` is a
  `Reporting.boxplot_stats/1` map (non-nil) and each point is
  `%{label: string | nil, value: number}` (with a `:exp` field optionally folded
  into the tooltip). `log1p` rescales the Y axis with `log(1 + v)` (tick labels
  stay in original units) to tame heavy-tailed metrics.
  """
  attr :id, :string, required: true
  attr :categories, :list, required: true
  attr :unit, :string, default: nil
  attr :width, :integer, default: 720
  attr :height, :integer, default: 260
  attr :log1p, :boolean, default: false

  def box_plot(assigns) do
    assigns =
      assign(
        assigns,
        :chart,
        build_box_chart(assigns.categories, assigns.width, assigns.height, assigns.log1p)
      )

    ~H"""
    <div id={@id} class="relative">
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
          <text x={@chart.pad_left - 6} y={tick.y + 3} text-anchor="end" font-size="10" fill="#98a2b3">
            {tick.label}
          </text>
        </g>

        <text :if={@unit} x={@chart.pad_left} y="11" font-size="10" fill="#98a2b3">
          {if @log1p, do: "#{@unit} (log1p)", else: @unit}
        </text>

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

        <g :for={b <- @chart.boxes}>
          <!-- whisker stem + caps -->
          <line
            x1={b.cx}
            y1={b.y_whisker_low}
            x2={b.cx}
            y2={b.y_whisker_high}
            stroke={b.color}
            stroke-width="1"
          />
          <line
            x1={b.cx - b.box_w * 0.25}
            y1={b.y_whisker_low}
            x2={b.cx + b.box_w * 0.25}
            y2={b.y_whisker_low}
            stroke={b.color}
            stroke-width="1"
          />
          <line
            x1={b.cx - b.box_w * 0.25}
            y1={b.y_whisker_high}
            x2={b.cx + b.box_w * 0.25}
            y2={b.y_whisker_high}
            stroke={b.color}
            stroke-width="1"
          />
          <!-- IQR box -->
          <rect
            x={b.cx - b.box_w / 2}
            y={b.y_q3}
            width={b.box_w}
            height={max(b.y_q1 - b.y_q3, 0.5)}
            fill={b.color}
            fill-opacity="0.15"
            stroke={b.color}
            stroke-width="1.5"
          />
          <!-- median (solid) -->
          <line
            x1={b.cx - b.box_w / 2}
            y1={b.y_median}
            x2={b.cx + b.box_w / 2}
            y2={b.y_median}
            stroke={b.color}
            stroke-width="2"
          />
          <!-- mean (dashed) -->
          <line
            x1={b.cx - b.box_w / 2}
            y1={b.y_mean}
            x2={b.cx + b.box_w / 2}
            y2={b.y_mean}
            stroke={b.color}
            stroke-width="1.5"
            stroke-dasharray="3 2"
          />
          <!-- outliers -->
          <circle
            :for={o <- b.outliers}
            cx={b.cx}
            cy={o.y}
            r="2"
            fill="none"
            stroke={b.color}
            stroke-width="1"
          />
          <!-- data points -->
          <g :for={p <- b.points}>
            <circle cx={p.x} cy={p.y} r="3" fill={b.color} fill-opacity="0.85">
              <title>{p.tooltip}</title>
            </circle>
            <text :if={p.label} x={p.x + 5} y={p.y + 3} font-size="9" fill="#475467">{p.label}</text>
          </g>

          <text
            x={b.cx}
            y={@height - @chart.pad_bottom + 15}
            text-anchor="middle"
            font-size="10.5"
            fill="#475467"
          >
            {b.label}
          </text>
        </g>
      </svg>
    </div>
    """
  end

  defp build_box_chart(categories, w, h, log1p) do
    tf = value_transform(log1p)
    inv = value_inverse(log1p)

    drawn =
      categories
      |> Enum.flat_map(fn c ->
        [c.box.min, c.box.max, c.box.mean | Enum.map(c.points, & &1.value)]
      end)
      |> Enum.map(tf)

    {min_t, max_t} = if drawn == [], do: {0.0, 1.0}, else: Enum.min_max(drawn)
    span = if max_t == min_t, do: 1.0, else: max_t - min_t
    min_t = min_t - span * 0.06
    max_t = max_t + span * 0.06
    range = max_t - min_t

    pad_left = 44
    pad_right = 12
    pad_top = 12
    pad_bottom = 34

    n = length(categories)
    slot_w = if n > 0, do: (w - pad_left - pad_right) / n, else: 0.0
    box_w = min(46.0, slot_w * 0.5)

    to_y_t = fn t -> h - pad_bottom - (t - min_t) / range * (h - pad_top - pad_bottom) end
    to_y = fn value -> to_y_t.(tf.(value)) end
    center_x = fn i -> pad_left + slot_w * (i + 0.5) end

    boxes =
      categories
      |> Enum.with_index()
      |> Enum.map(fn {c, i} ->
        cx = center_x.(i)
        b = c.box

        pts =
          c.points
          |> Enum.with_index()
          |> Enum.map(fn {p, j} ->
            %{
              x: Float.round(cx + jitter_offset(j, box_w), 1),
              y: Float.round(to_y.(p.value), 1),
              label: p.label,
              tooltip: point_tooltip(p)
            }
          end)

        %{
          label: c.label,
          color: c.color,
          cx: Float.round(cx, 1),
          box_w: Float.round(box_w, 1),
          y_q1: Float.round(to_y.(b.q1), 1),
          y_q3: Float.round(to_y.(b.q3), 1),
          y_median: Float.round(to_y.(b.median), 1),
          y_mean: Float.round(to_y.(b.mean), 1),
          y_whisker_low: Float.round(to_y.(b.whisker_low), 1),
          y_whisker_high: Float.round(to_y.(b.whisker_high), 1),
          outliers: Enum.map(b.outliers, fn v -> %{y: Float.round(to_y.(v), 1), value: v} end),
          points: pts
        }
      end)

    %{
      boxes: boxes,
      pad_left: pad_left,
      pad_right: pad_right,
      pad_top: pad_top,
      pad_bottom: pad_bottom,
      y_ticks: box_y_ticks(min_t, max_t, inv, to_y_t)
    }
  end

  # log1p transform is safe for the (non-negative) locomotion metrics; the
  # `max(_, ...)` guard keeps `log/1` defined even if a value ever dips below 0.
  defp value_transform(true), do: fn v -> :math.log(max(1 + v, 1.0e-9)) end
  defp value_transform(false), do: fn v -> v * 1.0 end

  defp value_inverse(true), do: fn t -> :math.exp(t) - 1 end
  defp value_inverse(false), do: fn t -> t end

  # Deterministic horizontal spread so points in a category don't stack on one
  # vertical line (and re-render identically across patches).
  defp jitter_offset(j, box_w) do
    (:erlang.phash2(j, 1000) / 1000 - 0.5) * box_w * 0.7
  end

  defp point_tooltip(%{label: nil, value: value}), do: "#{fmt(value)}"

  defp point_tooltip(%{label: label, value: value} = p) do
    exp = if p[:exp], do: " · #{p.exp}", else: ""
    "#{label}#{exp}: #{fmt(value)}"
  end

  defp box_y_ticks(min_t, max_t, inv, to_y_t) do
    range = max_t - min_t
    decimals = tick_decimals(abs(inv.(max_t) - inv.(min_t)))

    for i <- 0..(@y_tick_count - 1) do
      t = if range == 0, do: min_t, else: min_t + i / (@y_tick_count - 1) * range

      %{
        y: Float.round(to_y_t.(t), 1),
        label: :erlang.float_to_binary(inv.(t) * 1.0, decimals: decimals)
      }
    end
  end
end
