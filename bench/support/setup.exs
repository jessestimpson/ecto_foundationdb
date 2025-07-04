Code.require_file("repo.exs", __DIR__)
Code.require_file("schemas.exs", __DIR__)

alias Ecto.Bench.FdbRepo
alias Ecto.Bench.PgRepo
alias EctoFoundationDB.Tenant

{:ok, _} = Ecto.Adapters.FoundationDB.ensure_all_started(FdbRepo.config(), :temporary)

{:ok, _pid} = FdbRepo.start_link(log: false)

Tenant.open!(FdbRepo, "bench")

{:ok, _} = Ecto.Adapters.Postgres.ensure_all_started(PgRepo.config(), :temporary)
_ = Ecto.Adapters.Postgres.storage_down(PgRepo.config())
:ok = Ecto.Adapters.Postgres.storage_up(PgRepo.config())
{:ok, _pid} = PgRepo.start_link(log: false)
:ok = Ecto.Migrator.up(PgRepo, 0, CreateUser, log: false)
