defmodule MouseTracker.Experiments.SubjectsTest do
  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures
  import MouseTracker.ExperimentsFixtures

  alias MouseTracker.Experiments.Subjects

  describe "update_subject/3" do
    test "atualiza o nome do subject" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      subject = subject_fixture(user)

      assert {:ok, updated} = Subjects.update_subject(scope, subject, %{name: "M-02"})
      assert updated.name == "M-02"
    end

    test "retorna erro com nome duplicado para o mesmo usuário" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      subject_fixture(user, %{name: "M-01"})
      other = subject_fixture(user, %{name: "M-02"})

      assert {:error, changeset} = Subjects.update_subject(scope, other, %{name: "M-01"})
      assert "has already been taken" in errors_on(changeset).name
    end

    test "levanta erro se o subject pertencer a outro usuário" do
      subject = subject_fixture(user_fixture())
      other_scope = user_scope_fixture(user_fixture())

      assert_raise FunctionClauseError, fn ->
        Subjects.update_subject(other_scope, subject, %{name: "M-02"})
      end
    end
  end

  describe "delete_subject/2" do
    test "remove o subject do banco" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      subject = subject_fixture(user)

      assert {:ok, _} = Subjects.delete_subject(scope, subject)

      assert_raise Ecto.NoResultsError, fn ->
        Subjects.get_subject!(scope, subject.id)
      end
    end

    test "levanta erro se o subject pertencer a outro usuário" do
      subject = subject_fixture(user_fixture())
      other_scope = user_scope_fixture(user_fixture())

      assert_raise FunctionClauseError, fn ->
        Subjects.delete_subject(other_scope, subject)
      end
    end
  end

  describe "count_videos_using_subject/1" do
    test "0 quando nenhum vídeo usa o subject" do
      subject = subject_fixture(user_fixture())
      assert Subjects.count_videos_using_subject(subject) == 0
    end

    test "conta vídeos apontando para o subject, de qualquer status" do
      user = user_fixture()
      exp = experiment_fixture(user)
      subject = subject_fixture(user)
      video_fixture(exp, nil, %{status: "pending", subject_id: subject.id})
      video_fixture(exp, nil, %{status: "done", subject_id: subject.id})
      _other = video_fixture(exp)

      assert Subjects.count_videos_using_subject(subject) == 2
    end
  end
end
