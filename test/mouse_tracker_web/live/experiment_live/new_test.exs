defmodule MouseTrackerWeb.ExperimentLive.NewTest do
  use MouseTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mox
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments
  alias MouseTracker.Tracking.PythonPortMock

  setup :register_and_log_in_user
  setup :verify_on_exit!

  test "renders the upload step first", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/experiments/new")

    assert html =~ "New experiment · Step 1 of 3"
    assert html =~ "Upload videos"
    assert html =~ ~s(multiple)
  end

  test "guards later steps back to upload when there are no files", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/experiments/new"}}} =
             live(conn, ~p"/experiments/new/roi")
  end

  describe "step 2 prefills threshold/min_area from the user's pipeline defaults" do
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

      html =
        lv
        |> element("button[phx-value-ref='#{ref}'][phx-click='toggle_cal_ref']")
        |> render_click()

      %{html: html}
    end

    test "uses the built-in 80/250 when the user has no custom defaults", %{html: html} do
      assert html =~ ~s(name="threshold" value="80")
      assert html =~ ~s(name="min_area" value="250")
    end

    test "uses the user's saved defaults instead", %{conn: conn, user: user} do
      {:ok, _user} =
        MouseTracker.Accounts.update_user_pipeline_defaults(user, %{
          default_threshold: 60,
          default_min_area: 400
        })

      {:ok, lv, _html} = live(conn, ~p"/experiments/new")

      tmp = Path.join(System.tmp_dir!(), "wizard-#{System.unique_integer([:positive])}.mp4")
      File.write!(tmp, "not a real video, just bytes for the upload input")

      video =
        file_input(lv, "form", :videos, [
          %{name: "b.mp4", content: File.read!(tmp), type: "video/mp4"}
        ])

      render_upload(video, "b.mp4")
      lv |> element("button", "Continue → ROI & scale") |> render_click()

      html = render(lv)
      [_, ref] = Regex.run(~r/phx-value-ref="([^"]+)"/, html)

      html =
        lv
        |> element("button[phx-value-ref='#{ref}'][phx-click='toggle_cal_ref']")
        |> render_click()

      assert html =~ ~s(name="threshold" value="60")
      assert html =~ ~s(name="min_area" value="400")
    end
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
      assert html =~ "missing a name"
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

      assert html =~ "The two scale measurements diverge"
    end

    test "does not show a divergence warning when the two segments agree within 8%", %{lv: lv} do
      html = render(lv)

      refute html =~ "The two scale measurements diverge"
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

  describe "step 2 — reference dropdown (batch)" do
    setup %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/experiments/new")

      tmp_a = Path.join(System.tmp_dir!(), "wizard-a-#{System.unique_integer([:positive])}.mp4")
      tmp_b = Path.join(System.tmp_dir!(), "wizard-b-#{System.unique_integer([:positive])}.mp4")
      File.write!(tmp_a, "video a bytes")
      File.write!(tmp_b, "video b bytes")

      video_a =
        file_input(lv, "form", :videos, [
          %{name: "a.mp4", content: File.read!(tmp_a), type: "video/mp4"}
        ])

      render_upload(video_a, "a.mp4")

      video_b =
        file_input(lv, "form", :videos, [
          %{name: "b.mp4", content: File.read!(tmp_b), type: "video/mp4"}
        ])

      render_upload(video_b, "b.mp4")

      lv |> element("button", "Continue → ROI & scale") |> render_click()

      ref_a = video_ref(lv, "a.mp4")
      ref_b = video_ref(lv, "b.mp4")

      # a.mp4 becomes the active video, then the calibration/ROI reference
      lv |> element("li[phx-value-ref='#{ref_a}']") |> render_click()

      lv
      |> element("button[phx-value-ref='#{ref_a}'][phx-click='toggle_cal_ref']")
      |> render_click()

      lv
      |> element("button[phx-value-ref='#{ref_a}'][phx-click='toggle_roi_ref']")
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

      render_hook(lv, "shape_drawn", %{
        "kind" => "roi_polygon",
        "points" => [1, 2, 10, 2, 10, 20, 1, 20]
      })

      # switch the active video to b.mp4, which starts without any reference
      lv |> element("li[phx-value-ref='#{ref_b}']") |> render_click()

      %{lv: lv, ref_a: ref_a, ref_b: ref_b}
    end

    test "picking a calibration reference in the dropdown resolves inheritance and unblocks Continue",
         %{lv: lv, ref_a: ref_a, ref_b: ref_b} do
      html = render(lv)
      assert html =~ "no reference"
      assert html =~ ~s(phx-value-step="review" disabled)

      lv
      |> form("form[phx-change='set_cal_source']", %{"ref" => ref_b, "source" => ref_a})
      |> render_change()

      html = render(lv)
      assert html =~ "inherits from a.mp4"
      refute html =~ ~s(phx-value-step="review" disabled)
    end

    test "picking a ROI reference in the dropdown resolves inheritance", %{
      lv: lv,
      ref_a: ref_a,
      ref_b: ref_b
    } do
      lv
      |> form("form[phx-change='set_cal_source']", %{"ref" => ref_b, "source" => ref_a})
      |> render_change()

      html = render(lv)
      assert html =~ "no reference"

      lv
      |> form("form[phx-change='set_roi_source']", %{"ref" => ref_b, "source" => ref_a})
      |> render_change()

      html = render(lv)
      assert html =~ "inherits from a.mp4"
      refute html =~ ~s(phx-value-step="review" disabled)
    end
  end

  describe "step 3 review — subject picker" do
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

      lv |> element("button[phx-value-step='review']") |> render_click()

      %{lv: lv, ref: ref}
    end

    test "defaults to creating a new subject named after the video", %{lv: lv, scope: scope} do
      html = render(lv)

      assert html =~ "+ New subject"
      refute html =~ "M-existing"

      stub_python_port_success()

      lv
      |> form("form[phx-submit='create']", %{"experiment_name" => "Solo run"})
      |> render_submit()

      assert length(Experiments.list_subjects(scope)) == 1
      assert [subject] = Experiments.list_subjects(scope)
      assert subject.name == "a"
    end
  end

  describe "step 3 review — reusing an existing subject" do
    setup %{conn: conn, user: user} do
      subject = subject_fixture(user, %{name: "M-existing"})

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

      lv |> element("button[phx-value-step='review']") |> render_click()

      %{lv: lv, ref: ref, subject: subject}
    end

    test "shows the existing subject in the dropdown and reuses it without duplicating", %{
      lv: lv,
      ref: ref,
      subject: subject,
      scope: scope
    } do
      html = render(lv)
      assert html =~ "M-existing"

      lv
      |> form("form[phx-submit='create']", %{"subject" => %{ref => to_string(subject.id)}})
      |> render_change()

      stub_python_port_success()

      lv
      |> form("form[phx-submit='create']", %{"experiment_name" => "Reuse run"})
      |> render_submit()

      assert length(Experiments.list_subjects(scope)) == 1

      [experiment] = Experiments.list_experiments(scope)
      [video] = Experiments.list_videos(experiment)
      assert video.subject_id == subject.id
    end
  end

  # The default active video (and the order @saved_videos ends up in) isn't
  # guaranteed to match upload call order, so look a video's ref up by its
  # filename in the "batch" list instead of assuming a position.
  defp video_ref(lv, filename) do
    html = lv |> element("li", filename) |> render()
    [_, ref] = Regex.run(~r/phx-value-ref="([^"]+)"/, html)
    ref
  end

  defp stub_python_port_success do
    PythonPortMock
    |> stub(:run, fn _params, _on_progress ->
      {:ok,
       %{
         "distance_px" => 100.0,
         "distance_cm" => 20.0,
         "speed_mean_px" => 5.0,
         "speed_mean_cm" => 1.0,
         "speed_median_px" => 4.0,
         "speed_median_cm" => 0.8
       }}
    end)
  end
end
