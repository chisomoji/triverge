# Triverge Vault Contract

This Clarity smart contract implements a risk-based vault system for the Stacks blockchain, allowing users to deposit STX tokens into vaults with different risk profiles and earn yield after a lock period.

---

## Features

- **Vault Creation:** Admin can create vaults with specified risk type and lock period.
- **Deposits:** Users can deposit STX into a vault (one deposit per user per vault).
- **Withdrawals:** Users can withdraw their deposit plus yield after the lock period.
- **Yield Calculation:** Yield rates depend on vault risk type (2%, 5%, or 10%).
- **Admin Controls:** Admin can rebalance vault yields and change admin address.
- **Read-Only Queries:** Functions to get vault details, user deposits, admin address, vault counter, withdrawal eligibility, expected yield, and vault type name.

---

## Vault Types & Yield Rates

| Type   | Constant      | Yield Rate |
|--------|---------------|------------|
| LOW    | `VAULT_LOW`   | 2%         |
| MEDIUM | `VAULT_MEDIUM`| 5%         |
| HIGH   | `VAULT_HIGH`  | 10%        |

---

## Usage

### 1. Create a Vault (Admin Only)
```clarity
(create-vault vault-type lock-period)
```
- `vault-type`: `u1` (LOW), `u2` (MEDIUM), `u3` (HIGH)
- `lock-period`: Number of blocks funds are locked

### 2. Deposit STX
```clarity
(deposit vault-id amount)
```
- `vault-id`: Vault identifier
- `amount`: Amount of STX to deposit

### 3. Withdraw Funds
```clarity
(withdraw vault-id)
```
- Withdraws deposit plus yield after lock period

### 4. Rebalance Vault Yield (Admin Only)
```clarity
(rebalance-yields vault-id additional-yield)
```
- Adds additional yield to a vault

### 5. Change Admin (Admin Only)
```clarity
(change-admin new-admin)
```
- Sets a new admin principal

---

## Read-Only Functions

- **Get Vault Details:**  
  `(get-vault vault-id)`

- **Get User Deposit:**  
  `(get-deposit user vault-id)`

- **Get Admin Address:**  
  `(get-admin)`

- **Get Vault Counter:**  
  `(get-vault-counter)`

- **Check Withdrawal Eligibility:**  
  `(can-withdraw user vault-id)`

- **Get Expected Yield:**  
  `(get-expected-yield vault-id amount)`

- **Get Vault Type Name:**  
  `(get-vault-type-name vault-type)`

---

## Error Codes

| Code | Meaning                   |
|------|---------------------------|
| 100  | Unauthorized              |
| 101  | Vault not found           |
| 102  | Insufficient balance      |
| 103  | Locked (cannot withdraw)  |
| 104  | Invalid vault             |
| 105  | Invalid amount            |
| 106  | Transfer failed           |
| 107  | Already deposited         |

---

## Notes

- Only one deposit per user per vault is allowed.
- Withdrawals are only possible after the lock period.
- Admin is set to the contract deployer by default.

---

## License

MIT License (or specify your own)
