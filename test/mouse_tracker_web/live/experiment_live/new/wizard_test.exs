defmodule MouseTrackerWeb.ExperimentLive.New.WizardTest do
  use ExUnit.Case, async: true

  alias MouseTrackerWeb.ExperimentLive.New.Wizard

  describe "default_spec/2" do
    test "defaults to a new subject named after the file, when no subject_id is given" do
      assert Wizard.default_spec("mouse_7.mp4") == %{
               subject_ref: {:new, "mouse_7", nil},
               is_ref?: false,
               source: nil
             }
    end

    test "pre-fills the existing subject when reusing a video that already had one" do
      assert Wizard.default_spec("mouse_7.mp4", 42) == %{
               subject_ref: {:existing, 42},
               is_ref?: false,
               source: nil
             }
    end
  end
end
