defmodule Explorer.Chain.Import.Runner.PolygonSupernetWithdrawalExits do
  @moduledoc """
  Bulk imports `t:Explorer.Chain.PolygonSupernetWithdrawalExit.t/0`.
  """

  require Ecto.Query

  import Ecto.Query, only: [from: 2]

  alias Ecto.{Changeset, Multi, Repo}
  alias Explorer.Chain.{Import, PolygonSupernetWithdrawalExit}
  alias Explorer.Prometheus.Instrumenter

  @behaviour Import.Runner

  # milliseconds
  @timeout 60_000

  @type imported :: [PolygonSupernetWithdrawalExit.t()]

  @impl Import.Runner
  def ecto_schema_module, do: PolygonSupernetWithdrawalExit

  @impl Import.Runner
  def option_key, do: :polygon_supernet_withdrawal_exits

  @impl Import.Runner
  def imported_table_row do
    %{
      value_type: "[#{ecto_schema_module()}.t()]",
      value_description: "List of `t:#{ecto_schema_module()}.t/0`s"
    }
  end

  @impl Import.Runner
  def run(multi, changes_list, %{timestamps: timestamps} = options) do
    insert_options =
      options
      |> Map.get(option_key(), %{})
      |> Map.take(~w(on_conflict timeout)a)
      |> Map.put_new(:timeout, @timeout)
      |> Map.put(:timestamps, timestamps)

    Multi.run(multi, :insert_polygon_supernet_withdrawal_exits, fn repo, _ ->
      Instrumenter.block_import_stage_runner(
        fn -> insert(repo, changes_list, insert_options) end,
        :block_referencing,
        :polygon_supernet_withdrawal_exits,
        :polygon_supernet_withdrawal_exits
      )
    end)
  end

  @impl Import.Runner
  def timeout, do: @timeout

  @spec insert(Repo.t(), [map()], %{required(:timeout) => timeout(), required(:timestamps) => Import.timestamps()}) ::
          {:ok, [PolygonSupernetWithdrawalExit.t()]}
          | {:error, [Changeset.t()]}
  def insert(repo, changes_list, %{timeout: timeout, timestamps: timestamps} = options) when is_list(changes_list) do
    on_conflict = Map.get_lazy(options, :on_conflict, &default_on_conflict/0)

    # Enforce PolygonSupernetWithdrawalExit ShareLocks order (see docs: sharelock.md)
    ordered_changes_list = Enum.sort_by(changes_list, & &1.msg_id)

    {:ok, inserted} =
      Import.insert_changes_list(
        repo,
        ordered_changes_list,
        conflict_target: :msg_id,
        on_conflict: on_conflict,
        for: PolygonSupernetWithdrawalExit,
        returning: true,
        timeout: timeout,
        timestamps: timestamps
      )

    {:ok, inserted}
  end

  defp default_on_conflict do
    from(
      we in PolygonSupernetWithdrawalExit,
      update: [
        set: [
          # Don't update `msg_id` as it is a primary key and used for the conflict target
          l1_transaction_hash: fragment("EXCLUDED.l1_transaction_hash"),
          l1_block_number: fragment("EXCLUDED.l1_block_number"),
          success: fragment("EXCLUDED.success"),
          inserted_at: fragment("LEAST(?, EXCLUDED.inserted_at)", we.inserted_at),
          updated_at: fragment("GREATEST(?, EXCLUDED.updated_at)", we.updated_at)
        ]
      ],
      where:
        fragment(
          "(EXCLUDED.l1_transaction_hash, EXCLUDED.l1_block_number, EXCLUDED.success) IS DISTINCT FROM (?, ?, ?)",
          we.l1_transaction_hash,
          we.l1_block_number,
          we.success
        )
    )
  end
end
