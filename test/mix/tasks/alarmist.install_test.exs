# SPDX-FileCopyrightText: 2026 Lars Wikman
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Mix.Tasks.Alarmist.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  @nerves_files %{
    "config/config.exs" => """
    import Config

    config :logger, backends: [RingLogger]

    if Mix.target() == :host do
      import_config "host.exs"
    else
      import_config "target.exs"
    end
    """,
    "config/host.exs" => """
    import Config
    """,
    "config/target.exs" => """
    import Config

    config :nerves, :erlinit, update_clock: true
    """
  }

  defp install(igniter, argv \\ []) do
    Igniter.compose_task(igniter, "alarmist.install", argv)
  end

  describe "default install" do
    test "changes nothing in a Nerves project and prints next steps" do
      test_project(files: @nerves_files)
      |> install()
      |> assert_unchanged()
      |> assert_has_notice(&(&1 =~ "Alarmist is ready to use" and &1 =~ "Alarmist.info()"))
    end

    test "changes nothing in a plain project and prints next steps" do
      igniter = test_project() |> install()

      assert_unchanged(igniter)
      refute Rewrite.has_source?(igniter.rewrite, "config/config.exs")
      assert_has_notice(igniter, &(&1 =~ "--managed-alarm"))
    end

    test "is idempotent" do
      test_project(files: @nerves_files)
      |> install()
      |> apply_igniter!()
      |> install()
      |> assert_unchanged()
    end

    test "preserves existing alarmist config" do
      files =
        Map.put(@nerves_files, "config/config.exs", """
        import Config

        config :alarmist,
          managed_alarms: [Test.Existing],
          alarm_levels: %{{:disk_almost_full, ~c"/"} => :debug}
        """)

      test_project(files: files)
      |> install()
      |> assert_unchanged()
    end
  end

  describe "--managed-alarm" do
    test "scaffolds the alarm and registers it in a Nerves project" do
      igniter =
        test_project(files: @nerves_files)
        |> install(["--managed-alarm", "Test.NetworkUnstable"])

      igniter
      |> assert_creates("lib/test/network_unstable.ex", """
      defmodule Test.NetworkUnstable do
        @moduledoc \"\"\"
        Managed alarm

        Alarmist sets and clears this alarm based on the `alarm_if` condition
        below. Replace the condition with the alarms that you care about. See
        the Alarmist documentation for the available operators.
        \"\"\"
        use Alarmist.Alarm

        # Set when Test.NetworkUnstable.Input has been set for at least 5 seconds
        alarm_if do
          debounce(Test.NetworkUnstable.Input, 5_000)
        end
      end
      """)
      |> assert_has_patch("config/config.exs", """
      + |config :alarmist, managed_alarms: [Test.NetworkUnstable]
      """)
      |> assert_unchanged(["config/target.exs", "config/host.exs"])
      |> assert_has_notice(&(&1 =~ "* Test.NetworkUnstable"))
    end

    test "creates config/config.exs in a plain project" do
      test_project()
      |> install(["--managed-alarm", "Test.NetworkUnstable"])
      |> assert_creates("lib/test/network_unstable.ex")
      |> assert_creates("config/config.exs", """
      import Config
      config :alarmist, managed_alarms: [Test.NetworkUnstable]
      """)
    end

    test "may be given more than once" do
      test_project(files: @nerves_files)
      |> install(["--managed-alarm", "Test.First", "--managed-alarm", "Test.Second"])
      |> assert_creates("lib/test/first.ex")
      |> assert_creates("lib/test/second.ex")
      |> assert_has_patch("config/config.exs", """
      + |config :alarmist, managed_alarms: [Test.First, Test.Second]
      """)
    end

    test "is idempotent" do
      argv = ["--managed-alarm", "Test.NetworkUnstable"]

      test_project(files: @nerves_files)
      |> install(argv)
      |> apply_igniter!()
      |> install(argv)
      |> assert_unchanged()
    end

    test "appends to an existing list and keeps other alarmist config" do
      files =
        Map.put(@nerves_files, "config/config.exs", """
        import Config

        config :alarmist,
          managed_alarms: [Test.Existing],
          alarm_levels: %{{:disk_almost_full, ~c"/"} => :debug}
        """)

      test_project(files: files)
      |> install(["--managed-alarm", "Test.NetworkUnstable"])
      |> assert_has_patch("config/config.exs", """
      - |  managed_alarms: [Test.Existing],
      + |  managed_alarms: [Test.Existing, Test.NetworkUnstable],
      """)
    end

    test "leaves an existing alarm module alone" do
      module = """
      defmodule Test.NetworkUnstable do
        use Alarmist.Alarm

        alarm_if do
          Test.NetworkDown
        end
      end
      """

      files = Map.put(@nerves_files, "lib/test/network_unstable.ex", module)

      test_project(files: files)
      |> install(["--managed-alarm", "Test.NetworkUnstable"])
      |> assert_unchanged("lib/test/network_unstable.ex")
      |> assert_has_patch("config/config.exs", """
      + |config :alarmist, managed_alarms: [Test.NetworkUnstable]
      """)
    end

    test "warns rather than overwriting a non-list managed_alarms value" do
      files =
        Map.put(@nerves_files, "config/config.exs", """
        import Config

        alarms = [Test.Existing]
        config :alarmist, managed_alarms: alarms
        """)

      test_project(files: files)
      |> install(["--managed-alarm", "Test.NetworkUnstable"])
      |> assert_unchanged("config/config.exs")
      |> assert_has_warning(&(&1 =~ "Test.NetworkUnstable was not added"))
    end

    test "the scaffolded alarm compiles and works" do
      source =
        test_project()
        |> install(["--managed-alarm", "AlarmistInstallTest.Scaffolded"])
        |> Map.fetch!(:rewrite)
        |> Rewrite.source!("lib/alarmist_install_test/scaffolded.ex")
        |> Rewrite.Source.get(:content)

      assert [{alarm, _}] = Code.compile_string(source)
      assert alarm == AlarmistInstallTest.Scaffolded

      # Alarmist accepts it as a managed alarm
      on_exit(fn -> Alarmist.remove_managed_alarm(alarm) end)
      assert :ok = Alarmist.add_managed_alarm(alarm)
      assert alarm in Alarmist.managed_alarm_ids()
    end
  end
end
