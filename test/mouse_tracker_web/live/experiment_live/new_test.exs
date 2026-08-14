defmodule MouseTrackerWeb.ExperimentLive.NewTest do
  use MouseTrackerWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mox
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments
  alias MouseTracker.Experiments.Subjects
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
        |> element("#ref-own-#{ref}")
        |> render_click()

      %{html: html}
    end

    test "uses the built-in 80/250/20/2 when the user has no custom defaults", %{html: html} do
      assert html =~ ~s(name="threshold" value="80")
      assert html =~ ~s(name="min_area" value="250")
      assert html =~ ~s(name="peripheral_pct" value="20")
      assert html =~ ~s(name="immobility_threshold_cm" value="2")
    end

    test "uses the user's saved defaults instead", %{conn: conn, user: user} do
      {:ok, _user} =
        MouseTracker.Accounts.update_user_pipeline_defaults(user, %{
          default_threshold: 60,
          default_min_area: 400,
          default_peripheral_pct: 15,
          default_immobility_threshold_cm: 3
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
        |> element("#ref-own-#{ref}")
        |> render_click()

      assert html =~ ~s(name="threshold" value="60")
      assert html =~ ~s(name="min_area" value="400")
      assert html =~ ~s(name="peripheral_pct" value="15.0")
      assert html =~ ~s(name="immobility_threshold_cm" value="3.0")
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
      |> element("#ref-own-#{ref}")
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
      refute has_element?(lv, ~s(button[phx-value-step="review"][disabled]))
    end

    test "calibration alone (no ROI) is enough to continue", %{lv: lv} do
      refute has_element?(lv, ~s(button[phx-value-step="review"][disabled]))
    end

    test "set_trim stores the analysis window (clamped) without blocking Continue",
         %{lv: lv, ref: ref} do
      render_hook(lv, "set_trim", %{"ref" => ref, "start" => "5", "end" => "30"})

      # The window is optional, so it never disables Continue.
      refute has_element?(lv, ~s(button[phx-value-step="review"][disabled]))

      # end <= start collapses to open-ended (nil == "to the end").
      render_hook(lv, "set_trim", %{"ref" => ref, "start" => "40", "end" => "20"})

      lv |> element("button", "Continue → Review") |> render_click()

      assert render(lv) =~ "0:40 → end"
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

      assert has_element?(lv, ~s(button[phx-value-step="review"][disabled]))
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

  describe "step 1 — reuse from library" do
    setup %{conn: conn, user: user} do
      source_experiment = experiment_fixture(user, %{name: "Cohort A"})
      subject = subject_fixture(user, %{name: "Mouse 7"})

      source_path =
        Path.join(System.tmp_dir!(), "library-src-#{System.unique_integer([:positive])}.mp4")

      File.write!(source_path, "source video bytes")

      source =
        video_fixture(source_experiment, nil, %{
          filename: "source.mp4",
          filepath: source_path,
          status: "done",
          subject_id: subject.id
        })

      %{source: source, subject: subject, source_path: source_path}
    end

    test "lists videos from the user's library and filters by search",
         %{conn: conn, source: source} do
      {:ok, lv, html} = live(conn, ~p"/experiments/new")

      assert html =~ "Reuse from your library"
      assert html =~ source.filename

      html = lv |> form("#library-search", %{query: "no-such-video"}) |> render_change()
      refute html =~ source.filename

      html = lv |> form("#library-search", %{query: "source"}) |> render_change()
      assert html =~ source.filename
    end

    test "adding a library video copies the file into an independent Video row, without touching the original",
         %{conn: conn, source: source, source_path: source_path} do
      {:ok, lv, _html} = live(conn, ~p"/experiments/new")

      lv |> element("#library-video-#{source.id}") |> render_click()
      html = lv |> element("#add-from-library-btn") |> render_click()

      assert html =~ source.filename
      assert html =~ "from library"
      # already added — the library list no longer offers it again
      refute has_element?(lv, "#library-video-#{source.id}")

      assert File.exists?(source_path)
    end

    test "the reused video keeps the source's subject and creates its own experiment/video row",
         %{conn: conn, source: source, subject: subject, source_path: source_path, scope: scope} do
      existing_experiment_ids =
        MapSet.new(Experiments.list_experiments(scope), & &1.id)

      {:ok, lv, _html} = live(conn, ~p"/experiments/new")

      lv |> element("#library-video-#{source.id}") |> render_click()
      lv |> element("#add-from-library-btn") |> render_click()

      lv |> element("button", "Continue → ROI & scale") |> render_click()

      html = render(lv)
      assert html =~ "Reused from"

      [_, ref] = Regex.run(~r/phx-value-ref="([^"]+)"/, html)

      lv |> element("#ref-own-#{ref}") |> render_click()

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

      lv |> form("form[phx-change='set_scale_cm']", %{"value" => "10"}) |> render_change()

      render_hook(lv, "shape_drawn", %{
        "kind" => "scale2",
        "x1" => 0,
        "y1" => 10,
        "x2" => 40,
        "y2" => 10
      })

      lv |> form("form[phx-change='set_scale_cm2']", %{"value" => "8"}) |> render_change()

      lv |> element("button[phx-value-step='review']") |> render_click()

      review_html = render(lv)
      assert review_html =~ ~s(value="#{subject.id}" selected)

      stub_python_port_success()

      lv
      |> form("form[phx-submit='create']", %{"experiment_name" => "Reused run"})
      |> render_submit()

      [experiment] =
        Enum.reject(Experiments.list_experiments(scope), &(&1.id in existing_experiment_ids))

      [new_video] = Experiments.list_videos(experiment)

      assert new_video.subject_id == subject.id
      assert new_video.id != source.id
      assert new_video.filepath != source.filepath
      assert File.exists?(new_video.filepath)
      assert File.exists?(source_path)

      # reused the existing subject instead of duplicating it
      assert length(Subjects.list_subjects(scope)) == 1
    end

    test "reusing multiple videos, each set as its own reference, combined with a fresh upload — all survive to the created experiment",
         %{conn: conn, user: user, scope: scope} do
      sources =
        for n <- 1..3 do
          path =
            Path.join(System.tmp_dir!(), "lib-src-#{n}-#{System.unique_integer([:positive])}.mp4")

          File.write!(path, "bytes #{n}")

          video_fixture(experiment_fixture(user, %{name: "Src exp #{n}"}), nil, %{
            filename: "lib#{n}.mp4",
            filepath: path,
            status: "done"
          })
        end

      existing_experiment_ids = MapSet.new(Experiments.list_experiments(scope), & &1.id)

      {:ok, lv, _html} = live(conn, ~p"/experiments/new")

      for s <- sources, do: lv |> element("#library-video-#{s.id}") |> render_click()
      lv |> element("#add-from-library-btn") |> render_click()

      tmp = Path.join(System.tmp_dir!(), "wizard-fresh-#{System.unique_integer([:positive])}.mp4")
      File.write!(tmp, "fresh upload bytes")

      video =
        file_input(lv, "form[phx-change=validate_upload]", :videos, [
          %{name: "fresh.mp4", content: File.read!(tmp), type: "video/mp4"}
        ])

      render_upload(video, "fresh.mp4")
      lv |> element("button", "Continue → ROI & scale") |> render_click()

      html = render(lv)

      refs =
        Regex.scan(~r/phx-value-ref="([^"]+)"/, html) |> Enum.map(&Enum.at(&1, 1)) |> Enum.uniq()

      assert length(refs) == 4

      for ref <- refs do
        render_click(lv, "select_active", %{"ref" => ref})
        render_click(lv, "toggle_ref", %{"ref" => ref})

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

        lv |> form("form[phx-change='set_scale_cm']", %{"value" => "10"}) |> render_change()

        render_hook(lv, "shape_drawn", %{
          "kind" => "scale2",
          "x1" => 0,
          "y1" => 10,
          "x2" => 40,
          "y2" => 10
        })

        lv |> form("form[phx-change='set_scale_cm2']", %{"value" => "8"}) |> render_change()
      end

      refute has_element?(lv, ~s(button[phx-value-step="review"][disabled]))
      lv |> element("button[phx-value-step='review']") |> render_click()

      stub_python_port_success()

      lv
      |> form("form[phx-submit='create']", %{"experiment_name" => "Combo run"})
      |> render_submit()

      [experiment] =
        Enum.reject(Experiments.list_experiments(scope), &(&1.id in existing_experiment_ids))

      assert Experiments.list_videos(experiment) |> Enum.map(& &1.filename) |> Enum.sort() ==
               ["fresh.mp4", "lib1.mp4", "lib2.mp4", "lib3.mp4"]
    end

    test "reusing multiple videos that inherit ROI/scale from one of the reused videos (no fresh upload)",
         %{conn: conn, user: user, scope: scope} do
      sources =
        for n <- 1..3 do
          path =
            Path.join(
              System.tmp_dir!(),
              "lib-src2-#{n}-#{System.unique_integer([:positive])}.mp4"
            )

          File.write!(path, "bytes #{n}")

          video_fixture(experiment_fixture(user, %{name: "Src2 exp #{n}"}), nil, %{
            filename: "lib2_#{n}.mp4",
            filepath: path,
            status: "done"
          })
        end

      existing_experiment_ids = MapSet.new(Experiments.list_experiments(scope), & &1.id)

      {:ok, lv, _html} = live(conn, ~p"/experiments/new")

      for s <- sources, do: lv |> element("#library-video-#{s.id}") |> render_click()
      lv |> element("#add-from-library-btn") |> render_click()

      lv |> element("button", "Continue → ROI & scale") |> render_click()

      html = render(lv)

      refs =
        Regex.scan(~r/phx-value-ref="([^"]+)"/, html) |> Enum.map(&Enum.at(&1, 1)) |> Enum.uniq()

      [ref_video | inherit_videos] = refs

      render_click(lv, "select_active", %{"ref" => ref_video})
      render_click(lv, "toggle_ref", %{"ref" => ref_video})

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

      lv |> form("form[phx-change='set_scale_cm']", %{"value" => "10"}) |> render_change()

      render_hook(lv, "shape_drawn", %{
        "kind" => "scale2",
        "x1" => 0,
        "y1" => 10,
        "x2" => 40,
        "y2" => 10
      })

      lv |> form("form[phx-change='set_scale_cm2']", %{"value" => "8"}) |> render_change()

      for ref <- inherit_videos do
        render_click(lv, "select_active", %{"ref" => ref})
        render_click(lv, "set_source", %{"ref" => ref, "source" => ref_video})
      end

      refute has_element?(lv, ~s(button[phx-value-step="review"][disabled]))
      lv |> element("button[phx-value-step='review']") |> render_click()

      stub_python_port_success()

      lv
      |> form("form[phx-submit='create']", %{"experiment_name" => "Inherit run"})
      |> render_submit()

      [experiment] =
        Enum.reject(Experiments.list_experiments(scope), &(&1.id in existing_experiment_ids))

      assert Experiments.list_videos(experiment) |> Enum.map(& &1.filename) |> Enum.sort() ==
               ["lib2_1.mp4", "lib2_2.mp4", "lib2_3.mp4"]
    end

    test "reused videos inheriting ROI/scale from a freshly-uploaded reference video",
         %{conn: conn, user: user, scope: scope} do
      sources =
        for n <- 1..3 do
          path =
            Path.join(
              System.tmp_dir!(),
              "lib-src3-#{n}-#{System.unique_integer([:positive])}.mp4"
            )

          File.write!(path, "bytes #{n}")

          video_fixture(experiment_fixture(user, %{name: "Src3 exp #{n}"}), nil, %{
            filename: "lib3_#{n}.mp4",
            filepath: path,
            status: "done"
          })
        end

      existing_experiment_ids = MapSet.new(Experiments.list_experiments(scope), & &1.id)

      {:ok, lv, _html} = live(conn, ~p"/experiments/new")

      for s <- sources, do: lv |> element("#library-video-#{s.id}") |> render_click()
      lv |> element("#add-from-library-btn") |> render_click()

      tmp =
        Path.join(System.tmp_dir!(), "wizard-fresh3-#{System.unique_integer([:positive])}.mp4")

      File.write!(tmp, "fresh upload bytes")

      video =
        file_input(lv, "form[phx-change=validate_upload]", :videos, [
          %{name: "fresh3.mp4", content: File.read!(tmp), type: "video/mp4"}
        ])

      render_upload(video, "fresh3.mp4")
      lv |> element("button", "Continue → ROI & scale") |> render_click()

      html = render(lv)

      refs =
        Regex.scan(~r/phx-value-ref="([^"]+)"/, html) |> Enum.map(&Enum.at(&1, 1)) |> Enum.uniq()

      reused_refs = Enum.take(refs, 3)
      fresh_ref = List.last(refs)

      render_click(lv, "select_active", %{"ref" => fresh_ref})
      render_click(lv, "toggle_ref", %{"ref" => fresh_ref})

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

      lv |> form("form[phx-change='set_scale_cm']", %{"value" => "10"}) |> render_change()

      render_hook(lv, "shape_drawn", %{
        "kind" => "scale2",
        "x1" => 0,
        "y1" => 10,
        "x2" => 40,
        "y2" => 10
      })

      lv |> form("form[phx-change='set_scale_cm2']", %{"value" => "8"}) |> render_change()

      for ref <- reused_refs do
        render_click(lv, "select_active", %{"ref" => ref})
        render_click(lv, "set_source", %{"ref" => ref, "source" => fresh_ref})
      end

      refute has_element?(lv, ~s(button[phx-value-step="review"][disabled]))
      lv |> element("button[phx-value-step='review']") |> render_click()

      stub_python_port_success()

      lv
      |> form("form[phx-submit='create']", %{"experiment_name" => "Fresh-ref run"})
      |> render_submit()

      [experiment] =
        Enum.reject(Experiments.list_experiments(scope), &(&1.id in existing_experiment_ids))

      assert Experiments.list_videos(experiment) |> Enum.map(& &1.filename) |> Enum.sort() ==
               ["fresh3.mp4", "lib3_1.mp4", "lib3_2.mp4", "lib3_3.mp4"]
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
      |> element("#ref-own-#{ref}")
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
      assert has_element?(lv, ~s(button[phx-value-step="review"][disabled]))
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
      |> element("#ref-own-#{ref_a}")
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

    test "picking a reference in the dropdown resolves inheritance (scale + ROI together) and unblocks Continue",
         %{lv: lv, ref_a: ref_a, ref_b: ref_b} do
      html = render(lv)
      assert html =~ "no reference"
      assert has_element?(lv, ~s(button[phx-value-step="review"][disabled]))

      lv
      |> form("form[phx-change='set_source']", %{"ref" => ref_b, "source" => ref_a})
      |> render_change()

      html = render(lv)
      assert html =~ "inherits from a.mp4"
      refute has_element?(lv, ~s(button[phx-value-step="review"][disabled]))
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
      |> element("#ref-own-#{ref}")
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

      assert length(Subjects.list_subjects(scope)) == 1
      assert [subject] = Subjects.list_subjects(scope)
      assert subject.name == "a"
    end

    test "creating a new subject with a group persists it", %{lv: lv, ref: ref, scope: scope} do
      lv
      |> form("form[phx-submit='create']", %{"subject_new_group" => %{ref => "Control"}})
      |> render_change()

      stub_python_port_success()

      lv
      |> form("form[phx-submit='create']", %{"experiment_name" => "Grouped run"})
      |> render_submit()

      assert [subject] = Subjects.list_subjects(scope)
      assert subject.group == "Control"
    end
  end

  describe "step 3 review — reusing an existing subject" do
    setup %{conn: conn, user: user} do
      subject = subject_fixture(user, %{name: "M-existing", group: "Treated"})

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
      |> element("#ref-own-#{ref}")
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

    test "renders the subject's existing group in the datalist", %{lv: lv} do
      html = render(lv)

      assert html =~ ~s(<datalist id="subject-groups-datalist">)
      assert html =~ ~s(value="Treated")
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

      assert length(Subjects.list_subjects(scope)) == 1

      [experiment] = Experiments.list_experiments(scope)
      [video] = Experiments.list_videos(experiment)
      assert video.subject_id == subject.id
    end
  end

  describe "step 3 review — two videos creating the same new subject with different groups" do
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

      lv |> element("li[phx-value-ref='#{ref_a}']") |> render_click()
      lv |> element("#ref-own-#{ref_a}") |> render_click()

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

      # switch the active video to b.mp4, which starts without any reference
      lv |> element("li[phx-value-ref='#{ref_b}']") |> render_click()

      lv
      |> form("form[phx-change='set_source']", %{"ref" => ref_b, "source" => ref_a})
      |> render_change()

      lv |> element("button[phx-value-step='review']") |> render_click()

      %{lv: lv, ref_a: ref_a, ref_b: ref_b}
    end

    test "the last video in the batch wins the group for the shared new subject", %{
      lv: lv,
      ref_a: ref_a,
      ref_b: ref_b,
      scope: scope
    } do
      lv
      |> form("form[phx-submit='create']", %{
        "subject" => %{ref_a => "new", ref_b => "new"},
        "subject_new_name" => %{ref_a => "Shared", ref_b => "Shared"},
        "subject_new_group" => %{ref_a => "GroupA", ref_b => "GroupB"}
      })
      |> render_change()

      stub_python_port_success()

      lv
      |> form("form[phx-submit='create']", %{"experiment_name" => "Batch run"})
      |> render_submit()

      assert [subject] = Subjects.list_subjects(scope)
      assert subject.name == "Shared"
      # deterministic given @saved_videos order — whichever video is last to
      # be folded into the dedup map wins (see create_wizard_subjects/2)
      assert subject.group == "GroupA"
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
