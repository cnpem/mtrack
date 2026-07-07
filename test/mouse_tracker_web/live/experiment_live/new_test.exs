defmodule MouseTrackerWeb.ExperimentLive.NewTest do
  use MouseTrackerWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders the upload step first", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/experiments/new")

    assert html =~ "New experiment · Step 1 of 3"
    assert html =~ "Upload videos"
    assert html =~ "Batch"
  end

  test "guards later steps back to upload when there are no files", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/experiments/new"}}} =
             live(conn, ~p"/experiments/new/roi")
  end

  describe "step 2 -> review" do
    setup %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/experiments/new")

      tmp = Path.join(System.tmp_dir!(), "wizard-#{System.unique_integer([:positive])}.mp4")
      File.write!(tmp, "not a real video, just bytes for the upload input")

      video =
        file_input(lv, "form", :videos, [
          %{name: "a.mp4", content: File.read!(tmp), type: "video/mp4"}
        ])

      render_upload(video, "a.mp4")
      lv |> element("button", "Continue → ROI & scale") |> render_click()

      html = render(lv)
      [_, ref] = Regex.run(~r/phx-value-ref="([^"]+)"/, html)

      lv
      |> element("button[phx-value-ref='#{ref}'][phx-click='toggle_cal_ref']")
      |> render_click()

      lv
      |> element("button[phx-value-ref='#{ref}'][phx-click='toggle_roi_ref']")
      |> render_click()

      render_hook(lv, "shape_drawn", %{
        "kind" => "valid_region",
        "x" => 0,
        "y" => 0,
        "w" => 100,
        "h" => 100
      })

      render_hook(lv, "shape_drawn", %{
        "kind" => "scale",
        "x1" => 0,
        "y1" => 0,
        "x2" => 50,
        "y2" => 0
      })

      lv
      |> form("form[phx-change='set_scale_cm']", %{"value" => "10"})
      |> render_change()

      render_hook(lv, "shape_drawn", %{
        "kind" => "scale2",
        "x1" => 0,
        "y1" => 10,
        "x2" => 40,
        "y2" => 10
      })

      lv
      |> form("form[phx-change='set_scale_cm2']", %{"value" => "8"})
      |> render_change()

      %{lv: lv, ref: ref}
    end

    test "a drawn ROI gets a default name so it does not block continuing", %{lv: lv} do
      render_hook(lv, "shape_drawn", %{
        "kind" => "roi_polygon",
        "points" => [1, 2, 10, 2, 10, 20, 1, 20]
      })

      html = render(lv)

      assert html =~ ~r/value="Zone 1"/
      refute html =~ ~s(phx-value-step="review" disabled)
    end

    test "calibration alone (no ROI) is enough to continue", %{lv: lv} do
      html = render(lv)

      refute html =~ ~s(phx-value-step="review" disabled)
    end

    test "shows why Continue is disabled when a ROI name is blanked out", %{lv: lv, ref: ref} do
      render_hook(lv, "shape_drawn", %{
        "kind" => "roi_polygon",
        "points" => [1, 2, 10, 2, 10, 20, 1, 20]
      })

      lv
      |> form("form[phx-change='set_roi_name']", %{"index" => "0", "value" => ""})
      |> render_change()

      html = render(lv)

      assert html =~ ~s(phx-value-step="review" disabled)
      assert html =~ "sem nome"
      refute ref == nil
    end

    test "averages the two scale segments into px_per_10cm", %{lv: lv} do
      html = render(lv)

      assert html =~ "px_per_10cm=50.0"
    end

    test "shows a divergence warning when the two segments disagree by more than 8%", %{lv: lv} do
      render_hook(lv, "shape_drawn", %{
        "kind" => "scale2",
        "x1" => 0,
        "y1" => 10,
        "x2" => 80,
        "y2" => 10
      })

      lv
      |> form("form[phx-change='set_scale_cm2']", %{"value" => "10"})
      |> render_change()

      html = render(lv)

      assert html =~ "As duas medidas de escala divergem"
    end

    test "does not show a divergence warning when the two segments agree within 8%", %{lv: lv} do
      html = render(lv)

      refute html =~ "As duas medidas de escala divergem"
    end
  end

  describe "step 2 requires both scale segments" do
    setup %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/experiments/new")

      tmp = Path.join(System.tmp_dir!(), "wizard-#{System.unique_integer([:positive])}.mp4")
      File.write!(tmp, "not a real video, just bytes for the upload input")

      video =
        file_input(lv, "form", :videos, [
          %{name: "a.mp4", content: File.read!(tmp), type: "video/mp4"}
        ])

      render_upload(video, "a.mp4")
      lv |> element("button", "Continue → ROI & scale") |> render_click()

      html = render(lv)
      [_, ref] = Regex.run(~r/phx-value-ref="([^"]+)"/, html)

      lv
      |> element("button[phx-value-ref='#{ref}'][phx-click='toggle_cal_ref']")
      |> render_click()

      render_hook(lv, "shape_drawn", %{
        "kind" => "valid_region",
        "x" => 0,
        "y" => 0,
        "w" => 100,
        "h" => 100
      })

      render_hook(lv, "shape_drawn", %{
        "kind" => "scale",
        "x1" => 0,
        "y1" => 0,
        "x2" => 50,
        "y2" => 0
      })

      lv
      |> form("form[phx-change='set_scale_cm']", %{"value" => "10"})
      |> render_change()

      %{lv: lv}
    end

    test "Continue stays disabled while the second segment is missing", %{lv: lv} do
      html = render(lv)

      assert html =~ ~s(phx-value-step="review" disabled)
    end
  end
end
