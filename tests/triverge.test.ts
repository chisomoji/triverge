
import { beforeEach, describe, expect, it } from "vitest";
import { Cl, ClarityType, ResponseOkCV, TupleCV } from "@stacks/transactions";

const CONTRACT = "triverge";
const MANIFEST_PATH = "Clarinet.toml";

const ERR_UNAUTHORIZED = 100;
const ERR_VAULT_NOT_FOUND = 101;
const ERR_INSUFFICIENT_BALANCE = 102;
const ERR_LOCKED = 103;
const ERR_INVALID_AMOUNT = 105;
const ERR_CONTRACT_PAUSED = 108;

const VAULT_LOW = 1;
const ROLE_ADMIN = 1;
const ROLE_OPERATOR = 2;

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;

beforeEach(
  async () => {
    await simnet.initSession(".", MANIFEST_PATH);
  },
  30000,
);

const grantOperatorToDeployer = () => {
  const grant = simnet.callPublicFn(
    CONTRACT,
    "grant-role",
    [Cl.principal(deployer), Cl.uint(ROLE_OPERATOR)],
    deployer,
  );
  expect(grant.result).toBeOk(Cl.bool(true));
};

const createVault = (lockPeriod: number) => {
  grantOperatorToDeployer();
  const create = simnet.callPublicFn(
    CONTRACT,
    "create-vault",
    [Cl.uint(VAULT_LOW), Cl.uint(lockPeriod)],
    deployer,
  );
  expect(create.result).toBeOk(Cl.uint(0));
  return 0;
};

const unwrapOkTuple = (result: unknown) => {
  expect(result).toHaveClarityType(ClarityType.ResponseOk);
  const okValue = result as ResponseOkCV;
  expect(okValue.value).toHaveClarityType(ClarityType.Tuple);
  return (okValue.value as TupleCV).value;
};

describe("triverge core flows", () => {
  it("initializes admin and defaults", () => {
    const admin = simnet.callReadOnlyFn(CONTRACT, "get-admin", [], deployer);
    expect(admin.result).toBeOk(Cl.principal(deployer));

    const role = simnet.callReadOnlyFn(
      CONTRACT,
      "get-user-role",
      [Cl.principal(deployer)],
      deployer,
    );
    expect(role.result).toBeOk(Cl.uint(ROLE_ADMIN));

    const paused = simnet.callReadOnlyFn(CONTRACT, "is-contract-paused", [], deployer);
    expect(paused.result).toBeOk(Cl.bool(false));

    const limits = simnet.callReadOnlyFn(CONTRACT, "get-deposit-limits", [], deployer);
    expect(limits.result).toBeOk(
      Cl.tuple({
        "max-per-user": Cl.uint(1_000_000_000),
        "max-vault": Cl.uint(10_000_000_000),
      }),
    );
  });

  it("enforces admin-only role management", () => {
    const unauthorized = simnet.callPublicFn(
      CONTRACT,
      "grant-role",
      [Cl.principal(wallet1), Cl.uint(ROLE_OPERATOR)],
      wallet1,
    );
    expect(unauthorized.result).toBeErr(Cl.uint(ERR_UNAUTHORIZED));

    const grant = simnet.callPublicFn(
      CONTRACT,
      "grant-role",
      [Cl.principal(wallet1), Cl.uint(ROLE_OPERATOR)],
      deployer,
    );
    expect(grant.result).toBeOk(Cl.bool(true));

    const role = simnet.callReadOnlyFn(
      CONTRACT,
      "get-user-role",
      [Cl.principal(wallet1)],
      deployer,
    );
    expect(role.result).toBeOk(Cl.uint(ROLE_OPERATOR));

    const revoke = simnet.callPublicFn(
      CONTRACT,
      "revoke-role",
      [Cl.principal(wallet1)],
      deployer,
    );
    expect(revoke.result).toBeOk(Cl.bool(true));

    const roleCleared = simnet.callReadOnlyFn(
      CONTRACT,
      "get-user-role",
      [Cl.principal(wallet1)],
      deployer,
    );
    expect(roleCleared.result).toBeOk(Cl.uint(0));
  });

  it("creates a vault and accepts deposits", () => {
    const vaultId = createVault(5);
    const vault = simnet.callReadOnlyFn(CONTRACT, "get-vault", [Cl.uint(vaultId)], deployer);
    expect(vault.result).toBeOk(
      Cl.tuple({
        "total-deposit": Cl.uint(0),
        "total-yield": Cl.uint(0),
        "lock-period": Cl.uint(5),
        "vault-type": Cl.uint(VAULT_LOW),
      }),
    );

    const depositAmount = 100_000;
    const deposit = simnet.callPublicFn(
      CONTRACT,
      "deposit",
      [Cl.uint(vaultId), Cl.uint(depositAmount)],
      wallet1,
    );
    expect(deposit.result).toBeOk(Cl.bool(true));

    const depositInfo = simnet.callReadOnlyFn(
      CONTRACT,
      "get-deposit",
      [Cl.principal(wallet1), Cl.uint(vaultId)],
      deployer,
    );
    const depositTuple = unwrapOkTuple(depositInfo.result);
    expect(depositTuple.amount).toBeUint(depositAmount);
    expect(depositTuple.claimed).toBeBool(false);
    expect(depositTuple["deposit-block"]).toHaveClarityType(ClarityType.UInt);
  });

  it("rejects invalid or paused deposits", () => {
    const vaultId = createVault(3);
    const invalidDeposit = simnet.callPublicFn(
      CONTRACT,
      "deposit",
      [Cl.uint(vaultId), Cl.uint(0)],
      wallet1,
    );
    expect(invalidDeposit.result).toBeErr(Cl.uint(ERR_INVALID_AMOUNT));

    const pause = simnet.callPublicFn(
      CONTRACT,
      "set-contract-paused",
      [Cl.bool(true)],
      deployer,
    );
    expect(pause.result).toBeOk(Cl.bool(true));

    const pausedDeposit = simnet.callPublicFn(
      CONTRACT,
      "deposit",
      [Cl.uint(vaultId), Cl.uint(10_000)],
      wallet1,
    );
    expect(pausedDeposit.result).toBeErr(Cl.uint(ERR_CONTRACT_PAUSED));
  });

  it("prevents early withdrawals", () => {
    const vaultId = createVault(5);
    const deposit = simnet.callPublicFn(
      CONTRACT,
      "deposit",
      [Cl.uint(vaultId), Cl.uint(100_000)],
      wallet1,
    );
    expect(deposit.result).toBeOk(Cl.bool(true));

    const withdraw = simnet.callPublicFn(CONTRACT, "withdraw", [Cl.uint(vaultId)], wallet1);
    expect(withdraw.result).toBeErr(Cl.uint(ERR_LOCKED));
  });

  it("queues and processes withdrawals when funded", () => {
    const vaultId = createVault(1);
    const depositAmount = 100_000;

    const setReserveRatio = simnet.callPublicFn(
      CONTRACT,
      "set-emergency-reserve-ratio",
      [Cl.uint(0)],
      deployer,
    );
    expect(setReserveRatio.result).toBeOk(Cl.bool(true));

    const deposit = simnet.callPublicFn(
      CONTRACT,
      "deposit",
      [Cl.uint(vaultId), Cl.uint(depositAmount)],
      wallet1,
    );
    expect(deposit.result).toBeOk(Cl.bool(true));

    simnet.mineEmptyBlocks(2);

    const withdraw = simnet.callPublicFn(CONTRACT, "withdraw", [Cl.uint(vaultId)], wallet1);
    expect(withdraw.result).toBeOk(Cl.bool(true));

    const queued = simnet.callReadOnlyFn(
      CONTRACT,
      "get-queued-withdrawal",
      [Cl.principal(wallet1), Cl.uint(vaultId)],
      deployer,
    );
    const yieldAmount = 2_000;
    const queuedTuple = unwrapOkTuple(queued.result);
    expect(queuedTuple.amount).toBeUint(depositAmount);
    expect(queuedTuple.total).toBeUint(depositAmount + yieldAmount);
    expect(queuedTuple["yield"]).toBeUint(yieldAmount);

    const statusQueued = simnet.callReadOnlyFn(CONTRACT, "get-fund-status", [], deployer);
    const statusQueuedTuple = unwrapOkTuple(statusQueued.result);
    expect(statusQueuedTuple["withdrawal-queue-count"]).toBeUint(1);
    const fund = simnet.callPublicFn(
      CONTRACT,
      "fund-contract",
      [Cl.uint(yieldAmount)],
      deployer,
    );
    expect(fund.result).toBeOk(Cl.bool(true));

    const process = simnet.callPublicFn(
      CONTRACT,
      "process-withdrawal-queue",
      [Cl.principal(wallet1), Cl.uint(vaultId)],
      deployer,
    );
    expect(process.result).toBeOk(Cl.bool(true));

    const queuedCleared = simnet.callReadOnlyFn(
      CONTRACT,
      "get-queued-withdrawal",
      [Cl.principal(wallet1), Cl.uint(vaultId)],
      deployer,
    );
    expect(queuedCleared.result).toBeErr(Cl.uint(ERR_VAULT_NOT_FOUND));

    const statusCleared = simnet.callReadOnlyFn(CONTRACT, "get-fund-status", [], deployer);
    const statusClearedTuple = unwrapOkTuple(statusCleared.result);
    expect(statusClearedTuple["withdrawal-queue-count"]).toBeUint(0);
  });

  it("supports immediate withdrawals when fully funded", () => {
    const vaultId = createVault(1);
    const depositAmount = 100_000;
    const yieldAmount = 2_000;

    const setReserveRatio = simnet.callPublicFn(
      CONTRACT,
      "set-emergency-reserve-ratio",
      [Cl.uint(0)],
      deployer,
    );
    expect(setReserveRatio.result).toBeOk(Cl.bool(true));

    const deposit = simnet.callPublicFn(
      CONTRACT,
      "deposit",
      [Cl.uint(vaultId), Cl.uint(depositAmount)],
      wallet1,
    );
    expect(deposit.result).toBeOk(Cl.bool(true));

    const fund = simnet.callPublicFn(
      CONTRACT,
      "fund-contract",
      [Cl.uint(yieldAmount)],
      deployer,
    );
    expect(fund.result).toBeOk(Cl.bool(true));

    simnet.mineEmptyBlocks(2);

    const withdraw = simnet.callPublicFn(CONTRACT, "withdraw", [Cl.uint(vaultId)], wallet1);
    expect(withdraw.result).toBeOk(Cl.bool(true));

    const depositInfo = simnet.callReadOnlyFn(
      CONTRACT,
      "get-deposit",
      [Cl.principal(wallet1), Cl.uint(vaultId)],
      deployer,
    );
    expect(depositInfo.result).toBeErr(Cl.uint(ERR_INSUFFICIENT_BALANCE));
  });
});
