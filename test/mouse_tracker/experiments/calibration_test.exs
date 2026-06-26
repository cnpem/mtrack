defmodule MouseTracker.Experiments.CalibrationTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures

  alias MouseTracker.Experiments.Calibration

  @valid_attrs %{
    cage_side_cm: 30.0,
    px_per_10cm: 50.0,
    threshold: 80,
    min_area: 250
  }

  describe "changeset/2" do
    setup do
      %{user: user_fixture()}
    end

    test "válido com campos obrigatórios", %{user: user} do
      changeset = Calibration.changeset(%Calibration{user_id: user.id}, @valid_attrs)
      assert changeset.valid?
    end

    test "válido com coordenadas completas", %{user: user} do
      attrs =
        Map.merge(@valid_attrs, %{
          coordinate_x1: 0,
          coordinate_y1: 0,
          coordinate_x2: 640,
          coordinate_y2: 480
        })

      changeset = Calibration.changeset(%Calibration{user_id: user.id}, attrs)
      assert changeset.valid?
    end

    test "válido com valid_region completo", %{user: user} do
      attrs =
        Map.merge(@valid_attrs, %{
          valid_region_x: 0,
          valid_region_y: 0,
          valid_region_w: 640,
          valid_region_h: 480
        })

      changeset = Calibration.changeset(%Calibration{user_id: user.id}, attrs)
      assert changeset.valid?
    end

    test "inválido sem cage_side_cm", %{user: user} do
      changeset =
        Calibration.changeset(%Calibration{user_id: user.id}, Map.delete(@valid_attrs, :cage_side_cm))

      assert "can't be blank" in errors_on(changeset).cage_side_cm
    end

    test "inválido sem px_per_10cm", %{user: user} do
      changeset =
        Calibration.changeset(%Calibration{user_id: user.id}, Map.delete(@valid_attrs, :px_per_10cm))

      assert "can't be blank" in errors_on(changeset).px_per_10cm
    end

    test "inválido sem threshold", %{user: user} do
      changeset =
        Calibration.changeset(%Calibration{user_id: user.id}, Map.delete(@valid_attrs, :threshold))

      assert "can't be blank" in errors_on(changeset).threshold
    end

    test "inválido sem min_area", %{user: user} do
      changeset =
        Calibration.changeset(%Calibration{user_id: user.id}, Map.delete(@valid_attrs, :min_area))

      assert "can't be blank" in errors_on(changeset).min_area
    end

    test "cage_side_cm <= 0 é inválido", %{user: user} do
      changeset =
        Calibration.changeset(%Calibration{user_id: user.id}, Map.put(@valid_attrs, :cage_side_cm, 0.0))

      assert errors_on(changeset).cage_side_cm != []
    end

    test "px_per_10cm <= 0 é inválido", %{user: user} do
      changeset =
        Calibration.changeset(%Calibration{user_id: user.id}, Map.put(@valid_attrs, :px_per_10cm, 0.0))

      assert errors_on(changeset).px_per_10cm != []
    end

    test "threshold fora de [0..255] é inválido", %{user: user} do
      changeset =
        Calibration.changeset(%Calibration{user_id: user.id}, Map.put(@valid_attrs, :threshold, 256))

      assert errors_on(changeset).threshold != []
    end

    test "threshold negativo é inválido", %{user: user} do
      changeset =
        Calibration.changeset(%Calibration{user_id: user.id}, Map.put(@valid_attrs, :threshold, -1))

      assert errors_on(changeset).threshold != []
    end

    test "min_area <= 0 é inválido", %{user: user} do
      changeset =
        Calibration.changeset(%Calibration{user_id: user.id}, Map.put(@valid_attrs, :min_area, 0))

      assert errors_on(changeset).min_area != []
    end

    test "coordenadas parciais são inválidas (all-or-nothing)", %{user: user} do
      attrs = Map.merge(@valid_attrs, %{coordinate_x1: 10})
      changeset = Calibration.changeset(%Calibration{user_id: user.id}, attrs)
      assert errors_on(changeset).coordinate_x1 != []
    end

    test "valid_region parcial é inválido (all-or-nothing)", %{user: user} do
      attrs = Map.merge(@valid_attrs, %{valid_region_x: 10, valid_region_y: 10})
      changeset = Calibration.changeset(%Calibration{user_id: user.id}, attrs)
      assert errors_on(changeset).valid_region_x != []
    end

    test "user_id não é aceito via cast", %{user: user} do
      other_user = user_fixture()

      changeset =
        Calibration.changeset(
          %Calibration{user_id: user.id},
          Map.put(@valid_attrs, :user_id, other_user.id)
        )

      refute changeset.changes[:user_id]
    end
  end
end
