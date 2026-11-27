# SPDX-FileCopyrightText: 2026 Lars Wikman
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Mix.Tasks.Alarmist.Install.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc() do
    "Installs Alarmist in your project."
  end

  @spec example() :: String.t()
  def example() do
    "mix igniter.install alarmist"
  end

  @spec long_doc() :: String.t()
  def long_doc() do
    """
    #{short_doc()}

    Alarmist works as soon as it is a dependency: it starts with your
    application and takes over from the default `:alarm_handler` handler, so
    no configuration is required. By default this installer makes no changes
    beyond adding the dependency and prints the next steps.

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

    * `--managed-alarm` - Optional module name of a managed alarm to scaffold,
      e.g. `--managed-alarm MyApp.NetworkUnstable`. This creates the module
      with a placeholder `alarm_if` condition and registers it under
      `config :alarmist, managed_alarms: [...]` in `config/config.exs` so that
      Alarmist loads it on start. May be given more than once. Existing
      modules and existing configuration are left as they are.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Alarmist.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    alias Igniter.Code.List, as: CodeList
    alias Igniter.Project.Config
    alias Igniter.Project.Module, as: ProjectModule

    @config_file "config.exs"

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :alarmist,
        example: __MODULE__.Docs.example(),
        schema: [
          managed_alarm: :keep
        ],
        defaults: [],
        aliases: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      alarms =
        igniter.args.options
        |> Keyword.get_values(:managed_alarm)
        |> List.flatten()
        |> Enum.map(&ProjectModule.parse/1)
        |> Enum.uniq()

      igniter
      |> then(&Enum.reduce(alarms, &1, fn alarm, acc -> add_managed_alarm(acc, alarm) end))
      |> Igniter.add_notice(notice(alarms))
    end

    defp add_managed_alarm(igniter, alarm) do
      igniter
      |> create_alarm_module(alarm)
      |> register_alarm(alarm)
    end

    defp create_alarm_module(igniter, alarm) do
      {exists?, igniter} = ProjectModule.module_exists(igniter, alarm)

      if exists? do
        igniter
      else
        ProjectModule.create_module(igniter, alarm, alarm_contents(alarm))
      end
    end

    defp alarm_contents(alarm) do
      input = Module.concat(alarm, Input)

      """
      @moduledoc \"\"\"
      Managed alarm

      Alarmist sets and clears this alarm based on the `alarm_if` condition
      below. Replace the condition with the alarms that you care about. See
      the Alarmist documentation for the available operators.
      \"\"\"
      use Alarmist.Alarm

      # Set when #{inspect(input)} has been set for at least 5 seconds
      alarm_if do
        debounce(#{inspect(input)}, 5_000)
      end
      """
    end

    # Merge the alarm into the `:managed_alarms` list. Anything the user
    # already has in the list is kept.
    defp register_alarm(igniter, alarm) do
      Config.configure(
        igniter,
        @config_file,
        :alarmist,
        [:managed_alarms],
        [alarm],
        updater: fn zipper ->
          with :error <- CodeList.append_new_to_list(zipper, alarm) do
            {:warning,
             """
             Alarmist: `config :alarmist, managed_alarms: ...` in config/#{@config_file} is not a
             literal list, so #{inspect(alarm)} was not added to it. Add it by hand or call
             `Alarmist.add_managed_alarm(#{inspect(alarm)})` when your application starts.
             """}
          end
        end
      )
    end

    defp notice([]) do
      """
      Alarmist is ready to use. It starts with your application and tracks every
      alarm reported via `:alarm_handler.set_alarm/1` and `:alarm_handler.clear_alarm/1`.

        * Run `Alarmist.info()` at the IEx prompt to see the current alarms
        * Call `Alarmist.subscribe/1` to get notified when an alarm changes
        * Define managed alarms with `use Alarmist.Alarm` and list them under
          `config :alarmist, managed_alarms: [...]`, or scaffold one with
          `mix alarmist.install --managed-alarm MyApp.MyAlarm`

      See https://alarmist.hexdocs.pm/ for details.
      """
    end

    defp notice(alarms) do
      """
      Alarmist is ready to use. The following managed alarms were set up with
      placeholder `alarm_if` conditions. Edit them to describe the conditions
      that you care about:

      #{Enum.map_join(alarms, "\n", &"  * #{inspect(&1)}")}

      Run `Alarmist.info()` at the IEx prompt to see the current alarms and call
      `Alarmist.subscribe/1` to get notified when an alarm changes.

      See https://alarmist.hexdocs.pm/ for details.
      """
    end
  end
else
  defmodule Mix.Tasks.Alarmist.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'alarmist.install' requires igniter. Please install igniter and try again.

      For more information, see: https://igniter.hexdocs.pm/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
