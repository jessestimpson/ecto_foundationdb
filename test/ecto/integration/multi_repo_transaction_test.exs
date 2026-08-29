defmodule Ecto.Integration.MultiRepoTransactionTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.FoundationDB
  alias EctoFoundationDB.Sandbox
  alias EctoFoundationDB.Schemas.User

  defmodule OrgRepo do
    @moduledoc false
    use Ecto.Repo, otp_app: :ecto_foundationdb, adapter: Ecto.Adapters.FoundationDB
  end

  defmodule MemberRepo do
    @moduledoc false
    use Ecto.Repo, otp_app: :ecto_foundationdb, adapter: Ecto.Adapters.FoundationDB
  end

  def open_shared_db(_repo), do: Sandbox.open_db(Ecto.Integration.TestRepo)

  # The Repos are started for the whole module so that they outlive each test's
  # `on_exit`, which needs them for the tenant checkin.
  setup_all do
    Application.put_env(:ecto_foundationdb, OrgRepo,
      open_db: &__MODULE__.open_shared_db/1,
      storage_id: "MultiRepoTransactionTest.Org"
    )

    Application.put_env(:ecto_foundationdb, MemberRepo,
      open_db: &__MODULE__.open_shared_db/1,
      storage_id: "MultiRepoTransactionTest.Member"
    )

    {:ok, _} = OrgRepo.start_link()
    {:ok, _} = MemberRepo.start_link()

    :ok
  end

  setup do
    org = TenantForCase.setup(OrgRepo, log: false)
    member = TenantForCase.setup(MemberRepo, log: false)

    on_exit(fn ->
      TenantForCase.exit(OrgRepo, org[:tenant_id])
      TenantForCase.exit(MemberRepo, member[:tenant_id])
    end)

    [org_tenant: org[:tenant], member_tenant: member[:tenant]]
  end

  test "transaction spans tenants from multiple repos", context do
    org_tenant = context[:org_tenant]
    member_tenant = context[:member_tenant]

    db = FoundationDB.db(OrgRepo)
    assert db == FoundationDB.db(MemberRepo)

    {alice, bob} =
      FoundationDB.transactional(db, fn ->
        alice = OrgRepo.insert!(%User{name: "Alice"}, prefix: org_tenant)
        bob = MemberRepo.insert!(%User{name: "Bob"}, prefix: member_tenant)

        assert %User{name: "Alice"} = OrgRepo.get(User, alice.id, prefix: org_tenant)
        assert %User{name: "Bob"} = MemberRepo.get(User, bob.id, prefix: member_tenant)

        assert nil == MemberRepo.get(User, alice.id, prefix: member_tenant)

        {alice, bob}
      end)

    assert %User{name: "Alice"} = OrgRepo.get(User, alice.id, prefix: org_tenant)
    assert %User{name: "Bob"} = MemberRepo.get(User, bob.id, prefix: member_tenant)

    carol_id = Ecto.UUID.generate()
    dave_id = Ecto.UUID.generate()

    assert_raise RuntimeError, "tx abort", fn ->
      FoundationDB.transactional(db, fn ->
        OrgRepo.insert!(%User{id: carol_id, name: "Carol"}, prefix: org_tenant)
        MemberRepo.insert!(%User{id: dave_id, name: "Dave"}, prefix: member_tenant)
        raise "tx abort"
      end)
    end

    assert nil == OrgRepo.get(User, carol_id, prefix: org_tenant)
    assert nil == MemberRepo.get(User, dave_id, prefix: member_tenant)
  end

  test "repo transactions nest inside a database transaction", context do
    org_tenant = context[:org_tenant]
    member_tenant = context[:member_tenant]

    db = FoundationDB.db(OrgRepo)

    {alice, bob} =
      FoundationDB.transactional(db, fn ->
        alice =
          OrgRepo.transactional(org_tenant, fn ->
            OrgRepo.insert!(%User{name: "Alice"})
          end)

        bob =
          MemberRepo.transactional(member_tenant, fn ->
            MemberRepo.insert!(%User{name: "Bob"})
          end)

        {alice, bob}
      end)

    assert %User{name: "Alice"} = OrgRepo.get(User, alice.id, prefix: org_tenant)
    assert %User{name: "Bob"} = MemberRepo.get(User, bob.id, prefix: member_tenant)

    carol_id = Ecto.UUID.generate()

    assert_raise RuntimeError, "tx abort", fn ->
      FoundationDB.transactional(db, fn ->
        OrgRepo.transactional(org_tenant, fn ->
          OrgRepo.insert!(%User{id: carol_id, name: "Carol"})
        end)

        raise "tx abort"
      end)
    end

    assert nil == OrgRepo.get(User, carol_id, prefix: org_tenant)
  end

  test "a tenant transaction nests inside a tenant transaction", context do
    org_tenant = context[:org_tenant]

    alice =
      OrgRepo.transactional(org_tenant, fn ->
        OrgRepo.transactional(org_tenant, fn ->
          OrgRepo.insert!(%User{name: "Alice"})
        end)
      end)

    assert %User{name: "Alice"} = OrgRepo.get(User, alice.id, prefix: org_tenant)
  end

  test "a database transaction nests inside a tenant transaction", context do
    org_tenant = context[:org_tenant]
    member_tenant = context[:member_tenant]

    db = FoundationDB.db(OrgRepo)

    {alice, bob} =
      OrgRepo.transactional(org_tenant, fn ->
        alice = OrgRepo.insert!(%User{name: "Alice"})

        bob =
          FoundationDB.transactional(db, fn ->
            MemberRepo.insert!(%User{name: "Bob"}, prefix: member_tenant)
          end)

        {alice, bob}
      end)

    assert %User{name: "Alice"} = OrgRepo.get(User, alice.id, prefix: org_tenant)
    assert %User{name: "Bob"} = MemberRepo.get(User, bob.id, prefix: member_tenant)

    dave_id = Ecto.UUID.generate()

    assert_raise RuntimeError, "tx abort", fn ->
      OrgRepo.transactional(org_tenant, fn ->
        FoundationDB.transactional(db, fn ->
          MemberRepo.insert!(%User{id: dave_id, name: "Dave"}, prefix: member_tenant)
        end)

        raise "tx abort"
      end)
    end

    assert nil == MemberRepo.get(User, dave_id, prefix: member_tenant)
  end

  test "an operation takes its tenant from the prefix in a database transaction", context do
    org_tenant = context[:org_tenant]
    member_tenant = context[:member_tenant]

    db = FoundationDB.db(OrgRepo)

    future =
      FoundationDB.transactional(db, fn ->
        OrgRepo.async_insert_all!(User, [%User{name: "Alice"}],
          prefix: org_tenant,
          conflict_target: []
        )
      end)

    assert [alice] = OrgRepo.await(future)
    assert %User{name: "Alice"} = OrgRepo.get(User, alice.id, prefix: org_tenant)
    assert nil == MemberRepo.get(User, alice.id, prefix: member_tenant)
  end
end
